-- THE CEO NOTE IS NOT MAILED TO THE FOUNDER: THE BRIEF IS HIS ONE DAILY MESSAGE.          seat: ceo · 10 Nov 2026 · ledger 1609
-- Assigned: ceo
--
-- Founder, ledger 1609 (10 Nov 2026): the CEO must hold a real strategy, "not report what the founder already knows", and not
-- keep e-mailing him; "no decision goes to him".
--
-- MEASURED BEFORE WRITING (production htdblwldjkcgjvmqkbeh, read-only, 10 Nov 2026):
--   * notifications to the founder (to_role founder/admin, his own inboxes or his mobile), 28 Oct - 10 Nov, by kind:
--     founder_brief 21 e-mails. 14 are the daily brief ("QuotesDone daily brief - <day>", to_role admin) and 7 are a second
--     e-mail the same day, "[Attention] CEO note: <day>" (to_role founder), written by fn_ceo_daily_run (ids 117540, 117603,
--     129419, 129423, 129428, 129431, 129448).
--   * What the note said: "too many of our emails bounced this week ... What we are doing: sending slows down and bad
--     addresses are removed before anything else goes out" (5, 6, 8, 9 Nov). Nothing slowed: invite_daily_cap stayed 20 and
--     every growth decision of those days reads applied = false (ceo_growth_action, the switch was off). "On hold by your
--     decision: the supplier campaign is off until you say the platform is ready" (5, 6 Nov) while invite_enabled had read
--     'true' since 28 Oct 03:51Z.
--   * The daily brief already carries the CEO's line ("The plan for tomorrow: The CEO's focus ...") and says "Nothing here
--     needs a reply."
--
-- WHAT THIS FILE CHANGES: fn_ceo_daily_run still builds the note's lines, keeps them on ceo_day.matters and returns the text
-- as 'note', but no longer hands it to customer_support for delivery to the founder; 'note_handoff_id' is returned null.
-- The safety action the note promised is now the CEO's own (the_ceo_applies_its_safety_side_growth_powers_without_waiting_for_a_switch.sql).
--
-- WHAT THIS DOES NOT CHANGE: the daily brief (founder_brief, fn_founder_brief), the weekly review, the monthly memo and
-- market report (each one he asked for by name, founder_mail_policy), founder_mail_policy itself, the day's priorities,
-- directives and verdicts, or any row already sent.
--
-- Prevented by: scripts/checks/the_ceo_year_one_plan_follows_the_founder_targets.test.mjs (a day with misses must hand the
-- founder no note) and scripts/checks/the_founder_reads_a_plain_ceo_note_and_held_targets_are_paused.test.mjs (the text it
-- still builds carries no codes).
-- Apply at merge: node scripts/apply_sql.mjs scripts/sql/the_ceo_note_is_not_mailed_to_the_founder_the_brief_is_his_one_daily_message.sql --apply --ddl --seat ceo

CREATE OR REPLACE FUNCTION public.fn_ceo_daily_run(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_day date := (p_at at time zone 'Asia/Dubai')::date; v_m0 date := date_trunc('month', p_at at time zone 'Asia/Dubai')::date;
  v_from timestamptz := v_m0::timestamp at time zone 'Asia/Dubai';
  v_verdict jsonb; v_status jsonb; h record; n_stuck_new int := 0; v_stuck jsonb := '[]'::jsonb; v_prio jsonb := '{}'::jsonb;
  v_signals jsonb; v_matters text[] := '{}'; v_lines text[] := '{}'; v_note bigint; s text; v_m jsonb; v_first text; v_task bigint;
  v_body text; v_dir jsonb; v_d public.ceo_directive; v_behind text; v_hold text;
begin
  v_verdict := public.fn_ceo_target_daily_verdict(p_at);
  v_status := public.fn_ceo_year_plan_status(p_at);

  for h in select a.id, a.agent, a.detail->>'type' as type, a.detail->>'from' as from_seat, a.created_at
             from public.agent_actions a
             left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'replied_at' is null
              and a.created_at < p_at - coalesce(k.reply_within * 2, interval '1 day') loop
    v_stuck := v_stuck || jsonb_build_object('handoff_id', h.id, 'seat', h.agent, 'type', h.type, 'from', h.from_seat, 'since', h.created_at);
    if not exists (select 1 from public.ceo_task where title = format('Stuck handoff #%s', h.id)) then
      v_task := public.fn_ceo_task_open(format('Stuck handoff #%s', h.id),
        format(E'%s from %s to %s has waited since %s with no answer. The CEO re-runs it (fn_seat_handoff_act) and, if it fails again, the failure is on this task.',
               h.type, h.from_seat, h.agent, h.created_at));
      begin
        perform public.fn_seat_handoff_act(h.id);
        update public.ceo_task set state = 'done', closed_at = now(), evidence = 'Re-run on ' || v_day || ': the seat answered.'
         where task_id = v_task and exists (select 1 from public.agent_actions where id = h.id and (status = 'done' or detail ? 'replied_at'));
      exception when others then
        update public.ceo_task set state = 'blocked', blocked_reason = left('Re-run failed: ' || sqlerrm, 1000) where task_id = v_task;
      end;
      n_stuck_new := n_stuck_new + 1;
    end if;
  end loop;

  v_signals := jsonb_build_object(
    'stranded_registrations', public.fn_ceo_plan_measure('stranded_submissions', p_at - interval '1 day', p_at),
    'bounce_pct_7d', public.fn_ceo_plan_measure('bounce_pct_7d', p_at - interval '7 days', p_at),
    'requests_unquoted_3d', (select count(*) from public.inquiries i join public.customers c on c.id = i.customer_id
                               where i.parent_inquiry_id is null and i.created_at < p_at - interval '3 days' and i.created_at > p_at - interval '30 days'
                                 and not exists (select 1 from public.quotes q where q.inquiry_id = i.id)
                                 and coalesce(i.provenance->>'source', '') not in ('demo_factory', 'e2e')
                                 and not (coalesce(c.is_demo, false) or coalesce(c.full_name, '') ilike 'ZZ DEMO%' or coalesce(c.email, '') ilike '%@example.invalid')),
    'findings_open', (select count(*) from public.it_engineer_finding where closed_at is null),
    'findings_new_today', (select count(*) from public.it_engineer_finding where closed_at is null and started_at > p_at - interval '1 day'),
    'fee_month_aed', public.fn_ambition_measure('fee_aed', v_from, p_at),
    'costs_month_aed', public.fn_ambition_measure('costs_aed', v_from, p_at),
    'cost_ceiling_month_aed', (select cost_ceiling_aed from public.ceo_year_plan where month = v_m0),
    'stale_tasks', (select count(*) from public.ceo_task where state in ('open', 'working', 'blocked') and created_at < p_at - interval '14 days'));

  v_dir := public.fn_ceo_directive_run(p_at);

  -- the day's priorities per seat (internal record: ceo_day.priorities keeps the directive detail)
  foreach s in array array['sales_engineer', 'customer_support', 'marketing', 'accountant', 'it_engineer'] loop
    select e into v_m from jsonb_array_elements(v_status->'metrics') e
     where e->>'owner_seat' = s and e->>'status' in ('miss', 'within_tolerance')
     order by (e->>'status' = 'miss') desc, abs(coalesce((e->>'gap_pct')::numeric, 0)) desc limit 1;
    v_d := null;
    select * into v_d from public.ceo_directive d where d.seat = s and d.status = 'open' order by d.deadline, d.id limit 1;
    v_first := case
      when v_d.id is not null then format('Directive #%s, due %s: %s Done when %s', v_d.id,
        to_char(v_d.deadline at time zone 'Asia/Dubai', 'DD Mon HH24:MI'), v_d.instruction, v_d.done_when)
      when v_m is not null then format('Recover %s: %s against %s today (%s).', v_m->>'metric', coalesce(v_m->>'actual', '?'), v_m->>'expected', v_m->>'status')
      when exists (select 1 from jsonb_array_elements(v_stuck) e where e->>'seat' = s) then 'Answer the handoffs waiting past their reply time.'
      when exists (select 1 from public.ceo_improvement i where i.seat = s and i.status = 'assigned') then
        (select format('Improvement #%s: %s', i.id, left(i.proposal, 300)) from public.ceo_improvement i
          where i.seat = s and i.status = 'assigned' order by i.id limit 1)
      else 'Hold the path: every target of the month is on track.' end;
    v_prio := v_prio || jsonb_build_object(s, jsonb_build_object('first', v_first,
      'misses', (select coalesce(jsonb_agg(e->>'metric'), '[]'::jsonb) from jsonb_array_elements(v_status->'metrics') e where e->>'owner_seat' = s and e->>'status' = 'miss'),
      'directive_id', v_d.id,
      'stuck_handoffs', (select count(*) from jsonb_array_elements(v_stuck) e where e->>'seat' = s),
      'improvements_open', (select count(*) from public.ceo_improvement i where i.seat = s and i.status in ('open', 'assigned'))));
  end loop;

  -- What matters enough for the founder: kept as before in ceo_day.matters (internal), and written to him as a
  -- short note - one line each for what happened, why, and what is being done. 19 Oct 2026: no ids, no codes, no counts.
  select regexp_replace(string_agg(distinct public.fn_target_words(e->>'metric'), ', '), ', ([^,]*)$', ' and \1')
    into v_behind from jsonb_array_elements(v_status->'metrics') e where e->>'status' = 'miss';
  if coalesce((v_verdict->>'tasks_opened')::int, 0) > 0 then
    v_matters := v_matters || format('%s target(s) fell behind the path today', v_verdict->>'tasks_opened');
    v_lines := v_lines || ('- What happened: we slipped behind plan on ' || coalesce(v_behind, 'one of our targets') || '.'
      || E'\n  Why: the step that feeds it is not working well enough yet.'
      || E'\n  What we are doing: the team that owns it has a deadline this week to find and fix that step, and I check it every morning.');
  end if;
  if n_stuck_new > 0 then
    v_matters := v_matters || format('%s handoff(s) were stuck and re-run', n_stuck_new);
    v_lines := v_lines || ('- What happened: some work passed between teams waited too long for an answer.'
      || E'\n  Why: the team receiving it did not reply in time.'
      || E'\n  What we are doing: I restarted each one today; anything still stuck stays on my list until it moves.');
  end if;
  if coalesce((v_signals->>'stranded_registrations')::numeric, 0) > 0 then
    v_matters := v_matters || format('%s supplier registration(s) waited over 24 hours', v_signals->>'stranded_registrations');
    v_lines := v_lines || ('- What happened: supplier sign-ups waited more than a day for review.'
      || E'\n  Why: reviews did not keep up.'
      || E'\n  What we are doing: the sales team reviews them first thing tomorrow and I follow up.');
  end if;
  if coalesce((v_signals->>'bounce_pct_7d')::numeric, 0) >= 5 then
    v_matters := v_matters || format('email bounces at %s %% over 7 days', v_signals->>'bounce_pct_7d');
    v_lines := v_lines || ('- What happened: too many of our emails bounced this week.'
      || E'\n  Why: some addresses on our lists are no longer valid.'
      || E'\n  What we are doing: sending slows down and bad addresses are removed before anything else goes out.');
  end if;
  if coalesce((v_signals->>'requests_unquoted_3d')::int, 0) > 0 then
    v_matters := v_matters || format('%s request(s) have no quote after 3 days', v_signals->>'requests_unquoted_3d');
    v_lines := v_lines || ('- What happened: some customer requests have no quote after three days.'
      || E'\n  Why: not enough matching suppliers answered.'
      || E'\n  What we are doing: the sales team is reaching more suppliers for each one.');
  end if;
  if coalesce((v_signals->>'costs_month_aed')::numeric, 0) > coalesce((v_signals->>'cost_ceiling_month_aed')::numeric, 1e12) then
    v_matters := v_matters || format('costs this month AED %s are over the ceiling of AED %s', round((v_signals->>'costs_month_aed')::numeric), v_signals->>'cost_ceiling_month_aed');
    v_lines := v_lines || ('- What happened: this month''s costs are above the budget we set (AED '
      || to_char(round((v_signals->>'costs_month_aed')::numeric), 'FM999,999,990') || ' against AED '
      || to_char((v_signals->>'cost_ceiling_month_aed')::numeric, 'FM999,999,990') || ').'
      || E'\n  Why: spending ran ahead of plan.'
      || E'\n  What we are doing: finance is cutting what is not needed, and I review it daily.');
  end if;

  insert into public.ceo_day (day, facts, priorities, matters)
  values (v_day, jsonb_build_object('verdict', v_verdict, 'plan', v_status, 'signals', v_signals, 'stuck', v_stuck), v_prio, v_matters)
  on conflict (day) do update set facts = excluded.facts, priorities = excluded.priorities,
    matters = coalesce((select array_agg(distinct m) from unnest(ceo_day.matters || excluded.matters) m), '{}'), updated_at = now();

  -- 10 NOV 2026 (ceo, ledger 1609): THE NOTE IS NO LONGER MAILED TO THE FOUNDER. It was a second daily e-mail under the
  -- founder_brief kind (7 of the 21 founder_brief rows of 28 Oct - 10 Nov), it told him what the company already knew, and on
  -- 5-9 Nov it said "sending slows down" while the brake that would have slowed it was held behind a switch. The text is
  -- still built, returned and kept with the day (ceo_day.matters), so the brief and the weekly review can read it; the
  -- founder hears from the CEO through the brief he asked for, and the CEO acts on what it found instead of writing to him.
  v_note := null;
  if cardinality(v_lines) > 0 then
    v_hold := public.fn_founder_hold_line();
    v_body := to_char(v_day, 'FMDay DD Mon') || E'\n\n' || array_to_string(v_lines, E'\n\n')
      || coalesce(E'\n\nOn hold by your decision: ' || v_hold, '') || E'\n\nCEO';
  end if;
  return jsonb_build_object('day', v_day, 'misses', v_verdict->'misses', 'stuck_new', n_stuck_new, 'matters', to_jsonb(v_matters),
                            'note_handoff_id', v_note, 'note', v_body, 'priorities', v_prio, 'directives', v_dir);
end $function$;
