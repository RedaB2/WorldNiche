-- Hosted Supabase only. Run as postgres after deploying moderate-profile.
-- Enable pg_net and pg_cron first. Configure these Vault entries separately:
-- worldniche_moderation_url: the project moderate-profile Edge Function URL.
-- worldniche_moderation_worker_secret: the same scoped secret used by the worker.
-- Never put either the service-role key or personal profile content in cron.
begin;
do $$
declare endpoint text; worker_secret text;
begin
 if not exists(select 1 from pg_extension where extname='pg_net')
 or not exists(select 1 from pg_extension where extname='pg_cron')
 or to_regclass('vault.decrypted_secrets') is null then
  raise exception 'Enable pg_net, pg_cron and Vault before configuring automatic checks.';
 end if;
 select decrypted_secret into endpoint from vault.decrypted_secrets where name='worldniche_moderation_url';
 select decrypted_secret into worker_secret from vault.decrypted_secrets where name='worldniche_moderation_worker_secret';
 if endpoint is null or endpoint !~ '^https://[a-z0-9]+\.supabase\.co/functions/v1/moderate-profile$'
 or length(coalesce(worker_secret,''))<32 then
  raise exception 'Configure the moderation URL and scoped worker secret in Vault first.';
 end if;
end $$;
-- The stable job name replaces its schedule on rerun, avoiding duplicate jobs.
select cron.schedule('worldniche-profile-checks','* * * * *',$job$
 do $retry$ begin
  if not wn_private.dispatch_profile_checks() then
   raise exception 'Profile check dispatch is not configured or could not enqueue work.';
  end if;
 end $retry$;
$job$);
commit;

-- A row with active=true confirms scheduling, not successful provider processing.
select jobid,jobname,schedule,active from cron.job where jobname='worldniche-profile-checks';
-- After at least one minute, confirm a completed invocation and a successful
-- HTTP response in net._http_response. Do not print request headers or Vault data.
select d.status,d.start_time,d.end_time from cron.job_run_details d
join cron.job j on j.jobid=d.jobid where j.jobname='worldniche-profile-checks'
order by d.start_time desc limit 3;
