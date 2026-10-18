import {createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT} from "npm:jose@6.1.3";

// This deployment requires asymmetric JWT signing keys (ES256/RS256).
// Never put service-role keys or a JWT signing secret in the iOS app.
const base = Deno.env.get("SUPABASE_URL");
const publicKey = Deno.env.get("SUPABASE_ANON_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const jwks = base ? createRemoteJWKSet(new URL(`${base}/auth/v1/.well-known/jwks.json`)) : null;
const appleOrigin = "https://appleid.apple.com";
const appleJWKS = createRemoteJWKSet(new URL(`${appleOrigin}/auth/keys`));
const headers = {"Content-Type": "application/json", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"};
const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), {status, headers});
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type DeleteInput = {apple_authorization_code?: string; apple_nonce?: string; apple_manual_revocation?: boolean};
class AppleFailure extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string) { super(code); this.status = status; this.code = code; }
}

async function inputFor(request: Request): Promise<DeleteInput | null> {
  // Codes and nonces are small. Bound streaming input before allocating/parsing it.
  const reader = request.body?.getReader();
  if (!reader) return {};
  let bytes = 0;
  const chunks: Uint8Array[] = [];
  while (true) {
    const {done, value} = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    if (bytes > 8192) { await reader.cancel(); return null; }
    chunks.push(value);
  }
  const data = new Uint8Array(bytes);
  let offset = 0;
  for (const chunk of chunks) {data.set(chunk, offset); offset += chunk.byteLength;}
  try {
    const text = new TextDecoder("utf-8", {fatal: true}).decode(data);
    const input = text ? JSON.parse(text) : {};
    if (!input || typeof input !== "object" || Array.isArray(input)) return null;
    if (Object.keys(input).some(key => !["apple_authorization_code", "apple_nonce", "apple_manual_revocation"].includes(key))) return null;
    if (input.apple_manual_revocation !== undefined && typeof input.apple_manual_revocation !== "boolean") return null;
    if (input.apple_authorization_code !== undefined && (typeof input.apple_authorization_code !== "string" || input.apple_authorization_code.length < 1 || input.apple_authorization_code.length > 2048)) return null;
    if (input.apple_nonce !== undefined && (typeof input.apple_nonce !== "string" || !/^[A-Za-z0-9._-]{32,256}$/.test(input.apple_nonce))) return null;
    if (Boolean(input.apple_authorization_code) !== Boolean(input.apple_nonce)) return null;
    if (input.apple_manual_revocation && input.apple_authorization_code) return null;
    return input;
  } catch { return null; }
}

async function revokeApple(input: DeleteInput, expectedSubjects: string[]): Promise<void> {
  const clientID = Deno.env.get("APPLE_CLIENT_ID");
  const teamID = Deno.env.get("APPLE_TEAM_ID");
  const keyID = Deno.env.get("APPLE_KEY_ID");
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY");
  if (!clientID || !teamID || !keyID || !privateKey) throw new AppleFailure(503, "apple_revocation_unavailable");
  if (!input.apple_authorization_code || !input.apple_nonce) throw new AppleFailure(409, "apple_reauthentication_required");
  // Mint a short-lived client secret server-side; the .p8 never enters the app.
  const secret = await new SignJWT({})
    .setProtectedHeader({alg: "ES256", kid: keyID})
    .setIssuer(teamID).setSubject(clientID).setAudience(appleOrigin)
    .setIssuedAt().setExpirationTime("5m")
    .sign(await importPKCS8(privateKey.replace(/\\n/g, "\n"), "ES256"));
  const exchange = await fetch(`${appleOrigin}/auth/token`, {
    method: "POST", headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: new URLSearchParams({client_id: clientID, client_secret: secret,
      code: input.apple_authorization_code, grant_type: "authorization_code"}),
    signal: AbortSignal.timeout(10000), redirect: "error",
  });
  if (exchange.status === 400) {
    // Only an unusable authorization grant can be fixed by asking the person
    // to authenticate again. Bad client credentials/configuration must not
    // create an endless series of Apple authorization prompts.
    let errorCode: unknown;
    try { errorCode = (await exchange.json())?.error; } catch { /* Treat malformed errors as unavailable. */ }
    if (errorCode === "invalid_grant") throw new AppleFailure(409, "apple_reauthentication_required");
    throw new AppleFailure(503, "apple_revocation_unavailable");
  }
  if (!exchange.ok) throw new AppleFailure(503, "apple_revocation_unavailable");
  const tokens = await exchange.json();
  if (typeof tokens.id_token !== "string" || typeof tokens.refresh_token !== "string" || !tokens.refresh_token) {
    throw new AppleFailure(503, "apple_revocation_unavailable");
  }
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input.apple_nonce));
  const expectedNonce = Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
  try {
    const {payload} = await jwtVerify(tokens.id_token, appleJWKS, {
      issuer: appleOrigin, audience: clientID, algorithms: ["RS256"],
      requiredClaims: ["exp", "iat", "sub", "nonce"], maxTokenAge: "10m", clockTolerance: 5,
    });
    if (!payload.sub || !expectedSubjects.includes(payload.sub) || payload.nonce !== expectedNonce) {
      throw new AppleFailure(403, "apple_identity_mismatch");
    }
  } catch (error) {
    if (error instanceof AppleFailure) throw error;
    const code = error instanceof Error && "code" in error ? error.code : undefined;
    const invalidIdentity = typeof code === "string" && ["ERR_JWT_CLAIM_VALIDATION_FAILED", "ERR_JWT_EXPIRED",
      "ERR_JWS_SIGNATURE_VERIFICATION_FAILED", "ERR_JWS_INVALID", "ERR_JWT_INVALID", "ERR_JOSE_ALG_NOT_ALLOWED"].includes(code);
    // An unavailable/rotating JWKS is a retryable service failure, not evidence
    // that the person picked another Apple account.
    throw new AppleFailure(invalidIdentity ? 403 : 503, invalidIdentity ? "apple_identity_mismatch" : "apple_revocation_unavailable");
  }
  const revocation = await fetch(`${appleOrigin}/auth/revoke`, {
    method: "POST", headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: new URLSearchParams({client_id: clientID, client_secret: secret,
      token: tokens.refresh_token, token_type_hint: "refresh_token"}),
    signal: AbortSignal.timeout(10000), redirect: "error",
  });
  if (revocation.status !== 200) throw new AppleFailure(503, "apple_revocation_unavailable");
  // All Apple tokens are discarded after this request, never stored or logged.
}

// Storage objects are deleted through the Storage API, never by deleting metadata
// rows in SQL. authorize_deletion has already stopped concurrent photo uploads.
async function removeProfilePhotos(subject: string, headers: Record<string,string>): Promise<void> {
  for (let batch = 0; batch < 20; batch++) {
    const listed = await fetch(`${base}/storage/v1/object/list/profile-photos`, {
      method: "POST", headers, body: JSON.stringify({prefix: `${subject}/`, limit: 1000, offset: 0}),
      signal: AbortSignal.timeout(10000), redirect: "error",
    });
    if (listed.status === 404) return; // Before the photo bucket exists, there is nothing to erase.
    if (!listed.ok) throw new Error("storage_cleanup_unavailable");
    const files = await listed.json();
    if (!Array.isArray(files)) throw new Error("storage_cleanup_unavailable");
    if (files.length === 0) return;
    if (files.some(file => !file || typeof file.name !== "string" || !/^[0-9a-f-]{36}\.jpg$/.test(file.name))) {
      throw new Error("storage_cleanup_unavailable");
    }
    const removed = await fetch(`${base}/storage/v1/object/profile-photos`, {
      method: "DELETE", headers, body: JSON.stringify({prefixes: files.map(file => `${subject}/${file.name}`)}),
      signal: AbortSignal.timeout(20000), redirect: "error",
    });
    if (!removed.ok) throw new Error("storage_cleanup_unavailable");
  }
  throw new Error("storage_cleanup_unavailable");
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return reply(405, {error: "method_not_allowed"});
  const authorization = request.headers.get("Authorization") ?? "";
  if (!/^Bearer [^\s]+$/.test(authorization)) return reply(401, {error: "sign_in_required"});
  if (!base || !publicKey || !serviceKey || !jwks) return reply(503, {error: "service_unavailable"});
  let subject: string;
  try {
    // Verification works for a just-deleted subject too: Auth getUser alone would
    // reject a lost-response retry even though its signed JWT is still valid.
    const {payload} = await jwtVerify(authorization.slice(7), jwks, {
      issuer: `${base}/auth/v1`, audience: "authenticated", algorithms: ["ES256", "RS256"],
      requiredClaims: ["exp", "sub", "session_id"],
    });
    if (!payload.sub || !uuid.test(payload.sub) || typeof payload.session_id !== "string" || !uuid.test(payload.session_id)) {
      return reply(401, {error: "identity_verification_failed"});
    }
    subject = payload.sub;
  } catch {
    // Expired credentials do not prove who is requesting deletion confirmation.
    // Keep pending state in the app; do not recreate a deleted account to retry.
    return reply(401, {error: "deletion_identity_expired_or_invalid"});
  }
  const userHeaders = {Authorization: authorization, apikey: publicKey, "Content-Type": "application/json"};
  const adminHeaders = {Authorization: `Bearer ${serviceKey}`, apikey: serviceKey, "Content-Type": "application/json"};
  const accountURL = `${base}/auth/v1/admin/users/${subject}`;
  try {
    const existing = await fetch(accountURL, {headers: adminHeaders, signal: AbortSignal.timeout(10000)});
    if (existing.status === 404) {
      await removeProfilePhotos(subject, adminHeaders);
      return reply(200, {deleted: true});
    }
    if (!existing.ok) return reply(503, {error: "identity_verification_unavailable"});
    const account = await existing.json();
    if (account.id !== subject || !Array.isArray(account.identities)) return reply(503, {error: "identity_verification_unavailable"});
    const appleIdentities = account.identities.filter((identity: {provider?: string}) => identity.provider === "apple");
    const input = await inputFor(request);
    if (!input) return reply(400, {error: "invalid_deletion_request"});
    const allowed = await fetch(`${base}/rest/v1/rpc/authorize_deletion`, {
      method: "POST", headers: userHeaders, body: "{}", signal: AbortSignal.timeout(10000),
    });
    if (!allowed.ok) return reply(allowed.status === 401 || allowed.status === 403 ? 401 : 429, {error: "deletion_not_authorized_retry_later"});
    let appleRevocation: "not_required" | "revoked" | "manual_required" = "not_required";
    if (appleIdentities.length > 0) {
      if (input.apple_manual_revocation) {
        // TN3194 requires account erasure even when Apple tokens are unavailable.
        // The native client explicitly offers this alternative and shows manual
        // revocation instructions after deletion, including lost-response retries.
        appleRevocation = "manual_required";
      } else {
        if (!input.apple_authorization_code) return reply(409, {error: "apple_reauthentication_required"});
        const subjects = appleIdentities.map((identity: {identity_data?: {sub?: string}}) => identity.identity_data?.sub)
          .filter((value: unknown): value is string => typeof value === "string" && value.length > 0);
        if (subjects.length !== appleIdentities.length) return reply(503, {error: "identity_verification_unavailable"});
        try { await revokeApple(input, subjects); }
        catch (error) {
          if (error instanceof AppleFailure) throw error;
          throw new AppleFailure(503, "apple_revocation_unavailable");
        }
        appleRevocation = "revoked";
      }
    } else if (input.apple_authorization_code || input.apple_manual_revocation) {
      return reply(400, {error: "apple_identity_not_linked"});
    }
    await removeProfilePhotos(subject, adminHeaders);
    // Hard deletion removes the Auth record and all FK-cascaded application data.
    const deletion = await fetch(accountURL, {
      method: "DELETE", headers: adminHeaders, body: JSON.stringify({should_soft_delete: false}), signal: AbortSignal.timeout(20000),
    });
    if (!deletion.ok && deletion.status !== 404) return reply(503, {error: "deletion_failed_retry"});
    const check = await fetch(accountURL, {headers: adminHeaders, signal: AbortSignal.timeout(10000)});
    if (check.status !== 404) return reply(503, {error: "deletion_confirmation_unavailable"});
    return reply(200, {deleted: true, apple_revocation: appleRevocation});
  } catch (error) {
    if (error instanceof AppleFailure) return reply(error.status, {error: error.code});
    // No access tokens, emails, request bodies, or upstream responses in logs.
    return reply(503, {error: "deletion_confirmation_unavailable"});
  }
});
