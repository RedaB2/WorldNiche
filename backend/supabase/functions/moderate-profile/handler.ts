const providerURL = "https://api.openai.com/v1/moderations";
const model = "omni-moderation-latest";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const categories = ["sexual", "sexual/minors", "harassment", "harassment/threatening", "hate", "hate/threatening",
  "illicit", "illicit/violent", "self-harm", "self-harm/intent", "self-harm/instructions", "violence", "violence/graphic"];
// The provider does not classify image-only hate, harassment, illicit activity,
// or sexual/minors. Reports and human review remain necessary for those gaps.
const imageCategories = ["sexual", "self-harm", "self-harm/intent", "self-harm/instructions", "violence", "violence/graphic"];
const responseHeaders = {"Content-Type": "application/json", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"};
const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), {status, headers: responseHeaders});
const record = (value: unknown): value is Record<string, unknown> => Boolean(value) && typeof value === "object" && !Array.isArray(value);

export type Configuration = {
  supabaseURL?: string;
  publicKey?: string;
  serviceKey?: string;
  openaiKey?: string;
  workerSecret?: string;
};
type Claim = {user_id: string; kind: "name" | "photo"; revision: string; claim_token: string; text: string | null; photo_path: string | null};
type Outcome = "approve" | "review" | "retry";
type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

class UpstreamFailure extends Error {
  readonly status: number;
  readonly code?: string;
  constructor(status: number, code?: string) {super("upstream_unavailable"); this.status = status; this.code = code;}
}
class InvalidContent extends Error {}

async function boundedBytes(body: ReadableStream<Uint8Array> | null, limit: number): Promise<Uint8Array> {
  if (!body) return new Uint8Array();
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) {await reader.cancel(); throw new Error("body_too_large");}
      chunks.push(value);
    }
  } finally {reader.releaseLock();}
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {bytes.set(chunk, offset); offset += chunk.byteLength;}
  return bytes;
}

async function jsonBody(response: Response, limit = 32768): Promise<unknown> {
  const bytes = await boundedBytes(response.body, limit);
  return JSON.parse(new TextDecoder("utf-8", {fatal: true}).decode(bytes));
}

async function emptyInput(request: Request): Promise<boolean> {
  try {
    const bytes = await boundedBytes(request.body, 512);
    const input = bytes.length ? JSON.parse(new TextDecoder("utf-8", {fatal: true}).decode(bytes)) : {};
    return record(input) && Object.keys(input).length === 0;
  } catch {return false;}
}

async function sameSecret(supplied: string, expected: string): Promise<boolean> {
  if (supplied.length > 1024) return false;
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([supplied, expected].map(value => crypto.subtle.digest("SHA-256", encoder.encode(value))));
  const a = new Uint8Array(left), b = new Uint8Array(right);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

function claimFor(value: unknown): Claim | null {
  if (!record(value) || ![value.user_id, value.revision, value.claim_token].every(item => typeof item === "string" && uuid.test(item))) return null;
  if (value.kind !== "name" && value.kind !== "photo") return null;
  if (value.kind === "name" && (typeof value.text !== "string" || [...value.text].length < 1 || [...value.text].length > 32 || value.photo_path !== null)) return null;
  if (value.kind === "photo" && (value.text !== null || typeof value.photo_path !== "string" ||
    !new RegExp(`^${value.user_id}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.jpg$`).test(value.photo_path))) return null;
  return value as Claim;
}

function providerOutcome(value: unknown, kind: Claim["kind"]): Outcome {
  if (!record(value) || typeof value.id !== "string" || !value.id || typeof value.model !== "string" || !value.model.startsWith("omni-moderation-") ||
    !Array.isArray(value.results) || value.results.length !== 1) return "retry";
  const result = value.results[0];
  if (!record(result) || typeof result.flagged !== "boolean" || !record(result.categories) ||
    !record(result.category_scores) || !record(result.category_applied_input_types)) return "retry";
  for (const category of categories) {
    const score = result.category_scores[category], applied = result.category_applied_input_types[category];
    if (typeof result.categories[category] !== "boolean" || typeof score !== "number" || !Number.isFinite(score) || score < 0 || score > 1 ||
      !Array.isArray(applied) || applied.some(input => input !== "text" && input !== "image")) return "retry";
  }
  const expected = kind === "name" ? categories : imageCategories;
  const inputType = kind === "name" ? "text" : "image";
  if (expected.some(category => !(result.category_applied_input_types as Record<string, string[]>)[category].includes(inputType))) return "retry";
  if (result.flagged || Object.values(result.categories).some(flag => flag === true)) return "review";
  return "approve";
}

function dataURL(bytes: Uint8Array): string {
  // Bounded storage objects avoid unbounded arguments or allocations here.
  let binary = "";
  for (let start = 0; start < bytes.length; start += 8192) binary += String.fromCharCode(...bytes.subarray(start, start + 8192));
  return `data:image/jpeg;base64,${btoa(binary)}`;
}

export function createHandler(configuration: Configuration, fetcher: Fetch = fetch): (request: Request) => Promise<Response> {
  const {supabaseURL: base, publicKey, serviceKey, openaiKey, workerSecret} = configuration;
  const configured = Boolean(base && /^https:\/\/[a-z0-9]+\.supabase\.co$/.test(base) && publicKey && serviceKey && openaiKey);
  const adminHeaders = {Authorization: `Bearer ${serviceKey}`, apikey: serviceKey ?? "", "Content-Type": "application/json"};

  async function rpc(name: string, body: unknown, headers = adminHeaders): Promise<unknown> {
    const response = await fetcher(`${base}/rest/v1/rpc/${name}`, {
      method: "POST", headers, body: JSON.stringify(body), signal: AbortSignal.timeout(8000), redirect: "error",
    });
    const result = await jsonBody(response);
    if (!response.ok) throw new UpstreamFailure(response.status, record(result) && typeof result.code === "string" ? result.code : undefined);
    return result;
  }

  function parameters(claim: Claim) {
    return {p_user_id: claim.user_id, p_kind: claim.kind, p_revision: claim.revision, p_claim_token: claim.claim_token};
  }

  async function current(claim: Claim): Promise<boolean> {
    return await rpc("profile_check_is_current", parameters(claim)) === true;
  }

  async function imageInput(claim: Claim): Promise<string> {
    const response = await fetcher(`${base}/storage/v1/object/authenticated/profile-photos/${claim.photo_path}`, {
      headers: adminHeaders, signal: AbortSignal.timeout(8000), redirect: "error",
    });
    if (response.status === 404) {await response.body?.cancel(); throw new InvalidContent();}
    if (!response.ok) {await response.body?.cancel(); throw new UpstreamFailure(response.status);}
    const declaredLength = response.headers.get("content-length");
    if (response.headers.get("content-type")?.split(";")[0].trim().toLowerCase() !== "image/jpeg" ||
      (declaredLength !== null && (!/^\d+$/.test(declaredLength) || Number(declaredLength) > 300000))) {
      await response.body?.cancel(); throw new InvalidContent();
    }
    let bytes: Uint8Array;
    try {bytes = await boundedBytes(response.body, 300000);} catch (error) {
      if (error instanceof Error && error.message === "body_too_large") throw new InvalidContent();
      throw error;
    }
    if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[bytes.length - 2] !== 0xff || bytes[bytes.length - 1] !== 0xd9) throw new InvalidContent();
    return dataURL(bytes);
  }

  async function check(claim: Claim): Promise<{applied: boolean; outcome: Outcome | "stale"}> {
    let outcome: Outcome = "retry";
    try {
      if (!await current(claim)) return {applied: false, outcome: "stale"};
      const input = claim.kind === "name" ? [{type: "text", text: claim.text}] : [{type: "image_url", image_url: {url: await imageInput(claim)}}];
      // Consent can change while the photo is downloading. Check again at the
      // external disclosure boundary, then verify once more during publication.
      if (!await current(claim)) return {applied: false, outcome: "stale"};
      const response = await fetcher(providerURL, {
        method: "POST", headers: {Authorization: `Bearer ${openaiKey}`, "Content-Type": "application/json"},
        body: JSON.stringify({model, input}), signal: AbortSignal.timeout(20000), redirect: "error",
      });
      if (response.ok) outcome = providerOutcome(await jsonBody(response), claim.kind);
      else {
        await response.body?.cancel();
        // A rejected payload needs human inspection. Auth, limits, and service
        // errors remain retryable and can never publish unchecked content.
        outcome = response.status === 400 || response.status === 422 ? "review" : "retry";
      }
    } catch (error) {
      outcome = error instanceof InvalidContent ? "review" : "retry";
    }
    const finished = await rpc("finish_profile_check", {...parameters(claim), p_outcome: outcome});
    if (!record(finished) || typeof finished.applied !== "boolean") throw new UpstreamFailure(503);
    return {applied: finished.applied, outcome};
  }

  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return reply(405, {error: "method_not_allowed"});
    const suppliedWorkerSecret = request.headers.get("x-worldniche-worker-secret");
    const authorization = request.headers.get("Authorization") ?? "";
    let worker = false;
    if (suppliedWorkerSecret !== null) {
      if (!workerSecret || workerSecret.length < 32 || !await sameSecret(suppliedWorkerSecret, workerSecret)) return reply(401, {error: "worker_not_authorized"});
      worker = true;
    } else if (authorization.length > 8192 || !/^Bearer [^\s]+$/.test(authorization)) return reply(401, {error: "sign_in_required"});
    if (!configured) return reply(503, {error: "moderation_unavailable"});
    if (!await emptyInput(request)) return reply(400, {error: "invalid_moderation_request"});
    const userHeaders = {Authorization: authorization, apikey: publicKey ?? "", "Content-Type": "application/json"};
    let userID: string | null = null;
    try {
      if (!worker) {
        // PostgREST verifies this JWT, then the RPC checks that the Auth session
        // still exists and consumes the per-user request allowance.
        const allowed = await rpc("authorize_profile_check", {}, userHeaders);
        if (!record(allowed) || typeof allowed.user_id !== "string" || !uuid.test(allowed.user_id)) return reply(503, {error: "identity_verification_unavailable"});
        userID = allowed.user_id;
      }
      const claimed = await rpc("claim_profile_checks", {p_user_id: userID, p_limit: worker ? 8 : 2});
      if (!Array.isArray(claimed) || claimed.length > (worker ? 8 : 2)) throw new UpstreamFailure(503);
      const claims = claimed.map(claimFor);
      if (claims.some(claim => !claim || (userID !== null && claim.user_id !== userID))) throw new UpstreamFailure(503);
      // Every claim has a durable lease. A timeout or crash leaves work available
      // for the scheduled retry instead of silently approving or losing it.
      const results = await Promise.allSettled((claims as Claim[]).map(check));
      if (worker) return reply(results.some(result => result.status === "rejected") ? 503 : 200, {
        processed: results.filter(result => result.status === "fulfilled" && result.value.applied).length,
      });
      const profile = await rpc("get_my_profile", {}, userHeaders);
      if (!record(profile) || profile.id !== userID) return reply(503, {error: "profile_unavailable"});
      return reply(200, profile);
    } catch (error) {
      if (!worker && error instanceof UpstreamFailure) {
        if (error.status === 401 || error.code === "28000" || error.code === "PGRST301" || error.code === "PGRST303") return reply(401, {error: "sign_in_required"});
        if (error.status === 403 || error.code === "42501") return reply(403, {error: "profile_unavailable"});
        if (error.status === 429 || error.code === "P0001") return reply(429, {error: "try_again_later"});
      }
      // No credentials, submitted content, or upstream error bodies are logged.
      return reply(503, {error: "moderation_unavailable"});
    }
  };
}
