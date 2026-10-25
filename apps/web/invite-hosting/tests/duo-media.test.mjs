import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, cp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const source = fileURLToPath(new URL('..', import.meta.url));
const duoMedia = ['hand-duo.png', 'duo-demo.mp4', 'duo-poster.jpg'];
const bytes = Buffer.from(Array.from({ length: 101 }, (_, index) => index));

async function fixture() {
  const scratch = await mkdtemp(resolve(tmpdir(), 'worldniche-duo-media-test-'));
  for (const path of ['scripts', 'worker', '.openai', 'content/landing/assets', 'content/invite']) {
    await mkdir(resolve(scratch, path), { recursive: true });
  }
  for (const path of ['scripts/build.mjs', 'scripts/validate-artifact.mjs', 'scripts/configuration.mjs', 'worker/handler.js', 'hosting.example.json', 'association.example.json']) {
    await cp(resolve(source, path), resolve(scratch, path));
  }
  await writeFile(resolve(scratch, 'content/landing/index.html'), '<!doctype html><title>WorldNiche</title><video poster="/landing/assets/app-poster.jpg"><source src="/landing/assets/app-demo.mp4"></video>');
  for (const name of ['privacy', 'security', 'support', 'community', 'delete-account']) {
    await writeFile(resolve(scratch, `content/landing/${name}.html`), '<!doctype html><title>WorldNiche</title><a href="mailto:boutayeb.reda@icloud.com">Contact</a>');
  }
  await writeFile(resolve(scratch, 'content/invite/index.html'), '<!doctype html><title>Invitation</title>__INSTALL_ACTION__');
  await writeFile(resolve(scratch, 'content/invite/style.css'), 'body { margin: 0; }');
  await writeFile(resolve(scratch, 'content/invite/invite.js'), 'void 0;');
  // These tiny byte fixtures are isolated from all deployable content.
  for (const name of ['app-demo.mp4', 'app-poster.jpg', 'hand-phone.png', 'logo.png', 'logo-dark.png']) {
    await writeFile(resolve(scratch, 'content/landing/assets', name), bytes);
  }
  return scratch;
}

const run = (scratch, name) => spawnSync(process.execPath, [`scripts/${name}.mjs`], { cwd: scratch, encoding: 'utf8' });

test('a referenced Duo preview requires all three real assets, while legacy pages remain valid', async () => {
  const scratch = await fixture();
  try {
    const legacy = run(scratch, 'build');
    assert.equal(legacy.status, 0, legacy.stderr);
    const legacyValidation = run(scratch, 'validate-artifact');
    assert.equal(legacyValidation.status, 0, legacyValidation.stderr);
    const path = resolve(scratch, 'content/landing/index.html');
    const original = await readFile(path, 'utf8');
    // A lazy source alone still activates the full Duo media contract.
    await writeFile(path, original + '<video><source data-src="/landing/assets/duo-demo.mp4?v=duo-test"></video>');
    for (const name of duoMedia) {
      const missing = run(scratch, 'build');
      assert.notEqual(missing.status, 0, `Publishing must fail before ${name} is imported`);
      assert.ok(missing.stderr.includes(`Missing actual app media: ${name}`), missing.stderr);
      await writeFile(resolve(scratch, 'content/landing/assets', name), Buffer.alloc(0));
      const empty = run(scratch, 'build');
      assert.notEqual(empty.status, 0, `An empty ${name} must not satisfy the media contract`);
      assert.ok(empty.stderr.includes(`Missing actual app media: ${name}`), empty.stderr);
      await writeFile(resolve(scratch, 'content/landing/assets', name), bytes);
    }
    const complete = run(scratch, 'build');
    assert.equal(complete.status, 0, complete.stderr);
    const validated = run(scratch, 'validate-artifact');
    assert.equal(validated.status, 0, validated.stderr);
  } finally { await rm(scratch, { recursive: true, force: true }); }
});

test('artifact validation detects a missing packaged Duo file even when the HTML only references another Duo asset', async () => {
  const scratch = await fixture();
  try {
    const path = resolve(scratch, 'content/landing/index.html');
    await writeFile(path, (await readFile(path, 'utf8')) + '<img src="/landing/assets/hand-duo.png?v=duo-test" alt="">');
    for (const name of duoMedia) await writeFile(resolve(scratch, 'content/landing/assets', name), bytes);
    const built = run(scratch, 'build');
    assert.equal(built.status, 0, built.stderr);
    const valid = run(scratch, 'validate-artifact');
    assert.equal(valid.status, 0, valid.stderr);
    const workerPath = resolve(scratch, 'dist/server/index.js');
    const worker = await readFile(workerPath, 'utf8');
    const broken = worker.replace('"/landing/assets/duo-demo.mp4":', '"/landing/assets/removed-duo-demo.mp4":');
    assert.notEqual(broken, worker, 'The fixture must actually remove the published Duo video route');
    await writeFile(workerPath, broken);
    const rejected = run(scratch, 'validate-artifact');
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, /duo-demo\.mp4/);
  } finally { await rm(scratch, { recursive: true, force: true }); }
});
