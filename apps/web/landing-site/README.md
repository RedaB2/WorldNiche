# WorldNiche landing page

Buildless HTML, CSS, and JavaScript. Serve `index.html` at `/` and this directory's static contents at `/landing/`. Invite routes keep their existing HTML and assets.

## App media contract

- `/landing/assets/app-demo.mp4`: real, silent, portrait app recording (recommended H.264, fast-start MP4, 1206:2622 aspect ratio).
- `/landing/assets/app-poster.jpg`: matching actual screenshot, same aspect ratio, no account details.
- `/landing/assets/duo-demo.mp4`: a real, silent recording of WorldNiche on the horizontally unfolded iPhone Duo inner display, using its 2853:2007 landscape aspect ratio. Never substitute a stretched conventional iPhone recording.
- `/landing/assets/duo-poster.jpg`: matching Duo screenshot, without account details.
- `/landing/assets/logo.png` and `logo-dark.png`: transparent masks tinted by CSS. The opaque `app-icon.png`, `apple-touch-icon.png`, and `favicon.png` are used for sharing and browser icons.
- `/landing/assets/hand-phone.png`: original generated transparent hand/phone cutout, 1024×1536. The real video is registered to the blank screen using percentages in CSS. The entire composition rises and turns slightly with scroll; Reduce Motion removes the transform.
- `/landing/assets/hand-duo.png`: a separate original generated transparent hand holding a horizontally unfolded Duo, on a 1024×1536 portrait canvas. CSS narrows this decorative frame by 5.65% to match the real inner display, with an independently aligned screen mask. The mask matches the recording's 960:676 ratio, so `object-fit: cover` fills it without black side bars, stretching the app or cropping its controls and source credits. The wider device scales to fit mobile screens. Keep the original iPhone mask and its two-pixel bleed unchanged when adjusting the Duo composite.

The preview starts on iPhone. An accessible button group switches to iPhone Duo and fetches that recording on its first selection. Each device remembers its own manual pause across scrolling, switching, and background tabs. Only the visible preview can play. Reduce Motion removes the scroll transform and requires an explicit play choice; turning it on live pauses autoplay. Failed media exposes native controls and a download link for the selected device. Without JavaScript, the iPhone keeps native controls and the Duo recording has a direct link.

The page links to the public TestFlight beta. No signup, analytics, or cookies. Publish the Duo compatibility wording and preview only after the actual Duo recording is present and the app passes its Duo simulator checks. Replace the beta link with a real App Store destination only when available.

The included 15-second 660×1434 H.264 video is an actual app screen recording. It moves from Morocco to the Medfouna local reading and then the Atlas. The expandable **Preview credits** footer links the Wikipedia text source and license. Preserve those credits when reusing this recording.

The Duo preview is a separate 29.53-second, 960×676 H.264 recording of the simulator's inner display in landscape. It shows the globe, Morocco's Mawazine reading, and the Atlas. The matching poster is an actual screenshot. Its source and license are included in **Preview credits** too.

The main page uses `/landing/` asset URLs to avoid colliding with invite styles and scripts. The existing invite worker/router is responsible for serving the landing page and these static assets. Do not replace invitation routing or the Apple association document.

Run the playback and hosting tests with `npm --prefix apps/web test` from the repository root. Before publishing, check both video masks at 200% zoom, desktop and narrow mobile layouts, keyboard selection, playback failure, and Reduce Motion in the browser with the final recordings.

The hosting build rejects a Duo preview until its frame, video, and poster are all imported and nonempty. Artifact validation also verifies the exact bytes, content types, and range responses of those three assets. Pages without a Duo reference keep the original media contract.
