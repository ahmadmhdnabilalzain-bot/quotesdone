-- REORGANISING THE AGENT COMPANY — the compatibility resolver reaches the path every turn uses.
--
-- Asked to prove the compatibility functions are on every live path, the measurement says they
-- were not. Of 68 public routines taking an agent, actor or assignee argument, exactly ONE —
-- fn_workflow_actor_resolve — called a resolver. Most of the other 67 take a HUMAN actor (an email
-- or a uuid) and correctly do not, but roughly twenty take an agent key, and none of those did.
--
-- fn_agent_context_capped is the one that matters most: agent_brain, action_worker, dept_plan,
-- agent_act, exec_agents and six others reach context assembly through it. Probed on production
-- before this change:
--
--   fn_agent_context_capped('chief_of_staff', …)  -> a GENERIC context, no error, wrong employee
--   fn_agent_context_v3('chief_of_staff')         -> {"error":"unknown agent"}
--   fn_agent_context_v3('analytics_director')     -> a full context for an employee merged away
--
-- The last is the dangerous one. An employee that is inactive but still assembles is an employee
-- that can still act, and nothing in the chain says otherwise.
--
-- Resolution belongs at the boundary rather than in twenty call sites: one lookup, applied where
-- the identifier enters, so a canonical role id, a legacy agent key, a merged key, a packaged role
-- id and a job title all reach the same live employee — and an inactive one reaches nothing.

-- The defaults and the search_path are the live ones, kept exactly: CREATE OR REPLACE cannot remove
-- a parameter default, and this function is called with one, two and three arguments across the
-- runtime.
create or replace function public.fn_agent_context_capped(p_agent_key text, p_max_chars integer default 9000, p_query text default null::text)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_want   int := greatest(coalesce(p_max_chars, 9000), 500);
  v_raw    text;
  v_l2     int;
  v_head   text; v_tail text;
  v_room   int;
  v_note   text;
  v_stored text;
  c_head_max_age constant interval := interval '3 hours';
  v_reserve constant int := 4500;
  v_mark   constant text := E'\n# --- END STABLE CONTEXT ---\n';
  -- THE RESOLVED KEY. Everything below uses this, never the raw argument: the stored-prefix lookup
  -- keys on it too, or an alias would miss the cache it should hit and rebuild the head every call.
  v_key    text;
  v_live   boolean;
begin
  v_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);

  select a.active into v_live from public.org_agents a where a.agent_key = v_key;
  if v_live is null then
    return '[No such employee: ' || coalesce(p_agent_key,'(null)') || '. It resolves to nothing in '
        || 'org_agents or org_agent_alias, so there is no identity, no authority and no knowledge '
        || 'to assemble. Do not proceed as though there were.]' || v_mark;
  end if;
  if not v_live then
    return '[Employee ' || v_key || ' is INACTIVE — merged away or stood down. No context is '
        || 'assembled for an inactive employee, because a context is what lets one act. Address '
        || 'the surviving role instead.]' || v_mark;
  end if;

  if p_query is null or btrim(p_query) = '' then
    v_raw := public.fn_agent_context(v_key, v_want);
  else
    v_raw := public.fn_agent_context(v_key, v_want, p_query);

    -- Fail-open: no row, a stale row, or a different budget all fall through to the live head
    -- computed below, which is exactly the pre-14-Aug behaviour.
    if v_want = 24000 then
      select h.head into v_stored from agent_context_head h
       where h.agent_key = v_key and h.built_at > now() - c_head_max_age
         and h.head_chars = 19500;
    end if;
  end if;

  if v_raw is null then return null; end if;

  v_l2 := position('# LAYER 2b' in v_raw);

  -- No query-matched tail: the whole thing is standing context and is stable as it is.
  if v_l2 = 0 then
    if length(v_raw) <= v_want then return v_raw || v_mark; end if;
    return left(v_raw, v_want - 110) || v_mark ||
      E'\n[context truncated to the ' || v_want || ' characters requested; ' || length(v_raw) ||
      ' were available. No retrieved department layer was present, so this cut is positional.]';
  end if;

  v_head := substr(v_raw, 1, v_l2 - 1);   -- standing context: identity, expertise, company, live
  v_tail := substr(v_raw, v_l2);          -- LAYER 2b + 2c, retrieved for THIS question

  -- Everything fits: nothing is trimmed and the head is whole.
  if length(v_raw) <= v_want then return v_head || v_mark || v_tail; end if;

  v_room := v_want - v_reserve;           -- FIXED. Does not depend on this question's retrieval.

  if v_room < 600 then
    -- The budget cannot fit the standing context at all. Keep what answers the question.
    return E'[Standing context omitted in full: the ' || v_want || '-character budget does not fit '
      || 'it alongside the material retrieved for this question. Identity, expertise, company '
      || 'knowledge and live state are NOT below - do not assert anything about them.]' || v_mark
      || left(v_tail, greatest(v_want - 300, 400));
  end if;

  v_note := E'\n[Standing context trimmed to the first ' || v_room || ' characters of '
         || length(v_head) || '. What follows was retrieved for this specific question. If you '
         || 'need the omitted background, say so rather than guessing at it.]\n';

  -- head is left() to a CONSTANT length, so for a given agent and budget these bytes are identical
  -- on every call. Everything that varies - the note's digits, the retrieved layers - is after the
  -- marker.
  return coalesce(v_stored, left(v_head, v_room)) || v_mark || v_note ||
         case when length(v_tail) > v_reserve
              then left(v_tail, v_reserve - 120) ||
                   E'\n[retrieved material truncated at ' || v_reserve || ' characters]'
              else v_tail end;
end
$function$;
