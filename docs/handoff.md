# Pick up from here

**Source of truth:** [RedaB2/WorldNiche](https://github.com/RedaB2/WorldNiche), branch `main`. No access to the original chat is needed to work on the code. Deploying needs the owner's access to the relevant service.

## Current release

As checked October 29, 2026, WorldNiche **1.0 (8)** is **Waiting for Review** in App Store Connect. It was submitted at 6:28 p.m. Pacific and will require manual release after approval. Build 8 is also available in the [public TestFlight beta](https://testflight.apple.com/join/kqpQhYFw). The app status is a dated snapshot, not a live feed. The website moved from Sites version 16 to Vercel on October 30; merges to `main` now publish it automatically.

The `v1.0.0` tag marks this first submitted version. Documentation and CI were added after submission; app runtime source is unchanged. [Machine-readable release record](../ops/releases/1.0.json) · [submission checklist](app-store-readiness.md).

## Find the right place

| Want to change | Edit |
| --- | --- |
| Globe, onboarding, country screens, profile, journal | `apps/ios/WorldNiche/` |
| Country catalog, cultural topics, feed mappings | `apps/ios/WorldNiche/Resources/` |
| Landing page, demos, friends animation, public policies | `apps/web/landing-site/` |
| Friend link fallback and Universal Link routing | `apps/web/invite-site/`, `apps/web/invite-hosting/` |
| Accounts, friendship access, journal sync, moderation | `backend/supabase/` |
| App Store screenshots and preview | `marketing/app-store/1.0/` |
| App Store title, description, keywords and URLs | `metadata/app-info/`, `metadata/version/` |
| Logo and onboarding portraits | `apps/ios/WorldNiche/Assets.xcassets/`; website copies in `apps/web/landing-site/assets/` |
| Deployments, service IDs and current release | `docs/deployment.md`, `ops/` |

## A normal change

1. Pull `main`, check `AGENTS.md`, and create a branch. Inspect existing changes before editing.
2. Enable the local commit guard with `git config core.hooksPath .githooks` (Python 3 and Gitleaks required). Run `bash scripts/check.sh private` and the relevant suites: `web`, `backend`, `swift`, or `assets`. `all` runs everything on a Mac with Swift 6, Node 24+ and PostgreSQL installed.
3. For native UI changes, use XcodeBuildMCP to test the affected scenarios on a phone and an unfolded Duo. CI covers synthetic profile/journal flows; live news, Apple authorization, push-to-device and Duo testing remain release checks.
4. Review the diff for credentials and private data, then commit under the owner's GitHub identity. Open a PR and inspect [GitHub Actions](https://github.com/RedaB2/WorldNiche/actions).
5. Merge passing changes. Website changes publish through Vercel automatically; check `/deployment.json` against the merged commit. Backend and iOS publishing remain separate. Follow the [deployment guide](deployment.md) for the affected service.

## Important behavior

- The app is usable as a guest. Account entry uses only Sign in with Apple. New profiles choose their name and an optional photo; initials cover skipped photos.
- Music, news and cultural readings load and retry independently. News is attributed Global Voices content. Preserve source and image-license checks.
- Private journal notes and bookmarks never become friend-visible. Friend exploration sharing defaults on for new accounts and respects existing choices.
- Profile edits are immediate for their owner. Approved versions become visible to friends. Backend quotas and a scheduled worker process the latest eligible revision.
- Signup remembers the user's automatic-check choice. Do not reintroduce per-upload consent or remove the required privacy choice.
- Account deletion revokes Apple authorization and removes account data. Never test it with a real profile unless its owner explicitly agrees.

## Release handoff

The owner verified the private reviewer invite, five countries and duplicate prevention on TestFlight build 7, then completed Apple account deletion. Backend erasure and removal from Apple settings were confirmed. Build 8 changes the shared account-entry button, with 14 focused scenarios passing on each phone and Duo. Daily retention is installed and verified. Details are in [App Store readiness](app-store-readiness.md).

The reviewer invitation expires **November 29, 2026 at 00:54 UTC**. Its token and reviewer contact phone are only in App Store Connect/private release evidence. Renew the invitation if review lasts that long. Do not publish it in issues or documentation.

The owner monitors `boutayeb.reda@icloud.com` and the private moderation queue. Keep the backend and public support/privacy pages available during review. App Store release remains a separate owner decision after approval.

## Existing local files

On Reda's Mac, **`/Users/rb/dev/WorldNiche` is the single working repository** for the app, website, backend, App Store builds and GitHub PRs. Open this folder as the Codex project for new chats. Open `apps/ios/WorldNiche.xcodeproj` in Xcode, scheme `WorldNiche`.

The former `WorldNiche-Public` checkout was moved here without changing Git history. The older configured folder and clean `WorldNiche2` clone were verified and preserved as private recovery archives in `.local/archive/`. They are backups, not alternate workspaces. App source, assets and UI tests matched before consolidation; newer repository tests and website deployment code were preserved.

Private local files are `apps/ios/Config/Signing.local.xcconfig`, `apps/ios/WorldNiche/Resources/SocialConfiguration.local.json`, `backend/.env.local`, and `.local/ExportOptions.local.plist`. They are ignored. Signing certificates and private keys stay in the owner's Keychain. The checked-in service JSON remains a blank template. See [local workspace setup](local-workspace.md).

Private archives, IPAs and signing diagnostics are under `/Users/rb/dev/WorldNiche/outputs/testflight/1.0-8/`. Private reviewer/deletion evidence is under `/Users/rb/dev/WorldNiche/outputs/app-store-1.0/submission-review/`. The `127.0.0.1:8767` submission preview was just a local review page, not website hosting. These private files are not prerequisites for ordinary development.

## Brief for another agent

> Work in /Users/rb/dev/WorldNiche, the RedaB2/WorldNiche repository. Read AGENTS.md, docs/handoff.md and docs/deployment.md. Preserve the submitted v1.0.0 release. Make the requested change on a branch or worktree, run the private-file check, relevant suites and simulator tests, and show the diff and deployment target. Use this same source for App Store builds. Website merges to main publish automatically through Vercel; verify the live commit afterward. Use the service IDs in ops/production.json. Keep secrets and reviewer invitations private. Report separately what is committed, what passed CI and what is actually deployed.
