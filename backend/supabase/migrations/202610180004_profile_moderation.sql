begin;

-- Only reviewed content lives in public profiles. Submitted content stays private,
-- including when a caller bypasses the app and calls PostgREST or Storage directly.
create table wn_private.profile_moderation (
 user_id uuid primary key references public.wn_profiles(id) on delete cascade,
 submitted_name text not null,
 name_status text not null check(name_status in ('pending','approved','rejected')),
 name_revision uuid not null default gen_random_uuid(),
 name_reason text check(name_reason in ('community_guidelines','invalid_text','removed')),
 name_submitted_at timestamptz not null default now(),
 submitted_photo_path text,
 photo_status text not null check(photo_status in ('pending','approved','rejected')),
 photo_revision uuid not null default gen_random_uuid(),
 photo_reason text check(photo_reason in ('community_guidelines','removed')),
 photo_submitted_at timestamptz not null default now(),
 restricted_at timestamptz,
 updated_at timestamptz not null default now()
);
create table wn_private.moderation_actions (
 id uuid primary key default gen_random_uuid(),
 subject_id uuid not null references public.wn_profiles(id) on delete cascade,
 report_id uuid references wn_private.reports(id) on delete set null,
 content_kind text not null check(content_kind in ('name','photo','report','restriction')),
 revision uuid,
 action text not null,
 note text not null default '' check(length(note)<=500),
 created_at timestamptz not null default now()
);
alter table wn_private.profile_moderation enable row level security;
alter table wn_private.moderation_actions enable row level security;
revoke all on wn_private.profile_moderation,wn_private.moderation_actions from public,anon,authenticated;
create index wn_pending_names on wn_private.profile_moderation(name_submitted_at) where name_status='pending';
create index wn_pending_photos on wn_private.profile_moderation(photo_submitted_at) where photo_status='pending';
create index wn_open_reports on wn_private.reports(created_at) where status='open';

-- Preserve existing submissions for the owner and queue them for review. Earlier
-- clients never reviewed these fields, so they cannot be grandfathered as safe.
insert into wn_private.profile_moderation(user_id,submitted_name,name_status,submitted_photo_path,photo_status)
select id,display_name,case when display_name='Explorer' then 'approved' else 'pending' end,
 avatar_path,case when avatar_path is null then 'approved' else 'pending' end from public.wn_profiles;
update public.wn_profiles set display_name='Explorer',avatar_path=null;

create function wn_private.community_restricted(u uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from wn_private.profile_moderation where user_id=u and restricted_at is not null)
$$;
create or replace function wn_private.are_friends(a uuid,b uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select a is not null and b is not null and not wn_private.are_blocked(a,b)
 and not wn_private.community_restricted(a) and not wn_private.community_restricted(b)
 and exists(select 1 from public.wn_friendships where user_low=least(a,b) and user_high=greatest(a,b))
$$;
create function wn_private.require_sharing_user() returns uuid
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=wn_private.require_user();
begin
 if wn_private.community_restricted(u) then raise exception 'Sharing and invitations are paused. Contact support.' using errcode='42501'; end if;
 return u;
end $$;
create function wn_private.name_prefilter_rejects(p_name text) returns boolean
language sql immutable set search_path='' as $$
 select p_name ~* '(https?://|www\.)' or p_name ~ '[[:cntrl:]]' or p_name ~ U&'[\200B-\200F\202A-\202E\2060-\206F]'
$$;
create or replace function wn_private.get_my_profile() returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); result jsonb;
begin
 select wn_private.profile_json(p)||jsonb_build_object(
 'pending_display_name',case when m.name_status<>'approved' then m.submitted_name end,
 'pending_avatar_path',case when m.photo_status<>'approved' then m.submitted_photo_path end,
 'name_moderation_status',m.name_status,'photo_moderation_status',m.photo_status,
 'name_moderation_note',case when m.name_status='pending' then 'Your name is waiting for review. Friends see your approved name until then.'
 when m.name_status='rejected' then 'Please choose a different name that follows the community guidelines.' end,
 'photo_moderation_note',case when m.photo_status='pending' then 'Your photo is waiting for review. Friends see your approved photo or symbol until then.'
 when m.photo_status='rejected' then 'Please choose a different photo that follows the community guidelines.' end,
 'community_restricted',m.restricted_at is not null,
 'community_restriction_note',case when m.restricted_at is not null then 'Sharing and invitations are paused. Contact support if you think this is a mistake.' end)
 into result from public.wn_profiles p join wn_private.profile_moderation m on m.user_id=p.id where p.id=u;
 return result;
end $$;
create or replace function wn_private.update_my_profile(p_display_name text,p_avatar text,p_share_exploration boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); p public.wn_profiles; m wn_private.profile_moderation; candidate text:=btrim(p_display_name); next_status text;
begin
 perform wn_private.consume_rate(u,'profile',30,interval '1 hour');
 if candidate is null or length(candidate) not between 1 and 32 then raise exception 'Choose a name with 1 to 32 characters.' using errcode='22023'; end if;
 insert into public.wn_profiles(id,display_name,avatar,share_exploration) values(u,'Explorer',p_avatar,false) on conflict(id) do nothing;
 select * into p from public.wn_profiles where id=u for update;
 if p.deleting_at is not null then raise exception 'Profile unavailable.' using errcode='22023'; end if;
 insert into wn_private.profile_moderation(user_id,submitted_name,name_status,photo_status) values(u,'Explorer','approved','approved') on conflict(user_id) do nothing;
 select * into m from wn_private.profile_moderation where user_id=u for update;
 if candidate is distinct from m.submitted_name then
  next_status:=case when candidate=p.display_name or candidate='Explorer' then 'approved' when wn_private.name_prefilter_rejects(candidate) then 'rejected' else 'pending' end;
  update wn_private.profile_moderation set submitted_name=candidate,name_status=next_status,name_revision=gen_random_uuid(),
   name_reason=case when next_status='rejected' then 'invalid_text' end,name_submitted_at=now(),updated_at=now() where user_id=u;
  if next_status='approved' then update public.wn_profiles set display_name=candidate where id=u; end if;
 end if;
 update public.wn_profiles set avatar=p_avatar,share_exploration=coalesce(p_share_exploration,false) and m.restricted_at is null,updated_at=now() where id=u;
 if not coalesce(p_share_exploration,false) or m.restricted_at is not null then delete from public.wn_explorations where user_id=u; end if;
 return wn_private.get_my_profile();
end $$;
create or replace function wn_private.set_profile_avatar(p_path text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); p public.wn_profiles; m wn_private.profile_moderation;
begin
 perform wn_private.consume_rate(u,'avatar',30,interval '1 hour');
 select * into p from public.wn_profiles where id=u for update;
 if not found or p.deleting_at is not null then raise exception 'Profile unavailable.' using errcode='22023'; end if;
 select * into m from wn_private.profile_moderation where user_id=u for update;
 if p_path is not null and (p_path !~ ('^'||u::text||'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$') or not exists(
  select 1 from storage.objects where bucket_id='profile-photos' and name=p_path
  and metadata->>'mimetype'='image/jpeg' and (metadata->>'size')::bigint between 4 and 300000)) then
  raise exception 'Invalid photo.' using errcode='22023';
 end if;
 if p_path is distinct from m.submitted_photo_path or (p_path is null and p.avatar_path is not null) then
  update wn_private.profile_moderation set submitted_photo_path=p_path,photo_status=case when p_path is null or p_path=p.avatar_path then 'approved' else 'pending' end,
   photo_revision=gen_random_uuid(),photo_reason=null,photo_submitted_at=now(),updated_at=now() where user_id=u;
 end if;
 if p_path is null then update public.wn_profiles set avatar_path=null,updated_at=now() where id=u; end if;
 return wn_private.get_my_profile();
end $$;

-- App users have no EXECUTE grant on any administrative function, including the
-- private implementation. Revision checks prevent approving content changed
-- after it was inspected. Locks use the same profile-then-submission order.
create function wn_private.review_profile_content(p_user_id uuid,p_kind text,p_revision uuid,p_decision text,p_note text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.wn_profiles; m wn_private.profile_moderation;
begin
 if p_kind is null or p_decision is null or p_kind not in ('name','photo') or p_decision not in ('approve','reject') or length(p_note)>500 or p_revision is null then raise exception 'Invalid moderation decision.' using errcode='22023'; end if;
 select * into p from public.wn_profiles where id=p_user_id for update;
 if not found or p.deleting_at is not null then raise exception 'Profile unavailable.' using errcode='22023'; end if;
 select * into m from wn_private.profile_moderation where user_id=p_user_id for update;
 if (p_kind='name' and (m.name_revision<>p_revision or m.name_status<>'pending')) or (p_kind='photo' and (m.photo_revision<>p_revision or m.photo_status<>'pending')) then
  raise exception 'Submission changed. Refresh the queue and review the current content.' using errcode='40001';
 end if;
 if p_kind='name' then
  if p_decision='approve' then update public.wn_profiles set display_name=m.submitted_name,updated_at=now() where id=p_user_id; end if;
  update wn_private.profile_moderation set name_status=case when p_decision='approve' then 'approved' else 'rejected' end,
   name_reason=case when p_decision='reject' then 'community_guidelines' end,updated_at=now() where user_id=p_user_id;
 else
  if p_decision='approve' then
   if not exists(select 1 from storage.objects where bucket_id='profile-photos' and name=m.submitted_photo_path and metadata->>'mimetype'='image/jpeg' and (metadata->>'size')::bigint between 4 and 300000) then raise exception 'Photo no longer exists.' using errcode='22023'; end if;
   update public.wn_profiles set avatar_path=m.submitted_photo_path,updated_at=now() where id=p_user_id;
  end if;
  update wn_private.profile_moderation set photo_status=case when p_decision='approve' then 'approved' else 'rejected' end,
   photo_reason=case when p_decision='reject' then 'community_guidelines' end,updated_at=now() where user_id=p_user_id;
 end if;
 insert into wn_private.moderation_actions(subject_id,content_kind,revision,action,note) values(p_user_id,p_kind,p_revision,p_decision,coalesce(p_note,''));
 return jsonb_build_object('ok',true,'user_id',p_user_id,'kind',p_kind,'decision',p_decision);
end $$;

alter table wn_private.reports add column resolved_at timestamptz;
alter table wn_private.reports add column reported_display_name text;
alter table wn_private.reports add column reported_avatar_path text;
alter table wn_private.reports drop constraint reports_reason_check;
alter table wn_private.reports add constraint reports_reason_check check(reason in ('inappropriate_name','inappropriate_photo','harassment','spam','other'));
create or replace function wn_private.report_user(p_user_id uuid,p_reason text,p_details text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user();
begin
 perform wn_private.consume_rate(u,'report',10,interval '1 day');
 if not exists(select 1 from public.wn_friendships where user_low=least(u,p_user_id) and user_high=greatest(u,p_user_id))
 and not exists(select 1 from public.wn_blocks where blocker=u and blocked=p_user_id) then raise exception 'This profile is not available.' using errcode='42501'; end if;
 if length(coalesce(p_details,''))>500 then raise exception 'Report details are too long.' using errcode='22023'; end if;
 insert into wn_private.reports(reporter_id,subject_id,reason,details,reported_display_name,reported_avatar_path)
 select u,p_user_id,p_reason,btrim(coalesce(p_details,'')),display_name,avatar_path from public.wn_profiles where id=p_user_id;
 return '{"ok":true}';
end $$;
create function wn_private.moderation_queue(p_limit integer default 100) returns jsonb
language plpgsql security definer set search_path='' as $$
declare n integer:=greatest(1,least(coalesce(p_limit,100),200)); result jsonb;
begin
 select jsonb_build_object('profiles',coalesce((select jsonb_agg(to_jsonb(q)) from (
 select m.*,p.display_name as approved_name,p.avatar_path as approved_photo_path,p.avatar from wn_private.profile_moderation m
 join public.wn_profiles p on p.id=m.user_id where (name_status='pending' or photo_status='pending') and p.deleting_at is null
 order by least(case when name_status='pending' then name_submitted_at end,case when photo_status='pending' then photo_submitted_at end),user_id limit n) q),'[]'),
 'reports',coalesce((select jsonb_agg(to_jsonb(q)) from (select r.* from wn_private.reports r where status='open' order by created_at,id limit n) q),'[]'),
 'pending_profile_count',(select count(*) from wn_private.profile_moderation where name_status='pending' or photo_status='pending'),
 'open_report_count',(select count(*) from wn_private.reports where status='open')) into result;
 return result;
end $$;
create function wn_private.moderate_user(p_user_id uuid,p_action text,p_note text default '',p_report_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.wn_profiles;
begin
 if p_action is null or p_action not in ('dismiss_report','remove_name','remove_photo','remove_content','restrict','restore') or length(p_note)>500 then raise exception 'Invalid moderation action.' using errcode='22023'; end if;
 if p_action='restrict' then perform 1 from wn_private.invites where owner_id=p_user_id order by token_hash for update; end if;
 select * into p from public.wn_profiles where id=p_user_id for update;
 if not found or p.deleting_at is not null then raise exception 'Profile unavailable.' using errcode='22023'; end if;
 if p_report_id is not null then
  perform 1 from wn_private.reports where id=p_report_id and subject_id=p_user_id and status='open' for update;
  if not found then raise exception 'Report unavailable.' using errcode='22023'; end if;
 elsif p_action='dismiss_report' then raise exception 'Select a report.' using errcode='22023'; end if;
 perform 1 from wn_private.profile_moderation where user_id=p_user_id for update;
 if p_action in ('remove_name','remove_content','restrict') then
  update public.wn_profiles set display_name='Explorer',updated_at=now() where id=p_user_id;
  update wn_private.profile_moderation set name_status='rejected',name_reason='removed',name_revision=gen_random_uuid(),updated_at=now() where user_id=p_user_id;
 end if;
 if p_action in ('remove_photo','remove_content','restrict') then
  update public.wn_profiles set avatar_path=null,updated_at=now() where id=p_user_id;
  update wn_private.profile_moderation set photo_status=case when submitted_photo_path is null then 'approved' else 'rejected' end,
   photo_reason=case when submitted_photo_path is not null then 'removed' end,photo_revision=gen_random_uuid(),updated_at=now() where user_id=p_user_id;
 end if;
 if p_action='restrict' then
  update wn_private.profile_moderation set restricted_at=coalesce(restricted_at,now()),updated_at=now() where user_id=p_user_id;
  update public.wn_profiles set share_exploration=false,updated_at=now() where id=p_user_id;
  delete from public.wn_explorations where user_id=p_user_id;
  update wn_private.invites set revoked_at=coalesce(revoked_at,now()) where owner_id=p_user_id;
 elsif p_action='restore' then update wn_private.profile_moderation set restricted_at=null,updated_at=now() where user_id=p_user_id;
 end if;
 if p_report_id is not null then update wn_private.reports set status='resolved',resolved_at=now() where id=p_report_id; end if;
 insert into wn_private.moderation_actions(subject_id,report_id,content_kind,action,note) values(p_user_id,p_report_id,
 case when p_report_id is not null then 'report' else 'restriction' end,p_action,coalesce(p_note,''));
 return jsonb_build_object('ok',true,'user_id',p_user_id,'action',p_action);
end $$;

-- Friends and arbitrary SELECT callers never receive pending or rejected values.
create or replace function wn_private.list_friends() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); result jsonb;
begin
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name,'avatar',p.avatar,'avatar_path',p.avatar_path,
  'share_exploration',p.share_exploration,'country_ids',coalesce(e.ids,'[]'),'explored_count',coalesce(e.n,0),'connected_at',f.created_at)
  order by p.display_name,p.id),'[]') into result
 from public.wn_friendships f join public.wn_profiles p on p.id=case when f.user_low=u then f.user_high else f.user_low end
 left join lateral(select jsonb_agg(country_id order by country_id) ids,count(*) n from public.wn_explorations where user_id=p.id and p.share_exploration)e on true
 where u in(f.user_low,f.user_high) and wn_private.are_friends(u,p.id);
 return result;
end $$;
drop policy friendships_read on public.wn_friendships;
create policy friendships_read on public.wn_friendships for select to authenticated using (
 wn_private.active_user() in (user_low,user_high) and wn_private.are_friends(user_low,user_high));

create function public.moderation_queue(p_limit integer default 100) returns jsonb language sql security invoker set search_path='' as $$ select wn_private.moderation_queue(p_limit) $$;
create function public.review_profile_content(p_user_id uuid,p_kind text,p_revision uuid,p_decision text,p_note text default '') returns jsonb language sql security invoker set search_path='' as $$ select wn_private.review_profile_content(p_user_id,p_kind,p_revision,p_decision,p_note) $$;
create function public.moderate_user(p_user_id uuid,p_action text,p_note text default '',p_report_id uuid default null) returns jsonb language sql security invoker set search_path='' as $$ select wn_private.moderate_user(p_user_id,p_action,p_note,p_report_id) $$;
revoke all on function wn_private.community_restricted(uuid),wn_private.require_sharing_user(),wn_private.name_prefilter_rejects(text),
 wn_private.moderation_queue(integer),wn_private.review_profile_content(uuid,text,uuid,text,text),wn_private.moderate_user(uuid,text,text,uuid),
 public.moderation_queue(integer),public.review_profile_content(uuid,text,uuid,text,text),public.moderate_user(uuid,text,text,uuid) from public,anon,authenticated;
grant usage on schema wn_private to service_role;
grant execute on function wn_private.moderation_queue(integer),wn_private.review_profile_content(uuid,text,uuid,text,text),wn_private.moderate_user(uuid,text,text,uuid),
 public.moderation_queue(integer),public.review_profile_content(uuid,text,uuid,text,text),public.moderate_user(uuid,text,text,uuid) to service_role;

create or replace function wn_private.create_invite() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_sharing_user(); token text; expiry timestamptz:=now()+interval '7 days';
begin
 perform wn_private.consume_rate(u,'invite_create',10,interval '1 day');
 if not exists(select 1 from public.wn_profiles where id=u) then raise exception 'Create your profile first.'; end if;
 perform 1 from public.wn_profiles where id=u for update;
 if wn_private.community_restricted(u) then raise exception 'Sharing and invitations are paused.' using errcode='42501'; end if;
 token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into wn_private.invites(token_hash,owner_id,expires_at) values(extensions.digest(token,'sha256'),u,expiry);
 return jsonb_build_object('token',token,'expires_at',expiry);
end $$;
create or replace function wn_private.preview_invite(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_sharing_user(); owner_id uuid; expiry timestamptz; p public.wn_profiles;
begin
 perform wn_private.consume_rate(u,'invite_preview',60,interval '1 hour');
 if p_token !~ '^[0-9a-f]{64}$' or p_token is null then return '{"status":"unavailable"}'; end if;
 select i.owner_id,i.expires_at into owner_id,expiry from wn_private.invites i where token_hash=extensions.digest(p_token,'sha256') and revoked_at is null and expires_at>now();
 if owner_id is null or wn_private.are_blocked(u,owner_id) or wn_private.community_restricted(owner_id) then return '{"status":"unavailable"}'; end if;
 if owner_id=u then return '{"status":"self"}'; end if;
 select * into p from public.wn_profiles where id=owner_id;
 return jsonb_build_object('status','available','display_name',p.display_name,'avatar',p.avatar,'expires_at',expiry,'already_friends',wn_private.are_friends(u,owner_id));
end $$;
create or replace function wn_private.accept_invite(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_sharing_user(); owner_id uuid; already boolean;
begin
 perform wn_private.consume_rate(u,'invite_accept',30,interval '1 hour');
 if p_token !~ '^[0-9a-f]{64}$' or p_token is null then return '{"status":"unavailable"}'; end if;
 select i.owner_id into owner_id from wn_private.invites i where token_hash=extensions.digest(p_token,'sha256') and revoked_at is null and expires_at>now() for update;
 if owner_id is null then return '{"status":"unavailable"}'; end if;
 if owner_id=u then return '{"status":"self"}'; end if;
 perform pg_advisory_xact_lock(hashtextextended(least(u,owner_id)::text||greatest(u,owner_id)::text,1));
 if wn_private.are_blocked(u,owner_id) then return '{"status":"unavailable"}'; end if;
 if not exists(select 1 from public.wn_profiles where id=u) then raise exception 'Create your profile first.'; end if;
 perform 1 from public.wn_profiles where id in(u,owner_id) order by id for update;
 if wn_private.community_restricted(u) or wn_private.community_restricted(owner_id) then return '{"status":"unavailable"}'; end if;
 already:=wn_private.are_friends(u,owner_id);
 if not already and ((select count(*) from public.wn_friendships where u in(user_low,user_high))>=500 or
 (select count(*) from public.wn_friendships where owner_id in(user_low,user_high))>=500) then raise exception 'Friend limit reached.'; end if;
 insert into public.wn_friendships(user_low,user_high) values(least(u,owner_id),greatest(u,owner_id)) on conflict do nothing;
 return jsonb_build_object('status',case when already then 'already_friends' else 'accepted' end,'friend_id',owner_id);
end $$;

-- A selected or queued image cannot be deleted and recreated under the same path.
-- This keeps a review decision bound to immutable bytes, not just a filename.
create function wn_private.avatar_delete_allowed(p_path text) returns boolean
language plpgsql volatile security definer set search_path='' as $$
declare u uuid:=wn_private.active_user(); p public.wn_profiles;
begin
 if u is null or split_part(p_path,'/',1)<>u::text then return false; end if;
 select * into p from public.wn_profiles where id=u for update;
 if not found or p.deleting_at is not null then return false; end if;
 return p.avatar_path is distinct from p_path and not exists(
 select 1 from wn_private.profile_moderation where user_id=u and submitted_photo_path=p_path);
end $$;
drop policy wn_avatar_delete on storage.objects;
create policy wn_avatar_delete on storage.objects for delete to authenticated
using(bucket_id='profile-photos' and wn_private.avatar_delete_allowed(name));
revoke all on function wn_private.avatar_delete_allowed(text) from public,anon;
grant execute on function wn_private.avatar_delete_allowed(text) to authenticated;

commit;
