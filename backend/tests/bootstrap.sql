-- Isolated local PostgreSQL test fixture only. NEVER run against a hosted project.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
create table auth.sessions(id uuid primary key,user_id uuid references auth.users(id) on delete cascade);
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select (auth.jwt()->>'sub')::uuid $$;
grant usage on schema auth to authenticated,anon;
grant execute on function auth.jwt(),auth.uid() to authenticated,anon;
insert into auth.users values
('00000000-0000-0000-0000-000000000001','alice@integration.invalid',now()),
('00000000-0000-0000-0000-000000000002','bob@integration.invalid',now()),
('00000000-0000-0000-0000-000000000003','eve@integration.invalid',now());
insert into auth.sessions values
('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001'),
('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002'),
('10000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000003');
