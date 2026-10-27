-- A HELD ARABIC COMPARISON REPORT IS SENT TO THE CUSTOMER ONCE ITS LINES EXIST
-- Seat: it_engineer (PR #1574, release operator's review of 19 Oct 2026). 27 Oct 2026.
--
-- MEASURED. customer_api compare_pdf in Arabic answers 202 "held" when a line of the report has no Arabic yet (under
-- the model hold, or since PR #1574 when the request's 90 s budget is spent: run 0a717394 S09 had hit the 150 s edge
-- wall, HTTP 504). The missing lines are filed for the replay (surface sales_engineer.document_arabic) and
-- fn_reason_apply_sales_engineer__document_arabic stores their Arabic. Nothing then rendered the report or sent it:
-- arabic_document_waiter is keyed by a QUOTE and only supplier_api's regenerated quotation reads it. The customer
-- had been told the report would be ready shortly and had to come back and press the button again.
--
-- WHAT THIS CHANGES.
--   1. public.arabic_compare_waiter: one row per INQUIRY whose Arabic report is waiting, with the lines it waits on.
--      Not a second use of arabic_document_waiter: that table's key is quote_id and its renderer is supplier_api;
--      a comparison report belongs to an inquiry and is rendered by customer_api (customer_api/compare_arabic.ts).
--   2. fn_arabic_compare_wait(inquiry, texts): compare_pdf records the waiter when it answers 202. A second held
--      press updates the lines and KEEPS created_at, which is the delivery's dedupe key: one report, one send.
--   3. fn_arabic_compare_waiters_ready(limit): the waiters whose every line is now in public.arabic_translation,
--      fewer than 5 failed tries, and not offered in the last 2 minutes (it stamps last_offered_at), so the
--      replay's concurrent rows in one tick do not render the same report several times.
--   4. fn.resilience_ping's credential gains 'customer_api' in its scope: reasoned_delivery (run by resilience_ping)
--      calls customer_api compare_arabic_finish, which refuses any credential not scoped to it.
--
-- WHAT THIS DOES NOT CHANGE: how a line is translated or stored (fn_arabic_translation_store), the regenerated
-- quotation's waiter, and the English report (never held).
--
-- Prevented by: supabase/functions/customer_api/compare_arabic.test.ts (one delivered Arabic report per waiter;
-- nothing sent while a line is missing; a second run sends nothing) and the PROBE at the end of this file.

create table if not exists public.arabic_compare_waiter (
  inquiry_id      text primary key check (btrim(inquiry_id) <> ''),
  texts           text[] not null check (cardinality(texts) > 0),
  attempts        integer not null default 0,
  last_tried_at   timestamptz,
  last_offered_at timestamptz,
  created_at      timestamptz not null default now()
);
alter table public.arabic_compare_waiter enable row level security;
drop policy if exists arabic_compare_waiter_service_role_only on public.arabic_compare_waiter;
create policy arabic_compare_waiter_service_role_only on public.arabic_compare_waiter
  as permissive for all to public using (false) with check (false);
revoke all on public.arabic_compare_waiter from anon, authenticated;
-- The daily export: excluded like arabic_document_waiter, a retry queue whose inquiry is itself exported.
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('arabic_compare_waiter', false, 'cache', 'a retry queue for held Arabic comparison reports; the inquiry it waits on is exported, and a row lives only until the report is sent', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

create or replace function public.fn_arabic_compare_wait(p_inquiry text, p_texts text[])
returns void
language sql security definer
set search_path to 'public', 'pg_temp'
as $fn$
  insert into public.arabic_compare_waiter (inquiry_id, texts) values (p_inquiry, p_texts)
  on conflict (inquiry_id) do update set texts = excluded.texts
$fn$;
revoke execute on function public.fn_arabic_compare_wait(text, text[]) from public, anon, authenticated;
grant execute on function public.fn_arabic_compare_wait(text, text[]) to service_role;

create or replace function public.fn_arabic_compare_waiters_ready(p_limit integer default 10)
returns jsonb
language sql security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with ready as (
    select d.inquiry_id from public.arabic_compare_waiter d
     where d.attempts < 5   -- a render that keeps failing stops costing replays (customer_api tells the sales engineer)
       and (d.last_offered_at is null or d.last_offered_at < now() - interval '2 minutes')
       and not exists (select 1 from unnest(d.texts) t
                        where not exists (select 1 from public.arabic_translation a where a.source_md5 = md5(t)))
     order by d.attempts, d.last_offered_at nulls first, d.created_at
     limit greatest(1, least(coalesce(p_limit, 10), 100))
     for update skip locked
  ), offered as (
    update public.arabic_compare_waiter w set last_offered_at = now()
      from ready where w.inquiry_id = ready.inquiry_id
    returning w.inquiry_id
  )
  select coalesce(jsonb_agg(inquiry_id), '[]'::jsonb) from offered
$fn$;
revoke execute on function public.fn_arabic_compare_waiters_ready(integer) from public, anon, authenticated;
grant execute on function public.fn_arabic_compare_waiters_ready(integer) to service_role;

update public.internal_credential
   set scope = array_append(scope, 'customer_api')
 where context = 'fn.resilience_ping' and not ('customer_api' = any(scope));

-- PROBE (verdict row; cleans up after itself). Uses an inquiry id no real inquiry carries and two ZZ PROBE source
-- lines that no document contains; the waiter and both translation rows are deleted at the end, and the verdict
-- fails if either survives. No real waiter or translation is touched.
create temp table zz_probe_compare_ar (step text primary key, v boolean) on commit drop;
select public.fn_arabic_compare_wait('zz-probe-compare-ar', array['ZZ PROBE line one']);
select public.fn_arabic_compare_wait('zz-probe-compare-ar', array['ZZ PROBE line one', 'ZZ PROBE line two']);
insert into zz_probe_compare_ar select 'one_waiter_two_lines',
  (select count(*) = 1 and min(cardinality(texts)) = 2 from public.arabic_compare_waiter where inquiry_id = 'zz-probe-compare-ar');
insert into zz_probe_compare_ar select 'untranslated_not_offered', not (public.fn_arabic_compare_waiters_ready(100) ? 'zz-probe-compare-ar');
insert into public.arabic_translation (source_md5, source, arabic)
  values (md5('ZZ PROBE line one'), 'ZZ PROBE line one', 'سطر الفحص الأول'), (md5('ZZ PROBE line two'), 'ZZ PROBE line two', 'سطر الفحص الثاني')
  on conflict (source_md5) do nothing;
insert into zz_probe_compare_ar select 'translated_offered', public.fn_arabic_compare_waiters_ready(100) ? 'zz-probe-compare-ar';
insert into zz_probe_compare_ar select 'not_offered_twice', not (public.fn_arabic_compare_waiters_ready(100) ? 'zz-probe-compare-ar');
insert into zz_probe_compare_ar select 'scoped',
  coalesce((select 'customer_api' = any(scope) from public.internal_credential where context = 'fn.resilience_ping'), false);
insert into zz_probe_compare_ar select 'anon_refused',
  not has_function_privilege('anon', 'public.fn_arabic_compare_waiters_ready(integer)', 'execute')
  and not has_function_privilege('anon', 'public.fn_arabic_compare_wait(text, text[])', 'execute');
delete from public.arabic_compare_waiter where inquiry_id = 'zz-probe-compare-ar';
delete from public.arabic_translation where source in ('ZZ PROBE line one', 'ZZ PROBE line two');
insert into zz_probe_compare_ar select 'cleaned',
  not exists (select 1 from public.arabic_compare_waiter where inquiry_id = 'zz-probe-compare-ar')
  and not exists (select 1 from public.arabic_translation where source like 'ZZ PROBE line %');
select coalesce('PROBE FAILED: ' || string_agg(step, ', ' order by step) filter (where not v), 'PROBE OK') as verdict
  from zz_probe_compare_ar;
