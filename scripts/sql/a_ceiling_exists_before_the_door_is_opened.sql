-- A CEILING EXISTS BEFORE THE DOOR IS OPENED.
-- it_engineer, 23 September 2026.
--
-- department_budget holds ZERO ROWS. Measured on production 23 Sep 2026: `select count(*) from
-- public.department_budget` = 0. fn_ai_route's degrade and halt branches both hang off
-- `select * into v_bud from department_budget where dept_key = ... ; if found and monthly_aed > 0`,
-- so with no rows the branch is a condition that cannot occur. The estate has no spending ceiling
-- at all, and the founder is about to open the OpenRouter hold.
--
-- The table was not always empty — a_budget_guard_that_could_never_fire.sql (14 Aug 2026) rewrote 25
-- rows in it, and its own header records department_budget.spent_aed for exec agreeing with
-- ai_cost_log to within AED 0.71. Something emptied it since. The last section of this file makes
-- that unrepeatable.
--
-- ═══ WHY THE NUMBERS CANNOT COME FROM MEASURED SPEND ════════════════════════════════════════════
--
-- Measured over the whole of ai_cost_log, 8-22 Sep 2026: 3,207 rows, model_used = 'none' on all
-- 3,207, sum(cost_aed) = 0, sum(prompt_tokens) = 0, sum(output_tokens) = 0. Every call in the
-- estate's history was refused by the open circuit, so there is no spend to multiply and NO TOKEN
-- COUNT HAS EVER BEEN RECORDED. Anyone sizing this from ai_cost_log.cost_aed would set every
-- ceiling to zero.
--
-- So the ceiling is built from the two things that ARE measured — the CALL MIX, and the live
-- provider prices — plus a stated token estimate per class. The estimates are labelled as
-- estimates. They are to be re-derived from ai_cost_log after the first week of real traffic, which
-- is the first week the tokens exist.
--
-- ═══ THE ARITHMETIC ════════════════════════════════════════════════════════════════════════════
--
-- MEASURED call mix, 8-22 Sep 2026 (15 days, 3,207 calls), by calling function:
--
--   quote_compare      2,455   quote_comparison          (77% of everything)
--   inquiry_intake       653   agent_reasoning
--   site_assistant        50   32 visitor_chat + 18 answered by the deterministic FAQ levels
--   drawing_boq           25   document_extraction
--   drawing_redact        14   document_extraction (+ 14 identity_redaction_verify behind it)
--   founder_directive      4   json_extraction
--   license_extract        3   document_extraction
--   resend_inbound         2   intent_detection
--   quote_extract          1   document_extraction
--
-- Monthly rate = measured x 30/15 = x2. Prices USD per Mtok read live from the provider catalogue
-- 23 Sep 2026. USD->AED at the peg, 3.6725.
--
--   class / fn                 calls/mo  model              in$   out$  est in   est out   USD/mo
--   ─────────────────────────────────────────────────────────────────────────────────────────────
--   MARKETPLACE
--   quote_comparison              4,910  opus-5.5          4.00  20.00   6,000     3,000   412.44
--     per call 6,000/1e6x4.00 + 3,000/1e6x20.00 = 0.024 + 0.060 = 0.084 USD
--     est out 3,000 against a 10,000 ceiling: the ceiling is the worst case (many quotations,
--     long reasons); a top-3 ranking with its reasons is ~3,000.
--   agent_reasoning               1,306  sonnet-5          2.00  10.00   4,000     2,000    36.57
--     per call 0.008 + 0.020 = 0.028 USD
--   visitor_chat                     64  sonnet-5          2.00  10.00   2,000       600     0.64
--     32 of 50 site_assistant calls reached a model; the other 18 were answered by code.
--   document_extraction              86  gemini-3.8-flash  0.75   3.75   3,000     2,000     0.84
--     per call 0.00225 + 0.0075 = 0.00975 USD. est in 3,000 = one page image + the prompt.
--   identity_redaction_verify        28  sonnet-5          2.00  10.00   3,000       800     0.39
--                                                                       marketplace  =    450.88 USD
--                                                                                    =  1,655.86 AED
--     x1.5 headroom -> 2,483.79  ->  monthly_aed 2,500
--
--   EXEC
--   ceo_judgement / strategy        300  opus-5.5          4.00  20.00   8,000     2,000    21.60
--     per call 0.032 + 0.040 = 0.072 USD. The MEASURED rate is 4 calls in 15 days, because
--     app_secrets.ceo_model_slot is 'off' and ceo_agent returns before the model. Sizing on 4
--     would put the ceiling below the first working day. 300/mo = 10 judgements a day, which is
--     what a CEO seat that actually decides looks like.
--   json_extraction (directives)      8  gemini-3.8-flash  0.75   3.75   2,000       500     0.03
--                                                                       exec        =     21.63 USD
--                                                                                   =      79.44 AED
--     x1.5 -> 119.16  ->  monthly_aed 150
--
--   CUSTOMER_EXPERIENCE
--   customer_communication        1,000  sonnet-5          2.00  10.00   2,000       600    10.00
--   intent_detection (triage)     1,000  gemini-3.8-flash  0.75   3.75   1,500       500     3.00
--     MEASURED is 2 calls in 15 days, all refused. 1,000/mo = 33 inbound a day across email and
--     WhatsApp, which is the seat the founder has said must be better than Amazon's and whose LLM
--     is always on. A ceiling sized on 2 would halt the support seat on its first busy morning.
--                                                                       cust_exp    =     13.00 USD
--                                                                                   =      47.74 AED
--     x1.5 -> 71.61  ->  monthly_aed 100
--
--   MARKETING
--   marketing_copy                  300  sonnet-5          2.00  10.00   1,500       800     3.30
--     0 measured calls; marketing_social_inbox went live 22 Sep. 300/mo = 10 posts or replies a
--     day.                                                              marketing   =      3.30 USD
--                                                                                   =     12.12 AED
--     x1.5 -> 18.18, below the floor  ->  monthly_aed 40
--
--   FINANCE                                                             0 gateway callers today
--   IT                                                                  0 gateway callers today
--     Both get the FLOOR, 40 AED: enough for a seat to start working and be inside a ceiling from
--     its first call, small enough that the ceiling binds immediately if it starts spending.
--     Sized: the accountant's whole month on opus-5.5 (100 expense classifications at 0.016 USD,
--     100 receipt reads at 0.010 USD, 4 weekly reports at 0.072 USD) is 2.9 USD = 10.65 AED, so
--     40 is ~4x its expected load, matching the headroom the funded departments get.
--
--   TOTAL                                                               2,870 AED / month
--
-- ═══ WHY THESE CEILINGS CAN ACTUALLY FIRE ══════════════════════════════════════════════════════
--
-- This is the failure the 14 Aug 2026 file documented and did not finally fix: AED 12,000 across 25
-- departments against AED 176.86 of real spend, so degrade_at_pct 70 needed a SIXTEEN-fold traffic
-- increase to engage. A ceiling nothing can reach is not a ceiling.
--
-- At the estimates above, marketplace fills 1,656 of its 2,500 = 66% in its first month. degrade at
-- 70% is therefore reachable on ~6% more traffic than the estate already handles, and the estate is
-- about to grow. The other five sit between 30% and 66% of their own rows. Every ceiling here binds
-- within the first month of real traffic, which is the point.
--
-- degrade_at_pct / halt_at_pct, and why they differ by department:
--
--   marketplace          70 / 95  Degrading drops quote_comparison from opus-5.5 to the cheapest
--                                 medium row (gemini-3.8-flash, $0.75/$3.75) - 5x cheaper and still
--                                 answering, so degrade EARLY. Halt LATE: halting quote_comparison
--                                 stops the company earning, and 3% of a revealed quote is the only
--                                 revenue there is.
--   exec                 75 / 90  A CEO judgement that degrades is a worse judgement, so degrade
--                                 later; but exec spending 90% of its ceiling on judgements is a
--                                 loop, not a decision, and should stop.
--   customer_experience  75 / 90  Same shape: a customer must get an answer, but 90% of the ceiling
--                                 on inbound triage means something is retrying.
--   marketing            70 / 85  Nothing here is time-critical and nobody is waiting. A halted
--                                 social reply is a late reply.
--   finance              75 / 90  The books must close; they are not urgent to the hour.
--   it                   70 / 85  The IT seat's work can wait for the next tick.
--
-- Nothing here lifts the OpenRouter hold. llm_route_health.open_until is untouched by this file.

begin;

insert into public.department_budget
  (dept_key, monthly_aed, spent_aed, period_label, degrade_at_pct, halt_at_pct, updated_at)
values
  ('marketplace',         2500, 0, to_char(now(), 'YYYY-MM'), 70, 95, now()),
  ('exec',                 150, 0, to_char(now(), 'YYYY-MM'), 75, 90, now()),
  ('customer_experience',  100, 0, to_char(now(), 'YYYY-MM'), 75, 90, now()),
  ('marketing',             40, 0, to_char(now(), 'YYYY-MM'), 70, 85, now()),
  ('finance',               40, 0, to_char(now(), 'YYYY-MM'), 75, 90, now()),
  ('it',                    40, 0, to_char(now(), 'YYYY-MM'), 70, 85, now())
on conflict (dept_key) do update set
  monthly_aed = excluded.monthly_aed, period_label = excluded.period_label,
  degrade_at_pct = excluded.degrade_at_pct, halt_at_pct = excluded.halt_at_pct,
  updated_at = now();

-- ── THE GUARD: the table cannot be emptied while a model policy is live ────────────────────────
-- fn_ai_route's ceiling is not a column, an assertion or a check - it is the PRESENCE of a row.
-- Emptying the table therefore removes the ceiling without removing anything a reader would notice,
-- which is exactly what happened between 14 Aug and 23 Sep 2026. This makes the last row
-- undeletable while any active model_policy row still wants a model, and refuses a TRUNCATE
-- outright, which a row-level trigger never sees.
create or replace function public.trg_department_budget_is_never_empty()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if tg_op = 'TRUNCATE' or (select count(*) from department_budget) <= 1 then
    if exists (select 1 from model_policy where active and tier <> 'none') then
      raise exception
        'department_budget would be left empty while % active model_policy row(s) still route to a '
        'model. fn_ai_route finds its degrade and halt branches by the PRESENCE of a row here, so an '
        'empty table is an estate with no spending ceiling at all - the state measured on 23 Sep '
        '2026. Deactivate the policies first, or replace the row in the same transaction '
        '(a_ceiling_exists_before_the_door_is_opened.sql shows the arithmetic).',
        (select count(*) from model_policy where active and tier <> 'none')
        using errcode = '23514';
    end if;
  end if;
  -- OLD only exists on the row-level DELETE; touching it in the statement-level TRUNCATE trigger
  -- would raise on an unassigned record, so the level is tested rather than the operation.
  if tg_level = 'ROW' then return old; end if;
  return null;
end $fn$;

revoke execute on function public.trg_department_budget_is_never_empty() from public, anon, authenticated;

drop trigger if exists trg_department_budget_is_never_empty on public.department_budget;
create trigger trg_department_budget_is_never_empty
  before delete on public.department_budget
  for each row execute function public.trg_department_budget_is_never_empty();

drop trigger if exists trg_department_budget_no_truncate on public.department_budget;
create trigger trg_department_budget_no_truncate
  before truncate on public.department_budget
  for each statement execute function public.trg_department_budget_is_never_empty();

-- ── THE PROBE ─────────────────────────────────────────────────────────────────────────────────
-- It must show the ceiling can be FOUND by the path fn_ai_route actually walks (dept_key resolved
-- through fn_dept_canonical from fn_task_class for the calling function), and that the guard
-- refuses to empty the table. A verdict row, not a raise: a raise would roll back the DDL above.
--
-- Measured while writing this: public.org_departments holds 0 rows, so fn_dept_canonical is the
-- identity function and fn_dept_scope(x) = {x} for every key. The canonicalisation step therefore
-- cannot currently rescue a caller who passes a key with no budget row - one more reason the rows
-- below are keyed on exactly the dept_key values fn_task_class writes.
create temporary table probe_budget (k text primary key, v text) on commit drop;

-- The 19 fn labels that actually reach ai_gateway with a completion, enumerated from the source on
-- 23 Sep 2026 (scripts/checks/no_gateway_caller_is_clamped_below_what_it_asks_for.test.mjs walks
-- the same set from supabase/functions and fails if it changes). Every one of them must resolve to
-- a department that has a ceiling. fn_task_class rows for functions that do NOT call the gateway are
-- deliberately out of scope: a ceiling for a call that does not exist proves nothing.
insert into probe_budget
select 'callers_without_a_ceiling', count(*)::text
  from unnest(array['ceo_agent','doc_extract','drawing_boq','drawing_redact','drawing_redact_verify',
                    'email_triage','extract_text','founder_directive','inquiry_intake',
                    'license_extract','marketing_social_inbox','quote_compare','quote_extract',
                    'resend_inbound','site_assistant','supplier_catalog_ingest','supplier_directive',
                    'supplier_onboard','transcribe','wa_inbound']) g(fn)
  left join public.fn_task_class t on t.fn = g.fn and t.active
 where not exists (select 1 from public.department_budget b
                    where b.dept_key = public.fn_dept_canonical(t.dept_key));

insert into probe_budget
select 'callers_named', string_agg(g.fn, ',' order by g.fn)
  from unnest(array['ceo_agent','marketing_social_inbox','quote_compare','supplier_catalog_ingest']) g(fn)
  join public.fn_task_class t on t.fn = g.fn and t.active and t.dept_key is not null;

insert into probe_budget
select 'quote_compare_ceiling',
       coalesce((select b.monthly_aed::text from public.department_budget b
                  where b.dept_key = public.fn_dept_canonical(
                    (select t.dept_key from public.fn_task_class t where t.fn = 'quote_compare' and t.active))),
                '(none)');

with rows_now as (select count(*) n from public.department_budget),
pol as (select count(*) n from public.model_policy where active and tier <> 'none'),
zero as (select count(*) n from public.department_budget where coalesce(monthly_aed, 0) <= 0),
reach as (
  -- a ceiling that the estimated load cannot approach is the 14 Aug 2026 defect again. The
  -- estimates live in this file's header; this asserts the shape that made the old one unreachable
  -- (a huge allocation spread thin) cannot be what was just written.
  select count(*) n from public.department_budget
   where degrade_at_pct >= halt_at_pct or degrade_at_pct < 50 or halt_at_pct > 100)
select case
  when (select n from rows_now) = 0 then 'PROBE FAILED: department_budget is still empty'
  when (select n from zero) > 0 then 'PROBE FAILED: ' || (select n from zero)::text
       || ' budget row(s) have monthly_aed <= 0, which fn_ai_route skips exactly as it skips a missing row'
  when (select n from reach) > 0 then 'PROBE FAILED: ' || (select n from reach)::text
       || ' row(s) have a degrade/halt pair that cannot fire in order'
  when (select v from probe_budget where k = 'callers_without_a_ceiling') <> '0'
    then 'PROBE FAILED: ' || (select v from probe_budget where k = 'callers_without_a_ceiling')
         || ' active fn_task_class row(s) name a department with no budget row, so those calls are '
         || 'still outside every ceiling'
  when (select v from probe_budget where k = 'quote_compare_ceiling') = '(none)'
    then 'PROBE FAILED: quote_compare - 2,455 of the 3,207 calls ever logged - still resolves to no ceiling'
  else 'PROBE OK: ' || (select n from rows_now)::text || ' department ceilings totalling AED '
       || (select sum(monthly_aed)::text from public.department_budget)
       || '/month now cover ' || (select n from pol)::text
       || ' active model-routing policies; quote_compare resolves to AED '
       || (select v from probe_budget where k = 'quote_compare_ceiling')
       || ' via dept_key '
       || (select t.dept_key from public.fn_task_class t where t.fn = 'quote_compare' and t.active)
  end as verdict;

commit;
