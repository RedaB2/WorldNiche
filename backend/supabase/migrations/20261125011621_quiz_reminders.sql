begin;
create table wn_private.quiz_devices (
  installation uuid primary key,
  user_id uuid references auth.users(id) on delete cascade,
  token text not null check (length(token) between 32 and 512 and token ~ '^[0-9a-f]+$'),
  sandbox boolean not null,
  zone text not null,
  next_due timestamptz not null,
  last_day date,
  completed_day date,
  lease uuid,
  registered_at timestamptz not null default now(),
  unique(token,sandbox)
);
-- Bound guest enrollments as well as authenticated enrollments. Store hourly,
-- pseudonymous counters only for new token registrations.
create table wn_private.quiz_enrollments (
  hour timestamptz not null, bucket text not null, n integer not null,
  primary key(hour,bucket)
);
alter table wn_private.quiz_enrollments enable row level security;
revoke all on wn_private.quiz_enrollments from public,anon,authenticated;
create index quiz_devices_due on wn_private.quiz_devices(next_due);
create index quiz_devices_owner on wn_private.quiz_devices(user_id) where user_id is not null;
alter table wn_private.quiz_devices enable row level security;
revoke all on wn_private.quiz_devices from public,anon,authenticated;

create function wn_private.quiz_evening(z text, after_time timestamptz) returns timestamptz
language sql stable set search_path='' as $$
  select ((after_time at time zone z)::date + case when (after_time at time zone z)::time >= time '19:00' then 1 else 0 end
    + time '19:00') at time zone z
$$;

-- The installation ID is a random private capability. No client can list device registrations.
create function wn_private.set_quiz_reminder(p_installation uuid,p_token text,p_sandbox boolean,
  p_zone text,p_enabled boolean,p_completed date,p_owner uuid) returns void
language plpgsql security definer set search_path='' as $$
declare
  u uuid;
  h timestamptz := date_trunc('hour',now());
  client text := coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'x-forwarded-for','local');
  n integer;
  today date := (now() at time zone 'UTC')::date;
begin
  if p_installation is null or p_enabled is null then raise exception 'Invalid installation'; end if;
  if not p_enabled then
    delete from wn_private.quiz_devices where installation=p_installation;
    return;
  end if;
  if auth.uid() is not null then u:=wn_private.require_user(); end if;
  if p_owner is distinct from u or p_token is null or length(p_token) not between 32 and 512 or p_token !~ '^[0-9a-f]+$' or p_sandbox is null
    or p_zone is null or length(p_zone)>100 or not exists(select from pg_timezone_names where name=p_zone)
    then raise exception 'Invalid reminder registration'; end if;
  -- A reinstall may have a fresh installation ID and the same APNs token.
  perform pg_advisory_xact_lock(hashtextextended(p_token,0));
  if not exists(select from wn_private.quiz_devices where token=p_token and sandbox=p_sandbox) then
    delete from wn_private.quiz_enrollments where hour<h-interval '24 hours';
    insert into wn_private.quiz_enrollments values(h,'all',1)
      on conflict(hour,bucket) do update set n=quiz_enrollments.n+1 returning quiz_enrollments.n into n;
    if n>5000 then raise exception 'Enrollment busy' using errcode='PT429'; end if;
    insert into wn_private.quiz_enrollments values(h,md5(h::text || split_part(client,',',1)),1)
      on conflict(hour,bucket) do update set n=quiz_enrollments.n+1 returning quiz_enrollments.n into n;
    if n>120 then raise exception 'Enrollment busy' using errcode='PT429'; end if;
  end if;
  delete from wn_private.quiz_devices where token=p_token and sandbox=p_sandbox and installation<>p_installation;
  insert into wn_private.quiz_devices as d(installation,user_id,token,sandbox,zone,next_due,completed_day)
    values(p_installation,u,p_token,p_sandbox,p_zone,wn_private.quiz_evening(p_zone,now()),case when p_completed=today then today end)
    on conflict(installation) do update set user_id=u, token=p_token,sandbox=p_sandbox,zone=p_zone,
      next_due=case when (d.zone,d.token,d.sandbox,d.user_id) is distinct from (p_zone,p_token,p_sandbox,u)
        then excluded.next_due else d.next_due end,
      lease=case when (d.zone,d.token,d.sandbox,d.user_id) is distinct from (p_zone,p_token,p_sandbox,u)
        then null else d.lease end,
      completed_day=case when d.user_id is distinct from u then excluded.completed_day
        else greatest(d.completed_day,excluded.completed_day) end,
      registered_at=now();
end $$;
create function public.set_quiz_reminder(p_installation uuid,p_token text,p_sandbox boolean,p_zone text,
  p_enabled boolean,p_completed date,p_owner uuid) returns void language sql security definer set search_path='' as $$
  select wn_private.set_quiz_reminder(p_installation,p_token,p_sandbox,p_zone,p_enabled,p_completed,p_owner)
$$;

create function wn_private.claim_quiz_reminders() returns jsonb language plpgsql security definer set search_path='' as $$
declare today date := (now() at time zone 'UTC')::date; batch jsonb;
begin
  with due as (
    select d.installation,
      (d.last_day is distinct from today and d.completed_day is distinct from today and
       extract(hour from now() at time zone d.zone)=19 and exists(select from wn_private.quiz_schedule where day=today) and
       not exists(select from wn_private.quiz_attempts where user_id=d.user_id and day=today)) as send
    from wn_private.quiz_devices d where d.next_due<=now()
    order by d.next_due limit 100 for update of d skip locked
  ), claimed as (
    update wn_private.quiz_devices d set
      lease=case when due.send then gen_random_uuid() end,
      next_due=case when due.send then now()+interval '15 minutes' else wn_private.quiz_evening(d.zone,now()) end
    from due where d.installation=due.installation
    returning d.installation,d.lease,d.token,d.sandbox,today as day,d.registered_at
  )
  select coalesce(jsonb_agg(to_jsonb(c)),'[]') into batch from claimed c where lease is not null;
  return batch;
end $$;
create function wn_private.finish_quiz_reminder(p_installation uuid,p_lease uuid,p_day date,p_status text,p_invalid_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
begin
  if p_status='invalid' then
    delete from wn_private.quiz_devices where installation=p_installation and lease=p_lease
      and (p_invalid_at is null or registered_at<=p_invalid_at);
  elsif p_status='sent' then
    update wn_private.quiz_devices set last_day=p_day,lease=null,next_due=wn_private.quiz_evening(zone,now())
      where installation=p_installation and lease=p_lease;
  elsif p_status='retry' then
    update wn_private.quiz_devices set lease=null where installation=p_installation and lease=p_lease;
  else raise exception 'Unknown APNs result'; end if;
end $$;
create function public.claim_quiz_reminders() returns jsonb language sql security invoker set search_path='' as $$
  select wn_private.claim_quiz_reminders()
$$;
create function public.finish_quiz_reminder(p_installation uuid,p_lease uuid,p_day date,p_status text,p_invalid_at timestamptz)
returns void language sql security invoker set search_path='' as $$
  select wn_private.finish_quiz_reminder(p_installation,p_lease,p_day,p_status,p_invalid_at)
$$;
revoke all on function wn_private.quiz_evening(text,timestamptz),
  wn_private.set_quiz_reminder(uuid,text,boolean,text,boolean,date,uuid),public.set_quiz_reminder(uuid,text,boolean,text,boolean,date,uuid),
  wn_private.claim_quiz_reminders(),public.claim_quiz_reminders(),wn_private.finish_quiz_reminder(uuid,uuid,date,text,timestamptz),
  public.finish_quiz_reminder(uuid,uuid,date,text,timestamptz) from public,anon,authenticated;
grant execute on function wn_private.set_quiz_reminder(uuid,text,boolean,text,boolean,date,uuid),
  public.set_quiz_reminder(uuid,text,boolean,text,boolean,date,uuid) to anon,authenticated;
grant execute on function wn_private.claim_quiz_reminders(),public.claim_quiz_reminders(),
  wn_private.finish_quiz_reminder(uuid,uuid,date,text,timestamptz),public.finish_quiz_reminder(uuid,uuid,date,text,timestamptz) to service_role;
notify pgrst,'reload schema';
commit;
