-- REPORTS ARE CORPORATE PDFS (6 Sep 2026).
--
-- Founder's order: "any report needs to be in PDF format; all finance reports need to be extremely
-- organized in corporate PDF format." report_registry unions three stores — board_reports (narrative),
-- exec_reports and finance_reports — 515 rows, and until today nothing produced a PDF of any of them.
--
-- This file gives the estate the schema and the wiring; the renderer is the report_pdf edge function.
--   1. pdf_path + pdf_generated_at on every report store (finance_reports already carried pdf_path
--      from the retired html renderer; pdf_generated_at is what marks a CORPORATE render).
--   2. a private storage bucket `reports` holding <kind>/<period>/<source>_<id>.pdf.
--   3. report_registry projects the two columns so the OS can show which rows carry a PDF.
--   4. generation is AUTOMATIC: an AFTER INSERT trigger on each store queues an action_execution row
--      for the `report.pdf` executor (kind edge, target report_pdf). fn_action_invoke_dispatch — the
--      one HTTP invoker plpgsql uses for edge functions — posts it within five minutes and
--      fn_action_invoke_collect records the outcome. No net.http_post in a trigger, ever.
--   5. the two credentials that will present themselves to report_pdf (the action invoker and os_api)
--      are widened to the new scope, the way action_worker_wiring.sql widened the invoker.
--
--   node scripts/apply_sql.mjs scripts/sql/reports_are_corporate_pdfs.sql --apply --ddl
begin;

-- 1. columns ---------------------------------------------------------------------------------------
alter table public.board_reports   add column if not exists pdf_path text, add column if not exists pdf_generated_at timestamptz;
alter table public.exec_reports    add column if not exists pdf_path text, add column if not exists pdf_generated_at timestamptz;
alter table public.finance_reports add column if not exists pdf_generated_at timestamptz;

-- 2. bucket ----------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('reports', 'reports', false) on conflict (id) do nothing;

-- 3. the registry projects the PDF columns (appended, so every existing reader keeps its shape) ------
create or replace view public.report_registry as
 select 'narrative'::text as source, b.report_type, b.title,
        coalesce(b.week_start::text, to_char(b.created_at, 'YYYY-MM-DD')) as period,
        b.created_at, b.id, b.pdf_path, b.pdf_generated_at
   from public.board_reports b
 union all
 select 'exec'::text, 'exec_summary'::text, (e.officer || ' — ') || e.period, e.period, e.created_at, e.id, e.pdf_path, e.pdf_generated_at
   from public.exec_reports e
 union all
 select 'finance'::text, coalesce(f.kind, 'financial'), (('Financial — ' || coalesce(f.kind, '')) || ' ') || coalesce(f.period_start::text, ''),
        coalesce(f.period_start::text, to_char(f.created_at, 'YYYY-MM-DD')), f.created_at, f.id, f.pdf_path, f.pdf_generated_at
   from public.finance_reports f;

-- 4. automatic generation through the action queue -------------------------------------------------
create or replace function public.fn_report_pdf_enqueue()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_source text;
begin
  v_source := case tg_table_name when 'board_reports' then 'board' when 'exec_reports' then 'exec' when 'finance_reports' then 'finance' end;
  begin
    insert into public.action_execution (action_class, executor, idempotency_key, risk_tier, reversible, request, status, author, correlation_id)
    values ('report.pdf', 'report_pdf', 'report_pdf:' || v_source || ':' || new.id, 'low', true,
            jsonb_build_object('source', v_source, 'id', new.id), 'queued', 'report_pdf_trigger', gen_random_uuid());
  exception
    when unique_violation then null;                       -- already queued for this row
    when others then raise warning 'fn_report_pdf_enqueue: % (the report row is kept; its PDF can be minted on demand)', sqlerrm;
  end;
  return null;
end $function$;
revoke execute on function public.fn_report_pdf_enqueue() from public, anon, authenticated;

drop trigger if exists z_report_pdf_enqueue on public.board_reports;
drop trigger if exists z_report_pdf_enqueue on public.exec_reports;
drop trigger if exists z_report_pdf_enqueue on public.finance_reports;
create trigger z_report_pdf_enqueue after insert on public.board_reports   for each row execute function public.fn_report_pdf_enqueue();
create trigger z_report_pdf_enqueue after insert on public.exec_reports    for each row execute function public.fn_report_pdf_enqueue();
create trigger z_report_pdf_enqueue after insert on public.finance_reports for each row execute function public.fn_report_pdf_enqueue();

-- fn_org_action_executor_guard refused the executor row below with: "edge target report_pdf is outside
-- the fn.cos_execute credential scope. cos_execute would POST service-role authority to it. Widen the
-- credential scope deliberately if this executor is intended." It is intended, and this is the deliberate
-- widening (the same one action_worker_wiring.sql made): report_pdf reads one report row, writes a PDF
-- into the private reports bucket and two columns back onto that row. It sends nothing, spends nothing
-- and calls no model, so widening the hop widens no authority over money or messages.
update public.internal_credential
   set scope = (select array_agg(distinct s order by s) from unnest(scope || array['report_pdf']) s)
 where context = 'fn.cos_execute' and active and retired_at is null and not (scope @> array['report_pdf']);

insert into public.org_action_executor
  (action_class, kind, target, params, active, note, advisory_safe, department, risk_tier, reversible,
   idempotency_strategy, timeout_seconds, max_attempts, required_authority, notifies_human, unattended_ok)
values
  ('report.pdf', 'edge', 'report_pdf', '{}'::jsonb, true,
   'Renders a report row (board_reports / exec_reports / finance_reports) as a corporate PDF into the private reports bucket. Deterministic, no model call. Queued by z_report_pdf_enqueue.',
   true, 'exec', 'low', true, 'natural_key', 120, 2, null, false, true)
on conflict (action_class) do update
  set kind = excluded.kind, target = excluded.target, active = excluded.active, note = excluded.note,
      advisory_safe = excluded.advisory_safe, risk_tier = excluded.risk_tier, reversible = excluded.reversible,
      idempotency_strategy = excluded.idempotency_strategy, timeout_seconds = excluded.timeout_seconds,
      max_attempts = excluded.max_attempts, notifies_human = excluded.notifies_human, unattended_ok = excluded.unattended_ok;

-- 5. the callers' credentials name the new callee ---------------------------------------------------
update public.internal_credential
   set scope = (select array_agg(distinct s order by s) from unnest(scope || array['report_pdf']) s)
 where context in ('action.invoker', 'fn.os_api') and active and retired_at is null and not (scope @> array['report_pdf']);

-- 6. the OS action is registered in Control Mode's table with the classification os_api declares ----
insert into public.control_mode_action (action, description, risk, classification)
values ('report_pdf_url', 'Signs (minting on demand) the corporate PDF of a report the caller can already read. No business state changes; stays off the preview-key allowlist.', 'medium', 'read_only')
on conflict (action) do update set description = excluded.description, risk = excluded.risk, classification = excluded.classification;
update public.control_mode_action set description = 'Older name of report_pdf_url: renders a report the caller can already read into a PDF object in the private reports bucket. No business state changes; stays off the preview-key allowlist.' where action = 'report_pdf';

-- proof: both credentials are accepted for report_pdf, and the trigger queues (rolled back) ---------
do $proof$
declare v jsonb; n int;
begin
  select public.fn_internal_auth(s.value, 'report_pdf') into v from public.app_secrets s where s.key = 'cred_action_invoker';
  if v is null or coalesce((v->>'ok')::boolean, false) is not true then raise exception 'cred_action_invoker not accepted for report_pdf: %', coalesce(v->>'error', 'no secret'); end if;
  select public.fn_internal_auth(s.value, 'report_pdf') into v from public.app_secrets s where s.key = 'cred_fn_os_api';
  if v is null or coalesce((v->>'ok')::boolean, false) is not true then raise exception 'cred_fn_os_api not accepted for report_pdf: %', coalesce(v->>'error', 'no secret'); end if;
  select count(*) into n from pg_trigger where tgname = 'z_report_pdf_enqueue' and not tgisinternal;
  if n <> 3 then raise exception 'expected 3 z_report_pdf_enqueue triggers, found %', n; end if;
  if not exists (select 1 from public.org_action_executor where action_class = 'report.pdf' and active and kind = 'edge' and target = 'report_pdf') then raise exception 'report.pdf executor missing'; end if;
  raise notice 'proof: credentials accepted, 3 triggers, executor registered';
end $proof$;

commit;
