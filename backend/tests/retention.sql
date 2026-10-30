-- Isolated local database only. Capture and exercise the real scheduled SQL.
begin;
reset role;
create schema cron;
create table cron.job(jobid bigserial primary key, jobname text unique, schedule text, command text);
create function cron.schedule(text,text,text) returns bigint language sql as $$
 insert into cron.job(jobname,schedule,command) values($1,$2,$3)
 on conflict(jobname) do update set schedule=excluded.schedule,command=excluded.command
 returning jobid
$$;
\ir ../supabase/maintenance.sql
\ir ../supabase/maintenance.sql

insert into auth.users(id,email,email_confirmed_at) values
 ('90000000-0000-0000-0000-000000000001','retention-a@example.invalid',now()),
 ('90000000-0000-0000-0000-000000000002','retention-b@example.invalid',now());
insert into public.wn_profiles(id,display_name,avatar) values
 ('90000000-0000-0000-0000-000000000001','Retention A','globe'),
 ('90000000-0000-0000-0000-000000000002','Retention B','globe');
insert into wn_private.rate_events(user_id,action,happened_at) values
 ('90000000-0000-0000-0000-000000000001','retention_old',now()-interval '25 hours'),
 ('90000000-0000-0000-0000-000000000001','retention_boundary',now()-interval '24 hours'),
 ('90000000-0000-0000-0000-000000000001','retention_recent',now());
insert into wn_private.invites(token_hash,owner_id,expires_at,revoked_at)
 select extensions.digest(label,'sha256'),'90000000-0000-0000-0000-000000000001'::uuid,expires,revoked from (values
 ('retention_expired',now()-interval '1 second',null::timestamptz),
 ('retention_boundary',now(),null),
 ('retention_active',now()+interval '7 days',null),
 ('retention_revoked_old',now()+interval '7 days',now()-interval '25 hours'),
 ('retention_revoked_recent',now()+interval '7 days',now()-interval '1 hour')
 ) v(label,expires,revoked);
insert into wn_private.reports(reporter_id,subject_id,reason,details,status,resolved_at)
 select '90000000-0000-0000-0000-000000000001'::uuid,'90000000-0000-0000-0000-000000000002'::uuid,'other',label,status,resolved from (values
 ('retention_old','resolved',now()-interval '91 days'),
 ('retention_boundary','resolved',now()-interval '90 days'),
 ('retention_recent','resolved',now()-interval '1 day'),
 ('retention_open','open',null::timestamptz),
 ('retention_reviewed','reviewed',null),
 ('retention_undated','resolved',null)
 ) v(label,status,resolved);
insert into public.wn_journal(user_id,country_id,note,saved) values
 ('90000000-0000-0000-0000-000000000001','MA','Private note must remain',true);

do $$ declare cleanup text; begin
 assert (select count(*) from cron.job where jobname='worldniche-retention')=1,'Reinstall must not duplicate the daily job';
 select command into cleanup from cron.job where jobname='worldniche-retention';
 assert (select schedule from cron.job where jobname='worldniche-retention')='17 3 * * *';
 execute cleanup;
 assert not exists(select 1 from wn_private.rate_events where action='retention_old');
 assert (select count(*) from wn_private.rate_events where action like 'retention_%')=2,'Keep recent rate history and exact boundary';
 assert (select count(*) from wn_private.invites where owner_id='90000000-0000-0000-0000-000000000001')=3,'Keep active, boundary and recently revoked invites';
 assert not exists(select 1 from wn_private.invites where token_hash in(extensions.digest('retention_expired','sha256'),extensions.digest('retention_revoked_old','sha256')));
 assert not exists(select 1 from wn_private.reports where details='retention_old');
 assert (select count(*) from wn_private.reports where details like 'retention_%')=5,'Keep open, reviewed, undated and recent reports';
 assert (select note from public.wn_journal where user_id='90000000-0000-0000-0000-000000000001')='Private note must remain';
 assert (select count(*) from auth.users where id in ('90000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000002'))=2,'Never delete accounts';
 execute cleanup;
 assert (select count(*) from wn_private.reports where details like 'retention_%')=5,'Repeated cleanup must preserve retained rows';
end $$;
rollback;
\echo 'PASS: actual scheduled cleanup, retention boundaries, active invites, open reports, private journal preservation, repeatability and single-job installation.'
