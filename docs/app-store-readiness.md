# App Store readiness

Checked against Apple's current documentation on October 18, 2026. This is a release checklist, not an approval claim.

## Website and app disclosures

- Publish a public [privacy policy](https://worldniche.app/privacy) explaining data collection, uses, providers, sharing, retention, deletion, and consent controls.
- The [support page](https://worldniche.app/support) lists the operator-approved contact, [boutayeb.reda@icloud.com](mailto:boutayeb.reda@icloud.com), for help, privacy requests, and abuse reports. Verify delivery and establish ongoing monitoring before submission.
- Keep both links accessible in the app, including without an account or a configured social service. Enter the same URLs in App Store Connect.
- Describe implemented security controls without claiming certification or guaranteed safety. Published policies must match the released app and operated services.

Apple requires accessible privacy disclosures and contact information. A website does not replace app behavior or operational safeguards. [Review Guidelines, sections 1.2, 1.5, 1.6 and 5.1](https://developer.apple.com/app-store/review/guidelines/), [Support URL requirements](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/).

## Verified safety work

On October 18, 2026, the hosted service passed a three-account disposable workflow for profile quarantine and approval, private photos, reciprocal and repeated invitation acceptance, sharing opt-out, reports, blocking, revoked links, account deletion, safe deletion retry, and stale-session denial. The workflow sends no emails and removes its disposable accounts. The account-deletion fixture suite covers 32 cases, including signed Apple token validation and failure recovery. The native social suite covers 258 assertions.

Custom names and photos now require server-side review before sharing. Pending content stays private, approvals are revision-checked, selected images cannot be swapped, and only server operators can review reports or restrict sharing. See [moderation operations](moderation.md).

Hosted testing found that the storage CDN can replay a previously authorized photo response. Native photo reads now use a fresh cache nonce to reach current access rules, with valid no-store upload directives. Previously downloaded or externally cached copies cannot be recalled. [Supabase CDN guidance](https://supabase.com/docs/guides/storage/cdn/smart-cdn).

## Remaining release gates

- **Apple account deletion:** Email-account deletion is verified against the hosted service, including photo removal, friendships, repeated confirmation and stale-session denial. Actual Apple authorization revocation still needs a consenting disposable Apple identity. Do not use the operator's real account. Signed local fixtures cover Apple validation, revocation and fallback logic, but are not a live Apple test. [Account deletion guidance](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion).
- **Moderation operations:** Server-enforced prepublication review, reports, removal and account restrictions are deployed and tested. The operator must review the private queue and published inbox regularly, handle urgent reports promptly, and respond to appeals. A working queue alone does not establish ongoing staffing. [Review Guidelines, section 1.2](https://developer.apple.com/app-store/review/guidelines/).
- **Native end-to-end review:** Hosted multi-account access checks pass. Complete the same social and deletion flows on the exact signed release build, including interruption recovery and the actual Apple-account path. Keep the hosted suite as a regression check.
- **Retention:** Verify the deployed cleanup job and provider log/backup retention before publishing exact periods. The repository's maintenance SQL alone does not establish that cleanup is running.
- **Privacy labels:** Reconcile the website, release binary, privacy manifest, and App Store Connect answers. The manifest currently declares email, display name, user ID, profile photo, social graph, shared exploration, and support records as linked data for app functionality, with no tracking. Review operational logs and provider practices too. On-device-only processing and optional cloud collection are different. [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/).
- **Review access:** Provide a reliable way for App Review to test account and friend features, including instructions for email-code authentication. Keep the backend available. Finish metadata, screenshots, review notes, and on-device stability checks. [Review Guidelines, sections 2.1 and 2.3](https://developer.apple.com/app-store/review/guidelines/).
- **Content and age rating:** Check rights and attribution for music artwork, news, cultural text, images, and marketing media. Complete the current age-rating questionnaire for actual dynamic content and social features. Do not choose a rating solely from the app's educational purpose. [Review Guidelines, sections 4.5 and 5.2](https://developer.apple.com/app-store/review/guidelines/), [age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/).
- **Submission configuration:** Verify release signing, required-reason API declarations, encryption answers, distribution-territory requirements, and the current upload toolchain requirements before submitting. [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [current requirements](https://developer.apple.com/news/upcoming-requirements/).

Recheck this list against the exact build and deployed service submitted for review.

## Public TestFlight

The intended group is an external group named WorldNiche Public Beta with a public signup link. Do not substitute a private tester group. External builds need Apple's TestFlight review before testers can install them. At the October 18 check, App Store Connect blocked new app creation and its API with an agreement error, while the Developer account showed the current agreement accepted that same day. No public TestFlight link or approved external build exists yet. Recheck the account state before upload and preserve the verified backend configuration in the signed build.
