# Moderation

WorldNiche holds custom names and photos for human review before friends can see them. There is no external AI moderation provider or automatic photo approval. Symbols and the default Explorer name are available immediately. Existing approved content stays visible while an edit is pending. Links, control characters, and invisible formatting in names are rejected before review.

The database enforces this for every client. Pending content is owner-only, and review RPCs require the server role. Approval applies to an exact submission revision. Selected or queued photos cannot be deleted and replaced underneath a review. Blocking and moderator restrictions remove app-managed friend access. Native photo reads use a fresh cache nonce so a previous CDN response cannot bypass the current access check. Independently cached or downloaded copies cannot be recalled. Restricted users can still export and delete their accounts.

## Operator workflow

Reda Boutayeb is the published support contact. Before inviting public testers, establish a daily queue review routine and monitor the support inbox. Review urgent safety reports promptly. This code does not replace a human operator or send automatic email alerts.

Use Supabase's protected SQL editor with `select public.moderation_queue(200);`, or run `backend/scripts/moderate.mjs` from a trusted terminal. Set `WORLDNICHE_SERVICE_URL` and `WORLDNICHE_SERVICE_KEY` only in the operator's local session. Never place a server key in source, the app, a browser page, or a screenshot. The tool does not store credentials.

1. `node backend/scripts/moderate.mjs queue` lists pending submissions and reports, oldest first. Process batches until the counts reach zero.
2. Read each submitted name. For photos, use `photo USER PATH OUTPUT` to download a private review copy, inspect it, and remove that local copy afterward. Never approve an image from its filename or MIME type alone.
3. Use `review USER name|photo REVISION approve|reject "reason"`. Copy the revision from the inspected queue. A changed submission makes approval fail; refresh and inspect again.
4. For reports, use `action USER remove_name|remove_photo|remove_content|restrict|dismiss_report REPORT_ID "reason"`. Restrictions stop sharing and invitations. `restore` does not republish removed content or restore revoked links.
5. Handle appeals through the support inbox. Record factual decisions and avoid unrelated sensitive information.

Reject sexual or exploitative imagery, graphic violence, hateful symbols or language, threats, harassment, impersonation, personal information shared without permission, scams, and spam. Follow the public [community guidelines](https://worldniche.app/community). Escalate urgent or legally sensitive matters appropriately. Do not retain unnecessary copies of illegal material.

Reports keep the visible name and photo reference at reporting time. The reference does not guarantee the image remains stored. Open reports are not aged out. Resolved reports may be cleared after 90 days if maintenance is installed. Account deletion removes submissions, reports and decisions; the deletion function erases storage objects before Auth deletion.

## Verification

`backend/tests/run_database.sh` creates a disposable local cluster and checks quarantine, owner/friend isolation, immutable review, stale decisions, restrictions, report privacy, export, and deletion cascades. It also tests invitation, blocking, revocation, and sharing races.

`backend/tests/hosted_social.mjs --live --project-ref PROJECT` creates three disposable accounts through admin-generated links, sends no emails, exercises normal authenticated APIs, and cleans up only the exact accounts created in that run. Keys come from process environment; `WORLDNICHE_TEST_PHOTO` points to a harmless JPEG. Never use a person's account. Actual Apple revocation requires a separate consenting Apple test identity.
