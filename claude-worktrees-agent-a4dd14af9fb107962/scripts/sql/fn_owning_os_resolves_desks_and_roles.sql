-- fn_owning_os could not name an OS for a category desk or for a role that is not an employee.
--
-- FOUND BY A REGRESSION I CAUSED. explain-owning-os went MET -> NOT MET at 59 of 61 after the
-- inbox drain closed 123 items: the operations surface lists PENDING approvals, so closing the
-- items above these two promoted them into view. The defect was always there; the drain is what
-- made it visible, which is the honest version of a check going red.
--
--   id 2287  agent 'document_controller'  doc_task ("Oversized files")        -> os null
--   id 2297  agent 'cat:signage'          decision.route_category            -> os null
--
-- Six resolution rules and none covered them: 'cat:signage' is a category desk, not an
-- org_agents row, and 'document_controller' is a role name with no department at all.
--
-- Both new rules read os_responsibility rather than naming an OS, so the answer comes from the
-- company's own ownership map and moves with it:
--   * a category desk is owned by whoever owns category_coverage  -> marketplace
--   * document_controller stems to 'document', which matches      -> operations
--     process_documentation
create or replace function public.fn_owning_os(p_agent text)
returns text
language sql
stable security definer
set search_path to 'public', 'pg_catalog'
as $function$
  with a as (select coalesce(nullif(btrim(p_agent), ''), '~none~') k),
  stripped as (
    -- widened from _(ai|director|ops|monitor|watch|agent|bot) so a role title resolves too
    select regexp_replace(a.k, '_(ai|director|ops|monitor|watch|agent|bot|controller|curator|analyst|engineer|manager|lead|head|specialist)$', '') s
    from a)
  select coalesce(
    (select o.os_key from public.operating_system o, a where o.owner_agent = a.k and o.active limit 1),
    (select r.os_key from public.os_responsibility r, a where r.responsibility = a.k limit 1),
    (select r.os_key from public.os_responsibility r
       join public.org_agents g on g.department = r.responsibility, a
      where g.agent_key = a.k limit 1),
    (select r.os_key from public.os_responsibility r, stripped where r.responsibility = stripped.s limit 1),
    (select o.os_key from public.operating_system o, a where o.os_key = a.k and o.active limit 1),
    (select o.os_key from public.operating_system o, stripped where o.os_key = stripped.s and o.active limit 1),
    -- the live department -> OS map, which this function never consulted
    (select d.os_key from public.os_department d
       join public.org_agents g on g.department = d.dept_key, a
      where g.agent_key = a.k limit 1),
    -- a category desk ('cat:signage') is owned by whichever OS owns category coverage
    (select r.os_key from public.os_responsibility r, a
      where a.k like 'cat:%' and r.responsibility = 'category_coverage' limit 1),
    -- last resort: a role name whose stem appears in a responsibility. Ordered by the shortest
    -- responsibility so the most specific owner wins rather than whichever row is read first.
    (select r.os_key from public.os_responsibility r, stripped
      where length(stripped.s) >= 4 and r.responsibility like '%' || stripped.s || '%'
      order by length(r.responsibility), r.responsibility limit 1)
  );
$function$;

-- CREATE OR REPLACE preserves the ACL, so grants are deliberately not touched.
