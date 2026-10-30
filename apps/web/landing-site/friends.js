(() => {
  'use strict';
  const scene = document.getElementById('friend-invite');
  if (!scene) return;
  const status = scene.querySelector('.connection-status');
  const replay = scene.querySelector('.connection-replay');
  const envelope = scene.querySelector('.connection-envelope');
  const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let inView = false;
  let played = false;

  function finish() {
    scene.dataset.state = 'connected';
    status.textContent = 'You’re connected';
    replay.hidden = motion.matches;
  }

  function play() {
    if (motion.matches || document.hidden || !inView) return;
    played = true;
    scene.dataset.state = 'sending';
    status.textContent = 'An invite is on its way';
    replay.hidden = true;
  }

  replay.addEventListener('click', play);
  envelope.addEventListener('animationend', event => {
    if (event.animationName === 'deliver-invite') finish();
  });
  motion.addEventListener('change', () => {
    played = true;
    finish();
  });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden && scene.dataset.state === 'sending') finish();
    else if (!document.hidden && inView && !played) play();
  });

  if (typeof IntersectionObserver === 'function' && !motion.matches) {
    scene.dataset.state = 'waiting';
    status.textContent = 'A little closer, wherever you are';
    new IntersectionObserver(([entry]) => {
      inView = entry.isIntersecting && entry.intersectionRatio >= 0.5;
      if (inView && !played) play();
      else if (!inView && scene.dataset.state === 'sending') finish();
    }, { threshold: [0, 0.5] }).observe(scene);
  } else {
    // Keep the completed connection visible without animation support.
    inView = true;
    played = true;
    finish();
  }
})();
