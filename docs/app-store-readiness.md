# App Store readiness

Rechecked against Apple's documentation and the live App Store Connect record on October 29, 2026. This is a release checklist, not an approval claim.

## Current submission status: October 29, 2026

Version 1.0 is `PREPARE_FOR_SUBMISSION` with **build 7** selected and manual release. The listing now has its description, keywords, subtitle, support and privacy links, Education and Travel categories, copyright, and App Review contact and notes. Pricing is free in all 175 available territories, with future territories enabled. Regional permits and trader requirements still need checking before release.

Apple calculates **13+ in 172 regions**, with regional ratings of 16+ in Vietnam, 14+ in Brazil and 12+ in Korea. Mature or suggestive themes are marked infrequent for the app's incidental news and music content. The rating reflects the questionnaire, not a forced override. Reassess if the content or social features change.

The [listing media](../marketing/app-store/README.md) is uploaded and processed: five iPhone screenshots, three iPad screenshots, two unfolded iPhone Duo screenshots, and a 20-second Morocco app preview. These use actual simulator UI. Metadata and supported screenshot format validation pass. The revised Journal shows 20 explored and 10 saved countries; Mira has the existing girl portrait. All ten screenshot checksums match the processed uploads. The current CLI reports **zero errors** and **one warning**, because its size catalog does not yet recognize `APP_IPHONE_DUO`. The content-rights declaration is saved as `USES_THIRD_PARTY_CONTENT` and verified in the browser. Apple's browser accepts that display type and reports both Duo images processed at 2034 by 1398.

All twelve App Privacy categories are saved with app-functionality use, linked identity and no tracking. Publication is awaiting the owner's confirmation of Apple's accuracy and update agreement. The [category mapping](app-privacy.md), release manifest and live website policy are reconciled. The API validator cannot detect this publish gate. TestFlight approval does not approve the App Store listing.

Before requesting App Review:

1. Select build 7 or later, which replaces the previous news provider with attributed Global Voices country feeds under CC BY 3.0. The [source notices](../licenses/README.md) document the news, music, cultural text and map basis. Image filtering excludes noncommercial and no-derivatives licenses. Keep checking item-specific exceptions and attribution as dynamic content changes.
2. Publish the saved App Privacy answers after the owner confirms Apple's accuracy and update agreement.
3. Complete native account deletion with a consenting disposable Apple account, including Apple authorization revocation. Local fixtures and hosted deletion checks pass, but do not substitute for this live Apple path.
4. Provide a reliable friend-feature route for App Review, in addition to the saved native Apple sign-in instructions.
5. Confirm the support/moderation inbox is monitored, review outstanding reports, verify maintenance and provider retention, and check attribution and media rights for the submitted build.
6. Resolve applicable EU trader and China mainland permit requirements for the selected territories.

The journal migration is deployed. Hosted rollback-only checks passed for private sync, repeated-request handling, friend isolation, export and deletion cascades. They preserved the existing account and all 195 countries, and left no test accounts. Notes and bookmarks are private even when friend exploration sharing is on. See [journal behavior](journal.md).

The draft listing was updated. No App Store review request was sent.

## Website and app disclosures

- The public [privacy policy](https://worldniche.app/privacy) explains data collection, uses, providers, sharing, retention, deletion, and consent controls. Site version 15 updates the policy for private journal sync, Global Voices, IP-derived approximate location and operational logs; it was verified live on October 29. Existing moderation, security and community disclosures remain available.
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
- **Retention:** pg_cron is installed. On October 29, the moderation worker and daily reservation cleanup both showed successful latest executions with zero cron failures in the previous 24 hours. The separate `worldniche-retention` general maintenance job is not installed, so report, invite and other general cleanup remain outstanding. Verify provider log/backup retention before publishing exact periods.
- **Privacy labels:** All twelve categories are saved and reconciled with the website and build 7 manifest, including private journal notes, sync identifiers and provider diagnostics. Publication still needs the owner's approval of Apple's final agreement. [Category mapping](app-privacy.md). On-device-only processing and optional cloud collection are different. [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/).
- **Review access:** Provide a reliable way for App Review to test account and friend features, including instructions for Sign in with Apple and a usable friend-flow test route. Keep the backend available. Finish metadata, screenshots, review notes, and on-device stability checks. [Review Guidelines, sections 2.1 and 2.3](https://developer.apple.com/app-store/review/guidelines/).
- **Content and age rating:** Check rights and attribution for music artwork, news, cultural text, images, and marketing media. The questionnaire is saved and calculates 13+ with regional exceptions. Keep it aligned with actual dynamic content and social features. [Review Guidelines, sections 4.5 and 5.2](https://developer.apple.com/app-store/review/guidelines/), [age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/).
- **Submission configuration:** Verify release signing, required-reason API declarations, encryption answers, distribution-territory requirements, and the current upload toolchain requirements before submitting. [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [current requirements](https://developer.apple.com/news/upcoming-requirements/).

Recheck this list against the exact build and deployed service submitted for review.

## Public TestFlight

The external WorldNiche Public Beta group has a [public signup link](https://testflight.apple.com/join/kqpQhYFw) with a 100-tester limit. Release 1.0 (1) uploaded and processed successfully. Its distribution-signed IPA includes the expected Apple sign-in and Universal Link entitlements, production service configuration, and privacy manifest.

The agreement block is resolved. Apple approved build 1.0 (1), verified on October 20, and the public group shows Testing. Beta metadata and review instructions are saved, and the first TestFlight preflight reported no errors or warnings. Beta approval does not replace the App Store submission checks above. [Public beta notes](testflight.md) contain the distribution status, beta metadata, and remaining native validation and operational checks.

Public TestFlight is now on build 7 with licensed Global Voices headlines. The release passed live feed checks across sixteen countries, phone and unfolded news UI checks, seven final phone news/profile scenarios, culture license regressions, distribution-signature checks and a secret scan. Strict TestFlight validation has zero errors or warnings. The remaining App Store gates above are tracked separately from beta upload requirements. Their unfinished status is not evidence that Apple has rejected a TestFlight upload.
