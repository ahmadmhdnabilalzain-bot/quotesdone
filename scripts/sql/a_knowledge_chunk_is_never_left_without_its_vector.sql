-- A KNOWLEDGE CHUNK IS NEVER LEFT WITHOUT ITS VECTOR.
--
-- Seat: customer_support (owner of the knowledge base). 3 Nov 2026.
--
-- THE GAP (measured on production 2 Nov 2026 22:59 UTC):
--   * the only scheduler of the kb_chunks embedder is pg_cron 580 'kb_embed_daily' ('20 2 * * *'), one
--     fn_kb_embed_tick a day: HARVEST the pg_net responses of the previous tick, then DISPATCH up to 400 NULL rows.
--     No edge function calls the tick (resilience_ping's kbEmbedTick was removed; the 26 Oct header that says it
--     runs every 15 minutes is out of date), and scripts/kb/run_embed_backfill.mjs runs only by hand.
--   * pg_net keeps a response 6 hours (pg_net.ttl = '6 hours'; the oldest response held was 6 h 04 min old).
--   * so a request sent at 02:20 is looked for at 02:20 the next day, 18 hours after its answer was deleted. The
--     harvest finds nothing, the one-hour release frees the row, and the same tick sends it again: every row that
--     goes NULL by any path other than a dispatch in the six hours before 02:20 is sent once a day and never filled.
--   * the last 7 runs (27 Oct to 2 Nov) each harvested 0 and queued 0, because 0 rows were NULL: the loop was never
--     exercised, so nothing showed it. 5 rows are NULL now (177478, 177480, 177482, 177483, 177484), re-NULLed and
--     dispatched at 21:12 by the_corporate_kit_chunks_give_the_public_numbers_and_never_the_founders_mobile.sql;
--     their answers (pg_net 606-610, HTTP 200, 384-d) expire about 03:12, after the 02:20 run, so those five are
--     the lucky case, not the rule.
--   * the harvest also wrote a vector to any row still NULL, whatever its text had become since it was sent.
--
-- CHANGE (the same machinery, fixed in place: no second copy of the kb_chunks embedder):
--   1. kb_embed_inflight gains text_md5 (what was sent), failed_at and status_code. A row with failed_at is one
--      spent attempt, kept so the retries can be counted; every other row is a request still in flight.
--   2. fn_kb_embed_harvest: a vector is written only to a row still NULL whose text still has the md5 that was sent,
--      and only one the gateway returned as a 384-element array (anything else no longer aborts the whole tick on
--      a cast). An answer without a vector, or no answer within an hour, is a failed attempt. Answered requests
--      leave the table and release the row's claim lease, so a row still NULL is sent again by the same tick; the
--      attempts of a row that now has its vector (or is gone) are cleared.
--   3. fn_kb_embed_dispatch: never sends a row that already has a request in flight, and stops after 5 failed
--      attempts for the same text (a changed text gets 5 fresh attempts). It reports how many rows it gave up on.
--      Same text window (title + newline + content, first 1,200 characters), same free in-region path
--      (ai_gateway {action:'embed'}, gte-small, not OpenRouter), same tiers, same in-flight ceiling.
--   4. pg_cron 'kb_embed' every 10 minutes replaces 'kb_embed_daily': each harvest now finds answers at most
--      ~10 minutes old, far inside the 6-hour TTL. With no NULL row a tick reads two partial indexes and sends nothing.
--   5. fn_kb_embed_scheduled_run beats duty:kb_embed only when the dispatch answered ok (unchanged), and then only
--      when the tick did work or no beat is younger than 20 hours, so an idle day writes one agent_runs row, not 144,
--      and fn_it_workflow_heartbeats' 36-hour window still sees it.
--   6. cron_registry and writer_seat: 'kb_embed_daily' rows removed, 'kb_embed' rows owned by customer_support.
-- The four routines already exist: CREATE OR REPLACE keeps their ACL (EXECUTE revoked from public, anon,
-- authenticated); the verdict re-reads it. search_path pinned on each. No begin/commit: the applier runs the file as
-- one transaction. Ends with a verdict row.
--   node scripts/apply_sql.mjs scripts/sql/a_knowledge_chunk_is_never_left_without_its_vector.sql --apply --ddl --seat customer_support
-- prevented by: scripts/sql/a_knowledge_chunk_is_never_left_without_its_vector_probe.sql,
--               scripts/checks/a_knowledge_chunk_is_never_left_without_its_vector.test.mjs

alter table public.kb_embed_inflight
  add column if not exists text_md5    text,
  add column if not exists failed_at   timestamptz,
  add column if not exists status_code integer;

create or replace function public.fn_kb_embed_harvest()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $fn$
declare
  v_written int := 0;
  v_failed  int := 0;
  v_expired int := 0;
begin
  with answered as (
    select f.request_id, f.chunk_id, f.text_md5, r.status_code,
           -- the vector, only if the gateway really returned one; checked left to right so no cast can raise
           case when r.status_code = 200
                 and pg_input_is_valid(r.content, 'jsonb')
                 and jsonb_typeof(r.content::jsonb -> 'embedding') = 'string'
                 and pg_input_is_valid(r.content::jsonb ->> 'embedding', 'jsonb')
                 and jsonb_typeof((r.content::jsonb ->> 'embedding')::jsonb) = 'array'
                 and jsonb_array_length((r.content::jsonb ->> 'embedding')::jsonb) = 384
                then r.content::jsonb ->> 'embedding' end as vec
      from public.kb_embed_inflight f
      join net._http_response r on r.id = f.request_id
     where f.failed_at is null
  ), wrote as (
    -- only a row still NULL whose text is still what was sent
    update public.kb_chunks k
       set embedding_gte = a.vec::vector, embed_claimed_at = null
      from answered a
     where a.vec is not null and k.id = a.chunk_id and k.embedding_gte is null
       and md5(left(coalesce(k.title, '') || E'\n' || coalesce(k.content, ''), 1200)) = a.text_md5
    returning k.id
  ), failed as (
    update public.kb_embed_inflight f
       set failed_at = now(), status_code = a.status_code
      from answered a
     where f.request_id = a.request_id and a.vec is null
    returning f.chunk_id
  ), settled as (
    -- written, or its text changed after it was sent, or another path embedded the row: forgotten either way
    delete from public.kb_embed_inflight f
     using answered a
     where f.request_id = a.request_id and a.vec is not null
    returning f.chunk_id
  ), released as (
    -- an answered request holds no lease: a row that is still NULL can be sent again by the dispatch that follows
    update public.kb_chunks k
       set embed_claimed_at = null
     where k.id in (select chunk_id from failed union select chunk_id from settled)
       and k.id not in (select id from wrote)
       and k.embedding_gte is null
    returning k.id
  )
  select (select count(*) from wrote), (select count(*) from failed) into v_written, v_failed;

  -- No answer within an hour: a failed attempt, and the row is free to be sent again.
  with stale as (
    update public.kb_embed_inflight
       set failed_at = now()
     where failed_at is null and queued_at < now() - interval '1 hour'
    returning chunk_id
  )
  update public.kb_chunks k set embed_claimed_at = null
    from stale s where k.id = s.chunk_id and k.embedding_gte is null;
  get diagnostics v_expired = row_count;

  -- The attempts of a row that has its vector, or no longer exists, are history nobody needs.
  delete from public.kb_embed_inflight f
   where f.failed_at is not null
     and not exists (select 1 from public.kb_chunks k where k.id = f.chunk_id and k.embedding_gte is null);

  return jsonb_build_object('ok', true, 'embedded', v_written, 'failed', v_failed,
                            'expired_and_released', v_expired,
                            'still_inflight', (select count(*) from public.kb_embed_inflight where failed_at is null),
                            'at', now());
end
$fn$;

create or replace function public.fn_kb_embed_dispatch(p_limit integer default 200, p_max_tier integer default 4)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $fn$
declare
  v_lim      int := greatest(1, least(coalesce(p_limit, 200), 1000));
  v_url      text;
  v_secret   text;
  v_queued   int := 0;
  v_cap      constant int := 150;   -- the in-flight ceiling, not the normal bound
  v_tries    constant int := 5;     -- failed attempts allowed per text before a row is given up on
  v_inflight int;
  v_gave_up  bigint;
begin
  select 'https://' || value || '.supabase.co/functions/v1/ai_gateway' into v_url
    from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_fn_ai';
  if v_url is null or coalesce(v_secret, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_project_ref_or_cred_fn_ai');
  end if;

  -- Rows that spent every attempt on their current text. Counted, never sent again until the text changes.
  select count(*) into v_gave_up from (
    select f.chunk_id
      from public.kb_embed_inflight f
      join public.kb_chunks k on k.id = f.chunk_id and k.embedding_gte is null
     where f.failed_at is not null
       and f.text_md5 = md5(left(coalesce(k.title, '') || E'\n' || coalesce(k.content, ''), 1200))
     group by f.chunk_id having count(*) >= v_tries) g;

  -- CONCURRENCY CAP. Three minutes, matching the claim lease below.
  select count(*) into v_inflight from public.kb_embed_inflight i
   where i.failed_at is null and i.queued_at > now() - interval '3 minutes';
  v_lim := least(v_lim, greatest(0, v_cap - v_inflight));
  if v_lim = 0 then
    return jsonb_build_object('ok', true, 'queued', 0, 'inflight', v_inflight, 'cap', v_cap, 'gave_up', v_gave_up,
      'held', 'the gateway already has the in-flight ceiling of embed requests; nothing was claimed', 'at', now());
  end if;

  -- The claim: FOR UPDATE SKIP LOCKED and a three-minute lease in embed_claimed_at, so concurrent dispatches take
  -- disjoint slices. A row with a request still in flight is not sent twice.
  with pick as (
    select k.id, left(coalesce(k.title, '') || E'\n' || coalesce(k.content, ''), 1200) as txt
      from public.kb_chunks k
      left join public.kb_embed_priority p on p.category = k.category
     where k.embedding_gte is null
       and (k.embed_claimed_at is null or k.embed_claimed_at < now() - interval '3 minutes')
       and coalesce(p.tier, 3) <= greatest(1, least(coalesce(p_max_tier, 4), 4))
       and not exists (select 1 from public.kb_embed_inflight f where f.chunk_id = k.id and f.failed_at is null)
       and (select count(*) from public.kb_embed_inflight f
             where f.chunk_id = k.id and f.failed_at is not null
               and f.text_md5 = md5(left(coalesce(k.title, '') || E'\n' || coalesce(k.content, ''), 1200))) < v_tries
     order by coalesce(p.tier, 3) asc, k.created_at asc
     limit v_lim
     for update of k skip locked
  ), claimed as (
    update public.kb_chunks k set embed_claimed_at = now()
      from pick where k.id = pick.id
    returning k.id, pick.txt
  ), sent as (
    select c.id, md5(c.txt) as text_md5,
           net.http_post(
             url := v_url,
             headers := '{"Content-Type":"application/json"}'::jsonb,
             -- 1,200 characters is the window every existing kb_chunks vector was built from.
             body := jsonb_build_object('__secret', v_secret, 'fn', 'kb_embed_dispatch', 'action', 'embed', 'text', c.txt),
             timeout_milliseconds := 25000) as request_id
      from claimed c
  )
  insert into public.kb_embed_inflight (request_id, chunk_id, text_md5)
  select s.request_id, s.id, s.text_md5 from sent s
  on conflict (request_id) do nothing;
  get diagnostics v_queued = row_count;

  return jsonb_build_object('ok', true, 'queued', v_queued, 'inflight_before', v_inflight, 'cap', v_cap,
                            'gave_up', v_gave_up, 'max_tier', p_max_tier, 'at', now());
end
$fn$;

create or replace function public.fn_kb_embed_scheduled_run()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_t jsonb; v_work boolean;
begin
  v_t := public.fn_kb_embed_tick(400);
  v_work := coalesce((v_t->'harvest'->>'embedded')::int, 0) + coalesce((v_t->'harvest'->>'failed')::int, 0)
          + coalesce((v_t->'harvest'->>'expired_and_released')::int, 0) + coalesce((v_t->'dispatch'->>'queued')::int, 0) > 0;
  -- A refused dispatch (missing secret) must not beat; an idle tick beats at most once in 20 hours.
  if coalesce((v_t->'dispatch'->>'ok')::boolean, false)
     and (v_work or coalesce((select max(started_at) from public.agent_runs
                               where agent = 'it_engineer' and counts->>'job' = 'duty:kb_embed'), '-infinity') < now() - interval '20 hours') then
    perform public.fn_it_duty_ran('kb_embed', jsonb_build_object('scheduler', 'pg_cron kb_embed', 'tick', v_t));
  end if;
  return v_t;
end $fn$;

-- 4 and 6. Every 10 minutes, in place of once a day.
select cron.unschedule(jobid) from cron.job where jobname = 'kb_embed_daily';
select cron.schedule('kb_embed', '*/10 * * * *',
  $CRON$set statement_timeout = '120s'; select public.fn_kb_embed_scheduled_run();$CRON$);

delete from public.cron_registry where jobname = 'kb_embed_daily';
delete from public.writer_seat where kind = 'cron_job' and name = 'kb_embed_daily';
insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('kb_embed', 'a knowledge chunk is never left without its vector', 'knowledge',
   'Every 10 minutes: harvests the gte-small vectors of the kb_chunks rows sent last tick (pg_net keeps answers 6 hours), '
   || 'then sends every kb_chunks row whose embedding_gte is NULL through ai_gateway embed, the free in-region path, '
   || 'up to 5 attempts per text. Beats duty:kb_embed when it worked, and at least once in 20 hours. With no NULL row it sends nothing.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'kb_embed', 'customer_support',
   'Every 10 minutes: fn_kb_embed_scheduled_run() harvests and sends the gte-small embeds of kb_chunks rows with no vector.',
   'scripts/sql/a_knowledge_chunk_is_never_left_without_its_vector.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

-- verdict
select case when
       (select count(*) from cron.job where jobname = 'kb_embed' and active and schedule = '*/10 * * * *') = 1
   and not exists (select 1 from cron.job where jobname = 'kb_embed_daily')
   and (select count(*) from public.cron_registry where jobname = 'kb_embed') = 1
   and not exists (select 1 from public.cron_registry where jobname = 'kb_embed_daily')
   and (select count(*) from public.writer_seat where kind = 'cron_job' and name = 'kb_embed' and owner_seat = 'customer_support') = 1
   and (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'kb_embed_inflight'
          and column_name in ('text_md5', 'failed_at', 'status_code')) = 3
   and (select setting::interval from pg_settings where name = 'pg_net.ttl') > interval '30 minutes'
   and not exists (select 1 from unnest(array['public.fn_kb_embed_harvest()', 'public.fn_kb_embed_dispatch(integer,integer)',
                                              'public.fn_kb_embed_scheduled_run()', 'public.fn_kb_embed_tick(integer)']) s(sig)
                    where has_function_privilege('anon', s.sig, 'execute') or has_function_privilege('authenticated', s.sig, 'execute')
                       or not exists (select 1 from pg_proc where oid = s.sig::regprocedure and proconfig::text like '%search_path=public%'))
  then 'PROBE OK' else 'PROBE FAILED: the job, its registration, the inflight columns, the TTL, or the routines'' grants and search_path' end as verdict;
