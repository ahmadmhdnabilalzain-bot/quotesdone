-- fn_tool_readiness — ai_tool_matrix, the last pack table in the routing pack with no reader.
--
-- 22 rows: tool, current_status, priority, required_before_launch, purpose, recommendation,
-- code_dependency. It is the pack's answer to "what is this company plugged into, and what is
-- missing before it can open". Nothing read it, so a P0 connector sitting at Not connected was
-- invisible to every routine and every screen.
--
-- Deliberately NOT bolted into fn_ops_dashboard: that function already has a live caller and a
-- return shape, and a launch-blocker list is a scheduled fact, not a dashboard tile. Same shape
-- as fn_kb_corpus_integrity — one query, one incident when it is not true, one dated number.
create or replace function public.fn_tool_readiness()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_tot int; v_connected int; v_blockers int; v_names text[]; v_p0 int;
        v_cond int; v_cond_names text[];
begin
  select count(*),
         count(*) filter (where lower(coalesce(current_status,'')) like 'connected%'),
         count(*) filter (where lower(coalesce(priority,'')) = 'p0')
    into v_tot, v_connected, v_p0
    from public.ai_tool_matrix;

  -- The column is not a boolean. Eight rows say a bare 'Yes'; three say a CONDITIONAL yes —
  -- 'Yes for autonomous supplier discovery' (Apify), 'Yes if CAD/office conversion is enabled'
  -- (CloudConvert), 'Yes unless refactored' (Dropbox). Matching only 'yes' reports 0 blockers and
  -- reads as ready; matching 'yes%' reports 3 and would page about Apify, which was deliberately
  -- cancelled until ~Feb 2027. Both are counted, and only the unconditional ones raise.
  select count(*), coalesce(array_agg(tool || ' (' || coalesce(priority,'?') || ', ' ||
                                      coalesce(current_status,'unknown') || ')' order by priority, tool), '{}')
    into v_blockers, v_names
    from public.ai_tool_matrix
   where lower(coalesce(required_before_launch,'')) = 'yes'
     and lower(coalesce(current_status,'')) not like 'connected%';

  select count(*), coalesce(array_agg(tool || ' — ' || required_before_launch order by tool), '{}')
    into v_cond, v_cond_names
    from public.ai_tool_matrix
   where lower(coalesce(required_before_launch,'')) like 'yes %'
     and lower(coalesce(current_status,'')) not like 'connected%';

  if v_blockers > 0 then
    insert into public.agent_actions(agent, kind, title, recommendation, detail, risk, status)
    values ('it', 'ops_recommendation',
            format('%s tool(s) required before launch are not connected', v_blockers),
            'Connect them or record in ai_tool_matrix why the launch no longer depends on them. A required_before_launch row that stays disconnected is a launch date that has not been re-planned.',
            jsonb_build_object('tools', to_jsonb(v_names), 'source', 'fn_tool_readiness'),
            'medium', 'pending');
  end if;

  return jsonb_build_object('tools', v_tot, 'connected', v_connected, 'p0', v_p0,
                            'launch_blockers', v_blockers, 'blocker_list', to_jsonb(v_names),
                            'conditionally_required_not_connected', v_cond,
                            'conditional_list', to_jsonb(v_cond_names),
                            'ran_at', now());
end $function$;

revoke execute on function public.fn_tool_readiness() from public;
revoke execute on function public.fn_tool_readiness() from anon;
revoke execute on function public.fn_tool_readiness() from authenticated;

select cron.schedule('tool_readiness_daily', '55 3 * * *', $$select public.fn_tool_readiness();$$);
