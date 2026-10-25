import { corsHeaders, errorResponse, json } from "../_shared/cors.ts";
import { admin, authenticate, isResponse } from "../_shared/auth.ts";

const COLUMNS =
  "id, sku, name, category, description, price, stock, min_stock, is_active, updated_at";
const MAX_LIMIT = 500;
const MAX_PRICE = 1_000_000_000;
const MAX_STOCK = 1_000_000;
const MAX_ADD = 10_000;
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SKU_RE = /^[A-Za-z0-9._-]{2,30}$/;

interface Fields {
  sku?: string;
  name?: string;
  category?: string;
  description?: string | null;
  price?: number;
  stock?: number;
  min_stock?: number;
}

function invalid(message: string, code: string): Response {
  return errorResponse(message, 422, code);
}

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

function readInt(v: unknown, max: number): number | null {
  if (v === null || v === undefined || typeof v === "boolean") return null;
  if (typeof v === "string" && v.trim() === "") return null;
  const n = Number(v);
  return Number.isInteger(n) && n >= 0 && n <= max ? n : null;
}

/**
 * Memvalidasi body. Saat membuat (isCreate) sku, name, category, price wajib;
 * saat mengubah, hanya field yang dikirim yang diperiksa dan diubah.
 */
function parseFields(
  body: Record<string, unknown>,
  isCreate: boolean,
): Fields | Response {
  const out: Fields = {};

  if (isCreate || body.sku !== undefined) {
    const sku = String(body.sku ?? "").trim().toUpperCase();
    if (!SKU_RE.test(sku)) {
      return invalid(
        "SKU 2-30 karakter: huruf, angka, titik, minus, atau underscore",
        "INVALID_SKU",
      );
    }
    out.sku = sku;
  }
  if (isCreate || body.name !== undefined) {
    const name = String(body.name ?? "").trim();
    if (name.length < 2 || name.length > 80) {
      return invalid("Nama produk 2-80 karakter", "INVALID_NAME");
    }
    out.name = name;
  }
  if (isCreate || body.category !== undefined) {
    const category = String(body.category ?? "").trim();
    if (category.length < 2 || category.length > 40) {
      return invalid("Kategori 2-40 karakter", "INVALID_CATEGORY");
    }
    out.category = category;
  }
  if (body.description !== undefined) {
    const d = String(body.description ?? "").trim();
    if (d.length > 300) {
      return invalid("Deskripsi maksimal 300 karakter", "INVALID_DESCRIPTION");
    }
    out.description = d === "" ? null : d;
  }
  if (isCreate || body.price !== undefined) {
    const price = readInt(body.price, MAX_PRICE);
    if (price === null) return invalid("Harga tidak valid", "INVALID_PRICE");
    out.price = price;
  }
  if (body.stock !== undefined) {
    const stock = readInt(body.stock, MAX_STOCK);
    if (stock === null) return invalid("Stok tidak valid", "INVALID_STOCK");
    out.stock = stock;
  }
  if (body.min_stock !== undefined) {
    const minStock = readInt(body.min_stock, MAX_STOCK);
    if (minStock === null) {
      return invalid("Stok minimum tidak valid", "INVALID_MIN_STOCK");
    }
    out.min_stock = minStock;
  }
  return out;
}

async function readBody(req: Request): Promise<Record<string, unknown> | null> {
  try {
    const b = await req.json();
    return b && typeof b === "object" && !Array.isArray(b) ? b : null;
  } catch {
    return null;
  }
}

// GET /products?since=<ISO>&limit=<1-500>&offset=<0..>
//  - tanpa since : hanya produk aktif (sinkronisasi penuh)
//  - dengan since: produk yang berubah sejak waktu itu, TERMASUK yang
//    nonaktif (is_active=false) supaya klien menghapusnya dari cache.
// Batas bawah memakai >= (bukan >) agar baris dengan updated_at yang sama
// tidak terlewat; klien memakai upsert sehingga baris ganda tidak masalah.
// Semua role yang sudah login boleh membaca.
async function list(req: Request): Promise<Response> {
  const user = await authenticate(req);
  if (isResponse(user)) return user;

  const params = new URL(req.url).searchParams;
  const limit = intParam(params.get("limit"), 1, MAX_LIMIT, MAX_LIMIT);
  const offset = intParam(params.get("offset"), 0, 1_000_000, 0);
  const sinceRaw = params.get("since");

  let q = admin.from("products").select(COLUMNS);
  if (sinceRaw) {
    const since = new Date(sinceRaw);
    if (Number.isNaN(since.getTime())) {
      return errorResponse("Parameter since tidak valid", 422, "INVALID_SINCE");
    }
    q = q.gte("updated_at", since.toISOString());
  } else {
    q = q.eq("is_active", true);
  }

  const { data, error } = await q
    .order("updated_at", { ascending: true })
    .order("id", { ascending: true })
    .range(offset, offset + limit - 1);

  if (error) {
    console.error("products list error", error);
    return errorResponse("Gagal memuat produk", 500);
  }
  return json({ products: data ?? [] });
}

// POST /products  { sku, name, category, price, [description, stock, min_stock] }
// Hanya role internal.
async function create(req: Request): Promise<Response> {
  const user = await authenticate(req, ["internal"]);
  if (isResponse(user)) return user;

  const body = await readBody(req);
  if (!body) return errorResponse("Body harus berupa JSON", 400);

  const fields = parseFields(body, true);
  if (fields instanceof Response) return fields;

  const { data, error } = await admin
    .from("products")
    .insert(fields)
    .select(COLUMNS)
    .single();

  if (error) {
    if (error.code === "23505") {
      return errorResponse("SKU sudah dipakai", 409, "SKU_TAKEN");
    }
    console.error("product insert error", error);
    return errorResponse("Gagal menambah produk", 500);
  }
  return json({ product: data }, 201);
}

// POST /products/<id>  { field yang diubah }
// Memakai POST (bukan PATCH) agar ApiClient di aplikasi tidak perlu diubah.
// Hanya role internal. Produk nonaktif tidak bisa diubah.
async function update(req: Request, id: string): Promise<Response> {
  const user = await authenticate(req, ["internal"]);
  if (isResponse(user)) return user;

  if (!UUID_RE.test(id)) {
    return errorResponse("Produk tidak ditemukan", 404, "PRODUCT_NOT_FOUND");
  }

  const body = await readBody(req);
  if (!body) return errorResponse("Body harus berupa JSON", 400);

  const fields = parseFields(body, false);
  if (fields instanceof Response) return fields;
  if (Object.keys(fields).length === 0) {
    return invalid("Tidak ada perubahan", "NO_CHANGES");
  }

  const { data, error } = await admin
    .from("products")
    .update(fields)
    .eq("id", id)
    .eq("is_active", true)
    .select(COLUMNS)
    .maybeSingle();

  if (error) {
    if (error.code === "23505") {
      return errorResponse("SKU sudah dipakai", 409, "SKU_TAKEN");
    }
    console.error("product update error", error);
    return errorResponse("Gagal menyimpan produk", 500);
  }
  if (!data) {
    return errorResponse("Produk tidak ditemukan", 404, "PRODUCT_NOT_FOUND");
  }
  return json({ product: data });
}

// POST /products/<id>/stock  { qty }
// Menjumlahkan stok secara atomik. Hanya role internal.
async function addStock(req: Request, id: string): Promise<Response> {
  const user = await authenticate(req, ["internal"]);
  if (isResponse(user)) return user;

  if (!UUID_RE.test(id)) {
    return errorResponse("Produk tidak ditemukan", 404, "PRODUCT_NOT_FOUND");
  }

  const body = await readBody(req);
  if (!body) return errorResponse("Body harus berupa JSON", 400);

  const qty = Number(body.qty);
  if (!Number.isInteger(qty) || qty <= 0 || qty > MAX_ADD) {
    return invalid("Jumlah tidak valid", "INVALID_QTY");
  }

  const { data, error } = await admin.rpc("adjust_stock", {
    p_product_id: id,
    p_delta: qty,
  });

  if (error) {
    const msg = error.message ?? "";
    if (msg.startsWith("PRODUCT_NOT_FOUND")) {
      return errorResponse("Produk tidak ditemukan", 404, "PRODUCT_NOT_FOUND");
    }
    if (msg.startsWith("STOCK_OUT_OF_RANGE")) {
      return invalid("Stok melebihi batas yang diizinkan", "STOCK_LIMIT");
    }
    if (msg.startsWith("INVALID_QTY")) {
      return invalid("Jumlah tidak valid", "INVALID_QTY");
    }
    console.error("adjust_stock error", error);
    return errorResponse("Gagal menambah stok", 500);
  }

  const row = data as Record<string, unknown>;
  const product: Record<string, unknown> = {};
  for (const k of COLUMNS.split(", ")) product[k] = row[k];
  return json({ product });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const segs = new URL(req.url).pathname.split("/").filter(Boolean);
    const at = segs.lastIndexOf("products");
        const id = at >= 0 ? segs[at + 1] : undefined;
    const sub = at >= 0 ? segs[at + 2] : undefined;

    if (req.method === "GET") return await list(req);
    if (req.method === "POST") {
      if (id && sub === "stock") return await addStock(req, id);
      return id ? await update(req, id) : await create(req);
    }
    return errorResponse("Metode tidak didukung", 405);
  } catch (e) {
    console.error("products fatal", e);
    return errorResponse("Kesalahan server", 500);
  }
});