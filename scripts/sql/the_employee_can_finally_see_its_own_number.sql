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

create or replace function public.fn_employee_scorecard(p_agent_key text,
                                                        p_max_chars integer default 1400)
returns text
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_cap  int := greatest(coalesce(p_max_chars, 1400), 300);
  v_out  text := '';
  v_line text;
begin
  if coalesce(btrim(p_agent_key),'') = '' then return null; end if;

  -- YOUR NUMBER. attainment mirrors fn_kpi_scoreboard exactly, including the percent_max
  -- inversion; it is NOT recomputed with a different rule, because two rules that must agree is
  -- how sec() and J() ended up with 8 and 11 variants of the same helper.
  -- An unmeasured KPI says so in words. It must never read as a zero.
  select string_agg(
           '- '||z.kpi||': target '||coalesce(z.target_value::text,'?')||' '||coalesce(z.unit,'')
           ||case
               when z.actual_value is null then ' — NOT MEASURED YET (no number exists; do not assume one)'
               else ' — you are at '||z.actual_value::text
                    ||case when z.target_value is null or z.target_value = 0 then ''
                           when z.unit = 'percent_max'
                             then ', '||round(least(100.0, 100.0 * z.target_value / nullif(z.actual_value,0)),0)::text||'% of target'
                           else ', '||round(100.0 * z.actual_value / z.target_value,0)::text||'% of target' end
                    ||case
                        when z.target_value is null or z.target_value = 0 then ''
                        when z.unit = 'percent_max' then
                          case when z.actual_value <= z.target_value then ' (MET)' else ' (MISSED)' end
                        else
                          case when z.actual_value >= z.target_value then ' (MET)'
                               when z.actual_value >= 0.9 * z.target_value then ' (NEAR)'
                               else ' (MISSED)' end end
             end
           ||case when z.serves_goal is not null then ' — serves company goal '||z.serves_goal else '' end,
           E'\n' order by z.kpi)
    into v_line
    from (select k.kpi, k.target_value, k.unit, k.actual_value, k.serves_goal
            from employee_kpi k
           where k.agent_key = p_agent_key and k.active
           order by k.kpi limit 8) z;

  if v_line is not null then
    v_out := v_out || E'\n# YOUR NUMBER RIGHT NOW — measured, not asserted\n' || v_line || E'\n';
  end if;

  -- YOUR DEPARTMENT'S OBJECTIVE and the company goal it serves. This is the chain the founder
  -- described, delivered to the one employee that has to act on it.
  select string_agg(
           '- '||d.objective
           ||case when d.target_value is not null then ' (target '||d.target_value::text||' '||coalesce(d.unit,'')||')' else '' end
           ||case when d.actual_value is not null then ', department is at '||d.actual_value::text
                  when d.measure_sql is not null then ', not yet measured'
                  else '' end
           ||case when g.key is not null then E'\n    serves company goal '||g.key||' — "'||g.goal||'"' else '' end,
           E'\n' order by d.sort, d.id)
    into v_line
    from department_objective d
    join org_agents a on a.agent_key = p_agent_key and a.department = d.dept_key
    left join company_goals g on g.key = d.goal_key and g.active
   where d.active
   limit 6;

  if v_line is not null then
    v_out := v_out || E'\n# WHAT YOUR DEPARTMENT IS FOR\n' || v_line || E'\n';
  end if;

  if v_out = '' then return null; end if;
  return left(v_out, v_cap);
end $function$;

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
