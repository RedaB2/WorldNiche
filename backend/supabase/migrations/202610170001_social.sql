begin;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists wn_private;
revoke all on schema wn_private from public, anon;
grant usage on schema wn_private to authenticated;

create table public.wn_countries (id text primary key check (id ~ '^[A-Z]{2}$'));
insert into public.wn_countries(id) values ('AF'),('AL'),('DZ'),('AD'),('AO'),('AG'),('AR'),('AM'),('AU'),('AT'),('AZ'),('BS'),('BH'),('BD'),('BB'),('BY'),('BE'),('BZ'),('BJ'),('BT'),('BO'),('BA'),('BW'),('BR'),('BN'),('BG'),('BF'),('BI'),('KH'),('CM'),('CA'),('CV'),('CF'),('TD'),('CL'),('CN'),('CO'),('KM'),('CG'),('CR'),('HR'),('CU'),('CY'),('CZ'),('CD'),('DK'),('DJ'),('DM'),('DO'),('EC'),('EG'),('SV'),('GQ'),('ER'),('EE'),('SZ'),('ET'),('FJ'),('FI'),('FR'),('GA'),('GM'),('GE'),('DE'),('GH'),('GR'),('GD'),('GT'),('GN'),('GW'),('GY'),('HT'),('HN'),('HU'),('IS'),('IN'),('ID'),('IR'),('IQ'),('IE'),('IL'),('IT'),('CI'),('JM'),('JP'),('JO'),('KZ'),('KE'),('KI'),('KW'),('KG'),('LA'),('LV'),('LB'),('LS'),('LR'),('LY'),('LI'),('LT'),('LU'),('MG'),('MW'),('MY'),('MV'),('ML'),('MT'),('MH'),('MR'),('MU'),('MX'),('FM'),('MD'),('MC'),('MN'),('ME'),('MA'),('MZ'),('MM'),('NA'),('NR'),('NP'),('NL'),('NZ'),('NI'),('NE'),('NG'),('KP'),('MK'),('NO'),('OM'),('PK'),('PW'),('PS'),('PA'),('PG'),('PY'),('PE'),('PH'),('PL'),('PT'),('QA'),('RO'),('RU'),('RW'),('KN'),('LC'),('VC'),('WS'),('SM'),('SA'),('SN'),('RS'),('SC'),('SL'),('SG'),('SK'),('SI'),('SB'),('SO'),('ZA'),('KR'),('SS'),('ES'),('LK'),('SD'),('SR'),('SE'),('CH'),('SY'),('ST'),('TJ'),('TZ'),('TH'),('TL'),('TG'),('TO'),('TT'),('TN'),('TM'),('TV'),('TR'),('UG'),('UA'),('AE'),('GB'),('US'),('UY'),('UZ'),('VU'),('VA'),('VE'),('VN'),('YE'),('ZM'),('ZW');

create table public.wn_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check (length(btrim(display_name)) between 1 and 32 and display_name !~ '[[:cntrl:]]'),
 avatar text not null check (avatar in ('globe','leaf','sun','moon','mountain','wave')),
 share_exploration boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.wn_explorations (
 user_id uuid references public.wn_profiles(id) on delete cascade,
 country_id text references public.wn_countries(id),
 explored_at timestamptz not null default now(), primary key(user_id,country_id)
);
create table public.wn_friendships (
 user_low uuid references public.wn_profiles(id) on delete cascade,
 user_high uuid references public.wn_profiles(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(user_low,user_high), check(user_low < user_high)
);
create table public.wn_blocks (
 blocker uuid references public.wn_profiles(id) on delete cascade,
 blocked uuid references public.wn_profiles(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(blocker,blocked), check(blocker <> blocked)
);
create table wn_private.invites (
 token_hash bytea primary key,
 owner_id uuid not null references public.wn_profiles(id) on delete cascade,
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default (now()+interval '7 days'), revoked_at timestamptz
);
create index wn_invites_owner on wn_private.invites(owner_id);
create table wn_private.reports (
 id uuid primary key default gen_random_uuid(),
 reporter_id uuid not null references public.wn_profiles(id) on delete cascade,
 subject_id uuid not null references public.wn_profiles(id) on delete cascade,
 reason text not null check(reason in ('inappropriate_name','harassment','spam','other')),
 details text not null check(length(details)<=500), created_at timestamptz not null default now(),
 status text not null default 'open' check(status in ('open','reviewed','resolved')), check(reporter_id<>subject_id)
);
create table wn_private.rate_events (
 user_id uuid not null references auth.users(id) on delete cascade,
 action text not null, happened_at timestamptz not null default now()
);
create index wn_rate_events_user_action on wn_private.rate_events(user_id,action,happened_at);

-- Private helpers are not exposed as PostgREST RPCs. Every definer pins search_path.
create function wn_private.active_user() returns uuid language sql stable security definer set search_path='' as $$
 select u.id from auth.users u join auth.sessions s on s.user_id=u.id
 where u.id=auth.uid() and u.email_confirmed_at is not null
 and s.id::text=(auth.jwt()->>'session_id') limit 1
$$;
create function wn_private.require_user() returns uuid language plpgsql stable security definer set search_path='' as $$
declare u uuid := wn_private.active_user();
begin if u is null then raise exception 'Please sign in again.' using errcode='28000'; end if; return u; end $$;
create function wn_private.are_blocked(a uuid,b uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.wn_blocks where (blocker=a and blocked=b) or (blocker=b and blocked=a))
$$;
create function wn_private.are_friends(a uuid,b uuid) returns boolean language sql stable security definer set search_path='' as $$
 select a is not null and b is not null and not wn_private.are_blocked(a,b) and exists(
 select 1 from public.wn_friendships where user_low=least(a,b) and user_high=greatest(a,b))
$$;
create function wn_private.consume_rate(u uuid,a text,n integer,span interval) returns void language plpgsql security definer set search_path='' as $$
begin
 -- Shared by consent updates and sync: a racing upload cannot outlive an opt-out.
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 delete from wn_private.rate_events where user_id=u and happened_at < now()-interval '1 day';
 if (select count(*) from wn_private.rate_events where user_id=u and action=a and happened_at>now()-span)>=n then
  raise exception 'Please wait before trying again.' using errcode='P0001';
 end if;
 insert into wn_private.rate_events(user_id,action) values(u,a);
end $$;
create function wn_private.profile_json(p public.wn_profiles) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('id',p.id,'display_name',p.display_name,'avatar',p.avatar,'share_exploration',p.share_exploration,'created_at',p.created_at)
$$;

alter table public.wn_countries enable row level security;
alter table public.wn_profiles enable row level security;
alter table public.wn_explorations enable row level security;
alter table public.wn_friendships enable row level security;
alter table public.wn_blocks enable row level security;
alter table wn_private.invites enable row level security;
alter table wn_private.reports enable row level security;
alter table wn_private.rate_events enable row level security;
revoke all on public.wn_countries,public.wn_profiles,public.wn_explorations,public.wn_friendships,public.wn_blocks from public, anon, authenticated;
revoke all on all tables in schema wn_private from public,anon,authenticated;
grant select on public.wn_countries,public.wn_profiles,public.wn_explorations,public.wn_friendships,public.wn_blocks to authenticated;
create policy countries_read on public.wn_countries for select to authenticated using (wn_private.active_user() is not null);
create policy profiles_read on public.wn_profiles for select to authenticated using (
 id=wn_private.active_user() or wn_private.are_friends(wn_private.active_user(),id));
create policy explorations_read on public.wn_explorations for select to authenticated using (
 user_id=wn_private.active_user() or (wn_private.are_friends(wn_private.active_user(),user_id)
 and exists(select 1 from public.wn_profiles p where p.id=user_id and p.share_exploration)));
create policy friendships_read on public.wn_friendships for select to authenticated using (
 wn_private.active_user() in (user_low,user_high) and not wn_private.are_blocked(user_low,user_high));
create policy blocks_read on public.wn_blocks for select to authenticated using (blocker=wn_private.active_user());

create function wn_private.get_my_profile() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); result jsonb;
begin select wn_private.profile_json(p) into result from public.wn_profiles p where id=u; return result; end $$;
create function wn_private.update_my_profile(p_display_name text,p_avatar text,p_share_exploration boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); p public.wn_profiles;
begin
 perform wn_private.consume_rate(u,'profile',30,interval '1 hour');
 insert into public.wn_profiles(id,display_name,avatar,share_exploration) values(u,btrim(p_display_name),p_avatar,p_share_exploration)
 on conflict(id) do update set display_name=excluded.display_name,avatar=excluded.avatar,share_exploration=excluded.share_exploration,updated_at=now()
 returning * into p;
 if not p_share_exploration then delete from public.wn_explorations where user_id=u; end if;
 return wn_private.profile_json(p);
end $$;
create function wn_private.sync_explorations(p_country_ids text[]) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); ids jsonb;
begin
 perform wn_private.consume_rate(u,'sync',240,interval '1 hour');
 if not exists(select 1 from public.wn_profiles where id=u and share_exploration) then
 return '{"country_ids":[],"count":0}'; end if;
 if cardinality(p_country_ids)>195 or p_country_ids is null or exists(
  select 1 from unnest(p_country_ids) c where c is null or not exists(select 1 from public.wn_countries where id=c)) then
  raise exception 'Invalid country list.' using errcode='22023';
 end if;
 insert into public.wn_explorations(user_id,country_id) select u,c from unnest(p_country_ids) c on conflict do nothing;
 select coalesce(jsonb_agg(country_id order by country_id),'[]') into ids from public.wn_explorations where user_id=u;
 return jsonb_build_object('country_ids',ids,'count',jsonb_array_length(ids));
end $$;
create function wn_private.list_friends() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); result jsonb;
begin
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name,'avatar',p.avatar,
  'share_exploration',p.share_exploration,'country_ids',coalesce(e.ids,'[]'),'explored_count',coalesce(e.n,0),'connected_at',f.created_at)
  order by p.display_name,p.id),'[]') into result
 from public.wn_friendships f join public.wn_profiles p on p.id=case when f.user_low=u then f.user_high else f.user_low end
 left join lateral(select jsonb_agg(country_id order by country_id) ids,count(*) n from public.wn_explorations where user_id=p.id and p.share_exploration)e on true
 where u in(f.user_low,f.user_high) and not wn_private.are_blocked(u,p.id);
 return result;
end $$;
create function wn_private.create_invite() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); token text; expiry timestamptz:=now()+interval '7 days';
begin
 perform wn_private.consume_rate(u,'invite_create',10,interval '1 day');
 if not exists(select 1 from public.wn_profiles where id=u) then raise exception 'Create your profile first.'; end if;
 token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into wn_private.invites(token_hash,owner_id,expires_at) values(extensions.digest(token,'sha256'),u,expiry);
 return jsonb_build_object('token',token,'expires_at',expiry);
end $$;
create function wn_private.preview_invite(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); owner_id uuid; expiry timestamptz; p public.wn_profiles;
begin
 perform wn_private.consume_rate(u,'invite_preview',60,interval '1 hour');
 if p_token !~ '^[0-9a-f]{64}$' or p_token is null then return '{"status":"unavailable"}'; end if;
 select i.owner_id,i.expires_at into owner_id,expiry from wn_private.invites i where token_hash=extensions.digest(p_token,'sha256') and revoked_at is null and expires_at>now();
 if owner_id is null or wn_private.are_blocked(u,owner_id) then return '{"status":"unavailable"}'; end if;
 if owner_id=u then return '{"status":"self"}'; end if;
 select * into p from public.wn_profiles where id=owner_id;
 return jsonb_build_object('status','available','display_name',p.display_name,'avatar',p.avatar,'expires_at',expiry,'already_friends',wn_private.are_friends(u,owner_id));
end $$;
create function wn_private.accept_invite(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); owner_id uuid; already boolean;
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
 already:=wn_private.are_friends(u,owner_id);
 if not already and ((select count(*) from public.wn_friendships where u in(user_low,user_high))>=500 or
 (select count(*) from public.wn_friendships where owner_id in(user_low,user_high))>=500) then raise exception 'Friend limit reached.'; end if;
 insert into public.wn_friendships(user_low,user_high) values(least(u,owner_id),greatest(u,owner_id)) on conflict do nothing;
 return jsonb_build_object('status',case when already then 'already_friends' else 'accepted' end,'friend_id',owner_id);
end $$;
create function wn_private.revoke_invites() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user();
begin update wn_private.invites set revoked_at=now() where owner_id=u and revoked_at is null; return '{"ok":true}'; end $$;
create function wn_private.remove_friend(p_user_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user();
begin
 perform pg_advisory_xact_lock(hashtextextended(least(u,p_user_id)::text||greatest(u,p_user_id)::text,1));
 delete from public.wn_friendships where user_low=least(u,p_user_id) and user_high=greatest(u,p_user_id);
 return '{"ok":true}';
end $$;
create function wn_private.block_user(p_user_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user();
begin
 perform wn_private.consume_rate(u,'block',100,interval '1 day');
 if p_user_id=u then raise exception 'You cannot block yourself.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(least(u,p_user_id)::text||greatest(u,p_user_id)::text,1));
 if not exists(select 1 from public.wn_profiles where id=p_user_id) then return '{"ok":true}'; end if;
 insert into public.wn_blocks(blocker,blocked) values(u,p_user_id) on conflict do nothing;
 delete from public.wn_friendships where user_low=least(u,p_user_id) and user_high=greatest(u,p_user_id);
 return '{"ok":true}';
end $$;
create function wn_private.report_user(p_user_id uuid,p_reason text,p_details text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user();
begin
 perform wn_private.consume_rate(u,'report',10,interval '1 day');
 if not wn_private.are_friends(u,p_user_id) and not exists(select 1 from public.wn_blocks where blocker=u and blocked=p_user_id) then
 raise exception 'This profile is not available.' using errcode='42501'; end if;
 insert into wn_private.reports(reporter_id,subject_id,reason,details) values(u,p_user_id,p_reason,btrim(p_details));
 return '{"ok":true}';
end $$;
create function wn_private.export_my_data() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); result jsonb;
begin
 perform wn_private.consume_rate(u,'export',10,interval '1 day');
 select jsonb_build_object('exported_at',now(),'profile',wn_private.get_my_profile(),
 'email',(select email from auth.users where id=u),
 'explorations',(select coalesce(jsonb_agg(to_jsonb(e)-'user_id'),'[]') from public.wn_explorations e where user_id=u),
 'friends',wn_private.list_friends(),
 'blocks',(select coalesce(jsonb_agg(to_jsonb(b)-'blocker'),'[]') from public.wn_blocks b where blocker=u),
 'reports',(select coalesce(jsonb_agg(to_jsonb(r)-'reporter_id'),'[]') from wn_private.reports r where reporter_id=u),
 'invitations',(select coalesce(jsonb_agg(to_jsonb(i)-'token_hash'-'owner_id'),'[]') from wn_private.invites i where owner_id=u)) into result;
 return result;
end $$;
-- Invalidate all social requests immediately after global sign-out/account deletion:
-- require_user verifies both auth.users and the actual auth.sessions record, not just JWT claims.

create function wn_private.authorize_deletion() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user();
begin perform wn_private.consume_rate(u,'delete',5,interval '1 hour'); return '{"allowed":true}'; end $$;
create function public.authorize_deletion() returns jsonb language sql security invoker set search_path='' as $$ select wn_private.authorize_deletion() $$;
revoke all on function public.authorize_deletion() from public,anon;
grant execute on function public.authorize_deletion() to authenticated;
-- Exposed entry points use SECURITY INVOKER; implementation lives in a non-exposed schema.
create function public.get_my_profile() returns jsonb language sql security invoker set search_path='' as $$ select wn_private.get_my_profile() $$;
create function public.update_my_profile(p_display_name text,p_avatar text,p_share_exploration boolean) returns jsonb language sql security invoker set search_path='' as $$ select wn_private.update_my_profile(p_display_name,p_avatar,p_share_exploration) $$;
create function public.sync_explorations(p_country_ids text[]) returns jsonb language sql security invoker set search_path='' as $$ select wn_private.sync_explorations(p_country_ids) $$;
create function public.list_friends() returns jsonb language sql security invoker set search_path='' as $$ select wn_private.list_friends() $$;
create function public.create_invite() returns jsonb language sql security invoker set search_path='' as $$ select wn_private.create_invite() $$;
create function public.preview_invite(p_token text) returns jsonb language sql security invoker set search_path='' as $$ select wn_private.preview_invite(p_token) $$;
create function public.accept_invite(p_token text) returns jsonb language sql security invoker set search_path='' as $$ select wn_private.accept_invite(p_token) $$;
create function public.revoke_invites() returns jsonb language sql security invoker set search_path='' as $$ select wn_private.revoke_invites() $$;
create function public.remove_friend(p_user_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select wn_private.remove_friend(p_user_id) $$;
create function public.block_user(p_user_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select wn_private.block_user(p_user_id) $$;
create function public.report_user(p_user_id uuid,p_reason text,p_details text) returns jsonb language sql security invoker set search_path='' as $$ select wn_private.report_user(p_user_id,p_reason,p_details) $$;
create function public.export_my_data() returns jsonb language sql security invoker set search_path='' as $$ select wn_private.export_my_data() $$;
revoke all on all functions in schema wn_private from public,anon,authenticated;
revoke all on function public.get_my_profile() from public,anon;
grant execute on function public.get_my_profile() to authenticated;
grant execute on function wn_private.get_my_profile() to authenticated;
revoke all on function public.update_my_profile(text,text,boolean) from public,anon;
grant execute on function public.update_my_profile(text,text,boolean) to authenticated;
grant execute on function wn_private.update_my_profile(text,text,boolean) to authenticated;
revoke all on function public.sync_explorations(text[]) from public,anon;
grant execute on function public.sync_explorations(text[]) to authenticated;
grant execute on function wn_private.sync_explorations(text[]) to authenticated;
revoke all on function public.list_friends() from public,anon;
grant execute on function public.list_friends() to authenticated;
grant execute on function wn_private.list_friends() to authenticated;
revoke all on function public.create_invite() from public,anon;
grant execute on function public.create_invite() to authenticated;
grant execute on function wn_private.create_invite() to authenticated;
revoke all on function public.preview_invite(text) from public,anon;
grant execute on function public.preview_invite(text) to authenticated;
grant execute on function wn_private.preview_invite(text) to authenticated;
revoke all on function public.accept_invite(text) from public,anon;
grant execute on function public.accept_invite(text) to authenticated;
grant execute on function wn_private.accept_invite(text) to authenticated;
revoke all on function public.revoke_invites() from public,anon;
grant execute on function public.revoke_invites() to authenticated;
grant execute on function wn_private.revoke_invites() to authenticated;
revoke all on function public.remove_friend(uuid) from public,anon;
grant execute on function public.remove_friend(uuid) to authenticated;
grant execute on function wn_private.remove_friend(uuid) to authenticated;
revoke all on function public.block_user(uuid) from public,anon;
grant execute on function public.block_user(uuid) to authenticated;
grant execute on function wn_private.block_user(uuid) to authenticated;
revoke all on function public.report_user(uuid,text,text) from public,anon;
grant execute on function public.report_user(uuid,text,text) to authenticated;
grant execute on function wn_private.report_user(uuid,text,text) to authenticated;
revoke all on function public.export_my_data() from public,anon;
grant execute on function public.export_my_data() to authenticated;
grant execute on function wn_private.export_my_data() to authenticated;
grant execute on function wn_private.active_user(),wn_private.are_friends(uuid,uuid),wn_private.are_blocked(uuid,uuid) to authenticated;
grant execute on function wn_private.authorize_deletion() to authenticated;
commit;
