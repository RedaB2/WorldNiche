-- Synthetic users and this transaction exist only in the isolated fixture database.
begin;
select set_config('test.day', ((now() at time zone 'UTC')::date)::text,true);
-- Keep CI independent of the release calendar.
insert into wn_private.quiz_schedule(day,id,prompt,answer,options)
select current_setting('test.day')::date,'fixture-today','Fixture question for today?','FR',array['JP','BR','FR','MA']
where not exists(select from wn_private.quiz_schedule where day=current_setting('test.day')::date);
select set_config('test.owner','00000000-0000-0000-0000-000000000001',true);
select set_config('test.peer','00000000-0000-0000-0000-000000000002',true);
set role anon;
do $$ begin
  assert jsonb_array_length(public.today_quiz()->'options')=4;
  assert not has_function_privilege('anon','public.claim_quiz_reminders()','execute');
  assert not has_function_privilege('authenticated','public.claim_quiz_reminders()','execute');
  assert not has_function_privilege('anon','public.submit_quiz(uuid,date,text)','execute');
end $$;
reset role;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
do $$
declare u uuid:=current_setting('test.owner')::uuid; q jsonb:= public.today_quiz(); a jsonb; other text;
begin
  select v into other from jsonb_array_elements_text(q->'options') v where v<>q->>'answer' limit 1;
  a:=public.submit_quiz(u,(q->>'day')::date,other);
  assert a->>'correct'='false';
  assert public.submit_quiz(u,(q->>'day')::date,q->>'answer')=a,'First guess wins across devices';
  begin perform public.submit_quiz(u,(q->>'day')::date-1,other); assert false; exception when raise_exception then null; end;
  begin perform public.submit_quiz(u,(q->>'day')::date,'!!'); assert false; exception when raise_exception then null; end;
  begin perform public.submit_quiz(current_setting('test.peer')::uuid,(q->>'day')::date,other); assert false; exception when raise_exception then null; end;
  assert jsonb_array_length(public.quiz_standings()->'attempts')=1;
  assert public.export_my_data()->'quiz'=public.quiz_standings()->'attempts';
end $$;
reset role;
insert into public.wn_profiles(id,display_name,avatar,share_exploration) values
  (current_setting('test.owner')::uuid,'One','leaf',true),(current_setting('test.peer')::uuid,'Two','leaf',true)
  on conflict(id) do update set share_exploration=true;
insert into public.wn_friendships(user_low,user_high) values(current_setting('test.owner')::uuid,current_setting('test.peer')::uuid)
  on conflict do nothing;
delete from public.wn_blocks where blocker in(current_setting('test.owner')::uuid,current_setting('test.peer')::uuid);
do $$ begin
  assert public.quiz_standings()->'board' @> jsonb_build_array(jsonb_build_object('id',current_setting('test.peer')));
  update public.wn_profiles set share_exploration=false where id=current_setting('test.peer')::uuid;
  assert not (public.quiz_standings()->'board' @> jsonb_build_array(jsonb_build_object('id',current_setting('test.peer'))));
  update public.wn_profiles set share_exploration=true where id=current_setting('test.peer')::uuid;
  insert into public.wn_blocks(blocker,blocked) values(current_setting('test.peer')::uuid,current_setting('test.owner')::uuid);
  assert not (public.quiz_standings()->'board' @> jsonb_build_array(jsonb_build_object('id',current_setting('test.peer'))));
end $$;

-- Choose a test zone currently at 19:xx, so these checks also work after midnight UTC.
select set_config('test.zone',(select name from pg_timezone_names where extract(hour from now() at time zone name)=19 limit 1),true);
select set_config('test.install',gen_random_uuid()::text,true);
select public.set_quiz_reminder(current_setting('test.install')::uuid,repeat('a',64),true,current_setting('test.zone'),true,null,current_setting('test.owner')::uuid);
update wn_private.quiz_devices set next_due=now()-interval '1 minute';
do $$ begin assert public.claim_quiz_reminders()='[]','Completed account skipped across devices'; end $$;
set request.jwt.claims='{}';
set role anon;
select public.set_quiz_reminder(current_setting('test.install')::uuid,repeat('a',64),true,current_setting('test.zone'),true,null,null);
reset role;
update wn_private.quiz_devices set next_due=now()-interval '1 minute';
do $$ declare j jsonb; i uuid:=current_setting('test.install')::uuid; today date:=current_setting('test.day')::date;
begin
  j:=public.claim_quiz_reminders()->0;
  assert j->>'installation'=i::text;
  assert public.quiz_reminder_is_due(i,(j->>'lease')::uuid,today);
  assert not public.quiz_reminder_is_due(i,gen_random_uuid(),today);
  assert public.claim_quiz_reminders()='[]','Active lease prevents duplicate dispatch';
  perform public.finish_quiz_reminder(i,(j->>'lease')::uuid,today,'sent',null);
  update wn_private.quiz_devices set next_due=now();
  assert public.claim_quiz_reminders()='[]','Cannot send a second reminder for the same UTC day';
  perform public.set_quiz_reminder(i,null,true,'UTC',false,null,null);
  assert not public.quiz_reminder_is_due(i,(j->>'lease')::uuid,today);
  assert not exists(select from wn_private.quiz_devices where installation=i),'Opt-out removes token';
end $$;
rollback;
