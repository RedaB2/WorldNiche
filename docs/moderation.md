# Moderation

The currently deployed release holds custom names and photos for human review before friends can see them. The next release adds the automatic checks below. Do not describe those checks as live until the provider, database migrations, worker, scheduling, and public disclosures have been deployed and verified together.

Symbols and the default Explorer name are available immediately. Existing approved content stays visible to friends while an edit is pending. Links, control characters, and invisible formatting in names are rejected before review. The next app release also shows submitted names and photos immediately in the owner's private profile.

## Automatic checks

The `moderate-profile` Edge function uses OpenAI's `omni-moderation-latest` endpoint. Each person must grant separate, revocable permission before submitted names or photos are sent to OpenAI. Exploration sharing does not grant that permission. Existing submissions stay private and are not sent unless that person enables automatic checks. Declining keeps the human review route available.

The app saves the submission first and displays it privately. The backend then checks the exact saved revision, publishing passing content for friends automatically. A flagged result goes to human review. Provider outages, timeouts, incomplete responses, and missing coverage produce a retry without publishing unchecked content. The previous approved profile stays visible to friends until the new content passes. An app-managed refresh updates visible friend screens without requiring another invitation.

The function accepts no client-supplied user IDs, content, or media URLs. Native requests are authenticated through `authorize_profile_check`, which verifies the live Auth session and rate-limits calls. Scheduled work requires a separate scoped worker secret. Only the server role can claim or finish jobs. Photos are fetched from the private bucket, limited to 300 KB, and sent as JPEG data rather than a public or signed storage URL. Names and photos are sent separately without account IDs, email addresses, friendship lists, or exploration history.

The database supplies revision-specific jobs, exclusive claims, retry backoff, and consent, restriction, and deletion checks. Migration `202610240006_profile_check_disclosure.sql` adds a service-only claim check immediately before external disclosure. A withdrawal after a request has started cannot recall that request, but its result cannot publish content after consent is withdrawn. No credentials, submitted content, or provider response bodies are logged by the worker.

### Classifier limits

The worker uses the provider's boolean flags, with no custom confidence-score threshold. It validates the complete response and expected modality coverage before approving anything. Confidence scores are not proof that a photo is safe. OpenAI documents that image-only inputs do not support hate, harassment, illicit activity, or the sexual/minors category. The image classifier covers sexual content, self-harm, and violence categories. It also does not establish identity, consent to a photograph, copyright ownership, or authenticity. Reports, blocking, manual enforcement, and appeals remain part of moderation. Do not advertise this as comprehensive image safety or a guarantee of App Store approval. See the [OpenAI moderation guide](https://developers.openai.com/api/docs/guides/moderation).

### Deployment gate

Apply migrations `202610240005_automatic_profile_checks.sql` and `202610240006_profile_check_disclosure.sql` before deploying `moderate-profile`. Set `OPENAI_API_KEY` and `WORLDNICHE_MODERATION_WORKER_SECRET` only as backend secrets. Supabase supplies its project URL, public API key, and server API key. Disable the Edge gateway JWT check for this function because scheduled calls use the scoped worker secret; the function itself verifies either the worker secret or the native caller through the session-checking RPC.

Enable pg_net, pg_cron, and Vault. Store `worldniche_moderation_url` and `worldniche_moderation_worker_secret` in Vault, with the same scoped worker secret used by the Edge function. `configure_profile_checks.sql` refuses to configure retries without those dependencies. It installs a minute-based retry schedule. Verify a successful cron invocation, a successful worker response, a passing opted-in synthetic name/photo, a held flagged submission, and friend visibility before release. Keep the human queue and support inbox monitored.

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

`backend/tests/run_database.sh` creates a disposable local cluster and checks quarantine, owner/friend isolation, immutable review, stale decisions, restrictions, report privacy, export, and deletion cascades. It also tests invitation, blocking, revocation, sharing races, and the worker's permission to disclose a specific claimed revision.

Run `node --test backend/tests/moderate_profile.mjs` for isolated Edge-handler tests. These exercise the production handler with synthetic Auth, Storage, and OpenAI responses. They cover caller scope, worker credentials, malformed input, photo limits, modality coverage, stale claims, withdrawal before disclosure, provider failures, manual review, and fresh owner responses. They never contact OpenAI or use a person's content. `npm exec --yes --package=deno -- deno check backend/supabase/functions/moderate-profile/index.ts` checks the actual deployment entry point.

`backend/tests/hosted_social.mjs --live --project-ref PROJECT` creates three disposable accounts through admin-generated links, sends no emails, exercises normal authenticated APIs, and cleans up only the exact accounts created in that run. Keys come from process environment; `WORLDNICHE_TEST_PHOTO` points to a harmless JPEG. Never use a person's account. Actual Apple revocation requires a separate consenting Apple test identity.
