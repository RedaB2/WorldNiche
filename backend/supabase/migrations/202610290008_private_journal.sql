begin;

create table public.wn_journal (
 user_id uuid not null references public.wn_profiles(id) on delete cascade,
 country_id text not null references public.wn_countries(id),
 saved boolean not null default false,
 note text not null default '' check (char_length(note) <= 4000),
 first_explored_at timestamptz,
 last_explored_at timestamptz,
 saved_updated_at timestamptz,
 note_updated_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 primary key(user_id,country_id),
 check ((first_explored_at is null) = (last_explored_at is null)),
 check (first_explored_at <= last_explored_at)
);

-- Field-specific device clocks make retries idempotent without retaining note history.
create table wn_private.journal_clocks (
 user_id uuid not null references public.wn_profiles(id) on delete cascade,
 device_id uuid not null,
 country_id text not null references public.wn_countries(id),
 field text not null check (field in ('saved','note','explored')),
 sequence bigint not null check (sequence > 0),
 primary key(user_id,device_id,country_id,field)
);

alter table public.wn_journal enable row level security;
alter table wn_private.journal_clocks enable row level security;
revoke all on public.wn_journal, wn_private.journal_clocks from public,anon,authenticated;
grant select on public.wn_journal to authenticated;
create policy journal_owner_read on public.wn_journal for select to authenticated using (
 user_id=wn_private.active_user() and exists(select 1 from public.wn_profiles p where p.id=user_id and p.deleting_at is null)
);

insert into public.wn_journal(user_id,country_id,first_explored_at,last_explored_at)
 select user_id,country_id,explored_at,explored_at from public.wn_explorations;

create function wn_private.journal_entries(u uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'country_id',j.country_id,'saved',j.saved,'note',j.note,
  'first_explored_at',extract(epoch from j.first_explored_at),
  'last_explored_at',extract(epoch from j.last_explored_at),
  'saved_updated_at',extract(epoch from j.saved_updated_at),
  'note_updated_at',extract(epoch from j.note_updated_at),
  'updated_at',extract(epoch from j.updated_at)) order by j.country_id),'[]'::jsonb)
 from public.wn_journal j where j.user_id=u
$$;
revoke all on function wn_private.journal_entries(uuid) from public,anon,authenticated;

create function wn_private.sync_journal(p_owner uuid,p_device uuid,p_changes jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); c jsonb; country text; kind text; seq bigint;
 first_at timestamptz; last_at timestamptz; sharing boolean; previous bigint;
begin
 if p_owner is distinct from u or p_device is null then raise exception 'Account changed. Sign in again.' using errcode='42501'; end if;
 perform wn_private.consume_rate(u,'journal',240,interval '1 hour');
 select share_exploration into sharing from public.wn_profiles where id=u and deleting_at is null for update;
 if not found then raise exception 'Profile unavailable.' using errcode='42501'; end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'array' then raise exception 'Invalid journal changes.' using errcode='22023'; end if;
 if jsonb_array_length(p_changes)>585 or octet_length(p_changes::text)>4000000 then raise exception 'Journal changes too large.' using errcode='22023'; end if;
 if jsonb_array_length(p_changes)>0 and not exists(select 1 from wn_private.journal_clocks where user_id=u and device_id=p_device)
 and (select count(distinct device_id) from wn_private.journal_clocks where user_id=u)>=64 then
  raise exception 'Too many journal devices. Contact support.' using errcode='22023';
 end if;
 -- Older installed builds can continue to share explored countries.
 insert into public.wn_journal(user_id,country_id,first_explored_at,last_explored_at)
 select user_id,country_id,explored_at,explored_at from public.wn_explorations where user_id=u
 on conflict(user_id,country_id) do update set
 first_explored_at=least(wn_journal.first_explored_at,excluded.first_explored_at),
 last_explored_at=greatest(wn_journal.last_explored_at,excluded.last_explored_at);

 for c in select value from jsonb_array_elements(p_changes) loop
  country:=c->>'country_id'; kind:=c->>'field';
  if jsonb_typeof(c)<>'object' or country is null or not exists(select 1 from public.wn_countries where id=country)
   or kind is null or kind not in ('saved','note','explored') or jsonb_typeof(c->'sequence') is distinct from 'number'
   or (c->>'sequence') !~ '^[0-9]{1,16}$' then raise exception 'Invalid journal change.' using errcode='22023'; end if;
  seq:=(c->>'sequence')::bigint;
  if seq<=0 or seq>9007199254740991 then raise exception 'Invalid journal sequence.' using errcode='22023'; end if;
  select sequence into previous from wn_private.journal_clocks where user_id=u and device_id=p_device and country_id=country and field=kind;
  if previous is not null and seq<=previous then continue; end if;
  insert into public.wn_journal(user_id,country_id) values(u,country) on conflict do nothing;
  if kind='saved' then
   if jsonb_typeof(c->'saved') is distinct from 'boolean' then raise exception 'Invalid bookmark.' using errcode='22023'; end if;
   update public.wn_journal set saved=(c->>'saved')::boolean,saved_updated_at=now(),updated_at=now() where user_id=u and country_id=country;
  elsif kind='note' then
   if jsonb_typeof(c->'note') is distinct from 'string' or char_length(c->>'note')>4000 then raise exception 'Note is too long.' using errcode='22023'; end if;
   update public.wn_journal set note=c->>'note',note_updated_at=now(),updated_at=now() where user_id=u and country_id=country;
  else
   if jsonb_typeof(c->'first_explored_at') is distinct from 'number' or jsonb_typeof(c->'last_explored_at') is distinct from 'number' then
    raise exception 'Invalid exploration dates.' using errcode='22023'; end if;
   first_at:=to_timestamp((c->>'first_explored_at')::double precision);
   last_at:=to_timestamp((c->>'last_explored_at')::double precision);
   if first_at < '2000-01-01'::timestamptz or first_at>last_at or not isfinite(first_at) or not isfinite(last_at) then
    raise exception 'Invalid exploration dates.' using errcode='22023'; end if;
   first_at:=least(first_at,now()); last_at:=least(last_at,now());
   update public.wn_journal set first_explored_at=least(first_explored_at,first_at),
    last_explored_at=greatest(last_explored_at,last_at),updated_at=now() where user_id=u and country_id=country;
  end if;
  insert into wn_private.journal_clocks(user_id,device_id,country_id,field,sequence) values(u,p_device,country,kind,seq)
  on conflict(user_id,device_id,country_id,field) do update set sequence=excluded.sequence;
 end loop;
 -- Only the explored-country projection is shared. Bookmarks and notes never enter it.
 if sharing then
  insert into public.wn_explorations(user_id,country_id,explored_at)
   select user_id,country_id,last_explored_at from public.wn_journal where user_id=u and last_explored_at is not null
   on conflict(user_id,country_id) do nothing;
 end if;
 return jsonb_build_object('entries',wn_private.journal_entries(u));
end $$;
create function public.sync_journal(p_owner uuid,p_device uuid,p_changes jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select wn_private.sync_journal(p_owner,p_device,p_changes) $$;
revoke all on function wn_private.sync_journal(uuid,uuid,jsonb), public.sync_journal(uuid,uuid,jsonb) from public,anon;
grant execute on function wn_private.sync_journal(uuid,uuid,jsonb), public.sync_journal(uuid,uuid,jsonb) to authenticated;

create or replace function wn_private.export_my_data() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=wn_private.require_user(); result jsonb;
begin
 perform wn_private.consume_rate(u,'export',10,interval '1 day');
 select jsonb_build_object('exported_at',now(),'profile',wn_private.get_my_profile(),
 'email',(select email from auth.users where id=u),
 'journal',wn_private.journal_entries(u),
 'explorations',(select coalesce(jsonb_agg(to_jsonb(e)-'user_id'),'[]') from public.wn_explorations e where user_id=u),
 'friends',wn_private.list_friends(),
 'blocks',(select coalesce(jsonb_agg(to_jsonb(b)-'blocker'),'[]') from public.wn_blocks b where blocker=u),
 'reports',(select coalesce(jsonb_agg(to_jsonb(r)-'reporter_id'),'[]') from wn_private.reports r where reporter_id=u),
 'invitations',(select coalesce(jsonb_agg(to_jsonb(i)-'token_hash'-'owner_id'),'[]') from wn_private.invites i where owner_id=u)) into result;
 return result;
end $$;

notify pgrst, 'reload schema';
commit;
