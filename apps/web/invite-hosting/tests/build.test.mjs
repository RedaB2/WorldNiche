import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, cp, writeFile, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

test("packaging is self-contained, rejects missing real media, and deduplicates asset aliases", async () => {
  const source = fileURLToPath(new URL("..", import.meta.url));
  const scratch = await mkdtemp(resolve(tmpdir(), "worldniche-hosting-package-test-"));
  try {
    for (const directory of ["scripts", "worker", ".openai", "content/landing/assets", "content/invite"]) await mkdir(resolve(scratch, directory), { recursive: true });
    for (const path of ["scripts/build.mjs", "scripts/configuration.mjs", "worker/handler.js", "hosting.example.json", "association.example.json"]) await cp(resolve(source, path), resolve(scratch, path));
    await writeFile(resolve(scratch, "content/landing/index.html"), '<!doctype html><title>WorldNiche</title><video poster="/landing/assets/app-poster.jpg"><source src="/landing/assets/app-demo.mp4"></video>');
    const publicPages = ["privacy", "security", "support", "community", "delete-account"];
    for (const page of publicPages) await writeFile(resolve(scratch, `content/landing/${page}.html`), `<!doctype html><title>${page}</title><main>${page}</main>`);
    await writeFile(resolve(scratch, "content/invite/index.html"), '<!doctype html><title>Invitation</title>__INSTALL_ACTION__');
    await writeFile(resolve(scratch, "content/invite/style.css"), 'body { margin: 0; }');
    await writeFile(resolve(scratch, "content/invite/invite.js"), 'void 0;');
    // Synthetic bytes exist only in this disposable test repository. The public
    // hosting build always requires the actual app recording.
    for (const name of ["logo.png", "logo-dark.png"]) await writeFile(resolve(scratch, "content/landing/assets", name), Buffer.from([137, 80, 78, 71]));
    const beforeMedia = spawnSync(process.execPath, ["scripts/build.mjs"], { cwd: scratch, encoding: "utf8" });
    assert.notEqual(beforeMedia.status, 0);
    assert.match(beforeMedia.stderr, /Missing actual app media/);
    await writeFile(resolve(scratch, "content/landing/assets/app-demo.mp4"), Buffer.from(Array.from({ length: 101 }, (_, index) => index)));
    await writeFile(resolve(scratch, "content/landing/assets/app-poster.jpg"), Buffer.from([255, 216, 1, 2, 255, 217]));
    const built = spawnSync(process.execPath, ["scripts/build.mjs"], { cwd: scratch, encoding: "utf8" });
    assert.equal(built.status, 0, built.stderr);
    const report = JSON.parse(built.stdout);
    assert.ok(report.routes > report.uniqueAssets, "Root and landing aliases must share byte storage");
    const metadata = JSON.parse(await readFile(resolve(scratch, "dist/.openai/hosting.json")));
    assert.equal(metadata.project_id, "YOUR_SITES_PROJECT_ID");
    assert.equal("static" in metadata, false);
    const code = await readFile(resolve(scratch, "dist/server/index.js"), "utf8");
    const generated = await import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`);
    const association = await generated.default.fetch(new Request("https://worldniche.app/.well-known/apple-app-site-association"));
    assert.equal(association.headers.get("content-type"), "application/json");
    for (const page of publicPages) {
      for (const path of [`/${page}`, `/${page}/`]) {
        const response = await generated.default.fetch(new Request(`https://worldniche.app${path}`));
        assert.equal(response.status, 200, path);
        assert.equal(response.headers.get("content-type"), "text/html; charset=utf-8");
        assert.equal(response.headers.get("cache-control"), "no-store");
        assert.equal(response.headers.get("location"), null);
        assert.equal(response.headers.get("set-cookie"), null);
        assert.match(await response.text(), new RegExp(`<main>${page}</main>`));
      }
    }
    const video = await generated.default.fetch(new Request("https://worldniche.app/landing/assets/app-demo.mp4", { headers: { range: "bytes=5-7" } }));
    assert.equal(video.status, 206);
    assert.deepEqual(Buffer.from(await video.arrayBuffer()), Buffer.from([5, 6, 7]));
  } finally { await rm(scratch, { recursive: true, force: true }); }
});
