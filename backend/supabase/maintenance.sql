-- Hosted Supabase only; enable Cron/pg_cron in Integrations first. Run as postgres.
-- Install after the migration. No credentials are embedded in scheduled jobs.
select cron.schedule('worldniche-retention', '17 3 * * *', $job$
 delete from wn_private.rate_events where happened_at < now()-interval '1 day';
 delete from wn_private.invites where expires_at < now() or revoked_at < now()-interval '1 day';
 delete from wn_private.reports where created_at < now()-interval '90 days';
$job$);
-- Verify through cron.job and cron.job_run_details. Alert on failed runs.
