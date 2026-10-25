# Profile checks release

This work is on the development branch. It has not been deployed to Supabase or distributed through TestFlight.

## Intended behavior

- Profile edits appear immediately to their owner.
- With separate permission, OpenAI checks the saved name or photo. Passing content becomes visible to friends automatically.
- Open friend screens refresh every five seconds while active. A temporary photo failure retries without requiring navigation.
- Declining automatic checks keeps human review available. An outage keeps the previous approved profile visible to friends.
- Consent withdrawal, a newer edit, deletion, or a restriction prevents an old result from publishing.

## Verified locally

- 61 moderation handler tests passed.
- All 8 isolated database test groups passed, including friend access, blocking, deletion, consent and concurrent changes.
- The Edge function passed Deno type checking.
- 333 native social checks and 33 avatar checks passed.
- All 5 moderation UI scenarios passed on iOS 26.5.
- The complete iOS 27.0 simulator suite passed: 18 tests, no failures or skips. The final photo assertion also passed separately.
- All 3 globe and adaptive layout tests passed on iOS 26.5. The new pinch test also passed on the open Duo.
- 26 website behavior and packaging tests passed.
- Repository secret scanning passed without findings.

The actual on-device companion response test passed twice on iOS 27.0. The iOS 26.5 simulator reports a host model compatibility failure. Duo photo recovery and landscape layout were verified directly in Device Hub. Local mocks establish behavior, not connectivity to the deployed provider.

XCTest on the Duo inner display accepted rotation commands without rotating its active interface. Its full-screen captures were black, and row captures were upside down despite upright orientation metadata. The assertions remain intact; the photo check now samples both possible row-end avatar positions. These tooling failures are recorded separately from the passing iOS 27.0 suite. Closing the Duo also left XCTest unable to locate its tab bar, so that attempted outer-display run is not passing evidence.

## Deployment gates

1. Reconnect OpenAI Platform and provision the backend-only key through secure setup.
2. Apply migrations 005 and 006, deploy the worker, and configure its scoped secret and scheduled retries.
3. Verify the deployed flow using disposable identities and synthetic content, including friend visibility and cleanup.
4. Publish the matching privacy, security and community disclosures.
5. Finish simulator verification, remove diagnostic instrumentation, and build the next signed TestFlight release.

No real profile content has been sent to OpenAI by these local tests. No provider credential belongs in the app, website or repository.

## iPhone Duo

The landing page pairs a separate, unfolded landscape mockup with a real landscape simulator recording before publication. The original iPhone preview remains available. App Store Connect's Duo optimization badge requires Duo screenshots; there is no separate TestFlight compatibility switch. See [Apple's Duo submission guidance](https://developer.apple.com/news/?id=kkphp5qo) and [screenshot sizes](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

Apple documents that the simulator's Foundation Models depend on compatible host and simulator versions. A model failure on an older simulator must be reported separately from UI test results. See [Apple's simulator guidance](https://developer.apple.com/forums/thread/787445).
