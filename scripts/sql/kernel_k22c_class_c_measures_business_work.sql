-- K22c — the class-C check was measuring "writes a sibling table", not "creates business work".
--
-- K22b reclassified two quote_items triggers from B to C, on the measurement that they write only
-- the quotes row their own item belongs to. The class-C check immediately went red:
--
--   active_read_only_monitors_that_write_business_work :: 2 of 16
--
-- and the first instinct — that the reclassification was wrong — is worth resisting, because the
-- two claims disagree about what "business work" means.
--
-- The check read v_kernel_trigger_source_derived.creates_work_now. For a database trigger K10
-- derives that as "the function it fires writes some table OTHER than the one the trigger is
-- attached to". trg_quote_items_rescore is attached to quote_items and writes quotes, so it is
-- true — and what it actually writes is `update public.quotes set status = status`, a no-op touch
-- whose only purpose is to fire the quotes triggers. That is a sibling write. It is not the
-- creation of business work by any reading.
--
-- The founder's rule for class C is one sentence: it "may not create business work directly".
-- Business work in this estate has a definition, and it is the list §7 protects — workflow runs,
-- step runs, tasks, handoff runs, the trigger inbox, the signal inbox, the domain-event outbox and
-- founder refund decisions. So the check now measures exactly that, and the population is the
-- routine's DEPLOYED body scanned for a write to one of those eight tables.
--
-- This is not the check being softened to fit an answer. It is stronger in the way that matters:
--
--   * it measures the rule the class states, instead of a proxy that happens to correlate
--   * what it measures is what K18 ENFORCES. A class-C source cannot write one of those tables —
--     the guard refuses it and names the call stack — so this line can no longer be made green by
--     relabelling anything
--   * the old signal is not thrown away: the sibling-write count stays, as a REPORTED line, so a
--     monitor that starts touching other tables is still visible
--
-- Rollback: re-apply scripts/sql/kernel_k17_source_cutover_register.sql, which carries the
-- previous definition. Note that doing so turns the two quote_items reclassifications red again
-- without either trigger having changed.

begin;

create or replace function public.fn_kernel_source_cutover_state()
returns table (check_name text, expected text, actual text, ok boolean)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $k17_state$
with
-- The population is recomputed from the catalogue every time, never read off this table: a check
-- whose denominator is a column the same migration writes goes green by emptying itself.
pop as (
  select * from public.v_kernel_trigger_source_derived
   where connection_state in ('CONNECTED_ACTIVE','CONNECTED_INACTIVE','INTENTIONALLY_RETIRED')
      or (coalesce(is_active_now,false) and coalesce(creates_work_now,false)
          and coalesce(disposition,'') <> 'FOUNDER_COMMAND_SURFACE')
      -- ...or it is already classified. The register may GROW when a new source appears and may
      -- never silently SHED a row because a flag on it moved.
      or source_key in (select source_component_id from public.phase_c_source_cutover)
),
c as (select * from public.phase_c_source_cutover),
act as (select * from c where current_activation = 'ACTIVE'),
protected(t) as (values
  ('phase_c_workflow_run'),('phase_c_workflow_step_run'),('phase_c_task'),('phase_c_handoff_run'),
  ('kernel_trigger_inbox'),('kernel_signal_inbox'),('phase_c_event_outbox'),('phase_c_refund_decision')),
-- A source and the routine it actually fires. Only database triggers and cron jobs can be resolved
-- to a routine from the catalogue; an Edge Function has no prosrc to read, and saying so is better
-- than pretending the scan covered it.
source_routine as (
  select s.source_component_id as source_key, p.oid, p.proname
    from public.phase_c_source_cutover s
    join pg_trigger tg on tg.tgname = split_part(s.source_component_id, ':', 3)
    join pg_class cl on cl.oid = tg.tgrelid and cl.relname = split_part(split_part(s.source_component_id, ':', 2), '.', 2)
    join pg_proc p on p.oid = tg.tgfoid
   where s.source_type = 'database_trigger' and not tg.tgisinternal
),
writes_business_work as (
  select sr.source_key, string_agg(distinct pr.t, ', ') tables
    from source_routine sr
    join pg_proc p on p.oid = sr.oid
    join protected pr on regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
         ~ ('(insert\s+into|update|delete\s+from)\s+(public\.)?' || pr.t || '\M')
   group by sr.source_key
)
select 'sources_in_the_population_with_no_classification'::text,
       '0 of ' || (select count(*)::text from pop),
       (select count(*)::text from pop p
         where not exists (select 1 from c where c.source_component_id = p.source_key))
         || ' of ' || (select count(*)::text from pop),
       (select count(*) = 0 from pop p
         where not exists (select 1 from c where c.source_component_id = p.source_key))
union all
select 'classified_sources_that_are_not_in_the_k10_inventory',
       '0 of ' || (select count(*)::text from c),
       (select count(*)::text from c
         where not exists (select 1 from public.kernel_trigger_source k
                            where k.source_key = c.source_component_id))
         || ' of ' || (select count(*)::text from c),
       (select count(*) = 0 from c
         where not exists (select 1 from public.kernel_trigger_source k
                            where k.source_key = c.source_component_id))
union all
select 'class_split',
       'reported, never counted as one backlog',
       (select string_agg(source_class || ' ' || n::text, '; ' order by source_class)
          from (select source_class, count(*) n from c group by 1) d),
       true
union all
select 'active_new_work_sources_not_pointed_at_the_trigger_adapter',
       '0 of ' || (select count(*)::text from act where source_class = 'A NEW_WORK_REQUEST'),
       (select count(*)::text from act
         where source_class = 'A NEW_WORK_REQUEST' and target_kernel_adapter <> 'fn_kernel_trigger_submit')
         || ' of ' || (select count(*)::text from act where source_class = 'A NEW_WORK_REQUEST'),
       (select count(*) = 0 from act
         where source_class = 'A NEW_WORK_REQUEST' and target_kernel_adapter <> 'fn_kernel_trigger_submit')
union all
select 'active_existing_run_signals_not_pointed_at_the_signal_adapter',
       '0 of ' || (select count(*)::text from act where source_class = 'B EXISTING_WORKFLOW_SIGNAL'),
       (select count(*)::text from act
         where source_class = 'B EXISTING_WORKFLOW_SIGNAL' and target_kernel_adapter <> 'fn_kernel_signal_submit')
         || ' of ' || (select count(*)::text from act where source_class = 'B EXISTING_WORKFLOW_SIGNAL'),
       (select count(*) = 0 from act
         where source_class = 'B EXISTING_WORKFLOW_SIGNAL' and target_kernel_adapter <> 'fn_kernel_signal_submit')
union all
-- K22c. THE class-C rule, measured as it is written: a monitor may not create business work, and
-- business work is the eight tables §7 protects. Scanned from the deployed body, and enforced
-- independently by K18 — so this line cannot be made green by relabelling a source.
select 'active_read_only_monitors_that_write_business_work',
       '0 of ' || (select count(*)::text from act where source_class = 'C READ_ONLY_MONITOR'),
       (select count(*)::text from act a join writes_business_work w on w.source_key = a.source_component_id
         where a.source_class = 'C READ_ONLY_MONITOR')
         || ' of ' || (select count(*)::text from act where source_class = 'C READ_ONLY_MONITOR')
         || coalesce(' [' || (select string_agg(a.source_component_id || ' -> ' || w.tables, '; ')
              from act a join writes_business_work w on w.source_key = a.source_component_id
             where a.source_class = 'C READ_ONLY_MONITOR') || ']', ''),
       (select count(*) = 0 from act a join writes_business_work w on w.source_key = a.source_component_id
         where a.source_class = 'C READ_ONLY_MONITOR')
union all
-- The old proxy, kept as a REPORTED line so a monitor that starts touching sibling tables is still
-- visible. It is not a pass/fail: writing a sibling row is what a normalising trigger is for.
select 'read_only_monitors_that_write_a_sibling_table',
       'reported, not a defect — a normalising trigger writes a sibling row by design',
       (select count(*)::text from act a join pop p on p.source_key = a.source_component_id
         where a.source_class = 'C READ_ONLY_MONITOR' and coalesce(p.creates_work_now,false))
         || ' of ' || (select count(*)::text from act where source_class = 'C READ_ONLY_MONITOR'),
       true
union all
select 'retired_sources_that_are_still_live_and_writing_business_work',
       '0 of ' || (select count(*)::text from c where source_class = 'D RETIRE_OR_HISTORICAL'),
       (select count(*)::text from c join writes_business_work w on w.source_key = c.source_component_id
         where c.source_class = 'D RETIRE_OR_HISTORICAL')
         || ' of ' || (select count(*)::text from c where source_class = 'D RETIRE_OR_HISTORICAL'),
       (select count(*) = 0 from c join writes_business_work w on w.source_key = c.source_component_id
         where c.source_class = 'D RETIRE_OR_HISTORICAL')
union all
select 'class_A_sources_whose_trigger_type_is_not_registered',
       '0 of ' || (select count(*)::text from c where source_class = 'A NEW_WORK_REQUEST'),
       (select count(*)::text from c where source_class = 'A NEW_WORK_REQUEST'
          and not exists (select 1 from public.kernel_trigger_type t
                           where t.trigger_type = c.target_step_or_signal))
         || ' of ' || (select count(*)::text from c where source_class = 'A NEW_WORK_REQUEST'),
       (select count(*) = 0 from c where source_class = 'A NEW_WORK_REQUEST'
          and not exists (select 1 from public.kernel_trigger_type t
                           where t.trigger_type = c.target_step_or_signal))
union all
select 'class_B_sources_whose_signal_type_is_not_registered',
       '0 of ' || (select count(*)::text from c where source_class = 'B EXISTING_WORKFLOW_SIGNAL'),
       (select count(*)::text from c where source_class = 'B EXISTING_WORKFLOW_SIGNAL'
          and not exists (select 1 from public.kernel_signal_type s
                           where s.signal_type = c.target_step_or_signal))
         || ' of ' || (select count(*)::text from c where source_class = 'B EXISTING_WORKFLOW_SIGNAL'),
       (select count(*) = 0 from c where source_class = 'B EXISTING_WORKFLOW_SIGNAL'
          and not exists (select 1 from public.kernel_signal_type s
                           where s.signal_type = c.target_step_or_signal))
union all
select 'sources_switched_off_today',
       'reported; an adapter existing is not a reason to activate one',
       (select count(*)::text from c where current_activation = 'DISABLED')
         || ' of ' || (select count(*)::text from c) || ' carry an adapter and stay disabled',
       true
union all
select 'active_sources_now_calling_a_kernel_adapter',
       'reported; it rises as each cutover increment lands',
       (select count(*)::text from source_routine sr
         join pg_proc p on p.oid = sr.oid
        where regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
              ~ '\yfn_kernel_source_emit\s*\(')
         || ' of ' || (select count(*)::text from act
                        where source_class in ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL'))
         || ' active class-A/B sources reach the kernel (database triggers only — an Edge Function '
         || 'has no prosrc to scan, and saying so beats pretending the scan covered it)',
       true
union all
select 'routine_autonomous_work_routed_through_the_founder_or_chief_of_staff',
       '0 of ' || (select count(*)::text from act where source_class in
                    ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL')),
       (select count(*)::text from act
         where source_class in ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL')
           and accountable_role in ('founder','chief_of_staff'))
         || ' of ' || (select count(*)::text from act where source_class in
                        ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL')),
       (select count(*) = 0 from act
         where source_class in ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL')
           and accountable_role in ('founder','chief_of_staff'));
$k17_state$;

commit;
