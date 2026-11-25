type Config = Partial<Record<"url" | "service" | "secret" | "team" | "keyId" | "pem" | "sandboxKeyId" | "sandboxPem", string>>;
type Job = { installation: string; lease: string; day: string; token: string; sandbox: boolean };
type Fetch = (url: string, init: RequestInit) => Promise<Response>;

function base64url(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes)).replaceAll("=", "").replaceAll("+", "-").replaceAll("/", "_");
}

function providerAuthorization(config: Config) {
  const encoder = new TextEncoder();
  const encode = (value: unknown) => base64url(encoder.encode(JSON.stringify(value)));
  let cached: { token: string; issued: number } | undefined;
  return async () => {
    const issued = Math.floor(Date.now() / 1000);
    if (cached && issued >= cached.issued && issued - cached.issued < 3000) return cached.token;
    const pem = config.pem!.replaceAll("\\n", "\n").replace(/-----[^-]+-----|\s/g, "");
    const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(pem), c => c.charCodeAt(0)),
      { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
    const input = encode({ alg: "ES256", kid: config.keyId }) + "." + encode({ iss: config.team, iat: issued });
    const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(input));
    cached = { token: input + "." + base64url(new Uint8Array(signature)), issued };
    return cached.token;
  };
}

export function createHandler(config: Config, send: Fetch = fetch) {
  const authorize = providerAuthorization(config);
  const authorizeSandbox = config.sandboxKeyId && config.sandboxPem
    ? providerAuthorization({ ...config, keyId: config.sandboxKeyId, pem: config.sandboxPem })
    : authorize;
  async function rpc(name: string, body: unknown) {
    const response = await send(config.url + "/rest/v1/rpc/" + name, {
      method: "POST", headers: { apikey: config.service!, Authorization: "Bearer " + config.service, "Content-Type": "application/json" },
      body: JSON.stringify(body), signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw Error("Database operation failed");
    return response;
  }
  async function deliver(job: Job, bearer: string) {
    const host = job.sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    const expires = Date.parse(job.day + "T00:00:00Z") / 1000 + 86400;
    let status = "retry";
    let invalidAt: string | null = null;
    try {
      const result = await send("https://" + host + "/3/device/" + job.token, {
        method: "POST", headers: { authorization: "bearer " + bearer, "apns-topic": "io.worldniche.app",
          "apns-push-type": "alert", "apns-priority": "10", "apns-expiration": String(expires),
          "apns-collapse-id": "worldniche-daily-quiz" },
        body: JSON.stringify({ aps: { alert: { title: "Daily country quiz", body: "One clue, four countries. Make today’s guess." },
          sound: "default" }, quizDay: job.day }), signal: AbortSignal.timeout(6000),
      });
      if (result.ok) status = "sent";
      else {
        const error = await result.json();
        if (result.status === 410 && error.reason === "Unregistered" && Number.isFinite(error.timestamp)) {
          status = "invalid";
          invalidAt = new Date(error.timestamp).toISOString();
        } else if (result.status === 400 && ["BadDeviceToken", "DeviceTokenNotForTopic"].includes(error.reason)) {
          status = "invalid";
        }
      }
    } finally {
      await rpc("finish_quiz_reminder", { p_installation: job.installation, p_lease: job.lease, p_day: job.day,
        p_status: status, p_invalid_at: invalidAt });
    }
    return status;
  }
  return async (request: Request) => {
    if (request.method !== "POST") return new Response(null, { status: 405 });
    if (!config.secret || request.headers.get("x-quiz-worker") !== config.secret) return new Response(null, { status: 401 });
    if (!config.url || !config.service || !config.team || !config.keyId || !config.pem) return new Response(null, { status: 503 });
    try {
      const jobs: Job[] = await (await rpc("claim_quiz_reminders", {})).json();
      if (!jobs.length) return Response.json({ accepted: 0 });
      const productionToken = jobs.some(job => !job.sandbox) ? await authorize() : "";
      const sandboxToken = jobs.some(job => job.sandbox) ? await authorizeSandbox() : "";
      let accepted = 0;
      let failed = 0;
      for (let i = 0; i < jobs.length; i += 10) {
        const results = await Promise.allSettled(jobs.slice(i, i+10).map(job => deliver(job, job.sandbox ? sandboxToken : productionToken)));
        accepted += results.filter(r => r.status === "fulfilled" && r.value === "sent").length;
        failed += results.filter(r => r.status === "rejected" || r.value === "retry").length;
      }
      return Response.json({ accepted, failed }, { status: failed ? 503 : 200 });
    } catch { return new Response(null, { status: 503 }); }
  };
}
