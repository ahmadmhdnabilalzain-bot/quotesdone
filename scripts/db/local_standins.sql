-- THE STAND-INS A LOCAL POSTGRES 16 NEEDS BEFORE THE SCHEMA MIRROR LOADS (it_engineer, 13 Nov 2026).
-- Used by scripts/db/local_pg16.mjs (runbook: docs/runbooks/local-database.md). Production is Supabase: roles, the auth,
-- storage, cron, net and vault schemas and their routines come with the platform, and the mirror (supabase/schema/full_schema/)
-- names them without defining them. These are the smallest shapes the mirror and the probes use. Nothing here can reach a
-- person: net.http_post only queues a row, cron.schedule only records a job (local_from_mirror switches each one off), and the
-- vault holds no real secret. Worked out by the independent review of 13 Nov 2026 (808 tables, 2,175 routines, 374 policies,
-- 403 triggers and 110 inactive cron jobs after four passes).
do $$ begin create role anon; exception when others then null; end $$;
do $$ begin create role authenticated; exception when others then null; end $$;
do $$ begin create role service_role; exception when others then null; end $$;
do $$ begin create role authenticator; exception when others then null; end $$;
do $$ begin create role supabase_admin; exception when others then null; end $$;
do $$ begin create role supabase_auth_admin; exception when others then null; end $$;
do $$ begin create role supabase_storage_admin; exception when others then null; end $$;
do $$ begin create role dashboard_user; exception when others then null; end $$;
do $$ begin create role pgbouncer; exception when others then null; end $$;
create schema if not exists extensions; create schema if not exists auth; create schema if not exists storage;
create schema if not exists cron; create schema if not exists net; create schema if not exists vault;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pg_trgm with schema public;
create extension if not exists pg_stat_statements with schema extensions;
create table if not exists auth.users (id uuid primary key default gen_random_uuid(), email text, phone text, raw_user_meta_data jsonb, raw_app_meta_data jsonb, created_at timestamptz default now(), last_sign_in_at timestamptz, email_confirmed_at timestamptz, deleted_at timestamptz, banned_until timestamptz, is_anonymous boolean default false, updated_at timestamptz);
create table if not exists auth.audit_log_entries (id uuid, payload json, created_at timestamptz, ip_address text, instance_id uuid);
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
create or replace function auth.role() returns text language sql stable as $$ select nullif(current_setting('request.jwt.claim.role', true),'') $$;
create or replace function auth.email() returns text language sql stable as $$ select nullif(current_setting('request.jwt.claim.email', true),'') $$;
create or replace function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true),'')::jsonb,'{}') $$;
create table if not exists storage.buckets (id text primary key, name text, public boolean, created_at timestamptz default now(), file_size_limit bigint, allowed_mime_types text[]);
create table if not exists storage.objects (id uuid default gen_random_uuid() primary key, bucket_id text, name text, owner uuid, metadata jsonb, created_at timestamptz default now(), updated_at timestamptz, last_accessed_at timestamptz, path_tokens text[]);
create or replace function storage.foldername(name text) returns text[] language sql immutable as $$ select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1] $$;
create or replace function storage.filename(name text) returns text language sql immutable as $$ select (string_to_array(name,'/'))[array_length(string_to_array(name,'/'),1)] $$;
create or replace function storage.extension(name text) returns text language sql immutable as $$ select reverse(split_part(reverse(name),'.',1)) $$;
create table if not exists cron.job (jobid bigserial primary key, jobname text unique, schedule text, command text, active boolean default true, nodename text, nodeport int, database text, username text);
create table if not exists cron.job_run_details (jobid bigint, runid bigserial, job_pid int, database text, username text, command text, status text, return_message text, start_time timestamptz, end_time timestamptz);
create or replace function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language plpgsql as $f$
declare v bigint; begin insert into cron.job (jobname, schedule, command) values (p_name, p_schedule, p_command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning jobid into v; return v; end $f$;
create or replace function cron.unschedule(p_name text) returns boolean language sql as $$ delete from cron.job where jobname=p_name returning true $$;
create or replace function cron.unschedule(p_id bigint) returns boolean language sql as $$ delete from cron.job where jobid=p_id returning true $$;
create or replace function cron.alter_job(job_id bigint, schedule text default null, command text default null, database text default null, username text default null, active boolean default null) returns void language sql as $$ update cron.job set active=coalesce(alter_job.active, cron.job.active), schedule=coalesce(alter_job.schedule, cron.job.schedule), command=coalesce(alter_job.command, cron.job.command) where jobid=job_id $$;
create table if not exists net._http_response (id bigint, status_code int, content_type text, headers jsonb, content text, timed_out boolean, error_msg text, created timestamptz default now());
create table if not exists net.http_request_queue (id bigserial, method text, url text, headers jsonb, body bytea, timeout_milliseconds int);
create or replace function net.http_post(url text, body jsonb default '{}', params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000) returns bigint language sql as $$ insert into net.http_request_queue(method,url,headers,body) values ('POST',url,headers,convert_to(body::text,'utf8')) returning id $$;
create or replace function net.http_get(url text, params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000) returns bigint language sql as $$ insert into net.http_request_queue(method,url,headers) values ('GET',url,headers) returning id $$;
create table if not exists vault.secrets (id uuid default gen_random_uuid(), name text, secret text, description text, created_at timestamptz default now());
create or replace view vault.decrypted_secrets as select id, name, secret as decrypted_secret, description, created_at from vault.secrets;
create or replace function vault.create_secret(new_secret text, new_name text default null, new_description text default '') returns uuid language sql as $$ insert into vault.secrets(name,secret,description) values (new_name,new_secret,new_description) returning id $$;
-- PGVECTOR, STOOD IN (15 Nov 2026, review 2 of the certificate branch, item 11). A plain Postgres 16 has no pgvector, and the loader
-- writes every vector(N) column as real[] (local_pg16.mjs). A routine that says `p_embedding vector DEFAULT NULL::vector` or orders by
-- `embedding <=> p_embedding` then failed ("type vector does not exist", "operator does not exist: real[] <=> real[]": 13 subtests of
-- a_ready_request alone), and a red local gate is what tempts a session to replay on production. So: a domain `vector` over real[]
-- (a value is written '{0.1,0.2}', not pgvector's '[0.1,0.2]') and the three distance operators as SQL on real[] (cosine <=>,
-- Euclidean <->, negative inner product <#>), with pgvector's meanings; no index method (an hnsw index is simply not built here).
do $$ begin create domain public.vector as real[]; exception when duplicate_object then null; end $$;
create or replace function public.qd_local_cosine_distance(a real[], b real[]) returns double precision language sql immutable as $$
  select 1 - sum(x * y) / nullif(sqrt(sum(x * x)) * sqrt(sum(y * y)), 0) from unnest(a, b) as t(x, y) $$;
create or replace function public.qd_local_l2_distance(a real[], b real[]) returns double precision language sql immutable as $$
  select sqrt(sum((x - y) * (x - y))) from unnest(a, b) as t(x, y) $$;
create or replace function public.qd_local_negative_inner_product(a real[], b real[]) returns double precision language sql immutable as $$
  select -sum(x * y) from unnest(a, b) as t(x, y) $$;
do $$ begin create operator public.<=> (leftarg = real[], rightarg = real[], function = public.qd_local_cosine_distance, commutator = operator(public.<=>));
  exception when duplicate_function or duplicate_object then null; end $$;
do $$ begin create operator public.<-> (leftarg = real[], rightarg = real[], function = public.qd_local_l2_distance, commutator = operator(public.<->));
  exception when duplicate_function or duplicate_object then null; end $$;
do $$ begin create operator public.<#> (leftarg = real[], rightarg = real[], function = public.qd_local_negative_inner_product, commutator = operator(public.<#>));
  exception when duplicate_function or duplicate_object then null; end $$;
-- @@ SEEDS: run AFTER the schema has loaded @@
-- The rows the probes read before they act: a project_ref, a database credential and the key credentials are hashed with (dummy
-- values: the local database holds no secret), and the six seats in org_role and org_agents, so a seat-owned routine finds its seat.
insert into public.app_secrets (key, value) values ('project_ref', 'localpg16localpg16lo'), ('cred_db_internal', 'local-not-a-secret'),
  ('internal_credential_hmac_key', 'local-not-a-secret-either')
  on conflict (key) do nothing;
insert into public.org_role (role_id, display_name, runtime_mode, responsibilities, activation_conditions, authority_level)
select s, initcap(replace(s, '_', ' ')), 'persistent_manager', 'local stand-in for the ' || s || ' seat', 'local database', 'execute_medium'
  from unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing']) s
on conflict (role_id) do nothing;
insert into public.org_agents (agent_key, department, role, title, active, available)
select s, null, s, initcap(replace(s, '_', ' ')), true, true
  from unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing']) s
on conflict (agent_key) do nothing;
-- The four it.finding conversations of the IT seat (scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql), whose 4-hour reply
-- window fn_it_ceo_silence_watch and fn_it_loop_reverify read and raise without (review 2, item 11). The mirror holds the table, not
-- its rows.
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
select 'it.finding', 'it_engineer', s, 'local stand-in: the IT engineer found a fault in something ' || s || ' owns', 'fn_seat_answers_it_finding',
       interval '4 hours', true, 'scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql'
  from unnest(array['sales_engineer','accountant','customer_support','ceo']) s
on conflict (type, from_seat, to_seat) do nothing;
-- The database's own credential (context db.internal), hashed as production hashes it, for the dummy cred_db_internal above, scoped
-- to every edge function in this checkout (local_pg16.mjs passes their names as :fn_names), so a probe that asks "may db.internal
-- call X" finds the row it finds on production. The local database holds no secret: the value is the dummy above.
insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active)
select 'db.internal', 'local stand-in', public.fn_internal_credential_hash('local-not-a-secret'), string_to_array(:'fn_names', ','), false, true
 where not exists (select 1 from public.internal_credential where context = 'db.internal');
