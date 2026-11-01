# TestFlight

## Combined PR #8 and PR #9 candidate: November 1, 2026

**1.0.1 (10) is uploaded, valid and available in internal TestFlight.** It combines the native friend invitation changes from [PR #8](https://github.com/RedaB2/WorldNiche/pull/8), head `e2350b777a1d3b9b1aad25f3a01e2b3d5698d4aa`, and the country-location globe from [PR #9](https://github.com/RedaB2/WorldNiche/pull/9), head `d3102eafc1f591bde812128afd6120e44aed0ded`. Both heads are ancestors of archive source `d90d229ab7c66562a40873d421f7df2b6694d7ab` on `beta/pr8-pr9-testflight`.

App Store Connect build ID: `7b7b1f41-f84d-48fa-a323-cfbb0c07b952`. Readback confirms `VALID`, internal state `IN_BETA_TESTING`, automatic notification enabled, and exact assignment to **Release Checks**. The owner is the sole enrolled tester. The tester record is `INSTALLED`, indicating existing TestFlight participation; installation of build 10 itself has not been verified. Open TestFlight, select WorldNiche and update to **1.0.1 (10)**.

Owner acceptance, November 1: the owner subsequently confirmed testing PRs #8 and #9 in this build and approved merging all changes to `main`, explicitly without an App Store submission. Both PRs are merged. The build-10 version and validation record are included in the merge follow-up. The website publishes through its normal main-branch pipeline; the invitation metadata migration and runtime configuration remain a separate deployment step.

The same combined selection passes **25/25 on iPhone 17 Pro (iOS 27.0)** and **25/25 on unfolded Duo (iOS 27.1)**, with zero failures or skips. It covers all three country-location tests, fourteen globe regressions, seven profile setup/invitation preview tests, and warm/cold invitation opening. The full Swift suite passes, including 32,676 globe assertions and 411 social assertions. Private-file checks, website tests and packaging, Vercel HTTP/metadata validation, and isolated backend tests pass. The database run uses `PGTZ=UTC` for the existing local daylight-saving boundary issue.

Initial failures remain in the private evidence. The first Swift run and one focused rerun hit four temporary-file write failures; an instrumented run, an unchanged focused run, and the final unchanged full Swift run subsequently passed. The cause is unconfirmed. The initial Duo run began folded and continued with synthetic gestures targeting its outer display. Its replacement began unfolded and used `WORLDNICHE_UI_TEST_DISPLAY_ID=3`; all 25 scenarios passed. No app runtime changes were needed beyond the two PRs.

The distribution archive and exported IPA pass strict signature, version, App Store profile, Apple sign-in, associated-domain and disabled-debugger validation. The bundled production configuration matches the ignored local input and uses only a public client key. Privacy manifest, app icons and source credits are present; simulator fixture markers and private-key patterns are absent. Static release readiness passes against the live production AASA. IPA SHA-256: `cf4be080fe30efc2e8110b2cfbbc90a863c5f630b2618f176949ef9ac4cc2bc3`.

What to Test notes cover the country globe, Add a friend, approved-name privacy, main-globe regressions and both layouts. Personalized website previews from PR #8 still require its migration and Vercel deployment. This operation did not deploy the website or backend, merge either PR, change public access, or submit an App Store release. Build 10 is absent from **WorldNiche Public Beta**; the App Store readback remains **1.0 (8), READY_FOR_DISTRIBUTION** with build ID `47bfd9d3-1dd9-4322-8df7-4f7b3263d660`.

Private packages, logs, test results, package provenance and distribution readbacks are in `outputs/testflight/1.0.1-10/`. The final packages are `WorldNiche-distribution.xcarchive` and `WorldNiche-distribution.ipa`; `test-evidence.json` and `validation-provenance.json` identify their checks and source.

## Owner globe candidate: November 1, 2026

**1.0.1 (9) is uploaded, processed and in internal testing.** The archive source is `f912909c7dd302d349c8428782380ae2f4fff8f2` on `feat/globe-interactions` / [PR #4](https://github.com/RedaB2/WorldNiche/pull/4). It preserves the owner-approved globe runtime from `8352c453f18b94155786b1e7557bf5173a21d9e8`; only version/build configuration and documentation changed for preparation. Build 9 was the next available number across processed builds and in-flight uploads.

App Store Connect build ID: `81a13535-f895-4c8f-95a0-90dcf4ec474c`. Processing is `VALID`, internal state is `IN_BETA_TESTING`, and external state is `READY_FOR_BETA_SUBMISSION`. The existing internal **Release Checks** group contains this build and the owner as its sole tester. The owner's state is `INVITED`; accepting the TestFlight invitation and installing on a device remain owner actions. The saved What to Test notes cover rotation, flick/re-grab, pinch, repositioning, borders/fade, country previews, first-touch Reset and both device layouts.

The candidate is absent from **WorldNiche Public Beta**. A final App Store Connect readback still shows production 1.0 (8), `READY_FOR_DISTRIBUTION`, attached to build `47bfd9d3-1dd9-4322-8df7-4f7b3263d660`. No App Store version, submission, release, public access, main merge or production deployment was changed. The `v1.0.0` tag is intact.

The approved source passed Swift checks including 32,676 globe assertions. Exact full and focused phone/Duo outcomes remain in [globe review notes](globe-interactions.md). The earlier GitHub simulator job failed while its runner bootstrapped. On candidate [run 41300420574](https://github.com/RedaB2/WorldNiche/actions/runs/41300420574), Swift, secret, website and backend checks passed; the native UI job was still running at the upload readback. These checks are separate from package validation and do not imply a clean full globe UI suite.

The Release archive and exported IPA both passed strict signature, bundle/version, distribution profile, Sign in with Apple, associated-domain and disabled-debugger checks. The packaged production client configuration matches the ignored local input and uses only a public client key. Privacy manifest, icons and source credits are present; simulator fixture markers and private-key patterns are absent. Static release readiness passed using the live production AASA. Xcode 27.2 (27B52), iPhoneOS 27.2 SDK. IPA SHA-256: `e45d00ecdc61643bcd930baaf93d8d8ffb0786e6c6cce9bf31080dc77128a444`.

Private archive/export, upload and readback evidence is in `outputs/testflight/1.0.1-9/`, including `validation-provenance.json`. Preparation evidence is in `outputs/testflight/globe-preparation-2026-11-01/`. Configured binaries, signing files and tester details remain ignored.

## Existing public beta

The external **WorldNiche Public Beta** group has a [public signup link](https://testflight.apple.com/join/kqpQhYFw) with 100 places. Build 1.0 (8) is in external testing, with licensed Global Voices news, visible author/date credits and updated privacy declarations. Private journal notes, cloud sync and friend features remain available.

Build 5 adds a practice globe, expandable live music and news previews, a local-culture example, and an animated friend invitation. Only one preview opens at a time. The intro adapts to folded and unfolded displays and larger text. All email sign-in and recovery screens are removed. The matching website help is live in site version 12.

All 16 final simulator scenarios pass on both iPhone 17 Pro Max and an unfolded iPhone Duo, following an earlier 11-scenario phone run. They cover globe gestures without navigation, one-open-preview behavior, independent retry, Reduce Motion, large text, guest access, Apple-only sign-in, profile setup, remembered consent, and sharing choices. Also passed: 400 native social assertions twice, 12 intro state checks, the feed regression suite, and 31 website checks. Manual checks cover real United States charts and headlines on both devices, all three intro pages, and switching Duo from closed to unfolded without losing progress.

Apple currently requires an internal group before an external group can be created. If needed, create that prerequisite without adding testers, then use the external group for public distribution. Do not upload the build as TestFlight Internal Only. [Apple's external testing instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).

## Beta description

A little more world, every day. Spin the globe, find a song, catch up on local news, and discover small details about cultures around the world. Save places you're curious about and see what your friends have explored.

## What to test

- Explore Global Voices news in country details and the United States intro preview. Check author credits, dates, original links, independent refresh and honest empty coverage.

- Save a country and add a private note from Journal. Relaunch, edit, cancel and clear it. Signed-in users can check the same journal on another device and retry after being offline. Turning friend sharing off should preserve private journal sync. Friends must never see notes or bookmarks.

- Explore Morocco, spin to another country, search the Atlas, and save a place.
- Refresh music, news, and local discoveries independently. Tell us when a source fails or a discovery repeats too often.
- Try Sign in with Apple. Close and reopen the app to check that you stay signed in.
- Spin and zoom the practice globe, expand each discovery preview, and watch the friend invitation animation. One preview should stay open at a time, and tapping the practice globe should keep you in the intro.
- Try the intro folded, unfolded, and with larger text. Create a profile with your chosen name and an optional photo, or keep exploring without an account. Skipping the photo should show your initials.
- Check the sharing switch during signup and choose whether to allow automatic profile checks. Normal edits should remember that choice without asking again. Friends should see approved updates without reopening the app.
- Zoom closer on the globe to tap smaller countries, and try Show me another for new cultural discoveries.
- Share a friend invitation, open it from Messages, and check that it connects both accounts. Try exploration sharing, removing a friend, reporting, and blocking.
- If you create a disposable account specifically for testing, try data export and account deletion. Deletion is permanent, so use an account you intend to remove.

Send feedback through TestFlight or the contact at [worldniche.app/support](https://worldniche.app/support). Do not include passwords, sign-in codes, or invitation tokens in public bug reports.

## Review notes

Exploration works without an account. The optional intro includes a practice globe, expandable United States music/news/culture examples, and an illustrated friend-connection animation. The animation is a demonstration and does not send invitations. The intro can be skipped and ends with an optional invitation to create a profile. Account access uses only native Sign in with Apple; email sign-in and recovery are removed. Profile setup asks for a chosen display name and an optional photo, with initials when no photo is selected. There are no passwords, purchases, ads, or tracking SDKs. Exploration sharing is visibly on for new profiles during setup and can be turned off there or in Settings. Existing choices stay unchanged.

Profile edits appear privately to their owner immediately. Setup offers one-time permission to send the submitted name and selected photo to OpenAI, with a clear option to continue without automatic checks. That choice is remembered for normal edits and can be changed in Settings. Approved changes become visible to friends automatically. Human review remains available. Flagged or unapproved changes stay private, while friends see the previously approved profile or a neutral New friend placeholder. Normal edits show no review status card; rejected content and restrictions show actionable feedback. Settings contains the privacy policy, support, community guidelines, export, device clear, and account deletion.

Provide any private reviewer access details only in App Store Connect. Do not commit credentials or a real user's friend invitation. Keep the hosted service, moderation queue, and support inbox available during review.

## Test information

| Field | Value |
|---|---|
| Feedback email | boutayeb.reda@icloud.com |
| Marketing URL | https://worldniche.app |
| Privacy policy | https://worldniche.app/privacy |
| Support | https://worldniche.app/support |

To create or access a profile, open Profile and choose Sign in with Apple. Keep Apple passwords and verification codes on Apple’s authorization screen. Supply the review contact and any required private access details in App Store Connect before submission. [Apple's test information requirements](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/).

Before inviting testers, confirm native Apple sign-in, persistent sessions, and the social and deletion flows on the submitted build. Regularly monitor the profile queue and support inbox. The native Apple revocation and account deletion flow passed on build 7 with a consenting disposable profile; backend erasure and removal from Apple settings were both confirmed.

## Current state

October 18, 2026: Release 1.0 (1) is exported as an App Store distribution-signed IPA. The installed WorldNiche App Store profile uses the existing distribution certificate. Signature verification passes; the exported app has Sign in with Apple, the worldniche.app associated domain, disabled debugger access, the configured service, and its privacy manifest. The warm/cold invitation simulator test also passes. Signing artifacts and configured binaries stay outside the public repository.

October 19, 2026: The agreement block is resolved. WorldNiche's app record was created, and Release 1.0 (1) uploaded and processed successfully. The beta description, privacy and marketing URLs, feedback contact, test notes, and reviewer access instructions are saved. TestFlight preflight reported no errors or warnings.

The build was submitted for external review on October 19 at 11:07 p.m. Pacific. At submission, App Store Connect showed **Waiting for Review**. The external group has this build, its public link is enabled, feedback is enabled, and the limit is 100 testers. Automatic notification after approval is enabled. The empty Release Checks internal group satisfies Apple's prerequisite; the build is assigned to the external group.

October 20, 2026: Apple's API confirms that build 1.0 (1) is approved, and App Store Connect shows Testing for the public group. Build 1.0 (2) carries the new planet logo across the app icon, light and dark mode headers, About, and friend invitation previews. It passed release signing and TestFlight preflight with no errors or warnings, is approved, and is in external testing with automatic notification enabled. The App Store 1.0 draft also uses build 2; the full App Store listing has not been submitted.

An Agreements and Contracts support case was submitted after the earlier agreement mismatch. No reply was found in Mail or the support portal at this check. The cause of the earlier mismatch remains unconfirmed. Correspondence, reviewer contact details, configured binaries, and signing artifacts stay outside this repository.

October 27, 2026: Release 1.0 (3) passed all 18 simulator tests, 54 avatar checks, 348 social assertions, and the deterministic culture checks. A discovery filter that rejected valid musical styles and plural traditions was fixed with a regression test. The signed IPA passed signature, entitlement, app icon, privacy manifest, and configured-service verification.

The hosted moderation checks passed for safe names and JPEGs, exact approved friend-photo bytes, consent isolation, flagged content, cooldown recovery, and deletion. Temporary test accounts were removed. Updated privacy, security, and community disclosures are live. Reviewer notes now match automatic checks, the human-review choice, Apple sign-in, and sharing enabled by default. Build 1.0 (3) uploaded, processed successfully, and was approved for external testing on October 27. Fresh App Store Connect reads confirm `VALID`, `APPROVED`, and `IN_BETA_TESTING`, plus its assignment to WorldNiche Public Beta. The existing public link remains enabled with 100 places, the new What to Test notes are saved, and automatic notification is enabled. The build declares that it does not use non-exempt encryption. No Apple review is pending for this beta.

October 28, 2026: Release 1.0 (4) is approved and available to the existing public beta group. App Store Connect confirms `VALID`, `APPROVED`, and `IN_BETA_TESTING`. The exact build is assigned to WorldNiche Public Beta, the public signup link remains enabled, updated What to Test notes are saved, and automatic tester notification is enabled. All release checks above passed before upload. No Apple review is pending for this beta.

October 28, 2026: Release 1.0 (5) is approved and available to the existing public beta group. Fresh App Store Connect reads confirm `VALID`, `APPROVED`, and `IN_BETA_TESTING`, its exact public-group assignment, saved test and reviewer notes, and automatic notification. The public signup link remains enabled with 100 places. The signed IPA contains both intro avatars, the app icon, privacy manifest, production configuration, Apple sign-in, and the worldniche.app associated domain. Signature and secret/test-fixture exclusion checks pass, and strict TestFlight preflight has no errors or warnings.

October 29, 2026: Release 1.0 (6) is approved and in external testing for WorldNiche Public Beta. It adds private destination notes and account sync for bookmarks and exploration dates, independent of friend sharing. Guest journals remain device-only. The backend migration and website privacy update are deployed. All 12 selected intro, profile and journal scenarios pass on both iPhone 17 Pro Max and unfolded Duo, including large text, with 21 journal checks, 408 social checks, local database access checks, hosted rollback-only checks and 32 website checks. The signed package passed entitlement, production configuration, privacy manifest, and secret/test-fixture checks. Strict TestFlight preflight has zero errors or warnings; updated test/reviewer notes and automatic notification are verified. No production App Store review was submitted.

October 29, 2026: Build 1.0 (7) is `VALID` and `IN_BETA_TESTING` in the existing public group, with automatic tester notification enabled. Live Swift checks pass across sixteen country feeds, including an expected empty Vatican City result; France also returns its Apple Music chart. Both news UI scenarios pass on iPhone 17 Pro Max and unfolded Duo, and the final phone news/profile run passes all seven tests. Feed regressions, culture image-license checks, screenshot fixtures, release signing, privacy/entitlement checks and the secret scan pass. Strict TestFlight preflight has no errors or warnings. App Store version 1.0 now selects this build; final production review has not been requested.


October 29, 2026: Release 1.0 (8) is approved and available in WorldNiche Public Beta. App Store Connect readback confirms `VALID`, `APPROVED`, `IN_BETA_TESTING`, exact public-group membership and automatic notification. The existing public link and 100-place limit remain enabled. Profile and the final intro page offer one Continue with Apple entry for both new and returning users. Account, friend and deletion services are unchanged. Fourteen focused scenarios pass on each of iPhone 17 Pro Max and unfolded Duo, including larger text, new/returning profile behavior, optional photos, remembered choices and guest access. The culture smoke test now begins with a cleared local guest history; deterministic source, exhaustion and history checks also pass. The owner completed real Apple account deletion and reviewer-friend testing on build 7, with backend verification and confirmation that Apple authorization was removed. Daily retention is installed and verified. After the owner approved the complete submission overview, build 8 was submitted to App Review on October 29 at 6:28 p.m. Pacific. Apple confirms `WAITING_FOR_REVIEW`. Release remains manual after approval; this does not change public TestFlight availability.
