begin;

alter table public.wn_profiles add column avatar_path text;
alter table public.wn_profiles add column deleting_at timestamptz;
alter table public.wn_profiles add constraint wn_profile_avatar_path check (
 avatar_path is null or avatar_path ~ ('^'||id::text||'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('profile-photos','profile-photos',false,300000,array['image/jpeg'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- The same profile-row lock serializes uploads with account deletion. Once deletion
-- starts, no new object may appear between the Storage cleanup and Auth deletion.
create function wn_private.avatar_upload_allowed(p_path text) returns boolean
language plpgsql volatile security definer set search_path='' as $$
declare u uuid:=wn_private.active_user(); deleting timestamptz;
begin
 if u is null or p_path is null or p_path !~ ('^'||u::text||'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$') then return false; end if;
 select deleting_at into deleting from public.wn_profiles where id=u for update;
 if not found or deleting is not null then return false; end if;
 return (select count(*) from storage.objects where bucket_id='profile-photos' and split_part(name,'/',1)=u::text)<20;
end $$;

create function wn_private.avatar_read_allowed(p_path text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.wn_profiles p where
 (p.id=wn_private.active_user() and split_part(p_path,'/',1)=p.id::text)
 or (p.avatar_path=p_path and wn_private.are_friends(wn_private.active_user(),p.id)))
$$;
revoke all on function wn_private.avatar_upload_allowed(text),wn_private.avatar_read_allowed(text) from public,anon;
grant execute on function wn_private.avatar_upload_allowed(text),wn_private.avatar_read_allowed(text) to authenticated;

create policy wn_avatar_insert on storage.objects for insert to authenticated
with check(bucket_id='profile-photos' and wn_private.avatar_upload_allowed(name));
-- No UPDATE permission: every upload has a fresh, immutable name.
create policy wn_avatar_read on storage.objects for select to authenticated
using(bucket_id='profile-photos' and wn_private.avatar_read_allowed(name));
create policy wn_avatar_delete on storage.objects for delete to authenticated
using(bucket_id='profile-photos' and split_part(name,'/',1)=wn_private.active_user()::text);

create or replace function wn_private.profile_json(p public.wn_profiles) returns jsonb
language sql immutable set search_path='' as $$
 select jsonb_build_object('id',p.id,'display_name',p.display_name,'avatar',p.avatar,
 'avatar_path',p.avatar_path,'share_exploration',p.share_exploration,'created_at',p.created_at)
$$;
create function wn_private.set_profile_avatar(p_path text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); p public.wn_profiles;
begin
 perform wn_private.consume_rate(u,'avatar',30,interval '1 hour');
 select * into p from public.wn_profiles where id=u for update;
 if not found or p.deleting_at is not null then raise exception 'Profile unavailable.' using errcode='22023'; end if;
 if p_path is not null and (p_path !~ ('^'||u::text||'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$') or not exists(
  select 1 from storage.objects where bucket_id='profile-photos' and name=p_path
  and metadata->>'mimetype'='image/jpeg' and (metadata->>'size')::bigint between 4 and 300000)) then
  raise exception 'Invalid photo.' using errcode='22023';
 end if;
 update public.wn_profiles set avatar_path=p_path,updated_at=now() where id=u returning * into p;
 return wn_private.profile_json(p);
end $$;
create function public.set_profile_avatar(p_path text) returns jsonb
language sql security invoker set search_path='' as $$ select wn_private.set_profile_avatar(p_path) $$;
revoke all on function wn_private.set_profile_avatar(text),public.set_profile_avatar(text) from public,anon;
grant execute on function wn_private.set_profile_avatar(text),public.set_profile_avatar(text) to authenticated;

create or replace function wn_private.list_friends() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); result jsonb;
begin
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name,'avatar',p.avatar,'avatar_path',p.avatar_path,
  'share_exploration',p.share_exploration,'country_ids',coalesce(e.ids,'[]'),'explored_count',coalesce(e.n,0),'connected_at',f.created_at)
  order by p.display_name,p.id),'[]') into result
 from public.wn_friendships f join public.wn_profiles p on p.id=case when f.user_low=u then f.user_high else f.user_low end
 left join lateral(select jsonb_agg(country_id order by country_id) ids,count(*) n from public.wn_explorations where user_id=p.id and p.share_exploration)e on true
 where u in(f.user_low,f.user_high) and not wn_private.are_blocked(u,p.id);
 return result;
end $$;

create or replace function wn_private.authorize_deletion() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user();
begin
 perform wn_private.consume_rate(u,'delete',5,interval '1 hour');
 update public.wn_profiles set deleting_at=coalesce(deleting_at,now()) where id=u;
 return '{"allowed":true}';
end $$;

commit;
