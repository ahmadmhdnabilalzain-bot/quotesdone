-- comp-06-cross-os-query — "Leadership OS should not duplicate this knowledge; it queries Finance
-- OS when needed." (OS.txt line 109)
--
-- os_knowledge_domain holds 445 rows: 130 ownership='owns' and 315 ownership='queries'. The
-- 'queries' rows ARE the spec sentence, written down 315 times — Leadership queries finance,
-- Evolution queries ai_engineering — and NOTHING resolved them. The table's only reader was
-- fn_knowledge_gaps(p_stale_days, p_thin_min), which takes no os_key and cannot answer "who owns
-- this, and what do they know". So the routing existed as data and every OS was free to answer
-- from its own head.
--
-- This is the resolver. Given an os_key it answers, for the domains that OS does NOT own, WHICH OS
-- owns them and who to ask; given a topic as well it narrows to that domain and returns the owner's
-- actual published knowledge. It has a caller — fn_agent_context — which is the whole point:
-- fn_kb_retrieve was the last function to read a knowledge table with zero callers anywhere, and
-- that is what made 1,206 escalation rules invisible for weeks.
create or replace function public.fn_os_knowledge_query(p_os_key text, p_topic text DEFAULT NULL::text)
returns text
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare out text := ''; r record; v_line text; v_n int := 0;
begin
  if coalesce(p_os_key,'') = '' then return ''; end if;

  -- The routing table: every domain this OS is recorded as querying, and the OS that owns it.
  -- Restricted to domains that actually have an owner — a 'queries' row pointing at a domain
  -- nobody owns is a gap for fn_knowledge_gaps to report, not an address to send an employee to.
  for r in
    select k.domain_key,
           o.os_key   as owner_os,
           o2.name    as owner_name,
           o2.owner_agent
      from os_knowledge_domain k
      join os_knowledge_domain o
        on o.domain_key = k.domain_key and o.ownership = 'owns' and o.os_key <> k.os_key
      left join operating_system o2 on o2.os_key = o.os_key
     where k.os_key = p_os_key
       and k.ownership <> 'owns'
       and (p_topic is null or k.domain_key ilike '%'||p_topic||'%')
     order by o.os_key, k.domain_key
     limit 40
  loop
    -- operating_system.name already reads "Commercial OS"; only the raw key needs the suffix.
    out := out || '- ' || r.domain_key || ' -> ask ' || coalesce(r.owner_name, r.owner_os || ' OS')
               || coalesce(' (' || r.owner_agent || ')', '') || E'\n';
    v_n := v_n + 1;
  end loop;

  if v_n = 0 then return ''; end if;

  -- With a topic, also carry what the OWNER actually knows, so "query it" is an answer and not a
  -- forwarding address. Sourced from the owning OS's own employees' published knowledge.
  if p_topic is not null then
    select string_agg('  · ' || z.topic || ': ' || left(z.content, 240), E'\n')
      into v_line
      from (select distinct ak.topic, ak.content
              from os_knowledge_domain owns
              join os_department d on d.os_key = owns.os_key
              join org_agents a on a.department = d.dept_key and a.active
              join agent_knowledge ak on ak.agent_key = a.agent_key
             where owns.ownership = 'owns'
               and owns.domain_key ilike '%'||p_topic||'%'
               and coalesce(ak.layer,'profession') in ('profession','state')
               and (ak.topic ilike '%'||p_topic||'%' or ak.content ilike '%'||p_topic||'%')
             limit 4) z;
    if v_line is not null then
      out := out || 'What the owning OS publishes on "' || p_topic || '":' || E'\n' || v_line || E'\n';
    end if;
  end if;

  return out;
end $function$;
