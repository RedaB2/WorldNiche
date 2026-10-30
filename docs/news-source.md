# News source

Build 7 replaces Google News RSS with Global Voices' licensed country feeds. Each story shows its author, publisher, publication date, original link and a CC BY 3.0 license link. The app does not copy article bodies or news photographs. [Rights and attribution](../licenses/GLOBAL-VOICES.md).

The bundled directory maps 193 of the app's 195 countries to the publisher's actual feed directory. Andorra and Micronesia have no listed feed. Coverage varies: an existing feed does not promise a daily story. Stories older than a year are excluded, and empty coverage has an explicit unavailable state. News remains independent of music, with its own refresh, retry and 15-minute memory cache.

## Checks on October 29, 2026

- A live probe covered Morocco, France, the United States, Japan, Georgia, both Congos, Dominica, Brazil, India, Senegal, New Zealand, Vatican City, Kenya, South Korea and the United Kingdom. Requests took roughly 1.2 to 1.7 seconds in that sample. Vatican City had no recent attributed story, which is a valid empty result.
- South Korea exposed an XML-forbidden control character in an unused article body. The parser now replaces only forbidden scalars and still requires valid RSS. The real Swift client then loaded four stories. A regression fixture covers the same failure.
- Deterministic checks pass for bylines, trusted original URLs, duplicate filtering, invalid dates, old/future stories, absent feeds, malformed XML, cancellation, transient failures, retries, independent caches and out-of-order refresh completion.
- Live Swift checks pass for all sixteen news feeds, including the expected empty Vatican City result, plus France's Apple Music chart. Run `bash apps/ios/Scripts/test_feeds.sh --live --live-coverage` to repeat that sample.
- Both live news simulator scenarios pass on iPhone 17 Pro Max and unfolded iPhone Duo: Morocco's country sheet and the United States onboarding preview. They verify visible publisher/license information and author attribution. The unfolded test uses short gestures inside the sheet so it does not swipe outside the presented content.
- Existing onboarding checks confirm only one preview opens at a time and retrying music preserves news.

The coverage sample is a point-in-time check, not an uptime or completeness guarantee. The source can return empty feeds or change content independently of an app release.
