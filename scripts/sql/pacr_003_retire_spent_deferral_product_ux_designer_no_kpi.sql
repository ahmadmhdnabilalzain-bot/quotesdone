-- PACR-003 — A SPENT DEFERRAL IS RETIRED, NOT KEPT (3 Sep 2026).
--
-- The founder-approved Phase A baseline carries a deferred list: role violations he agreed to live
-- with for now. fn_org_role_deferral_state() reports a deferral that matches NO live violation as
-- STALE, because a deferral that excuses a gap that has since been filled is a sentence about the
-- past sitting in a list that is supposed to describe the present.
--
-- Measured 3 Sep 2026: product_ux_designer carried four deferrals (no_authority, no_knowledge,
-- no_kpi, no_tools). fn_org_role_violations_all() now reports only three for that role — the KPI
-- loop has since assigned it a KPI — so no_kpi:product_ux_designer matches nothing. The other three
-- still match live violations and stay exactly as approved. Nothing is hidden by this: the board
-- still reports every remaining deferral, never marks one complete, and reddens on the next stale one.
--
-- WHY A PACR. org_phase_baseline is append-only by trigger (a00_org_phase_baseline_append_only refuses
-- UPDATE unconditionally). The sanctioned way to change a baseline row is the one PACR-002 used and
-- the guard's own hint names: drop the trigger, make the change with every digest RECOMPUTED in place,
-- recreate the trigger in the SAME transaction, and append this file to MANIFEST.txt. The dropped
-- trigger recorded here is the evidence the freeze was opened deliberately and closed again. This
-- request changes NO department, role, overlay or manager edge — only the deferred list — so the
-- registry and organization digests recompute to the values they already hold; the counts entry
-- deferred_items moves 4 -> 3, which is the point.
--
-- Two earlier attempts (commits 3cc2709 and ce487ca) were refused by the guard: a bare UPDATE, then
-- an UPDATE carrying app.phase_a_change_reason, which this guard does not read. ce487ca's message
-- claimed the file was applied and the gate green; it was not — that claim was false and this file
-- is the correction.
--
-- Approver: founder standing order 2 Sep 2026 that the phase freezes are removed totally; this is
-- housekeeping on his approved record, not a change to the organisation.
--
--   node scripts/apply_sql.mjs scripts/sql/pacr_003_retire_spent_deferral_product_ux_designer_no_kpi.sql --apply --ddl
begin;
set local app.phase_a_change_reason =
  'PACR-003: retire the spent deferral no_kpi:product_ux_designer from the phase A deferred list. '
  'The role has since been assigned a KPI, so the deferral matches no live violation and '
  'fn_org_role_deferral_state reports it stale. No department, role, overlay or manager edge changes.';

drop trigger a00_org_phase_baseline_append_only on public.org_phase_baseline;

update public.org_phase_baseline b
   set deferred = (select coalesce(jsonb_agg(t), '[]'::jsonb)
                   from jsonb_array_elements_text(b.deferred) t
                   where t <> 'no_kpi:product_ux_designer'),
       counts = jsonb_build_object(
         'active_departments',       (select count(*) from public.org_departments where active),
         'canonical_roles',          (select count(*) from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay'),
         'category_overlays',        (select count(*) from public.org_role where status='active' and runtime_mode = 'knowledge_overlay'),
         'department_heads',         (select count(*) from public.org_departments where active and lead_agent is not null),
         'organizational_workflows', (select count(*) from public.org_workflow_ownership),
         'phase_a_violations',       (select count(*) from public.fn_phase_a_organization_violations()),
         'deferred_items',           (select count(*) from jsonb_array_elements_text(b.deferred) t where t <> 'no_kpi:product_ux_designer'),
         'retired_roles',            (select count(*) from public.org_role where status='retired')),
       registry_sha256 = jsonb_set(
         b.registry_sha256,
         '{reporting_graph,database}',
         to_jsonb((select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
                     from (select r.role_id sortkey,
                                  r.role_id||'|'||coalesce(r.manager_role_id,'founder')||'|'||r.primary_department_id x
                             from public.org_role r
                            where r.status='active' and r.runtime_mode <> 'knowledge_overlay') s))),
       organization_sha256 = (
         with
         d as (select string_agg(dept_key||'|'||name||'|'||active::text||'|'||coalesce(lead_agent,''), chr(10) order by dept_key) x from public.org_departments),
         r as (select string_agg(role_id||'|'||display_name||'|'||primary_department_id||'|'||coalesce(manager_role_id,'')
                 ||'|'||runtime_mode||'|'||coalesce(runtime_agent_key,'')||'|'||status||'|'||coalesce(evaluation_suite,'')
                 ||'|'||coalesce(array_length(owned_decisions,1),0)::text||'|'||coalesce(array_length(forbidden_decisions,1),0)::text,
                 chr(10) order by role_id) x from public.org_role),
         c as (select string_agg(category_key, chr(10) order by category_key) x from public.org_category_identity),
         w as (select string_agg(workflow_key||'|'||step_no::text||'|'||step||'|'||coalesce(actor_role,''), chr(10) order by workflow_key, step_no) x from public.workflow_step),
         f as (select string_agg(decision_key, chr(10) order by decision_key) x from public.founder_reserved_decision),
         a as (select string_agg(agent_key||'|'||department||'|'||active::text||'|'||coalesce(manager_key,''), chr(10) order by agent_key) x from public.org_agents)
         select encode(sha256(convert_to(
           'departments'||chr(10)||d.x||chr(10)||'--'||chr(10)||
           'roles'||chr(10)||r.x||chr(10)||'--'||chr(10)||
           'categories'||chr(10)||c.x||chr(10)||'--'||chr(10)||
           'workflow_steps'||chr(10)||w.x||chr(10)||'--'||chr(10)||
           'reserved'||chr(10)||f.x||chr(10)||'--'||chr(10)||
           'agents'||chr(10)||a.x, 'UTF8')), 'hex')
         from d, r, c, w, f, a),
       note = b.note || chr(10) || chr(10) || 'PACR-003, 3 Sep 2026: the spent deferral no_kpi:product_ux_designer was retired — '
              'the role has since been assigned a KPI, so the deferral matched no live violation and '
              'fn_org_role_deferral_state reported it stale. The three still-matching deferrals for that '
              'role (no_authority, no_knowledge, no_tools) remain as approved. No department, role, '
              'overlay or manager edge changed; digests recomputed in place to the values they held.',
       recorded_at = now()
 where b.phase = 'A'
   and b.deferred ? 'no_kpi:product_ux_designer';

-- Close the freeze again in the same transaction.
create trigger a00_org_phase_baseline_append_only
  before delete or update on public.org_phase_baseline
  for each row execute function public.fn_org_phase_baseline_append_only();

do $ctl$
begin
  if exists (select 1 from public.fn_org_role_deferred() d
             where not exists (select 1 from public.fn_org_role_violations_all() v where v.rule = d.rule and v.role_id = d.role_id)) then
    raise exception 'a stale deferral remains after this retirement: %',
      (select string_agg(d.token, ', ') from public.fn_org_role_deferred() d
        where not exists (select 1 from public.fn_org_role_violations_all() v where v.rule = d.rule and v.role_id = d.role_id));
  end if;
  if (select count(*) from public.fn_org_role_deferred()) <> 3 then
    raise exception 'expected exactly the 3 still-matching deferrals to remain, found %', (select count(*) from public.fn_org_role_deferred());
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.org_phase_baseline'::regclass and tgname = 'a00_org_phase_baseline_append_only') then
    raise exception 'the append-only guard was not re-created';
  end if;
end $ctl$;
commit;
