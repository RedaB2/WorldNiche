# Public beta

The external **WorldNiche Public Beta** group has a [public signup link](https://testflight.apple.com/join/kqpQhYFw) with 100 places. Build 1.0 (7) is in external testing, with licensed Global Voices news, visible author/date credits and updated privacy declarations. Private journal notes, cloud sync and friend features remain available.

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

Before inviting testers, confirm native Apple sign-in, persistent sessions, and the social and deletion flows on the submitted build. Regularly monitor the profile queue and support inbox. Live Apple authorization revocation still needs a disposable Apple identity.

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
