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
-- RE-DERIVED 23 Sep 2026 from founder_instruction 841's matrix (qwen/qwen3.8-max-0902 for reasoning,
-- z-ai/glm-5.3-flash for everything else). An earlier draft of this file was priced on
-- anthropic/claude-opus-5.5 and came to AED 2,870/month; the founder's ruling cuts the same measured
-- workload to AED 1,170/month, because the dominant line falls from $0.084 to $0.030 a call.
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
-- 23 Sep 2026: qwen3.8-max 2.00/6.00, glm-5.3-flash 0.15/0.50, gemini-3.1-flash-lite 0.25/1.50.
-- USD->AED at the peg, 3.6725.
--
--   class / fn                 calls/mo  model    in$   out$  est in   est out   USD/mo   AED/mo
--   ─────────────────────────────────────────────────────────────────────────────────────────────
--   MARKETPLACE
--   quote_comparison              4,910  qwen     2.00  6.00   6,000     3,000   147.30   540.96
--     per call 6,000/1e6x2.00 + 3,000/1e6x6.00 = 0.012 + 0.018 = 0.030 USD
--     est out 3,000 against a 10,000 ceiling: the ceiling is the worst case (many quotations, long
--     reasons); a top-3 ranking with its reasons is ~3,000.
--   agent_reasoning               1,306  qwen     2.00  6.00   4,000     2,000    26.12    95.93
--     per call 0.008 + 0.012 = 0.020 USD
--   identity_redaction_verify        28  qwen     2.00  6.00   3,000       800     0.30     1.11
--   visitor_chat                     64  glm      0.15  0.50   2,000       600     0.04     0.14
--     32 of 50 site_assistant calls reached a model; the other 18 were answered by code.
--   document_extraction              86  glm      0.15  0.50   3,000     2,000     0.12     0.46
--     per call 0.00045 + 0.001 = 0.00145 USD. est in 3,000 = one page image + the prompt.
--                                                             marketplace  =    173.89   638.59
--     x1.5 headroom -> 957.89  ->  monthly_aed 960     (fill 66.5% in month one)
--
--   EXEC
--   ceo_judgement / strategy        300  qwen     2.00  6.00   8,000     2,000     8.40    30.85
--     per call 0.016 + 0.012 = 0.028 USD. The MEASURED rate is 4 calls in 15 days, because
--     app_secrets.ceo_model_slot is 'off' and ceo_agent returns before the model. Sizing on 4 would
--     put the ceiling below the first working day. 300/mo = 10 judgements a day, which is what a CEO
--     seat that actually decides looks like.
--   json_extraction (directives)      8  glm      0.15  0.50   2,000       500     0.00     0.02
--                                                             exec         =      8.40    30.87
--     x1.5 -> 46.30  ->  monthly_aed 50                (fill 61.7%)
--
--   CUSTOMER_EXPERIENCE
--   customer_communication        1,000  glm      0.15  0.50   2,000       600     0.60     2.20
--   intent_detection (triage)     1,000  glm      0.15  0.50   1,500       500     0.47     1.74
--     MEASURED is 2 calls in 15 days, all refused. 1,000/mo = 33 inbound a day across email and
--     WhatsApp, which is the seat the founder has said must be better than Amazon's and whose LLM is
--     always on. A ceiling sized on 2 would halt the support seat on its first busy morning.
--                                                             cust_exp     =      1.07     3.95
--     x1.5 -> 5.92, below the floor  ->  monthly_aed 40  (fill 9.9%)
--
--   FINANCE
--   accountant_expense_classification 100 qwen    2.00  6.00   1,000       600     0.56     2.06
--   accountant_receipt_extraction     100 glm     0.15  0.50   3,000     2,000     0.14     0.53
--   accountant_weekly_report            4 qwen    2.00  6.00   8,000     2,000     0.11     0.41
--     0 measured calls; the accountant has no gateway caller yet. This is the shape of one month of
--     real bookkeeping, and it is what says the floor is not arbitrary.
--                                                             finance      =      0.82     3.00
--     x1.5 -> 4.50, below the floor  ->  monthly_aed 40  (fill 7.5%)
--
--   MARKETING
--   marketing_copy                  300  glm      0.15  0.50   1,500       800     0.19     0.69
--     0 measured calls; marketing_social_inbox went live 22 Sep. 300/mo = 10 posts or replies a day.
--                                                             marketing    =      0.19     0.69
--     x1.5 -> 1.03, below the floor  ->  monthly_aed 40  (fill 1.7%)
--
--   IT                                                        0 gateway callers today
--     Floor 40: enough for the seat to start working and be inside a ceiling from its first call.
--
--   TOTAL                                                                       AED 1,170 / month
--
-- THE FLOOR IS AED 40, and it is the one number here that is a judgement rather than a derivation:
-- small enough that a department which starts spending crosses degrade quickly and visibly, large
-- enough that a seat's first day of work is not halted. It is inherited from the 14 Aug 2026 file,
-- which used the same 40 for the same reason.
--
-- NONE OF THESE FIGURES IS A MEASURED COST. They are estimates from the measured CALL MIX and the
-- live PRICES, with a token estimate per class that no measurement supports, because no measurement
-- exists: all 3,207 rows carry prompt_tokens 0 and output_tokens 0. Re-derive from ai_cost_log after
-- the first week of real traffic — that is the first week the tokens exist, and quote_comparison's
-- true input size is the single number that moves this total.
--
-- ═══ WHY THESE CEILINGS CAN ACTUALLY FIRE ══════════════════════════════════════════════════════
--
-- This is the failure the 14 Aug 2026 file documented and did not finally fix: AED 12,000 across 25
-- departments against AED 176.86 of real spend, so degrade_at_pct 70 needed a SIXTEEN-fold traffic
-- increase to engage. A ceiling nothing can reach is not a ceiling.
--
-- At the estimates above, marketplace fills 638.59 of its 960 = 66.5% in its first month. degrade at
-- 70% is therefore reachable on 5% more traffic than the estate already handles, and the estate is
-- about to grow. exec sits at 61.7% of its own row. The four on the floor sit between 1.7% and 9.9%
-- — not because the ceiling is loose but because they have almost no traffic yet; the floor is what
-- keeps them inside a ceiling at all, and their first real week will move them.
--
-- WHAT DEGRADING ACTUALLY DOES, CORRECTED (23 Sep 2026, in review). An earlier draft of this header
-- claimed marketplace would degrade to google/gemini-3.8-flash "5x cheaper". That was wrong twice
-- over. fn_ai_route degrades exactly ONE BAND — `case v_tier when 'xlarge' then 'large' when 'large'
-- then 'medium' else 'small' end` — and then picks the cheapest active approved row in that band. So:
--
--   marketplace's reasoning classes are tier large (qwen3.8-max $2.00/$6.00)
--     -> degrade to the cheapest MEDIUM row, google/gemini-3.8-flash $0.75/$3.75
--     -> 2.67x cheaper on input, 1.6x on output. A real step, not a 5x one.
--   the GLM classes are tier small ($0.15/$0.50)
--     -> degrade within small to openai/gpt-6-luna $0.10/$0.50 — 1.5x, i.e. almost nothing, which is
--        correct: work that already costs a fraction of a fils has nothing to give back.
--
-- 70/95 for marketplace still stands, but for a different reason than the draft gave: degrade EARLY
-- because a 2.67x step still buys real headroom and the class keeps answering, and halt LATE because
-- halting quote_comparison stops the company earning — 3% of a revealed quote is the only revenue
-- there is.
--
-- degrade_at_pct / halt_at_pct, and why they differ by department:
--
--   marketplace          70 / 95  see above.
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
  ('marketplace',          960, 0, to_char(now(), 'YYYY-MM'), 70, 95, now()),
  ('exec',                  50, 0, to_char(now(), 'YYYY-MM'), 75, 90, now()),
  ('customer_experience',   40, 0, to_char(now(), 'YYYY-MM'), 75, 90, now()),
  ('marketing',             40, 0, to_char(now(), 'YYYY-MM'), 70, 85, now()),
  ('finance',               40, 0, to_char(now(), 'YYYY-MM'), 75, 90, now()),
  ('it',                    40, 0, to_char(now(), 'YYYY-MM'), 70, 85, now())
on conflict (dept_key) do update set
  monthly_aed = excluded.monthly_aed, period_label = excluded.period_label,
  degrade_at_pct = excluded.degrade_at_pct, halt_at_pct = excluded.halt_at_pct,
  updated_at = now();

-- ── THE GUARD: every department a caller routes to keeps a ceiling while a policy is live ────────────────────────
-- fn_ai_route's ceiling is not a column, an assertion or a check - it is the PRESENCE of a row.
-- Emptying the table therefore removes the ceiling without removing anything a reader would notice,
-- which is exactly what happened between 14 Aug and 23 Sep 2026. This makes the last row
-- undeletable while any active model_policy row still wants a model, and refuses a TRUNCATE
-- outright, which a row-level trigger never sees.
create or replace function public.trg_department_budget_keeps_a_ceiling_per_caller()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  -- PER-DEPARTMENT, NOT "IS THE TABLE EMPTY" (corrected 23 Sep 2026 in review). The first draft
  -- fired only at count(*) <= 1, so five of the six ceilings could be deleted one at a time and the
  -- guard would say nothing: marketplace — 77% of every call the estate has ever routed — could lose
  -- its ceiling in silence as long as `it` still had a row. The table being non-empty was never the
  -- property worth protecting. The property is that EVERY DEPARTMENT A CALLER ROUTES TO still
  -- resolves to a ceiling, which is exactly the lookup fn_ai_route performs.
  if tg_op = 'TRUNCATE' then
    if exists (select 1 from model_policy where active and tier <> 'none') then
      raise exception
        'TRUNCATE on department_budget would remove every spending ceiling at once while % active '
        'model_policy row(s) still route to a model. fn_ai_route finds its degrade and halt branches '
        'by the PRESENCE of a row here, so an empty table is an estate with no ceiling at all - the '
        'state measured on 23 Sep 2026. Deactivate the policies first, or replace the rows in the '
        'same transaction (a_ceiling_exists_before_the_door_is_opened.sql shows the arithmetic).',
        (select count(*) from model_policy where active and tier <> 'none')
        using errcode = '23514';
    end if;
  elsif exists (select 1 from model_policy where active and tier <> 'none')
    and exists (select 1 from fn_task_class t
                 where t.active and t.dept_key is not null
                   and public.fn_dept_canonical(t.dept_key) = old.dept_key)
  then
    raise exception
      'deleting the "%" ceiling would leave % active fn_task_class row(s) routing to a department '
      'with no budget, so fn_ai_route could neither degrade nor halt them. Per-department on purpose: '
      '"the table is not empty" was never the property - every department a caller routes to must '
      'resolve to a ceiling. Repoint or deactivate those rows first, or replace this one in the same '
      'transaction.',
      old.dept_key,
      (select count(*) from fn_task_class t
        where t.active and t.dept_key is not null
          and public.fn_dept_canonical(t.dept_key) = old.dept_key)
      using errcode = '23514';
  end if;
  -- OLD only exists on the row-level DELETE; touching it in the statement-level TRUNCATE trigger
  -- would raise on an unassigned record, so the level is tested rather than the operation.
  if tg_level = 'ROW' then return old; end if;
  return null;
end $fn$;

revoke execute on function public.trg_department_budget_keeps_a_ceiling_per_caller() from public, anon, authenticated;

drop trigger if exists trg_department_budget_keeps_a_ceiling_per_caller on public.department_budget;
create trigger trg_department_budget_keeps_a_ceiling_per_caller
  before delete on public.department_budget
  for each row execute function public.trg_department_budget_keeps_a_ceiling_per_caller();

drop trigger if exists trg_department_budget_no_truncate on public.department_budget;
create trigger trg_department_budget_no_truncate
  before truncate on public.department_budget
  for each statement execute function public.trg_department_budget_keeps_a_ceiling_per_caller();

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
