import { corsHeaders, errorResponse, json } from "../_shared/cors.ts";
import { admin, authenticate, isResponse } from "../_shared/auth.ts";

const MIN_LEN = 5;
const MAX_LEN = 500;

// POST /feedback  { rating: 1-5, impression: string, suggestion: string }
// Semua role yang sudah login boleh mengirim. user_id diambil dari token.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return errorResponse("Metode tidak didukung", 405);
    }

    const user = await authenticate(req);
    if (isResponse(user)) return user;

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return errorResponse("Body harus berupa JSON", 400);
    }

    const rating = Number(body.rating);
    const impression = String(body.impression ?? "").trim();
    const suggestion = String(body.suggestion ?? "").trim();

    if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
      return errorResponse("Penilaian harus 1 sampai 5", 422, "INVALID_RATING");
    }
    if (impression.length < MIN_LEN || impression.length > MAX_LEN) {
      return errorResponse(
        `Kesan ${MIN_LEN}-${MAX_LEN} karakter`,
        422,
        "INVALID_IMPRESSION",
      );
    }
    if (suggestion.length < MIN_LEN || suggestion.length > MAX_LEN) {
      return errorResponse(
        `Saran ${MIN_LEN}-${MAX_LEN} karakter`,
        422,
        "INVALID_SUGGESTION",
      );
    }

    const { data, error } = await admin
      .from("feedback")
      .insert({ user_id: user.id, impression, suggestion, rating })
      .select("id, created_at")
      .single();

    if (error) {
      console.error("feedback insert error", error);
      return errorResponse("Gagal menyimpan saran dan kesan", 500);
    }

    return json({ feedback: data }, 201);
  } catch (e) {
    console.error("feedback fatal", e);
    return errorResponse("Kesalahan server", 500);
  }
});