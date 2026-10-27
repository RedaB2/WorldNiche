# App Store readiness

Checked against Apple's current documentation on October 18, 2026. This is a release checklist, not an approval claim.

## Website and app disclosures

- The public [privacy policy](https://worldniche.app/privacy) explains data collection, uses, providers, sharing, retention, deletion, and consent controls. Matching automatic-moderation disclosures were published with the security and community pages in site version 10 on October 27 and verified live.
- The [support page](https://worldniche.app/support) lists the operator-approved contact, [boutayeb.reda@icloud.com](mailto:boutayeb.reda@icloud.com), for help, privacy requests, and abuse reports. Verify delivery and establish ongoing monitoring before submission.
- Keep both links accessible in the app, including without an account or a configured social service. Enter the same URLs in App Store Connect.
- Describe implemented security controls without claiming certification or guaranteed safety. Published policies must match the released app and operated services.

Apple requires accessible privacy disclosures and contact information. A website does not replace app behavior or operational safeguards. [Review Guidelines, sections 1.2, 1.5, 1.6 and 5.1](https://developer.apple.com/app-store/review/guidelines/), [Support URL requirements](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/).

## Verified safety work

On October 18, 2026, the hosted service passed a three-account disposable workflow for profile quarantine and approval, private photos, reciprocal and repeated invitation acceptance, sharing opt-out, reports, blocking, revoked links, account deletion, safe deletion retry, and stale-session denial. The workflow sends no emails and removes its disposable accounts. The account-deletion fixture suite covers 32 cases, including signed Apple token validation and failure recovery.

On October 27, migrations 005, 006 and 007 and the guarded moderation worker were installed with cloud secrets, account/shared request limits and an active minute-based retry job. The OpenAI key is restricted to moderation: moderation succeeded and unrelated model-catalog access returned 403. Its project has a verified $5 monthly hard spend limit, subject to enforcement delay. Eight hosted moderation groups passed, covering real approval, friend visibility, held unsafe content, cooldown recovery of the latest edit, consent isolation and deletion. All four disposable identities and their photos were removed. Scheduled runs succeeded with HTTP 200 responses. Separate validation passed 124 database abuse assertions, 81 handler tests, 348 native social checks, 54 avatar checks and all 18 iOS 27.0 simulator tests. Build 1.0 (3) has a verified distribution-signed archive and export; its upload status is tracked in [public beta notes](testflight.md).

Custom names and photos require server-side review before sharing. With separate permission, automatic checks can approve the exact saved revision; otherwise human review remains available. Pending content stays private, selected images cannot be swapped, and only server operators can review reports or restrict sharing. See [moderation operations](moderation.md).

Hosted testing found that the storage CDN can replay a previously authorized photo response. Native photo reads now use a fresh cache nonce to reach current access rules, with valid no-store upload directives. Previously downloaded or externally cached copies cannot be recalled. [Supabase CDN guidance](https://supabase.com/docs/guides/storage/cdn/smart-cdn).

## Remaining release gates

- **Apple account deletion:** Email-account deletion is verified against the hosted service, including photo removal, friendships, repeated confirmation and stale-session denial. Actual Apple authorization revocation still needs a consenting disposable Apple identity. Do not use the operator's real account. Signed local fixtures cover Apple validation, revocation and fallback logic, but are not a live Apple test. [Account deletion guidance](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion).
- **Moderation operations:** Server-enforced prepublication review, reports, removal and account restrictions are deployed and tested. The operator must review the private queue and published inbox regularly, handle urgent reports promptly, and respond to appeals. A working queue alone does not establish ongoing staffing. [Review Guidelines, section 1.2](https://developer.apple.com/app-store/review/guidelines/).
- **Native end-to-end review:** Hosted multi-account access checks pass. Complete the same social and deletion flows on the exact signed release build, including interruption recovery and the actual Apple-account path. Keep the hosted suite as a regression check.
- **Retention:** pg_cron is installed. Moderation reservation cleanup is scheduled but has not yet had its first scheduled execution. The separate `worldniche-retention` general maintenance job is not installed, so report, invite and other general cleanup remain outstanding. Verify provider log/backup retention before publishing exact periods.
- **Privacy labels:** Reconcile the website, release binary, privacy manifest, and App Store Connect answers. The manifest currently declares email, display name, user ID, profile photo, social graph, shared exploration, and support records as linked data for app functionality, with no tracking. Review operational logs and provider practices too. On-device-only processing and optional cloud collection are different. [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/).
- **Review access:** Provide a reliable way for App Review to test account and friend features, including instructions for Sign in with Apple and a usable friend-flow test route. Keep the backend available. Finish metadata, screenshots, review notes, and on-device stability checks. [Review Guidelines, sections 2.1 and 2.3](https://developer.apple.com/app-store/review/guidelines/).
- **Content and age rating:** Check rights and attribution for music artwork, news, cultural text, images, and marketing media. Complete the current age-rating questionnaire for actual dynamic content and social features. Do not choose a rating solely from the app's educational purpose. [Review Guidelines, sections 4.5 and 5.2](https://developer.apple.com/app-store/review/guidelines/), [age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/).
- **Submission configuration:** Verify release signing, required-reason API declarations, encryption answers, distribution-territory requirements, and the current upload toolchain requirements before submitting. [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [current requirements](https://developer.apple.com/news/upcoming-requirements/).

Recheck this list against the exact build and deployed service submitted for review.

## Public TestFlight

The external WorldNiche Public Beta group has a [public signup link](https://testflight.apple.com/join/kqpQhYFw) with a 100-tester limit. Release 1.0 (1) uploaded and processed successfully. Its distribution-signed IPA includes the expected Apple sign-in and Universal Link entitlements, production service configuration, and privacy manifest.

The agreement block is resolved. Apple approved build 1.0 (1), verified on October 20, and the public group shows Testing. Beta metadata and review instructions are saved, and the first TestFlight preflight reported no errors or warnings. Beta approval does not replace the App Store submission checks above. [Public beta notes](testflight.md) contain the distribution status, beta metadata, and remaining native validation and operational checks.

The full App Store listing tasks above, including store screenshots and final privacy labels, remain tracked separately from beta upload requirements. Their unfinished status is not evidence that Apple has rejected a TestFlight upload.
