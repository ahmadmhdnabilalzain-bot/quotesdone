-- Stage 0 chain-of-command — Defect 3: authority grants held by inactive/superseded agent keys.
--
-- Measured on production htdblwldjkcgjvmqkbeh, 28 Aug 2026:
--   employee_authority holds exactly two grants whose agent_key is an INACTIVE row that
--   fn_org_agent_resolve() maps to a DIFFERENT, active canonical agent:
--     gov_relations_mgr / analysis     (advisory)            -> resolves to partnerships_mgr (active)
--     marketing_copy    / content_draft (autonomous, 0 AED)  -> resolves to marketing_content (active)
--
-- These grants are ALREADY UNREACHABLE: every authority consumer canonicalizes the agent key via
--   p_agent := coalesce(fn_org_agent_resolve(p_agent), p_agent)
-- BEFORE matching employee_authority on the raw agent_key (verified in fn_check_spend). No request
-- ever resolves TO a superseded key, so the ghost rows can never be selected. Deleting them is
-- behaviour-preserving; it makes the authority record honest (0 grants on inactive agents).
--
-- Re-keying to the canonical agent is DELIBERATELY NOT done here: marketing_content already holds
-- content_draft at 'advisory', and the ghost row is 'autonomous' — re-keying would silently ELEVATE
-- its authority, which is an authority change, not a cleanup. partnerships_mgr does not hold
-- 'analysis' and would gain it. Any such grant must be a deliberate, reasoned change, not a
-- side effect of removing dead rows.
--
-- Reversible: trg_undo_employee_authority captures the DELETE for undo. Down script re-seeds both rows.

begin;
set local app.change_reason =
  'Stage 0 CoC Defect 3: delete 2 authority grants stranded on inactive/superseded agent keys '
  '(gov_relations_mgr, marketing_copy). Unreachable — consumers canonicalize via fn_org_agent_resolve '
  'before matching employee_authority raw. Behaviour-preserving; not re-keyed to avoid silent elevation.';

delete from public.employee_authority ea
where ea.agent_key in ('gov_relations_mgr', 'marketing_copy')
  -- only superseded keys: an inactive row whose canonical identity is a DIFFERENT agent
  and exists (select 1 from public.org_agents a
              where a.agent_key = ea.agent_key and a.active is not true)
  and public.fn_org_agent_resolve(ea.agent_key) is distinct from ea.agent_key;

-- Verify by measurement, same transaction: no grant may be held by a missing or inactive agent.
do $$
declare n int;
begin
  select count(*) into n
  from public.employee_authority ea
  left join public.org_agents a on a.agent_key = ea.agent_key
  where a.agent_key is null or a.active is not true;
  if n <> 0 then
    raise exception 'Stage 0 Defect 3 verify FAILED: % authority grant(s) still held by missing/inactive agents', n;
  end if;
end $$;

commit;
