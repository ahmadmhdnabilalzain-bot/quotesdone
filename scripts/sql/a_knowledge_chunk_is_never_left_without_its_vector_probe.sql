-- PROBE: A KNOWLEDGE CHUNK IS NEVER LEFT WITHOUT ITS VECTOR.
--
-- Assigned: customer_support. 3 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_knowledge_chunk_is_never_left_without_its_vector.sql (apply-on-merge runs both in one rolled-back transaction, then the
-- probe alone after the apply). It always raises, so every write below is rolled back: the four vectors it clears, the
-- requests it queues (pg_net sends only committed requests, so nothing reaches the gateway), the attempts and the
-- responses it fakes. The five real NULL rows (177478, 177480, 177482, 177483, 177484) and their requests are restored
-- by the same rollback.
--
-- PROBE OK only if
--   1. four rows whose vectors are cleared are sent by one tick (t1, t2, t4) or held (t3, which already spent 5
--      attempts on its current text), each sent one with the md5 of its first 1,200 characters of title + newline + content;
--   2. a 200 response carrying a 384-element vector fills its row with exactly that vector;
--   3. a 200 response for a row whose text changed after it was sent does NOT fill it, and the row is sent again;
--   4. a 500 response is a failed attempt (failed_at, status 500) and the row is sent again; t3 is never sent and is
--      counted as given up;
--   5. after the second tick every NULL row is either in flight or given up;
--   6. the job runs every 10 minutes, the daily job is gone, pg_net keeps answers longer than 30 minutes, and anon /
--      authenticated can neither run the routines nor read the table.
do $probe$
declare
  t1 bigint; t2 bigint; t3 bigint; t4 bigint; v1 text;
  r1 jsonb; r2 jsonb; q1 bigint; q2 bigint; q4 bigint; m1 text; m3 text; fails text := '';
begin
  select k.id, k.embedding_gte::text into t1, v1
    from public.kb_chunks k left join public.kb_embed_priority p on p.category = k.category
   where k.embedding_gte is not null and coalesce(p.tier, 3) <= 4 order by k.id limit 1;
  select k.id into t2 from public.kb_chunks k left join public.kb_embed_priority p on p.category = k.category
   where k.embedding_gte is not null and coalesce(p.tier, 3) <= 4 and k.id > t1 order by k.id limit 1;
  select k.id into t3 from public.kb_chunks k left join public.kb_embed_priority p on p.category = k.category
   where k.embedding_gte is not null and coalesce(p.tier, 3) <= 4 and k.id > t2 order by k.id limit 1;
  select k.id into t4 from public.kb_chunks k left join public.kb_embed_priority p on p.category = k.category
   where k.embedding_gte is not null and coalesce(p.tier, 3) <= 4 and k.id > t3 order by k.id limit 1;
  update public.kb_chunks set embedding_gte = null where id in (t1, t2, t3, t4);

  -- t3 has already spent its five attempts on its current text
  select md5(left(coalesce(title, '') || E'\n' || coalesce(content, ''), 1200)) into m3 from public.kb_chunks where id = t3;
  insert into public.kb_embed_inflight (request_id, chunk_id, text_md5, queued_at, failed_at, status_code)
  select -1000 - g, t3, m3, now() - interval '2 hours', now() - interval '1 hour', 500 from generate_series(1, 5) g;

  r1 := public.fn_kb_embed_dispatch(400, 4);
  select request_id, text_md5 into q1, m1 from public.kb_embed_inflight where chunk_id = t1 and failed_at is null;
  select request_id into q2 from public.kb_embed_inflight where chunk_id = t2 and failed_at is null;
  select request_id into q4 from public.kb_embed_inflight where chunk_id = t4 and failed_at is null;
  if q1 is null or q2 is null or q4 is null then fails := fails || ' 1:not_sent(' || coalesce(r1::text, 'null') || ')'; end if;
  if m1 is distinct from (select md5(left(coalesce(title, '') || E'\n' || coalesce(content, ''), 1200)) from public.kb_chunks where id = t1) then
    fails := fails || ' 1:md5'; end if;
  if exists (select 1 from public.kb_embed_inflight where chunk_id = t3 and failed_at is null) then fails := fails || ' 1:spent_row_sent'; end if;

  -- the gateway's answers, faked: t1 and t2 get a vector (t2's text "changed" after it was sent), t4 a 500
  insert into net._http_response (id, status_code, content, created)
  values (q1, 200, jsonb_build_object('ok', true, 'embedding', v1)::text, now()),
         (q2, 200, jsonb_build_object('ok', true, 'embedding', v1)::text, now()),
         (q4, 500, '<html>upstream error</html>', now());
  update public.kb_embed_inflight set text_md5 = 'edited after it was sent' where request_id = q2;

  r2 := public.fn_kb_embed_tick(400);
  if (select embedding_gte::text from public.kb_chunks where id = t1) is distinct from v1
     or (select vector_dims(embedding_gte) from public.kb_chunks where id = t1) is distinct from 384 then
    fails := fails || ' 2:not_filled(' || coalesce(r2::text, 'null') || ')'; end if;
  if exists (select 1 from public.kb_embed_inflight where chunk_id = t1) then fails := fails || ' 2:history_not_cleared'; end if;
  if (select embedding_gte from public.kb_chunks where id = t2) is not null then fails := fails || ' 3:stale_vector_written'; end if;
  if not exists (select 1 from public.kb_embed_inflight where chunk_id = t2 and failed_at is null and request_id <> q2) then
    fails := fails || ' 3:not_resent'; end if;
  if not exists (select 1 from public.kb_embed_inflight where request_id = q4 and failed_at is not null and status_code = 500) then
    fails := fails || ' 4:failure_not_counted'; end if;
  if not exists (select 1 from public.kb_embed_inflight where chunk_id = t4 and failed_at is null and request_id <> q4) then
    fails := fails || ' 4:failure_not_retried'; end if;
  if exists (select 1 from public.kb_embed_inflight where chunk_id = t3 and failed_at is null)
     or coalesce((r2 -> 'dispatch' ->> 'gave_up')::int, 0) < 1 then
    fails := fails || ' 4:spent_row_not_held(' || coalesce(r2 -> 'dispatch' ->> 'gave_up', 'null') || ')'; end if;
  if exists (select 1 from public.kb_chunks k where k.embedding_gte is null and k.id <> t3
               and not exists (select 1 from public.kb_embed_inflight f where f.chunk_id = k.id and f.failed_at is null)) then
    fails := fails || ' 5:null_row_unsent'; end if;
  if (select count(*) from cron.job where jobname = 'kb_embed' and active and schedule = '*/10 * * * *') <> 1
     or exists (select 1 from cron.job where jobname = 'kb_embed_daily')
     or (select setting::interval from pg_settings where name = 'pg_net.ttl') <= interval '30 minutes'
     or has_function_privilege('anon', 'public.fn_kb_embed_scheduled_run()', 'execute')
     or has_function_privilege('authenticated', 'public.fn_kb_embed_harvest()', 'execute')
     or has_function_privilege('anon', 'public.fn_kb_embed_dispatch(integer,integer)', 'execute')
     or has_table_privilege('anon', 'public.kb_embed_inflight', 'select')
     or has_table_privilege('authenticated', 'public.kb_embed_inflight', 'select') then
    fails := fails || ' 6:job_ttl_or_grants'; end if;

  raise exception 'CHK<<%>>', case when fails = ''
    then 'PROBE OK rows=' || t1 || ',' || t2 || ',' || t3 || ',' || t4 || ' first_dispatch=' || (r1 ->> 'queued')
         || ' queued, second_tick embedded=' || (r2 -> 'harvest' ->> 'embedded') || ' failed=' || (r2 -> 'harvest' ->> 'failed')
         || ' requeued=' || (r2 -> 'dispatch' ->> 'queued') || ' gave_up=' || (r2 -> 'dispatch' ->> 'gave_up')
    else 'PROBE FAILED:' || fails end;
end $probe$;
