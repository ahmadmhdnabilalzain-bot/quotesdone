-- THE CEO DECISION RULES THAT HAVE NO INSTRUMENT SAY SO IN OK.
--
-- Assigned: ceo (the rules), it_engineer (the audit that found it). 22 Sep 2026, SEATS-07.
--
-- ══ MEASURED, htdblwldjkcgjvmqkbeh, 22 Sep 2026 (fn_ceo_decisions_evaluate(p_dry_run => true),
--    run inside an aborted transaction) ═══════════════════════════════════════════════════════
--   The evaluator returned ok:true with TWO active rules in state 'not_instrumented' —
--   'risk_owner' and 'spend_against_constraint' — although the routine's own comment says
--   "Returns ok:false with error when an ACTIVE rule has no branch: that is precisely the state
--   that left ten rules silent for two weeks". A branch that says "no instrument" is the same
--   silence as no branch at all: the CEO is recorded as having evaluated a rule it cannot read.
--   'binding_constraint' compared the feasibility verdict's binding stage with the last LOGGED
--   binding_constraint decision, not with the stage the company is actually working. The stage
--   being worked lives in public.ceo_plan.stage (id 5, 22 Sep 2026, stage 'invitations'); the last
--   target_verdict (7 Sep 2026) has binding_stage null, so nothing could ever be compared at all.
--
-- ══ WHAT THIS FILE CHANGES (fn_ceo_decisions_evaluate only; everything else is byte-identical to
--    the_weekly_report_arrives_and_the_rules_decide.sql) ═══════════════════════════════════════
--   1. binding_constraint reads the CEO's own plan: it fires when the feasibility verdict names a
--      binding stage that differs from ceo_plan.stage, and says plainly when the verdict names
--      none (nothing to compare) or when no plan has been written yet.
--   2. risk_owner is INSTRUMENTED from public.risk_register (19 rows; columns risk, owner_agent,
--      mitigation, status, review_due): an open risk with no owner, an owner that is not a live
--      seat, or a review date already past, is one firing each, outcome needs_judgement — the CEO
--      names the owner and the test date. The half the register cannot answer is stated in the
--      rule's own detail rather than assumed: NOTHING records when a mitigation was last actually
--      TESTED, so this rule fires on ownership and review date only.
--   3. spend_against_constraint stays not_instrumented — no table attributes spend to a funnel
--      stage (checked 22 Sep: department_budget, budgets, budget_lines, it_spend_daily,
--      marketing_ad_spend_day, accountant_spend_report — none carries a stage) — and it now makes
--      the evaluator answer ok:false naming itself, which is what the routine always claimed to do.
--   4. ok is false when any active rule has no evaluator OR no instrument, and the two are reported
--      separately so the remedy is obvious: write a branch, or instrument the measure (or, if the
--      CEO no longer decides it, set ceo_decision.active = false — a rule nobody can read is not
--      allowed to sit quietly in the middle).
--
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_decision_rules_that_have_no_instrument_say_so_in_ok.sql --apply --ddl

create or replace function public.fn_ceo_decisions_evaluate(p_dry_run boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  d record; x record;
  v_out jsonb := '[]'::jsonb; v_fired int := 0; v_written int := 0; v_missing text[] := '{}';
  v_blind text[] := '{}';   -- active rules whose MEASURE has no instrument (22 Sep 2026, SEATS-07)
  v_state text; v_detail text; v_reading text;
  v_day date := ((now() at time zone 'Asia/Dubai')::date - 1);   -- the last COMPLETE Dubai day
  v_hold timestamptz := timestamptz '2026-08-15 02:51:33.108565+00';
  v_n bigint; v_m numeric; v_rate numeric; v_prev text; v_ev jsonb;
  v_rows jsonb;   -- [{key, decision, outcome, evidence}] this rule wants written
begin
  for d in select * from public.ceo_decision where active order by decision_key loop
    v_rows := '[]'::jsonb; v_state := 'quiet'; v_detail := null; v_reading := null;
    if d.measure_sql is not null then
      begin execute d.measure_sql into v_reading;
      exception when others then v_reading := 'INSTRUMENT FAILED -- '||sqlerrm; end;
    end if;

    case d.decision_key
    when 'target_is_reachable' then
      -- "Any weekly feasibility run whose verdict is not REACHABLE, or any week the required run rate
      -- rises above twice the highest ever measured." One firing per feasibility run.
      for x in select v.*, c.contract_key,
                      (select max(v2.current_run_rate) from public.target_verdict v2 where v2.contract_id = c.id) as best_rate
                 from public.target_contract c
                 join lateral (select * from public.target_verdict v where v.contract_id = c.id order by v.run_at desc limit 1) v on true
                where c.status = 'active' and c.metric_unit = 'AED'
      loop
        if x.verdict <> 'REACHABLE' or (x.best_rate > 0 and x.required_run_rate > 2 * x.best_rate) then
          v_rows := v_rows || jsonb_build_object('key', 'target_is_reachable:verdict:'||x.id, 'outcome', 'decided',
            'decision', format('The AED 1,000,000 target is NOT reachable on the evidence (verdict %s of %s). What must change: %s',
                               x.verdict, to_char(x.run_at at time zone 'Asia/Dubai','DD Mon YYYY'),
                               coalesce(array_to_string(x.what_must_change, ' '), x.verdict_reason)),
            'evidence', jsonb_build_object('contract', x.contract_key, 'verdict_id', x.id, 'verdict', x.verdict,
              'run_at', x.run_at, 'verdict_reason', x.verdict_reason, 'binding_stage', x.binding_stage,
              'required_run_rate', x.required_run_rate, 'highest_measured_run_rate', x.best_rate,
              'measured_rate_count', x.measured_rate_count, 'assumed_rate_count', x.assumed_rate_count));
        end if;
      end loop;

    when 'binding_constraint' then
      -- "Any week the binding stage named by the feasibility run differs from the one currently being
      -- worked." The one being worked is the stage of the last logged binding_constraint decision.
      select v.* into x from public.target_verdict v join public.target_contract c on c.id = v.contract_id
       where c.status = 'active' and v.binding_stage is not null order by v.run_at desc limit 1;
      if not found then
        v_detail := 'no feasibility run has named a binding stage (target_verdict.binding_stage is null on every run), so there is nothing to compare the worked stage with';
      else
        -- THE STAGE BEING WORKED IS THE PLAN'S, NOT THE LAST LOG LINE'S (22 Sep 2026). The company
        -- works whatever public.ceo_plan.stage names — fn_ceo_plan_tick writes it every Dubai day
        -- and directs the seats from it. Reading the last logged decision instead compared the
        -- verdict with the evaluator's own previous output, which is a loop, not a measurement.
        select p.stage into v_prev from public.ceo_plan p order by p.plan_date desc, p.id desc limit 1;
        if v_prev is null then
          v_detail := 'no CEO plan has named a stage yet (public.ceo_plan is empty), so the stage being worked is unknown';
        end if;
        if v_prev is distinct from x.binding_stage then
          v_rows := jsonb_build_array(jsonb_build_object('key', 'binding_constraint:verdict:'||x.id, 'outcome', 'decided',
            'decision', format('Work the %s stage next: the feasibility run names it as the binding constraint%s.',
                               x.binding_stage, case when v_prev is null then ' and no plan names a stage being worked' else ', and the CEO plan is working '||v_prev end),
            'evidence', jsonb_build_object('verdict_id', x.id, 'run_at', x.run_at, 'binding_stage', x.binding_stage,
              'binding_reason', x.binding_reason, 'stage_being_worked', v_prev, 'stage_read_from', 'ceo_plan.stage')));
        end if;
      end if;

    when 'supplier_admission' then
      -- "A registration arrives with all six present." Fixtures never produce a company decision.
      for x in select l.id, l.company_name, l.verified, l.owner_email_verified, l.owner_phone_verified
                 from public.leads l
                where l.claimed and coalesce(l.company_name,'') not ilike 'ZZ DEMO%'
                  and coalesce(l.email,'') !~* '@example[.]invalid$'
                  and cardinality(public.fn_supplier_mandatory_six_for(l.id)) = 0
      loop
        v_rows := v_rows || jsonb_build_object(
          'key', 'supplier_admission:lead:'||x.id||':'||case when x.owner_email_verified and x.owner_phone_verified then 'admit' else 'hold' end,
          'outcome', 'decided',
          'decision', case when x.owner_email_verified and x.owner_phone_verified
                           then format('Admit %s: all six mandatory fields present, email and UAE mobile confirmed by OTP.', x.company_name)
                           else format('Hold %s: the six are present but the %s is not OTP-confirmed.', x.company_name,
                                       case when not coalesce(x.owner_email_verified,false) then 'email' else 'UAE mobile' end) end,
          'evidence', jsonb_build_object('lead_id', x.id, 'mandatory_missing', '[]'::jsonb,
            'owner_email_verified', x.owner_email_verified, 'owner_phone_verified', x.owner_phone_verified,
            'verified_flag_now', x.verified));
      end loop;

    when 'report_to_founder' then
      -- "Every reporting cadence." Fires once per weekly report the founder actually received.
      for x in select * from public.ceo_weekly_report where founder_submitted_at is not null
                  and report_key like 'quotesdone:%'
                order by week_start desc limit 4
      loop
        select count(*) into v_n from public.ceo_decision_log l
         where l.decided_at > x.founder_submitted_at - interval '7 days' and l.decided_at <= x.founder_submitted_at;
        v_rows := v_rows || jsonb_build_object('key', 'report_to_founder:'||x.report_key||':r'||x.revision, 'outcome', 'decided',
          'decision', format('Reported to the founder: "%s". %s decision(s) taken alone in the week before it; none escalated.', x.subject, v_n),
          'evidence', jsonb_build_object('report_id', x.id, 'report_key', x.report_key, 'notification_id', x.notification_id,
            'delivered_at', x.founder_submitted_at, 'pdf', x.pdf_bucket||'/'||x.pdf_path, 'decisions_alone', v_n, 'escalated', 0));
      end loop;

    when 'channel_volume' then
      -- "Any bounce rate above 5 per cent." Bounces = email_suppressions added for a bounce in the last 7
      -- days, over emails sent in the same window. The "proposal to send more" half has no instrument.
      select count(*) into v_n from public.notifications
       where channel = 'email' and status = 'sent' and sent_at > now() - interval '7 days';
      select count(*) into v_m from public.email_suppressions
       where reason ilike '%bounce%' and created_at > now() - interval '7 days';
      v_rate := case when v_n > 0 then round(100.0 * v_m / v_n, 2) end;
      v_detail := format('bounce %s%% (%s bounced / %s sent, 7 days); proposals to raise volume are not instrumented',
                         coalesce(v_rate::text,'n/a'), v_m, v_n);
      if v_rate > 5 then
        v_rows := jsonb_build_array(jsonb_build_object('key', 'channel_volume:'||v_day, 'outcome', 'decided',
          'decision', format('No outreach channel is raised above its standing ceiling: the 7-day bounce rate is %s%%, above the 5%% limit.', v_rate),
          'evidence', jsonb_build_object('bounced_7d', v_m, 'sent_7d', v_n, 'bounce_pct', v_rate, 'ceilings', v_reading)));
      end if;

    when 'refund' then
      -- "A buyer asks for a refund, or a reveal is disputed." Weighing a buyer's stated reason is
      -- judgement; the CEO's refund review decides it. Until that review has an outcome, say so.
      for x in select t.id, t.refund_status,
                      (select rv.outcome from public.refund_ceo_review rv where rv.transaction_id = t.id
                        order by rv.created_at desc limit 1) as review_outcome
                 from public.transactions t where coalesce(t.refund_status,'') <> ''
      loop
        v_rows := v_rows || jsonb_build_object(
          'key', 'refund:tx:'||x.id||':'||coalesce(x.review_outcome,'open'),
          'outcome', case when x.review_outcome is null then 'needs_judgement' else 'decided' end,
          'decision', case when x.review_outcome is null
                           then format('Refund on transaction %s needs judgement: no CEO refund review has reached an outcome.', x.id)
                           else format('Refund on transaction %s: %s (the CEO refund review).', x.id, x.review_outcome) end,
          'evidence', jsonb_build_object('transaction_id', x.id, 'refund_status', x.refund_status, 'review_outcome', x.review_outcome));
      end loop;

    when 'paid_inference' then
      -- "Any request that needs a paid model while the hold is on." ai_gateway marks those rows HELD.
      -- One firing per complete Dubai day. A charge during the hold is not a rule's to excuse.
      select coalesce(sum(n), 0), coalesce(jsonb_object_agg(fn, n), '{}'::jsonb) into v_n, v_ev from (
        select coalesce(fn, '(unnamed)') fn, count(*) n from public.ai_cost_log
         where model_selected_because like '%HELD:%'
           and occurred_at >= (v_day::timestamp at time zone 'Asia/Dubai')
           and occurred_at <  ((v_day + 1)::timestamp at time zone 'Asia/Dubai')
         group by fn) s;
      select coalesce(sum(cost_aed),0) into v_m from public.ai_cost_log where occurred_at > v_hold;
      if v_n > 0 or v_m > 0 then
        v_rows := jsonb_build_array(jsonb_build_object('key', 'paid_inference:'||v_day,
          'outcome', case when v_m > 0 then 'needs_judgement' else 'decided' end,
          'decision', case when v_m > 0
            then format('Paid inference was charged during the hold (AED %s since 15 Aug). The hold is the founder''s constraint; this is not excused by a rule.', v_m)
            else format('Paid inference refused on %s for %s request(s) that asked for a model; each was held and answered without one. Cost since the hold: AED 0.', v_day, v_n) end,
          'evidence', jsonb_build_object('day', v_day, 'held_requests', v_n, 'held_by_function', v_ev, 'cost_since_hold_aed', v_m)));
      end if;

    when 'risk_owner' then
      -- "A risk is raised, or a mitigation passes its review date untested." public.risk_register
      -- holds the live risks (risk, owner_agent, mitigation, status, review_due). What it CANNOT
      -- answer is when a mitigation was last actually tested — nothing records a test — so this
      -- rule fires on the two halves that ARE measurable and says so in its detail.
      for x in select rr.id, rr.risk, rr.owner_agent, rr.mitigation, rr.review_due, rr.dept_key,
                      (rr.owner_agent is null or not exists (select 1 from public.org_agents oa
                         where oa.agent_key = rr.owner_agent and oa.active)) as no_live_owner,
                      (rr.review_due is not null and rr.review_due < current_date) as review_past
                 from public.risk_register rr where rr.status = 'open'
      loop
        continue when not (x.no_live_owner or x.review_past);
        v_rows := v_rows || jsonb_build_object(
          'key', 'risk_owner:risk:'||x.id||':'||case when x.no_live_owner then 'unowned' else 'review_past' end,
          'outcome', 'needs_judgement',
          'decision', case when x.no_live_owner
            then format('Risk %s ("%s") has no live owner (%s): the CEO must name the seat that owns it and the date its mitigation is tested.',
                        x.id, left(x.risk, 90), coalesce(x.owner_agent, 'nobody named'))
            else format('Risk %s ("%s") passed its review date (%s) with no recorded test: the CEO must re-date it or retire it.',
                        x.id, left(x.risk, 90), x.review_due) end,
          'evidence', jsonb_build_object('risk_id', x.id, 'risk', x.risk, 'owner_agent', x.owner_agent,
            'owner_is_a_live_seat', not x.no_live_owner, 'mitigation', x.mitigation, 'review_due', x.review_due,
            'department', x.dept_key,
            'not_measured', 'no table records when a mitigation was last actually tested; this firing reads ownership and review date only'));
      end loop;
      v_detail := 'read from public.risk_register (open risks: owner not a live seat, or review_due past). '
                  || 'NOT measured: when a mitigation was last actually tested — nothing records it.';

    when 'spend_against_constraint' then
      -- No instrument, and the evaluator now SAYS SO in ok (22 Sep 2026). Checked this day:
      -- department_budget, budgets, budget_lines, budget_vs_actual, it_spend_daily,
      -- marketing_ad_spend_day, accountant_spend_report — not one attributes spend to a funnel
      -- stage, so "did the money go to the binding constraint" cannot be answered from any row.
      v_state := 'not_instrumented'; v_blind := v_blind || d.decision_key;
      v_detail := d.measure || ' [22 Sep 2026: no table attributes spend to a funnel stage. Either add the attribution or set this rule inactive — it is not evaluated today.]';

    when 'structure' then
      v_state := 'founder_specified'; v_detail := 'the founder specifies the seats; the CEO decides nothing here';

    when 'seat_directive', 'constraint_stalled', 'plan_review' then
      -- 22 Sep 2026 (ceo): decided by the daily plan on its own heartbeat step (fn_ceo_plan_tick, step
      -- ceoPlan), which writes these rows with their evidence. Named here so they are not no_evaluator.
      v_state := 'decided_by_the_plan'; v_detail := 'fn_ceo_plan_tick (the_ceo_plans_every_day_and_directs_the_seats.sql)';

    else
      v_state := 'no_evaluator'; v_missing := v_missing || d.decision_key;
    end case;

    if jsonb_array_length(v_rows) > 0 then
      v_state := 'fired'; v_fired := v_fired + jsonb_array_length(v_rows);
      if not p_dry_run then
        with ins as (
          insert into public.ceo_decision_log (decision_key, the_decision, evidence, reading_before, escalated_to_founder, outcome, dedupe_key)
          select d.decision_key, e->>'decision', (e->'evidence') || jsonb_build_object('rule', d.trigger_condition),
                 v_reading, false, e->>'outcome', e->>'key'
            from jsonb_array_elements(v_rows) e
          on conflict (dedupe_key) where dedupe_key is not null do nothing
          returning 1)
        select v_written + count(*) into v_written from ins;
      end if;
    end if;

    v_out := v_out || jsonb_build_object('rule', d.decision_key, 'state', v_state, 'firings', jsonb_array_length(v_rows),
                                         'detail', v_detail, 'keys', (select jsonb_agg(e->'key') from jsonb_array_elements(v_rows) e));
  end loop;

  -- ok is the honest answer to "was every active rule actually evaluated". A branch that answers
  -- 'not_instrumented' did not evaluate anything, so it cannot leave ok true (22 Sep 2026).
  --
  -- THE KEY NAME IS LOAD-BEARING, DO NOT "TIDY" IT — AND NO CHECK WILL STOP YOU. The review of
  -- #852 measured this: renaming `uninstrumented_error` to `error` still passes every assertion in
  -- the repository. It is caught only OPERATIONALLY, and late: the ceoDecisions step goes
  -- permanently red on the heartbeat, which is how an estate learns to ignore a red step. The
  -- reason the name matters is below; treat this paragraph as the check that does not exist.
  -- resilience_ping's failureOf (steps.ts:14)
  -- counts a step as FAILED only when it answers ok:false AND a string `error` key; ok:false with
  -- no `error` is a result that has already reported itself, and is deliberately left alone.
  -- The missing-evaluator case keeps `error` because it IS a heartbeat failure — a rule nothing
  -- evaluates is a defect in the code. The uninstrumented case is reported under
  -- `uninstrumented_error` instead, because it is a standing, known gap the CEO must close by
  -- instrumenting the measure or deactivating the rule, not a tick that went wrong. Renaming it to
  -- `error` would turn the ceoDecisions step permanently red and train the estate to ignore it.
  return jsonb_build_object('ok', cardinality(v_missing) = 0 and cardinality(v_blind) = 0, 'dry_run', p_dry_run,
           'fired', v_fired, 'written', v_written, 'rules', v_out,
           'not_instrumented', to_jsonb(v_blind))
      || case when cardinality(v_missing) = 0 then '{}'::jsonb
              else jsonb_build_object('error', 'active ceo_decision rule(s) with no evaluator: '||array_to_string(v_missing, ', ')) end
      || case when cardinality(v_blind) = 0 then '{}'::jsonb
              else jsonb_build_object('uninstrumented_error',
                     'active ceo_decision rule(s) whose measure has no instrument, so they were not evaluated: '
                     ||array_to_string(v_blind, ', ')) end;
end $fn$;
revoke execute on function public.fn_ceo_decisions_evaluate(boolean) from public, anon, authenticated;

comment on function public.fn_ceo_decisions_evaluate(boolean) is
  'Evaluates every active public.ceo_decision rule deterministically and writes one ceo_decision_log row with evidence per firing (dedupe_key). Called by resilience_ping step ceoDecisions. ok:false names any active rule with no evaluator AND any whose measure has no instrument (not_instrumented). binding_constraint compares the feasibility verdict with ceo_plan.stage; risk_owner reads risk_register. Writes nothing to the founder. 22 Sep 2026, ceo + it_engineer.';
