# Moderation

Automatic profile checks are live in the backend as of October 27. Database migrations 005, 006 and 007, upload quotas, provider reservations and the guarded worker are installed. Cloud secrets are configured, provider processing is enabled, and the minute-based retry job is active. A hosted test verified approval, friend visibility, held unsafe content, cooldown recovery and deletion, then removed all four disposable accounts. Privacy, security and community pages are published in site version 11 with the signup choices and simpler public explanations. See the [public beta notes](testflight.md) for build availability.

Symbols and the default Explorer name are available immediately. Existing approved content stays visible to friends while an edit is pending. Links, control characters, and invisible formatting in names are rejected before review. Saved names and photos appear immediately in the owner's private profile. Signup asks for a chosen name and optional photo; initials are used without a photo. A one-time, explicit permission choice is stored with the account and applies to later edits. Normal edits do not show moderation prompts. Rejections and account restrictions still explain what the user needs to change.

## Automatic checks

The `moderate-profile` Edge function uses OpenAI's `omni-moderation-latest` endpoint. Each person must grant separate, revocable permission before submitted names or photos are sent to OpenAI. Exploration sharing does not grant that permission. Existing submissions stay private and are not sent unless that person enables automatic checks. Declining keeps the human review route available.

The app saves the submission first and displays it privately. The backend then checks the exact saved revision, publishing passing content for friends automatically. A flagged result goes to human review. Provider outages, timeouts, incomplete responses, and missing coverage produce a retry without publishing unchecked content. The previous approved profile stays visible to friends until the new content passes. An app-managed refresh updates visible friend screens without requiring another invitation.

The function accepts no client-supplied user IDs, content, or media URLs. Native requests are authenticated through `authorize_profile_check`, which verifies the live Auth session and rate-limits calls. Scheduled work requires a separate scoped worker secret. Only the server role can claim or finish jobs. Photos are fetched from the private bucket, limited to 300 KB, and sent as JPEG data rather than a public or signed storage URL. Names and photos are sent separately without account IDs, email addresses, friendship lists, or exploration history.

The database supplies revision-specific jobs, exclusive claims, retry backoff, and consent, restriction, and deletion checks. Migration `202610240006_profile_check_disclosure.sql` adds a service-only claim check immediately before external disclosure. A withdrawal after a request has started cannot recall that request, but its result cannot publish content after consent is withdrawn. No credentials, submitted content, or provider response bodies are logged by the worker.

### Abuse controls

Migration `202610270007_moderation_abuse_limits.sql` puts an atomic reservation immediately before every OpenAI request. Native requests, upload-triggered work and scheduled retries share the same rolling limits. A database lock serializes reservations across workers and accounts; a claim can reserve only once. Timeouts, provider errors and crashed workers still consume their allowance.

| Limit | Per minute | Per hour | Per 24 hours |
| --- | ---: | ---: | ---: |
| Provider requests per account | 4 | 12 | 30 |
| Provider requests across the app | 30 | 300 | 1,000 |
| Accepted photo uploads per account | 6 | 20 | 40 |

These are initial beta limits. Each submitted revision gets at most five provider attempts before human review. Names and photos count separately. Replacing a pending edit or toggling permission does not reset the account or shared quota. Deleting an account removes its identity from reservation records but leaves the anonymous usage charge until it expires, so account recreation cannot reset the shared budget. Daily reservation cleanup is scheduled to remove records older than 25 hours; its first scheduled execution is still pending.

When a provider limit is reached, the saved submission stays private and is scheduled for the earliest eligible time. The minute-based worker checks it after the cooldown without needing the app open. New edits replace the pending revision, so only the latest accepted version can publish. Friends keep seeing the previous approved content. Flagged content and revisions that exhaust their attempts need human review; those are not automatically retried forever.

The upload limit is separate: a rejected upload is not saved or queued. The app keeps the selected photo available for the person to retry and shows an error. Deleting and uploading again does not refund accepted-upload usage. Restricted accounts cannot upload. The private JPEG size and stored-object limits still apply.

The worker accepts no arbitrary prompts, models or URLs and calls only the fixed moderation endpoint. A missing, malformed or unavailable reservation response never permits a provider call. Limits are server-owned; authenticated clients cannot change them or approve their own content.

The backend key is restricted to `api.model.moderations.request`. A direct moderation request succeeded, while a model-catalog request returned 403. Runtime credentials are stored in encrypted cloud secrets and stay out of the app, website and public repository. An operator-only local copy is kept outside the repository. The default OpenAI project currently contains only this key and has a verified $5 monthly hard spend limit with a 100% alert. The platform shows the limit as enforced, but enforcement can have a small delay and overshoot. The shared backend request limits remain independently enforced. See [key permissions](https://help.openai.com/en/articles/9186755-managing-projects-in-the-api-platform) and [spend limits](https://developers.openai.com/api/docs/guides/spend-limits).

### Classifier limits

The worker uses the provider's boolean flags, with no custom confidence-score threshold. It validates the complete response and expected modality coverage before approving anything. Confidence scores are not proof that a photo is safe. OpenAI documents that image-only inputs do not support hate, harassment, illicit activity, or the sexual/minors category. The image classifier covers sexual content, self-harm, and violence categories. It also does not establish identity, consent to a photograph, copyright ownership, or authenticity. Reports, blocking, manual enforcement, and appeals remain part of moderation. Do not advertise this as comprehensive image safety or a guarantee of App Store approval. See the [OpenAI moderation guide](https://developers.openai.com/api/docs/guides/moderation).

### Deployment gate

Apply migrations `202610240005_automatic_profile_checks.sql`, `202610240006_profile_check_disclosure.sql` and `202610270007_moderation_abuse_limits.sql` before deploying `moderate-profile`. Set `OPENAI_API_KEY` and `WORLDNICHE_MODERATION_WORKER_SECRET` only as backend secrets. Supabase supplies its project URL, public API key, and server API key. Disable the Edge gateway JWT check for this function because scheduled calls use the scoped worker secret; the function itself verifies either the worker secret or the native caller through the session-checking RPC.

Enable pg_net, pg_cron, and Vault. Store `worldniche_moderation_url` and `worldniche_moderation_worker_secret` in Vault, with the same scoped worker secret used by the Edge function. `configure_profile_checks.sql` refuses to configure retries without those dependencies. It installs a minute-based retry schedule. Verify a successful cron invocation, a successful worker response, a passing opted-in synthetic name/photo, a held flagged submission, and friend visibility before release. Keep the human queue and support inbox monitored.

Vault protects stored secrets, but pg_net temporarily places the decrypted worker token in `net.http_request_queue`. Every role with database login access can read it there. The OpenAI key stays in Edge secrets and never enters that queue. Before enabling scheduling, confirm that `net` is absent from the Data API's exposed schemas and that database login roles belong only to trusted services. Inspect configuration and role metadata without printing queued headers or secrets. Hosted pg_net grants are a platform constraint; a `REVOKE` issued as `postgres` does not secure them. See [queued credentials](https://supabase.com/kb/troubleshooting/database-roles-can-read-request-headers-queued-by-pg_net) and [supported access controls](https://supabase.com/kb/troubleshooting/revoking-access-to-pg_net-objects-has-no-effect).

The database enforces this for every client. Pending content is owner-only, and review RPCs require the server role. Approval applies to an exact submission revision. Selected or queued photos cannot be deleted and replaced underneath a review. Blocking and moderator restrictions remove app-managed friend access. Native photo reads use a fresh cache nonce so a previous CDN response cannot bypass the current access check. Independently cached or downloaded copies cannot be recalled. Restricted users can still export and delete their accounts.

## Operator workflow

Reda Boutayeb is the published support contact. Before inviting public testers, establish a daily queue review routine and monitor the support inbox. Review urgent safety reports promptly. This code does not replace a human operator or send automatic email alerts.

Use Supabase's protected SQL editor with `select public.moderation_queue(200);`, or run `backend/scripts/moderate.mjs` from a trusted terminal. Set `WORLDNICHE_SERVICE_URL` and `WORLDNICHE_SERVICE_KEY` only in the operator's local session. Never place a server key in source, the app, a browser page, or a screenshot. The tool does not store credentials.

To pause new provider requests, run `update wn_private.profile_check_limits set enabled = false where singleton;` in the protected SQL editor. Requests already sent cannot be recalled. Set it back to `true` to resume pending work through the normal schedule. Review hourly and daily reservation counts and pending jobs when investigating abuse. Changing limits must be an operator decision, never a response to client input. The shared cap protects API usage; it is not a promise of uninterrupted service during an account-creation attack.

1. `node backend/scripts/moderate.mjs queue` lists pending submissions and reports, oldest first. Process batches until the counts reach zero.
2. Read each submitted name. For photos, use `photo USER PATH OUTPUT` to download a private review copy, inspect it, and remove that local copy afterward. Never approve an image from its filename or MIME type alone.
3. Use `review USER name|photo REVISION approve|reject "reason"`. Copy the revision from the inspected queue. A changed submission makes approval fail; refresh and inspect again.
4. For reports, use `action USER remove_name|remove_photo|remove_content|restrict|dismiss_report REPORT_ID "reason"`. Restrictions stop sharing and invitations. `restore` does not republish removed content or restore revoked links.
5. Handle appeals through the support inbox. Record factual decisions and avoid unrelated sensitive information.

Reject sexual or exploitative imagery, graphic violence, hateful symbols or language, threats, harassment, impersonation, personal information shared without permission, scams, and spam. Follow the public [community guidelines](https://worldniche.app/community). Escalate urgent or legally sensitive matters appropriately. Do not retain unnecessary copies of illegal material.

Reports keep the visible name and photo reference at reporting time. The reference does not guarantee the image remains stored. Open reports are not aged out. Resolved reports may be cleared after 90 days if maintenance is installed. Account deletion removes submissions, reports and decisions; the deletion function erases storage objects before Auth deletion.

## Verification

On October 27, 124 database abuse assertions, 81 isolated handler tests, 348 native social checks, 54 avatar checks and all 18 iOS 27.0 simulator tests passed. The hosted moderation run passed eight groups with real provider processing: approved name/photo publication, friend photo access, subsequent profile updates, held threatening text, latest-edit recovery after cooldown, consent isolation and account deletion. Cleanup was confirmed for all four disposable accounts. Minute-based cron runs at 23:38 and 23:39 UTC succeeded, with corresponding HTTP 200 responses and no timeout or error. Only synthetic test content was submitted by that run. It did not test revoking a real Apple authorization.

`backend/tests/run_database.sh` creates a disposable local cluster and checks quarantine, owner/friend isolation, immutable review, stale decisions, restrictions, report privacy, export, and deletion cascades. It also tests invitation, blocking, revocation, sharing races, the worker's permission to disclose a specific claimed revision, rolling quotas, cooldowns, replacement revisions, retry exhaustion and concurrent reservations.

Run `node --test backend/tests/moderate_profile.mjs` for isolated Edge-handler tests. These exercise the production handler with synthetic Auth, Storage, and OpenAI responses. They cover caller scope, worker credentials, malformed input, photo limits, modality coverage, stale claims, withdrawal before disclosure, provider failures, manual review, fresh owner responses, denied allowances, replayed claims and budget-store failures. They never contact OpenAI or use a person's content. `npm exec --yes --package=deno -- deno check backend/supabase/functions/moderate-profile/index.ts` checks the actual deployment entry point.

`backend/tests/hosted_social.mjs --live --project-ref PROJECT` creates three disposable accounts through admin-generated links, sends no emails, exercises normal authenticated APIs, and cleans up only the exact accounts created in that run. Keys come from process environment; `WORLDNICHE_TEST_PHOTO` points to a harmless JPEG. Never use a person's account. Actual Apple revocation requires a separate consenting Apple test identity.

`backend/tests/hosted_moderation.mjs --live --project-ref PROJECT --cooldown` exercises the deployed provider and scheduled recovery with four disposable identities. It requires explicitly supplied credentials and a harmless JPEG, never sends email, and verifies cleanup in its final step. Use `--dry-run` without live credentials to inspect its planned scenarios.
