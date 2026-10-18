(() => {
  'use strict';
  const video = document.getElementById('app-video');
  const control = document.getElementById('playback-control');
  const label = control.querySelector('.playback-label');
  const icon = control.querySelector('.playback-icon');
  const fallback = document.getElementById('video-fallback');
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const hand = document.getElementById('handheld');
  const stage = document.getElementById('preview');
  let userPaused = false;
  let manuallyStarted = false;
  let inView = false;
  let passivePause = false;

  document.getElementById('year').textContent = String(new Date().getFullYear());

  function updateControl() {
    label.textContent = video.paused ? 'Play the preview' : 'Pause the preview';
    icon.textContent = video.paused ? '▶' : 'Ⅱ';
    control.setAttribute('aria-label', label.textContent);
  }

  function failedVideo() {
    control.hidden = true;
    fallback.hidden = false;
    video.controls = true;
  }

  // Keep the hero screen clear while the accessible playback button is active.
  // Native controls remain available without JavaScript and if playback fails.
  video.controls = false;
  control.hidden = false;
  control.addEventListener('click', async () => {
    if (!video.paused) {
      userPaused = true;
      video.pause();
    } else {
      userPaused = false;
      manuallyStarted = true;
      try { await video.play(); } catch { updateControl(); }
    }
  });
  video.addEventListener('play', () => {
    userPaused = false;
    if (reducedMotion.matches) manuallyStarted = true;
    updateControl();
  });
  video.addEventListener('pause', () => {
    if (passivePause) passivePause = false;
    else userPaused = true;
    updateControl();
  });
  video.addEventListener('error', failedVideo);
  video.querySelector('source').addEventListener('error', failedVideo);

  // Keep data use and movement modest: only play while the demo is in view.
  // A user-requested preview still works with Reduce Motion enabled.
  const observer = new IntersectionObserver(async ([entry]) => {
    inView = entry.isIntersecting;
    if (!entry.isIntersecting) {
      pauseWhenHidden();
    } else if (!userPaused && (!reducedMotion.matches || manuallyStarted)) {
      try { await video.play(); } catch { updateControl(); }
    }
  }, { threshold: 0.35 });
  observer.observe(video);
  reducedMotion.addEventListener('change', () => {
    if (reducedMotion.matches && !manuallyStarted) pauseWhenHidden();
  });
  document.addEventListener('visibilitychange', async () => {
    if (document.hidden) pauseWhenHidden();
    else if (inView && !userPaused && (!reducedMotion.matches || manuallyStarted)) {
      try { await video.play(); } catch { updateControl(); }
    }
  });

  function pauseWhenHidden() {
    if (video.paused) return;
    passivePause = true;
    video.pause();
  }

  // Move the photograph and its real app screen as one surface, so their
  // registration stays exact during the small perspective turn.
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
  reducedMotion.addEventListener('change', queuePosition);
  positionHand();
})();
