\set ON_ERROR_STOP on
begin;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
do $$ declare a uuid:='00000000-0000-0000-0000-000000000001'; d uuid:='20000000-0000-0000-0000-000000000001'; r jsonb;
begin
 perform public.update_my_profile('Explorer','globe',false);
 r:=public.sync_journal(a,d,'[{"country_id":"MA","field":"saved","sequence":1,"saved":true},{"country_id":"MA","field":"note","sequence":2,"note":"Try a local music venue"},{"country_id":"FR","field":"explored","sequence":3,"first_explored_at":1790000000,"last_explored_at":1790000010}]');
 assert jsonb_array_length(r->'entries')=2,'Saved and unsaved explored countries sync';
 assert (select note from public.wn_journal where country_id='MA')='Try a local music venue','Owner reads private notes';
 assert (select saved from public.wn_journal where country_id='MA'),'Bookmark persisted';
 assert (select count(*) from public.wn_explorations)=0,'Sharing off does not publish private history';
 assert public.export_my_data()->'journal' @> '[{"country_id":"MA","note":"Try a local music venue"}]','Export includes private journal';
 perform public.sync_journal(a,'20000000-0000-0000-0000-000000000002','[{"country_id":"MA","field":"note","sequence":1,"note":"Edited on the second device"}]');
 perform public.sync_journal(a,d,'[{"country_id":"MA","field":"note","sequence":2,"note":"Try a local music venue"}]');
 assert (select note from public.wn_journal where country_id='MA')='Edited on the second device','Lost-response replay cannot overwrite a newer edit from another device';
 perform public.sync_journal(a,d,'[{"country_id":"MA","field":"saved","sequence":4,"saved":false}]');
 assert not (select saved from public.wn_journal where country_id='MA'),'Unsave is synchronized';
 assert (select note from public.wn_journal where country_id='MA')='Edited on the second device','Unsave keeps private note';
 perform public.sync_journal(a,d,'[{"country_id":"MA","field":"note","sequence":5,"note":""}]');
 assert (select note from public.wn_journal where country_id='MA')='','Empty note removes content';
 begin perform public.sync_journal('00000000-0000-0000-0000-000000000002',d,'[]'); raise exception 'wrong owner accepted'; exception when insufficient_privilege then null; end;
 begin perform public.sync_journal(a,d,'[{"country_id":"XX","field":"saved","sequence":6,"saved":true}]'); raise exception 'invalid country accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.sync_journal(a,d,jsonb_build_array(jsonb_build_object('country_id','MA','field','note','sequence',6,'note',repeat('a',4001)))); raise exception 'oversized note accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.sync_journal(a,d,'[{"country_id":"MA","field":"saved","sequence":6,"saved":"true"}]'); raise exception 'invalid boolean accepted'; exception when invalid_parameter_value then null; end;
 begin insert into public.wn_journal(user_id,country_id) values(a,'JP'); raise exception 'direct write accepted'; exception when insufficient_privilege then null; end;
 begin perform wn_private.journal_entries(a); raise exception 'private helper exposed'; exception when insufficient_privilege then null; end;
 begin perform 1 from wn_private.journal_clocks; raise exception 'clocks exposed'; exception when insufficient_privilege then null; end;
 perform public.update_my_profile('Explorer','globe',true);
 perform public.sync_journal(a,d,'[]');
 assert (select count(*) from public.wn_explorations)=1,'Only explored destinations enter the social projection';
 perform set_config('test.journal_invite',public.create_invite()->>'token',false);
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002"}';
do $$ begin
 perform public.update_my_profile('Explorer','sun',true);
 assert (select count(*) from public.wn_journal)=0,'Stranger cannot read journal';
 perform public.accept_invite(current_setting('test.journal_invite'));
 assert (select count(*) from public.wn_journal)=0,'Even friends cannot read notes or bookmarks';
 assert public.list_friends()->0->'country_ids' @> '["FR"]','Friends can see shared exploration';
 assert not (public.list_friends()->0 ? 'note'),'Friend RPC does not leak notes';
 assert not (public.list_friends()->0 ? 'saved'),'Friend RPC does not leak bookmarks';
 assert jsonb_array_length(public.sync_journal('00000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','[]')->'entries')=0,'Empty second account cannot pull another journal';
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
do $$ begin
 perform public.update_my_profile('Explorer','globe',false);
 assert (select count(*) from public.wn_explorations)=0,'Opt-out removes shared projection';
 assert (select count(*) from public.wn_journal)=2,'Opt-out preserves private journal';
end $$;
reset role;
update public.wn_profiles set deleting_at=now() where id='00000000-0000-0000-0000-000000000001';
set role authenticated;
do $$ begin
 assert (select count(*) from public.wn_journal)=0,'Deletion quarantine denies journal reads';
 begin perform public.sync_journal('00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','[]'); raise exception 'deleting account synced'; exception when insufficient_privilege then null; end;
end $$;
reset role;
delete from auth.users where id='00000000-0000-0000-0000-000000000001';
do $$ begin
 assert (select count(*) from public.wn_journal)=0,'Account deletion cascades journal';
 assert (select count(*) from wn_private.journal_clocks)=0,'Account deletion cascades retry clocks';
end $$;
set role authenticated;
do $$ begin
 begin perform public.sync_journal('00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','[]'); raise exception 'stale session accepted'; exception when invalid_authorization_specification then null; end;
end $$;
reset role;
set role anon;
do $$ begin
 begin perform public.sync_journal('00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','[]'); raise exception 'anonymous sync accepted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
\echo 'Journal privacy, retry, export, sharing and deletion checks passed'
