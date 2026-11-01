begin;

-- A shared bearer link may disclose only its owner's approved display name.
-- Crawlers never redeem invitations, create friendships or consume invite quotas.
create function public.invitation_link_metadata(p_token text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare friend_name text;
begin
 if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return '{}'; end if;
 select p.display_name into friend_name
 from wn_private.invites i join public.wn_profiles p on p.id=i.owner_id
 where i.token_hash=extensions.digest(p_token,'sha256')
   and i.revoked_at is null and i.expires_at>now()
   and not wn_private.community_restricted(i.owner_id);
 if friend_name is null or lower(btrim(friend_name))='explorer' then return '{}'; end if;
 return jsonb_build_object('display_name',friend_name);
end $$;
revoke all on function public.invitation_link_metadata(text) from public;
grant execute on function public.invitation_link_metadata(text) to anon,authenticated;

commit;
