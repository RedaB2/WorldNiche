import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";
import { createHandler } from "../supabase/functions/quiz-reminders/sender.ts";

const key = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const pem = Buffer.from(await crypto.subtle.exportKey("pkcs8", key.privateKey)).toString("base64");
const config = { url: "https://database.example.test", service: "fixture", secret: "fixture-worker", team: "TEST", keyId: "TEST", pem };
const job = { installation: crypto.randomUUID(), lease: crypto.randomUUID(), day: "2026-11-25", token: "ab".repeat(32), sandbox: true };
const request = () => new Request("https://example.test", { method: "POST", headers: { "x-quiz-worker": config.secret } });

test("worker rejects missing scoped authorization before touching any provider", async () => {
  const handler = createHandler(config, () => assert.fail("unexpected network call"));
  assert.equal((await handler(new Request("https://example.test", { method: "POST" }))).status, 401);
  assert.equal((await handler(new Request("https://example.test"))).status, 405);
});

for (const [reply, expected] of [[200, "sent"], [410, "invalid"], [400, "invalid"], [403, "retry"], [429, "retry"], [503, "retry"]]) {
  test("Apple response " + reply + " produces " + expected, async () => {
    const completed = [];
    const handler = createHandler(config, async (url, init) => {
      if (url.endsWith("/claim_quiz_reminders")) return Response.json([job, { ...job, sandbox: false }]);
      if (url.endsWith("/quiz_reminder_is_due")) return Response.json(true);
      if (url.includes("push.apple.com")) {
        assert.ok(["https://api.push.apple.com/3/device/" + job.token, "https://api.sandbox.push.apple.com/3/device/" + job.token].includes(url));
        assert.equal(init.headers["apns-push-type"], "alert");
        assert.equal(init.headers["apns-topic"], "io.worldniche.app");
        assert.equal(init.headers["apns-expiration"], String(Date.parse("2026-11-26T00:00:00Z") / 1000));
        assert.equal(JSON.parse(init.body).quizDay, job.day);
        const [head, claims, sig] = init.headers.authorization.slice(7).split(".");
        assert.ok(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key.publicKey,
          Buffer.from(sig, "base64url"), Buffer.from(head + "." + claims)));
        return Response.json({ reason: reply === 410 ? "Unregistered" : "BadDeviceToken", timestamp: 86400000 }, { status: reply });
      }
      assert.ok(url.endsWith("/finish_quiz_reminder"));
      completed.push(JSON.parse(init.body));
      return new Response(null, { status: 204 });
    });
    const response = await handler(request());
    assert.equal(response.status, expected === "retry" ? 503 : 200);
    assert.equal(completed.length, 2);
    for (const item of completed) {
      assert.equal(item.p_status, expected);
      assert.equal(item.p_lease, job.lease);
      assert.equal(item.p_invalid_at, reply === 410 ? "1970-01-02T00:00:00.000Z" : null);
    }
  });
}
test("empty batch never contacts Apple", async () => {
  const handler = createHandler(config, async url => {
    assert.ok(url.endsWith("/claim_quiz_reminders"));
    return Response.json([]);
  });
  assert.deepEqual(await (await handler(request())).json(), { accepted: 0 });
});

test("signing environments and scheduled worker routing agree with the native configurations", async () => {
  const source = path => readFile(new URL(path, import.meta.url), "utf8");
  assert.match(await source("../../apps/ios/Config/WorldNiche.entitlements"), /<key>aps-environment<\/key>\s*<string>\$\(WORLDNICHE_PUSH_ENVIRONMENT\)<\/string>/);
  assert.match(await source("../../apps/ios/Config/Debug.xcconfig"), /WORLDNICHE_PUSH_ENVIRONMENT = development/);
  assert.match(await source("../../apps/ios/Config/Release.xcconfig"), /WORLDNICHE_PUSH_ENVIRONMENT = production/);
  assert.match(await source("../supabase/configure_quiz_reminders.sql"), /'x-quiz-worker',s.decrypted_secret/);
});

test("opt-out after batch claim suppresses the Apple request", async () => {
  const handler = createHandler(config, async url => {
    if (url.endsWith("/claim_quiz_reminders")) return Response.json([job]);
    assert.ok(url.endsWith("/quiz_reminder_is_due"));
    return Response.json(false);
  });
  assert.deepEqual(await (await handler(request())).json(), { accepted: 0, failed: 0 });
});
