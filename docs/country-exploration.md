# Country exploration

Selecting a destination with Take me somewhere, tapping a country on the globe, or opening a country from Atlas does not mark it explored. One continuous clay progress line stays below the country toolbar and fills smoothly with the percentage of the card scrolled. The existing paper, pine, serif type and glass controls remain the visual language.

Progress is the furthest scroll offset divided by the available scroll distance, from zero at the top to 100 percent at the bottom. It updates during every scroll without section milestones or a reading pause. Scrolling back, reopening the card or loading more content never reduces saved progress. The bar follows fractional progress continuously; persistent writes are coalesced at each whole percentage and when scrolling stops or the card closes. Music links remain optional and do not require a subscription or external playback.

At the end, hold the leaf for 900 milliseconds, or pull up past the bottom and keep holding. A clay ring fills, changes to a pine check, and confirms that the country is saved to the journal. Releasing early cancels. VoiceOver and other assistive activation use the same completion action without a timed gesture. Reduce Motion removes the progress, ring and scale animations.

Scroll progress is a reading cue, not proof of comprehension. A fast scroll can reach 100 percent, but confirmation is still required to mark a country explored. Progress survives closing and relaunching on this device and stays within the existing guest/account workspaces. It is included in local data exports and erased with local data. Partial progress is not uploaded or shared with friends. Only confirmed completion uses the existing exploration sync and sharing preference. No backend change is required.

Previously explored countries remain explored. Reopening or refreshing them does not change their exploration dates. Bookmarks, private notes, feed retries and source attribution retain their existing behavior. Opening a country from Atlas dismisses search keyboard focus, so it does not obscure the journal controls when the sheet closes.

## Validation

`CountryReadingUITests` exercises Take me somewhere without premature exploration, shared progress between Discover and Atlas, gradual scroll progress, backward scrolling without regression, partial progress across relaunch, cancelling a short hold, completing and reopening, bottom pull and hold, unavailable feeds and accessibility text sizes. The globe selection test separately checks that previewing countries leaves their discovery incomplete and does not increase explored history. These tests use simulator-only content fixtures without provider or paid AI calls. Journal checks cover scroll geometry, continuous fractions, monotonic persistence, legacy decoding, sync isolation, confirmation, duplicate completion and workspace reset/restore.

Simulator results and the review video are kept under ignored `outputs/country-reading-progress/`. The owner's authorized TestFlight candidate is **1.0.1 (12)**; package and availability evidence are recorded in [TestFlight status](testflight.md) and ignored `outputs/testflight/1.0.1-12/`. App Store and backend releases remain separate.
