# Globe interaction review

October 31, 2026. Branch: `feat/globe-interactions`, based on `24d1ac0`.

This work is for a future update. The submitted build 8, `v1.0.0` tag, App Store metadata and version/build settings are unchanged. Development builds are installed directly on the owner's RBDUO. No archive, upload or release was performed. Assign the next build number when preparing the eventual update.

## Behavior

- The cream, sage and pine palette, lighting, orthographic globe and starting composition are retained. At up to 400% zoom, the actual sphere extends beyond its original silhouette. Discover's canvas reaches the sides of its content area and gently fades into the page above and below, without a fixed circular crop.
- Country borders are spherical geometry with a thin width adjusted to the camera scale. They stay fine at close zoom instead of enlarging a raster stroke. Country fills and the subtle ocean grid retain the existing 4096 by 2048 texture; the change does not multiply texture memory.
- One finger rotates the geography with north upright and never changes the camera scale or offset. This preserves both the starting composition and an intentionally shifted close-up. Near a pole or the horizon, angular movement is bounded by finger travel and the surface is re-grabbed on each sample so reversing does not accumulate lag. Movement stops on release for precise selection.
- A pinch anchors the geography between the fingers, including when its midpoint moves. One gesture recognizer applies scale and translation from a shared touch snapshot, eliminating ordering differences between separate pinch and pan callbacks. Adding or lifting a finger starts a new snapshot without jumping.
- Two fingers also reposition the globe without changing zoom. Its center can leave the view. A reachable slice stays visible and the reset control remains available. One-finger drags in transparent corners scroll the page; a pinch may straddle the sphere when its midpoint is on the visible surface.
- Reset smoothly coordinates zoom, position and orientation, centering the selected country. Touching the sphere interrupts navigation at its visible state. Reduce Motion makes reset and surprise navigation immediate.
- Tapping a country updates its marker and name without moving the globe or opening details. Tap the name to open discoveries. The existing journal visit behavior remains. Take Me Somewhere restores the framing and previews the new country first.
- The onboarding practice globe shares the gestures and still does not select or open countries. The marker retains its capped screen size at close zoom.

## Implementation

`WorldGlobeView.swift` owns the unified touch recognizer, SceneKit rendering, border strips and main-thread navigation animation. Border segments are subdivided along the sphere and their width is controlled by a small geometry shader. `GlobeInteraction.swift` contains testable surface projection, continuous north-upright surface dragging, combined pinch transforms, recoverable framing bounds and reset interpolation. The one-finger path only assigns orientation; viewport mutation is confined to two-finger navigation and explicit navigation/reset. `RootView.swift` presents the name preview and reset control.

`GlobeTestGestures.h/.m` is compiled only into the UI test runner. XCTest has no public two-finger drag API, so this helper uses its event synthesis classes to deliver simultaneous touch paths. It is not linked into the shipping app and may need adaptation when Xcode changes. No runtime gesture hooks or test-only behavior were added to the app.

## One-finger regression

The owner's recording exposed the globe translating during ordinary spins. A rendered UI regression reproduced a center-to-limb drag moving the sphere's horizontal midpoint from 200.83 to 259 points at unchanged 100% zoom. The one-finger handler had applied the difference between the desired and achievable surface positions to `viewport.move`. This fallback moved the camera whenever a north-upright rotation could not keep the grabbed point under the finger. Removing that correction alone made the regression pass.

Broader sampling also exposed a near-pole singularity: less than one point of finger travel could rotate longitude by over forty degrees. The production surface-drag function now limits angular change relative to finger travel in scene units and re-grabs from the current orientation on every sample. Normal drags retain exact surface tracking; pole and limb constraints cannot move the camera or produce an abrupt orientation jump. Touch-count changes still rebase from the visible viewport, and release has no inertia.

The earlier eleven UI scenarios checked zoom labels and country hits without measuring the rendered silhouette during aggressive spins. The old mathematical tests checked orientation separately from the coordinator's camera correction, using moderate latitudes for surface following. They therefore missed the position mutation. The new UI tests measure horizontal and vertical silhouette chords after repeated horizontal, vertical, diagonal and limb drags, verify an intentionally offscreen 400% frame, and deliver a continuous one-to-two-to-one-finger touch sequence. A delayed outline comparison also checks that release does not introduce drift.

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

The fourteen scenarios cover country previews/details, Switzerland and Belgium at 400%, combined off-center pinch/movement, precise one-finger country dragging, offscreen recovery, page scrolling from transparent corners, zoom bounds, reset, surprise navigation, large text and onboarding. The three new scenarios measure rendered framing through aggressive spins, an offscreen 400% close-up, and a continuous one-to-two-to-one-finger sequence. `testExplorationDemo` starts with aggressive one-finger spins before showing the retained zoom, movement and reset behavior.

All `bash scripts/check.sh swift` suites pass, including 204,802 globe assertions. The expanded surface-drag matrix crosses and reverses past the limb at seven latitudes, including views near both poles, at default zoom, maximum zoom and an intentionally shifted maximum-zoom frame. It checks finite, bounded angular response, north staying upright, no movement from a stationary finger, and precise geographic anchoring on ordinary paths.

All fourteen affected UI scenarios passed on each of iPhone 17 Pro (iOS 27.0) and unfolded iPhone Duo (iOS 27.1), across the full selection and focused reruns. Each full selection passed twelve scenarios. The two new outline tests initially failed because one path began on the overlaid country-name button and the pixel detector included faded or lightly lit land. The final tests start on exposed geography, also assert that the page did not scroll, exclude the 24-point page fade, and distinguish the sphere's lightest land from the page. Both outline scenarios then passed with zero failures or skips on each device. No app code changed during these test-harness corrections.

`bash scripts/check.sh private`, staged Gitleaks and `git diff --check` pass. The corrected app was signed with the owner's Apple Development identity and existing RBDUO development profile, installed and launched on RBDUO. The first launch was blocked by the device lock; after the owner unlocked it, launch succeeded with process ID 17301. Signature, device eligibility and version 1.0 (8) were verified.

Current evidence is ignored under `outputs/globe-interactions/spin-fix/`: `repro-phone.xcresult` records the original rendered failure; `isolated-fix-phone.xcresult` verifies removal of the camera correction; `pole-red.log` records the orientation discontinuity before its fix; `phone-verified.xcresult` and `duo-verified.xcresult` contain the full affected selections; `phone-framing.xcresult` and `duo-framing.xcresult` contain the final outline passes. `swift-checks.log`, `private-checks.log`, `rbduo-install.log`, `rbduo-launch-unlocked.log` and `device-verification.log` retain the other checks. The approximately 32-second `globe-demo.mp4` shows centered spins, anchored close-ups, fine borders at 400%, offscreen two-finger movement, coordinated reset and details through the country name. Earlier evidence remains under `outputs/globe-interactions/refinement/` for comparison.

The earlier supplemental `AdaptiveLayoutUITests/testAtlasCapitalSearchAndCountryPresentationInLandscapeWithLargeText` failure remains a separate follow-up. Atlas and that test's behavior are unchanged; it has not been verified against the base commit. The full UI suite is not claimed to pass.
