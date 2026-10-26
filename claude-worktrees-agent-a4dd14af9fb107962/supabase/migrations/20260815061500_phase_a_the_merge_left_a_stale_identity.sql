-- THE MERGE LEFT A STALE IDENTITY ROW, AND THE COUNT IT BROKE IS THE ONE THAT NAMES IT.
--
-- org_reorg_behaviour asserts "the 90 accountable roles are the identity holders". It reads 91,
-- because org_role_identity still holds a row for gov_relations_mgr — the employee the Phase A
-- merge stood down. The role aliases were repaired, the agent alias was repaired, and this third
-- vocabulary was missed. Third time on the same merge, in a different table each time.
--
-- Deleting it is safe and was checked before writing, not assumed: partnerships_mgr, the surviving
-- employee of that merge, ALREADY holds the same packaged role
-- (business-development-and-partnerships-operations-specialist, package_composite). So the packaged
-- count stays at 96 — that number is a fact about the knowledge package, not ours to move — and the
-- mapping survives on the employee that still exists.
delete from public.org_role_identity
 where agent_key = 'gov_relations_mgr'
   and exists (select 1 from public.org_role_identity keep
                where keep.agent_key = 'partnerships_mgr'
                  and keep.packaged_role_id = org_role_identity.packaged_role_id);

do $$
declare v int;
begin
  select count(distinct packaged_role_id) into v from public.org_role_identity;
  if v <> 96 then raise exception 'POST: packaged roles = %, expected 96 - a packaged id was orphaned by the delete', v; end if;

  select count(distinct agent_key) into v from public.org_role_identity;
  if v <> 90 then raise exception 'POST: identity holders = %, expected 90', v; end if;

  select count(*) into v from public.org_role_identity i
   where not exists (select 1 from public.org_role r
                      where r.runtime_agent_key = i.agent_key and r.status='active'
                        and r.runtime_mode <> 'knowledge_overlay');
  if v <> 0 then raise exception 'POST: % identity row(s) belong to no active accountable role', v; end if;

  -- and every active employee still HAS one; a delete that fixed the count by removing a live
  -- mapping would pass the line above and be the opposite of a fix.
  select count(*) into v from public.org_agents a
   where a.active and not exists (select 1 from public.org_role_identity i where i.agent_key = a.agent_key);
  if v <> 0 then raise exception 'POST: % active employee(s) now have no role identity', v; end if;

  raise notice 'PHASE A: the stale identity row is gone; 90 holders, 96 packaged roles, every active employee mapped.';
end $$;
