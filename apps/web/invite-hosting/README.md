# Website routing

Shared routing serves the landing page, invitation fallback and Apple association document. Opening an invitation page never redeems its token or looks up profiles.

Production uses Vercel with `apps/web` as the project root. `npm --prefix apps/web run build:vercel` creates `.vercel/output`, with pages, images and videos on the CDN and a small function for invitation/error routes. It reads public routing IDs from `ops/production.json` and checks exact asset bytes, headers and invitation behavior. Vercel runs the website tests before every build and publishes `main` automatically.

The original `npm run build`, `npm test` and `npm run validate` commands still exercise the Worker package. Ignored local routing files override the examples for that legacy build. `scripts/prepare_site.py` preserves the old Sites delivery format for archival use, not production publishing.

See [the deployment guide](../../../docs/deployment.md) for the GitHub workflow, live checks and rollback.
