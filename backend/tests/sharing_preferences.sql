\set ON_ERROR_STOP on
begin;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
do $$ begin
 assert public.get_my_profile() is null;
 assert public.update_my_profile('Explorer','globe',true)->>'share_exploration'='true','A new profile honors the visible signup sharing choice';
 assert public.get_my_profile()->>'automatic_profile_checks_enabled'='false','Exploration sharing is separate from AI moderation consent';
 assert public.sync_explorations(array['MA','FR'])->>'count'='2';
 perform set_config('test.sharing_invite',public.create_invite()->>'token',false);
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002"}';
do $$ begin
 assert public.get_my_profile() is null;
 assert public.update_my_profile('Explorer','sun',false)->>'share_exploration'='false','A new profile can turn sharing off before saving';
 assert public.sync_explorations(array['JP'])->>'count'='0';
 assert (select count(*) from public.wn_explorations)=0,'Strangers cannot read a sharing-enabled profile';
 perform public.accept_invite(current_setting('test.sharing_invite'));
 assert public.list_friends()->0->>'share_exploration'='true';
 assert public.list_friends()->0->>'explored_count'='2';
 assert (select count(*) from public.wn_explorations)=2,'Only accepted friends can read shared country IDs';
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000003","session_id":"10000000-0000-0000-0000-000000000003"}';
do $$ begin
 assert (select count(*) from public.wn_explorations)=0,'A third account cannot read shared countries';
 assert jsonb_array_length(public.list_friends())=0;
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
do $$ begin
 assert public.update_my_profile('Explorer','globe',false)->>'share_exploration'='false';
 assert public.get_my_profile()->>'share_exploration'='false','Reading an existing profile preserves its opt-out';
 assert public.update_my_profile('Explorer','moon',false)->>'share_exploration'='false','A later profile edit preserves the submitted existing choice';
 assert public.sync_explorations(array['JP'])->>'count'='0';
 assert (select count(*) from public.wn_explorations)=0,'Opt-out deletes cloud exploration rows and prevents reupload';
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002"}';
do $$ begin
 assert public.list_friends()->0->>'share_exploration'='false';
 assert public.list_friends()->0->>'explored_count'='0';
 assert public.list_friends()->0->'country_ids'='[]'::jsonb;
 assert (select count(*) from public.wn_explorations)=0,'Friends immediately lose exploration access after opt-out';
end $$;
reset role;
do $$ begin
 assert (select count(*) from public.wn_explorations)=0,'Opt-out removes data rather than only hiding it';
end $$;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
do $$ begin
 perform public.update_my_profile('Explorer','globe',true);
 assert (select count(*) from public.wn_explorations)=0,'Re-enabling does not restore deleted cloud history on its own';
 assert public.sync_explorations(array['MA'])->>'count'='1';
end $$;
reset role;
rollback;
\echo 'PASS: new-profile sharing choice, existing opt-out preservation, separate AI consent, friend-only access and cloud deletion.'
