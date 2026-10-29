import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const privacy = await readFile(new URL('../../landing-site/privacy.html', import.meta.url), 'utf8');
test('account journal collection and private notes are disclosed', () => {
  assert.match(privacy, /saved status, private notes, first and most recent exploration dates/);
  assert.match(privacy, /Private notes are not sent to OpenAI or shown to friends/);
  assert.match(privacy, /private account journal remains available when sharing is off/);
  assert.match(privacy, /account journal entries and notes, shared explorations/);
  assert.doesNotMatch(privacy, /Your saved countries stay on your device/);
});
