import { corsHeaders, errorResponse, json } from "../_shared/cors.ts";
import { admin, authenticate, isResponse } from "../_shared/auth.ts";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SALE_COLS =
  "id, product_id, product_name, unit_price, qty, total, cashier_id, sold_at, created_at";
const MAX_QTY = 10_000;
const MAX_FUTURE_MS = 24 * 60 * 60 * 1000; // toleransi jam perangkat
const MAX_LIMIT = 500;

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

// POST /sales  { id, product_id, qty, sold_at }
// Hanya role internal. Kasir diambil dari token; harga dari tabel produk.
// Idempoten: id yang sudah ada dikembalikan apa adanya (stok tidak berkurang lagi),
// jadi klien boleh mengirim ulang kapan saja.
async function record(req: Request): Promise<Response> {
  const user = await authenticate(req, ["internal"]);
  if (isResponse(user)) return user;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return errorResponse("Body harus berupa JSON", 400);
  }

  const id = String(body.id ?? "");
  const productId = String(body.product_id ?? "");
  const qty = Number(body.qty);
  const soldAt = new Date(String(body.sold_at ?? ""));

  if (!UUID_RE.test(id)) {
    return errorResponse("id penjualan tidak valid", 422, "INVALID_ID");
  }
  if (!UUID_RE.test(productId)) {
    return errorResponse("product_id tidak valid", 422, "INVALID_PRODUCT");
  }
  if (!Number.isInteger(qty) || qty <= 0 || qty > MAX_QTY) {
    return errorResponse("Jumlah tidak valid", 422, "INVALID_QTY");
  }
  if (
    Number.isNaN(soldAt.getTime()) ||
    soldAt.getTime() > Date.now() + MAX_FUTURE_MS
  ) {
    return errorResponse("Waktu penjualan tidak valid", 422, "INVALID_SOLD_AT");
  }

  const { data, error } = await admin.rpc("record_sale", {
    p_id: id,
    p_product_id: productId,
    p_qty: qty,
    p_cashier_id: user.id,
    p_sold_at: soldAt.toISOString(),
  });

  if (error) {
    const msg = error.message ?? "";
    if (msg.startsWith("INSUFFICIENT_STOCK")) {
      const name = msg.slice("INSUFFICIENT_STOCK:".length).trim();
      return errorResponse(
        `Stok tidak cukup${name ? `: ${name}` : ""}`,
        409,
        "INSUFFICIENT_STOCK",
      );
    }
    if (msg.startsWith("PRODUCT_NOT_FOUND")) {
      return errorResponse("Produk tidak ditemukan", 404, "PRODUCT_NOT_FOUND");
    }
    if (msg.startsWith("INVALID_QTY")) {
      return errorResponse("Jumlah tidak valid", 422, "INVALID_QTY");
    }
    console.error("record_sale error", error);
    return errorResponse("Gagal mencatat penjualan", 500);
  }

  return json({ sale: data }, 201);
}

// GET /sales?since=<ISO>&limit=<1-500>&offset=<0..>   (hanya internal)
// Penjualan semua perangkat, diurutkan menurut waktu DITERIMA server
// (created_at), bukan waktu transaksi: penjualan offline yang baru terkirim
// tetap ikut terambil oleh perangkat lain. Batas bawah memakai >=; klien
// memakai upsert sehingga baris ganda tidak masalah.
async function list(req: Request): Promise<Response> {
  const user = await authenticate(req, ["internal"]);
  if (isResponse(user)) return user;

  const params = new URL(req.url).searchParams;
  const limit = intParam(params.get("limit"), 1, MAX_LIMIT, MAX_LIMIT);
  const offset = intParam(params.get("offset"), 0, 10_000_000, 0);
  const sinceRaw = params.get("since");

  let q = admin.from("sales").select(SALE_COLS);
  if (sinceRaw) {
    const since = new Date(sinceRaw);
    if (Number.isNaN(since.getTime())) {
      return errorResponse("Parameter since tidak valid", 422, "INVALID_SINCE");
    }
    q = q.gte("created_at", since.toISOString());
  }

  const { data, error } = await q
    .order("created_at", { ascending: true })
    .order("id", { ascending: true })
    .range(offset, offset + limit - 1);

  if (error) {
    console.error("sales list error", error);
    return errorResponse("Gagal memuat penjualan", 500);
  }
  return json({ sales: data ?? [] });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method === "POST") return await record(req);
    if (req.method === "GET") return await list(req);
    return errorResponse("Metode tidak didukung", 405);
  } catch (e) {
    console.error("sales fatal", e);
    return errorResponse("Kesalahan server", 500);
  }
});