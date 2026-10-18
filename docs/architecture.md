# A quick look around

- `apps/ios`: the SwiftUI app and Xcode project. The globe uses native rendering; music, news, and cultural discoveries have separate loading and retry states.
- `apps/web/landing-site`: the landing page, hand animation, and real app recording.
- `apps/web/invite-site`: the invitation fallback page. Opening a page never redeems an invitation.
- `apps/web/invite-hosting`: the Worker that serves the website, video ranges, and Apple association document.
- `backend`: Supabase migrations, account-deletion function, email templates, and security tests.

The app stores its session in Keychain. Invitation links carry an opaque token; the signed-in app redeems it through an idempotent database function. Row-level policies keep profiles, friendships, shared exploration, and private profile photos scoped to their owners and friends. Account deletion removes stored photos and revokes Apple credentials when applicable.

Cultural discoveries come from linked sources, with country checks and persistent seen-history. Compatible devices can use Apple's on-device model to select a source-grounded detail. Source links and image credits remain visible.

Deployment configuration is intentionally absent. `SocialConfiguration.local.json` can override the blank bundled configuration, and `Config/Signing.local.xcconfig` holds local signing settings; both are ignored. The web package has example association and hosting files with ignored local overrides. Backend credentials belong in the deployment platform's secret store.
