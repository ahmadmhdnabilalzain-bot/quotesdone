-- THE SUPPLY ENGINE'S CRONS RUN, THROUGH THE KERNEL, UNDER THE SUPPLY DEPARTMENT (3 Sep 2026).
--
-- The four routines the five files before this one define do nothing until something ticks them.
-- Three of the jobs existed and were stood down on 16 Aug; one is new. Every one goes through
-- fn_kernel_wrap_and_enable_cron so its ticks are traced (phase_c_system_execution) and owned:
--
--   job 155 supply_gap_scan_daily      03:20 UTC  fn_supply_gap_scan            supplier_coverage
--   NEW     supplier_discovery_daily   02:50 UTC  fn_supplier_discovery_promote supplier_coverage
--   job 59  doc_expiry_daily           05:20 UTC  fn_doc_expiry_scan            supplier_verification
--   job 2   supplier_invites_daily     09:00 UTC  enqueue_supplier_invites      strategic_partnerships_government_relations_manager
--
-- Discovery runs before the gap scan so the scan counts what discovery just promoted; the scan runs
-- before the invite plan so the plan draws on the day's gaps. Job 162 (company_indices_daily) was
-- wrapped earlier today by another session and is not touched here; the routine it runs now
-- investigates its own falls (supply_engine_marketplace_eight_inputs_and_fall_investigated.sql).
--
-- The invite job is enabled with the send gate CLOSED (invite_enabled = 'false', set by
-- supply_engine_invite_plan_is_real_and_held.sql): its tick plans the batch and holds it. The
-- founder's go opens the gate; nothing here does.
--
--   node scripts/apply_sql.mjs scripts/sql/supply_engine_crons_run_through_the_kernel.sql --apply --ddl
begin;

do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'cron' and p.proname = 'schedule') then
    raise exception 'pg_cron not installed';
  end if;
  -- cron.schedule() upserts on the job name.
  perform cron.schedule('supplier_discovery_daily', '50 2 * * *', 'select public.fn_supplier_discovery_promote(300, 500);');
end $$;

insert into public.cron_registry (jobname, human_name, category, purpose)
values
  ('supplier_discovery_daily', 'Supplier discovery (daily)', 'Supplier growth',
   'fn_supplier_discovery_promote(300, 500) — promotes up to 300 staged directory rows (yello_staging) that no lead carries into leads, thinnest catalogue category first, classifies each through the category lexicon, marks the staged row promoted or duplicate, and classifies up to 500 existing leads the lexicon never saw. Records itself in scrape_runs. Replaces the Apify scrape, paused until ~Feb 2027.'),
  ('supply_gap_scan_daily', 'Supply Gap Scan Daily', 'Supplier growth',
   'fn_supply_gap_scan() — writes the daily supply snapshot: every catalogue category against the 10-matchable-supplier target with the matchable and sendable pool by emirate, the categories with no supply at all, and one coverage_gap action per category per week addressed to the supplier_coverage seat. Demand-side coverage (inquiries that got quotes) is kept in the same snapshot.'),
  ('doc_expiry_daily', 'Document expiry scan (daily)', 'Documents & compliance',
   'fn_doc_expiry_scan() — for every approved supplier with a licence, insurance, registration, ISO or manufacturer authorisation expiring within 30 days or lapsed: writes the renewal request to the supplier outbox (held until the founder''s go), suspends matching on a lapsed licence and restores it on renewal (fn_reconcile_licence_blocks), and records the action on agent_actions for the supplier_verification seat. Writes nothing to the founder.'),
  ('supplier_invites_daily', 'Supplier Invites Daily', 'Supplier growth',
   'enqueue_supplier_invites() — plans today''s invitation batch in invite_schedule (ramp cap bounded by the never-invited pool) and, only when app_secrets.invite_enabled is true, queues it to the outbox. With the gate closed the day is planned and held with the reason in the note.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

do $wrap$
declare r record; v jsonb; v_new bigint;
begin
  select jobid into v_new from cron.job where jobname = 'supplier_discovery_daily';
  if v_new is null then raise exception 'supplier_discovery_daily was not scheduled'; end if;
  for r in select * from (values
      (155::bigint, 'supplier_coverage',                                    'supply'),
      (v_new,       'supplier_coverage',                                    'supply'),
      (59::bigint,  'supplier_verification',                                'supply'),
      (2::bigint,   'strategic_partnerships_government_relations_manager',  'supply')
    ) t(jobid, role_id, dept) loop
    v := public.fn_kernel_wrap_and_enable_cron(r.jobid, r.role_id, r.dept, 'routine_operational_decision');
    if coalesce((v->>'ok')::boolean, false) is not true then
      raise exception 'wrap of cron % failed: %', r.jobid, v;
    end if;
    raise notice 'cron %: %', r.jobid, v->>'action';
  end loop;

  -- The wrap keeps an already-wrapped job's owner; the owners above are the ones this department
  -- carries, so they are set explicitly for all four.
  update public.phase_c_component c
     set accountable_role_id = o.role_id, department_id = o.dept, authority_class = 'routine_operational_decision',
         activation_state = 'active', schedule_or_trigger = j.schedule,
         repair_or_keep_action = 'supply engine 3 Sep 2026: runs through fn_kernel_cron_exec under the supply department'
    from (values
        ('cron:supply_gap_scan_daily',    'supplier_coverage',                                   'supply'),
        ('cron:supplier_discovery_daily', 'supplier_coverage',                                   'supply'),
        ('cron:doc_expiry_daily',         'supplier_verification',                               'supply'),
        ('cron:supplier_invites_daily',   'strategic_partnerships_government_relations_manager', 'supply')
      ) o(component_id, role_id, dept)
    join cron.job j on 'cron:' || j.jobname = o.component_id
   where c.component_id = o.component_id;
end $wrap$;

do $proof$
declare v_raw int; v_gate text;
begin
  select count(*) into v_raw from cron.job
   where jobname in ('supply_gap_scan_daily','supplier_discovery_daily','doc_expiry_daily','supplier_invites_daily')
     and (not active or command not ilike '%fn_kernel_cron_exec%');
  if v_raw > 0 then raise exception '% of the four supply jobs are still raw or inactive', v_raw; end if;
  select value into v_gate from public.app_secrets where key = 'invite_enabled';
  if coalesce(v_gate, 'false') = 'true' then
    raise exception 'invite_enabled is true: the invite cron would send real invitations at 09:00 UTC without the founder''s go';
  end if;
  if (select count(*) from public.phase_c_component where component_id in
        ('cron:supply_gap_scan_daily','cron:supplier_discovery_daily','cron:doc_expiry_daily','cron:supplier_invites_daily')
        and department_id = 'supply' and activation_state = 'active') <> 4 then
    raise exception 'the four supply cron components are not all active under supply';
  end if;
  raise notice 'proof: four supply jobs active through fn_kernel_cron_exec, owned by supply, invite gate closed';
end $proof$;
commit;
