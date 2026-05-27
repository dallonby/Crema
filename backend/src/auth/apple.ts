import { createRemoteJWKSet, jwtVerify } from "jose";

/**
 * Verify an Apple identity token (JWT) coming from a Sign-In-with-Apple
 * authorization response. Returns the verified Apple user id (`sub`) and
 * email if available.
 *
 * Apple's identity tokens are RS256-signed by keys published at
 * https://appleid.apple.com/auth/keys. We fetch + cache those keys via jose's
 * createRemoteJWKSet (handles rotation automatically).
 *
 * The `aud` claim must match our app's bundle id (the OAuth client id Apple
 * issued the token for). For first-party iOS Sign-in this is the app's
 * bundle id directly.
 */
const APPLE_JWKS = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys"),
  { cacheMaxAge: 60 * 60 * 1000 }
);

export interface AppleIdentity {
  sub: string;           // stable Apple user id (per-app)
  email?: string;
  emailVerified?: boolean;
}

export async function verifyAppleIdentityToken(
  identityToken: string,
  audience: string,
): Promise<AppleIdentity> {
  const { payload } = await jwtVerify(identityToken, APPLE_JWKS, {
    issuer: "https://appleid.apple.com",
    audience,
  });
  const sub = payload.sub;
  if (!sub) throw new Error("apple token missing sub");
  return {
    sub,
    email: typeof payload.email === "string" ? payload.email : undefined,
    emailVerified: payload.email_verified === true
      || payload.email_verified === "true",
  };
}
