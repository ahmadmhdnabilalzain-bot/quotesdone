-- SPEC FILE #2 — first run of everything bus_contract_close.sql wired up, on BOTH projects.
--   node scripts/apply_sql.mjs scripts/sql/bus_contract_seed.sql --promote --ddl
--
-- Deploying is not verifying. Every routine below is EXECUTED here against real rows, in the order
-- the chain runs, so the effect can be read back immediately instead of waiting for a cron:
--   emit → dispatch → close → consolidate → re-prioritise → dispatch the re-prioritisation.
-- Re-applying is safe: every step in the chain is deduped on its own key.

-- 1 · Intelligence tells the company which KPIs are missed. Deduped per metric per day.
select public.fn_emit_metric_alerts() as alerts_emitted;

-- 2 · The nightly reflection, which now EMITS the supply gap instead of writing into procurement's
--     queue. Deduped on a 20-hour window.
select public.fn_company_reflect() -> 'actions' as reflection_actions;

-- 3 · Continuous improvement. Emits improvement.proposed for each question it actually raises.
select public.fn_os_improve() -> 'questions' as improvement_questions;

-- 4 · Drain the bus. Each call is capped at 50 (event, subscriber) pairs on purpose; four calls
--     clear the backlog these emissions and the repointed subscriptions created.
select public.fn_event_dispatch() -> 'delivered' as d1;
select public.fn_event_dispatch() -> 'delivered' as d2;
select public.fn_event_dispatch() -> 'delivered' as d3;
select public.fn_event_dispatch() -> 'delivered' as d4;

-- 5 · Close the loop: results back onto the deliveries, lessons into institutional memory, one
--     rollup per business episode, and a re-prioritisation for every episode that finished across
--     more than one OS.
select public.fn_event_consolidate() as consolidated;

-- 6 · Deliver the re-prioritisations that step 5 just emitted, so link 9 is a delivered event and
--     not just a published one.
select public.fn_event_dispatch() -> 'delivered' as d5;

-- 7 · An interface that has now flowed is not "planned", whatever step 3 of the schema file said.
--     Derived from company_event, so the flag cannot survive the traffic that disproves it.
-- Both names, not just event_type: one row's declared kind (campaign.published) differs from the
-- event_type the bus carries (content.published), and clearing the flag on event_type alone would
-- call an interface live whose own declared kind has never fired.
update public.os_interface i set planned = false, planned_reason = null
 where coalesce(i.planned,false)
   and exists (select 1 from public.company_event e where e.event_type = i.event_type)
   and exists (select 1 from public.company_event e where e.event_type = i.kind);

select 'seeded' as done;
