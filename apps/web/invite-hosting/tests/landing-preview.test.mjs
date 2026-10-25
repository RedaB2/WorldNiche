import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const landing = new URL('../../landing-site/', import.meta.url);
const script = await readFile(new URL('landing.js', landing), 'utf8');
const html = await readFile(new URL('index.html', landing), 'utf8');
const css = await readFile(new URL('style.css', landing), 'utf8');

class Element {
  constructor(id, attrs = {}) {
    this.id = id;
    this.attrs = new Map(Object.entries(attrs));
    this.listeners = new Map();
    this.children = new Map();
    this.style = {};
    this.dataset = {};
    this.hidden = false;
    this.textContent = '';
  }
  addEventListener(type, handler) {
    const handlers = this.listeners.get(type) || [];
    handlers.push(handler);
    this.listeners.set(type, handlers);
  }
  emit(type, details = {}) {
    for (const handler of this.listeners.get(type) || []) handler({ target: this, ...details });
  }
  setAttribute(name, value) { this.attrs.set(name, String(value)); }
  getAttribute(name) { return this.attrs.get(name) ?? null; }
  querySelector(selector) { return this.children.get(selector) ?? null; }
  getBoundingClientRect() { return { top: 100, height: 900 }; }
}

class Video extends Element {
  constructor(id, source) {
    super(id);
    this.children.set('source', source);
    this.paused = true;
    this.controls = true;
    this.playCalls = 0;
    this.loadCalls = 0;
    this.pending = [];
    this.deferPlay = false;
    this.rejectPlay = false;
  }
  play() {
    this.playCalls++;
    if (this.rejectPlay) return Promise.reject(new Error('Autoplay blocked'));
    if (this.deferPlay) return new Promise((resolve, reject) => this.pending.push({ resolve, reject }));
    this.paused = false;
    this.emit('play');
    return Promise.resolve();
  }
  resolvePlay() {
    const pending = this.pending.shift();
    assert.ok(pending, 'A delayed play request must exist');
    this.paused = false;
    this.emit('play');
    pending.resolve();
  }
  pause() {
    const wasPlaying = !this.paused;
    this.paused = true;
    if (wasPlaying) this.emit('pause');
  }
  load() { this.loadCalls++; this.error = null; }
}

function setup({ reduced = false, hidden = false, observer = true, initialDuoError = false } = {}) {
  const ids = new Map();
  const add = (id, attrs) => { const element = new Element(id, attrs); ids.set(id, element); return element; };
  const phoneSource = new Element('phone-source', { src: '/landing/assets/app-demo.mp4?v=test' });
  const duoSource = new Element('duo-source');
  duoSource.dataset.src = '/landing/assets/duo-demo.mp4?v=test';
  const phone = new Video('app-video', phoneSource);
  const duo = new Video('duo-video', duoSource);
  if (initialDuoError) duo.error = { code: 4 };
  ids.set(phone.id, phone);
  ids.set(duo.id, duo);
  add('preview-iphone');
  add('preview-duo').hidden = true;
  add('device-iphone', { 'aria-pressed': 'true' });
  add('device-duo', { 'aria-pressed': 'false' });
  add('device-selector').hidden = true;
  const control = add('playback-control');
  control.hidden = true;
  control.children.set('.playback-label', new Element('label'));
  control.children.set('.playback-icon', new Element('icon'));
  const fallback = add('video-fallback');
  fallback.hidden = true;
  const download = add('video-download');
  fallback.children.set('a', download);
  add('year');
  add('handheld');
  add('preview');
  const media = new Element('motion');
  media.matches = reduced;
  const document = new Element('document');
  document.hidden = hidden;
  document.getElementById = id => ids.get(id);
  const window = new Element('window');
  window.innerHeight = 900;
  window.matchMedia = () => media;
  window.requestAnimationFrame = callback => { callback(); return 1; };
  let onIntersection;
  class Observer {
    constructor(callback) { onIntersection = callback; }
    observe() {}
  }
  const context = { document, window, Date, console };
  if (observer) context.IntersectionObserver = Observer;
  vm.runInNewContext(script, context);
  return {
    ids, phone, duo, phoneSource, duoSource, control, fallback, download, media, document, window,
    click: id => ids.get(id).emit('click'),
    visible: value => onIntersection?.([{ isIntersecting: value, intersectionRatio: value ? 1 : 0 }]),
    motion: value => { media.matches = value; media.emit('change'); },
    hidden: value => { document.hidden = value; document.emit('visibilitychange'); },
  };
}

const settle = async () => { await Promise.resolve(); await Promise.resolve(); await Promise.resolve(); };

test('the default stays iPhone, with a native no-JavaScript fallback and lazy Duo source', () => {
  assert.match(html, /id="app-video"[^>]*controls/);
  assert.match(html, /id="device-selector"[^>]*hidden/);
  assert.match(html, /id="preview-duo"[^>]*hidden/);
  assert.match(html, /data-src="\/landing\/assets\/duo-demo\.mp4/);
  assert.match(html, /<noscript>[\s\S]*duo-demo\.mp4/);
  assert.match(html, /https:\/\/testflight\.apple\.com\/join\/kqpQhYFw/);
  const s = setup();
  assert.equal(s.duoSource.getAttribute('src'), null);
  assert.equal(s.duo.loadCalls, 0);
  assert.equal(s.ids.get('device-selector').hidden, false);
  assert.equal(s.phone.controls, false);
});

test('switching loads Duo once, pauses iPhone, and updates accessible controls', async () => {
  const s = setup();
  s.visible(true);
  await settle();
  assert.equal(s.phone.paused, false);
  s.click('device-duo');
  await settle();
  assert.equal(s.phone.paused, true);
  assert.equal(s.duo.paused, false);
  assert.equal(s.duo.loadCalls, 1);
  assert.equal(s.duoSource.getAttribute('src'), s.duoSource.dataset.src);
  assert.equal(s.ids.get('preview-iphone').hidden, true);
  assert.equal(s.ids.get('preview-duo').hidden, false);
  assert.equal(s.ids.get('device-duo').getAttribute('aria-pressed'), 'true');
  assert.equal(s.ids.get('device-iphone').getAttribute('aria-pressed'), 'false');
  assert.equal(s.control.getAttribute('aria-controls'), 'duo-video');
  s.click('device-iphone');
  s.click('device-duo');
  await settle();
  assert.equal(s.duo.loadCalls, 1);
  assert.equal(s.phone.paused, true);
});

test('an empty lazy source error does not poison the first Duo selection', async () => {
  const s = setup();
  s.visible(true);
  s.duoSource.emit('error');
  s.duo.emit('error');
  assert.equal(s.duoSource.getAttribute('src'), null);
  assert.equal(s.duo.loadCalls, 0);
  assert.equal(s.duo.controls, false);
  s.click('device-duo');
  await settle();
  assert.equal(s.duo.loadCalls, 1);
  assert.equal(s.duo.paused, false);
  assert.equal(s.fallback.hidden, true);
  assert.equal(s.control.hidden, false);
  assert.equal(s.duo.controls, false);
});

test('a lazy video error present before script setup clears when its first real source loads', async () => {
  const s = setup({ initialDuoError: true });
  s.visible(true);
  s.click('device-duo');
  await settle();
  assert.equal(s.duo.error, null);
  assert.equal(s.duo.paused, false);
  assert.equal(s.fallback.hidden, true);
  assert.equal(s.control.hidden, false);
  assert.equal(s.duo.controls, false);
  s.duoSource.emit('error');
  assert.equal(s.fallback.hidden, false, 'An error after assigning the actual media must still be shown');
  assert.equal(s.duo.controls, true);
  assert.equal(s.duo.paused, true);
});

test('manual pause survives scrolling, visibility changes, and device switching', async () => {
  const s = setup();
  s.visible(true);
  await settle();
  s.click('playback-control');
  s.visible(false);
  s.visible(true);
  s.hidden(true);
  s.hidden(false);
  s.click('device-duo');
  await settle();
  assert.equal(s.duo.paused, false);
  s.click('device-iphone');
  await settle();
  assert.equal(s.phone.paused, true);
  assert.equal(s.phone.playCalls, 1);
  s.click('playback-control');
  await settle();
  assert.equal(s.phone.paused, false);
});

test('manual pause is independent for each device', async () => {
  const s = setup();
  s.visible(true);
  s.click('device-duo');
  await settle();
  s.click('playback-control');
  s.click('device-iphone');
  await settle();
  assert.equal(s.phone.paused, false);
  s.click('device-duo');
  await settle();
  assert.equal(s.duo.paused, true);
});

test('Reduce Motion prevents autoplay but permits an explicit play for only that device', async () => {
  const s = setup({ reduced: true });
  s.visible(true);
  assert.equal(s.phone.playCalls, 0);
  assert.equal(s.ids.get('handheld').style.transform, 'none');
  s.click('playback-control');
  await settle();
  assert.equal(s.phone.paused, false);
  s.click('device-duo');
  await settle();
  assert.equal(s.duo.playCalls, 0);
  s.click('device-iphone');
  await settle();
  assert.equal(s.phone.paused, false);
});

test('turning Reduce Motion on live pauses previous autoplay and requires a fresh play', async () => {
  const s = setup();
  s.visible(true);
  await settle();
  s.motion(true);
  assert.equal(s.phone.paused, true);
  assert.equal(s.ids.get('handheld').style.transform, 'none');
  s.visible(false);
  s.visible(true);
  await settle();
  assert.equal(s.phone.paused, true);
  s.click('playback-control');
  await settle();
  assert.equal(s.phone.paused, false);
  s.motion(false);
  assert.match(s.ids.get('handheld').style.transform, /translate3d/);
});

test('hidden documents and offscreen previews never autoplay or switch-play', async () => {
  const s = setup({ hidden: true });
  s.visible(true);
  s.click('device-duo');
  await settle();
  assert.equal(s.duo.playCalls, 0);
  s.hidden(false);
  await settle();
  assert.equal(s.duo.paused, false);
  s.visible(false);
  s.click('device-iphone');
  await settle();
  assert.equal(s.phone.playCalls, 0);
  assert.equal(s.duo.paused, true);
  s.visible(true);
  await settle();
  assert.equal(s.phone.paused, false);
});

test('a late play resolution cannot restart a device after switching away', async () => {
  const s = setup();
  s.phone.deferPlay = true;
  s.visible(true);
  s.click('device-duo');
  await settle();
  s.phone.resolvePlay();
  await settle();
  assert.equal(s.phone.paused, true);
  assert.equal(s.duo.paused, false);
  assert.match(s.control.getAttribute('aria-label'), /iPhone Duo/);
});

test('a late play resolution cannot override manual pause or document hiding', async () => {
  const s = setup();
  s.phone.deferPlay = true;
  s.visible(true);
  s.click('playback-control');
  s.phone.resolvePlay();
  await settle();
  assert.equal(s.phone.paused, true);
  s.click('playback-control');
  s.hidden(true);
  s.phone.resolvePlay();
  await settle();
  assert.equal(s.phone.paused, true);
});

test('autoplay rejection leaves a working manual play control', async () => {
  const s = setup();
  s.phone.rejectPlay = true;
  s.visible(true);
  await settle();
  assert.match(s.control.getAttribute('aria-label'), /^Play/);
  assert.equal(s.fallback.hidden, true);
  s.phone.rejectPlay = false;
  s.click('playback-control');
  await settle();
  assert.equal(s.phone.paused, false);
});

test('media failure exposes native controls and the active device download only', async () => {
  const s = setup();
  s.visible(true);
  s.click('device-duo');
  await settle();
  s.duoSource.emit('error');
  assert.equal(s.control.hidden, true);
  assert.equal(s.fallback.hidden, false);
  assert.equal(s.duo.controls, true);
  assert.equal(s.download.getAttribute('href'), s.duoSource.dataset.src);
  s.click('device-iphone');
  await settle();
  assert.equal(s.fallback.hidden, true);
  assert.equal(s.control.hidden, false);
  assert.equal(s.phone.controls, false);
  s.duo.emit('error');
  assert.equal(s.fallback.hidden, true, 'An inactive error must not replace the visible device controls');
  s.click('device-duo');
  assert.equal(s.fallback.hidden, false);
});

test('without IntersectionObserver the native preview remains operable', async () => {
  const s = setup({ observer: false, reduced: true });
  s.click('playback-control');
  await settle();
  assert.equal(s.phone.paused, false);
});

test('phone registration remains unchanged and Duo uses a separate mask and touch targets', () => {
  assert.match(css, /left:27\.76%;top:3%;width:43\.85%;height:61\.44%/);
  assert.match(css, /\.device-preview-duo \.phone\{[^}]*left:8\.20%/);
  assert.match(css, /\.device-preview-duo \.app-video\{object-fit:contain/);
  assert.match(css, /\.app-stage:has\(\.device-preview-duo:not\(\[hidden\]\)\) \.handheld\{width:min\(660px,calc\(100vw - 24px\)\)/);
  const duoMask = css.match(/\.device-preview-duo \.phone\{[^}]*width:([\d.]+)%;height:([\d.]+)%/);
  assert.ok(duoMask);
  assert.ok(Number(duoMask[1]) * 1024 > Number(duoMask[2]) * 1536, 'The unfolded Duo screen must be landscape');
  assert.match(css, /\.device-selector button\{[^}]*min-height:44px/);
  assert.match(css, /object-fit:cover/);
  assert.doesNotMatch(script + css + html, /\u2014/);
});
