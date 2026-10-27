# Public beta

The external **WorldNiche Public Beta** group has a [public signup link](https://testflight.apple.com/join/kqpQhYFw) with 100 places. Apple approved build 1.0 (3), and it is available to external testers with automatic profile checks, friend updates, closer globe zoom, and the discovery fix.

Apple currently requires an internal group before an external group can be created. If needed, create that prerequisite without adding testers, then use the external group for public distribution. Do not upload the build as TestFlight Internal Only. [Apple's external testing instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).

## Beta description

A little more world, every day. Spin the globe, find a song, catch up on local news, and discover small details about cultures around the world. Save places you're curious about and see what your friends have explored.

## What to test

- Explore Morocco, spin to another country, search the Atlas, and save a place.
- Refresh music, news, and local discoveries independently. Tell us when a source fails or a discovery repeats too often.
- Try Sign in with Apple. Existing email users can recover their account with a six-digit code. Close and reopen the app to check that you stay signed in.
- Change your name or photo and try automatic checks. Your private preview should appear immediately; friends should see approved updates without reopening the app. Human review remains an option.
- Zoom closer on the globe to tap smaller countries, and try Show me another for new cultural discoveries.
- Share a friend invitation, open it from Messages, and check that it connects both accounts. Try exploration sharing, removing a friend, reporting, and blocking.
- If you create a disposable account specifically for testing, try data export and account deletion. Deletion is permanent, so use an account you intend to remove.

Send feedback through TestFlight or the contact at [worldniche.app/support](https://worldniche.app/support). Do not include passwords, sign-in codes, or invitation tokens in public bug reports.

## Review notes

Exploration works without an account. Sign-in is optional for friends and cloud sharing. New users can use native Sign in with Apple; existing email users can recover their account with a six-digit code. There are no passwords, purchases, ads, or tracking SDKs. Exploration sharing starts on for new profiles and can be turned off in Settings.

Profile edits appear privately to their owner immediately. Automatic checks send the submitted name and selected photo to OpenAI only after the user explicitly chooses that option. Approved changes become visible to friends automatically. Human review remains available. Flagged or unapproved changes stay private, while friends see the previously approved profile or a neutral Explorer profile. Settings contains the privacy policy, support, community guidelines, export, device clear, and account deletion.

Provide any private reviewer access details only in App Store Connect. Do not commit credentials or a real user's friend invitation. Keep the hosted service, SMTP delivery, moderation queue, and support inbox available during review.

## Test information

| Field | Value |
|---|---|
| Feedback email | boutayeb.reda@icloud.com |
| Marketing URL | https://worldniche.app |
| Privacy policy | https://worldniche.app/privacy |
| Support | https://worldniche.app/support |

For a new profile, open Profile and choose Sign in with Apple. To recover an existing email account, choose the email recovery option and enter the six-digit code sent to that address. A code is short-lived and must not be saved as a reusable review credential. Supply the review contact and any required private access details in App Store Connect before submission. [Apple's test information requirements](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/).

Before inviting testers, confirm production email-code delivery, the native social and deletion flows on the submitted build, and regular human monitoring of the profile queue and support inbox. The hosted integration suite sends no emails; its passing result does not establish email delivery. Live Apple authorization revocation still needs a disposable Apple identity.

## Current state

October 18, 2026: Release 1.0 (1) is exported as an App Store distribution-signed IPA. The installed WorldNiche App Store profile uses the existing distribution certificate. Signature verification passes; the exported app has Sign in with Apple, the worldniche.app associated domain, disabled debugger access, the configured service, and its privacy manifest. The warm/cold invitation simulator test also passes. Signing artifacts and configured binaries stay outside the public repository.

October 19, 2026: The agreement block is resolved. WorldNiche's app record was created, and Release 1.0 (1) uploaded and processed successfully. The beta description, privacy and marketing URLs, feedback contact, test notes, and reviewer access instructions are saved. TestFlight preflight reported no errors or warnings.

The build was submitted for external review on October 19 at 11:07 p.m. Pacific. At submission, App Store Connect showed **Waiting for Review**. The external group has this build, its public link is enabled, feedback is enabled, and the limit is 100 testers. Automatic notification after approval is enabled. The empty Release Checks internal group satisfies Apple's prerequisite; the build is assigned to the external group.

October 20, 2026: Apple's API confirms that build 1.0 (1) is approved, and App Store Connect shows Testing for the public group. Build 1.0 (2) carries the new planet logo across the app icon, light and dark mode headers, About, and friend invitation previews. It passed release signing and TestFlight preflight with no errors or warnings, is approved, and is in external testing with automatic notification enabled. The App Store 1.0 draft also uses build 2; the full App Store listing has not been submitted.

An Agreements and Contracts support case was submitted after the earlier agreement mismatch. No reply was found in Mail or the support portal at this check. The cause of the earlier mismatch remains unconfirmed. Correspondence, reviewer contact details, configured binaries, and signing artifacts stay outside this repository.

October 27, 2026: Release 1.0 (3) passed all 18 simulator tests, 54 avatar checks, 348 social assertions, and the deterministic culture checks. A discovery filter that rejected valid musical styles and plural traditions was fixed with a regression test. The signed IPA passed signature, entitlement, app icon, privacy manifest, and configured-service verification.

The hosted moderation checks passed for safe names and JPEGs, exact approved friend-photo bytes, consent isolation, flagged content, cooldown recovery, and deletion. Temporary test accounts were removed. Updated privacy, security, and community disclosures are live. Reviewer notes now match automatic checks, the human-review choice, Apple sign-in, and sharing enabled by default. Build 1.0 (3) uploaded, processed successfully, and was approved for external testing on October 27. Fresh App Store Connect reads confirm `VALID`, `APPROVED`, and `IN_BETA_TESTING`, plus its assignment to WorldNiche Public Beta. The existing public link remains enabled with 100 places, the new What to Test notes are saved, and automatic notification is enabled. The build declares that it does not use non-exempt encryption. No Apple review is pending for this beta.
