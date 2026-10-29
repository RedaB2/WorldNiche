# App Store media

The first listing, with Morocco as the demo destination. Captured from WorldNiche in the simulator on October 29, 2026, then framed with the app's logo, serif type and pine, cream and sage palette.

## Assets

| Set | Files | Size |
| --- | --- | --- |
| iPhone | 5 screenshots | 1320 x 2868 |
| iPad | 3 screenshots | 2064 x 2752 |
| iPhone Duo, unfolded horizontally | 2 screenshots | 2034 x 1398 |
| iPhone preview | 20-second Morocco demo | 886 x 1920, 30 fps |

All ten screenshots and the preview have finished processing in App Store Connect for version 1.0, English (U.S.). The preview shows the globe rotating and Morocco's overview opening. It uses H.264 video and a silent AAC stereo track, with no commercial music. Its final frame is held briefly for readability.

`source/` holds the actual UI captures. Journal notes and the Mira/Jun friend profiles are simulator fixtures, not real users or production records. The journal has 20 explored countries and 10 saved countries with notes. Mira uses the existing girl illustration from onboarding. The Duo captures use the active inner display (`primary-1`); the outer display is blank when unfolded. No app UI was painted into these screenshots.

Run `swift marketing/app-store/render.swift` from the repository root on macOS to rebuild the posters. Rendered screenshots are opaque sRGB PNGs. The renderer preserves each screen's proportions. The current App Store CLI recognizes the iPhone and iPad sizes; the Duo sizes were checked against Apple's upload page and uploaded there.

## Source credits

The Morocco Local Lens screenshot and video include [Ary-qrichlat ronds michots.JPG](https://commons.wikimedia.org/wiki/File:Ary-qrichlat_ronds_michots.JPG) by [Lucyin](https://commons.wikimedia.org/wiki/User:Lucyin), licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). The photo is resized and cropped by the app's image card. Those photo adaptations retain the same license. The visible creator and license credit are preserved.

The cultural excerpt comes from [Qrashel](https://en.wikipedia.org/wiki/Qrashel), by Wikipedia contributors under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). See the article's [revision history](https://en.wikipedia.org/w/index.php?title=Qrashel&action=history) for attribution. The app supplies a separate heading and discussion prompt. No endorsement by the contributors is implied.

These credits cover the captured cultural material. Rights for other live feeds and artwork remain part of the [release checklist](../../docs/app-store-readiness.md).
