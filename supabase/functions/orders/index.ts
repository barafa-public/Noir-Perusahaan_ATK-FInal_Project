import { corsHeaders, errorResponse, json } from "../_shared/cors.ts";
import { admin, type AuthUser, authenticate, isResponse } from "../_shared/auth.ts";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ORDER_COLS =
  "id, order_no, status, total, note, cancel_reason, created_at, updated_at";
// User internal juga melihat nama pemesan dan siapa yang memproses.
// Petunjuk !kolom wajib karena orders punya dua FK ke users.
const INTERNAL_EMBEDS =
  "customer:users!customer_id(full_name, username), processor:users!processed_by(full_name)";
const ITEM_COLS = "product_id, product_name, unit_price, qty, subtotal";
const STATUSES = ["Dipesan", "Diproses", "Selesai", "Dibatalkan"];
const ACTIONS = ["process", "complete", "cancel"];
const MAX_ITEMS = 50;
const MAX_QTY = 1000;
const MAX_NOTE = 200;

function intParam(
  raw: string | null,
  min: number,
  max: number,
  fallback: number,
): number {
  const n = Number(raw);
  if (raw === null || !Number.isInteger(n)) return fallback;
  return Math.min(Math.max(n, min), max);
}

function listColumns(user: AuthUser): string {
  return user.role === "internal"
    ? `${ORDER_COLS}, ${INTERNAL_EMBEDS}`
    : ORDER_COLS;
}

// Customer hanya bisa membaca pesanannya sendiri; internal membaca semua.
function fetchOne(id: string, user: AuthUser) {
  let q = admin
    .from("orders")
    .select(`${listColumns(user)}, order_items(${ITEM_COLS})`)
    .eq("id", id);
  if (user.role !== "internal") q = q.eq("customer_id", user.id);
  return q
    .order("product_name", { referencedTable: "order_items" })
    .maybeSingle();
}

// Menerjemahkan pesan exception fungsi SQL menjadi respons HTTP.
function rpcErrorResponse(message: string): Response | null {
  if (message.startsWith("INSUFFICIENT_STOCK")) {
    const name = message.slice("INSUFFICIENT_STOCK:".length).trim();
    return errorResponse(
      `Stok tidak cukup${name ? `: ${name}` : ""}`,
      409,
      "INSUFFICIENT_STOCK",
    );
  }
  if (message.startsWith("PRODUCT_NOT_FOUND")) {
    return errorResponse(
      "Ada produk yang sudah tidak tersedia.",
      404,
      "PRODUCT_NOT_FOUND",
    );
  }
  if (message.startsWith("ORDER_NOT_FOUND")) {
    return errorResponse("Pesanan tidak ditemukan", 404, "ORDER_NOT_FOUND");
  }
  if (message.startsWith("INVALID_STATUS")) {
    return errorResponse(
      "Status pesanan sudah berubah. Muat ulang halaman.",
      409,
      "INVALID_STATUS",
    );
  }
  if (message.startsWith("EMPTY_ORDER")) {
    return errorResponse("Pesanan kosong", 422, "EMPTY_ORDER");
  }
  if (message.startsWith("INVALID_QTY")) {
    return errorResponse("Jumlah tidak valid", 422, "INVALID_QTY");
  }
  return null;
}

// POST /orders  { items: [{ product_id, qty }], note? }   (hanya Customer)
// Harga SELALU diambil dari tabel produk oleh fungsi SQL create_order;
// harga dari klien tidak dipakai. Stok hanya dicek, belum dikurangi.
async function create(req: Request): Promise<Response> {
  const user = await authenticate(req, ["customer"]);
  if (isResponse(user)) return user;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return errorResponse("Body harus berupa JSON", 400);
  }

  const raw = body.items;
  if (!Array.isArray(raw) || raw.length === 0) {
    return errorResponse("Pesanan kosong", 422, "EMPTY_ORDER");
  }
  if (raw.length > MAX_ITEMS) {
    return errorResponse(
      `Maksimal ${MAX_ITEMS} produk per pesanan`,
      422,
      "TOO_MANY_ITEMS",
    );
  }

  // Produk yang sama digabung (tabel order_items unik per order+produk).
  const merged = new Map<string, number>();
  for (const it of raw) {
    if (!it || typeof it !== "object") {
      return errorResponse("Item pesanan tidak valid", 422, "INVALID_ITEM");
    }
    const row = it as Record<string, unknown>;
    const productId = String(row.product_id ?? "").toLowerCase();
    const qty = Number(row.qty);
    if (!UUID_RE.test(productId)) {
      return errorResponse("product_id tidak valid", 422, "INVALID_PRODUCT");
    }
    if (!Number.isInteger(qty) || qty <= 0) {
      return errorResponse("Jumlah tidak valid", 422, "INVALID_QTY");
    }
    merged.set(productId, (merged.get(productId) ?? 0) + qty);
  }
  for (const qty of merged.values()) {
    if (qty > MAX_QTY) {
      return errorResponse(`Maksimal ${MAX_QTY} per produk`, 422, "INVALID_QTY");
    }
  }

  const note = String(body.note ?? "").trim();
  if (note.length > MAX_NOTE) {
    return errorResponse(
      `Catatan maksimal ${MAX_NOTE} karakter`,
      422,
      "INVALID_NOTE",
    );
  }

  const items = [...merged].map(([product_id, qty]) => ({ product_id, qty }));

  const { data, error } = await admin.rpc("create_order", {
    p_customer_id: user.id,
    p_items: items,
    p_note: note === "" ? null : note,
  });

  if (error) {
    const mapped = rpcErrorResponse(error.message ?? "");
    if (mapped) return mapped;
    console.error("create_order error", error);
    return errorResponse("Gagal membuat pesanan", 500);
  }

  const full = await fetchOne((data as { id: string }).id, user);
  if (full.error || !full.data) {
    console.error("fetch created order error", full.error);
    return errorResponse("Pesanan dibuat, tetapi gagal dimuat", 500);
  }
  return json({ order: full.data }, 201);
}

// GET /orders?status=<Dipesan|Diproses|Selesai|Dibatalkan>&limit=<1-100>&offset=<0..>
//  - Customer: pesanan miliknya sendiri
//  - Internal: semua pesanan (dengan nama pemesan)
// Terbaru dulu.
async function list(req: Request): Promise<Response> {
  const user = await authenticate(req);
  if (isResponse(user)) return user;

  const params = new URL(req.url).searchParams;
  const limit = intParam(params.get("limit"), 1, 100, 50);
  const offset = intParam(params.get("offset"), 0, 100_000, 0);
  const status = params.get("status");
  if (status !== null && !STATUSES.includes(status)) {
    return errorResponse("Filter status tidak valid", 422, "INVALID_FILTER");
  }

  let q = admin.from("orders").select(listColumns(user));
  if (user.role !== "internal") q = q.eq("customer_id", user.id);
  if (status !== null) q = q.eq("status", status);

  const { data, error } = await q
    .order("created_at", { ascending: false })
    .range(offset, offset + limit - 1);

  if (error) {
    console.error("orders list error", error);
    return errorResponse("Gagal memuat pesanan", 500);
  }
  return json({ orders: data ?? [] });
}

// GET /orders/<id>   (detail + item)
async function getOne(req: Request, id: string): Promise<Response> {
  const user = await authenticate(req);
  if (isResponse(user)) return user;

  if (!UUID_RE.test(id)) {
    return errorResponse("Pesanan tidak ditemukan", 404, "ORDER_NOT_FOUND");
  }
  const { data, error } = await fetchOne(id, user);
  if (error) {
    console.error("order detail error", error);
    return errorResponse("Gagal memuat pesanan", 500);
  }
  if (!data) {
    return errorResponse("Pesanan tidak ditemukan", 404, "ORDER_NOT_FOUND");
  }
  return json({ order: data });
}

// POST /orders/<id>/process    Dipesan  -> Diproses (validasi + kurangi stok, atomik)
// POST /orders/<id>/complete   Diproses -> Selesai
// POST /orders/<id>/cancel     { reason }  Dipesan/Diproses -> Dibatalkan
//                              (stok dikembalikan hanya jika sebelumnya Diproses)
// Hanya role internal. Seluruh logika status dan stok ada di fungsi SQL
// (satu transaksi dengan penguncian baris), bukan di sini.
async function act(
  req: Request,
  id: string,
  action: string,
): Promise<Response> {
  const user = await authenticate(req, ["internal"]);
  if (isResponse(user)) return user;

  if (!UUID_RE.test(id)) {
    return errorResponse("Pesanan tidak ditemukan", 404, "ORDER_NOT_FOUND");
  }

  let error: { message?: string } | null = null;

  if (action === "process") {
    const res = await admin.rpc("process_order", {
      p_order_id: id,
      p_staff_id: user.id,
    });
    error = res.error;
  } else if (action === "complete") {
    const res = await admin.rpc("complete_order", { p_order_id: id });
    error = res.error;
  } else {
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      // body kosong: ditolak oleh validasi alasan di bawah
    }
    const reason = String(body.reason ?? "").trim();
    if (reason.length < 3 || reason.length > 200) {
      return errorResponse(
        "Alasan pembatalan 3-200 karakter",
        422,
        "INVALID_REASON",
      );
    }
    const res = await admin.rpc("cancel_order", {
      p_order_id: id,
      p_reason: reason,
    });
    error = res.error;
  }

  if (error) {
    const mapped = rpcErrorResponse(error.message ?? "");
    if (mapped) return mapped;
    console.error(`${action}_order error`, error);
    return errorResponse("Gagal memperbarui pesanan", 500);
  }

  const full = await fetchOne(id, user);
  if (full.error || !full.data) {
    console.error("fetch updated order error", full.error);
    return errorResponse("Pesanan diperbarui, tetapi gagal dimuat", 500);
  }
  return json({ order: full.data });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const segs = new URL(req.url).pathname.split("/").filter(Boolean);
    const at = segs.lastIndexOf("orders");
    const id = at >= 0 ? segs[at + 1] : undefined;
    const action = at >= 0 ? segs[at + 2] : undefined;

    if (req.method === "GET") {
      return id ? await getOne(req, id) : await list(req);
    }
    if (req.method === "POST") {
      if (!id) return await create(req);
      if (action && ACTIONS.includes(action)) return await act(req, id, action);
    }
    return errorResponse("Endpoint tidak ditemukan", 404);
  } catch (e) {
    console.error("orders fatal", e);
    return errorResponse("Kesalahan server", 500);
  }
});