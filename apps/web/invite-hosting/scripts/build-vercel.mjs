import { readFile, writeFile, mkdir, rm } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { payload, securityHeaders } from "../dist/server/index.js";

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const output = resolve(webRoot, ".vercel/output");
await rm(output, { recursive: true, force: true });
await mkdir(resolve(output, "static/_assets"), { recursive: true });
const functionRoot = resolve(output, "functions/fallback.func");
await mkdir(functionRoot, { recursive: true });

const routing = [];
const written = new Set();
const escape = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const overrides = {};
async function addRoute(path, route) {
  const blob = payload.blobs[route.blob];
  const asset = `_assets/${route.blob}`;
  if (!written.has(asset)) {
    await writeFile(resolve(output, "static", asset), Buffer.from(blob.base64, "base64"));
    written.add(asset);
    overrides[asset] = { contentType: route.type };
  }
  routing.push({
    src: `^${escape(path)}$`, methods: ["GET", "HEAD"], caseSensitive: true,
    dest: `/${asset}`, headers: { ...securityHeaders, "cache-control": route.cache, "content-type": route.type },
  });
}
for (const [path, route] of Object.entries(payload.routes)) {
  if (path !== "/invite-template") await addRoute(path, route);
}
await addRoute("/index.html", payload.routes["/"]);
for (const path of ["/.well-known/apple-app-site-association", "/apple-app-site-association"]) {
  await addRoute(path, payload.association);
}

const commit = process.env.VERCEL_GIT_COMMIT_SHA || process.env.GITHUB_SHA
  || execFileSync("git", ["rev-parse", "HEAD"], { cwd: webRoot, encoding: "utf8" }).trim();
if (!/^[0-9a-f]{40}$/.test(commit)) throw new Error("Missing exact Git commit for deployment provenance");
await writeFile(resolve(output, "static/deployment.json"), JSON.stringify({ repository: "RedaB2/WorldNiche", commit }) + "\n");
routing.push({ src: "^/deployment\\.json$", methods: ["GET", "HEAD"], dest: "/deployment.json", headers: {
  ...securityHeaders, "content-type": "application/json", "cache-control": "no-store",
} });
// Only invitations and errors use a function. Videos and images stay on the CDN.
routing.push({ src: "/.*", dest: "/fallback" });
await writeFile(resolve(output, "config.json"), JSON.stringify({ version: 3, routes: routing, overrides }, null, 2) + "\n");

const invitation = payload.routes["/invite-template"];
const fallback = {
  routes: { "/invite-template": invitation }, association: payload.association,
  blobs: Object.fromEntries([invitation.blob, payload.association.blob].map(key => [key, payload.blobs[key]])),
};
const handler = await readFile(new URL("../worker/handler.js", import.meta.url), "utf8");
await writeFile(resolve(functionRoot, "handler.mjs"), `${handler}\nexport default createHandler(${JSON.stringify(fallback)});\n`);
await writeFile(resolve(functionRoot, "index.cjs"), await readFile(new URL("../worker/vercel-adapter.cjs", import.meta.url)));
await writeFile(resolve(functionRoot, ".vc-config.json"), JSON.stringify({
  runtime: "nodejs24.x", handler: "index.cjs", launcherType: "Nodejs", maxDuration: 10,
}, null, 2) + "\n");
console.log(`Prepared Vercel build: ${written.size} CDN assets, invitation fallback, commit ${commit}.`);
