(() => {
  'use strict';
  const control = document.getElementById('playback-control');
  const label = control.querySelector('.playback-label');
  const icon = control.querySelector('.playback-icon');
  const fallback = document.getElementById('video-fallback');
  const download = document.getElementById('video-download');
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const hand = document.getElementById('handheld');
  const stage = document.getElementById('preview');
  const devices = [
    { key: 'iphone', name: 'iPhone', video: document.getElementById('app-video') },
    { key: 'duo', name: 'iPhone Duo', video: document.getElementById('duo-video') },
  ].map(device => ({
    ...device,
    frame: document.getElementById(`preview-${device.key}`),
    button: document.getElementById(`device-${device.key}`),
    source: device.video.querySelector('source'),
    userPaused: false,
    motionPermission: false,
    pendingPlay: false,
    failed: false,
    attempt: 0,
  }));
  let active = devices[0];
  let inView = false;

  document.getElementById('year').textContent = String(new Date().getFullYear());

  function isVisible(device) {
    return device === active && inView && !document.hidden;
  }

  function mayPlay(device) {
    return isVisible(device) && !device.failed && !device.userPaused
      && (!reducedMotion.matches || device.motionPermission);
  }

  function updateControl() {
    const playing = !active.video.paused || active.pendingPlay;
    label.textContent = `${playing ? 'Pause' : 'Play'} the preview`;
    icon.textContent = playing ? 'Ⅱ' : '▶';
    control.setAttribute('aria-label', `${playing ? 'Pause' : 'Play'} the ${active.name} preview`);
    control.setAttribute('aria-controls', active.video.id);
    control.hidden = active.failed;
    fallback.hidden = !active.failed;
    download.setAttribute('href', active.source.getAttribute('src') || active.source.dataset.src);
    download.textContent = `Open the ${active.name} video`;
  }

  function pause(device) {
    // Invalidate pending play promises even when the media is still paused.
    device.attempt++;
    device.pendingPlay = false;
    device.video.pause();
  }

  async function play(device) {
    if (!mayPlay(device) || device.pendingPlay || !device.video.paused) return;
    const attempt = ++device.attempt;
    device.pendingPlay = true;
    updateControl();
    try {
      await device.video.play();
    } catch {
      // Autoplay can be denied. The explicit play button remains available.
    } finally {
      if (attempt === device.attempt) device.pendingPlay = false;
      // A delayed media promise must never restart a hidden or paused preview.
      if (!mayPlay(device) && !device.video.paused) pause(device);
      updateControl();
    }
  }

  function reconcilePlayback() {
    for (const device of devices) {
      if (mayPlay(device)) void play(device);
      else pause(device);
    }
    updateControl();
  }

  function select(device) {
    if (device === active) return;
    const previous = active;
    active = device;
    pause(previous);
    for (const item of devices) {
      item.frame.hidden = item !== active;
      item.button.setAttribute('aria-pressed', String(item === active));
    }
    // The Duo recording is fetched only after someone selects its preview.
    if (!device.source.getAttribute('src')) {
      device.failed = false;
      device.video.controls = false;
      device.source.setAttribute('src', device.source.dataset.src);
      device.video.load();
    }
    reconcilePlayback();
  }

  for (const device of devices) {
    // Native controls remain in the HTML and return if this media fails.
    device.video.controls = false;
    device.button.addEventListener('click', () => select(device));
    device.video.addEventListener('play', () => {
      if (!isVisible(device) || (!device.failed && !mayPlay(device))) pause(device);
      updateControl();
    });
    device.video.addEventListener('pause', updateControl);
    const failedVideo = () => {
      // Browsers can reject an empty lazy source before its first selection.
      if (!device.source.getAttribute('src')) return;
      device.failed = true;
      pause(device);
      device.video.controls = true;
      updateControl();
    };
    device.video.addEventListener('error', failedVideo);
    device.source.addEventListener('error', failedVideo);
    if (device.video.error) failedVideo();
  }

  control.addEventListener('click', () => {
    if (!active.video.paused || active.pendingPlay) {
      active.userPaused = true;
      pause(active);
    } else {
      active.userPaused = false;
      active.motionPermission = reducedMotion.matches;
      void play(active);
    }
    updateControl();
  });

  document.getElementById('device-selector').hidden = false;
  if (typeof IntersectionObserver === 'function') {
    const observer = new IntersectionObserver(([entry]) => {
      inView = entry.isIntersecting && entry.intersectionRatio >= 0.25;
      reconcilePlayback();
    }, { threshold: [0, 0.25] });
    observer.observe(stage);
  } else {
    // Older browsers still have an explicit playback control.
    inView = true;
  }
  document.addEventListener('visibilitychange', reconcilePlayback);
  reducedMotion.addEventListener('change', () => {
    // A newly enabled preference needs a new explicit playback choice.
    for (const device of devices) device.motionPermission = false;
    reconcilePlayback();
    queuePosition();
  });
  updateControl();

  // Keep the whole hand and real screen together during the perspective turn.
  let queuedFrame = false;
  function positionHand() {
    queuedFrame = false;
    if (reducedMotion.matches) {
      hand.style.transform = 'none';
      return;
    }
    const bounds = stage.getBoundingClientRect();
    const progress = Math.max(0, Math.min(1, (window.innerHeight - bounds.top) / (window.innerHeight + bounds.height * 0.35)));
    const rise = 110 * (1 - progress) - 25 * progress;
    const turn = -10 + progress * 16;
    const lean = -3 + progress * 5;
    hand.style.transform = `translate3d(0, ${rise.toFixed(2)}px, 0) rotateY(${turn.toFixed(2)}deg) rotateZ(${lean.toFixed(2)}deg)`;
  }
  function queuePosition() {
    if (!queuedFrame) {
      queuedFrame = true;
      window.requestAnimationFrame(positionHand);
    }
  }
  window.addEventListener('scroll', queuePosition, { passive: true });
  window.addEventListener('resize', queuePosition, { passive: true });
  positionHand();
})();
