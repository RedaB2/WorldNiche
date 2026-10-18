# WorldNiche landing page

Buildless HTML, CSS, and JavaScript. Serve `index.html` at `/` and this directory's static contents at `/landing/`. Invite routes keep their existing HTML and assets.

## App media contract

- `/landing/assets/app-demo.mp4`: real, silent, portrait app recording (recommended H.264, fast-start MP4, 1206:2622 aspect ratio).
- `/landing/assets/app-poster.jpg`: matching actual screenshot, same aspect ratio, no account details.
- `/landing/assets/logo.png` and `logo-dark.png`: the application logos.
- `/landing/assets/hand-phone.png`: original generated transparent hand/phone cutout, 1024×1536. The real video is registered to the blank screen using percentages in CSS. The entire composition rises and turns slightly with scroll; Reduce Motion removes the transform.

The video has native controls and an accessible pause/play button, plays inline when visible, and respects Reduce Motion. Manual pause persists across scrolling. No signup, analytics, cookies, or invented App Store link. The current development availability is stated beside the preview CTA. Replace that sentence and CTA with the real App Store destination only when available.

The included 13-second 660×1434 H.264 video is an actual app screen recording. It moves from Morocco to Spain and opens the Powder Day cultural reading. The expandable **Preview credits** footer links the Wikimedia photo author/source/license and Wikipedia text sources/licenses. Preserve those credits when reusing this recording.

The main page uses `/landing/` asset URLs to avoid colliding with invite styles and scripts. The existing invite worker/router is responsible for serving the landing page and these static assets. Do not replace invitation routing or the Apple association document.
