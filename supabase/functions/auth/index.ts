import bcrypt from "npm:bcryptjs@2.4.3";
import { corsHeaders, errorResponse, json } from "../_shared/cors.ts";
import {
  admin,
  authenticate,
  type AuthUser,
  isResponse,
  signToken,
} from "../_shared/auth.ts";

const BCRYPT_COST = 10;
const USERNAME_RE = /^[a-z0-9_]{3,20}$/;

// Hash dummy dihitung sekali saat pertama dibutuhkan (bukan saat boot),
// supaya waktu respons login tidak membocorkan apakah username ada.
let dummyHash: string | null = null;
async function getDummyHash(): Promise<string> {
  dummyHash ??= await bcrypt.hash("dummy-password", BCRYPT_COST);
  return dummyHash;
}

async function readBody(req: Request): Promise<Record<string, unknown> | null> {
  try {
    const b = await req.json();
    return b && typeof b === "object" ? b : null;
  } catch {
    return null;
  }
}

async function session(user: AuthUser, status = 200): Promise<Response> {
  const { token, expiresAt } = await signToken(user);
  return json({ token, expires_at: expiresAt, user }, status);
}

// POST /auth/register  { username, password, full_name }
async function register(req: Request): Promise<Response> {
  const body = await readBody(req);
  if (!body) return errorResponse("Body harus berupa JSON", 400);

  const username = String(body.username ?? "").trim().toLowerCase();
  const password = String(body.password ?? "");
  const fullName = String(body.full_name ?? "").trim();

  if (!USERNAME_RE.test(username)) {
    return errorResponse(
      "Username 3-20 karakter: huruf kecil, angka, atau underscore",
      422,
      "INVALID_USERNAME",
    );
  }
  if (password.length < 8 || password.length > 72) {
    return errorResponse("Password 8-72 karakter", 422, "INVALID_PASSWORD");
  }
  if (fullName.length < 2 || fullName.length > 50) {
    return errorResponse("Nama lengkap 2-50 karakter", 422, "INVALID_NAME");
  }

  const passwordHash = await bcrypt.hash(password, BCRYPT_COST);

  // Role dipaksa 'customer'. Akun internal hanya dari seed.
  const { data, error } = await admin
    .from("users")
    .insert({
      username,
      password_hash: passwordHash,
      full_name: fullName,
      role: "customer",
    })
    .select("id, username, full_name, role")
    .single();

  if (error) {
    if (error.code === "23505") {
      return errorResponse("Username sudah dipakai", 409, "USERNAME_TAKEN");
    }
    console.error("register error", error);
    return errorResponse("Gagal registrasi", 500);
  }

  return session(data as AuthUser, 201);
}

// POST /auth/login  { username, password }
async function login(req: Request): Promise<Response> {
  const body = await readBody(req);
  if (!body) return errorResponse("Body harus berupa JSON", 400);

  const username = String(body.username ?? "").trim().toLowerCase();
  const password = String(body.password ?? "");
  if (!username || !password) {
    return errorResponse("Username dan password wajib diisi", 422);
  }

  const { data, error } = await admin
    .from("users")
    .select("id, username, full_name, role, password_hash, is_active")
    .eq("username", username)
    .maybeSingle();

  if (error) {
    console.error("login error", error);
    return errorResponse("Gagal login", 500);
  }

  const ok = await bcrypt.compare(
    password,
    data?.password_hash ?? (await getDummyHash()),
  );
  if (!data || !ok) {
    return errorResponse("Username atau password salah", 401, "BAD_CREDENTIALS");
  }
  if (!data.is_active) {
    return errorResponse("Akun dinonaktifkan", 403, "INACTIVE");
  }

  return session({
    id: data.id,
    username: data.username,
    full_name: data.full_name,
    role: data.role,
  });
}

// GET /auth/me  (Authorization: Bearer <token>)
async function me(req: Request): Promise<Response> {
  const user = await authenticate(req);
  if (isResponse(user)) return user;
  return json({ user });
}

// GET /auth/internal-check  (hanya role internal; endpoint uji pembatasan akses)
async function internalCheck(req: Request): Promise<Response> {
  const user = await authenticate(req, ["internal"]);
  if (isResponse(user)) return user;
  return json({ ok: true, user });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const action = new URL(req.url).pathname.split("/").filter(Boolean).pop();

  try {
    if (req.method === "POST" && action === "register") return await register(req);
    if (req.method === "POST" && action === "login") return await login(req);
    if (req.method === "GET" && action === "me") return await me(req);
    if (req.method === "GET" && action === "internal-check") {
      return await internalCheck(req);
    }
    return errorResponse("Endpoint tidak ditemukan", 404);
  } catch (e) {
    console.error("auth fatal", e);
    return errorResponse("Kesalahan server", 500);
  }
});