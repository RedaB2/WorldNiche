# App Store readiness

Checked against Apple's current documentation on October 18, 2026. This is a release checklist, not an approval claim.

## Website and app disclosures

- Publish a public [privacy policy](https://worldniche.app/privacy) explaining data collection, uses, providers, sharing, retention, deletion, and consent controls.
- The [support page](https://worldniche.app/support) lists the operator-approved contact, [boutayeb.reda@icloud.com](mailto:boutayeb.reda@icloud.com), for help, privacy requests, and abuse reports. Verify delivery and establish ongoing monitoring before submission.
- Keep both links accessible in the app, including without an account or a configured social service. Enter the same URLs in App Store Connect.
- Describe implemented security controls without claiming certification or guaranteed safety. Published policies must match the released app and operated services.

Apple requires accessible privacy disclosures and contact information. A website does not replace app behavior or operational safeguards. [Review Guidelines, sections 1.2, 1.5, 1.6 and 5.1](https://developer.apple.com/app-store/review/guidelines/), [Support URL requirements](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/).

## Remaining release gates

- **Account deletion:** Exercise deletion against the live service using disposable email and Apple accounts. Verify photo removal, account and friendship deletion, retries after interrupted requests, local cleanup, and Apple token revocation or the documented fallback. A successful local test does not prove production erasure. [Account deletion guidance](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion).
- **Social safety:** Reporting and blocking are implemented. Add and verify objectionable-content filtering for shared profile names and photos, and establish a monitored moderation process. Current server validation checks format and size, not whether content is appropriate. Do not describe moderation as complete. [Review Guidelines, section 1.2](https://developer.apple.com/app-store/review/guidelines/).
- **Access controls:** Test two accounts against production. Verify non-friends cannot read private profiles or photos; blocking, revocation, and deletion remove app-managed access; invitation acceptance remains authenticated and idempotent.
- **Retention:** Verify the deployed cleanup job and provider log/backup retention before publishing exact periods. The repository's maintenance SQL alone does not establish that cleanup is running.
- **Privacy labels:** Reconcile the website, release binary, privacy manifest, and App Store Connect answers. The manifest currently declares email, display name, user ID, profile photo, social graph, shared exploration, and support records as linked data for app functionality, with no tracking. Review operational logs and provider practices too. On-device-only processing and optional cloud collection are different. [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/).
- **Review access:** Provide a reliable way for App Review to test account and friend features, including instructions for email-code authentication. Keep the backend available. Finish metadata, screenshots, review notes, and on-device stability checks. [Review Guidelines, sections 2.1 and 2.3](https://developer.apple.com/app-store/review/guidelines/).
- **Content and age rating:** Check rights and attribution for music artwork, news, cultural text, images, and marketing media. Complete the current age-rating questionnaire for actual dynamic content and social features. Do not choose a rating solely from the app's educational purpose. [Review Guidelines, sections 4.5 and 5.2](https://developer.apple.com/app-store/review/guidelines/), [age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/).
- **Submission configuration:** Verify release signing, required-reason API declarations, encryption answers, distribution-territory requirements, and the current upload toolchain requirements before submitting. [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [current requirements](https://developer.apple.com/news/upcoming-requirements/).

Recheck this list against the exact build and deployed service submitted for review.
