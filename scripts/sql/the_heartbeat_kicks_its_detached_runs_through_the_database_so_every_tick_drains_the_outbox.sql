-- THE HEARTBEAT KICKS ITS DETACHED RUNS THROUGH THE DATABASE, SO EVERY TICK DRAINS THE OUTBOX (it_engineer, 19 Nov 2026).
-- Assigned: it_engineer (resilience_ping's scheduling and the outbox drain).
--
-- MEASURED (production, read-only, 19 Nov 2026 14:00-14:25Z):
--   * Finding duty:heartbeat:outbox, open, seen 380 times: "resilience_ping step outbox failed: Rate limit exceeded for trace
--     01a1f41bbf9d71cf9714c18fb35566f1. Retry after 22830ms." (14:00:59Z). The same trace failed whatsapp, supportVoice and
--     specoffer that tick. The trace id is the tick's own request id (function_logs request_id 01a1f41b-bf9d-71cf-9714-
--     c18fb35566f1, resilience_ping, ap-southeast-1): the edge runtime's limit on function-to-function calls within one request
--     chain (docs: guides/functions/recursive-functions; RATE_LIMIT_EXCEEDED). Not Vercel (the cron's POST is the chain's
--     entry, not a hop) and not an OpenTelemetry exporter (resilience_ping and _shared configure none). Every Retry-After ends ~60 s after the tick began.
--   * What exhausts it is resilience_ping calling ITSELF: kickDetached POSTs /resilience_ping {detached}. function_edge_logs over
--     96 ticks (18 Nov 14:30Z - 19 Nov 14:15Z): ticks with at most 2 self-calls (the :15 and :45 ticks: supportVoice,
--     caseCatchup) drained the outbox 47 of 48 times; ticks with 3 or more (the :00 and :30 ticks also kick marketing and
--     itlater, and itlater's run kicks heldReplay and routineJudgements, two deep) 9 of 48. Call volume did not decide it: the
--     15:45 tick made 135 calls with 2 self-calls and drained. agent_runs fn:send_outbox, 24 h: 24 of 24 :15 ticks, 23 of 24 :45,
--     4 :00, 3 :30. So ordinary mail waited up to 30 minutes (notification 150035: written 13:45:54Z, sent 14:16:02Z).
--
-- CHANGE
--   1. fn_resilience_detached_kick(name): posts {detached: name} to resilience_ping through pg_net, with the db.internal
--      credential in x-qd-internal (resilience_ping's tickCaller -> requireInternal), region pinned. A request pg_net makes
--      enters the platform from outside, so each detached run is its own chain and the tick's chain holds no recursion. It is
--      the path outbox_person_mail_kick already takes to send_outbox. resilience_ping/shared.ts kickDetached calls it.
--   2. NOT SILENT. pg_net answers later, so the routine keeps the last request id per name (resilience_detached_kick) and, on
--      the next kick of that name, reads its answer from net._http_response (kept 6 h, pg_net.ttl): a non-2xx, a timeout, or
--      no answer after 10 minutes makes this kick answer ok:false with the reason, which is the step's finding
--      (duty:heartbeat:<step>, or duty:detached_itlater for the two kicks inside itlater) exactly as a failed self-POST was.
--      A kick that cannot be made (no credential) answers ok:false at once. The run itself still settles duty:detached_<name>.
--   3. db.internal's scope gains resilience_ping (as it gained send_outbox for the person-mail kick).
-- ORDER: APPLY THIS FIRST, THEN DEPLOY resilience_ping. A resilience_ping that calls the routine before it exists kicks nothing
--   (every kick answers ok:false, so it is a finding, but no detached run would start); this file changes nothing the
--   deployed function reads.
-- SEAT: it_engineer. Apply (after review):
--   node scripts/apply_sql.mjs scripts/sql/the_heartbeat_kicks_its_detached_runs_through_the_database_so_every_tick_drains_the_outbox.sql --apply --ddl --seat it_engineer
--   then append the file as the LAST line of scripts/sql/MANIFEST.txt (Edit tool) and delete its note in scripts/sql/pending/.
-- ROLLBACK: redeploy the previous resilience_ping (its kickDetached self-POSTs), then
--   drop function public.fn_resilience_detached_kick(text); drop table public.resilience_detached_kick;
--   update public.internal_credential set scope = array_remove(scope, 'resilience_ping') where context = 'db.internal' and active;
-- Prevented by: resilience_ping/detached_kick_is_not_a_self_call.test.ts, and the probe below.

set local lock_timeout = '1500ms';

update public.internal_credential set scope = scope || array['resilience_ping']
 where context = 'db.internal' and active and not ('resilience_ping' = any (scope));

create table if not exists public.resilience_detached_kick (
  name       text primary key check (name ~ '^[A-Za-z]{1,40}$'),
  request_id bigint not null,
  kicked_at  timestamptz not null default now()
);
comment on table public.resilience_detached_kick is
  'The last pg_net request that kicked each detached resilience_ping run; the next kick reads its answer (it_engineer, 19 Nov 2026).';
alter table public.resilience_detached_kick enable row level security;
drop policy if exists resilience_detached_kick_service_role_only on public.resilience_detached_kick;
create policy resilience_detached_kick_service_role_only on public.resilience_detached_kick
  as permissive for all to public using (false) with check (false);
revoke all on public.resilience_detached_kick from anon, authenticated;

create or replace function public.fn_resilience_detached_kick(p_name text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_prev public.resilience_detached_kick;
  v_status int; v_timed_out boolean; v_err text; v_body text; v_seen boolean := false;
  v_bad text; v_secret text; v_ref text; v_req bigint;
begin
  if p_name is null or p_name !~ '^[A-Za-z]{1,40}$' then
    return jsonb_build_object('ok', false, 'started', false, 'error', 'not a detached run name: ' || coalesce(p_name, '(null)'));
  end if;

  -- the answer to the previous kick of this name: a run that never started is this step's finding, one beat late
  select * into v_prev from public.resilience_detached_kick where name = p_name;
  if found then
    select r.status_code, r.timed_out, r.error_msg, left(r.content, 200), true
      into v_status, v_timed_out, v_err, v_body, v_seen
      from net._http_response r where r.id = v_prev.request_id;
    if coalesce(v_seen, false) then
      if coalesce(v_timed_out, false) or v_status is null or v_status not between 200 and 299 then
        v_bad := 'the detached ' || p_name || ' run kicked at ' || v_prev.kicked_at || ' answered '
                 || coalesce(v_status::text, 'no status') || case when v_timed_out then ' (timed out)' else '' end
                 || coalesce(': ' || nullif(v_err, ''), '') || coalesce(': ' || nullif(v_body, ''), '');
      end if;
    elsif v_prev.kicked_at < now() - interval '10 minutes' and v_prev.kicked_at > now() - interval '5 hours' then
      v_bad := 'the detached ' || p_name || ' run kicked at ' || v_prev.kicked_at || ' has no answer recorded by pg_net';
    end if;
  end if;

  select value into v_secret from public.app_secrets where key = 'cred_db_internal';
  v_ref := public.qd_project_ref();
  if coalesce(v_secret, '') = '' or v_ref is null then
    return jsonb_build_object('ok', false, 'started', false, 'error', 'no db.internal credential or project ref: the detached ' || p_name || ' run was not kicked');
  end if;
  select net.http_post('https://' || v_ref || '.supabase.co/functions/v1/resilience_ping?forceFunctionRegion=ap-southeast-1',
                       jsonb_build_object('detached', p_name), '{}'::jsonb,
                       jsonb_build_object('Content-Type', 'application/json', 'x-qd-internal', v_secret), 15000)
    into v_req;
  insert into public.resilience_detached_kick (name, request_id, kicked_at) values (p_name, v_req, now())
  on conflict (name) do update set request_id = excluded.request_id, kicked_at = excluded.kicked_at;

  return jsonb_build_object('ok', v_bad is null, 'started', true, 'request', v_req)
         || case when v_bad is null then '{}'::jsonb else jsonb_build_object('error', v_bad) end
         || case when v_prev.request_id is null then '{}'::jsonb
                 else jsonb_build_object('previous', jsonb_build_object('request', v_prev.request_id, 'kicked_at', v_prev.kicked_at, 'status', v_status)) end;
end $fn$;

revoke execute on function public.fn_resilience_detached_kick(text) from public, anon, authenticated;
grant execute on function public.fn_resilience_detached_kick(text) to service_role;

-- PROBE: read-only (it does not call the routine, which would post); the file holds DDL, so it returns its verdict as a row.
with f as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.proname = 'fn_resilience_detached_kick' and p.prosecdef
              and p.oid = 'public.fn_resilience_detached_kick(text)'::regprocedure
              and exists (select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%')
              and not has_function_privilege('anon', p.oid, 'execute')
              and not has_function_privilege('authenticated', p.oid, 'execute')
              and has_function_privilege('service_role', p.oid, 'execute')),
     o as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.proname = 'fn_resilience_detached_kick'),
     t as (select count(*) n from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname = 'public' and c.relname = 'resilience_detached_kick' and c.relrowsecurity
              and exists (select 1 from pg_policy pl where pl.polrelid = c.oid)
              and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select')),
     c as (select count(*) n from public.internal_credential where context = 'db.internal' and active and 'resilience_ping' = any (scope)),
     k as (select count(*) n from public.app_secrets where key = 'cred_db_internal' and coalesce(value, '') <> '')
select case when (select n from f) = 1 and (select n from o) = 1 and (select n from t) = 1 and (select n from c) >= 1 and (select n from k) = 1
            then 'PROBE OK: fn_resilience_detached_kick(text) closed to anon/authenticated, open to service_role; table RLS with policy; db.internal may call resilience_ping'
            else 'PROBE FAILED: routine ' || (select n from f) || '/1, overloads ' || (select n from o) || ', table ' || (select n from t)
                 || ', scope ' || (select n from c) || ', credential ' || (select n from k) end as verdict;
