import { corsHeaders, errorResponse, json } from "../_shared/cors.ts";
import { admin, authenticate, isResponse } from "../_shared/auth.ts";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_QTY = 10_000;
const MAX_FUTURE_MS = 24 * 60 * 60 * 1000; // toleransi jam perangkat

// POST /sales  { id, product_id, qty, sold_at }
// Hanya role internal. Kasir diambil dari token; harga dari tabel produk.
// Idempoten: id yang sudah ada dikembalikan apa adanya (stok tidak berkurang lagi),
// jadi klien boleh mengirim ulang kapan saja.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return errorResponse("Metode tidak didukung", 405);
    }

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
  } catch (e) {
    console.error("sales fatal", e);
    return errorResponse("Kesalahan server", 500);
  }
});