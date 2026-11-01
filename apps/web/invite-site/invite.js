// No tracking, API requests, cookies, analytics, or profile lookup on this page.
const match = /^\/invite\/([0-9a-f]{64})\/?$/.exec(window.location.pathname);
const button = document.getElementById('open-app');
if (match) {
  button.href = `worldniche://invite/${match[1]}`;
  button.hidden = false;
  document.getElementById('eyebrow').textContent = 'A FRIEND INVITED YOU';
  document.getElementById('connection-note').hidden = false;
} else if (window.location.pathname !== '/') {
  document.getElementById('eyebrow').textContent = 'LET’S FIND YOUR FRIEND';
  document.getElementById('message').textContent = 'This invitation link is incomplete. Ask your friend for a new one.';
}
