import { corsHeaders, errorResponse, json } from "../_shared/cors.ts";
import { admin, authenticate, isResponse } from "../_shared/auth.ts";

const COLS =
  "block_index, block_type, ref_id, payload, prev_hash, hash, created_at";
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

// GET /blocks?after=<block_index>&limit=<1-500>   (hanya internal)
// Blok dengan block_index > after, berurutan naik. after=-1 mulai dari genesis.
async function list(req: Request): Promise<Response> {
  const user = await authenticate(req, ["internal"]);
  if (isResponse(user)) return user;

  const params = new URL(req.url).searchParams;
  const after = intParam(params.get("after"), -1, Number.MAX_SAFE_INTEGER, -1);
  const limit = intParam(params.get("limit"), 1, MAX_LIMIT, MAX_LIMIT);

  const { data, error } = await admin
    .from("blocks")
    .select(COLS)
    .gt("block_index", after)
    .order("block_index", { ascending: true })
    .limit(limit);

  if (error) {
    console.error("blocks list error", error);
    return errorResponse("Gagal memuat blockchain", 500);
  }
  return json({ blocks: data ?? [] });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method === "GET") return await list(req);
    return errorResponse("Metode tidak didukung", 405);
  } catch (e) {
    console.error("blocks fatal", e);
    return errorResponse("Kesalahan server", 500);
  }
});