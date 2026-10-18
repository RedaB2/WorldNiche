\set ON_ERROR_STOP on
begin;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
select public.update_my_profile('Alice','globe',true);
do $$ begin
 assert public.get_my_profile()->>'display_name'='Explorer';
 assert public.get_my_profile()->>'pending_display_name'='Alice';
 assert public.get_my_profile()->>'name_moderation_status'='pending';
 assert public.export_my_data()->'profile'->>'pending_display_name'='Alice';
 begin perform public.moderation_queue(); raise exception 'Client can moderate'; exception when insufficient_privilege then null; end;
 begin perform wn_private.moderation_queue(); raise exception 'Private moderator RPC exposed'; exception when insufficient_privilege then null; end;
 begin update public.wn_profiles set display_name='Bypass'; raise exception 'Direct write allowed'; exception when insufficient_privilege then null; end;
 perform set_config('test.moderation_invite',public.create_invite()->>'token',false);
end $$;
insert into storage.objects(bucket_id,name,metadata) values('profile-photos','00000000-0000-0000-0000-000000000001/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg','{"size":1234,"mimetype":"image/jpeg"}');
select public.set_profile_avatar('00000000-0000-0000-0000-000000000001/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg');
do $$ declare deleted integer; begin
 assert public.get_my_profile()->>'avatar_path' is null;
 assert public.get_my_profile()->>'photo_moderation_status'='pending';
 delete from storage.objects;
 get diagnostics deleted=row_count;
 assert deleted=0,'Queued image cannot be deleted and replaced while reviewed';
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002"}';
select public.update_my_profile('Bob','sun',false);
do $$ begin
 assert (select count(*) from public.wn_profiles)=1,'Stranger profile denied';
 assert (select count(*) from storage.objects)=0,'Stranger photo denied';
 assert public.preview_invite(current_setting('test.moderation_invite'))->>'display_name'='Explorer';
 assert public.accept_invite(current_setting('test.moderation_invite'))->>'status'='accepted';
 assert public.accept_invite(current_setting('test.moderation_invite'))->>'status'='already_friends';
 assert public.list_friends()->0->>'display_name'='Explorer';
 assert (select count(*) from storage.objects)=0,'Even friends cannot see pending photos';
end $$;
reset role;
set role service_role;
do $$ declare q jsonb; p jsonb; begin
 q:=public.moderation_queue();
 assert jsonb_array_length(q->'profiles')=2;
 select item into p from jsonb_array_elements(q->'profiles') item where item->>'user_id'='00000000-0000-0000-0000-000000000001';
 perform public.review_profile_content((p->>'user_id')::uuid,'name',(p->>'name_revision')::uuid,'approve');
 perform public.review_profile_content((p->>'user_id')::uuid,'photo',(p->>'photo_revision')::uuid,'approve');
 begin perform public.review_profile_content((p->>'user_id')::uuid,'photo',(p->>'photo_revision')::uuid,'approve'); raise exception 'Stale approval accepted'; exception when serialization_failure then null; end;
end $$;
reset role;
set role authenticated;
do $$ begin
 assert public.list_friends()->0->>'display_name'='Alice';
 assert (select count(*) from storage.objects)=1,'Approved photo available to current friend';
 perform public.report_user('00000000-0000-0000-0000-000000000001','inappropriate_photo','Please review this photo.');
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
select public.update_my_profile('Alice revision','globe',true);
insert into storage.objects(bucket_id,name,metadata) values('profile-photos','00000000-0000-0000-0000-000000000001/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jpg','{"size":1234,"mimetype":"image/jpeg"}');
select public.set_profile_avatar('00000000-0000-0000-0000-000000000001/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jpg');
do $$ declare deleted integer; begin
 assert public.get_my_profile()->>'display_name'='Alice','Previous approval survives edit';
 delete from storage.objects;
 get diagnostics deleted=row_count;
 assert deleted=0,'Approved and pending images cannot be swapped';
 assert jsonb_array_length(public.export_my_data()->'reports')=0,'Reported user cannot see reports against them';
end $$;
reset role;
select set_config('test.old_revision',(select name_revision::text from wn_private.profile_moderation where user_id='00000000-0000-0000-0000-000000000001'),false);
set role authenticated;
select public.update_my_profile('Another revision','globe',true);
reset role;
set role service_role;
do $$ begin
 begin perform public.review_profile_content('00000000-0000-0000-0000-000000000001','name',current_setting('test.old_revision')::uuid,'approve'); raise exception 'Changed submission approved'; exception when serialization_failure then null; end;
end $$;
reset role;
set role authenticated;
select public.update_my_profile('https://spam.invalid','globe',true);
do $$ begin
 assert public.get_my_profile()->>'name_moderation_status'='rejected';
 assert public.get_my_profile()->>'display_name'='Alice','Rejected name is never published';
end $$;
reset role;
set role service_role;
do $$ declare q jsonb; report jsonb; begin
 q:=public.moderation_queue(); report:=q->'reports'->0;
 assert report->>'reported_display_name'='Alice';
 assert report->>'reported_avatar_path' like '%aaaaaaaaaaaa.jpg';
 perform public.moderate_user('00000000-0000-0000-0000-000000000001','restrict','Community guidelines',(report->>'id')::uuid);
 assert public.moderation_queue()->>'open_report_count'='0';
end $$;
reset role;
set role authenticated;
do $$ begin
 assert public.get_my_profile()->>'community_restricted'='true';
 begin perform public.create_invite(); raise exception 'Restricted invite allowed'; exception when insufficient_privilege then null; end;
 assert public.get_my_profile()->>'share_exploration'='false';
 assert public.export_my_data() is not null,'Restricted user retains export and deletion';
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002"}';
do $$ begin
 assert public.list_friends()='[]';
 assert (select count(*) from storage.objects)=0;
 assert public.accept_invite(current_setting('test.moderation_invite'))->>'status'='unavailable';
end $$;
reset role;
select public.moderate_user('00000000-0000-0000-0000-000000000001','restore');
set role authenticated;
do $$ begin
 assert public.list_friends()->0->>'display_name'='Explorer','Restore never republishes removed content';
 perform public.block_user('00000000-0000-0000-0000-000000000001');
 assert public.list_friends()='[]';
 assert (select count(*) from storage.objects)=0;
end $$;
reset role;
-- Auth cascading deletion must remove private moderation data as well.
delete from auth.users where id='00000000-0000-0000-0000-000000000001';
do $$ begin
 assert not exists(select 1 from wn_private.profile_moderation where user_id='00000000-0000-0000-0000-000000000001');
 assert not exists(select 1 from wn_private.moderation_actions where subject_id='00000000-0000-0000-0000-000000000001');
 assert not exists(select 1 from wn_private.reports);
 assert not exists(select 1 from public.wn_friendships);
 assert not exists(select 1 from public.wn_blocks);
end $$;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
do $$ begin
 begin perform public.update_my_profile('Recreated','globe',false); raise exception 'Deleted user recreated profile'; exception when invalid_authorization_specification then null; end;
end $$;
reset role;
rollback;
\echo 'PASS: moderation quarantine, immutable review, revision checks, privileged decisions, reports, restrictions, friend access, export and deletion cascades.'
