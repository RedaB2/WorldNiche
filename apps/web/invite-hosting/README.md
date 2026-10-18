# Website routing

This Worker serves the landing page, invitation fallback, and Apple's association document from one package. Video requests support byte ranges for Safari. Invitation pages do not redeem tokens or request profiles.

`npm run build` imports the sibling website sources and builds `dist/server/index.js`; `npm test` and `npm run validate` check the output. Local hosting and app-association settings override the example files through ignored `hosting.local.json` and `association.local.json`. Example values are for local builds only, never production deployment.
