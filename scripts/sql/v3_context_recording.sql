CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text, p_max_chars integer, p_query text)
 RETURNS text
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text; v_dept text; lib text := ''; ops text := ''; r record; r2 record;
begin
  out := public.fn_agent_context(p_agent_key, p_max_chars);
  if p_agent_key is null or coalesce(p_query,'') = '' then return out; end if;
  select a.department into v_dept from org_agents a where a.agent_key = p_agent_key;
  for r in
    with hits as (
      select 1 as ord, s.* from public.fn_dept_library_search(v_dept, p_query, 4) s
      union all
      select 2 as ord, s.* from public.fn_dept_library_search('company', p_query, 2) s
    ), uniq as (
      select distinct on (id) id, title, content, ord, rank from hits order by id, ord
    )
    select title, content from uniq order by ord, rank desc
  loop
    exit when length(lib) > 2600;
    lib := lib || '## ' || coalesce(r.title,'') || E'\n' || left(coalesce(r.content,''), 700) || E'\n\n';
  end loop;
  if lib <> '' then
    out := out || E'\n' ||
      '# LAYER 2b - YOUR DEPARTMENT REFERENCE LIBRARY (retrieved from dept_library for this task; cite the title in [brackets] when you use it)' ||
      E'\n\n' || lib;
  end if;

  for r2 in
    select title, content, record_type, authority_tier, implementation_status, rank
      from public.fn_ops_knowledge_search(v_dept, p_query, 5)
     order by rank desc
  loop
    exit when length(ops) > 2400;
    ops := ops || '## [' || coalesce(r2.record_type,'record') || ' · authority: ' ||
           coalesce(r2.authority_tier,'?') || ' · ' || coalesce(r2.implementation_status,'?') || '] ' ||
           coalesce(r2.title,'') || E'\n' || left(coalesce(r2.content,''), 700) || E'\n\n';
  end loop;
  if ops <> '' then
    out := out || E'\n' ||
      '# LAYER 2c - HOW THIS COMPANY OPERATES (your department''s own SOPs, decision rules, exception playbooks and KPI definitions). ' ||
      'These OVERRIDE generic practice. Respect the authority tier on each: gated means it needs approval, ' ||
      'supervised means a human reviews it, autonomous means you may act. A record marked target_state describes ' ||
      'a capability the company has NOT built yet — plan around it, do not assume it exists.' ||
      E'\n\n' || ops;
  end if;

  -- LAYER 2d/2e/2f: the V3 delivery. Added here rather than in a new function because this is
  -- the path every agent already calls; a second assembler would have been a corpus no runtime
  -- function reads. fn_agent_context_v3 does the deterministic filtering and the budgeting.
  declare v3 jsonb; sec text := ''; itm jsonb; begin
    v3 := public.fn_agent_context_v3(p_agent_key, null, p_query, null, 9000);
    if v3 ? 'role_knowledge' then
      for itm in select * from jsonb_array_elements(v3->'role_knowledge') loop
        exit when length(sec) > 2400;
        sec := sec || '## ' || coalesce(itm->>'title','') || ' [' || coalesce(itm->>'record_id','') || ']' || E'
'
            || left(coalesce(itm->>'content',''), 700) || E'

';
      end loop;
      if sec <> '' then
        out := out || E'
' ||
          '# LAYER 2d - YOUR PROFESSIONAL ROLE KNOWLEDGE (the packaged role identity you hold: purpose, ' ||
          'competencies, expert decision checklist and evidence contract). Cite the [record_id] you use.'
          || E'

' || sec;
      end if;
    end if;

    sec := '';
    for itm in select * from jsonb_array_elements(coalesce(v3->'deterministic_rules','[]'::jsonb)) loop
      exit when length(sec) > 2000;
      sec := sec || '- [' || coalesce(itm->>'record_id','') || ' · ' || coalesce(itm->>'layer','') ||
             ' · authority ' || coalesce(itm->>'authority_tier','?') || '] ' || coalesce(itm->>'title','') || E'
';
    end loop;
    if sec <> '' then
      out := out || E'
' ||
        '# LAYER 2f - DETERMINISTIC RULES THAT BIND YOU (authority, policy, decision playbooks, KPI ' ||
        'definitions). These are looked up as structured records, never inferred from similarity. If a ' ||
        'rule here contradicts anything above, the rule wins.' || E'

' || sec;
    end if;

    sec := '';
    for itm in select * from jsonb_array_elements(coalesce(v3->'live_data_required','[]'::jsonb)) loop
      exit when length(sec) > 900;
      sec := sec || '- ' || coalesce(itm->>'title','') || E'
';
    end loop;
    if sec <> '' then
      out := out || E'
' ||
        '# LAYER 2g - FACTS YOU MUST FETCH, NOT REMEMBER. For each of these the current value comes from ' ||
        'a live authorised tool. Answering one of them from the text above is a wrong answer, however ' ||
        'confident it reads.' || E'

' || sec;
    end if;
    -- The trace has to be able to name what was read. Recorded here because this is where
    -- the assembled context and its record ids are both in scope. A STABLE function may not
    -- execute an INSERT, which is why this one and its caller are now VOLATILE.
    perform public.fn_record_context_retrieval(
      p_agent_key, null, null,
      (select array_agg(x) from jsonb_array_elements_text(coalesce(v3->'knowledge_ids','[]'::jsonb)) x),
      p_max_chars, length(out));
  end;
  return out;
end
$function$
;

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
  -- THE STORED PREFIX. See scripts/sql/a_prefix_that_moved_four_times_in_forty_five_minutes.sql:
  -- the head used to be reassembled per call and drifted four times in forty-five minutes, so
  -- the provider cache wrote on every call and read on none.
  v_stored text;
  -- Older than this and we assemble live rather than serve a prefix nobody refreshed. The
  -- refresh runs hourly; three hours means the job has been broken for three ticks.
  c_head_max_age constant interval := interval '3 hours';
  -- Fixed, so the stable region cannot be resized by what this particular question retrieved.
  v_reserve constant int := 4500;
  -- The one place the stable/volatile boundary is declared. agent_brain splits on this exact
  -- string. It is deliberately not a content heading: headings get reworded, and the last time
  -- the split depended on one it silently stopped matching and nobody noticed for a month.
  v_mark   constant text := E'\n# --- END STABLE CONTEXT ---\n';
begin
  if p_query is null or btrim(p_query) = '' then
    v_raw := public.fn_agent_context(p_agent_key, v_want);
  else
    v_raw := public.fn_agent_context(p_agent_key, v_want, p_query);

    -- Fail-open: no row, a stale row, or a different budget all fall through to the live head
    -- computed below, which is exactly the pre-14-Aug behaviour.
    if v_want = 24000 then
      select h.head into v_stored from agent_context_head h
       where h.agent_key = p_agent_key and h.built_at > now() - c_head_max_age
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
