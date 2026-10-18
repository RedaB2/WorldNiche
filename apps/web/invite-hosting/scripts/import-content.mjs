import { cp, mkdir, readdir, rm } from "node:fs/promises";
import { resolve, dirname, extname } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
if (args.length !== 4 || args[0] !== "--landing" || args[2] !== "--invites") {
  throw new Error("Use: node scripts/import-content.mjs --landing ABSOLUTE_LANDING_DIR --invites ABSOLUTE_INVITE_DIR");
}
const allowed = new Set([".html", ".css", ".js", ".png", ".jpg", ".jpeg", ".webp", ".svg", ".mp4", ".woff2"]);
async function copyTree(source, target) {
  await mkdir(target, { recursive: true });
  for (const entry of await readdir(source, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    if (entry.isSymbolicLink()) throw new Error(`Source symlink is not allowed: ${entry.name}`);
    if (entry.isDirectory()) await copyTree(resolve(source, entry.name), resolve(target, entry.name));
    else if (entry.isFile() && allowed.has(extname(entry.name))) await cp(resolve(source, entry.name), resolve(target, entry.name));
  }
}
for (const [kind, source] of [["landing", args[1]], ["invite", args[3]]]) {
  const target = resolve(root, "content", kind);
  await rm(target, { recursive: true, force: true });
  await copyTree(resolve(source), target);
}
console.log("Copied landing and invitation sources into this standalone hosting repository.");
