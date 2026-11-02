# Country exploration

Opening a country no longer marks it explored. A small, three-part clay progress line stays below the country toolbar while the user reads culture, music and local stories. The existing paper, pine, serif type and glass controls remain the visual language.

Each section contributes equally. After scrolling, content must rest visibly for 650 milliseconds before it earns coverage. Eighteen of twenty vertical bands in each section unlock completion. Loading placeholders earn nothing; settled unavailable states and the saved cultural fallback can earn coverage, so one failed provider does not block exploration. Music links remain optional and do not require a subscription or external playback.

At the end, hold the leaf for 900 milliseconds, or pull up past the bottom and keep holding. A clay ring fills, changes to a pine check, and confirms that the country is saved to the journal. Releasing early cancels. VoiceOver and other assistive activation use the same completion action without a timed gesture. Reduce Motion removes the ring and scale animation. Incomplete reading has a Continue exploring control that returns to the first unfinished section.

Coverage is a reading cue, not proof of comprehension. A quick jump cannot credit skipped sections. Progress survives closing and relaunching on this device and stays within the existing guest/account workspaces. It is included in local data exports and erased with local data. Partial progress is not uploaded or shared with friends. Only confirmed completion uses the existing exploration sync and sharing preference. No backend change is required.

Previously explored countries remain explored. Reopening or refreshing them does not change their exploration dates. Bookmarks, private notes, feed retries and source attribution retain their existing behavior.

## Validation

`CountryReadingUITests` exercises opening without completion, partial progress across relaunch, cancelling a short hold, completing and reopening, bottom pull and hold, unavailable feeds and accessibility text sizes. Its simulator-only content fixtures make no provider or paid AI calls. Journal checks cover coverage gaps, persistence, legacy decoding, sync isolation, confirmation, duplicate completion and workspace reset/restore.

Builds, simulator results and the review video are kept under ignored `outputs/country-reading-progress/`. No App Store, TestFlight or backend release is part of this change.
