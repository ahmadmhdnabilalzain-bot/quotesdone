-- A COMPANY FAQ ROW IS NEVER LEFT WITHOUT ITS VECTOR.
--
-- Seat: customer_support
-- Agent: customer_support (owner of the FAQ). 3 Nov 2026.
--
-- THE GAP (measured on production 2 Nov 2026 21:45 UTC): 34 of 638 company_faq rows, all approved, had embedding_gte NULL,
-- 620 and 622 among them (their answers were rewritten by the_live_system_gives_out_the_public_numbers_and_never_the_founders_mobile.sql
-- and trg_company_faq_text_change_clears_embedding cleared the vectors, as designed). Nothing scheduled re-embeds company_faq:
-- the only cron that embeds (580 kb_embed_daily -> fn_kb_embed_scheduled_run) dispatches kb_chunks only, and the one other path is
-- `node scripts/kb/embed_sales_knowledge.mjs --table=company_faq`, which needs a laptop holding SUPABASE_ACCESS_TOKEN. A row with no
-- vector cannot be found by meaning, so the site assistant and WhatsApp miss exactly the answers that were most recently corrected.
--
-- CHANGE: the script's recipe, run by the database itself.
--   1. company_faq_embed_inflight: one row per embed request in flight (request id, FAQ id, md5 of the text it was sent).
--      RLS on, one deny-all policy, nothing for anon or authenticated: service_role only.
--   2. fn_company_faq_embed_tick(p_limit): HARVEST first (a 200 response with an embedding fills embedding_gte only if the row is
--      still NULL AND its text still has the md5 that was sent, so an answer edited mid-flight is never given the old text's
--      vector), then DISPATCH every NULL row not already in flight, through the same free in-region path as the script:
--      ai_gateway {action:'embed'} runs gte-small inside the edge runtime and short-circuits before routing, budget and every
--      model call, so this is not OpenRouter and costs nothing. Same text (question + newline + answer), same 384-d column.
--      A request pg_net never answered is released after 30 minutes and sent again. Never writes a vector it did not get.
--   3. pg_cron company_faq_embed every 10 minutes. With no NULL row it reads one index and sends nothing. pg_net keeps responses
--      6 hours (pg_net.ttl, measured), so a 10-minute harvest always finds them; a daily one would not.
--   4. Registered in cron_registry and writer_seat, owner customer_support.
--   5. One tick now, so the 34 rows are sent at apply and filled by the first scheduled tick (within 10 minutes).
-- SECURITY DEFINER, search_path pinned, EXECUTE revoked from public, anon and authenticated (CREATE grants PUBLIC).
-- No begin/commit: the applier runs the file as one transaction. Ends with a verdict row (PROBE OK or PROBE FAILED).
--   node scripts/apply_sql.mjs scripts/sql/a_company_faq_row_is_never_left_without_its_vector.sql --apply --ddl --seat customer_support
-- prevented by: scripts/sql/a_company_faq_row_is_never_left_without_its_vector_probe.sql,
--               scripts/checks/a_company_faq_row_is_never_left_without_its_vector.test.mjs

create table if not exists public.company_faq_embed_inflight (
  request_id bigint primary key,
  faq_id     bigint not null,
  text_md5   text not null,
  queued_at  timestamptz not null default now()
);
create index if not exists company_faq_embed_inflight_faq_idx on public.company_faq_embed_inflight (faq_id);
alter table public.company_faq_embed_inflight enable row level security;
drop policy if exists company_faq_embed_inflight_service_role_only on public.company_faq_embed_inflight;
create policy company_faq_embed_inflight_service_role_only on public.company_faq_embed_inflight
  as permissive for all to public using (false) with check (false);
revoke all on public.company_faq_embed_inflight from anon, authenticated;

create or replace function public.fn_company_faq_embed_tick(p_limit integer default 100)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $fn$
declare
  v_lim     int := greatest(1, least(coalesce(p_limit, 100), 1000));
  v_url     text;
  v_secret  text;
  v_written int := 0;
  v_failed  int := 0;
  v_stale   int := 0;
  v_queued  int := 0;
begin
  -- HARVEST. Only the row that is still NULL and still says what was sent gets the vector.
  with done as (
    select f.request_id, f.faq_id, f.text_md5, r.status_code, r.content
      from public.company_faq_embed_inflight f
      join net._http_response r on r.id = f.request_id
  ), good as (
    select d.faq_id, d.text_md5, (d.content::jsonb) ->> 'embedding' as vec
      from done d
     where d.status_code = 200 and (d.content::jsonb) ->> 'embedding' is not null
  ), upd as (
    update public.company_faq q
       set embedding_gte = g.vec::vector
      from good g
     where q.id = g.faq_id and q.embedding_gte is null
       and md5(coalesce(q.question, '') || E'\n' || coalesce(q.answer, '')) = g.text_md5
    returning q.id
  ), del as (
    delete from public.company_faq_embed_inflight f using done d where f.request_id = d.request_id
    returning d.status_code
  )
  select (select count(*) from upd), (select count(*) from del where status_code is distinct from 200)
    into v_written, v_failed;

  -- A request pg_net never answered: forget it, so the row is sent again below.
  delete from public.company_faq_embed_inflight where queued_at < now() - interval '30 minutes';
  get diagnostics v_stale = row_count;

  if not exists (select 1 from public.company_faq q where q.embedding_gte is null
                    and not exists (select 1 from public.company_faq_embed_inflight f where f.faq_id = q.id)) then
    return jsonb_build_object('ok', true, 'embedded', v_written, 'failed', v_failed, 'released', v_stale, 'queued', 0,
                              'still_null', (select count(*) from public.company_faq where embedding_gte is null), 'at', now());
  end if;

  select 'https://' || value || '.supabase.co/functions/v1/ai_gateway' into v_url from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_fn_ai';
  if v_url is null or coalesce(v_secret, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_project_ref_or_cred_fn_ai', 'embedded', v_written);
  end if;

  -- DISPATCH. The text is the recipe the existing vectors were built from (embed_sales_knowledge.mjs: question + "\n" + answer).
  with pick as (
    select q.id, coalesce(q.question, '') || E'\n' || coalesce(q.answer, '') as txt
      from public.company_faq q
     where q.embedding_gte is null
       and not exists (select 1 from public.company_faq_embed_inflight f where f.faq_id = q.id)
     order by q.id
     limit v_lim
  ), sent as (
    select p.id, md5(p.txt) as text_md5,
           net.http_post(
             url := v_url,
             headers := '{"Content-Type":"application/json"}'::jsonb,
             body := jsonb_build_object('__secret', v_secret, 'fn', 'embed_company_faq', 'action', 'embed', 'text', p.txt),
             timeout_milliseconds := 25000) as request_id
      from pick p
  )
  insert into public.company_faq_embed_inflight (request_id, faq_id, text_md5)
  select s.request_id, s.id, s.text_md5 from sent s
  on conflict (request_id) do nothing;
  get diagnostics v_queued = row_count;

  return jsonb_build_object('ok', true, 'embedded', v_written, 'failed', v_failed, 'released', v_stale, 'queued', v_queued,
                            'still_null', (select count(*) from public.company_faq where embedding_gte is null), 'at', now());
end
$fn$;
revoke execute on function public.fn_company_faq_embed_tick(integer) from public, anon, authenticated;

-- 3 and 4. The job, owned by customer_support.
select cron.schedule('company_faq_embed', '*/10 * * * *', $CRON$select public.fn_company_faq_embed_tick();$CRON$);
insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('company_faq_embed', 'a company FAQ row is never left without its vector', 'Support',
   'Every 10 minutes: harvests the gte-small vectors of FAQ rows sent last tick and sends every company_faq row whose '
   || 'embedding_gte is NULL (new, or its question or answer changed) through ai_gateway embed, the free in-region path. '
   || 'With no NULL row it sends nothing.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'company_faq_embed', 'customer_support',
   'Every 10 minutes: fn_company_faq_embed_tick() harvests and sends the gte-small embeds of company_faq rows with no vector.',
   'scripts/sql/a_company_faq_row_is_never_left_without_its_vector.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

-- 5. The rows waiting now are sent at apply (pg_net sends after the commit); the first scheduled tick fills them.
select public.fn_company_faq_embed_tick();

-- verdict
select case when
       (select count(*) from cron.job where jobname = 'company_faq_embed' and active and schedule = '*/10 * * * *') = 1
   and (select count(*) from public.cron_registry where jobname = 'company_faq_embed') = 1
   and (select count(*) from public.writer_seat where kind = 'cron_job' and name = 'company_faq_embed' and owner_seat = 'customer_support') = 1
   and (select relrowsecurity from pg_class where oid = 'public.company_faq_embed_inflight'::regclass)
   and not has_table_privilege('anon', 'public.company_faq_embed_inflight', 'select')
   and not has_table_privilege('authenticated', 'public.company_faq_embed_inflight', 'select')
   and not has_function_privilege('anon', 'public.fn_company_faq_embed_tick(integer)', 'execute')
   and not has_function_privilege('authenticated', 'public.fn_company_faq_embed_tick(integer)', 'execute')
   and (select proconfig::text like '%search_path=public, extensions, pg_temp%' from pg_proc where oid = 'public.fn_company_faq_embed_tick(integer)'::regprocedure)
   and (select count(*) from public.company_faq q where q.embedding_gte is null
          and not exists (select 1 from public.company_faq_embed_inflight f where f.faq_id = q.id)) = 0
  then 'PROBE OK' else 'PROBE FAILED: the job, its registration, the grants, or a NULL company_faq row left unsent' end as verdict;
