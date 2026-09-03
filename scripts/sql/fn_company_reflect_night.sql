-- THE NINE QUESTIONS, ASKED OF ONE NIGHT (3 Sep 2026).
--
-- fn_company_reflect answered the nine questions from `now() - interval '24 hours'` windows and
-- wrote the row for current_date. That is right for the night it runs on and useless for any night
-- it missed: the 16 Aug stand-down switched company_reflect_nightly off, it came back on 2 Sep, and
-- the nights in between are a hole in the company's memory that nothing could fill. A real
-- executive back from an outage writes up the days from the logs. This is that.
--
-- The per-night computation lives here; fn_company_reflect loops it over every unreflected night
-- of the last week and today. Every answer that CAN be read for the night itself is read from the
-- night's own window (institutional_memory.created_at, agent_runs.started_at,
-- outcome_record.closed_at, org_tasks.created_at/updated_at). The answers that are a snapshot of
-- present state (stale knowledge, the supply gap, competitors, the event backbone) cannot be
-- reconstructed for a past night from these tables, so on a late reflection they SAY they were
-- measured today — the row never pretends to be something written on the night. `reflected_at`
-- carries the clock time of the computation for the same reason. No model: nine deterministic
-- reads, exactly as before.
--
-- The supply.gap emission stays with the live night only: it is about the state now, and its 20h
-- dedupe is per run, not per night.

create or replace function public.fn_company_reflect_night(p_night date)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare a jsonb; n_concern int := 0; n_act int := 0;
  w_start timestamptz := (p_night::timestamp at time zone 'UTC');
  w_end   timestamptz := (p_night::timestamp at time zone 'UTC') + interval '1 day';
  v_live boolean := (p_night = current_date);
  v_late text := '';
  v_learned int; v_errors int; v_wrong int; v_dept text; v_improved text;
  v_stale int; v_missed int; v_comp int; v_worst text; v_bus text;
begin
  if p_night > current_date then
    raise exception 'fn_company_reflect_night: % is in the future; a night is reflected on when it has happened', p_night;
  end if;
  if not v_live then
    v_late := ' [state measured '||current_date||', reflecting late on '||p_night||']';
  end if;

  -- The night's own facts, from the night's own window.
  select count(*) into v_learned from institutional_memory where created_at >= w_start and created_at < w_end;
  select count(*) into v_errors  from agent_runs where status='error' and started_at >= w_start and started_at < w_end;
  select count(*) into v_wrong   from outcome_record where verdict='worse' and closed_at >= w_start and closed_at < w_end;
  select string_agg(actor, ', ') into v_improved from (
    select distinct actor from outcome_record where verdict='improved'
       and closed_at >= w_start - interval '6 days' and closed_at < w_end limit 3) x;
  -- The backlog as it stood at the end of that night: tasks that existed by then and were not
  -- done by then (a task done later still counts as open for that night).
  select dept_key into v_dept from org_tasks
   where created_at < w_end and (status <> 'done' or coalesce(updated_at, created_at) >= w_end)
   group by dept_key order by count(*) desc limit 1;

  -- Present-state answers. Honest for tonight; labelled when reflected late.
  select count(*) into v_stale from agent_knowledge where validation_status in ('stale','quarantined');
  select count(*) into v_missed from v_supply_gap where status='READY - not yet invited';
  select count(*) into v_comp from competitor;
  select name into v_worst from v_supply_gap where status like 'NO POOL%' limit 1;
  select coalesce(string_agg(event_type || ' ' || state, ', ' order by event_type),
                  'every subscribed event type is carrying traffic')
    into v_bus from v_event_backbone where state <> 'LIVE';

  a := jsonb_build_object(
    'what_did_i_learn', v_learned||' lesson(s) entered institutional memory on '||p_night||'.',
    'what_mistakes_did_i_make', v_errors||' agent run(s) errored on '||p_night||'.',
    'which_decisions_were_wrong', v_wrong||' graded improvement(s) made things worse and were flagged for reversal on '||p_night||'.',
    'which_departments_are_struggling', coalesce('Heaviest open backlog at the end of '||p_night||': '||v_dept,'No department was carrying an unusual backlog on '||p_night||'.'),
    'which_employees_improved', coalesce('Improvements that worked in the week to '||p_night||' came from: '||v_improved,'No graded improvement closed successfully in the week to '||p_night||'.'),
    'which_knowledge_became_outdated', v_stale||' knowledge item(s) are stale or quarantined.'||v_late,
    'which_opportunities_did_i_miss', v_missed||' category/categories have a viable supplier pool and no invitations sent.'||v_late,
    'which_competitor_became_stronger', v_comp||' competitor(s) tracked but 0 market signals captured, so this cannot be answered honestly yet.'||v_late,
    'is_my_nervous_system_carrying_traffic', 'Event types subscribed but not live: '||v_bus||v_late,
    'how_can_i_be_better_tomorrow', coalesce('Close the supply gap starting with '||v_worst,'Close the open KPI gaps before taking on new work.')||v_late,
    'reflected_at', now()::timestamptz(0)::text,
    'reflected_late', (not v_live));

  if v_errors > 10 then n_concern := n_concern + 1; end if;
  if v_wrong  > 0  then n_concern := n_concern + 1; end if;
  if v_stale  > 50 then n_concern := n_concern + 1; end if;

  -- xos-12. Emits through the bus; procurement's supply.gap subscription turns it into the task.
  -- Live night only — the gap is a present-state fact and the dedupe is on the emission clock.
  if v_live and v_missed > 0 then
    if not exists (select 1 from company_event
                    where event_type='supply.gap' and occurred_at > now()-interval '20 hours') then
      perform public.fn_emit('supply.gap', 'category', 'ready_uninvited', 'ceo',
                jsonb_build_object('categories_ready', v_missed,
                                   'detail', v_missed||' category(ies) hold a viable supplier pool with '
                                          || 'no invitations sent. Queue them, or record why not.'));
      n_act := n_act + 1;
    end if;
  end if;

  insert into company_reflection (reflected_on,answers,concerns,actions)
  values (p_night,a,n_concern,n_act)
  on conflict (reflected_on) do update set answers=excluded.answers, concerns=excluded.concerns, actions=excluded.actions;

  return jsonb_build_object('night',p_night,'late',(not v_live),'concerns',n_concern,'actions',n_act,'answers',a);
end $function$;

revoke execute on function public.fn_company_reflect_night(date) from public, anon, authenticated;
