-- PURE PROBE for the_it_engineer_breaks_the_company_once_a_month_to_prove_it_heals.sql (it_engineer, instruction 1009).
-- No DDL here, so it ends in raise exception: the whole run rolls back and the verdict is the error text.
-- Runs every scenario directly (not the month-gated duty), then the weekly line, and checks nothing is left behind.
do $probe$
declare s text; r jsonb; v_all jsonb := '{}'::jsonb; v_bad text := ''; v_left int; v_line text;
begin
  foreach s in array array['email_provider_down', 'whatsapp_down', 'edge_function_slow', 'db_connection', 'credential_expired'] loop
    execute format('select public.%I()', 'fn_it_game_day_' || s) into r;
    v_all := v_all || jsonb_build_object(s, r);
    if not coalesce((r->>'passed')::boolean, false) then v_bad := v_bad || s || ' '; end if;
  end loop;
  v_left := public.fn_it_game_day_leftovers();
  v_line := public.fn_it_game_day_weekly_line();
  raise exception 'CHK<<%>> leftovers=% failing=[%] weekly_line=% results=%',
    case when v_bad = '' and v_left = 0 and v_line is not null then 'PROBE OK' else 'PROBE FAILED' end,
    v_left, btrim(v_bad), v_line, v_all;
end $probe$;
