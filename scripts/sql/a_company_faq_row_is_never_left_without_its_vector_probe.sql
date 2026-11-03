-- PROBE: A COMPANY FAQ ROW IS NEVER LEFT WITHOUT ITS VECTOR.
--
-- Assigned: customer_support. 3 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_company_faq_row_is_never_left_without_its_vector.sql (apply-on-merge runs both in one rolled-back transaction, then the
-- probe alone after the apply). It always raises, so every write below is rolled back: the two FAQ vectors it clears, the
-- requests it queues (pg_net sends only committed requests, so nothing reaches the gateway) and the responses it fakes.
--
-- PROBE OK only if
--   1. two rows whose vectors are cleared are both sent by one tick, each with the md5 of question + newline + answer;
--   2. a 200 response carrying a vector fills its row with exactly that vector (384 dimensions);
--   3. a response for a row whose text changed after it was sent does NOT fill it, and the row is sent again;
--   4. after a tick no NULL row is left unsent;
--   5. the job runs every 10 minutes and anon / authenticated can neither run the routine nor read the table.
do $probe$
declare
  t1 bigint; t2 bigint; v1 text; r1 jsonb; r2 jsonb; q1 bigint; q2 bigint; m1 text; m2 text; fails text := '';
begin
  select id, embedding_gte::text into t1, v1 from public.company_faq where embedding_gte is not null order by id limit 1;
  select id into t2 from public.company_faq where embedding_gte is not null and id > t1 order by id limit 1;
  update public.company_faq set embedding_gte = null where id in (t1, t2);

  r1 := public.fn_company_faq_embed_tick(1000);
  select request_id, text_md5 into q1, m1 from public.company_faq_embed_inflight where faq_id = t1;
  select request_id, text_md5 into q2, m2 from public.company_faq_embed_inflight where faq_id = t2;
  if q1 is null or q2 is null then fails := fails || ' 1:not_sent(' || coalesce(r1::text, 'null') || ')'; end if;
  if m1 is distinct from (select md5(coalesce(question, '') || E'\n' || coalesce(answer, '')) from public.company_faq where id = t1) then
    fails := fails || ' 1:md5'; end if;

  -- the gateway's answers, faked; t2's text "changed" after it was sent
  insert into net._http_response (id, status_code, content, created)
  values (q1, 200, jsonb_build_object('embedding', v1::jsonb)::text, now()),
         (q2, 200, jsonb_build_object('embedding', v1::jsonb)::text, now());
  update public.company_faq_embed_inflight set text_md5 = 'edited after it was sent' where request_id = q2;

  r2 := public.fn_company_faq_embed_tick(1000);
  if (select embedding_gte::text from public.company_faq where id = t1) is distinct from v1
     or (select vector_dims(embedding_gte) from public.company_faq where id = t1) is distinct from 384 then
    fails := fails || ' 2:not_filled(' || coalesce(r2::text, 'null') || ')'; end if;
  if (select embedding_gte from public.company_faq where id = t2) is not null then fails := fails || ' 3:stale_vector_written'; end if;
  if not exists (select 1 from public.company_faq_embed_inflight where faq_id = t2 and request_id <> q2) then
    fails := fails || ' 3:not_resent'; end if;
  if exists (select 1 from public.company_faq q where q.embedding_gte is null
               and not exists (select 1 from public.company_faq_embed_inflight f where f.faq_id = q.id)) then
    fails := fails || ' 4:null_row_unsent'; end if;
  if (select count(*) from cron.job where jobname = 'company_faq_embed' and active and schedule = '*/10 * * * *') <> 1
     or has_function_privilege('anon', 'public.fn_company_faq_embed_tick(integer)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_company_faq_embed_tick(integer)', 'execute')
     or has_table_privilege('anon', 'public.company_faq_embed_inflight', 'select')
     or has_table_privilege('authenticated', 'public.company_faq_embed_inflight', 'select') then
    fails := fails || ' 5:job_or_grants'; end if;

  raise exception 'CHK<<%>>', case when fails = ''
    then 'PROBE OK rows=' || t1 || ',' || t2 || ' first_tick=' || (r1 ->> 'queued') || ' queued, second_tick embedded='
         || (r2 ->> 'embedded') || ' still_null=' || (r2 ->> 'still_null')
    else 'PROBE FAILED:' || fails end;
end $probe$;
