begin;

-- The worker revalidates its claim immediately before sending content to the
-- provider. A withdrawal after an HTTP request starts cannot recall that request;
-- finish_profile_check independently prevents publication after withdrawal.
create function wn_private.profile_check_is_current(p_user_id uuid,p_kind text,p_revision uuid,p_claim_token uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.wn_profiles p
  join wn_private.profile_moderation m on m.user_id=p.id
  join wn_private.profile_check_jobs j on j.user_id=p.id and j.kind=p_kind
  where p.id=p_user_id and p.deleting_at is null and m.restricted_at is null
   and m.automatic_profile_checks_enabled and m.automatic_checks_consent_version='2026-10-24'
   and j.revision=p_revision and j.claim_token=p_claim_token and j.state='checking' and j.lease_until>now()
   and ((p_kind='name' and m.name_status='pending' and m.name_revision=p_revision)
    or (p_kind='photo' and m.photo_status='pending' and m.photo_revision=p_revision))
 )
$$;
create function public.profile_check_is_current(p_user_id uuid,p_kind text,p_revision uuid,p_claim_token uuid) returns boolean
language sql security invoker set search_path='' as $$ select wn_private.profile_check_is_current(p_user_id,p_kind,p_revision,p_claim_token) $$;
revoke all on function wn_private.profile_check_is_current(uuid,text,uuid,uuid),public.profile_check_is_current(uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function wn_private.profile_check_is_current(uuid,text,uuid,uuid),public.profile_check_is_current(uuid,text,uuid,uuid) to service_role;

commit;
