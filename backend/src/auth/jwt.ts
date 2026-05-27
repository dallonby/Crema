import { SignJWT, jwtVerify } from "jose";

const secret = new TextEncoder().encode(
  process.env.JWT_SECRET ?? "dev-secret-change-me"
);
const ISSUER = "crema-backend";
const AUDIENCE = "crema-app";
const SESSION_DURATION = "365d";  // long-lived; client re-auths if rejected

export interface Session {
  userId: string;
  exp: number;
}

/** Issue a session JWT for a verified user. */
export async function issueSessionToken(userId: string): Promise<string> {
  return await new SignJWT({ sub: userId })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuer(ISSUER)
    .setAudience(AUDIENCE)
    .setIssuedAt()
    .setExpirationTime(SESSION_DURATION)
    .sign(secret);
}

/** Verify and decode a session token. Throws if invalid/expired. */
export async function verifySessionToken(token: string): Promise<Session> {
  const { payload } = await jwtVerify(token, secret, {
    issuer: ISSUER,
    audience: AUDIENCE,
  });
  if (!payload.sub || typeof payload.exp !== "number") {
    throw new Error("invalid session token");
  }
  return { userId: payload.sub, exp: payload.exp };
}
