# A quick look around

- `apps/ios`: the SwiftUI app and Xcode project. The globe uses native rendering; music, news, and cultural discoveries have separate loading and retry states.
- `apps/web/landing-site`: the landing page, hand animation, and real app recording.
- `apps/web/invite-site`: the invitation fallback page. Opening a page never redeems an invitation.
- `apps/web/invite-hosting`: the Worker that serves the website, video ranges, and Apple association document.
- `backend`: Supabase migrations, account-deletion function, email templates, and security tests.

The app stores its session in Keychain. Invitation links carry an opaque token; the signed-in app redeems it through an idempotent database function. Row-level policies keep profiles, friendships, shared exploration, and private profile photos scoped to their owners and friends. Account deletion removes stored photos and revokes Apple credentials when applicable.

Cultural discoveries come from linked sources, with country checks and persistent seen-history. The first verified reading appears before optional enrichment finishes. Licensed images and Apple's on-device observations arrive independently. Saved readings survive relaunch, renew daily, and resume interrupted enrichment without repeating the search. Source links and image credits remain visible.

New profiles offer exploration sharing on the sign-in screen, enabled initially. Existing accounts keep their saved choice. Only post-sign-in exploration is synchronized, and turning sharing off removes shared records. Guest discovery and journals remain local.

Public service identifiers and routing are recorded in `ops/production.json`. Credentials are intentionally absent. `SocialConfiguration.local.json` can override the blank bundled configuration, and `Config/Signing.local.xcconfig` holds local signing settings; both are ignored. The web package uses examples for local tests; `scripts/prepare_site.py` creates a production routing snapshot from a committed revision. Backend credentials belong in the deployment platform's secret store. Start with the [handoff](handoff.md) and [deployment map](deployment.md) when continuing this project.
