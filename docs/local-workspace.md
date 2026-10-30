# One project, one checkout

Use `/Users/rb/dev/WorldNiche` on the owner's Mac. This is the GitHub repository and the configured local release project. Open that folder as the Codex project for new chats. No second public or App Store source copy is needed.

| Work | Location |
| --- | --- |
| iOS app and Xcode project | `apps/ios/WorldNiche.xcodeproj`, scheme `WorldNiche` |
| Website | `apps/web/`, deployed by Vercel after a merge to `main` |
| Database and Edge Functions | `backend/` |
| Public listing media | `marketing/app-store/` |
| Private build and review evidence | `outputs/`, ignored |
| Private export settings and recovery archives | `.local/`, ignored |

For a new task, pull current `main` and create a branch. Use a Git worktree when another task is already editing this checkout. Worktrees share Git history but not ignored local files. Guest builds and synthetic tests work without service credentials. Configured device or release builds need the owner's local files and Keychain access, supplied privately. Do not copy those files into public attachments or commits.

## Local configuration

- `apps/ios/Config/Signing.local.xcconfig`: Apple team settings, included by Xcode but excluded from app resources.
- `apps/ios/WorldNiche/Resources/SocialConfiguration.local.json`: the Supabase public client configuration and Apple sign-in flag. It is intentionally bundled into configured app builds. Never put backend service-role or AI keys here.
- `backend/.env.local`: backend operator secrets. Not bundled into the app or website.
- `.local/ExportOptions.local.plist`: private App Store export settings. The destination is a local export, not an automatic upload.
- Signing private keys and distribution certificates remain in Keychain; provisioning profiles remain in Xcode's local profile store.

The tracked `SocialConfiguration.json` stays blank. Its local override is loaded automatically. Source paths are relative so the repository can also be cloned elsewhere.

## Keep private files private

On a fresh clone, install Python 3 and Gitleaks, then enable the local guard:

```sh
git config core.hooksPath .githooks
bash scripts/check.sh private
```

The guard checks Git's index before a commit, rejects ignored files that were force-added, keeps the tracked service template blank, and runs Gitleaks on staged changes with secret values redacted. GitHub CI repeats the private-file checks and scans commit history. `.gitignore` covers local settings, credentials, signing material, archives, database dumps, build outputs and private evidence. Public screenshots and source stay tracked.

These checks prevent common accidents. Git ignore rules and local hooks can be bypassed deliberately, so do not use `git add -f` or `--no-verify` to publish private files. If a secret is ever pushed, revoke it immediately; adding it to `.gitignore` afterward does not remove it from history.

## Consolidation record

On October 30, 2026, the current GitHub checkout was moved from `WorldNiche-Public` to `WorldNiche`. The original configured source and clean older `WorldNiche2` clone were archived under `.local/archive/`, with file hashes verified before removing the duplicate folders. Existing release and review evidence moved into `outputs/`. Private configuration was restored at the paths above. Published tags and submitted app source were preserved.

See [the deployment guide](deployment.md) for tests, hosting, App Store signing and release steps.
