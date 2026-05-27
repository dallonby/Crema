import { createRemoteJWKSet, jwtVerify } from "jose";

/**
 * Verify a Google ID token (JWT) issued during a Sign-In-with-Google flow.
 *
 * Both the iOS Google SDK and the Android Google SDK return ID tokens with
 * the same shape — verifying them server-side means iOS and Android share
 * identity rows in our `users` table by Google `sub`.
 *
 * Google publishes its signing keys at the standard OIDC discovery URL.
 * Issuer must be `accounts.google.com` or `https://accounts.google.com`
 * (Google emits both interchangeably — we accept either).
 *
 * Audience must match one of the configured client IDs. Mobile apps and
 * web have separate client IDs; we accept any of them so a single
 * deployment can serve multiple platforms.
 */
const GOOGLE_JWKS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/oauth2/v3/certs"),
  { cacheMaxAge: 60 * 60 * 1000 }
);

export interface GoogleIdentity {
  sub: string;           // stable Google account id
  email?: string;
  emailVerified?: boolean;
  name?: string;         // optional friendly display name
  picture?: string;      // avatar URL (Google CDN)
}

export async function verifyGoogleIdToken(
  idToken: string,
  audiences: string[],   // platform client ids that are allowed
): Promise<GoogleIdentity> {
  const { payload } = await jwtVerify(idToken, GOOGLE_JWKS, {
    issuer: ["accounts.google.com", "https://accounts.google.com"],
    audience: audiences,
  });
  const sub = payload.sub;
  if (!sub) throw new Error("google token missing sub");
  return {
    sub,
    email: typeof payload.email === "string" ? payload.email : undefined,
    emailVerified: payload.email_verified === true,
    name: typeof payload.name === "string" ? payload.name : undefined,
    picture: typeof payload.picture === "string" ? payload.picture : undefined,
  };
}
