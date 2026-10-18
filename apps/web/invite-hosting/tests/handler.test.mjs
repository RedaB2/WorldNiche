import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { createHandler } from "../worker/handler.js";

const blobs = {};
function asset(text, type, cache = "public, max-age=3600") {
  const bytes = typeof text === "string" ? Buffer.from(text) : text;
  const hash = createHash("sha256").update(bytes).digest("hex");
  blobs[hash] = { base64: bytes.toString("base64"), size: bytes.length, etag: `"${hash}"` };
  return { blob: hash, type, cache };
}
const video = Buffer.from(Array.from({ length: 101 }, (_, index) => index));
const routes = {
  "/": asset("WorldNiche landing", "text/html; charset=utf-8", "no-store"),
  "/invite-template": asset("Open your invitation", "text/html; charset=utf-8", "no-store"),
  "/landing/assets/app-demo.mp4": asset(video, "video/mp4"),
  "/landing/style.css": asset("body{}", "text/css; charset=utf-8"),
  "/landing/landing.js": asset("void 0;", "application/javascript; charset=utf-8"),
  "/logo.png": asset(Buffer.from([137, 80, 78, 71]), "image/png"),
};
const association = asset(JSON.stringify({ applinks: { details: [{ appIDs: ["TEAMIDHERE.io.worldniche.app"], components: [{ "/": "/invite/*" }] }] } }), "application/json", "public, max-age=300");
const handler = createHandler({ routes, blobs, association });
const request = (path, options) => handler.fetch(new Request(`https://worldniche.app${path}`, options));
const token = "a".repeat(64);

test("AASA is anonymous JSON without a redirect at both Apple paths", async () => {
  for (const path of ["/.well-known/apple-app-site-association", "/apple-app-site-association"]) {
    const response = await request(path);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "application/json");
    assert.equal(response.headers.get("location"), null);
    assert.equal(response.headers.get("set-cookie"), null);
    assert.deepEqual((await response.json()).applinks.details[0].appIDs, ["TEAMIDHERE.io.worldniche.app"]);
  }
});

test("home and valid invitation serve separate content without redeeming", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () => { throw new Error("GET must never contact a redemption API"); };
  try {
    assert.equal(await (await request("/")).text(), "WorldNiche landing");
    const invite = await request(`/invite/${token}`, { headers: { purpose: "prefetch" } });
    assert.equal(await invite.text(), "Open your invitation");
    assert.equal(invite.headers.get("cache-control"), "no-store");
    assert.equal(invite.headers.get("referrer-policy"), "no-referrer");
    assert.equal(invite.headers.get("set-cookie"), null);
  } finally { globalThis.fetch = original; }
});

test("malformed, noncanonical, internal and unknown routes cannot open an invitation", async () => {
  for (const path of ["/invite/bad", `/invite/${token}/`, `/invite/${token}?track=1`, `/invite/${token.toUpperCase()}`, `/invite/%61${token.slice(1)}`, "/invite-template", "/missing", "/.openai/hosting.json", "/server/index.js"]) {
    const response = await request(path);
    assert.equal(response.status, 404, path);
    assert.doesNotMatch(await response.text(), /worldniche:\/\/invite/);
    assert.equal(response.headers.get("location"), null);
  }
});

test("mutation verbs are rejected and never forwarded", async () => {
  for (const method of ["POST", "PUT", "DELETE", "PATCH", "OPTIONS"]) {
    const response = await request(`/invite/${token}`, { method });
    assert.equal(response.status, 405);
    assert.equal(response.headers.get("allow"), "GET, HEAD");
  }
});

test("CSS, JavaScript and raster content have explicit safe MIME types", async () => {
  for (const [path, type] of [["/landing/style.css", "text/css; charset=utf-8"], ["/landing/landing.js", "application/javascript; charset=utf-8"], ["/logo.png", "image/png"]]) {
    const response = await request(path);
    assert.equal(response.headers.get("content-type"), type);
    assert.equal(response.headers.get("x-content-type-options"), "nosniff");
    assert.match(response.headers.get("content-security-policy"), /connect-src 'none'/);
  }
});

test("MP4 full fetch and HEAD retain exact bytes and size", async () => {
  const full = await request("/landing/assets/app-demo.mp4");
  assert.equal(full.status, 200);
  assert.equal(full.headers.get("content-type"), "video/mp4");
  assert.equal(full.headers.get("content-length"), "101");
  assert.equal(full.headers.get("accept-ranges"), "bytes");
  assert.deepEqual(Buffer.from(await full.arrayBuffer()), video);
  const head = await request("/landing/assets/app-demo.mp4", { method: "HEAD", headers: { range: "bytes=0-1" } });
  assert.equal(head.status, 200);
  assert.equal(head.headers.get("content-length"), "101");
  assert.equal((await head.arrayBuffer()).byteLength, 0);
});

test("Safari video probes, seeking, suffixes and clamped end ranges work", async () => {
  for (const [range, start, end] of [["bytes=0-1", 0, 1], ["bytes=1-4", 1, 4], ["bytes=4-10", 4, 10], ["bytes=90-", 90, 100], ["bytes=-7", 94, 100], ["bytes=99-500", 99, 100], ["bytes=-500", 0, 100], ["bytes=100-100", 100, 100]]) {
    const response = await request("/landing/assets/app-demo.mp4", { headers: { range } });
    assert.equal(response.status, 206, range);
    assert.equal(response.headers.get("content-range"), `bytes ${start}-${end}/101`);
    assert.equal(Number(response.headers.get("content-length")), end - start + 1);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), video.subarray(start, end + 1), range);
  }
});

test("invalid and multipart ranges fail explicitly without giant allocations", async () => {
  for (const range of ["bytes=101-", "bytes=9-2", "bytes=-0", "bytes=", "bytes=a-b", "bytes=0-1,5-6", "bytes=9007199254740992-"]) {
    const response = await request("/landing/assets/app-demo.mp4", { headers: { range } });
    assert.equal(response.status, 416, range);
    assert.equal(response.headers.get("content-range"), "bytes */101");
    assert.equal((await response.arrayBuffer()).byteLength, 0);
  }
});

test("conditional requests honor ETags and If-Range", async () => {
  const tag = blobs[routes["/landing/assets/app-demo.mp4"].blob].etag;
  const unchanged = await request("/landing/assets/app-demo.mp4", { headers: { "if-none-match": `W/${tag}` } });
  assert.equal(unchanged.status, 304);
  assert.equal(unchanged.headers.get("content-length"), null);
  const stale = await request("/landing/assets/app-demo.mp4", { headers: { range: "bytes=0-1", "if-range": '"old"' } });
  assert.equal(stale.status, 200);
  assert.deepEqual(Buffer.from(await stale.arrayBuffer()), video);
  const fresh = await request("/landing/assets/app-demo.mp4", { headers: { range: "bytes=0-1", "if-range": tag } });
  assert.equal(fresh.status, 206);
});

test("example hosting configuration has no live Site identity", async () => {
  const manifest = JSON.parse(await readFile(new URL("../hosting.example.json", import.meta.url)));
  assert.equal(manifest.project_id, "YOUR_SITES_PROJECT_ID");
  assert.equal("static" in manifest, false);
});
