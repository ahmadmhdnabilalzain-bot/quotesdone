-- PROBE of the_ceos_weekly_plan_is_retried_and_fits_the_gateway_deadline.sql. Seat: ceo (agent: L1_CEO). 16 Nov 2026.
-- LOCAL ONLY (a Postgres 16 copy). It always raises CHK<<...>>, so every plan it writes rolls back; its world is its own
-- (qd.duty_fixtures = 'on'). Each case names the line that fails on production's bodies before this file.
do $probe$
declare v_fail text := ''; v_id bigint; v_r jsonb; v_at timestamptz := now(); v_today date := (now() at time zone 'Asia/Dubai')::date;
        v_cut text := 'gateway_http_502:gateway_deadline'; v_n int;
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  update public.decision_policy set value = value || '{"week_aed_cap": 8, "week_calls_cap": 14}'::jsonb where key = 'ceo_planning_loop';

  -- 1. THE SHAPE OF ID 12: asked, one call cut by our clock, asked_at 18 s into the tick two hours ago. The hourly tick at
  --    :30:0x must offer it (before: asked_at < p_at - 2 h was 18 s short, so the retry waited a third tick)
  insert into public.ceo_plan_week (kind, period, status, task_class, attempts, asked_at, error, pack)
  values ('weekly', v_today, 'asked', 'ceo_strategic_planning', 1, v_at - interval '2 hours' + interval '18 seconds', v_cut, '{}') returning id into v_id;
  v_r := public.fn_ceo_plan_handover(v_at);
  if not coalesce((v_r->>'call_model')::boolean, false) or (v_r->>'plan_id')::bigint <> v_id then v_fail := v_fail || '1: the tick two hours on did not offer the plan: ' || v_r::text || '; '; end if;
  update public.ceo_plan_week set asked_at = v_at - interval '100 minutes' where id = v_id;
  if coalesce((public.fn_ceo_plan_handover(v_at)->>'call_model')::boolean, true) then v_fail := v_fail || '1: a plan asked 100 minutes ago was offered again; '; end if;

  -- 2. A SECOND CUT IS ASKED AGAIN, A THIRD CALL IS THE LAST (fn_ceo_plan_file; before: the second failure held the plan)
  update public.ceo_plan_week set asked_at = v_at - interval '3 hours' where id = v_id;
  v_r := public.fn_ceo_plan_request(v_id);                                     -- attempts 2
  perform public.fn_ceo_plan_file(v_id, null, null, v_cut);
  if (select status || '/' || attempts from public.ceo_plan_week where id = v_id) <> 'asked/2' then
    v_fail := v_fail || '2: a second answer cut by our clock was not asked again: ' || (select status || '/' || attempts from public.ceo_plan_week where id = v_id) || '; '; end if;
  update public.ceo_plan_week set asked_at = v_at - interval '3 hours' where id = v_id;
  if not coalesce((public.fn_ceo_plan_handover(v_at)->>'call_model')::boolean, false) then v_fail := v_fail || '2: the third call for a cut answer was not offered; '; end if;
  v_r := public.fn_ceo_plan_request(v_id);                                     -- attempts 3
  perform public.fn_ceo_plan_file(v_id, null, null, 'client_timeout_143000ms');
  if (select status from public.ceo_plan_week where id = v_id) <> 'held' then v_fail := v_fail || '2: a fourth call was left open; '; end if;
  if coalesce((public.fn_ceo_plan_request(v_id)->>'ok')::boolean, true) then v_fail := v_fail || '2: a held plan was handed out; '; end if;
  if (public.fn_ceo_plan_reopen_cut(v_at)->'reopened') @> to_jsonb(v_id) then v_fail := v_fail || '2: a plan with three calls was reopened; '; end if;

  -- 3. ANY OTHER FAILURE KEEPS ITS RULE: once more, then held, and never reopened
  insert into public.ceo_plan_week (kind, period, status, task_class, attempts, asked_at, pack)
  values ('daily', v_today, 'asked', 'routine_employee_reasoning', 1, v_at - interval '3 hours', '{}') returning id into v_id;
  perform public.fn_ceo_plan_file(v_id, null, null, 'the answer was not a JSON object');
  if (select status from public.ceo_plan_week where id = v_id) <> 'asked' then v_fail := v_fail || '3: a first broken answer was not asked once more; '; end if;
  update public.ceo_plan_week set attempts = 2 where id = v_id;
  perform public.fn_ceo_plan_file(v_id, null, null, 'the answer was not a JSON object');
  if (select status from public.ceo_plan_week where id = v_id) <> 'held' then v_fail := v_fail || '3: a second broken answer was not held; '; end if;
  if (public.fn_ceo_plan_reopen_cut(v_at)->'reopened') @> to_jsonb(v_id) then v_fail := v_fail || '3: a plan held for a broken answer was reopened; '; end if;
  delete from public.ceo_plan_week where id = v_id;

  -- 4. A PLAN HELD BY OUR CLOCK (the old body held the second cut) IS REOPENED BY THE DUTY, ONCE, INSIDE ITS WINDOW ONLY
  delete from public.ceo_plan_week where world = 'demo' and kind = 'weekly' and period = v_today;
  insert into public.ceo_plan_week (kind, period, status, task_class, attempts, asked_at, error, pack)
  values ('weekly', v_today, 'held', 'ceo_strategic_planning', 2, v_at - interval '3 hours', v_cut, '{}') returning id into v_id;
  insert into public.ceo_plan_week (kind, period, status, task_class, attempts, asked_at, error, pack)
  values ('weekly', v_today - 14, 'held', 'ceo_strategic_planning', 2, v_at - interval '14 days', v_cut, '{}');
  v_r := public.fn_ceo_plan_reopen_cut(v_at);
  if jsonb_array_length(v_r->'reopened') <> 1 or not (v_r->'reopened') @> to_jsonb(v_id)
     or (select status from public.ceo_plan_week where id = v_id) <> 'asked' then v_fail := v_fail || '4: the cut plan was not reopened alone: ' || v_r::text || '; '; end if;
  v_r := public.fn_ceo_plan_handover(v_at);
  if not coalesce((v_r->>'call_model')::boolean, false) or (v_r->>'plan_id')::bigint <> v_id then v_fail := v_fail || '4: the reopened plan was not offered: ' || v_r::text || '; '; end if;
  update public.ceo_plan_week set status = 'held' where id = v_id;   -- cut again (as fn_ceo_plan_file would at attempts 3: held)
  if jsonb_array_length(public.fn_ceo_plan_reopen_cut(v_at)->'reopened') <> 0 then v_fail := v_fail || '4: a plan was reopened twice; '; end if;
  if (select prosrc from pg_proc where oid = 'public.fn_ceo_planning_loop_tick()'::regprocedure) not like '%fn_ceo_plan_reopen_cut(now())%'
    then v_fail := v_fail || '4: the duty does not reopen; '; end if;
  if (select prosrc from pg_proc where oid = 'public.fn_ceo_plan_handover(timestamptz)'::regprocedure) ~ 'update |insert into|fn_ceo_planning_pack'
    then v_fail := v_fail || '4: the hand-over writes or builds; '; end if;

  -- 5. THE CAPS STILL BIND A RETRY
  update public.ceo_plan_week set status = 'asked', attempts = 1, asked_at = v_at - interval '3 hours', error = v_cut where id = v_id;
  update public.decision_policy set value = value || jsonb_build_object('week_calls_cap', 0) where key = 'ceo_planning_loop';
  v_r := public.fn_ceo_plan_handover(v_at);
  if coalesce((v_r->>'call_model')::boolean, true) or (select status from public.ceo_plan_week where id = v_id) <> 'held' then v_fail := v_fail || '5: a retry ran past the call cap: ' || v_r::text || '; '; end if;

  if (public.fn_ceo_plan_contract('weekly')->>'system') not like '%at most 1,500 words%' or (public.fn_ceo_plan_contract('weekly')->>'system') not like '%THE TARGET is 300 to 400%'
    then v_fail := v_fail || '5: the contract does not bound the answer or lost the target; '; end if;

  -- 6. CLOSED: nobody outside the service reaches the new routines
  if has_function_privilege('anon', 'public.fn_ceo_plan_reopen_cut(timestamptz)', 'execute') or has_function_privilege('authenticated', 'public.fn_ceo_plan_cut_by_our_clock(text)', 'execute')
    then v_fail := v_fail || '6: a routine is open to anon or authenticated; '; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK: a cut answer is retried at the next tick, three calls at most, reopened once, inside the caps' else 'PROBE FAILED: ' || v_fail end;
end $probe$;
