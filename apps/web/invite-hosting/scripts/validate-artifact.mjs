import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createHash } from "node:crypto";
import { readConfiguration } from "./configuration.mjs";

const projectRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));
const workerPath = resolve(projectRoot, "dist/server/index.js");
const manifestPath = resolve(projectRoot, "dist/.openai/hosting.json");

const [source, manifest] = await Promise.all([
  readFile(workerPath, "utf8"),
  readFile(manifestPath, "utf8"),
]);
const configuration = JSON.parse(manifest);
assert.deepEqual(configuration, await readConfiguration(projectRoot, "hosting"));
assert.equal("static" in configuration, false);

// A data URL forces ESM parsing even though the generated output has no package.json.
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`;
const workerModule = await import(moduleUrl);
assert.equal(
  typeof workerModule.default?.fetch,
  "function",
  `${pathToFileURL(workerPath)} must export default.fetch`,
);

const fetch = (path, options) => workerModule.default.fetch(new Request(`https://worldniche.app${path}`, options));
const association = await fetch("/.well-known/apple-app-site-association");
assert.equal(association.status, 200);
assert.equal(association.headers.get("content-type"), "application/json");
assert.equal(association.headers.get("location"), null);
assert.deepEqual(await association.json(), await readConfiguration(projectRoot, "association"));
const landing = await fetch("/");
assert.equal(landing.status, 200);
const html = await landing.text();
assert.match(html, /WorldNiche/);
assert.match(html, /\/landing\/assets\/app-demo\.mp4/);
assert.doesNotMatch(html, /__INSTALL_ACTION__|codex-preview|apps\.apple\.com\/[^"'\s]*id0\b/);
for (const match of html.matchAll(/(?:src|href|poster)="(\/[^"#]*)(?:#[^"]*)?"/g)) {
  const path = match[1];
  assert.equal((await fetch(path, { method: "HEAD" })).status, 200, `Missing landing asset: ${path}`);
}
const invite = await fetch(`/invite/${"a".repeat(64)}`);
assert.equal(invite.status, 200);
assert.equal(invite.headers.get("cache-control"), "no-store");
assert.doesNotMatch(await invite.text(), /__INSTALL_ACTION__/);

for (const page of ["privacy", "security", "support", "community", "delete-account"]) {
  const response = await fetch(`/${page}`);
  assert.equal(response.status, 200, page);
  assert.equal(response.headers.get("content-type"), "text/html; charset=utf-8");
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(response.headers.get("set-cookie"), null);
  assert.match(response.headers.get("content-security-policy"), /frame-ancestors 'none'/);
  const pageHTML = await response.text();
  assert.match(pageHTML, /mailto:boutayeb\.reda@icloud\.com/);
  assert.doesNotMatch(pageHTML, /\[MONITORED|\[PUBLICATION|__INSTALL_ACTION__|\u2014/);
  for (const match of pageHTML.matchAll(/(?:src|href)="(\/[^"#]*)(?:#[^"]*)?"/g)) {
    assert.equal((await fetch(match[1], { method: "HEAD" })).status, 200, `${page}: ${match[1]}`);
  }
  const head = await fetch(`/${page}/`, { method: "HEAD" });
  assert.equal(head.status, 200);
  assert.equal((await head.arrayBuffer()).byteLength, 0);
}

for (const [name, type] of [["app-demo.mp4", "video/mp4"], ["app-poster.jpg", "image/jpeg"], ["hand-phone.png", "image/png"], ["logo.png", "image/png"], ["logo-dark.png", "image/png"]]) {
  const expected = await readFile(resolve(projectRoot, "content/landing/assets", name));
  const path = `/landing/assets/${name}`;
  const response = await fetch(path);
  assert.equal(response.headers.get("content-type"), type);
  assert.equal(Number(response.headers.get("content-length")), expected.length);
  const actual = Buffer.from(await response.arrayBuffer());
  assert.equal(createHash("sha256").update(actual).digest("hex"), createHash("sha256").update(expected).digest("hex"), `${name} must retain the supplied bytes`);
  for (const [start, end] of [[0, 1], [1, Math.min(4096, expected.length - 1)], [expected.length - 2, expected.length - 1]]) {
    const partial = await fetch(path, { headers: { range: `bytes=${start}-${end}` } });
    assert.equal(partial.status, 206);
    assert.deepEqual(Buffer.from(await partial.arrayBuffer()), expected.subarray(start, end + 1));
  }
}
const report = JSON.parse(await readFile(resolve(projectRoot, "dist/.openai/build-report.json")));
assert.ok(report.gzipBytes <= 8 * 1024 * 1024);
console.log(`PASS: standalone ESM, configured Site identity, direct JSON AASA, landing routes, invitation fallback, and exact media bytes/ranges. Worker gzip ${(report.gzipBytes / 1048576).toFixed(2)} MiB.`);
