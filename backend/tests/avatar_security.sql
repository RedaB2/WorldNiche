\set ON_ERROR_STOP on
begin;
do $$ begin
 assert (select public=false and file_size_limit=300000 and allowed_mime_types=array['image/jpeg'] from storage.buckets where id='profile-photos'),'Private JPEG-only limited bucket';
end $$;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
select public.update_my_profile('Alice','globe',false);
insert into storage.objects(bucket_id,name,metadata) values('profile-photos','00000000-0000-0000-0000-000000000001/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg','{"size":1234,"mimetype":"image/jpeg"}');
select public.set_profile_avatar('00000000-0000-0000-0000-000000000001/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg');
do $$ begin
 assert public.get_my_profile()->>'avatar_path' like '%aaaaaaaaaaaa.jpg';
 assert public.export_my_data()->'profile'->>'avatar_path' like '%aaaaaaaaaaaa.jpg','Exports contain photo reference';
 begin perform public.set_profile_avatar('00000000-0000-0000-0000-000000000002/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jpg'); raise exception 'Cross-account path accepted'; exception when sqlstate '22023' then null; end;
 begin perform public.set_profile_avatar('00000000-0000-0000-0000-000000000001/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jpg'); raise exception 'Missing object accepted'; exception when sqlstate '22023' then null; end;
 begin insert into storage.objects(bucket_id,name) values('profile-photos','00000000-0000-0000-0000-000000000002/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg'); raise exception 'Other folder upload allowed'; exception when insufficient_privilege then null; end;
 begin insert into storage.objects(bucket_id,name) values('profile-photos','00000000-0000-0000-0000-000000000001/../bad.jpg'); raise exception 'Traversal allowed'; exception when insufficient_privilege then null; end;
 perform set_config('test.avatar_invite',public.create_invite()->>'token',false);
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002"}';
select public.update_my_profile('Bob','sun',false);
do $$ begin
 assert (select count(*) from storage.objects)=0,'Stranger cannot download photo';
 assert not(public.preview_invite(current_setting('test.avatar_invite')) ? 'avatar_path'),'Invitation never reveals private photo';
 perform public.accept_invite(current_setting('test.avatar_invite'));
 assert (select count(*) from storage.objects)=1,'Current friend can download active photo';
 assert public.list_friends()->0->>'avatar_path' like '%aaaaaaaaaaaa.jpg';
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
insert into storage.objects(bucket_id,name,metadata) values('profile-photos','00000000-0000-0000-0000-000000000001/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jpg','{"size":1234,"mimetype":"image/jpeg"}');
select public.set_profile_avatar('00000000-0000-0000-0000-000000000001/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jpg');
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002"}';
do $$ begin
 assert (select count(*) from storage.objects)=1,'Old or orphan photos are hidden from friends';
 assert (select name like '%bbbbbbbbbbbb.jpg' from storage.objects),'Friend sees only the selected photo';
 perform public.block_user('00000000-0000-0000-0000-000000000001');
 assert (select count(*) from storage.objects)=0,'Blocking immediately removes photo access';
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
select public.set_profile_avatar(null);
do $$ begin
 assert public.get_my_profile()->>'avatar_path' is null,'Removing photo restores symbol';
 perform public.authorize_deletion();
 begin insert into storage.objects(bucket_id,name,metadata) values('profile-photos','00000000-0000-0000-0000-000000000001/cccccccc-cccc-cccc-cccc-cccccccccccc.jpg','{"size":1234,"mimetype":"image/jpeg"}'); raise exception 'Deletion allowed new upload'; exception when insufficient_privilege then null; end;
 begin perform public.set_profile_avatar(null); raise exception 'Deletion allowed photo change'; exception when sqlstate '22023' then null; end;
end $$;
reset role;
set role anon;
do $$ begin
 begin perform public.set_profile_avatar(null); raise exception 'Anonymous photo mutation allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
\echo 'PASS: private photo bucket, owner uploads, active-friend access, no preview leakage, old-photo denial, blocks, deletion gate, export, and anonymous denial.'
