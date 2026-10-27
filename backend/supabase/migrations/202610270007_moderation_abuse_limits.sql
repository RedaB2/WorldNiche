begin;

-- Only trusted operators can change these shared provider budgets or pause checks.
create table wn_private.profile_check_limits (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default true,
 user_per_minute integer not null default 4 check(user_per_minute>0),
 user_per_hour integer not null default 12 check(user_per_hour>0),
 user_per_day integer not null default 30 check(user_per_day>0),
 global_per_minute integer not null default 30 check(global_per_minute>0),
 global_per_hour integer not null default 300 check(global_per_hour>0),
 global_per_day integer not null default 1000 check(global_per_day>0),
 max_revision_attempts integer not null default 5 check(max_revision_attempts between 1 and 20)
);
insert into wn_private.profile_check_limits(singleton) values(true);
alter table wn_private.profile_check_limits enable row level security;
revoke all on wn_private.profile_check_limits from public,anon,authenticated;
grant select,update on wn_private.profile_check_limits to service_role;

-- Charged before provider traffic, including failed requests and abandoned claims.
-- Deletion removes the account link but keeps the anonymous global budget charge.
create table wn_private.profile_check_reservations (
 id bigint generated always as identity primary key,
 user_id uuid references public.wn_profiles(id) on delete set null,
 happened_at timestamptz not null default clock_timestamp()
);
alter table wn_private.profile_check_reservations enable row level security;
revoke all on wn_private.profile_check_reservations from public,anon,authenticated;
create index wn_profile_check_account_budget on wn_private.profile_check_reservations(user_id,happened_at);
create index wn_profile_check_global_budget on wn_private.profile_check_reservations(happened_at);

alter table wn_private.profile_check_jobs
 add column provider_attempts integer not null default 0 check(provider_attempts>=0),
 add column provider_claim_token uuid;
alter table wn_private.profile_check_jobs drop constraint profile_check_jobs_review_reason_check;
alter table wn_private.profile_check_jobs add constraint profile_check_jobs_review_reason_check
 check(review_reason in ('consent','flagged','attempts'));

create function wn_private.reset_profile_provider_attempts() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' or new.revision is distinct from old.revision then
  new.provider_attempts:=0;
  new.provider_claim_token:=null;
 end if;
 return new;
end $$;
create trigger wn_reset_profile_provider_attempts before insert or update of revision on wn_private.profile_check_jobs
for each row execute function wn_private.reset_profile_provider_attempts();

create function wn_private.reserve_profile_check(p_user_id uuid,p_kind text,p_revision uuid,p_claim_token uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.wn_profiles; m wn_private.profile_moderation; j wn_private.profile_check_jobs;
 limits wn_private.profile_check_limits; instant timestamptz; due timestamptz; expires timestamptz;
 spans interval[]:=array[interval '1 minute',interval '1 hour',interval '1 day'];
 user_caps integer[]; global_caps integer[]; used bigint; i integer;
begin
 if p_user_id is null or p_kind is null or p_kind not in ('name','photo') or p_revision is null or p_claim_token is null then
  return '{"allowed":false,"reason":"stale"}';
 end if;
 -- Match edit, consent, deletion and completion lock order. Do not take the
 -- per-account rate lock here: profile edits already take it before this row.
 select * into p from public.wn_profiles where id=p_user_id for update;
 if not found or p.deleting_at is not null then return '{"allowed":false,"reason":"stale"}'; end if;
 select * into m from wn_private.profile_moderation where user_id=p_user_id for update;
 if not found then return '{"allowed":false,"reason":"stale"}'; end if;
 select * into j from wn_private.profile_check_jobs where user_id=p_user_id and kind=p_kind for update;
 if not found or m.restricted_at is not null or not m.automatic_profile_checks_enabled
 or m.automatic_checks_consent_version is distinct from '2026-10-24'
 or j.revision<>p_revision or j.claim_token is distinct from p_claim_token or j.state<>'checking'
 or j.lease_until is null or j.lease_until<=clock_timestamp()
 or (p_kind='name' and (m.name_revision<>p_revision or m.name_status<>'pending'))
 or (p_kind='photo' and (m.photo_revision<>p_revision or m.photo_status<>'pending')) then
  return '{"allowed":false,"reason":"stale"}';
 end if;
 if j.provider_claim_token=p_claim_token then return '{"allowed":false,"reason":"reserved"}'; end if;

 -- All accounts contend on one small row, so concurrent workers cannot pass a
 -- shared ceiling using separate snapshots. No provider call holds this lock.
 select * into limits from wn_private.profile_check_limits where singleton for update;
 instant:=clock_timestamp();
 if j.lease_until<=instant then return '{"allowed":false,"reason":"stale"}'; end if;
 if not found or not limits.enabled then
  update wn_private.profile_check_jobs set state='retry',claim_token=null,lease_until=null,
   available_at=instant+interval '1 minute',updated_at=instant where user_id=p_user_id and kind=p_kind;
  return '{"allowed":false,"reason":"disabled"}';
 end if;
 if j.provider_attempts>=limits.max_revision_attempts then
  update wn_private.profile_check_jobs set state='review',review_reason='attempts',claim_token=null,lease_until=null,
   updated_at=instant where user_id=p_user_id and kind=p_kind;
  return '{"allowed":false,"reason":"attempts"}';
 end if;
 user_caps:=array[limits.user_per_minute,limits.user_per_hour,limits.user_per_day];
 global_caps:=array[limits.global_per_minute,limits.global_per_hour,limits.global_per_day];
 due:=instant;
 for i in 1..3 loop
  select count(*) into used from wn_private.profile_check_reservations
   where user_id=p_user_id and happened_at>instant-spans[i];
  if used>=user_caps[i] then
   select happened_at+spans[i]+interval '1 millisecond' into expires from wn_private.profile_check_reservations
    where user_id=p_user_id and happened_at>instant-spans[i] order by happened_at,id offset (used-user_caps[i]) limit 1;
   due:=greatest(due,expires);
  end if;
  select count(*) into used from wn_private.profile_check_reservations where happened_at>instant-spans[i];
  if used>=global_caps[i] then
   select happened_at+spans[i]+interval '1 millisecond' into expires from wn_private.profile_check_reservations
    where happened_at>instant-spans[i] order by happened_at,id offset (used-global_caps[i]) limit 1;
   due:=greatest(due,expires);
  end if;
 end loop;
 if due>instant then
  update wn_private.profile_check_jobs set state='retry',claim_token=null,lease_until=null,available_at=due,
   updated_at=instant where user_id=p_user_id and kind=p_kind;
  return jsonb_build_object('allowed',false,'reason','budget','retry_at',due);
 end if;
 insert into wn_private.profile_check_reservations(user_id,happened_at) values(p_user_id,instant);
 update wn_private.profile_check_jobs set provider_attempts=provider_attempts+1,provider_claim_token=p_claim_token,
  updated_at=instant where user_id=p_user_id and kind=p_kind;
 return '{"allowed":true,"reason":"allowed"}';
end $$;

create or replace function wn_private.finish_profile_check(p_user_id uuid,p_kind text,p_revision uuid,p_claim_token uuid,p_outcome text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.wn_profiles; m wn_private.profile_moderation; j wn_private.profile_check_jobs; exhausted boolean;
begin
 if p_kind is null or p_outcome is null or p_kind not in ('name','photo') or p_outcome not in ('approve','review','retry') or p_revision is null or p_claim_token is null then
  raise exception 'Invalid check result.' using errcode='22023';
 end if;
 select * into p from public.wn_profiles where id=p_user_id for update;
 if not found or p.deleting_at is not null then return '{"applied":false}'; end if;
 select * into m from wn_private.profile_moderation where user_id=p_user_id for update;
 if not found then return '{"applied":false}'; end if;
 select * into j from wn_private.profile_check_jobs where user_id=p_user_id and kind=p_kind for update;
 if not found or m.restricted_at is not null or not m.automatic_profile_checks_enabled or m.automatic_checks_consent_version is distinct from '2026-10-24' or j.revision<>p_revision or j.claim_token is distinct from p_claim_token
 or j.state<>'checking' or j.lease_until is null or j.lease_until<=clock_timestamp()
 or (p_kind='name' and (m.name_revision<>p_revision or m.name_status<>'pending'))
 or (p_kind='photo' and (m.photo_revision<>p_revision or m.photo_status<>'pending')) then return '{"applied":false}'; end if;
 -- Invalid images and unavailable storage may finish without reaching OpenAI.
 -- Approval, however, always needs this exact claim's charged reservation.
 if p_outcome='approve' and j.provider_claim_token is distinct from p_claim_token then return '{"applied":false}'; end if;
 exhausted:=p_outcome='retry' and j.provider_attempts>=coalesce((select max_revision_attempts from wn_private.profile_check_limits where singleton),5);
 if p_outcome='approve' then
  perform wn_private.review_profile_content(p_user_id,p_kind,p_revision,'approve','Automatic content check passed.');
 elsif p_outcome='review' or exhausted then
  insert into wn_private.moderation_actions(subject_id,content_kind,revision,action,note)
  values(p_user_id,p_kind,p_revision,'automatic_review',case when exhausted then 'Automatic check attempt limit reached.' else 'Automatic check requested human review.' end);
 end if;
 update wn_private.profile_check_jobs set state=case when exhausted then 'review' when p_outcome='approve' then 'complete' when p_outcome='review' then 'review' else 'retry' end,
 review_reason=case when exhausted then 'attempts' when p_outcome='review' then 'flagged' end,claim_token=null,lease_until=null,
 available_at=clock_timestamp()+make_interval(secs=>least(300,5*power(2,least(j.attempts-1,6)))::integer),updated_at=clock_timestamp()
 where user_id=p_user_id and kind=p_kind and revision=p_revision;
 return '{"applied":true}';
end $$;

create or replace function wn_private.avatar_upload_allowed(p_path text) returns boolean
language plpgsql volatile security definer set search_path='' as $$
declare u uuid:=wn_private.active_user(); deleting timestamptz;
begin
 if u is null or p_path is null or p_path !~ ('^'||u::text||'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$') then return false; end if;
 -- Take the same rate lock as profile edits before taking the profile lock.
 -- A failed INSERT rolls these charges back. Deleting a photo never refunds it.
 begin
  perform wn_private.consume_rate(u,'avatar_upload_minute',6,interval '1 minute');
  perform wn_private.consume_rate(u,'avatar_upload_hour',20,interval '1 hour');
  perform wn_private.consume_rate(u,'avatar_upload_day',40,interval '1 day');
 exception when sqlstate 'P0001' then
  if sqlerrm='Please wait before trying again.' then
   raise exception 'Please wait before trying again.' using errcode='PT429';
  end if;
  raise;
 end;
 select deleting_at into deleting from public.wn_profiles where id=u for update;
 if not found or deleting is not null or wn_private.community_restricted(u) then return false; end if;
 return (select count(*) from storage.objects where bucket_id='profile-photos' and split_part(name,'/',1)=u::text)<20;
end $$;

create function public.reserve_profile_check(p_user_id uuid,p_kind text,p_revision uuid,p_claim_token uuid) returns jsonb
language sql security invoker set search_path='' as $$ select wn_private.reserve_profile_check(p_user_id,p_kind,p_revision,p_claim_token) $$;
create function wn_private.prune_profile_check_reservations() returns bigint
language plpgsql security definer set search_path='' as $$
declare removed bigint;
begin
 delete from wn_private.profile_check_reservations where happened_at<clock_timestamp()-interval '25 hours';
 get diagnostics removed=row_count;
 return removed;
end $$;
revoke all on function wn_private.reset_profile_provider_attempts(),wn_private.reserve_profile_check(uuid,text,uuid,uuid),public.reserve_profile_check(uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function wn_private.reserve_profile_check(uuid,text,uuid,uuid),public.reserve_profile_check(uuid,text,uuid,uuid) to service_role;
revoke all on function wn_private.prune_profile_check_reservations() from public,anon,authenticated;
grant execute on function wn_private.prune_profile_check_reservations() to service_role;

commit;
