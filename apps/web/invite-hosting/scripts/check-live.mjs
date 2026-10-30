import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const origin = new URL(process.argv[2] || "https://worldniche.app");
assert.equal(origin.protocol, "https:", "Use a public HTTPS deployment URL");
assert.equal(origin.username + origin.password + origin.search + origin.hash, "");
const production = JSON.parse(await readFile(new URL("../../../../ops/production.json", import.meta.url)));
const expectedCommit = process.argv[3];
const request = (path, options = {}) => fetch(new URL(path, origin), {
  redirect: "manual", signal: AbortSignal.timeout(20000), ...options,
});
for (const path of ["/", "/privacy", "/security", "/support", "/community", "/delete-account"]) {
  const response = await request(path);
  assert.equal(response.status, 200, path);
  assert.match(response.headers.get("content-type"), /text\/html/);
  assert.match(response.headers.get("content-security-policy"), /frame-ancestors 'none'/);
  assert.match(response.headers.get("cache-control"), /no-store/);
  assert.ok(!response.headers.has("set-cookie"), `${path}: unexpected cookie header`);
  assert.match(await response.text(), /WorldNiche/);
}
for (const path of ["/.well-known/apple-app-site-association", "/apple-app-site-association"]) {
  const response = await request(path);
  assert.equal(response.status, 200, path);
  assert.match(response.headers.get("content-type"), /application\/json/);
  const association = await response.json();
  assert.deepEqual(association.applinks.details[0].appIDs, [`${production.apple.teamID}.${production.apple.bundleID}`]);
  assert.equal(association.applinks.details[0].components[0]["/"], "/invite/*");
}
for (const name of ["app-demo.mp4", "duo-demo.mp4"]) {
  const path = `/landing/assets/${name}`;
  const expected = await readFile(new URL(`../../landing-site/assets/${name}`, import.meta.url));
  for (const [start, end] of [[0, 1], [expected.length - 2, expected.length - 1]]) {
    const response = await request(path, { headers: { range: `bytes=${start}-${end}` } });
    assert.equal(response.status, 206, `${name}: range`);
    assert.equal(response.headers.get("content-type"), "video/mp4");
    assert.equal(response.headers.get("content-range"), `bytes ${start}-${end}/${expected.length}`);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), expected.subarray(start, end + 1), name);
  }
}
const invitation = `/invite/${"a".repeat(64)}`;
const response = await request(invitation);
assert.equal(response.status, 200, "Valid invitation page");
assert.match(response.headers.get("cache-control"), /no-store/);
assert.match(await response.text(), /Open in WorldNiche/);
assert.equal((await request(invitation, { method: "HEAD" })).status, 200);
assert.equal((await request(invitation, { method: "POST" })).status, 405);
assert.equal((await request(`${invitation}?extra=1`)).status, 404);
assert.equal((await request("/invite/invalid")).status, 404);
assert.equal((await request("/invite-template")).status, 404);
if (expectedCommit) {
  assert.match(expectedCommit, /^[0-9a-f]{40}$/);
  const response = await request("/deployment.json");
  assert.equal(response.status, 200);
  assert.equal((await response.json()).commit, expectedCommit, "Live commit must match the merged GitHub commit");
}
console.log(`PASS: ${origin.origin} pages, security headers, direct JSON AASA, both video ranges, invitations and deployment provenance.`);
