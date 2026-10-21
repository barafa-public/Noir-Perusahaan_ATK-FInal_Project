import { createClient } from "npm:@supabase/supabase-js@2";
import { jwtVerify, SignJWT } from "npm:jose@5";
import { errorResponse } from "./cors.ts";

export type Role = "internal";

export interface AuthUser {
  id: string;
  username: string;
  full_name: string;
  role: Role;
}

// Klien service role: melewati RLS. JANGAN pernah dikirim ke aplikasi.
export const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

const TOKEN_TTL_SECONDS = 7 * 24 * 60 * 60; // 7 hari

function secretKey(): Uint8Array {
  const s = Deno.env.get("JWT_SECRET");
  if (!s || s.length < 32) {
    throw new Error("JWT_SECRET belum diatur (minimal 32 karakter)");
  }
  return new TextEncoder().encode(s);
}

export async function signToken(
  user: AuthUser,
): Promise<{ token: string; expiresAt: string }> {
  const exp = Math.floor(Date.now() / 1000) + TOKEN_TTL_SECONDS;
  const token = await new SignJWT({ role: user.role, username: user.username })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(user.id)
    .setIssuedAt()
    .setExpirationTime(exp)
    .sign(secretKey());
  return { token, expiresAt: new Date(exp * 1000).toISOString() };
}

/**
 * Memverifikasi header "Authorization: Bearer <token>".
 * Mengembalikan AuthUser, atau Response error (401/403) yang siap dikirim.
 * Role dibaca ulang dari database, bukan dari isi token.
 */
export async function authenticate(
  req: Request,
  allowedRoles?: Role[],
): Promise<AuthUser | Response> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!token) return errorResponse("Token tidak ada", 401, "NO_TOKEN");

  let userId: string;
  try {
    const { payload } = await jwtVerify(token, secretKey(), {
      algorithms: ["HS256"],
    });
    if (!payload.sub) throw new Error("no sub");
    userId = payload.sub;
  } catch {
    return errorResponse("Token tidak valid atau kedaluwarsa", 401, "BAD_TOKEN");
  }

  const { data, error } = await admin
    .from("users")
    .select("id, username, full_name, role, is_active")
    .eq("id", userId)
    .maybeSingle();

  if (error) return errorResponse("Gagal memeriksa akun", 500);
  if (!data || !data.is_active) {
    return errorResponse("Akun tidak aktif", 401, "INACTIVE");
  }

  const user: AuthUser = {
    id: data.id,
    username: data.username,
    full_name: data.full_name,
    role: data.role as Role,
  };

  if (allowedRoles && !allowedRoles.includes(user.role)) {
    return errorResponse("Akses ditolak untuk role ini", 403, "FORBIDDEN");
  }
  return user;
}

export function isResponse(v: unknown): v is Response {
  return v instanceof Response;
}