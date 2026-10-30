# Repository audit, October 29, 2026

The public `main` branch and local checkout matched commit `3a5ed94` at the start of this audit. This handoff update adds documentation, CI and a reproducible website delivery step without changing the submitted app or website runtime behavior.

| Area | Evidence |
| --- | --- |
| App implementation and assets | All tracked files under `WorldNiche/` match the configured build mirror, except the intentionally blank public service configuration. The public repo includes newer feed/image-license tests. |
| Website source | Landing assets, scripts, HTML and invite runtime files match the Sites source checkout at `051505aceddbe8eafa190a6579710dddc1f06637`, the commit reported for live version 16. |
| Hosting | Sites reports public/active version 16, custom domain active, TLS active. DNS resolves to the Sites proxy addresses and Squarespace nameservers. |
| Live assets | Logos, portraits, hand mockups, posters, both demo videos, CSS and JS match the repository bytes. Public HTML contains Cloudflare's injected request-specific security script, so its raw response hash differs from the source. |
| App Store media | All 10 listing screenshots and the Morocco preview are tracked. All 11 SHA-256 hashes match the release manifest, including image dimensions. Raw simulator captures and the poster renderer are tracked too. |
| Apple submission | Fresh API readback: version 1.0, build 8, `WAITING_FOR_REVIEW`, `MANUAL` release. The repo's submission checklist already reflected the submitted state. |
| Private operational files | Configured binaries, signing material, credentials, private reviewer invite/contact details and deletion evidence remain outside Git. Their locations and access requirements are documented in the handoff. |

The older local build folder is not another source of truth. Its remaining differences are local configuration, comments, path adaptations and older test helpers. Future edits should start in this monorepo. The production Supabase state was verified during the submission checks; this repository audit does not claim to have repeated destructive account tests or redeployed the backend.

Before this update, no GitHub Actions workflow or independent deployment handoff existed. The new workflow provides automatic tests and a commit-linked website artifact; production publication remains explicit. See [deployment](deployment.md) for exact boundaries and [handoff](handoff.md) for another agent's starting point.

Verification for this update: 41 website tests plus packaged-route/media validation; all 11 listing checksums; the deletion/moderation and isolated database suites; all six Swift harnesses; and all nine selected profile/journal simulator tests from the public checkout passed. Full Git history secret scanning found no leaks. The prepared production Worker matches the last published Worker byte for byte, including its association document. Invalid Git references and existing output directories are rejected, and local credential files are excluded.

Two stale test assumptions surfaced while making this portable: the avatar harness needed its journal model dependencies, and shared CI hardware could exceed a fixed 300 ms culture benchmark despite making the correct two requests. The harness now includes those models; regular CI asserts request order and progressive result content, while `bash apps/ios/Scripts/test_live_culture.sh --performance` retains the opt-in 300 ms local benchmark. That benchmark also passed. The app implementation is unchanged.

The CI secret scanner uses Gitleaks 8.24.3, while the local scanner is 8.30.1. Its older parser ignored the newer global allowlist format and flagged two UserDefaults storage identifiers in historical commits. The compatible configuration exempts only those two exact strings. Full history passes on both versions, and a synthetic credential is still detected on both.
