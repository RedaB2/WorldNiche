import test from "node:test";
import assert from "node:assert/strict";
import { createInvitationLookup } from "../worker/invitation-preview.mjs";

const token = "a".repeat(64);
const configuration = { serviceURL: "https://social.example.test", publicAPIKey: "sb_publishable_synthetic_key_for_tests_only" };
const jwt = role => `e30.${Buffer.from(JSON.stringify({ role })).toString("base64url")}.synthetic`;

test("lookup calls only the read-only metadata RPC with a public key and timeout", async () => {
  for (const publicAPIKey of [configuration.publicAPIKey, jwt("anon")]) {
    let calls = 0;
    const lookup = createInvitationLookup({ ...configuration, publicAPIKey }, async (url, options) => {
      calls++;
      assert.equal(String(url), "https://social.example.test/rest/v1/rpc/invitation_link_metadata");
      assert.equal(options.method, "POST");
      assert.equal(options.headers.apikey, publicAPIKey);
      assert.equal(options.headers.authorization, undefined);
      assert.deepEqual(JSON.parse(options.body), { p_token: token });
      assert.ok(options.signal instanceof AbortSignal);
      assert.equal(options.redirect, "error");
      return Response.json({ display_name: "Mira" });
    });
    assert.equal(await lookup(token), "Mira");
    assert.equal(await lookup("bad"), null);
    assert.equal(calls, 1);
  }
});

test("missing configuration, non-public keys and unsafe endpoints never make a request", async () => {
  for (const overrides of [{ serviceURL: undefined }, { serviceURL: "http://social.example.test" },
    { serviceURL: "https://user:pass@social.example.test" }, { serviceURL: "https://social.example.test/path" },
    { publicAPIKey: undefined }, { publicAPIKey: "sb_secret_never_use_for_previews" }, { publicAPIKey: jwt("service_role") }]) {
    const lookup = createInvitationLookup({ ...configuration, ...overrides }, () => { assert.fail("Unexpected network request"); });
    assert.equal(await lookup(token), null);
  }
});

test("backend failures, missing names and timeouts degrade without leaking errors", async () => {
  for (const fetcher of [async () => new Response("unavailable", { status: 503 }), async () => Response.json({}),
    async () => new Response("invalid JSON"), async () => { throw new Error("timeout"); }]) {
    assert.equal(await createInvitationLookup(configuration, fetcher)(token), null);
  }
});
