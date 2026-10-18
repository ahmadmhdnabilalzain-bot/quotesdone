-- PROBE: A REJECTION NEVER ENDS THE CYCLE; THE CEO GIVES REASONS AND THE SEAT REVISES (29 Sep 2026; seat: ceo).
--
-- A pure probe: it always ends in raise exception 'CHK<<...>>', so every row it writes rolls back with it. Run it
-- AFTER a_rejection_never_ends_the_cycle_the_ceo_gives_reasons_and_the_seat_revises.sql and
-- the_directive_escalation_rule_is_decided_by_its_own_duty.sql are applied (or after both in the same rolled-back
-- transaction). The verdict is the first key of the CHK payload: PROBE OK, or PROBE FAILED with what failed.
--
-- NOTHING HERE CAN REACH A PERSON OR A MODEL. Every subject is a ZZ DEMO fixture made here: two transactions and two
-- refunds with no customer and no supplier, deliberations flagged demo, experiments and improvements keyed zz_probe.
-- think() is stubbed: each seat's and the CEO's reasoned answer is handed to fn_reason_held_resolve exactly as the
-- model would return it, and no gateway is called (a demo deliberation is held before any model; the model hold is
-- on). fn_ceo_refund_checklist is replaced by a stub for THIS transaction only (catalog changes are transactional
-- and invisible to every other session), so the probe decides when a check fails and when the seat's fix lands.
--
-- WHAT IT PROVES, per path (seat_deliberation, refund, ceo_experiment, ceo_improvement) plus ceo_approval and the
-- sales-escalation choice:
--   * a reasonless decision is refused by the database;
--   * reject -> the originating seat's revision -> resubmit -> approve, with every round kept in ceo_decision_round;
--   * the loop guard: 4 rejections are recorded, a 5th is refused and the CEO is owed a replace-or-withdraw, which
--     it makes with reasons; the founder is never paged (no refund_ceo_summary delivery request);
--   * the ledger is append-only, a closed item takes no more decisions, and directive_escalation has an evaluator.
--
--   node scripts/apply_sql.mjs scripts/sql/a_rejection_never_ends_the_cycle_the_ceo_gives_reasons_and_the_seat_revises_probe.sql --apply

do $probe$
declare
  v_bad text[] := '{}'; r jsonb := '{}'::jsonb; v jsonb; v_err text; n int; k int;
  v_start bigint; v_d1 bigint; v_d2 bigint; v_held bigint; v_h bigint;
  v_tx1 uuid; v_tx2 uuid; v_rf1 bigint; v_rf2 bigint; v_e1 bigint; v_e2 bigint; v_i1 bigint; v_i2 bigint;
  c_rev constant text := 'openai/gpt-5.6-sol';     -- the seats' revisions (stub)
  c_ceo constant text := 'google/gemini-3.8-flash'; -- the CEO's reviews (stub), another family
  v_decs text;
begin
  select coalesce(max(id), 0) into v_start from public.agent_actions;

  -- ── A. THE LEDGER'S OWN RULES, on a direct insert ────────────────────────────────────────────────────────
  foreach v_decs in array array['no', 'ok ok ok ok ok ok', ''] loop
    v_err := null;
    begin
      insert into public.ceo_decision_round (path, item_key, originator_seat, decision, reasons)
      values ('refund', 'zz_probe:direct', 'accountant', 'rejected', v_decs);
      v_bad := v_bad || ('reasonless_insert_stored:' || v_decs);
    exception when check_violation then v_err := sqlerrm; end;
    if coalesce(v_err, '') !~ 'REASONLESS_DECISION' then v_bad := v_bad || ('reasonless_refused_for_the_wrong_reason:' || coalesce(v_err, 'none')); end if;
  end loop;
  v_err := null;
  begin
    insert into public.ceo_decision_round (path, item_key, originator_seat, decision, reasons)
    values ('refund', 'zz_probe:direct', 'ceo', 'approved', 'the chief executive approving its own work is not a submission');
    v_bad := v_bad || 'ceo_as_originator_stored'::text;
  exception when check_violation then v_err := sqlerrm; end;
  for k in 1..4 loop
    insert into public.ceo_decision_round (path, item_key, originator_seat, decision, reasons)
    values ('refund', 'zz_probe:direct', 'accountant', 'rejected', 'ZZ DEMO round ' || k || ' is sent back because the evidence is still missing');
  end loop;
  v_err := null;
  begin
    insert into public.ceo_decision_round (path, item_key, originator_seat, decision, reasons)
    values ('refund', 'zz_probe:direct', 'accountant', 'rejected', 'ZZ DEMO a fifth rejection of the same item with reasons');
    v_bad := v_bad || 'fifth_rejection_stored'::text;
  exception when check_violation then v_err := sqlerrm; end;
  if coalesce(v_err, '') !~ 'ROUND_LIMIT' then v_bad := v_bad || ('fifth_rejection_refused_for_the_wrong_reason:' || coalesce(v_err, 'none')); end if;
  r := r || jsonb_build_object('direct_fifth', v_err);
  v_err := null;
  begin update public.ceo_decision_round set reasons = reasons || ' edited' where item_key = 'zz_probe:direct';
        v_bad := v_bad || 'ledger_row_edited'::text;
  exception when check_violation then v_err := sqlerrm; end;
  v_err := null;
  begin delete from public.ceo_decision_round where item_key = 'zz_probe:direct'; v_bad := v_bad || 'ledger_row_deleted'::text;
  exception when check_violation then v_err := sqlerrm; end;
  insert into public.ceo_decision_round (path, item_key, originator_seat, decision, reasons)
  values ('refund', 'zz_probe:direct', 'accountant', 'withdrawn', 'ZZ DEMO withdrawn after four rounds because the item cannot be fixed');
  v_err := null;
  begin
    insert into public.ceo_decision_round (path, item_key, originator_seat, decision, reasons)
    values ('refund', 'zz_probe:direct', 'accountant', 'approved', 'ZZ DEMO an approval after the item was withdrawn');
    v_bad := v_bad || 'decision_after_withdrawal_stored'::text;
  exception when check_violation then v_err := sqlerrm; end;
  if coalesce(v_err, '') !~ 'ITEM_CLOSED' then v_bad := v_bad || 'closed_item_refused_for_the_wrong_reason'::text; end if;
  select string_agg(decision || '#' || round, ',' order by round) into v_decs from public.ceo_decision_round where item_key = 'zz_probe:direct';
  if v_decs is distinct from 'rejected#1,rejected#2,rejected#3,rejected#4,withdrawn#5' then v_bad := v_bad || ('direct_history:' || coalesce(v_decs, 'none')); end if;

  -- a huge submission is cut to the ledger's bound and keeps the ids the paths read back (quotes double when escaped)
  v := public.fn_ceo_decision_version_cut(jsonb_build_object('deliberation_id', 7, 'big', repeat('"', 40000)));
  if v->>'deliberation_id' is distinct from '7' or length(v::text) > 30000 then v_bad := v_bad || 'version_cut_lost_its_ids_or_bound'::text; end if;

  -- ── B. CEO_APPROVAL REFUSES A REASONLESS DECISION ──────────────────────────────────────────────────────────
  v_err := null;
  begin
    insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, rationale) values ('other', 'zz-probe', 'refused', 'ceo', 'no');
    v_bad := v_bad || 'reasonless_ceo_approval_stored'::text;
  exception when check_violation then v_err := sqlerrm; end;
  if coalesce(v_err, '') !~ 'REASONLESS_DECISION' then v_bad := v_bad || 'ceo_approval_refused_for_the_wrong_reason'::text; end if;

  -- ── C. SEAT_DELIBERATION: reasonless refused; reject -> revise -> resubmit -> approve ──────────────────────
  v_d1 := public.fn_seat_deliberation_open('zz_probe.ceo_cycle', 'sales_engineer', 'ceo', 'ZZ DEMO probe: judge the seat''s answer to a disputed reveal',
            '{"facts":"a customer disputes a reveal fee on day four"}'::jsonb, '{"answer":"the supplier responded inside the window so the fee stands"}'::jsonb,
            'deterministic', null, 'zz_probe', 'd1', true);
  if (select max_rounds from public.seat_deliberation where id = v_d1) <> 5 then v_bad := v_bad || 'ceo_review_not_given_five_rounds'::text; end if;
  perform public.fn_seat_deliberation_record(v_d1, 'blind', c_ceo, '{"verdict":"reject","steelman_against":"the supplier may have replied only after the deadline had passed"}'::jsonb);
  foreach v_decs in array array['reject', 'approve'] loop
    v_err := null;
    begin
      perform public.fn_seat_deliberation_record(v_d1, 'compare', c_ceo, jsonb_build_object('verdict', v_decs,
        'steelman_against', 'the customer might hold a message we have not yet read', 'agreements', 'none', 'disagreements', 'none'));
      v_bad := v_bad || ('reasonless_' || v_decs || '_recorded');
    exception when check_violation then v_err := sqlerrm; end;
    if coalesce(v_err, '') !~ 'REASONLESS_DECISION' then v_bad := v_bad || ('deliberation_reasonless_' || v_decs || '_wrong_reason:' || coalesce(v_err, 'none')); end if;
  end loop;
  perform public.fn_seat_deliberation_record(v_d1, 'compare', c_ceo, jsonb_build_object('verdict', 'reject',
    'steelman_against', 'the customer might hold a message we have not yet read',
    'agreements', 'the window rule is the right test for this dispute',
    'disagreements', 'the answer cites no delivery timestamp and ignores the customer message sent on day two'));
  select id into v_held from public.reasoning_held_question where dedupe_key = 'ceo_revision:seat_deliberation:' || v_d1 || ':g1:r1';
  if v_held is null or (select seat from public.reasoning_held_question where id = v_held) <> 'sales_engineer' then
    v_bad := v_bad || 'rejection_did_not_reach_the_originator'::text;
  end if;
  v_err := null;
  begin
    perform public.fn_reason_held_resolve(v_held, '{"status":"answered","answer":"ok","decision":{"choice":"revised","fields":{"revision":{"value":"x"},"answers":{"value":"ok"}}}}'::jsonb);
    v_bad := v_bad || 'empty_revision_accepted'::text;
  exception when check_violation then v_err := sqlerrm; end;
  if coalesce(v_err, '') !~ 'UNANSWERED_REVISION' then v_bad := v_bad || 'empty_revision_refused_for_the_wrong_reason'::text; end if;
  perform public.fn_reason_held_resolve(v_held, jsonb_build_object('status', 'answered', 'model', c_rev,
    'answer', 'The revision adds the delivery timestamp from the outbox and answers the customer message from day two directly.',
    'decision', jsonb_build_object('choice', 'revised', 'fields', jsonb_build_object(
      'revision', jsonb_build_object('value', 'the supplier replied at 10:04 on day one, inside the window, so the fee stands'),
      'answers', jsonb_build_object('value', 'timestamp added from the outbox; the day two message asked for a call that the supplier made')))));
  if (select round || ':' || status from public.seat_deliberation where id = v_d1) <> '2:open' then v_bad := v_bad || 'revision_not_resubmitted'::text; end if;
  perform public.fn_seat_deliberation_record(v_d1, 'compare', c_ceo, jsonb_build_object('verdict', 'approve',
    'steelman_against', 'the timestamp could come from a retry rather than the first send',
    'agreements', 'the revision now cites the delivery timestamp and answers the customer message, so the fee stands on evidence',
    'disagreements', 'none'));
  select string_agg(decision || '#' || round, ',' order by round) into v_decs from public.ceo_decision_round where item_key = 'seat_deliberation:' || v_d1;
  r := r || jsonb_build_object('deliberation_cycle', v_decs, 'deliberation_status', (select status from public.seat_deliberation where id = v_d1));
  if v_decs is distinct from 'rejected#1,approved#2' then v_bad := v_bad || ('deliberation_history:' || coalesce(v_decs, 'none')); end if;
  if (select status from public.seat_deliberation where id = v_d1) <> 'closed' then v_bad := v_bad || 'approved_deliberation_not_closed_by_its_author'::text; end if;
  if exists (select 1 from public.agent_actions a where a.id > v_start and a.detail->>'type' = 'ceo.revise'
               and a.detail->>'item_key' = 'seat_deliberation:' || v_d1 and a.status <> 'done') then
    v_bad := v_bad || 'revise_handoff_left_open'::text;
  end if;
  if not exists (select 1 from public.agent_actions a where a.id > v_start and a.detail->>'type' = 'ceo.decision_closed'
                   and a.agent = 'sales_engineer' and a.detail->>'item_key' = 'seat_deliberation:' || v_d1 and a.detail->>'decision' = 'approved') then
    v_bad := v_bad || 'approval_logic_not_returned_to_the_seat'::text;
  end if;

  -- ── D. SEAT_DELIBERATION: THE LOOP GUARD ──────────────────────────────────────────────────────────────────
  v_d2 := public.fn_seat_deliberation_open('zz_probe.ceo_cycle', 'sales_engineer', 'ceo', 'ZZ DEMO probe: judge the seat''s second dispute answer',
            '{"facts":"a supplier disputes a non-response charge"}'::jsonb, '{"answer":"the charge stands because no reply was logged"}'::jsonb,
            'deterministic', null, 'zz_probe', 'd2', true);
  perform public.fn_seat_deliberation_record(v_d2, 'blind', c_ceo, '{"verdict":"reject","steelman_against":"a reply could have arrived on a channel we do not log"}'::jsonb);
  for k in 1..5 loop
    perform public.fn_seat_deliberation_record(v_d2, 'compare', c_ceo, jsonb_build_object('verdict', 'reject',
      'steelman_against', 'round ' || k || ' the supplier may have phoned the customer instead of writing',
      'agreements', 'the charge rule is cited correctly',
      'disagreements', 'round ' || k || ' still shows no check of the WhatsApp channel or the phone log before charging'));
    exit when k = 5;
    select id into v_held from public.reasoning_held_question where dedupe_key = 'ceo_revision:seat_deliberation:' || v_d2 || ':g1:r' || k;
    perform public.fn_reason_held_resolve(v_held, jsonb_build_object('status', 'answered', 'model', c_rev,
      'answer', 'Revision ' || k || ': the seat re-checked the channels it could reach and answers the CEO reason point by point.',
      'decision', jsonb_build_object('choice', 'defended', 'fields', jsonb_build_object(
        'revision', jsonb_build_object('value', 'revision ' || k || ' of the charge answer'),
        'answers', jsonb_build_object('value', 'round ' || k || ': email and portal checked, the other channels are not reachable by this seat')))));
  end loop;
  select string_agg(decision || '#' || round, ',' order by round) into v_decs from public.ceo_decision_round where item_key = 'seat_deliberation:' || v_d2;
  r := r || jsonb_build_object('guard_deliberation', v_decs);
  if v_decs is distinct from 'rejected#1,rejected#2,rejected#3,rejected#4' then v_bad := v_bad || ('guard_deliberation_history:' || coalesce(v_decs, 'none')); end if;
  select id into v_held from public.reasoning_held_question where dedupe_key = 'ceo_decision_owed:seat_deliberation:' || v_d2 || ':g1:after_r4' and seat = 'ceo';
  if v_held is null then v_bad := v_bad || 'no_decision_owed_to_the_ceo_after_four_rounds'::text; end if;
  v_err := null;
  begin
    perform public.fn_reason_held_resolve(v_held, '{"status":"answered","answer":"no","decision":{"choice":"withdraw"}}'::jsonb);
    v_bad := v_bad || 'reasonless_withdrawal_accepted'::text;
  exception when check_violation then v_err := sqlerrm; end;
  if coalesce(v_err, '') !~ 'REASONLESS_DECISION' then v_bad := v_bad || 'reasonless_withdrawal_wrong_reason'::text; end if;
  perform public.fn_reason_held_resolve(v_held, jsonb_build_object('status', 'answered', 'model', c_ceo,
    'answer', 'Withdrawn: after four rounds the charge still rests on channels the seat cannot check, so it does not go ahead.',
    'decision', jsonb_build_object('choice', 'withdraw')));
  select string_agg(decision || '#' || round, ',' order by round) into v_decs from public.ceo_decision_round where item_key = 'seat_deliberation:' || v_d2;
  if v_decs is distinct from 'rejected#1,rejected#2,rejected#3,rejected#4,withdrawn#5' then v_bad := v_bad || ('guard_deliberation_closed:' || coalesce(v_decs, 'none')); end if;
  if (select status from public.seat_deliberation where id = v_d2) <> 'closed' then v_bad := v_bad || 'withdrawn_deliberation_not_closed'::text; end if;

  -- ── E. REFUNDS (the checklist stubbed for this transaction; no money moves) ───────────────────────────────
  execute $stub$
    create or replace function public.fn_ceo_refund_checklist(p_transaction_id uuid, p_phase text, p_record boolean default true)
    returns jsonb language sql set search_path to 'public', 'pg_temp' as $s$
      select case when current_setting('qd.zz_probe_pass', true) = 'on'
        then jsonb_build_object('ok', true, 'phase', p_phase, 'transaction_id', p_transaction_id,
               'items', jsonb_build_array(jsonb_build_object('item', 'zz_probe_check', 'passed', true)), 'failed', '[]'::jsonb)
        else jsonb_build_object('ok', false, 'phase', p_phase, 'transaction_id', p_transaction_id,
               'items', jsonb_build_array(jsonb_build_object('item', 'zz_probe_check', 'passed', false)),
               'failed', jsonb_build_array(jsonb_build_object('item', 'zz_probe_check', 'passed', false, 'remediable', true,
                 'owner', 'accountant', 'remedy_key', 'zz_probe_fix', 'reason', 'ZZ DEMO the probe check fails until the seat fixes it'))) end
    $s$ $stub$;
  insert into public.transactions (payment_ref, total_charged, reveal_fee, refund_deadline)
  values ('pi_zzdemo_probe_cycle_1', 100, 100, now() - interval '1 day') returning id into v_tx1;
  insert into public.transactions (payment_ref, total_charged, reveal_fee, refund_deadline)
  values ('pi_zzdemo_probe_cycle_2', 100, 100, now() - interval '1 day') returning id into v_tx2;
  insert into public.refunds (transaction_id, stripe_payment_intent, amount_fils, currency, reason_code, reason_note, requested_by, status)
  values (v_tx1, 'pi_zzdemo_probe_cycle_1', 10000, 'AED', 'supplier_unresponsive', 'ZZ DEMO probe refund one', 'customer', 'requested') returning id into v_rf1;
  insert into public.refunds (transaction_id, stripe_payment_intent, amount_fils, currency, reason_code, reason_note, requested_by, status)
  values (v_tx2, 'pi_zzdemo_probe_cycle_2', 10000, 'AED', 'supplier_unresponsive', 'ZZ DEMO probe refund two', 'customer', 'requested') returning id into v_rf2;
  v_err := null;
  begin
    insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale) values ('refund', v_rf1::text, 'refused', 'ceo', 100, '');
    v_bad := v_bad || 'reasonless_refund_refusal_stored'::text;
  exception when check_violation then v_err := sqlerrm; end;
  if coalesce(v_err, '') !~ 'REASONLESS_DECISION' then v_bad := v_bad || 'refund_reasonless_wrong_reason'::text; end if;

  perform set_config('qd.zz_probe_pass', 'off', true);
  v := public.fn_ceo_refund_review(v_rf1, 'probe');
  if v->>'outcome' <> 'rejected' then v_bad := v_bad || ('refund_first_review:' || coalesce(v->>'outcome', 'null')); end if;
  -- the accountant fixes its check and closes its task: the review re-runs and the CEO approves
  perform set_config('qd.zz_probe_pass', 'on', true);
  select a.id into v_h from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'refund.remediate'
     and a.detail->>'refund_id' = v_rf1::text;
  perform public.fn_seat_handoff_complete(v_h, '{"fixed_by":"accountant","probe":"ZZ DEMO"}'::jsonb);
  select string_agg(decision || '#' || round, ',' order by round) into v_decs from public.ceo_decision_round where item_key = 'refunds:' || v_rf1;
  r := r || jsonb_build_object('refund_cycle', v_decs, 'refund_status', (select status || ':' || (refund_decision_id is not null) from public.refunds where id = v_rf1));
  if v_decs is distinct from 'rejected#1,approved#2' then v_bad := v_bad || ('refund_history:' || coalesce(v_decs, 'none')); end if;
  -- Since #1138 the approval goes through fn_refund_decide (the one decision + the second seat), which moves the
  -- refund to 'approved' - not 'requested' as before. 'approved' is still before money: only 'processing' /
  -- 'succeeded' or a Stripe refund id means money moved (outcome audit 30 Sep 2026, measured: approved, dec linked,
  -- stripe_refund_id null).
  if (select status from public.refunds where id = v_rf1) <> 'approved' or (select refund_decision_id from public.refunds where id = v_rf1) is null
     or (select stripe_refund_id from public.refunds where id = v_rf1) is not null then
    v_bad := v_bad || 'refund_approval_not_linked_or_money_moved'::text;
  end if;

  perform set_config('qd.zz_probe_pass', 'off', true);
  v := public.fn_ceo_refund_review(v_rf2, 'probe');
  for k in 1..4 loop   -- the seat closes its task each time, the check still fails, the CEO rejects again ... until the guard
    select a.id into v_h from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'refund.remediate'
       and a.detail->>'refund_id' = v_rf2::text;
    exit when v_h is null;
    perform public.fn_seat_handoff_complete(v_h, jsonb_build_object('attempted_by', 'accountant', 'round', k));
    v_h := null;
  end loop;
  select string_agg(decision || '#' || round, ',' order by round) into v_decs from public.ceo_decision_round where item_key = 'refunds:' || v_rf2;
  r := r || jsonb_build_object('guard_refund', v_decs, 'refund_guard_review', public.fn_ceo_refund_review(v_rf2, 'probe')->>'outcome');
  if v_decs is distinct from 'rejected#1,rejected#2,rejected#3,rejected#4' then v_bad := v_bad || ('guard_refund_history:' || coalesce(v_decs, 'none')); end if;
  if not exists (select 1 from public.refund_ceo_review where refund_id = v_rf2 and outcome = 'escalated') then v_bad := v_bad || 'refund_guard_not_recorded'::text; end if;
  if r->>'refund_guard_review' <> 'awaiting_ceo_replace_or_withdraw' then v_bad := v_bad || 'refund_not_held_for_the_ceo'::text; end if;
  select id into v_held from public.reasoning_held_question where dedupe_key = 'ceo_decision_owed:refunds:' || v_rf2 || ':g1:after_r4';
  perform public.fn_reason_held_resolve(v_held, jsonb_build_object('status', 'answered', 'model', c_ceo,
    'answer', 'Withdrawn: four rounds have not produced the evidence the refund needs, so it is declined and the customer is told why.',
    'decision', jsonb_build_object('choice', 'withdraw')));
  select string_agg(decision || '#' || round, ',' order by round) into v_decs from public.ceo_decision_round where item_key = 'refunds:' || v_rf2;
  r := r || jsonb_build_object('refund_withdrawn', v_decs, 'refund2_status', (select status from public.refunds where id = v_rf2));
  if v_decs is distinct from 'rejected#1,rejected#2,rejected#3,rejected#4,withdrawn#5' then v_bad := v_bad || ('refund_withdrawal:' || coalesce(v_decs, 'none')); end if;
  if (select status from public.refunds where id = v_rf2) <> 'rejected' then v_bad := v_bad || 'withdrawn_refund_not_declined'::text; end if;
  if not exists (select 1 from public.ceo_approval where subject_kind = 'refund' and subject_id = v_rf2::text and decision = 'refused') then
    v_bad := v_bad || 'withdrawal_has_no_ceo_refusal'::text;
  end if;
  if exists (select 1 from public.agent_actions a where a.id > v_start and a.detail->>'type' = 'delivery.request'
               and (a.detail->>'kind' = 'refund_ceo_summary' or a.target_id like '%refund_loop_stuck%' or a.target_id like '%refund_task_overdue%')) then
    v_bad := v_bad || 'the_founder_was_paged'::text;
  end if;

  -- ── F. EXPERIMENTS A SEAT PROPOSES ────────────────────────────────────────────────────────────────────────
  v_e1 := public.fn_ceo_experiment_propose('sales_engineer', 'zz_probe_exp_cycle', 'ZZ DEMO a shorter first message lifts reveals',
            'reveal_conversion_pct', 'ZZ DEMO reveals over comparisons', null, 'ZZ DEMO no baseline in the probe', 5, 'min',
            'ZZ DEMO send the short message to half the requests', current_date + 1, 14);
  select id into v_held from public.reasoning_held_question where dedupe_key = 'ceo_exp_approve:' || v_e1 || ':1';
  v_err := null;
  begin
    perform public.fn_reason_held_resolve(v_held, '{"status":"answered","answer":"no","decision":{"choice":"reject"}}'::jsonb);
    v_bad := v_bad || 'reasonless_experiment_reject_accepted'::text;
  exception when check_violation then v_err := sqlerrm; end;
  if coalesce(v_err, '') !~ 'REASONLESS_DECISION' then v_bad := v_bad || 'experiment_reasonless_wrong_reason'::text; end if;
  perform public.fn_reason_held_resolve(v_held, jsonb_build_object('status', 'answered', 'model', 'anthropic/claude-opus-5.5',
    'answer', 'Rejected for now: a half split over fourteen days is too short to separate the effect from weekly noise.',
    'decision', jsonb_build_object('choice', 'reject')));
  if (select status from public.ceo_experiment where id = v_e1) <> 'proposed' then v_bad := v_bad || 'rejected_experiment_was_closed'::text; end if;
  select id into v_held from public.reasoning_held_question where dedupe_key = 'ceo_revision:ceo_experiment:' || v_e1 || ':g1:r1' and seat = 'sales_engineer';
  if v_held is null then v_bad := v_bad || 'experiment_rejection_did_not_reach_the_proposer'::text; end if;
  perform public.fn_reason_held_resolve(v_held, jsonb_build_object('status', 'answered', 'model', c_rev,
    'answer', 'Revised: the run is extended to twenty eight days so weekly noise averages out, as the CEO asked.',
    'decision', jsonb_build_object('choice', 'revised', 'fields', jsonb_build_object(
      'answers', jsonb_build_object('value', 'the run length is now twenty eight days, four full weeks'),
      'days', jsonb_build_object('value', '28')))));
  select id into v_held from public.reasoning_held_question where dedupe_key = 'ceo_exp_approve:' || v_e1 || ':2';
  if v_held is null then v_bad := v_bad || 'experiment_revision_not_resubmitted'::text; end if;
  perform public.fn_reason_held_resolve(v_held, jsonb_build_object('status', 'answered', 'model', 'anthropic/claude-opus-5.5',
    'answer', 'Approved: four full weeks separate the effect from weekly noise and the metric is measured by code.',
    'decision', jsonb_build_object('choice', 'approve', 'fields', jsonb_build_object('owner_seat', jsonb_build_object('value', 'sales_engineer')))));
  select string_agg(decision || '#' || round, ',' order by round) into v_decs from public.ceo_decision_round where item_key = 'ceo_experiment:' || v_e1;
  r := r || jsonb_build_object('experiment_cycle', v_decs, 'experiment_status', (select status || ':' || days from public.ceo_experiment where id = v_e1));
  if v_decs is distinct from 'rejected#1,approved#2' then v_bad := v_bad || ('experiment_history:' || coalesce(v_decs, 'none')); end if;
  if (select status from public.ceo_experiment where id = v_e1) not in ('approved', 'running') then v_bad := v_bad || 'approved_experiment_not_approved'::text; end if;

  v_e2 := public.fn_ceo_experiment_propose('marketing', 'zz_probe_exp_guard', 'ZZ DEMO a second hypothesis for the guard',
            'reveal_conversion_pct', 'ZZ DEMO reveals over comparisons', null, 'ZZ DEMO no baseline in the probe', 5, 'min',
            'ZZ DEMO an approach the CEO keeps sending back', current_date + 1, 14);
  for k in 1..5 loop
    select id into v_held from public.reasoning_held_question where dedupe_key = 'ceo_exp_approve:' || v_e2 || ':' || k;
    perform public.fn_reason_held_resolve(v_held, jsonb_build_object('status', 'answered', 'model', 'anthropic/claude-opus-5.5',
      'answer', 'Round ' || k || ': sent back because the approach still does not name how the result will be measured.',
      'decision', jsonb_build_object('choice', 'revise')));
    exit when k = 5;
    select id into v_held from public.reasoning_held_question where dedupe_key = 'ceo_revision:ceo_experiment:' || v_e2 || ':g1:r' || k;
    perform public.fn_reason_held_resolve(v_held, jsonb_build_object('status', 'answered', 'model', c_rev,
      'answer', 'Revision ' || k || ' restates the approach and answers the CEO about measurement as far as the seat can.',
      'decision', jsonb_build_object('choice', 'revised', 'fields', jsonb_build_object(
        'answers', jsonb_build_object('value', 'round ' || k || ' measurement is the existing reveal conversion metric'),
        'approach', jsonb_build_object('value', 'ZZ DEMO approach revision ' || k)))));
  end loop;
  select id into v_held from public.reasoning_held_question where dedupe_key = 'ceo_decision_owed:ceo_experiment:' || v_e2 || ':g1:after_r4';
  if v_held is null then v_bad := v_bad || 'experiment_guard_not_owed_to_the_ceo'::text; end if;
  perform public.fn_reason_held_resolve(v_held, jsonb_build_object('status', 'answered', 'model', c_ceo,
    'answer', 'Replaced: the hypothesis is sound but this approach cannot be measured, so a measurable experiment takes its place.',
    'decision', jsonb_build_object('choice', 'replace')));
  select string_agg(decision || '#' || round, ',' order by round) into v_decs from public.ceo_decision_round where item_key = 'ceo_experiment:' || v_e2;
  r := r || jsonb_build_object('guard_experiment', v_decs, 'experiment2_status', (select status from public.ceo_experiment where id = v_e2));
  if v_decs is distinct from 'rejected#1,rejected#2,rejected#3,rejected#4,replaced#5' then v_bad := v_bad || ('guard_experiment_history:' || coalesce(v_decs, 'none')); end if;
  if (select status from public.ceo_experiment where id = v_e2) <> 'rejected' then v_bad := v_bad || 'replaced_experiment_not_closed'::text; end if;

  -- ── G. A SEAT'S ANSWER TO A CEO IMPROVEMENT ───────────────────────────────────────────────────────────────
  v_i1 := public.fn_ceo_improvement_open('self_review', 'zz-probe-improvement-1', 'marketing', 'ZZ DEMO shorten the weekly report to one page', '{"probe":true}'::jsonb);
  select handoff_id into v_h from public.ceo_improvement where id = v_i1;
  update public.agent_actions set evidence = evidence || '{"accepted":false}'::jsonb where id = v_h;   -- the seat's answer does not accept it
  v := public.fn_ceo_review_one_answered_improvement(v_h);
  if not coalesce((v->>'returned')::boolean, false) then v_bad := v_bad || 'improvement_not_returned'::text; end if;
  -- the seat answers again, accepting it: the CEO closes it. (Each answer is a round keyed by its replied_at, so the
  -- probe stamps clock_timestamp(): now() is one instant for the whole of this transaction.)
  update public.agent_actions set evidence = evidence || '{"accepted":true}'::jsonb, detail = detail || jsonb_build_object('replied_at', clock_timestamp()) where id = v_h;
  v := public.fn_ceo_review_one_answered_improvement(v_h);
  select string_agg(decision || '#' || round, ',' order by round) into v_decs from public.ceo_decision_round where item_key = 'ceo_improvement:' || v_i1;
  r := r || jsonb_build_object('improvement_cycle', v_decs);
  if v_decs is distinct from 'rejected#1,approved#2' then v_bad := v_bad || ('improvement_history:' || coalesce(v_decs, 'none')); end if;
  if (select status from public.agent_actions where id = v_h) <> 'done' then v_bad := v_bad || 'accepted_improvement_not_closed'::text; end if;

  v_i2 := public.fn_ceo_improvement_open('self_review', 'zz-probe-improvement-2', 'marketing', 'ZZ DEMO an improvement the seat never accepts', '{"probe":true}'::jsonb);
  select handoff_id into v_h from public.ceo_improvement where id = v_i2;
  for k in 1..5 loop
    update public.agent_actions set evidence = evidence || '{"accepted":false}'::jsonb, detail = detail || jsonb_build_object('replied_at', clock_timestamp()) where id = v_h;
    v := public.fn_ceo_review_one_answered_improvement(v_h);
  end loop;
  select string_agg(decision || '#' || round, ',' order by round) into v_decs from public.ceo_decision_round where item_key = 'ceo_improvement:' || v_i2;
  if v_decs is distinct from 'rejected#1,rejected#2,rejected#3,rejected#4' then v_bad := v_bad || ('guard_improvement_history:' || coalesce(v_decs, 'none')); end if;
  if not (v ? 'decision_owed') then v_bad := v_bad || 'improvement_guard_not_owed'::text; end if;
  select id into v_held from public.reasoning_held_question where dedupe_key = 'ceo_decision_owed:ceo_improvement:' || v_i2 || ':g1:after_r4';
  perform public.fn_reason_held_resolve(v_held, jsonb_build_object('status', 'answered', 'model', c_ceo,
    'answer', 'Withdrawn: the seat has declined this improvement four times with its reasons, so the CEO drops it.',
    'decision', jsonb_build_object('choice', 'withdraw')));
  r := r || jsonb_build_object('guard_improvement', (select string_agg(decision || '#' || round, ',' order by round) from public.ceo_decision_round where item_key = 'ceo_improvement:' || v_i2),
                               'improvement2', (select status from public.ceo_improvement where id = v_i2) || ':' || (select status from public.agent_actions where id = v_h));
  if r->>'improvement2' <> 'dropped:done' then v_bad := v_bad || 'withdrawn_improvement_not_dropped'::text; end if;

  -- ── H. THE SALES-ESCALATION CHOICE SAYS WHY ───────────────────────────────────────────────────────────────
  v_h := public.fn_seat_handoff('sales_engineer', 'ceo', 'sales.escalation', 'zz_probe', 'zz-probe-escalation',
           '{"escalation":"disputed_reveal","demo":true,"case":{"note":"ZZ DEMO"}}'::jsonb);
  select id into v_held from public.reasoning_held_question where dedupe_key = 'sales_escalation:' || v_h;
  v_err := null;
  begin
    perform public.fn_reason_apply_ceo__sales_escalation(v_held, '{"answer":"ok","decision":{"choice":"uphold_reveal"}}'::jsonb);
    v_bad := v_bad || 'reasonless_escalation_answer_accepted'::text;
  exception when check_violation then v_err := sqlerrm; end;
  if coalesce(v_err, '') !~ 'REASONLESS_DECISION' then v_bad := v_bad || 'escalation_reasonless_wrong_reason'::text; end if;
  perform public.fn_reason_apply_ceo__sales_escalation(v_held,
    '{"answer":"Upheld: the reveal was delivered as the terms say and both parties are told why.","decision":{"choice":"uphold_reveal"}}'::jsonb);
  if (select status from public.agent_actions where id = v_h) <> 'done' then v_bad := v_bad || 'reasoned_escalation_not_closed'::text; end if;

  -- ── I. EVERY ACTIVE CEO RULE HAS AN EVALUATOR ─────────────────────────────────────────────────────────────
  v := public.fn_ceo_decisions_evaluate(true);
  r := r || jsonb_build_object('evaluator_error', v->>'error',
    'directive_escalation', (select x->>'state' from jsonb_array_elements(v->'rules') x where x->>'rule' = 'directive_escalation'));
  if coalesce(v->>'error', '') ~ 'directive_escalation' or r->>'directive_escalation' is distinct from 'decided_by_its_duty' then
    v_bad := v_bad || 'directive_escalation_unevaluated'::text;
  end if;

  -- ── J. NOTHING HERE REACHED A PERSON ──────────────────────────────────────────────────────────────────────
  if exists (select 1 from public.refunds where id in (v_rf1, v_rf2) and (customer_id is not null or supplier_lead_id is not null)) then
    v_bad := v_bad || 'a_probe_refund_names_a_person'::text;
  end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED' end, 'bad', v_bad, 'r', r);
end $probe$;
