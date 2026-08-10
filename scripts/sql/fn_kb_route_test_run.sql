-- fn_kb_route_test_run — a scheduled runner for the 344 operational route tests the
-- 86-CATEGORIES pack ships.
--
-- WHY. kb_operational_route_test held 344 cases with last_run_at = 2026-08-02 12:48 — one
-- execution, eight days ago, by a script that no longer exists. The pack scorecard has called
-- this artefact "partial — stored, no scheduled runner" ever since, and that was exactly right:
-- a regression suite that runs once is a snapshot, not a guard. The routing tables it guards
-- (kb_operational_alias 4,212 rows, kb_operational_route_map 426) are rewritten by every import.
--
-- WHICH ROUTINE PRODUCES THE RESULT, AND HOW THAT WAS ESTABLISHED. The first version of this
-- runner called fn_trade_identify, which is the live inquiry classifier — and it was WRONG.
-- Executed against 5 cases on production it reported 5 regressions; the regressions were mine.
-- fn_trade_identify returns {ok, proposed, confirmed, clarification_required, ...} and the stored
-- expectations are keyed on `action`, which comes from fn_kb_route_decide(text) — STABLE, no
-- writes, and the only routine in the database that emits 'route_or_ask_scope_details'. The
-- assertion "5 of 5 Arabic routes have regressed" was a false alarm produced by asserting the
-- wrong shape, which is why the runner asserts on the recorded expectation and not on a 200.
create or replace function public.fn_kb_route_test_run(p_limit integer default 400)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare t record; r jsonb;
        v_ran int := 0; v_pass int := 0; v_fail int := 0; v_reg int := 0; v_regs text[] := '{}';
begin
  for t in
    select x.test_id, x.input, x.expected_action, (x.last_result->>'action') prev_action
      from public.kb_operational_route_test x
     order by x.last_run_at nulls first, x.test_id
     limit greatest(coalesce(p_limit, 400), 1)
  loop
    begin
      r := public.fn_kb_route_decide(t.input);
    exception when others then
      r := jsonb_build_object('action', 'error', 'error', left(SQLERRM, 300));
    end;

    update public.kb_operational_route_test
       set last_result = r, last_run_at = now()
     where test_id = t.test_id;

    v_ran := v_ran + 1;
    if (r->>'action') = t.expected_action then
      v_pass := v_pass + 1;
    else
      v_fail := v_fail + 1;
      -- a REGRESSION is a case that used to pass and no longer does. The cases that were already
      -- failing on 2 Aug are failures, not regressions, and must not page anyone every hour.
      if t.prev_action is not distinct from t.expected_action then
        v_reg := v_reg + 1; v_regs := v_regs || t.test_id;
      end if;
    end if;
  end loop;

  if v_reg > 0 then
    insert into public.agent_actions(agent, kind, title, recommendation, detail, risk, status)
    values ('knowledge_eng', 'incident',
            format('%s operational route test(s) regressed', v_reg),
            'A route that used to resolve correctly no longer does. Check kb_operational_alias and kb_operational_route_map for the affected catalog numbers.',
            jsonb_build_object('test_ids', to_jsonb(v_regs), 'source', 'fn_kb_route_test_run'),
            'medium', 'pending');
  end if;

  return jsonb_build_object('ran', v_ran, 'passed', v_pass, 'failed', v_fail,
                            'regressions', v_reg, 'regressed', to_jsonb(v_regs), 'ran_at', now());
end $function$;

-- SECURITY DEFINER functions are granted EXECUTE to PUBLIC on creation. Revoked in the same
-- migration, per the standing rule.
revoke execute on function public.fn_kb_route_test_run(integer) from public;
revoke execute on function public.fn_kb_route_test_run(integer) from anon;
revoke execute on function public.fn_kb_route_test_run(integer) from authenticated;
