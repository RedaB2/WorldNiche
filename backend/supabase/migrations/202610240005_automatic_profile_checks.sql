begin;

alter table wn_private.profile_moderation
 add column automatic_profile_checks_enabled boolean not null default false,
 add column automatic_checks_consent_version text,
 add column automatic_checks_consented_at timestamptz,
 add column automatic_checks_revoked_at timestamptz;

-- Jobs contain references, never another copy of a person's name or photo.
-- A new revision replaces the previous job; an old response cannot publish it.
create table wn_private.profile_check_jobs (
 user_id uuid not null references public.wn_profiles(id) on delete cascade,
 kind text not null check(kind in ('name','photo')),
 revision uuid not null,
 state text not null check(state in ('queued','checking','retry','review','complete')),
 review_reason text check(review_reason in ('consent','flagged')),
 claim_token uuid,
 lease_until timestamptz,
 attempts integer not null default 0 check(attempts>=0),
 available_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 primary key(user_id,kind)
);
alter table wn_private.profile_check_jobs enable row level security;
revoke all on wn_private.profile_check_jobs from public,anon,authenticated;
create index wn_profile_checks_due on wn_private.profile_check_jobs(available_at) where state in ('queued','retry','checking');

-- Optional hosted delivery uses pg_net and Vault. The endpoint and scoped worker
-- secret are configured by the operator, not stored in migration source. The
-- persistent queue remains authoritative when dispatch or the provider fails.
create function wn_private.dispatch_profile_checks() returns boolean
language plpgsql security definer set search_path='' as $$
declare endpoint text; worker_secret text;
begin
 if to_regclass('vault.decrypted_secrets') is null or to_regnamespace('net') is null then return false; end if;
 execute 'select decrypted_secret from vault.decrypted_secrets where name=$1 limit 1' into endpoint using 'worldniche_moderation_url';
 execute 'select decrypted_secret from vault.decrypted_secrets where name=$1 limit 1' into worker_secret using 'worldniche_moderation_worker_secret';
 if endpoint is null or endpoint !~ '^https://[a-z0-9]+\.supabase\.co/functions/v1/moderate-profile$'
 or length(coalesce(worker_secret,''))<32 then return false; end if;
 execute 'select net.http_post(url:=$1,body:=$2,headers:=$3,timeout_milliseconds:=60000)'
 using endpoint,'{}'::jsonb,jsonb_build_object('Content-Type','application/json','x-worldniche-worker-secret',worker_secret);
 return true;
exception when others then
 -- Saving a profile must succeed even when the background dispatcher is down.
 return false;
end $$;

create function wn_private.queue_profile_checks() returns trigger
language plpgsql security definer set search_path='' as $$
declare should_dispatch boolean:=false; k text; rev uuid; moderation_status text; old_revision uuid;
begin
 foreach k in array array['name','photo'] loop
  rev:=case when k='name' then new.name_revision else new.photo_revision end;
  moderation_status:=case when k='name' then new.name_status else new.photo_status end;
  old_revision:=case when tg_op='INSERT' then null when k='name' then old.name_revision else old.photo_revision end;
  if moderation_status='pending' and new.restricted_at is null then
   if tg_op='INSERT' or rev is distinct from old_revision then
    insert into wn_private.profile_check_jobs(user_id,kind,revision,state,review_reason)
    values(new.user_id,k,rev,case when new.automatic_profile_checks_enabled then 'queued' else 'review' end,case when not new.automatic_profile_checks_enabled then 'consent' end)
    on conflict(user_id,kind) do update set revision=excluded.revision,state=excluded.state,review_reason=excluded.review_reason,claim_token=null,lease_until=null,attempts=0,available_at=now(),updated_at=now();
    should_dispatch:=should_dispatch or new.automatic_profile_checks_enabled;
   elsif new.automatic_profile_checks_enabled and not old.automatic_profile_checks_enabled then
    update wn_private.profile_check_jobs set state='queued',review_reason=null,available_at=now(),updated_at=now()
    where user_id=new.user_id and kind=k and state='review' and review_reason='consent';
    should_dispatch:=true;
   elsif not new.automatic_profile_checks_enabled then
    update wn_private.profile_check_jobs set state='review',review_reason='consent',claim_token=null,lease_until=null,updated_at=now()
    where user_id=new.user_id and kind=k and state in ('queued','checking','retry');
   end if;
  else
   update wn_private.profile_check_jobs set state='complete',claim_token=null,lease_until=null,updated_at=now()
   where user_id=new.user_id and kind=k;
  end if;
 end loop;
 if should_dispatch then perform wn_private.dispatch_profile_checks(); end if;
 return new;
end $$;
create trigger wn_queue_profile_checks after insert or update on wn_private.profile_moderation
for each row execute function wn_private.queue_profile_checks();

insert into wn_private.profile_check_jobs(user_id,kind,revision,state,review_reason)
select user_id,'name',name_revision,'review','consent' from wn_private.profile_moderation where name_status='pending' and restricted_at is null
union all
select user_id,'photo',photo_revision,'review','consent' from wn_private.profile_moderation where photo_status='pending' and restricted_at is null;

create function wn_private.claim_profile_checks(p_user_id uuid default null,p_limit integer default 8) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb:='[]'; p public.wn_profiles; m wn_private.profile_moderation; j wn_private.profile_check_jobs;
 n integer:=greatest(1,least(coalesce(p_limit,8),8)); claim uuid;
begin
 -- Lock the profile before its submission and jobs, matching edits and decisions.
 -- Reading the content after these locks prevents a concurrent edit from pairing
 -- a new revision with the previous name or image in the worker's snapshot.
 for p in select pr.* from public.wn_profiles pr
  where (p_user_id is null or pr.id=p_user_id) and pr.deleting_at is null
  and exists(select 1 from wn_private.profile_moderation mr where mr.user_id=pr.id and mr.restricted_at is null
   and mr.automatic_profile_checks_enabled and mr.automatic_checks_consent_version='2026-10-24')
  and exists(select 1 from wn_private.profile_check_jobs jr where jr.user_id=pr.id
   and ((jr.state in ('queued','retry') and jr.available_at<=now()) or (jr.state='checking' and jr.lease_until<now())))
  order by (select min(jr.available_at) from wn_private.profile_check_jobs jr where jr.user_id=pr.id),pr.id
  limit n for update of pr skip locked
 loop
  select * into m from wn_private.profile_moderation where user_id=p.id for update;
  if m.restricted_at is not null or not m.automatic_profile_checks_enabled or m.automatic_checks_consent_version is distinct from '2026-10-24' then continue; end if;
  for j in select * from wn_private.profile_check_jobs where user_id=p.id
   and ((state in ('queued','retry') and available_at<=now()) or (state='checking' and lease_until<now()))
   order by available_at,kind for update skip locked
  loop
   if (j.kind='name' and (m.name_status<>'pending' or m.name_revision<>j.revision))
   or (j.kind='photo' and (m.photo_status<>'pending' or m.photo_revision<>j.revision)) then continue; end if;
   claim:=gen_random_uuid();
   update wn_private.profile_check_jobs set state='checking',claim_token=claim,lease_until=now()+interval '2 minutes',attempts=attempts+1,updated_at=now()
   where user_id=j.user_id and kind=j.kind;
   result:=result||jsonb_build_array(jsonb_build_object('user_id',j.user_id,'kind',j.kind,'revision',j.revision,'claim_token',claim,
    'text',case when j.kind='name' then m.submitted_name end,'photo_path',case when j.kind='photo' then m.submitted_photo_path end));
   if jsonb_array_length(result)>=n then return result; end if;
  end loop;
 end loop;
 return result;
end $$;

create function wn_private.finish_profile_check(p_user_id uuid,p_kind text,p_revision uuid,p_claim_token uuid,p_outcome text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.wn_profiles; m wn_private.profile_moderation; j wn_private.profile_check_jobs;
begin
 if p_kind is null or p_outcome is null or p_kind not in ('name','photo') or p_outcome not in ('approve','review','retry') or p_revision is null or p_claim_token is null then
  raise exception 'Invalid check result.' using errcode='22023';
 end if;
 -- This lock order matches submission, human review, restriction, and deletion.
 select * into p from public.wn_profiles where id=p_user_id for update;
 if not found or p.deleting_at is not null then return '{"applied":false}'; end if;
 select * into m from wn_private.profile_moderation where user_id=p_user_id for update;
 select * into j from wn_private.profile_check_jobs where user_id=p_user_id and kind=p_kind for update;
 if not found or m.restricted_at is not null or not m.automatic_profile_checks_enabled or m.automatic_checks_consent_version is distinct from '2026-10-24' or j.revision<>p_revision or j.claim_token is distinct from p_claim_token
 or j.state<>'checking' or j.lease_until<now()
 or (p_kind='name' and (m.name_revision<>p_revision or m.name_status<>'pending'))
 or (p_kind='photo' and (m.photo_revision<>p_revision or m.photo_status<>'pending')) then return '{"applied":false}'; end if;
 if p_outcome='approve' then
  perform wn_private.review_profile_content(p_user_id,p_kind,p_revision,'approve','Automatic content check passed.');
 elsif p_outcome='review' then
  insert into wn_private.moderation_actions(subject_id,content_kind,revision,action,note)
  values(p_user_id,p_kind,p_revision,'automatic_review','Automatic check requested human review.');
 end if;
 update wn_private.profile_check_jobs set state=case p_outcome when 'approve' then 'complete' when 'review' then 'review' else 'retry' end,
 review_reason=case when p_outcome='review' then 'flagged' end,claim_token=null,lease_until=null,available_at=now()+make_interval(secs=>least(300,5*power(2,least(j.attempts-1,6)))::integer),updated_at=now()
 where user_id=p_user_id and kind=p_kind and revision=p_revision;
 return '{"applied":true}';
end $$;

create function wn_private.authorize_profile_check() returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user();
begin
 perform wn_private.consume_rate(u,'profile_check',120,interval '1 hour');
 if exists(select 1 from public.wn_profiles where id=u and deleting_at is not null) then raise exception 'Profile unavailable.' using errcode='42501'; end if;
 return jsonb_build_object('user_id',u);
end $$;

create function wn_private.set_profile_check_consent(p_enabled boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user();
begin
 if p_enabled is null then raise exception 'Choose whether to enable automatic checks.' using errcode='22023'; end if;
 perform wn_private.consume_rate(u,'profile_check_consent',30,interval '1 hour');
 perform 1 from public.wn_profiles where id=u and deleting_at is null for update;
 if not found then raise exception 'Profile unavailable.' using errcode='42501'; end if;
 update wn_private.profile_moderation set automatic_profile_checks_enabled=p_enabled,
 automatic_checks_consent_version=case when p_enabled then '2026-10-24' else automatic_checks_consent_version end,
 automatic_checks_consented_at=case when p_enabled then now() else automatic_checks_consented_at end,
 automatic_checks_revoked_at=case when p_enabled then null else now() end,updated_at=now()
 where user_id=u;
 return wn_private.get_my_profile();
end $$;

create function wn_private.profile_check_note(p_status text,p_state text,p_kind text) returns text
language sql immutable set search_path='' as $$
 select case when p_status='rejected' then 'Please choose another '||p_kind||' that follows the community guidelines.'
 when p_status='pending' then case p_state
 when 'review' then 'Saved privately. This '||p_kind||' needs a closer review before friends can see it.'
 when 'retry' then 'Saved privately. The check could not finish. It will retry automatically, or you can try again.'
 else 'Saved. Checking your '||p_kind||' before sharing it with friends.' end end
$$;
create or replace function wn_private.get_my_profile() returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); result jsonb;
begin
 select wn_private.profile_json(p)||jsonb_build_object(
 'pending_display_name',case when m.name_status<>'approved' then m.submitted_name end,
 'pending_avatar_path',case when m.photo_status<>'approved' then m.submitted_photo_path end,
 'name_moderation_status',m.name_status,'photo_moderation_status',m.photo_status,
 'name_check_state',coalesce(n.state,'complete'),'photo_check_state',coalesce(f.state,'complete'),
 'profile_check_consent_recorded',m.automatic_checks_consented_at is not null or m.automatic_checks_revoked_at is not null,
 'automatic_profile_checks_enabled',m.automatic_profile_checks_enabled and m.automatic_checks_consent_version='2026-10-24',
 'automatic_checks_consent_version',m.automatic_checks_consent_version,'automatic_checks_consented_at',m.automatic_checks_consented_at,
 'automatic_checks_revoked_at',m.automatic_checks_revoked_at,
 'name_moderation_note',case when m.name_status='pending' and n.review_reason='consent' then 'Saved privately. Enable automatic checks to share it sooner, or wait for manual review.' else wn_private.profile_check_note(m.name_status,n.state,'name') end,
 'photo_moderation_note',case when m.photo_status='pending' and f.review_reason='consent' then 'Saved privately. Enable automatic checks to share it sooner, or wait for manual review.' else wn_private.profile_check_note(m.photo_status,f.state,'photo') end,
 'community_restricted',m.restricted_at is not null,
 'community_restriction_note',case when m.restricted_at is not null then 'Sharing and invitations are paused. Contact support if you think this is a mistake.' end)
 into result from public.wn_profiles p join wn_private.profile_moderation m on m.user_id=p.id
 left join wn_private.profile_check_jobs n on n.user_id=p.id and n.kind='name'
 left join wn_private.profile_check_jobs f on f.user_id=p.id and f.kind='photo'
 where p.id=u;
 return result;
end $$;

create function public.set_profile_check_consent(p_enabled boolean) returns jsonb language sql security invoker set search_path='' as $$ select wn_private.set_profile_check_consent(p_enabled) $$;
create function public.authorize_profile_check() returns jsonb language sql security invoker set search_path='' as $$ select wn_private.authorize_profile_check() $$;
create function public.claim_profile_checks(p_user_id uuid default null,p_limit integer default 8) returns jsonb language sql security invoker set search_path='' as $$ select wn_private.claim_profile_checks(p_user_id,p_limit) $$;
create function public.finish_profile_check(p_user_id uuid,p_kind text,p_revision uuid,p_claim_token uuid,p_outcome text) returns jsonb language sql security invoker set search_path='' as $$ select wn_private.finish_profile_check(p_user_id,p_kind,p_revision,p_claim_token,p_outcome) $$;

revoke all on function wn_private.set_profile_check_consent(boolean),public.set_profile_check_consent(boolean),wn_private.dispatch_profile_checks(),wn_private.queue_profile_checks(),wn_private.claim_profile_checks(uuid,integer),wn_private.finish_profile_check(uuid,text,uuid,uuid,text),wn_private.profile_check_note(text,text,text),wn_private.authorize_profile_check(),public.authorize_profile_check(),public.claim_profile_checks(uuid,integer),public.finish_profile_check(uuid,text,uuid,uuid,text) from public,anon,authenticated;
grant execute on function wn_private.set_profile_check_consent(boolean),public.set_profile_check_consent(boolean),wn_private.authorize_profile_check(),public.authorize_profile_check() to authenticated;
grant execute on function wn_private.dispatch_profile_checks(),wn_private.claim_profile_checks(uuid,integer),public.claim_profile_checks(uuid,integer),wn_private.finish_profile_check(uuid,text,uuid,uuid,text),public.finish_profile_check(uuid,text,uuid,uuid,text) to service_role;

commit;
