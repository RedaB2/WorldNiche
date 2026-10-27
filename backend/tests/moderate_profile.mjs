// Runs the real Edge handler against isolated Auth, Storage, and provider fixtures.
// No network request or real profile content leaves this process.
import assert from "node:assert/strict";
import {test} from "node:test";
import {createHandler} from "../supabase/functions/moderate-profile/handler.ts";

const alice = "00000000-0000-0000-0000-000000000001";
const bob = "00000000-0000-0000-0000-000000000002";
const revision = "10000000-0000-0000-0000-000000000001";
const claimToken = "20000000-0000-0000-0000-000000000001";
const photo = `${alice}/30000000-0000-0000-0000-000000000001.jpg`;
const categoryNames = ["sexual", "sexual/minors", "harassment", "harassment/threatening", "hate", "hate/threatening", "illicit", "illicit/violent", "self-harm", "self-harm/intent", "self-harm/instructions", "violence", "violence/graphic"];
const visualCategories = ["sexual", "self-harm", "self-harm/intent", "self-harm/instructions", "violence", "violence/graphic"];
const config = {supabaseURL: "https://fixture.supabase.co", publicKey: "fixture-public-key", serviceKey: "fixture-service-key", openaiKey: "fixture-provider-key", workerSecret: "fixture-worker-secret-at-least-thirty-two-characters"};
const headers = {Authorization: "Bearer fixture-user-token", "Content-Type": "application/json"};
const json = (value, status = 200) => new Response(JSON.stringify(value), {status, headers: {"Content-Type": "application/json"}});
const nameClaim = (text = "Alice") => ({user_id: alice, kind: "name", revision, claim_token: claimToken, text, photo_path: null});
const photoClaim = () => ({user_id: alice, kind: "photo", revision, claim_token: claimToken, text: null, photo_path: photo});
const result = (kind = "name") => ({id: "modr-fixture", model: "omni-moderation-latest", results: [{
  flagged: false,
  categories: Object.fromEntries(categoryNames.map(category => [category, false])),
  category_scores: Object.fromEntries(categoryNames.map(category => [category, 0.001])),
  category_applied_input_types: Object.fromEntries(categoryNames.map(category => [category, kind === "name" ? ["text"] : visualCategories.includes(category) ? ["image"] : []])),
}]});

function fixture(overrides = {}, configuration = {}) {
  const state = {claims: [nameClaim()], profile: {id: alice, display_name: "Explorer", pending_display_name: "Alice", name_moderation_status: "pending"},
    authStatus: 200, authCode: null, authID: alice, current: true, applied: true, finishes: [], calls: [], providerBodies: [],
    providerStatus: 200, providerResponse: null, providerThrow: false, storageStatus: 200, image: new Uint8Array([0xff, 0xd8, 0xff, 0xd9]),
    imageType: "image/jpeg", imageLength: null, currentChecks: 0, finishStatus: 200,
    reservations: [], reservedClaims: new Set(), reservationStatus: 200, ...overrides};
  const fetcher = async (url, init) => {
    const body = init.body ? JSON.parse(init.body) : null;
    state.calls.push({url, body});
    assert.equal(init.redirect, "error", "Upstreams cannot redirect credentials or profile content");
    assert.ok(init.signal instanceof AbortSignal, "Every upstream has a deadline");
    if (url === "https://api.openai.com/v1/moderations") {
      assert.equal(init.headers.Authorization, `Bearer ${config.openaiKey}`);
      assert.equal(init.headers.apikey, undefined, "Supabase credentials never reach the provider");
      assert.equal(body.model, "omni-moderation-latest");
      assert.deepEqual(Object.keys(body).sort(), ["input", "model"]);
      state.providerBodies.push(body);
      if (state.providerThrow) throw new Error("fixture network failure");
      if (state.onProvider) state.onProvider();
      return state.providerResponse instanceof Response ? state.providerResponse : json(state.providerResponse ?? result(body.input[0].type === "text" ? "name" : "photo"), state.providerStatus);
    }
    assert.ok(url.startsWith("https://fixture.supabase.co/"), "Only fixed project and provider origins are contacted");
    assert.notEqual(init.headers.Authorization, `Bearer ${config.openaiKey}`);
    if (url.endsWith("/authorize_profile_check")) {
      assert.equal(init.headers.apikey, config.publicKey);
      assert.equal(init.headers.Authorization, "Bearer fixture-user-token");
      assert.deepEqual(body, {});
      return state.authStatus === 200 ? json({user_id: state.authID}) : json({code: state.authCode, message: "private upstream detail"}, state.authStatus);
    }
    if (url.endsWith("/get_my_profile")) {
      assert.equal(init.headers.apikey, config.publicKey);
      assert.equal(init.headers.Authorization, "Bearer fixture-user-token");
      return json(state.profile);
    }
    assert.equal(init.headers.apikey, config.serviceKey);
    assert.equal(init.headers.Authorization, `Bearer ${config.serviceKey}`);
    if (url.endsWith("/claim_profile_checks")) return json(state.claims);
    if (url.endsWith("/profile_check_is_current")) {
      state.currentChecks++;
      assert.equal(body.p_claim_token, claimToken);
      return json(state.currentUntil ? state.currentChecks < state.currentUntil : state.current);
    }
    if (url.endsWith("/reserve_profile_check")) {
      state.reservations.push(body);
      state.currentChecks++;
      assert.equal(body.p_claim_token, claimToken);
      if (state.reservationStatus !== 200) return json({code: "fixture_unavailable"}, state.reservationStatus);
      if ("reservationResponse" in state) return json(state.reservationResponse);
      if (!(state.currentUntil ? state.currentChecks < state.currentUntil : state.current)) return json({allowed: false, reason: "stale"});
      const key = `${body.p_user_id}/${body.p_kind}/${body.p_revision}/${body.p_claim_token}`;
      if (state.reservedClaims.has(key)) return json({allowed: false, reason: "reserved"});
      state.reservedClaims.add(key);
      return json({allowed: true, reason: "allowed"});
    }
    if (url.endsWith("/finish_profile_check")) {
      state.finishes.push(body);
      if (state.finishStatus !== 200) return json({code: "fixture_failure"}, state.finishStatus);
      if (state.applied && body.p_outcome === "approve") {
        state.profile.name_moderation_status = "approved";
        if (body.p_kind === "name") state.profile.display_name = state.claims.find(item => item.kind === "name").text;
        else state.profile.avatar_path = photo;
      }
      return json({applied: state.applied});
    }
    assert.equal(url, `https://fixture.supabase.co/storage/v1/object/authenticated/profile-photos/${photo}`);
    const imageHeaders = {"Content-Type": state.imageType};
    if (state.imageLength !== null) imageHeaders["Content-Length"] = state.imageLength;
    return new Response(state.image, {status: state.storageStatus, headers: imageHeaders});
  };
  const handler = createHandler({...config, ...configuration}, fetcher);
  const request = (options = {}) => handler(new Request("https://fixture.supabase.co/functions/v1/moderate-profile", {
    method: "POST", headers, body: "{}", ...options,
  }));
  return {state, request};
}

test("approved name returns fresh owner profile and publishes only the claimed revision", async () => {
  const {request, state} = fixture();
  const response = await request();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal((await response.json()).display_name, "Alice");
  assert.deepEqual(state.providerBodies[0].input, [{type: "text", text: "Alice"}]);
  assert.deepEqual(state.finishes, [{p_user_id: alice, p_kind: "name", p_revision: revision, p_claim_token: claimToken, p_outcome: "approve"}]);
  assert.equal(state.currentChecks, 2);
  assert.equal(state.reservations.length, 1);
});

for (const reason of ["stale", "budget", "attempts", "disabled", "reserved"]) {
  test(`a database ${reason} denial cannot call the provider or finish the deferred job`, async () => {
    const {request, state} = fixture({reservationResponse: {allowed: false, reason}});
    const response = await request();
    assert.equal(response.status, 200);
    assert.equal((await response.json()).display_name, "Explorer");
    assert.equal(state.reservations.length, 1);
    assert.equal(state.providerBodies.length, 0);
    assert.equal(state.finishes.length, 0);
  });
}

for (const reservationResponse of [null, true, "allowed", {}, {allowed: "true", reason: "allowed"},
  {allowed: true, reason: "budget"}, {allowed: false, reason: "allowed"}, {allowed: true, reason: "unknown"}]) {
  test(`malformed allowance fails closed (${JSON.stringify(reservationResponse)})`, async () => {
    const {request, state} = fixture({reservationResponse});
    await request();
    assert.equal(state.providerBodies.length, 0);
    assert.equal(state.finishes[0].p_outcome, "retry");
  });
}

for (const reservationStatus of [404, 503]) {
  test(`missing or unavailable budget store never calls the provider (${reservationStatus})`, async () => {
    const {request, state} = fixture({reservationStatus});
    await request();
    assert.equal(state.providerBodies.length, 0);
    assert.equal(state.finishes[0].p_outcome, "retry");
  });
}

test("concurrent replay of one claim can consume only one provider allowance", async () => {
  const {request, state} = fixture();
  const responses = await Promise.all(Array.from({length: 20}, () => request()));
  assert.ok(responses.every(response => response.status === 200));
  assert.equal(state.providerBodies.length, 1);
  assert.equal(state.finishes.length, 1);
});

test("photo validation precedes reservation, which precedes the external request", async () => {
  const {request, state} = fixture({claims: [photoClaim()]});
  await request();
  const storage = state.calls.findIndex(call => call.url.includes("/storage/"));
  const reserve = state.calls.findIndex(call => call.url.endsWith("/reserve_profile_check"));
  const provider = state.calls.findIndex(call => call.url === "https://api.openai.com/v1/moderations");
  assert.ok(storage >= 0 && reserve > storage && provider > reserve);
});

test("scheduled worker shares the budget and does not finish quota-deferred work", async () => {
  const {request, state} = fixture({claims: [nameClaim(), photoClaim()], reservationResponse: {allowed: false, reason: "budget"}});
  const response = await request({headers: {"x-worldniche-worker-secret": config.workerSecret}});
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {processed: 0});
  assert.equal(state.reservations.length, 2);
  assert.equal(state.providerBodies.length, 0);
  assert.equal(state.finishes.length, 0);
});

test("photo sends bounded private bytes, never a storage URL or user identity", async () => {
  const {request, state} = fixture({claims: [photoClaim()]});
  assert.equal((await request()).status, 200);
  assert.deepEqual(state.providerBodies[0].input, [{type: "image_url", image_url: {url: "data:image/jpeg;base64,/9j/2Q=="}}]);
  assert.equal(JSON.stringify(state.providerBodies).includes(alice), false);
  assert.equal(state.finishes[0].p_outcome, "approve");
});

test("worker processes a bounded batch without returning private content", async () => {
  const {request, state} = fixture({claims: [nameClaim(), photoClaim()]});
  const response = await request({headers: {"x-worldniche-worker-secret": config.workerSecret}});
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {processed: 2});
  assert.equal(state.calls.some(call => call.url.endsWith("authorize_profile_check") || call.url.endsWith("get_my_profile")), false);
  assert.deepEqual(state.calls.find(call => call.url.endsWith("claim_profile_checks")).body, {p_user_id: null, p_limit: 8});
});

test("user can claim only their own two fields", async () => {
  const {request, state} = fixture();
  await request();
  assert.deepEqual(state.calls.find(call => call.url.endsWith("claim_profile_checks")).body, {p_user_id: alice, p_limit: 2});
});

for (const token of [null, "", "Basic secret", "Bearer token extra", `Bearer ${"a".repeat(8192)}`]) {
  test(`invalid authorization is rejected without upstream requests (${token === null ? "missing" : token.slice(0, 12)})`, async () => {
    const {request, state} = fixture();
    const response = await request({headers: token === null ? {} : {Authorization: token}});
    assert.equal(response.status, 401);
    assert.equal(state.calls.length, 0);
  });
}

test("incorrect worker secret never falls back to a valid user token", async () => {
  const {request, state} = fixture();
  assert.equal((await request({headers: {...headers, "x-worldniche-worker-secret": "incorrect"}})).status, 401);
  assert.equal(state.calls.length, 0);
});

for (const [status, code, expected] of [[401, "PGRST301", 401], [400, "28000", 401], [403, "42501", 403], [400, "P0001", 429], [503, "unavailable", 503]]) {
  test(`revoked, expired, rate-limited, or unavailable identity cannot invoke provider (${code})`, async () => {
    const {request, state} = fixture({authStatus: status, authCode: code});
    const response = await request();
    assert.equal(response.status, expected);
    assert.equal((await response.text()).includes("private upstream detail"), false);
    assert.equal(state.calls.length, 1);
  });
}

for (const body of ['{"user_id":"spoofed"}', `{"photo_url":"https://example.com"}`, '{"model":"other-model"}', '{"input":"arbitrary prompt"}', "null", "[]", "bad JSON", "x".repeat(513)]) {
  test(`client parameters are never accepted (${body.slice(0, 25)})`, async () => {
    const {request, state} = fixture();
    assert.equal((await request({body})).status, 400);
    assert.equal(state.calls.length, 0);
  });
}

test("unsupported HTTP method is rejected", async () => {
  const {request, state} = fixture();
  assert.equal((await request({method: "GET", body: undefined})).status, 405);
  assert.equal(state.calls.length, 0);
});

for (const configuration of [{openaiKey: undefined}, {serviceKey: undefined}, {supabaseURL: "https://attacker.example"}]) {
  test(`missing or invalid configuration fails before claiming work (${Object.keys(configuration)[0]})`, async () => {
    const {request, state} = fixture({}, configuration);
    assert.equal((await request()).status, 503);
    assert.equal(state.calls.length, 0);
  });
}

test("unconsented, already claimed, and manual-review jobs are absent from claims and never sent", async () => {
  const {request, state} = fixture({claims: []});
  assert.equal((await request()).status, 200);
  assert.equal(state.providerBodies.length, 0);
  assert.equal(state.finishes.length, 0);
});

for (const changed of [{current: false}, {currentUntil: 2}]) {
  test(`consent withdrawal or superseded claim before disclosure avoids provider (${JSON.stringify(changed)})`, async () => {
    const {request, state} = fixture({claims: [photoClaim()], ...changed});
    assert.equal((await request()).status, 200);
    assert.equal(state.providerBodies.length, 0);
    assert.equal(state.finishes.length, 0);
  });
}

test("stale decision cannot update profile even after provider approval", async () => {
  const {request, state} = fixture({applied: false});
  const response = await request();
  assert.equal(response.status, 200);
  assert.equal((await response.json()).display_name, "Explorer");
  assert.equal(state.finishes[0].p_outcome, "approve");
});

for (const claims of [[{...nameClaim(), user_id: bob}], [{...photoClaim(), photo_path: "../other.jpg"}], [nameClaim(), nameClaim(), nameClaim()], [{...nameClaim(), revision: "bad"}]]) {
  test(`malformed or incorrectly scoped claim fails closed (${JSON.stringify(claims).slice(0, 80)})`, async () => {
    const {request, state} = fixture({claims});
    assert.equal((await request()).status, 503);
    assert.equal(state.providerBodies.length, 0);
  });
}

test("flagged content waits for human review and retains previous approved profile", async () => {
  const flagged = result(); flagged.results[0].flagged = true;
  const {request, state} = fixture({providerResponse: flagged});
  assert.equal((await (await request()).json()).display_name, "Explorer");
  assert.equal(state.finishes[0].p_outcome, "review");
});

test("a flagged category cannot be bypassed by a false aggregate flag", async () => {
  const flagged = result(); flagged.results[0].categories.hate = true;
  const {request, state} = fixture({providerResponse: flagged});
  await request();
  assert.equal(state.finishes[0].p_outcome, "review");
});

const malformed = [null, {}, {results: []}, {...result(), results: [result().results[0], result().results[0]]}];
const missingCoverage = result("photo"); missingCoverage.results[0].category_applied_input_types.sexual = [];
malformed.push(missingCoverage);
const invalidScore = result(); invalidScore.results[0].category_scores.hate = 2; malformed.push(invalidScore);
const noCategory = result(); delete noCategory.results[0].categories.hate; malformed.push(noCategory);
const wrongModel = result(); wrongModel.model = "text-moderation-latest"; malformed.push(wrongModel);
for (const [index, data] of malformed.entries()) {
  test(`incomplete provider response is retried without approval (${index})`, async () => {
    const {request, state} = fixture({claims: [index === 4 ? photoClaim() : nameClaim()], providerResponse: json(data)});
    assert.equal((await request()).status, 200);
    assert.equal(state.finishes[0].p_outcome, "retry");
  });
}

test("oversized provider response is bounded and never approved", async () => {
  const {request, state} = fixture({providerResponse: new Response("x".repeat(32769))});
  await request();
  assert.equal(state.finishes[0].p_outcome, "retry");
});

for (const status of [401, 403, 429, 500, 503]) {
  test(`provider failure ${status} records durable retry and returns saved owner profile`, async () => {
    const {request, state} = fixture({providerStatus: status});
    assert.equal((await request()).status, 200);
    assert.equal(state.finishes[0].p_outcome, "retry");
  });
}

test("provider timeout records a retry", async () => {
  const {request, state} = fixture({providerThrow: true});
  assert.equal((await request()).status, 200);
  assert.equal(state.finishes[0].p_outcome, "retry");
});

for (const status of [400, 422]) {
  test(`provider rejects invalid media ${status} into review instead of an endless retry`, async () => {
    const {request, state} = fixture({providerStatus: status});
    await request();
    assert.equal(state.finishes[0].p_outcome, "review");
  });
}

for (const override of [{imageType: "text/html"}, {imageLength: "300001"}, {image: new Uint8Array(300001)}, {image: new Uint8Array([0, 1, 2, 3])}, {storageStatus: 404}]) {
  test(`invalid or oversized stored media never reaches provider (${Object.keys(override)[0]})`, async () => {
    const {request, state} = fixture({claims: [photoClaim()], ...override});
    await request();
    assert.equal(state.providerBodies.length, 0);
    assert.equal(state.reservations.length, 0);
    assert.equal(state.finishes[0].p_outcome, "review");
  });
}

test("storage outage records retry without sending an empty photo", async () => {
  const {request, state} = fixture({claims: [photoClaim()], storageStatus: 503});
  await request();
  assert.equal(state.providerBodies.length, 0);
  assert.equal(state.finishes[0].p_outcome, "retry");
});

test("worker exposes failure when publishing fails so operational monitoring can detect it", async () => {
  const {request, state} = fixture({finishStatus: 503});
  const response = await request({headers: {"x-worldniche-worker-secret": config.workerSecret}});
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {processed: 0});
  assert.equal(state.finishes.length, 1);
});

test("native request still returns saved profile when durable lease must recover a failed finish", async () => {
  const {request} = fixture({finishStatus: 503});
  const response = await request();
  assert.equal(response.status, 200);
  assert.equal((await response.json()).display_name, "Explorer");
});

test("owner response cannot return another account after an upstream mismatch", async () => {
  const {request} = fixture({claims: [], profile: {id: bob}});
  assert.equal((await request()).status, 503);
});
