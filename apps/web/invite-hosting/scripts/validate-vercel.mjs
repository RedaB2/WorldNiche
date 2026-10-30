import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { resolve, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import worker, { payload } from "../dist/server/index.js";

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const output = resolve(webRoot, ".vercel/output");
const config = JSON.parse(await readFile(resolve(output, "config.json")));
assert.equal(config.version, 3);
const paths = [...Object.keys(payload.routes).filter(path => path !== "/invite-template"),
  "/index.html", "/.well-known/apple-app-site-association", "/apple-app-site-association"];
for (const path of paths) {
  const route = config.routes.find(item => new RegExp(item.src).test(path));
  assert.ok(route.dest.startsWith("/_assets/"), `CDN route missing: ${path}`);
  const bytes = await readFile(resolve(output, "static", route.dest.slice(1)));
  const original = await worker.fetch(new Request(`https://worldniche.app${path}`));
  assert.equal(original.status, 200, path);
  assert.deepEqual(bytes, Buffer.from(await original.arrayBuffer()), path);
  for (const key of ["content-type", "cache-control", "content-security-policy", "referrer-policy", "x-content-type-options", "permissions-policy"]) {
    assert.equal(route.headers[key], original.headers.get(key), `${path}: ${key}`);
  }
}
const aasaRoute = config.routes.find(item => new RegExp(item.src).test("/.well-known/apple-app-site-association"));
const aasa = JSON.parse(await readFile(resolve(output, "static", aasaRoute.dest.slice(1))));
const production = JSON.parse(await readFile(resolve(webRoot, "../../ops/production.json")));
assert.deepEqual(aasa.applinks.details[0].appIDs, [`${production.apple.teamID}.${production.apple.bundleID}`]);

const { default: adapter } = await import(pathToFileURL(resolve(output, "functions/fallback.func/index.cjs")));
const server = createServer(adapter);
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
try {
  const base = `http://127.0.0.1:${server.address().port}`;
  const token = "a".repeat(64);
  for (const [path, method] of [
    [`/invite/${token}`, "GET"], [`/invite/${token}`, "HEAD"], [`/invite/${token}`, "POST"],
    [`/invite/${token}?extra=1`, "GET"], ["/invite/short", "GET"], ["/invite-template", "GET"],
    [`/invite/${token.toUpperCase()}`, "GET"], ["/_assets/not-public", "GET"], ["/missing", "GET"],
  ]) {
    const actual = await fetch(`${base}${path}`, { method });
    const expected = await worker.fetch(new Request(`https://worldniche.app${path}`, { method }));
    assert.equal(actual.status, expected.status, `${method} ${path}`);
    for (const key of ["content-type", "cache-control", "allow", "content-security-policy", "referrer-policy"]) {
      assert.equal(actual.headers.get(key), expected.headers.get(key), `${method} ${path}: ${key}`);
    }
    assert.deepEqual(Buffer.from(await actual.arrayBuffer()), Buffer.from(await expected.arrayBuffer()), path);
  }
} finally { await new Promise(resolve => server.close(resolve)); }
console.log(`PASS: ${paths.length} CDN routes match current website bytes and headers; production AASA and nine invitation/error HTTP scenarios pass.`);
