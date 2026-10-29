# Private journals

Signed-in account journals sync saved countries, private notes, and first and most recent exploration times. The country catalog supplies names and other stable country details by ID. No location coordinates, raw taps, music listening history or Ask Niche conversations are collected for this feature.

Guests retain a device-only journal. Signing in switches to the account's separate workspace, without publishing or importing guest activity. Account notes and bookmarks are never visible to friends and never sent to profile moderation.

## Storage and access

`public.wn_journal` holds one entry per account and country, including saved state, a note, exploration dates, creation time and field update times. Row-level security permits only the active owner to read it. Direct client writes are denied. The `sync_journal` RPC validates the active session, owner, profile deletion state, country IDs, field types, dates and note size.

`wn_private.journal_clocks` stores only device identifiers and field sequence numbers. It prevents a repeated request, such as a retry after a lost response, from overwriting newer content. Notes are limited to 4,000 Unicode scalars. Each request is bounded and account-limited; journal synchronization makes no AI requests.

Only explored country IDs are projected into `wn_explorations` when friend sharing is enabled. Turning sharing off removes that shared projection and preserves the private journal. Account deletion cascades both journal tables; the account export includes journal content.

## Offline edits and multiple devices

Local entries and pending field changes are persisted immediately. Sync runs after edits, on session restoration, on Journal entry and on pull-to-refresh. A failed request retains pending edits and shows a retry in Journal. Saved state, notes and exploration dates sync independently, so saving a country does not replace a note edited on another device. Changes made during an upload are sent in the next batch. Delayed responses cannot switch account workspaces or replace an unsent note.

For concurrent edits to the same note from different devices, the last newly accepted edit wins. The app does not keep a note revision history. Exploration dates merge to the earliest and latest known times. Legacy device journals migrate locally, and existing shared exploration rows seed the cloud journal. Old builds remain compatible with their existing sharing endpoint.

## Verification

Run the journal and social scripts in `apps/ios/Scripts`, the database suite in `backend/tests/run_database.sh`, and `JournalUITests` on both iPhone and unfolded Duo. Database checks cover private reads and writes, sharing opt-out, friends, retries across devices, invalid data, data export, account deletion, stale sessions and anonymous access. Hosted checks use a transaction that rolls back all temporary accounts and records.

On October 29, 2026, 21 journal checks, 408 social checks, 12 intro checks, the full local database suite, the hosted rollback-only journal checks and 32 website checks passed. All 12 selected onboarding, profile setup and journal scenarios passed on iPhone 17 Pro Max and unfolded iPhone Duo, including accessibility text size. Simulator diagnostics included non-failing layout and QoS warnings; no test failures remained. The avatar placement was also checked visually. The updated privacy and deletion pages are live in site version 14.
