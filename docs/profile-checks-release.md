# Profile checks release

This work is on the development branch. Database migrations 005, 006 and 007, the guarded worker, its scoped credential and the schedules were installed in Supabase on October 27. Automatic moderation and its minute-based retry job are paused pending the OpenAI key and live verification. Daily reservation retention is active. The signed build 3 is prepared locally and has not been distributed through TestFlight.

## Intended behavior

- Profile edits appear immediately to their owner.
- With separate permission, OpenAI checks the saved name or photo. Passing content becomes visible to friends automatically.
- Open friend screens refresh every five seconds while active. A temporary photo failure retries without requiring navigation.
- Declining automatic checks keeps human review available. An outage keeps the previous approved profile visible to friends.
- Consent withdrawal, a newer edit, deletion, or a restriction prevents an old result from publishing.
- Account and shared provider quotas defer excess work. The minute-based worker resumes the newest accepted revision after cooldown; older pending revisions are replaced.
- Repeated failures stop after five provider attempts per revision. Accepted photo uploads have separate rolling limits and a clear retry message.

## Verification

- 81 moderation handler tests passed, including allowance denials, malformed budget responses, scheduled work and concurrent claim replay.
- 124 database abuse assertions passed, including concurrent reservations, all rolling limits, account deletion, upload churn and latest-photo/name cooldown recovery.
- Hosted schema checks confirmed the limits and server-only reservation permissions. The deployed worker returned 401 for anonymous and forged-worker requests, and 503 for missing provider configuration.
- A manual scheduled-worker dispatch authenticated through Vault and reached the deployed worker, which returned the expected 503 while the provider key is missing. Only managed database login roles were present, and the Data API exposed only `public` and `graphql_public`.
- All 8 isolated database test groups passed, including friend access, blocking, deletion, consent and concurrent changes.
- The Edge function passed Deno type checking.
- 348 native social checks and 54 avatar checks passed, including rejected uploads, preserved approved photos and explicit retry.
- All 5 moderation UI scenarios passed on iOS 26.5.
- The final October 27 iOS 27.0 simulator suite passed: 18 tests, no failures or skips. A new regression covers rotation past rejected regional candidates to a valid local music article while retaining country validation. The focused live test also passed separately.
- All 3 globe and adaptive layout tests passed on iOS 26.5. The new pinch test also passed on the open Duo.
- The photo recovery test passed on both the open landscape Duo and regular iPhone after its navigation helper was updated for the native sidebar.
- 29 website behavior and packaging tests passed, including empty lazy video sources and the Duo screen fit regression.
- Repository secret scanning passed without findings.
- Build 1.0 (3) was archived and exported with App Store distribution signing. Signature, production entitlements, Apple sign-in, Universal Links, icon and privacy manifest checks passed. No upload was performed.

The actual on-device companion response test passed twice on iOS 27.0. The iOS 26.5 simulator reports a host model compatibility failure. Duo photo recovery and landscape layout were verified directly in Device Hub. Local mocks establish behavior, not connectivity to the deployed provider.

XCTest on the Duo inner display accepted rotation commands without rotating its active interface. Its full-screen captures were black, and row captures were upside down despite upright orientation metadata. The assertions remain intact; the photo check samples both possible row-end avatar positions. The final landscape photo run passed with adaptive navigation. Rotation tooling failures are recorded separately from the passing iOS 27.0 suite. Closing the Duo also left XCTest unable to locate its tab bar, so that earlier attempted outer-display run is not passing evidence.

## Deployment gates

1. Provision the backend-only key through secure setup. Verify moderation-only key permissions and project spend protection.
2. Configure the provider and enable `wn_private.profile_check_limits.enabled` for controlled live verification. The scoped credential, Vault entries and daily retention are installed.
3. Verify the deployed flow using disposable identities and synthetic content, including friend visibility and cleanup. Then activate the `worldniche-profile-checks` cron job and verify a scheduled run.
4. Publish the matching privacy, security and community disclosures.
5. Upload the verified signed build and verify its availability in the public TestFlight group.

No real profile content has been sent to OpenAI by these local tests. No provider credential belongs in the app, website or repository.

## iPhone Duo

The published landing page pairs a separate, unfolded landscape mockup with a real 29.53-second landscape simulator recording. The original iPhone preview remains available. Desktop and 390-pixel mobile browser checks confirmed both screen masks, switching, keyboard selection, playback and no horizontal overflow. The hosting artifact passed exact-byte and video range validation. The live legal pages retain the existing disclosures until the new moderation backend is deployed.

Site version 9 fixes the Duo's black side edges by matching its decorative frame and screen mask to the recording. The full app image is preserved without cropping or stretching. Live desktop and mobile checks passed.

App Store Connect's Duo optimization badge requires Duo screenshots; there is no separate TestFlight compatibility switch. See [Apple's Duo submission guidance](https://developer.apple.com/news/?id=kkphp5qo) and [screenshot sizes](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

Apple documents that the simulator's Foundation Models depend on compatible host and simulator versions. A model failure on an older simulator must be reported separately from UI test results. See [Apple's simulator guidance](https://developer.apple.com/forums/thread/787445).
