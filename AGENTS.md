# Working on WorldNiche

Read `docs/handoff.md` and `docs/deployment.md` before changing or deploying anything. This repository is the source of truth; another chat is not a dependency.

- On the owner's Mac, use `/Users/rb/dev/WorldNiche` for editing, signing, archiving and GitHub work. Do not recreate a separate public or release copy. Use a branch or Git worktree for parallel work; worktrees do not automatically receive ignored local configuration.
- App: `apps/ios`. Website: `apps/web`. Database and Edge Functions: `backend`. Listing assets: `marketing/app-store`.
- Use a branch for new work. Keep the submitted version intact. Never move a published release tag.
- Commit as the owner's configured GitHub identity. Do not add assistant attribution or coauthor trailers. No em dashes in documentation or comments.
- Run the relevant checks in `scripts/check.sh`. Native changes also need simulator UI tests on a phone and unfolded Duo. Live Apple authorization/deletion tests require a consenting disposable account.
- Website merges to `main` publish automatically through Vercel after its website checks. Backend and iOS releases remain explicit. Follow `docs/deployment.md` and verify the live commit; a green GitHub check alone is not proof of deployment.
- Never commit local configuration, keys, signed packages, account exports, private reviewer invitations or real user data. Do not print credentials. CI uses synthetic data and does not call paid AI services.
- Enable the commit guard with `git config core.hooksPath .githooks` on a fresh clone. It requires Python 3 and Gitleaks. Run `bash scripts/check.sh private` before pushing. Keep private recovery archives in ignored `.local/` and build/review evidence in ignored `outputs/`.
- Preserve music/news/culture failure isolation, source attribution, private journals, sharing preferences and moderation safeguards.
- Do not reset production data, accept legal terms, send messages, change public access or release the App Store version without the owner's authorization for that action.
