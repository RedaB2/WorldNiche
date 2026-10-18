import { readFile, writeFile, mkdir, readdir, rm } from "node:fs/promises";
import { resolve, dirname, extname } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { gzipSync } from "node:zlib";
import { readConfiguration } from "./configuration.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = await readConfiguration(root, "hosting");
if (typeof manifest.project_id !== "string" || !manifest.project_id || "static" in manifest) throw new Error("Configure a Worker hosting project ID without static configuration.");
const types = { ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".js": "application/javascript; charset=utf-8", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".svg": "image/svg+xml", ".mp4": "video/mp4", ".woff2": "font/woff2" };
const routes = {};
const blobs = {};
function add(path, bytes, type, cache = "public, max-age=3600") {
  const digest = createHash("sha256").update(bytes).digest("hex");
  blobs[digest] ??= { base64: bytes.toString("base64"), size: bytes.length, etag: `"${digest}"` };
  const route = { blob: digest, type, cache };
  if (path) routes[path] = route;
  return route;
}
async function walk(directory, prefix) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.name.startsWith(".") || entry.isSymbolicLink()) throw new Error(`Unexpected source entry: ${entry.name}`);
    const file = resolve(directory, entry.name);
    if (entry.isDirectory()) await walk(file, `${prefix}/${entry.name}`);
    else if (entry.isFile()) {
      const type = types[extname(file)];
      if (!type) throw new Error(`Unsupported asset: ${file}`);
      const bytes = await readFile(file);
      if (bytes.length > 25 * 1024 * 1024) throw new Error(`Asset exceeds the 25 MiB limit: ${file}`);
      add(`${prefix}/${entry.name}`, bytes, type, type.startsWith("text/html") ? "no-store" : undefined);
    }
  }
}
await walk(resolve(root, "content/landing"), "/landing");
routes["/"] = routes["/landing/index.html"];
if (!routes["/"]) throw new Error("Missing landing index.html");
for (const media of ["app-demo.mp4", "app-poster.jpg"]) {
  if (!routes[`/landing/assets/${media}`]) throw new Error(`Missing actual app media: ${media}. Import it before publishing.`);
}
let invitation = await readFile(resolve(root, "content/invite/index.html"), "utf8");
invitation = invitation.replace("__INSTALL_ACTION__", '<p class="install">WorldNiche is in development. If you already have it installed, open your invitation above.</p>');
add("/invite-template", Buffer.from(invitation), types[".html"], "no-store");
for (const name of ["style.css", "invite.js"]) add(`/${name}`, await readFile(resolve(root, "content/invite", name)), types[extname(name)]);
for (const name of ["logo.png", "logo-dark.png"]) routes[`/${name}`] = routes[`/landing/assets/${name}`];
const parsedAssociation = await readConfiguration(root, "association");
if (!parsedAssociation.applinks?.details?.some((detail) => detail.appIDs?.length && detail.components?.some((component) => component["/"] === "/invite/*"))) throw new Error("Association document must identify the app and invitation route");
const associationBytes = Buffer.from(JSON.stringify(parsedAssociation));
const association = add(null, associationBytes, "application/json", "public, max-age=300");
const handler = await readFile(resolve(root, "worker/handler.js"), "utf8");
const output = `${handler}\nconst payload = ${JSON.stringify({ routes, blobs, association })};\nexport default createHandler(payload);\n`;
const compressed = gzipSync(output).length;
if (compressed > 8 * 1024 * 1024) throw new Error(`Worker is ${(compressed / 1048576).toFixed(2)} MiB gzip; compress actual media to stay below this package's 8 MiB budget.`);
await rm(resolve(root, "dist"), { recursive: true, force: true });
await mkdir(resolve(root, "dist/server"), { recursive: true });
await mkdir(resolve(root, "dist/.openai"), { recursive: true });
await writeFile(resolve(root, "dist/server/index.js"), output);
await writeFile(resolve(root, "dist/.openai/hosting.json"), JSON.stringify(manifest, null, 2) + "\n");
const report = { routes: Object.keys(routes).length, uniqueAssets: Object.keys(blobs).length, workerBytes: Buffer.byteLength(output), gzipBytes: compressed, assetBytes: Object.values(blobs).reduce((sum, blob) => sum + blob.size, 0) };
await writeFile(resolve(root, "dist/.openai/build-report.json"), JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(report));
