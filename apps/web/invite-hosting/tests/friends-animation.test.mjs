import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { createHash } from 'node:crypto';

const script = await readFile(new URL('../../landing-site/friends.js', import.meta.url), 'utf8');
function setup({ reduced = false, observer = true, hidden = false } = {}) {
  const element = () => ({
    listeners: {}, hidden: true, textContent: '', dataset: {},
    addEventListener(name, fn) { this.listeners[name] = fn; },
    emit(name, event = {}) { this.listeners[name]?.(event); },
  });
  const scene = element(), status = element(), replay = element(), envelope = element();
  scene.querySelector = selector => ({ '.connection-status': status, '.connection-replay': replay, '.connection-envelope': envelope })[selector];
  const motion = Object.assign(element(), { matches: reduced });
  const document = Object.assign(element(), { hidden, getElementById: () => scene });
  let intersection;
  const context = { document, window: { matchMedia: () => motion } };
  if (observer) context.IntersectionObserver = class {
    constructor(callback) { intersection = callback; }
    observe() {}
  };
  vm.runInNewContext(script, context);
  return {
    scene, status, replay, envelope, motion, document,
    visible(value) { intersection?.([{ isIntersecting: value, intersectionRatio: value ? 1 : 0 }]); },
    end() { envelope.emit('animationend', { animationName: 'deliver-invite' }); },
  };
}

test('the invite plays once in view, completes, and only replays on request', () => {
  const s = setup();
  assert.equal(s.scene.dataset.state, 'waiting');
  s.visible(true);
  assert.equal(s.scene.dataset.state, 'sending');
  assert.equal(s.replay.hidden, true);
  s.end();
  assert.equal(s.scene.dataset.state, 'connected');
  assert.equal(s.status.textContent, 'You’re connected');
  s.visible(false); s.visible(true);
  assert.equal(s.scene.dataset.state, 'connected');
  s.replay.emit('click');
  assert.equal(s.scene.dataset.state, 'sending');
});

test('Reduce Motion shows the completed connection and never starts the invite', () => {
  const s = setup({ reduced: true });
  s.visible(true); s.replay.emit('click');
  assert.equal(s.scene.dataset.state, 'connected');
  assert.equal(s.replay.hidden, true);
  const live = setup();
  live.visible(true);
  live.motion.matches = true;
  live.motion.emit('change');
  assert.equal(live.scene.dataset.state, 'connected');
  assert.equal(live.replay.hidden, true);
});

test('leaving the section or hiding the tab finishes active motion', () => {
  const s = setup(); s.visible(true); s.visible(false);
  assert.equal(s.scene.dataset.state, 'connected');
  const hidden = setup({ hidden: true }); hidden.visible(true);
  assert.equal(hidden.scene.dataset.state, 'waiting');
  hidden.document.hidden = false; hidden.document.emit('visibilitychange');
  assert.equal(hidden.scene.dataset.state, 'sending');
  hidden.document.hidden = true; hidden.document.emit('visibilitychange');
  assert.equal(hidden.scene.dataset.state, 'connected');
});

test('older browsers keep the complete illustration and a working explicit replay', () => {
  const s = setup({ observer: false });
  assert.equal(s.scene.dataset.state, 'connected');
  assert.equal(s.replay.hidden, false);
  s.replay.emit('click'); s.end();
  assert.equal(s.scene.dataset.state, 'connected');
});

test('the site preserves the original onboarding portraits', async () => {
  const originals = {'ari': '9a65855201892cef962d5b6885c3c1e7618e51e12dcb6eae023acc93b87f4e00', 'sam': 'dc42784d43f39de4a0b37c4bd95c2b010adf3b0b478ef3bdc6933c2e56cf40c9'};
  for (const [name, hash] of Object.entries(originals)) {
    const web = await readFile(new URL(`../../landing-site/assets/friend-${name}.png`, import.meta.url));
    assert.equal(createHash('sha256').update(web).digest('hex'), hash);
  }
});
