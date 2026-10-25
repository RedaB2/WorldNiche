\set ON_ERROR_STOP on
begin;
-- Hosted extensions are mocked only in this disposable test transaction.
create schema vault;
create table vault.decrypted_secrets(name text,decrypted_secret text);
insert into vault.decrypted_secrets values
 ('worldniche_moderation_url','https://testfixture.supabase.co/functions/v1/moderate-profile'),
 ('worldniche_moderation_worker_secret','synthetic-test-worker-token-at-least-32-characters');
create schema net;
create table net.test_dispatches(timeout_ms integer);
create function net.http_post(url text,body jsonb,headers jsonb,timeout_milliseconds integer) returns bigint
language plpgsql as $$ begin
 assert url='https://testfixture.supabase.co/functions/v1/moderate-profile';
 assert body='{}'::jsonb;
 assert length(headers->>'x-worldniche-worker-secret')>=32;
 insert into net.test_dispatches values(timeout_milliseconds);
 return 1;
end $$;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
select public.update_my_profile('Alice','globe',false);
insert into storage.objects(bucket_id,name,metadata) values('profile-photos','00000000-0000-0000-0000-000000000001/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg','{"size":1234,"mimetype":"image/jpeg"}');
select public.set_profile_avatar('00000000-0000-0000-0000-000000000001/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg');
do $$ begin
 assert public.get_my_profile()->>'automatic_profile_checks_enabled'='false';
 assert public.get_my_profile()->>'profile_check_consent_recorded'='false';
 assert public.get_my_profile()->>'name_check_state'='review';
 assert public.get_my_profile()->>'pending_display_name'='Alice';
 begin perform public.claim_profile_checks(); raise exception 'Client claimed moderation jobs'; exception when insufficient_privilege then null; end;
 begin perform public.finish_profile_check(auth.uid(),'name',gen_random_uuid(),gen_random_uuid(),'approve'); raise exception 'Client approved a job'; exception when insufficient_privilege then null; end;
 begin perform public.profile_check_is_current(auth.uid(),'name',gen_random_uuid(),gen_random_uuid()); raise exception 'Client inspected a worker claim'; exception when insufficient_privilege then null; end;
 begin perform wn_private.dispatch_profile_checks(); raise exception 'Client dispatched worker'; exception when insufficient_privilege then null; end;
 begin perform count(*) from wn_private.profile_check_jobs; raise exception 'Client read private jobs'; exception when insufficient_privilege then null; end;
 assert public.authorize_profile_check()->>'user_id'=auth.uid()::text;
end $$;
reset role;
set role service_role;
do $$ begin assert public.claim_profile_checks()='[]','No provider work without explicit consent'; end $$;
reset role;
set role authenticated;
select public.set_profile_check_consent(false);
do $$ begin assert public.get_my_profile()->>'profile_check_consent_recorded'='true'; end $$;
select public.set_profile_check_consent(true);
reset role;
truncate net.test_dispatches;
set role authenticated;
select public.set_profile_avatar(null);
select public.set_profile_avatar('00000000-0000-0000-0000-000000000001/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg');
reset role;
do $$ begin assert (select count(*) from net.test_dispatches)=1,'A photo-only edit must dispatch checks'; end $$;
set role authenticated;
do $$ begin
 assert public.get_my_profile()->>'automatic_profile_checks_enabled'='true';
 assert public.get_my_profile()->>'name_check_state'='queued';
 assert public.get_my_profile()->>'photo_check_state'='queued';
 perform set_config('test.automatic_invite',public.create_invite()->>'token',false);
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002"}';
select public.update_my_profile('Bob','sun',false);
select public.accept_invite(current_setting('test.automatic_invite'));
do $$ begin
 assert public.list_friends()->0->>'display_name'='Explorer';
 assert (select count(*) from storage.objects)=0,'Pending photo cannot leak to friends';
end $$;
reset role;
set role service_role;
do $$ declare jobs jsonb; n jsonb; f jsonb; begin
 jobs:=public.claim_profile_checks('00000000-0000-0000-0000-000000000001',2);
 assert jsonb_array_length(jobs)=2;
 select x into n from jsonb_array_elements(jobs)x where x->>'kind'='name';
 select x into f from jsonb_array_elements(jobs)x where x->>'kind'='photo';
 assert n->>'text'='Alice' and n->>'photo_path' is null;
 assert public.profile_check_is_current((n->>'user_id')::uuid,'name',(n->>'revision')::uuid,(n->>'claim_token')::uuid);
 assert not public.profile_check_is_current((n->>'user_id')::uuid,'name',(n->>'revision')::uuid,gen_random_uuid()),'A different claim cannot disclose content';
 assert f->>'photo_path' like '%aaaaaaaaaaaa.jpg' and f->>'text' is null;
 assert public.claim_profile_checks()='[]','Claims exclude in-flight and unconsented jobs';
 perform set_config('test.name_job',n::text,false);
 perform set_config('test.photo_job',f::text,false);
 assert public.finish_profile_check((f->>'user_id')::uuid,'photo',(f->>'revision')::uuid,(f->>'claim_token')::uuid,'approve')->>'applied'='true';
 assert public.finish_profile_check((f->>'user_id')::uuid,'photo',(f->>'revision')::uuid,(f->>'claim_token')::uuid,'approve')->>'applied'='false','Result is idempotent';
end $$;
reset role;
do $$ begin
 assert exists(select 1 from net.test_dispatches where timeout_ms=60000),'Background worker needs a realistic response deadline';
end $$;
reset role;
set role authenticated;
do $$ begin
 assert public.list_friends()->0->>'avatar_path' like '%aaaaaaaaaaaa.jpg','Approval publishes friend photo immediately';
 assert (select count(*) from storage.objects)=1;
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
select public.update_my_profile('Alice Changed','globe',false);
reset role;
set role service_role;
do $$ declare n jsonb:=current_setting('test.name_job')::jsonb; fresh jsonb; begin
 assert public.finish_profile_check((n->>'user_id')::uuid,'name',(n->>'revision')::uuid,(n->>'claim_token')::uuid,'approve')->>'applied'='false','Old revision must never publish';
 assert not public.profile_check_is_current((n->>'user_id')::uuid,'name',(n->>'revision')::uuid,(n->>'claim_token')::uuid),'Old revision cannot be sent to provider';
 fresh:=public.claim_profile_checks('00000000-0000-0000-0000-000000000001',2)->0;
 assert fresh->>'text'='Alice Changed';
 assert public.finish_profile_check((fresh->>'user_id')::uuid,'name',(fresh->>'revision')::uuid,gen_random_uuid(),'approve')->>'applied'='false','Claim token is required';
 assert public.finish_profile_check((fresh->>'user_id')::uuid,'name',(fresh->>'revision')::uuid,(fresh->>'claim_token')::uuid,'review')->>'applied'='true';
 assert public.claim_profile_checks()='[]','Flagged jobs cannot be retried into approval';
end $$;
reset role;
set role authenticated;
select public.set_profile_check_consent(false);
select public.set_profile_check_consent(true);
do $$ begin assert public.get_my_profile()->>'name_check_state'='review','Consent toggles cannot bypass a flag'; end $$;
select public.update_my_profile('Alice Retry','globe',false);
reset role;
set role service_role;
do $$ declare n jsonb; begin
 n:=public.claim_profile_checks('00000000-0000-0000-0000-000000000001')->0;
 assert public.finish_profile_check((n->>'user_id')::uuid,'name',(n->>'revision')::uuid,(n->>'claim_token')::uuid,'retry')->>'applied'='true';
 assert public.claim_profile_checks()='[]','Provider failures back off';
end $$;
reset role;
update wn_private.profile_check_jobs set available_at=now()-interval '1 second' where kind='name' and state='retry';
set role service_role;
do $$ declare n jsonb; begin
 n:=public.claim_profile_checks('00000000-0000-0000-0000-000000000001')->0;
 perform set_config('test.revoked_job',n::text,false);
end $$;
reset role;
set role authenticated;
select public.set_profile_check_consent(false);
reset role;
set role service_role;
do $$ declare n jsonb:=current_setting('test.revoked_job')::jsonb; begin
 assert public.finish_profile_check((n->>'user_id')::uuid,'name',(n->>'revision')::uuid,(n->>'claim_token')::uuid,'approve')->>'applied'='false','Revocation invalidates even an in-flight approval';
 assert not public.profile_check_is_current((n->>'user_id')::uuid,'name',(n->>'revision')::uuid,(n->>'claim_token')::uuid),'Revoked consent prevents external disclosure';
 assert public.claim_profile_checks()='[]';
end $$;
reset role;
set role authenticated;
select public.set_profile_check_consent(true);
reset role;
set role service_role;
do $$ declare n jsonb; begin
 n:=public.claim_profile_checks('00000000-0000-0000-0000-000000000001')->0;
 perform set_config('test.restricted_job',n::text,false);
 perform public.moderate_user((n->>'user_id')::uuid,'restrict','Test restriction');
 assert not public.profile_check_is_current((n->>'user_id')::uuid,'name',(n->>'revision')::uuid,(n->>'claim_token')::uuid),'Restriction prevents external disclosure';
 assert public.finish_profile_check((n->>'user_id')::uuid,'name',(n->>'revision')::uuid,(n->>'claim_token')::uuid,'approve')->>'applied'='false','Restriction wins over automatic approval';
end $$;
reset role;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002"}';
do $$ begin assert public.list_friends()='[]'; assert (select count(*) from storage.objects)=0; end $$;
reset role;
delete from auth.users where id='00000000-0000-0000-0000-000000000001';
do $$ begin assert not exists(select 1 from wn_private.profile_check_jobs where user_id='00000000-0000-0000-0000-000000000001'); end $$;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
do $$ begin
 begin perform public.authorize_profile_check(); raise exception 'Deleted session authorized checks'; exception when invalid_authorization_specification then null; end;
end $$;
rollback;
\echo 'PASS: automatic checks require consent, protect owner/friend isolation, reject stale results, retry safely, honor revocation/restriction, and cascade on deletion.'
