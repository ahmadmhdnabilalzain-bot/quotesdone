-- REORGANISING THE AGENT COMPANY - 24: every employee has been answering with no context at all.
--
-- Measured on staging, 14 Aug 2026, from agent_runs during the Gate B smoke - 23 of 23 cases:
--
--   "fn_agent_context_capped returned no context for account_mgr (cannot execute INSERT in a
--    read-only transaction), so this employee answered without its identity, company genome,
--    authority limits or profession."
--
-- THE WHOLE CHAIN, and it is three correct-looking things that are wrong together:
--
--   agent_brain  ->  fn_agent_context_capped   declared STABLE
--                ->  fn_agent_context(3-arg)   declared VOLATILE, and it RECORDS what it retrieved
--                ->  fn_record_context_retrieval  INSERT into agent_context_retrieval
--
-- PostgREST executes a STABLE function in a READ-ONLY transaction. The nested INSERT therefore
-- throws, and because it throws inside the assembly it does not merely skip the recording - it
-- takes the entire context with it. agent_brain catches that, writes the note above, and answers
-- anyway. Every employee turn since the recording was added has run BLIND: no identity, no
-- authority, no department knowledge, no company genome.
--
-- Nothing failed loudly. The HTTP call returns 200, the model answers fluently, the answer looks
-- professional, and agent_runs carries a note nobody was reading. agent_context_retrieval stopped
-- at 14:12 UTC and that silence was the only external symptom.
--
-- A function that writes is not STABLE. The declaration was the defect: fn_agent_context_capped
-- reaches a recording INSERT on its query path, so it is VOLATILE and always was.
--
-- Not fixed by removing the recording instead: the recording is what puts real knowledge ids into
-- decision_trace.knowledge_refs, which is the blueprint's traced-stable-id requirement. Deleting it
-- would have turned a loud contradiction into a quiet gap.
--
-- Body is the live staging definition with one word changed, generated rather than retyped.

begin;

CREATE OR REPLACE FUNCTION public.fn_agent_context_capped(p_agent_key text, p_max_chars integer DEFAULT 9000, p_query text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$
;

commit;
