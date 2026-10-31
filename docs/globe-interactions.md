# Globe interaction review

October 30, 2026. Branch: `feat/globe-interactions`, based on `24d1ac0`.

This work is for a future update. The submitted build 8, `v1.0.0` tag, App Store metadata and version/build settings are unchanged. No archive, upload or release was performed. Assign the next build number when preparing the eventual update.

## Behavior

- The existing globe texture, palette, lighting and starting scale are preserved. Zoom now reaches 400% through a circular window, avoiding the previous rectangular crop. At close zoom the window shows part of the same sphere, rather than shrinking the entire planet back into view.
- A one-finger drag turns longitude and latitude with north kept upright. Pitch stops before either pole can flip over. Turning becomes finer when zoomed in, with shorter inertia.
- Two fingers move the view horizontally and vertically. Pinch zoom follows the point between the fingers and can run alongside movement. Movement is bounded so the globe cannot disappear. The reset button restores the starting scale and centers the selected country.
- Tapping a country changes its marker and the existing country-name button without recentering or opening details. Tap that button to open discoveries. The existing journal visit behavior remains. Take Me Somewhere still picks a country, restores the framing and shows its name first.
- The onboarding practice globe shares these gestures and still does not select or open countries. Reduced Motion continues to suppress navigation and inertia animations.

## Implementation to review

`WorldGlobeView.swift` owns gesture coordination, the circular mask, camera changes and rendering. `GlobeInteraction.swift` contains bounded camera and orientation math. `RootView.swift` changes selection presentation and adds reset. Globe materials and geographic hit testing are retained.

`GlobeTestGestures.h/.m` is compiled only into the UI test runner. XCTest has no public two-finger drag API, so this helper uses its event synthesis classes to deliver actual simultaneous touch paths. It is not linked into the shipping app and may need adaptation when Xcode changes. No runtime gesture hooks or test-only behavior were added to the app.

## Verification

- `bash scripts/check.sh swift`: all suites passed, including globe bounds, anchored zoom, reset, interruption and 2,000 repeated diagonal turns.
- `bash scripts/check.sh private`: passed. `git diff --check`: passed.
- Eight affected UI scenarios passed on iPhone 17 Pro (iOS 27.0) and the unfolded iPhone Duo simulator (iOS 27.1), with no failures or skips on either device. They cover country-name previews, details via the name button, Switzerland and Belgium selection at 400%, two-finger movement, combined pinch/movement, rotation afterward, reset, ocean/outside-circle taps, surprise navigation, accessibility text sizing and onboarding.

Run the same UI selection with XcodeBuildMCP's simulator test tool and these `extraArgs` (plus a device and derived-data path):

```text
CODE_SIGNING_ALLOWED=NO
-parallel-testing-enabled NO
-only-testing:WorldNicheUITests/GlobeInteractionUITests
-only-testing:WorldNicheUITests/AdaptiveLayoutUITests/testGlobePinchExtendsZoomAndStillSelectsTheVisibleCountry
-only-testing:WorldNicheUITests/WorldNicheUITests/testDiscoverGuidanceAppearsAboveInteractiveGlobe
-only-testing:WorldNicheUITests/WorldNicheUITests/testDiscoverGuidanceLargeTextKeepsCountryControlsAccessible
-only-testing:WorldNicheUITests/IntroInteractionUITests/testDemoGlobeCanTurnAndZoomWithoutOpeningACountry
```

Local evidence is ignored under `outputs/globe-interactions/`: `phone-verified.xcresult`, `duo-verified.xcresult`, `swift-checks.log`, and `globe-demo.mp4` (a 30-second recording of the phone simulator). The video shows small-country selection, two-finger movement, reset, opening details through the country name and rotation. It contains the same app runtime as the final checks; the test's drag coordinates were subsequently made less sensitive to device-specific gesture recognition slop.

One supplemental test outside the globe selection, `AdaptiveLayoutUITests/testAtlasCapitalSearchAndCountryPresentationInLandscapeWithLargeText`, failed to find Japan after searching Tokyo. The Atlas implementation and that test are unchanged. This failure has not been verified against the base commit and remains a separate follow-up; the full UI suite is not claimed to pass. The owner should also review the gesture feel on a physical device before the eventual release.
