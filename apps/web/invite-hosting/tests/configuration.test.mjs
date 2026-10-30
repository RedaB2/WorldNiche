import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {readConfiguration} from '../scripts/configuration.mjs';

test('public examples support fresh development checkouts', async t => {
  const root = await fixture(t);
  assert.deepEqual(await readConfiguration(root, 'hosting'), {project_id:'example'});
});

test('delivery uses its public routing while local overrides remain explicit', async t => {
  const root = await fixture(t);
  await writeFile(join(root, 'hosting.production.json'), '{"project_id":"production"}');
  assert.equal((await readConfiguration(root, 'hosting')).project_id, 'production');
  await writeFile(join(root, 'hosting.local.json'), '{"project_id":"local"}');
  assert.equal((await readConfiguration(root, 'hosting')).project_id, 'local');
});

test('malformed production config fails instead of deploying example routing', async t => {
  const root = await fixture(t);
  await writeFile(join(root, 'hosting.production.json'), 'invalid');
  await assert.rejects(readConfiguration(root, 'hosting'), SyntaxError);
});

test('missing configuration fails instead of inventing a project', async t => {
  const root = await fixture(t);
  await assert.rejects(readConfiguration(root, 'association'), {code:'ENOENT'});
});

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'worldniche-routing-'));
  t.after(() => rm(root, {recursive:true, force:true}));
  await writeFile(join(root, 'hosting.example.json'), '{"project_id":"example"}');
  return root;
}
