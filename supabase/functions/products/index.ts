import { corsHeaders, errorResponse, json } from "../_shared/cors.ts";
import { admin, authenticate, isResponse } from "../_shared/auth.ts";

const COLUMNS =
  "id, sku, name, category, description, price, stock, min_stock, is_active, updated_at";
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

// GET /products?since=<ISO>&limit=<1-500>&offset=<0..>
//  - tanpa since : hanya produk aktif (sinkronisasi penuh)
//  - dengan since: produk yang berubah sejak waktu itu, TERMASUK yang
//    nonaktif (is_active=false) supaya klien menghapusnya dari cache.
// Batas bawah memakai >= (bukan >) agar baris dengan updated_at yang sama
// tidak terlewat; klien memakai upsert sehingga baris ganda tidak masalah.
// Semua role yang sudah login boleh membaca.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "GET") {
      return errorResponse("Metode tidak didukung", 405);
    }

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
  } catch (e) {
    console.error("products fatal", e);
    return errorResponse("Kesalahan server", 500);
  }
});