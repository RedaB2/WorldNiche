# Globe interaction review

October 30, 2026. Branch: `feat/globe-interactions`, based on `24d1ac0`.

This work is for a future update. The submitted build 8, `v1.0.0` tag, App Store metadata and version/build settings are unchanged. Development builds are installed directly on the owner's RBDUO. No archive, upload or release was performed. Assign the next build number when preparing the eventual update.

## Behavior

- The cream, sage and pine palette, lighting, orthographic globe and starting composition are retained. At up to 400% zoom, the actual sphere extends beyond its original silhouette. Discover's canvas reaches the sides of its content area and gently fades into the page above and below, without a fixed circular crop.
- Country borders are spherical geometry with a thin width adjusted to the camera scale. They stay fine at close zoom instead of enlarging a raster stroke. Country fills and the subtle ocean grid retain the existing 4096 by 2048 texture; the change does not multiply texture memory.
- One finger grabs a geographic surface point and follows it, keeping north upright. At a pole or the horizon, the view carries any remaining movement so the grabbed point does not slip or flip the planet. Movement stops on release for precise selection.
- A pinch anchors the geography between the fingers, including when its midpoint moves. One gesture recognizer applies scale and translation from a shared touch snapshot, eliminating ordering differences between separate pinch and pan callbacks. Adding or lifting a finger starts a new snapshot without jumping.
- Two fingers also reposition the globe without changing zoom. Its center can leave the view. A reachable slice stays visible and the reset control remains available. One-finger drags in transparent corners scroll the page; a pinch may straddle the sphere when its midpoint is on the visible surface.
- Reset smoothly coordinates zoom, position and orientation, centering the selected country. Touching the sphere interrupts navigation at its visible state. Reduce Motion makes reset and surprise navigation immediate.
- Tapping a country updates its marker and name without moving the globe or opening details. Tap the name to open discoveries. The existing journal visit behavior remains. Take Me Somewhere restores the framing and previews the new country first.
- The onboarding practice globe shares the gestures and still does not select or open countries. The marker retains its capped screen size at close zoom.

## Implementation

`WorldGlobeView.swift` owns the unified touch recognizer, SceneKit rendering, border strips and main-thread navigation animation. Border segments are subdivided along the sphere and their width is controlled by a small geometry shader. `GlobeInteraction.swift` contains testable surface projection, north-upright orientation solving, combined pinch transforms, recoverable framing bounds and reset interpolation. `RootView.swift` presents the name preview and reset control.

`GlobeTestGestures.h/.m` is compiled only into the UI test runner. XCTest has no public two-finger drag API, so this helper uses its event synthesis classes to deliver simultaneous touch paths. It is not linked into the shipping app and may need adaptation when Xcode changes. No runtime gesture hooks or test-only behavior were added to the app.

## Verification

The reproducible affected UI selection is below. Run it with XcodeBuildMCP's simulator test tool, specifying the phone or unfolded Duo and a separate derived-data path:

```text
CODE_SIGNING_ALLOWED=NO
-parallel-testing-enabled NO
-only-testing:WorldNicheUITests/GlobeInteractionUITests
-only-testing:WorldNicheUITests/AdaptiveLayoutUITests/testGlobePinchExtendsZoomAndStillSelectsTheVisibleCountry
-only-testing:WorldNicheUITests/WorldNicheUITests/testDiscoverGuidanceAppearsAboveInteractiveGlobe
-only-testing:WorldNicheUITests/WorldNicheUITests/testDiscoverGuidanceLargeTextKeepsCountryControlsAccessible
-only-testing:WorldNicheUITests/IntroInteractionUITests/testDemoGlobeCanTurnAndZoomWithoutOpeningACountry
```

The eleven scenarios cover country previews/details, Switzerland and Belgium at 400%, combined off-center pinch/movement with Switzerland asserted at the moving midpoint, one-finger surface anchoring, offscreen-center recovery, page scrolling from transparent corners, zoom bounds, reset, surprise navigation, large text and onboarding. `testExplorationDemo` provides a reproducible recording sequence with screenshot attachments.

All `bash scripts/check.sh swift` suites pass, including 2,182 globe checks. These include geographic anchoring throughout 100 combined pinch samples, reversal, orientation solutions across latitudes/longitudes, framing bounds, reset interpolation and 2,000 diagonal turns.

Eleven affected UI scenarios passed with zero failures or skips on each of iPhone 17 Pro (iOS 27.0) and unfolded iPhone Duo (iOS 27.1). The first wider pass exposed a zoom-out gesture whose fingers started beyond the small sphere; accepting a pinch by its midpoint fixed it, and the full affected selection passed again on both devices. Rendered initial and close-up captures were inspected on both layouts.

`bash scripts/check.sh private`, staged Gitleaks and `git diff --check` pass. The final app was signed with the owner's Apple Development identity and existing RBDUO development profile, installed and launched on RBDUO. Signature, device eligibility and version 1.0 (8) were verified.

Fresh evidence is ignored under `outputs/globe-interactions/refinement/`: `phone-verified.xcresult`, `duo-verified.xcresult`, `demo.xcresult`, `globe-demo.mp4`, `swift-checks.log`, `private-checks.log` and `rbduo-final.log`. The video shows the starting globe, off-center pinch, fine borders at 400%, surface dragging, offscreen movement, coordinated reset and details through the country name. Earlier evidence remains under `outputs/globe-interactions/` for comparison.

The earlier supplemental `AdaptiveLayoutUITests/testAtlasCapitalSearchAndCountryPresentationInLandscapeWithLargeText` failure remains a separate follow-up. Atlas and that test's behavior are unchanged; it has not been verified against the base commit. The full UI suite is not claimed to pass.
