# Working on WorldNiche

Read `docs/handoff.md` and `docs/deployment.md` before changing or deploying anything. This repository is the source of truth; another chat is not a dependency.

- App: `apps/ios`. Website: `apps/web`. Database and Edge Functions: `backend`. Listing assets: `marketing/app-store`.
- Use a branch for new work. Keep the submitted version intact. Never move a published release tag.
- Commit as the owner's configured GitHub identity. Do not add assistant attribution or coauthor trailers. No em dashes in documentation or comments.
- Run the relevant checks in `scripts/check.sh`. Native changes also need simulator UI tests on a phone and unfolded Duo. Live Apple authorization/deletion tests require a consenting disposable account.
- Production deploys are separate from Git pushes. Follow `docs/deployment.md`, record the source commit and verify the resulting live state. A green build is not a deployed build.
- Never commit local configuration, keys, signed packages, account exports, private reviewer invitations or real user data. Do not print credentials. CI uses synthetic data and does not call paid AI services.
- Preserve music/news/culture failure isolation, source attribution, private journals, sharing preferences and moderation safeguards.
- Do not reset production data, accept legal terms, send messages, change public access or release the App Store version without the owner's authorization for that action.
