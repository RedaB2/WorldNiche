\set ON_ERROR_STOP on
begin;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
select public.update_my_profile('Mira','globe',false);
select set_config('test.metadata_invite',public.create_invite()->>'token',true);
reset role;
set role anon;
do $$ begin
 assert public.invitation_link_metadata(current_setting('test.metadata_invite'))='{}', 'Pending first name stays private';
 assert public.invitation_link_metadata(null)='{}';
 assert public.invitation_link_metadata('bad')='{}';
 assert public.invitation_link_metadata(repeat('b',64))='{}';
 begin perform public.preview_invite(current_setting('test.metadata_invite')); raise exception 'Full preview exposed'; exception when insufficient_privilege then null; end;
 begin perform public.accept_invite(current_setting('test.metadata_invite')); raise exception 'Anonymous acceptance allowed'; exception when insufficient_privilege then null; end;
 begin perform 1 from public.wn_profiles; raise exception 'Profiles exposed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select public.review_profile_content(user_id,'name',name_revision,'approve') from wn_private.profile_moderation
 where user_id='00000000-0000-0000-0000-000000000001';
set role authenticated;
select public.update_my_profile('Pending revision','globe',false);
reset role;
select set_config('test.metadata_rates',(select count(*)::text from wn_private.rate_events),true);
select set_config('test.metadata_friendships',(select count(*)::text from public.wn_friendships),true);
set role anon;
do $$ begin
 for i in 1..20 loop
  assert public.invitation_link_metadata(current_setting('test.metadata_invite'))='{"display_name":"Mira"}', 'Only the approved name is disclosed';
 end loop;
end $$;
reset role;
do $$ begin
 assert (select count(*)::text from wn_private.rate_events)=current_setting('test.metadata_rates'), 'Previews do not consume user quotas';
 assert (select count(*)::text from public.wn_friendships)=current_setting('test.metadata_friendships'), 'Previews do not create friends';
 assert exists(select 1 from wn_private.invites where token_hash=extensions.digest(current_setting('test.metadata_invite'),'sha256') and revoked_at is null), 'Previews do not consume links';
end $$;
update wn_private.invites set expires_at=now()-interval '1 second';
set role anon;
do $$ begin assert public.invitation_link_metadata(current_setting('test.metadata_invite'))='{}', 'Expired links hide names'; end $$;
reset role;
update wn_private.invites set expires_at=now()+interval '1 day',revoked_at=now();
set role anon;
do $$ begin assert public.invitation_link_metadata(current_setting('test.metadata_invite'))='{}', 'Revoked links hide names'; end $$;
reset role;
update wn_private.invites set revoked_at=null;
select public.moderate_user('00000000-0000-0000-0000-000000000001','restrict');
set role anon;
do $$ begin assert public.invitation_link_metadata(current_setting('test.metadata_invite'))='{}', 'Restricted owners stay hidden'; end $$;
reset role;
delete from auth.users where id='00000000-0000-0000-0000-000000000001';
set role anon;
do $$ begin assert public.invitation_link_metadata(current_setting('test.metadata_invite'))='{}', 'Deleted accounts stay hidden'; end $$;
reset role;
rollback;
