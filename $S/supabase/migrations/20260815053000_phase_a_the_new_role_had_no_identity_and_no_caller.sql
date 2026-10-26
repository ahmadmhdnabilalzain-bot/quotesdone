-- THE NEW ROLE HAD NO IDENTITY AND NOTHING NAMED IT.
--
-- Two more consequences of creating product_ux_designer, both found by the repo's own checks and
-- both squarely inside Phase A's scope — identity and accountability, not knowledge or tools.
--
-- 1. NO ROLE IDENTITY. org_role_identity maps every runtime employee to the packaged role it
--    realises, and "no active agent may run without a role identity" is asserted. A new employee
--    with no row is an employee the packaged-knowledge layer cannot address at all.
--
--    It joins engineering-operations-specialist, which backend_engineer and frontend_engineer
--    already share as package_composite — the package's single engineering operations role covers
--    several runtime roles, and this is a fourth. Deliberately NOT a new packaged_role_id: that
--    would take the packaged count from 96 to 97 and break "all 96 packaged roles reach an active
--    canonical role", which is a true statement about the knowledge package and not ours to move.
--    Deliberately NOT one_to_one either: that mapping type claims exclusivity, and a check exists
--    that says an exclusive mapping never shares its packaged role.
--
--    readiness stays restricted_to_advisory, the same as all 96. Phase A activates nothing.
insert into public.org_role_identity
  (agent_key, packaged_role_id, packaged_department, archetype, mapping_type, readiness, package_version)
values ('product_ux_designer', 'engineering-operations-specialist', 'engineering',
        'operations-specialist', 'package_composite', 'restricted_to_advisory', '2026.08.14')
on conflict (agent_key, packaged_role_id) do nothing;

-- 2. NO WORKFLOW NAMED IT. "A role named by no step, no routine, no cron, no executor and no tool
--    grant is a row, not a job." product_ux_designer was named by nothing, so it was a row.
--
--    The Phase A registry has it as a contributor to W22 "Product discovery to delivery"; the
--    runtime analogue is improvement_lifecycle, whose participants are already the Corporate
--    Performance Director, the Product Manager, the Knowledge Director and the Product Optimisation
--    Engineer. A designer belongs in exactly that company.
--
--    'participant', not 'owner' and not 'step actor'. The package is explicit that contributors do
--    not become co-accountable owners, and W22 is owned by the Product Manager. Recording it as an
--    owner to satisfy a check would have manufactured a second accountable owner for a workflow
--    that has one.
insert into public.employee_workflow (agent_key, workflow_key, role_in_workflow)
values ('product_ux_designer', 'improvement_lifecycle', 'participant')
on conflict (agent_key, workflow_key) do nothing;

do $$
declare v int; v_who text;
begin
  select count(*) into v from public.org_agents a
   where a.active and not exists (select 1 from public.org_role_identity i where i.agent_key = a.agent_key);
  if v <> 0 then raise exception 'FOLLOW-UP: % active employee(s) still have no role identity', v; end if;

  -- the packaged count is a fact about the knowledge package. It must not have moved.
  select count(distinct packaged_role_id) into v from public.org_role_identity;
  if v <> 96 then raise exception 'FOLLOW-UP: packaged roles = %, expected 96 — a new packaged id was invented', v; end if;

  select count(*), string_agg(r.role_id, ', ') into v, v_who from public.org_role r
   where r.runtime_mode <> 'knowledge_overlay' and r.status = 'active'
     and not exists (select 1 from public.workflow_step s
                      where coalesce(public.fn_org_agent_resolve(s.actor_role), public.fn_org_role_resolve(s.actor_role)) = r.runtime_agent_key)
     and not exists (select 1 from public.employee_workflow w where w.agent_key = r.runtime_agent_key);
  if v <> 0 then raise exception 'FOLLOW-UP: % role(s) are named by no workflow: %', v, v_who; end if;

  -- and W22 still has exactly one accountable owner, which is the whole reason this was recorded
  -- as a participant rather than an owner.
  select count(*) into v from public.org_workflow_ownership
   where workflow_id = 'W22' and accountable_role_id = 'product_manager';
  if v <> 1 then raise exception 'FOLLOW-UP: W22 no longer has exactly one accountable owner'; end if;

  raise notice 'PHASE A FOLLOW-UP: every active employee has a role identity, 96 packaged roles unchanged, no role unnamed.';
end $$;
