-- THE EMPLOYEE SAW ITS TARGET AND NEVER ITS NUMBER.
--
-- fn_agent_context has emitted "# YOUR KPIs - this is how your work is measured" for weeks, with
-- the target, the unit, the cadence and the company goal served. Measured 11 Aug 2026, what it
-- could not emit was the one thing that makes a KPI a KPI: WHERE THE EMPLOYEE ACTUALLY IS.
--
-- It could not, because until this morning employee_kpi had no actual_value column. fn_kpi_scoreboard
-- computed the number live and discarded it. That column now exists and is refreshed on cron
-- (fn_employee_kpi_measure, 03:30 daily) - 74 of 94 measurable KPIs carry a real number as of now.
--
-- So every employee in this company can be told, at prompt time and for free:
--   your KPI, your current number, how far that is from target, your department's objective, and
--   the company goal it serves.
-- which is the founder's §3 stated in his own words.
--
-- WHY THIS DOES NOT EDIT fn_agent_context. Same reason LAYER 4 did not: that function is 34,892
-- characters with a documented history of one bug per rewrite, and an inserted line once silently
-- evicted knowledge from 19 employees. This is built as its own function and folded into the value
-- fn_agent_context_capped already appends, so NOT ONE LINE of that function's budget arithmetic
-- changes - the scorecard is simply carried in the same variable the external layer already used.
--
-- READS THE STORED NUMBER, NEVER EXECUTES A MEASURE. fn_agent_context runs at 765 ms against an
-- 8-second PostgREST wall. Executing up to 8 arbitrary measure_sql statements per prompt is exactly
-- the 7,302 ms defect that was fixed this month.

-- ROUTINE REMOVED 7 September 2026. public.fn_employee_scorecard was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke all on function public.fn_employee_scorecard(text, integer) from public;

-- ---------------------------------------------------------------------------------------------
-- FOLD IT IN. The ONLY change to fn_agent_context_capped is the block marked below: the scorecard
-- is prepended into v_ext and v_extn recomputed, so every existing budget branch, split point and
-- truncation note works unchanged and unre-tested.
-- CREATE OR REPLACE preserves the ACL, so this must NOT be followed by a revoke.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_agent_context_capped(p_agent_key text, p_max_chars integer DEFAULT 9000, p_query text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_want  int := greatest(coalesce(p_max_chars, 9000), 500);
  v_raw   text;
  v_l2    int;
  v_head  text; v_tail text;
  v_room  int;
  v_note  text;
  v_ext   text;
  v_extn  int := 0;
  v_sc    text;
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

  -- ---- THE ONLY ADDITION, 11 Aug 2026 --------------------------------------------------------
  -- The employee's own current number, its department's objective and the company goal that
  -- objective serves. Carried in v_ext so that every branch below keeps working unchanged.
  -- Same defensive shape as the external layer: a failure here must never cost the employee its
  -- context, and must never be allowed to read as a zero.
  begin
    v_sc := public.fn_employee_scorecard(p_agent_key, 1400);
    if v_sc is not null then
      v_ext  := v_sc || coalesce(v_ext, '');
      v_extn := coalesce(length(v_ext), 0);
    end if;
  exception when others then
    null;
  end;
  -- --------------------------------------------------------------------------------------------

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
