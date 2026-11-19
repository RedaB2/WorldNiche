# A quick look around

- `apps/ios`: the SwiftUI app and Xcode project. The globe uses native rendering. Country overviews, population figures and an initial fact catalog ship in the app. Reviewed fact updates and music charts load independently.
- `apps/web/landing-site`: the landing page, hand animation, and real app recording.
- `apps/web/invite-site`: the invitation fallback page. Opening a page never redeems an invitation.
- `apps/web/invite-hosting`: shared routing and packaging. Vercel serves static pages/media from its CDN and uses a small function for invitations and errors; the original Worker remains an archival build target.
- `backend`: Supabase migrations, account-deletion function, email templates, and security tests.

The app stores its session in Keychain. Invitation links carry an opaque token; the signed-in app redeems it through an idempotent database function. Row-level policies keep profiles, friendships, shared exploration, and private profile photos scoped to their owners and friends. Account deletion removes stored photos and revokes Apple credentials when applicable.

Country readings start with a short historical introduction and a population figure labeled with its year and source. The first visit shows the first reviewed fact. Reopening that day keeps the selected fact. On a later local date the next visit advances once. Next fact and pull to refresh advance immediately, and the cycle restarts after every available fact has appeared. The onboarding preview uses the same country selection.

The initial collection has two reviewed facts per country. Each published edition can carry up to five per country without an app update. Withdrawing the displayed fact selects an eligible replacement or clears the card if the country has none. Single-fact entries omit Next fact. Each fact links to its source, and both sharing and Ask Niche use the fact on screen.

The local journal remembers fact IDs separately for each country and account workspace. A fact change never queues a cloud journal update. Clearing device data erases this history. Apple Music supplies the default top five. A country without an Apple chart can show up to five tracks from Tuneping’s seven-day local radio chart. A provider error leaves the reading available offline.

New profiles offer exploration sharing on the sign-in screen, enabled initially. Existing accounts keep their saved choice. Only post-sign-in exploration is synchronized, and turning sharing off removes shared records. Guest discovery and journals remain local.

Public service identifiers and routing are recorded in `ops/production.json`. Credentials are intentionally absent. `SocialConfiguration.local.json` can override the blank bundled configuration, and `Config/Signing.local.xcconfig` holds local signing settings; both are ignored. The web package uses examples for local Worker tests; `npm --prefix apps/web run build:vercel` reads the public production IDs and generates the checked Vercel output. Merges to `main` deploy through the Vercel GitHub integration. `scripts/prepare_site.py` retains the legacy Sites packaging flow for archival use. Backend credentials belong in the deployment platform's secret store. Start with the [handoff](handoff.md) and [deployment map](deployment.md) when continuing this project.
