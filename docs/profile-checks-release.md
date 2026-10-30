# Profile checks release

This is the October 27 moderation release record, now merged into `main`. Database migrations 005, 006 and 007, the guarded worker, cloud secrets and the schedules were installed in Supabase on October 27. Hosted verification passed all eight groups and confirmed cleanup of four disposable accounts. Build 1.0 (3) was approved for public TestFlight at that time.

Update, October 29: general retention is now installed and its scheduled SQL passed verification. Build 1.0 (8) is in public TestFlight and submitted to App Review. The website is on version 16, including subsequent disclosure, journal and friends updates. See [App Store readiness](app-store-readiness.md) for the current dated status and [deployment](deployment.md) for operational details. The verification below describes the original moderation rollout.

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
- Hosted schema checks confirmed the limits and server-only reservation permissions. The deployed worker returned 401 for anonymous and forged-worker requests. Before the provider key was installed, it also failed closed with 503.
- The cloud key is restricted to `api.model.moderations.request`. Direct moderation returned 200 and an unrelated model-catalog request returned 403. The scoped worker credential is configured in Edge secrets and Vault.
- The default OpenAI project currently contains only the WorldNiche key. Its $5 monthly hard spend limit was saved and displayed as enforced, with a 100% alert. Enforcement can have a small delay and overshoot; backend quotas are separate safeguards.
- All eight hosted moderation groups passed with synthetic content: approval, friend name/photo access, later updates, held threatening text, latest-edit recovery after cooldown, consent isolation and deletion. Read-only polling after cooldown confirmed background processing without another foreground check. Cleanup was confirmed for all four disposable accounts.
- Only managed database login roles were present, and the Data API exposed only `public` and `graphql_public`. Scheduled work authenticates through the scoped Vault credential. Minute-based runs at 23:38 and 23:39 UTC on October 27 succeeded, with corresponding HTTP 200 responses and no timeout or error.
- All 8 isolated database test groups passed, including friend access, blocking, deletion, consent and concurrent changes.
- The Edge function passed Deno type checking.
- 348 native social checks and 54 avatar checks passed, including rejected uploads, preserved approved photos and explicit retry.
- All 5 moderation UI scenarios passed on iOS 26.5.
- The final October 27 iOS 27.0 simulator suite passed: 18 tests, no failures or skips. A new regression covers rotation past rejected regional candidates to a valid local music article while retaining country validation. The focused live test also passed separately.
- All 3 globe and adaptive layout tests passed on iOS 26.5. The new pinch test also passed on the open Duo.
- The photo recovery test passed on both the open landscape Duo and regular iPhone after its navigation helper was updated for the native sidebar.
- 29 website behavior and packaging tests passed, including empty lazy video sources and the Duo screen fit regression.
- Site version 10 published the matching privacy, security and community disclosures, and the live pages were verified. The legal update is recorded in public commit `29194ed`.
- Repository secret scanning passed without findings.
- Build 1.0 (3) was archived and exported with App Store distribution signing. Signature, production entitlements, Apple sign-in, Universal Links, icon and privacy manifest checks passed. Fresh App Store Connect reads confirmed `VALID`, `APPROVED`, and `IN_BETA_TESTING`, with build 3 assigned to WorldNiche Public Beta. The existing public link, saved test notes, and automatic notification are enabled. The build declares that it does not use non-exempt encryption.

The actual on-device companion response test passed twice on iOS 27.0. The iOS 26.5 simulator reports a host model compatibility failure. Duo photo recovery and landscape layout were verified directly in Device Hub. The isolated tests establish behavior; the separate hosted run verified connectivity to the deployed moderation provider. Actual Apple authorization revocation still requires a consenting disposable Apple identity and was not exercised by these synthetic email accounts.

XCTest on the Duo inner display accepted rotation commands without rotating its active interface. Its full-screen captures were black, and row captures were upside down despite upright orientation metadata. The assertions remain intact; the photo check samples both possible row-end avatar positions. The final landscape photo run passed with adaptive navigation. Rotation tooling failures are recorded separately from the passing iOS 27.0 suite. Closing the Duo also left XCTest unable to locate its tab bar, so that earlier attempted outer-display run is not passing evidence.

## Deployment gates

No deployment gate remains for build 1.0 (3). It is approved and available through the [public TestFlight link](https://testflight.apple.com/join/kqpQhYFw).

Operational follow-up: confirm the first scheduled reservation cleanup and configure the separate general retention job. Provider log and backup retention still need verification before publishing exact periods.

The isolated tests sent no network traffic. The hosted test sent only synthetic profile text and a harmless fixture image to OpenAI. No provider credential belongs in the app, website or repository.

## iPhone Duo

The published landing page pairs a separate, unfolded landscape mockup with a real 29.53-second landscape simulator recording. The original iPhone preview remains available. Desktop and 390-pixel mobile browser checks confirmed both screen masks, switching, keyboard selection, playback and no horizontal overflow. The hosting artifact passed exact-byte and video range validation. Site version 10 also published the matching automatic-moderation disclosures, with live verification of the privacy, security and community pages.

Site version 9 fixes the Duo's black side edges by matching its decorative frame and screen mask to the recording. The full app image is preserved without cropping or stretching. Live desktop and mobile checks passed.

App Store Connect's Duo optimization badge requires Duo screenshots; there is no separate TestFlight compatibility switch. See [Apple's Duo submission guidance](https://developer.apple.com/news/?id=kkphp5qo) and [screenshot sizes](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

Apple documents that the simulator's Foundation Models depend on compatible host and simulator versions. A model failure on an older simulator must be reported separately from UI test results. See [Apple's simulator guidance](https://developer.apple.com/forums/thread/787445).
