\set ON_ERROR_STOP on
begin;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
do $$ begin
 assert public.get_my_profile() is null;
 perform public.update_my_profile('Alice','globe',false);
 assert (public.sync_explorations(array['FR'])->>'count')::int=0, 'No upload before opt-in';
 perform public.update_my_profile('Alice','globe',true);
 assert (public.sync_explorations(array['FR','JP','FR'])->>'count')::int=2, 'Deduplicate exploration IDs';
 begin perform public.sync_explorations(array['XX']); raise exception 'Invalid country accepted'; exception when sqlstate '22023' then null; end;
 perform set_config('test.invite',public.create_invite()->>'token',false);
 perform set_config('test.expired_invite',public.create_invite()->>'token',false);
 assert (public.preview_invite(current_setting('test.invite'))->>'status')='self';
 assert public.accept_invite(current_setting('test.invite'))->>'status'='self','Own invitation cannot create a self friendship';
 begin insert into public.wn_profiles values('00000000-0000-0000-0000-000000000002','Forgery','globe',false,now(),now()); raise exception 'Direct mutation allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update wn_private.invites set expires_at=now()-interval '1 second' where token_hash=extensions.digest(current_setting('test.expired_invite'),'sha256');
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002"}';
do $$ declare preview jsonb; friends jsonb; begin
 perform public.update_my_profile('Bob','sun',false);
 assert public.preview_invite(current_setting('test.expired_invite'))->>'status'='unavailable';
 assert public.accept_invite(current_setting('test.expired_invite'))->>'status'='unavailable';
 perform set_config('test.bob_invite',public.create_invite()->>'token',false);
 assert (select count(*) from public.wn_profiles)=1,'Strangers cannot read profiles';
 assert (select count(*) from public.wn_explorations)=0,'Strangers cannot read explorations';
 preview:=public.preview_invite(current_setting('test.invite'));
 assert preview->>'status'='available' and preview->>'display_name'='Alice' and preview ? 'expires_at';
 assert (preview->>'already_friends')::boolean=false;
 assert jsonb_array_length(public.list_friends())=0,'Preview never creates a friendship';
 assert public.accept_invite(current_setting('test.invite'))->>'status'='accepted';
 assert public.accept_invite(current_setting('test.invite'))->>'status'='already_friends','Invite redemption idempotent';
 perform public.remove_friend('00000000-0000-0000-0000-000000000001');
 assert jsonb_array_length(public.list_friends())=0;
 assert public.accept_invite(current_setting('test.invite'))->>'status'='accepted';
 friends:=public.list_friends();
 assert jsonb_array_length(friends)=1 and (friends->0->>'explored_count')::int=2;
 assert (select count(*) from public.wn_profiles)=2,'Friends can read profile';
 assert (select count(*) from public.wn_explorations)=2,'Opted-in explorations readable by friend';
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000003","session_id":"10000000-0000-0000-0000-000000000003"}';
do $$ begin
 perform public.update_my_profile('Eve','moon',false);
 assert (select count(*) from public.wn_profiles)=1,'Third party cannot see friends';
 assert (select count(*) from public.wn_friendships)=0;
 assert (select count(*) from public.wn_explorations)=0;
 begin perform public.report_user('00000000-0000-0000-0000-000000000001','spam','fabricated stranger report'); raise exception 'Report stranger allowed'; exception when insufficient_privilege then null; end;
 assert public.preview_invite('bad-token')->>'status'='unavailable';
 assert public.accept_invite(repeat('f',64))->>'status'='unavailable';
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
do $$ begin
 assert jsonb_array_length(public.list_friends())=1,'Friendship mutual';
 perform public.update_my_profile('Alice','globe',false);
 assert (select count(*) from public.wn_explorations)=0,'Opt out deletes cloud progress';
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002"}';
do $$ begin
 assert (public.list_friends()->0->>'share_exploration')::boolean=false;
 assert (public.list_friends()->0->>'explored_count')::int=0;
 perform public.block_user('00000000-0000-0000-0000-000000000001');
 assert jsonb_array_length(public.list_friends())=0;
 assert public.preview_invite(current_setting('test.invite'))->>'status'='unavailable';
 assert public.accept_invite(current_setting('test.invite'))->>'status'='unavailable';
 assert (select count(*) from public.wn_profiles)=1,'Block hides profile';
 perform public.report_user('00000000-0000-0000-0000-000000000001','inappropriate_name','Test report');
 assert jsonb_array_length(public.export_my_data()->'reports')=1;
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
do $$ begin
 assert jsonb_array_length(public.list_friends())=0,'Block enforced both directions';
 assert public.preview_invite(current_setting('test.bob_invite'))->>'status'='unavailable';
 assert public.accept_invite(current_setting('test.bob_invite'))->>'status'='unavailable';
 perform public.revoke_invites();
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000003","session_id":"10000000-0000-0000-0000-000000000003"}';
do $$ begin
 assert public.preview_invite(current_setting('test.invite'))->>'status'='unavailable','Revocation blocks preview';
 assert public.accept_invite(current_setting('test.invite'))->>'status'='unavailable','Revocation blocks redemption';
 for i in 1..10 loop perform public.create_invite(); end loop;
 begin perform public.create_invite(); raise exception 'Invite quota bypassed'; exception when raise_exception then assert sqlerrm='Please wait before trying again.'; end;
end $$;
reset role;
do $$ begin
 assert not exists(select 1 from information_schema.columns where table_schema='wn_private' and table_name='invites' and column_name='token');
 assert (select count(*) from wn_private.reports)=1;
end $$;
delete from auth.users where id='00000000-0000-0000-0000-000000000001';
do $$ begin
 assert not exists(select 1 from public.wn_profiles where id='00000000-0000-0000-0000-000000000001');
 assert (select count(*) from public.wn_friendships)=0;
 assert (select count(*) from public.wn_blocks)=0;
 assert (select count(*) from wn_private.reports)=0,'Deletion removes shared report data';
 assert not exists(select 1 from wn_private.invites where owner_id='00000000-0000-0000-0000-000000000001');
end $$;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
do $$ begin
 begin perform public.update_my_profile('Undelete','globe',true); raise exception 'Deleted user reused JWT'; exception when invalid_authorization_specification then null; end;
 assert (select count(*) from public.wn_profiles)=0,'Deleted JWT has no read access';
end $$;
reset role;
delete from auth.sessions where user_id='00000000-0000-0000-0000-000000000002';
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002"}';
do $$ begin
 begin perform public.get_my_profile(); raise exception 'Revoked session reused JWT'; exception when invalid_authorization_specification then null; end;
end $$;
reset role;
set role anon;
do $$ begin
 begin perform public.get_my_profile(); raise exception 'Anonymous RPC allowed'; exception when insufficient_privilege then null; end;
 begin perform public.create_invite(); raise exception 'Anonymous invite allowed'; exception when insufficient_privilege then null; end;
 begin perform public.preview_invite(repeat('a',64)); raise exception 'Anonymous preview allowed'; exception when insufficient_privilege then null; end;
 begin perform public.accept_invite(repeat('a',64)); raise exception 'Anonymous redemption allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
\echo 'PASS: consent, RLS isolation, reciprocal/idempotent invitations, blocks, reports, revocation, rate limits, deletion cascades, and stale-session denial.'
