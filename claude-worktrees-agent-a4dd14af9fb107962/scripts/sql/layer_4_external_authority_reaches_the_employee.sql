-- LAYER 4 WAS DELIVERING THE OPPOSITE OF THE CONTRACT.
--
-- Spec #7 L541: "Layer 4 - External Knowledge: UAE regulations, industry standards, manufacturer
-- catalogs, and other authoritative external sources."
--
-- fn_agent_context emits `# LAYER 4 - WHAT THIS ORGANIZATION HAS LEARNED` — internal experience,
-- pointing the other way. The external stores exist and are populated, and are read by nobody in
-- the employee path. Counted on production 11 Aug 2026:
--
--   regulations          17   (approved, active)
--   reg_catalog          38
--   compliance_sources   17
--   mdm_standards        22
--   mdm_manufacturers    22
--   supplier_catalog      2
--                       ---
--                       118 rows of external authority reaching no employee
--
-- WHY THIS DOES NOT TOUCH fn_agent_context. That function is 34,892 characters with a documented
-- history of one bug per rewrite — an inserted line once silently evicted knowledge from 19
-- employees. The layer is therefore built as its OWN function and appended by
-- fn_agent_context_capped, which is 60 lines and which agent_brain — the employee runtime — already
-- calls. The internal LAYER 4 keeps its name and its place; this is the missing one, added beside it.
--
-- BOUNDARY, STATED: fn_agent_context has eleven other callsites and they do NOT get this layer yet.
-- Everything that runs through agent_brain does. Widening it is a separate change with its own
-- measurement.

-- ROUTINE REMOVED 7 September 2026. public.fn_external_authority was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke execute on function public.fn_external_authority(text, integer) from public;

-- The wrapper reserves a slice of its own budget for the new layer, so the standing context is
-- trimmed a little further rather than the query-matched tail being squeezed. Everything else about
-- this function is unchanged.
create or replace function public.fn_agent_context_capped(p_agent_key text, p_max_chars integer default 9000, p_query text default null)
returns text
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_want  int := greatest(coalesce(p_max_chars, 9000), 500);
  v_raw   text;
  v_l2    int;
  v_head  text; v_tail text;
  v_room  int;
  v_note  text;
  v_ext   text;
  v_extn  int := 0;
begin
  if p_query is null or btrim(p_query) = '' then
    v_raw := public.fn_agent_context(p_agent_key, v_want);
  else
    v_raw := public.fn_agent_context(p_agent_key, v_want, p_query);
  end if;

  if v_raw is null then return null; end if;

  -- LAYER 4 (EXTERNAL). 118 rows of UAE regulations, standards, manufacturers and watched
  -- authorities that reached no employee until 11 Aug 2026. Built here rather than inside
  -- fn_agent_context, which is 34,892 characters with a documented history of one bug per rewrite.
  begin
    v_ext := public.fn_external_authority(p_query, 2800);
    v_extn := coalesce(length(v_ext), 0);
  exception when others then
    v_ext := null; v_extn := 0;   -- a missing external layer must never cost the employee its context
  end;

  if length(v_raw) + v_extn <= v_want then return v_raw || coalesce(v_ext, ''); end if;

  -- THE EMITTED ORDER IS NOT THE NUMBERED ORDER. Measured on production 11 Aug 2026, the layers
  -- come out as:  LAYER 2 -> LAYER 1 -> LAYER 3 -> LAYER 4 -> LAYER 2b -> LAYER 2c
  -- so the split is at LAYER 2b: everything from there is retrieved for this exact question and is
  -- kept whole; everything before it is the standing context and is what gets trimmed.
  v_l2 := position('# LAYER 2b' in v_raw);
  if v_l2 = 0 then
    return left(v_raw, v_want - v_extn - 110) ||
      E'\n\n[context truncated to the ' || v_want || ' characters requested; ' || length(v_raw) ||
      ' were available. No retrieved department layer was present, so this cut is positional.]'
      || coalesce(v_ext, '');
  end if;

  v_head := substr(v_raw, 1, v_l2 - 1);
  v_tail := substr(v_raw, v_l2);
  v_room := v_want - length(v_tail) - v_extn - 240;

  if v_room < 600 then
    return E'[Standing context omitted in full: the ' || v_want || '-character budget does not fit '
      || 'it alongside the ' || length(v_tail) || ' characters retrieved for this question. '
      || 'Identity, expertise, company knowledge and live state are NOT below - do not assert '
      || 'anything about them.]\n\n' || left(v_tail, greatest(v_want - v_extn - 300, 400))
      || coalesce(v_ext, '');
  end if;

  v_note := E'\n\n[Standing context trimmed to fit the ' || v_want || '-character budget: '
         || length(v_head) || ' characters were available, ' || v_room || ' kept. What follows was '
         || 'retrieved for this specific question and is complete. If you need the omitted '
         || 'background, say so rather than guessing at it.]\n';

  return left(v_head, v_room) || v_note || v_tail || coalesce(v_ext, '');
end
$function$;
