-- Install explicitly after configuring the worker and Vault. The cron job contains no credentials.
do $$
begin
  if not exists(select from vault.decrypted_secrets where name='quiz_worker_url' and
    decrypted_secret ~ '^https://[a-z0-9]+\.supabase\.co/functions/v1/quiz-reminders$')
    or not exists(select from vault.decrypted_secrets where name='quiz_worker_secret' and length(decrypted_secret)>=32)
    then raise exception 'Configure the quiz worker URL and secret in Vault'; end if;
end $$;
select cron.schedule('worldniche-quiz-reminders','* * * * *',$job$
  select net.http_post(url:=u.decrypted_secret,headers:=jsonb_build_object('x-quiz-worker',s.decrypted_secret),
    body:='{}'::jsonb,timeout_milliseconds:=60000)
  from vault.decrypted_secrets u,vault.decrypted_secrets s
  where u.name='quiz_worker_url' and s.name='quiz_worker_secret'
    and u.decrypted_secret ~ '^https://[a-z0-9]+\.supabase\.co/functions/v1/quiz-reminders$'
    and exists(select from wn_private.quiz_devices where next_due<=now());
$job$);
