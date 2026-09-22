-- PROBE: the CEO's daily plan is produced from live data, its directives reach the seats and are followed
-- up met or missed, a stalled constraint escalates, the model slot refuses an answer outside its contract,
-- and nothing reaches the founder or touches a supplier, customer or payment row.
-- Pure probe -- NO DDL in this file. Seat: ceo. 22 Sep 2026.
-- Pairs with the_ceo_plans_every_day_and_directs_the_seats.sql (apply that, the re-applied
-- the_weekly_report_arrives_and_the_rules_decide.sql, and the brief file first).
--   node scripts/qsql.mjs scripts/sql/the_ceo_plans_every_day_and_directs_the_seats_probe.sql
-- Against a database without the plan it answers PROBE FAILED (fn_ceo_plan_tick does not exist).
--
-- HOW IT STAYS HARMLESS: every write is inside an inner block that always ends in a raised exception, so
-- nothing commits. The directives it issues go to seats (internal handoffs), never to a person, and the
-- handler of a ceo.directive only reads. The rehearsal plans are dated 2000-01-xx so no real day's plan
-- is ever read as their predecessor. Every table a person could be reached through is checked for rows
-- written by THIS transaction (xmin), which is zero or the probe fails.
--
-- WHAT IT ASSERTS
--   A. LIVE: fn_ceo_plan_tick at today 07:00 Dubai plans once, from live rows: the plan's month-to-date
--      supplier registrations and the contactable-lead count equal independent recounts; the stage
--      follows the live switches; the binding_constraint decision is written with evidence; a second
--      tick the same day does not plan again.
--   B. DIRECTIVE: with the switches on (rehearsal funnel), invitations bind on a seat lever and a
--      ceo.directive reaches sales_engineer; its handler replied (awaiting set, evidence.duty named).
--   C. MISSED: past its deadline and unmet, the follow-up closes it (verified_by ceo, met false) and logs it.
--   D. MET: a directive whose target the live reading already meets closes met on the next follow-up.
--   E. STALL: the same stage 8 days with nothing moving -> level 2, a constraint_stalled row, a 3-day
--      deadline; 15 days -> level 3 and a line for the founder's brief.
--   F. MODEL SLOT: the request carries the contract; an answer outside it is rejected and plan C stands;
--      an answer inside it is recorded as the model's decision and its directive reaches the seat.
--   G. NOTHING TO THE FOUNDER, NOTHING TO A PERSON: notifications, founder_alerts, leads, customers,
--      transactions, inquiries and quotes carry no row written by this transaction.
--   H. after the rollback: ceo_plan, ceo_decision_log and ceo.directive handoffs are as before.
begin;

do $$
declare
  v_at timestamptz := ((now() at time zone 'Asia/Dubai')::date + time '07:00') at time zone 'Asia/Dubai';
  v_m0 timestamptz := date_trunc('month', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai';
  v_tick jsonb; v_tick2 jsonb; p public.ceo_plan; v_sub numeric; v_cont numeric; v_bc int;
  v_oct jsonb; v_f jsonb; v_d jsonb; v_pid bigint; v_act jsonb; v_hid bigint; a public.agent_actions;
  v_fu jsonb; v_met_hid bigint; v_d2 jsonb; v_d3 jsonb; v_stall_rows int; v_req jsonb; v_bad jsonb; v_good jsonb;
  v_model_hid bigint; v_person int; v_plan_before bigint; v_log_before bigint; v_dir_before bigint;
  v_plan_after bigint; v_log_after bigint; v_dir_after bigint; v_summary text;
begin
  set local statement_timeout = '60s';
  select count(*) into v_plan_before from public.ceo_plan;
  select count(*) into v_log_before from public.ceo_decision_log;
  select count(*) into v_dir_before from public.agent_actions where kind='handoff' and detail->>'type'='ceo.directive';
  begin
    -- ── A. LIVE ──────────────────────────────────────────────────────────────────────────────────
    delete from public.ceo_plan where plan_date = (v_at at time zone 'Asia/Dubai')::date;   -- rolled back
    v_tick := public.fn_ceo_plan_tick(v_at);
    if not coalesce((v_tick->>'planned')::boolean, false) then raise exception 'A: the tick did not plan: %', v_tick; end if;
    select * into p from public.ceo_plan where id = (v_tick->>'plan_id')::bigint;

    -- independent recounts, written without fn_ceo_plan_measure
    select count(*) into v_sub from public.leads
     where registration_submitted_at >= v_m0 and registration_submitted_at < v_at
       and is_demo is not true and company_name not ilike 'zz demo%' and coalesce(email,'') not ilike '%@example.invalid';
    select count(*) into v_cont from public.leads
     where email is not null and invited_at is null and invite_status is distinct from 'bounced'
       and is_demo is not true and coalesce(company_name,'') not ilike 'zz demo%' and email not ilike '%@example.invalid';
    if (p.funnel->'month_to_date'->>'registrations_submitted')::numeric <> v_sub
       or (p.funnel->'state'->>'contactable_leads')::numeric <> v_cont then
      raise exception 'A: the plan disagrees with live rows: registrations % vs %, contactable % vs %',
        p.funnel->'month_to_date'->>'registrations_submitted', v_sub, p.funnel->'state'->>'contactable_leads', v_cont;
    end if;
    if not (p.funnel->'gates'->>'invite_enabled')::boolean or not (p.funnel->'gates'->>'supplier_outreach_golive')::boolean then
      -- instruction 636: a closed campaign gate is held SILENTLY -- no founder line, no brief line, no directive
      if p.stage <> 'invitations' or p.decision->>'lever' <> 'founder_reserved' or p.founder_line is not null
         or p.decision->'directive' <> 'null'::jsonb or p.decision->>'held_because' is null then
        raise exception 'A: with the switches off the plan must bind on invitations, held silently with no directive; got % % %', p.stage, p.decision->>'lever', p.founder_line;
      end if;
      if jsonb_array_length(public.fn_ceo_plan_brief_lines()) <> 0 then
        raise exception 'A: a silent hold put lines in the founder brief: %', public.fn_ceo_plan_brief_lines();
      end if;
    end if;
    if exists (select 1 from jsonb_array_elements_text(public.fn_ceo_plan_brief_lines()) x where x ~* public.fn_ceo_founder_text_forbidden()) then
      raise exception 'A: the brief lines raise a reserved subject: %', public.fn_ceo_plan_brief_lines();
    end if;
    select count(*) into v_bc from public.ceo_decision_log
     where decision_key = 'binding_constraint' and (evidence->>'plan_id')::bigint = p.id and evidence ? 'funnel_month_to_date';
    if v_bc <> 1 and not exists (select 1 from public.ceo_decision_log where dedupe_key = 'binding_constraint:plan:'||p.stage||':'||p.constraint_since) then
      raise exception 'A: no binding_constraint decision for the plan';
    end if;
    v_tick2 := public.fn_ceo_plan_tick(v_at + interval '1 hour');
    if coalesce((v_tick2->>'planned')::boolean, true) then raise exception 'A: a second tick the same day planned again: %', v_tick2; end if;

    -- ── B. A DIRECTIVE REACHES A SEAT ────────────────────────────────────────────────────────────
    select to_jsonb(m) into v_oct from public.ceo_plan_month m where month = date '2026-10-01';
    v_f := p.funnel || jsonb_build_object('local_date', '2000-01-10', 'day_of_month', 15, 'days_in_month', 31,
      'gates', jsonb_build_object('invite_enabled', true, 'supplier_outreach_golive', true, 'invite_daily_cap', 50, 'ceo_model_slot', 'off'),
      'month_to_date', jsonb_build_object('invitations_delivered', 0, 'registrations_submitted', 0, 'registrations_verified', 0,
                                          'inquiries_posted', 0, 'quote_coverage_pct', null, 'reveals_paid', 0, 'fee_aed', 0),
      'last_7_days', jsonb_build_object('invitations_delivered', 0, 'registrations_submitted', 0, 'registrations_verified', 0,
                                        'inquiries_posted', 0, 'quote_coverage_pct', null, 'reveals_paid', 0, 'fee_aed', 0),
      'state', jsonb_build_object('bounce_pct_7d', 1, 'stranded_submissions', 0, 'contactable_leads', v_cont, 'fee_aed_cumulative', 0));
    v_d := public.fn_ceo_plan_decide(v_f, v_oct, null);
    if v_d->>'stage' <> 'invitations' or v_d->>'lever' <> 'seat' or v_d->'directive'->>'seat' <> 'sales_engineer' then
      raise exception 'B: expected an invitations directive to sales_engineer, got %', v_d - 'options' - 'attainment';
    end if;
    -- a live open invitations directive would be reused rather than duplicated; the probe needs its own
    update public.agent_actions set status = 'failed' where kind='handoff' and detail->>'type'='ceo.directive' and status='pending';
    insert into public.ceo_plan (plan_date, funnel, month_target, stage, constraint_since, decision, founder_line)
    values ('2000-01-10', v_f, v_oct, v_d->>'stage', (v_d->>'constraint_since')::date, v_d, v_d->>'founder_line') returning id into v_pid;
    v_act := public.fn_ceo_plan_act(v_pid);
    v_hid := (v_act->'directives'->0->>'handoff_id')::bigint;
    select * into a from public.agent_actions where id = v_hid;
    if a.agent <> 'sales_engineer' or a.status <> 'pending' or a.detail->>'awaiting' is null
       or a.evidence->>'duty' is null or not coalesce((a.evidence->>'accepted')::boolean, false) then
      raise exception 'B: the directive did not reach the seat and get a reply: agent % status % awaiting % evidence %', a.agent, a.status, a.detail->>'awaiting', a.evidence;
    end if;
    if not exists (select 1 from public.ceo_decision_log where dedupe_key = 'seat_directive:issued:'||v_hid) then
      raise exception 'B: the directive was not logged as a decision';
    end if;

    -- ── C. MISSED: past its deadline and unmet ───────────────────────────────────────────────────
    update public.agent_actions set detail = detail || jsonb_build_object('due_at', now() - interval '1 hour', 'target', 999999) where id = v_hid;
    v_fu := public.fn_ceo_plan_followup(now());
    select * into a from public.agent_actions where id = v_hid;
    if a.status <> 'done' or a.evidence->>'verified_by' <> 'ceo' or (a.evidence->>'met')::boolean
       or not exists (select 1 from public.ceo_decision_log where dedupe_key = 'seat_directive:missed:'||v_hid) then
      raise exception 'C: an overdue unmet directive was not closed as missed: % %', a.status, a.evidence;
    end if;

    -- ── D. MET: stranded submissions at or below 0 (the live reading) ────────────────────────────
    v_d := public.fn_ceo_plan_decide(v_f || jsonb_build_object('local_date', '2000-01-11',
             'state', (v_f->'state') || jsonb_build_object('stranded_submissions', 1)), v_oct, null);
    if v_d->'directive'->>'measure_key' <> 'stranded_submissions' then raise exception 'D: expected a stranded_submissions directive, got %', v_d->'directive'; end if;
    insert into public.ceo_plan (plan_date, funnel, month_target, stage, constraint_since, decision)
    values ('2000-01-11', v_f, v_oct, v_d->>'stage', (v_d->>'constraint_since')::date, v_d) returning id into v_pid;
    v_act := public.fn_ceo_plan_act(v_pid);
    v_met_hid := (v_act->'directives'->0->>'handoff_id')::bigint;
    if public.fn_ceo_plan_measure('stranded_submissions', now(), now()) = 0 then
      v_fu := public.fn_ceo_plan_followup(now());
      select * into a from public.agent_actions where id = v_met_hid;
      if a.status <> 'done' or not coalesce((a.evidence->>'met')::boolean, false) then
        raise exception 'D: a directive already met was not closed met: % %', a.status, a.evidence;
      end if;
    end if;

    -- ── E. A STALLED CONSTRAINT ESCALATES ────────────────────────────────────────────────────────
    v_d2 := public.fn_ceo_plan_decide(v_f || jsonb_build_object('local_date', '2000-01-18'), v_oct,
              jsonb_build_object('stage', 'invitations', 'constraint_since', '2000-01-10'));
    v_d3 := public.fn_ceo_plan_decide(v_f || jsonb_build_object('local_date', '2000-01-25'), v_oct,
              jsonb_build_object('stage', 'invitations', 'constraint_since', '2000-01-10'));
    if not (v_d2->>'stalled')::boolean or (v_d2->>'level')::int <> 2 or v_d2->>'plan_c_choice' <> 'escalate'
       or (v_d2->'directive'->>'due_days')::int <> 3 then
      raise exception 'E: 8 days without movement must be level 2 with a 3-day deadline, got %', v_d2 - 'options' - 'attainment';
    end if;
    -- the invitation stage stays with the seats even at level 3 (instructions 636/639)
    if (v_d3->>'level')::int <> 3 or v_d3->>'founder_line' is not null then
      raise exception 'E: 15 days on invitations must be level 3 with NO founder line, got %', v_d3 - 'options' - 'attainment';
    end if;
    -- any other seat-movable stage reaches the brief at level 3: reveals behind with everything upstream on plan
    v_d3 := public.fn_ceo_plan_decide(v_f || jsonb_build_object('local_date', '2000-01-25',
              'month_to_date', (v_f->'month_to_date') || jsonb_build_object('invitations_delivered', 5000, 'registrations_submitted', 500,
                                                                             'registrations_verified', 500, 'inquiries_posted', 500)),
              v_oct || jsonb_build_object('reveals', 30), jsonb_build_object('stage', 'reveals', 'constraint_since', '2000-01-10'));
    if v_d3->>'stage' <> 'reveals' or (v_d3->>'level')::int <> 3 or v_d3->>'founder_line' is null
       or v_d3->>'founder_line' ~* public.fn_ceo_founder_text_forbidden() then
      raise exception 'E: a 15-day stall on reveals must reach the brief in allowed words, got %', v_d3 - 'options' - 'attainment';
    end if;
    insert into public.ceo_plan (plan_date, funnel, month_target, stage, constraint_since, decision, founder_line)
    values ('2000-01-18', v_f, v_oct, v_d2->>'stage', '2000-01-10', v_d2, v_d2->>'founder_line') returning id into v_pid;
    v_act := public.fn_ceo_plan_act(v_pid);
    select count(*) into v_stall_rows from public.ceo_decision_log where dedupe_key = 'constraint_stalled:invitations:2000-01-10:L2';
    if v_stall_rows <> 1 then raise exception 'E: the stall was not recorded as a constraint_stalled decision'; end if;

    -- ── F. THE MODEL SLOT ─────────────────────────────────────────────────────────────────────────
    v_req := public.fn_ceo_judgement_request(v_pid);
    if v_req->>'contract' <> 'ceo-judgement-v1' or v_req->>'system' is null or jsonb_array_length(v_req->'input'->'options') < 4 then
      raise exception 'F: the judgement request does not carry the contract: %', left(v_req::text, 400);
    end if;
    v_bad := public.fn_ceo_judgement_accept(v_pid, jsonb_build_object('option_id', 'wire_the_money', 'reasoning', 'x'), null);
    if coalesce((v_bad->>'ok')::boolean, true) or not coalesce((v_bad->>'plan_c_stands')::boolean, false) then
      raise exception 'F: an answer outside the contract was not rejected: %', v_bad;
    end if;
    -- a well-formed answer that raises the campaign with the founder is refused (instruction 636)
    v_bad := public.fn_ceo_judgement_accept(v_pid, jsonb_build_object(
      'option_id', 'hold_reserved',
      'reasoning', 'Invitations delivered read 0 against a plan of 1,100 for the month, eight days running.',
      'prediction', jsonb_build_object('measure_key', 'invitations_delivered', 'direction', 'min', 'value', 0, 'by_date', '2000-01-25'),
      'directives', '[]'::jsonb, 'founder_decision', 'Please switch the supplier invitation campaign on.'), null);
    if coalesce((v_bad->>'ok')::boolean, true) or v_bad->>'error' !~ 'reserved from the founder' then
      raise exception 'F: a founder_decision about the campaign was not refused: %', v_bad;
    end if;
    v_good := public.fn_ceo_judgement_accept(v_pid, jsonb_build_object(
      'option_id', 'escalate',
      'reasoning', 'Invitations delivered read 0 against a plan of 1,100 for the month, eight days running; the owner has missed once.',
      'prediction', jsonb_build_object('measure_key', 'invitations_delivered', 'direction', 'min', 'value', 150, 'by_date', '2000-01-25'),
      'directives', jsonb_build_array(jsonb_build_object('seat', 'customer_support', 'stage', 'deliverability', 'measure_key', 'bounce_pct_7d',
                                                          'direction', 'max', 'target', 5, 'due_days', 7, 'instruction', 'Keep bounces under 5% while invitations ramp.')),
      'founder_decision', null), null);
    if not coalesce((v_good->>'ok')::boolean, false) then raise exception 'F: a valid answer was refused: %', v_good; end if;
    v_model_hid := (v_good->'directive_handoffs'->>0)::bigint;
    select * into a from public.agent_actions where id = v_model_hid;
    if a.agent <> 'customer_support' or a.detail->>'decided_by' <> 'model' or a.evidence->>'duty' is null
       or (select decided_by from public.ceo_plan where id = v_pid) <> 'model' then
      raise exception 'F: the model''s directive did not reach customer_support as a model decision: % %', a.agent, a.detail;
    end if;

    -- ── G. NOTHING TO THE FOUNDER, NOTHING TO A PERSON, NO MONEY ─────────────────────────────────
    select (select count(*) from public.notifications   where xmin = pg_current_xact_id()::xid)
         + (select count(*) from public.founder_alerts  where xmin = pg_current_xact_id()::xid)
         + (select count(*) from public.leads           where xmin = pg_current_xact_id()::xid)
         + (select count(*) from public.customers       where xmin = pg_current_xact_id()::xid)
         + (select count(*) from public.transactions    where xmin = pg_current_xact_id()::xid)
         + (select count(*) from public.inquiries       where xmin = pg_current_xact_id()::xid)
         + (select count(*) from public.quotes          where xmin = pg_current_xact_id()::xid)
      into v_person;
    if v_person <> 0 then raise exception 'G: % row(s) written to a table that reaches a person or moves money', v_person; end if;

    v_summary := format('live plan %s stage=%s lever=%s founder_line=%s; directive %s -> sales_engineer replied, closed missed; met directive %s; stall L2 %s L3 %s; model bad rejected, good -> handoff %s customer_support',
      p.id, p.stage, p.decision->>'lever', (p.founder_line is not null), v_hid, v_met_hid, v_d2->>'level', v_d3->>'level', v_model_hid);
    raise exception 'ROLLBACK_PROBE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_PROBE' then raise; end if;
  end;

  select count(*) into v_plan_after from public.ceo_plan;
  select count(*) into v_log_after from public.ceo_decision_log;
  select count(*) into v_dir_after from public.agent_actions where kind='handoff' and detail->>'type'='ceo.directive';
  if v_plan_after <> v_plan_before or v_log_after <> v_log_before or v_dir_after <> v_dir_before then
    raise exception 'H: the rollback left rows behind: plans % -> %, decisions % -> %, directives % -> %',
      v_plan_before, v_plan_after, v_log_before, v_log_after, v_dir_before, v_dir_after;
  end if;
  perform set_config('qd.probe_verdict', 'PROBE OK ' || v_summary || '; nothing reached a person; left_behind=0', true);
exception when others then
  perform set_config('qd.probe_verdict', 'PROBE FAILED ' || sqlerrm, true);
end $$;

select coalesce(current_setting('qd.probe_verdict', true), 'PROBE FAILED (the block set no verdict)') as verdict;

commit;
