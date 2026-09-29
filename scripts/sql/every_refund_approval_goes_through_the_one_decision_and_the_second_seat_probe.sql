-- PROBE: EVERY REFUND APPROVAL GOES THROUGH THE ONE DECISION AND THE SECOND SEAT (29 Sep 2026; seat: accountant).
--
-- A pure probe: it always ends in raise exception 'CHK<<...>>', so every row it writes rolls back. Run it AFTER
-- every_refund_approval_goes_through_the_one_decision_and_the_second_seat.sql (or after it in the same rolled-back
-- transaction). The verdict is the first key of the CHK payload: PROBE OK, or PROBE FAILED with what failed.
-- Against the bodies that file replaces it reports PROBE FAILED (the negative control).
--
-- NOTHING HERE CAN REACH A PERSON, A MODEL OR STRIPE. Every subject is a ZZ DEMO fixture made here: transactions and
-- refunds with no customer and no supplier (pi_zzdemo_*), deliberations flagged demo, an experiment and an
-- improvement keyed zz_probe. No edge function is called, so no money can move. fn_ceo_refund_checklist is stubbed
-- to pass and fn_high_stakes_clearance is wrapped to answer 'disagreed' when qd.zz_disagree is on, for THIS
-- transaction only (catalog changes are transactional and invisible to every other session).
--
-- WHAT IT PROVES
--   refunds, every approval path runs the second seat (a seat_deliberation on refunds:<id> exists, status 'approved'
--   only after it):
--     A. fn_ceo_refund_review approves through fn_refund_decide;
--     B. ceo_agent decide (ceo_approval + link): paying it straight from 'requested' is refused; fn_refund_decide approves;
--     C. writing status 'approved' directly is refused;
--     D. a second seat that disagrees holds the refund 'requested', and a re-review asks the one decision again;
--     E. a top-up of an undecided refund may not be paid;
--     F. refund_case: a direct 'ceo_authorized' is refused; fn_ceo_decide_refund authorises through fn_refund_decide;
--     G. a Stripe event does not claim an undecided refund by payment intent.
--   reasons (the #1128 bypass): a direct UPDATE without reasons is refused on ceo_experiment, ceo_improvement and
--   seat_deliberation_turn with REASONLESS_DECISION.
--
--   node scripts/apply_sql.mjs scripts/sql/every_refund_approval_goes_through_the_one_decision_and_the_second_seat_probe.sql --apply

do $probe$
declare
  v_bad text[] := '{}'; r jsonb := '{}'::jsonb; v jsonb; v_err text; v_dec bigint;
  v_tx uuid[] := '{}'; v_rf bigint[] := '{}'; v_t uuid; v_id bigint; i int; v_e bigint; v_i bigint; v_d bigint; v_turn bigint;
  c_why constant text := 'ZZ DEMO the supplier never answered inside the window, so the fee returns to the customer in full';
  c_ceo constant text := 'google/gemini-3.8-flash';
begin
  execute $stub$
    create or replace function public.fn_ceo_refund_checklist(p_transaction_id uuid, p_phase text, p_record boolean default true)
    returns jsonb language sql set search_path to 'public', 'pg_temp' as $s$
      select jsonb_build_object('ok', true, 'phase', p_phase, 'transaction_id', p_transaction_id,
               'items', jsonb_build_array(jsonb_build_object('item', 'zz_probe_check', 'passed', true)), 'failed', '[]'::jsonb)
    $s$ $stub$;
  execute 'alter function public.fn_high_stakes_clearance(text, text, text) rename to fn_high_stakes_clearance_zz_orig';
  execute $stub$
    create function public.fn_high_stakes_clearance(p_kind text, p_table text, p_id text)
    returns jsonb language sql set search_path to 'public', 'pg_temp' as $s$
      select case when current_setting('qd.zz_disagree', true) = 'on'
                  then jsonb_build_object('state', 'disagreed', 'cleared', false)
                  else public.fn_high_stakes_clearance_zz_orig(p_kind, p_table, p_id) end
    $s$ $stub$;

  for i in 1..8 loop
    insert into public.transactions (payment_ref, total_charged, reveal_fee, refund_deadline)
    values ('pi_zzdemo_onedecision_' || i, 100, 100, now() - interval '1 day') returning id into v_t;
    insert into public.refunds (transaction_id, stripe_payment_intent, amount_fils, currency, reason_code, reason_note, requested_by, status)
    values (v_t, 'pi_zzdemo_onedecision_' || i, 10000, 'AED', 'supplier_unresponsive', 'ZZ DEMO one-decision probe ' || i, 'customer', 'requested')
    returning id into v_id;
    v_tx := v_tx || v_t; v_rf := v_rf || v_id;
  end loop;

  -- ── A. fn_ceo_refund_review ────────────────────────────────────────────────────────────────────────────
  v := public.fn_ceo_refund_review(v_rf[1], 'zz_probe');
  r := r || jsonb_build_object('A_review', v->'outcome', 'A_status', (select status from public.refunds where id = v_rf[1]));
  if (select status from public.refunds where id = v_rf[1]) <> 'approved' then v_bad := v_bad || 'A_review_did_not_approve_through_the_one_decision'::text; end if;
  if not exists (select 1 from public.seat_deliberation where subject_table = 'refunds' and subject_id = v_rf[1]::text) then
    v_bad := v_bad || 'A_review_skipped_the_second_seat'::text;
  end if;

  -- ── B. ceo_agent decide: the approval and the link, then the accountant's pay step ──────────────────────
  insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
  values ('refund', v_rf[2]::text, 'approved', 'ceo', 100, c_why) returning decision_id into v_dec;
  update public.refunds set refund_decision_id = v_dec, decided_by = 'ceo', decided_at = now() where id = v_rf[2];
  v_err := null;
  begin
    update public.refunds set status = 'processing', stripe_refund_id = 're_zzdemo_b' where id = v_rf[2];
    v_bad := v_bad || 'B_paid_from_requested_without_the_one_decision'::text;
  exception when others then v_err := sqlerrm; end;
  r := r || jsonb_build_object('B_pay_refused', v_err);
  if coalesce(v_err, '') !~ 'REFUND_NOT_DECIDED' then v_bad := v_bad || 'B_pay_refused_for_the_wrong_reason'::text; end if;
  v := public.fn_refund_decide(v_rf[2], true, 'ceo', null);
  if (select status from public.refunds where id = v_rf[2]) <> 'approved'
     or not exists (select 1 from public.seat_deliberation where subject_table = 'refunds' and subject_id = v_rf[2]::text) then
    v_bad := v_bad || ('B_decide:' || coalesce(v::text, 'null'));
  end if;
  update public.refunds set status = 'processing', stripe_refund_id = 're_zzdemo_b' where id = v_rf[2];   -- now allowed

  -- ── C. a direct 'approved' ─────────────────────────────────────────────────────────────────────────────
  insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
  values ('refund', v_rf[3]::text, 'approved', 'ceo', 100, c_why) returning decision_id into v_dec;
  v_err := null;
  begin
    update public.refunds set status = 'approved', refund_decision_id = v_dec, decided_by = 'ceo', decided_at = now() where id = v_rf[3];
    v_bad := v_bad || 'C_direct_approved_stored'::text;
  exception when others then v_err := sqlerrm; end;
  r := r || jsonb_build_object('C_direct_approved_refused', v_err);
  if coalesce(v_err, '') !~ 'REFUND_NOT_DECIDED' then v_bad := v_bad || 'C_refused_for_the_wrong_reason'::text; end if;

  -- ── D. the second seat disagrees ───────────────────────────────────────────────────────────────────────
  perform set_config('qd.zz_disagree', 'on', true);
  v := public.fn_ceo_refund_review(v_rf[4], 'zz_probe');
  r := r || jsonb_build_object('D_review', v->'decide'->'error', 'D_status', (select status from public.refunds where id = v_rf[4]));
  if (select status from public.refunds where id = v_rf[4]) <> 'requested' or coalesce(v->'decide'->>'error', '') <> 'awaiting_second_seat' then
    v_bad := v_bad || 'D_disagreement_did_not_hold_the_refund'::text;
  end if;
  v := public.fn_ceo_refund_review(v_rf[4], 'zz_probe');
  if coalesce(v->'decide'->>'error', '') <> 'awaiting_second_seat' then v_bad := v_bad || 'D_rereview_did_not_ask_the_one_decision_again'::text; end if;
  perform set_config('qd.zz_disagree', 'off', true);
  v := public.fn_ceo_refund_review(v_rf[4], 'zz_probe');
  if (select status from public.refunds where id = v_rf[4]) <> 'approved' then v_bad := v_bad || 'D_cleared_rereview_did_not_approve'::text; end if;

  -- ── E. a top-up of an undecided refund ─────────────────────────────────────────────────────────────────
  insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
  values ('refund', v_rf[5]::text, 'approved', 'ceo', 100, c_why) returning decision_id into v_dec;
  update public.refunds set refund_decision_id = v_dec, decided_by = 'ceo', decided_at = now() where id = v_rf[5];
  update public.transactions set total_charged = 200 where id = v_tx[5];   -- room for a top-up
  v := public.fn_accountant_reserves_topup(v_tx[5], 1000, -1);
  r := r || jsonb_build_object('E_reserve', v);
  if coalesce((v->>'ok')::boolean, false) then v_bad := v_bad || 'E_topup_reserved_on_an_undecided_refund'::text; end if;
  -- and should a top-up row exist anyway, the database refuses paying it
  if coalesce((v->>'ok')::boolean, false) then
    v_id := (v->>'refund_id')::bigint;
  else
    insert into public.refunds (transaction_id, stripe_payment_intent, amount_fils, currency, reason_code, reason_note, requested_by, status,
                                topup_of, refund_decision_id, decided_by, decided_at, amount_source)
    values (v_tx[5], 'pi_zzdemo_onedecision_5', 1000, 'AED', 'supplier_unresponsive', 'incident.fix #-1: ZZ DEMO probe top-up', 'accountant',
            'requested', v_rf[5], v_dec, 'ceo', now(), 'in_platform_request') returning id into v_id;
  end if;
  v_err := null;
  begin
    update public.refunds set status = 'processing', stripe_refund_id = 're_zzdemo_e' where id = v_id;
    v_bad := v_bad || 'E_topup_of_undecided_refund_paid'::text;
  exception when others then v_err := sqlerrm; end;
  r := r || jsonb_build_object('E_pay_refused', v_err);
  if coalesce(v_err, '') !~ 'REFUND_NOT_DECIDED' then v_bad := v_bad || 'E_refused_for_the_wrong_reason'::text; end if;

  -- ── F. the refund_case rail (its own numbering: a case is NOT a public.refunds id) ──────────────────────
  insert into public.refund_case (transaction_id, amount_aed, currency, requested_reason, state)
  values (v_tx[6], 100, 'AED', 'ZZ DEMO one-decision probe', 'eligible') returning refund_id into v_id;
  v_err := null;
  begin
    update public.refund_case set state = 'ceo_authorized', decided_by = 'ceo', decided_at = now(), decision = 'approved',
           decision_rationale = c_why where refund_id = v_id;
    v_bad := v_bad || 'F_direct_authorisation_stored'::text;
  exception when others then v_err := sqlerrm; end;
  r := r || jsonb_build_object('F_direct_refused', v_err);
  if coalesce(v_err, '') !~ 'REFUND_NOT_DECIDED' then v_bad := v_bad || 'F_refused_for_the_wrong_reason'::text; end if;
  perform set_config('qd.zz_disagree', 'on', true);
  v := public.fn_ceo_decide_refund(v_id, true, c_why);
  if (select state from public.refund_case where refund_id = v_id) = 'ceo_authorized' then v_bad := v_bad || 'F_authorised_over_a_disagreeing_second_seat'::text; end if;
  perform set_config('qd.zz_disagree', 'off', true);
  v := public.fn_ceo_decide_refund(v_id, true, c_why);
  r := r || jsonb_build_object('F_decide', v->'ok', 'F_state', (select state from public.refund_case where refund_id = v_id));
  if (select state from public.refund_case where refund_id = v_id) <> 'ceo_authorized'
     or not exists (select 1 from public.seat_deliberation where subject_table = 'refund_case' and subject_id = v_id::text) then
    v_bad := v_bad || ('F_decide_refund:' || coalesce(v::text, 'null'));
  end if;

  -- ── G. a Stripe event on an undecided refund's payment ─────────────────────────────────────────────────
  v_err := null;
  begin
    v := public.fn_refund_settle('re_zzdemo_g', 'succeeded', 10000, 'pi_zzdemo_onedecision_7');
  exception when others then v_err := sqlerrm; v_bad := v_bad || 'G_stripe_event_raised_on_an_undecided_refund'::text; end;
  r := r || jsonb_build_object('G_status', (select status from public.refunds where id = v_rf[7]), 'G_error', v_err);
  if (select status from public.refunds where id = v_rf[7]) <> 'requested' then v_bad := v_bad || 'G_stripe_event_claimed_an_undecided_refund'::text; end if;

  -- ── H. ceo_experiment: a direct decision without reasons ───────────────────────────────────────────────
  v_e := public.fn_ceo_experiment_propose('accountant', 'zz_probe_one_decision', 'ZZ DEMO a probe hypothesis',
           'reveal_conversion_pct', 'ZZ DEMO a probe metric', null, 'ZZ DEMO no baseline in the probe', 5, 'min',
           'ZZ DEMO a probe approach', current_date + 1, 14);
  v_err := null;
  begin
    update public.ceo_experiment set status = 'approved', approval = '{"decision":"approve","reasoning":"ok"}'::jsonb where id = v_e;
    v_bad := v_bad || 'H_reasonless_experiment_decision_stored'::text;
  exception when others then v_err := sqlerrm; end;
  r := r || jsonb_build_object('H', v_err);
  if coalesce(v_err, '') !~ 'REASONLESS_DECISION' then v_bad := v_bad || 'H_refused_for_the_wrong_reason'::text; end if;

  -- ── I. ceo_improvement: a direct drop without reasons ──────────────────────────────────────────────────
  v_i := public.fn_ceo_improvement_open('self_review', 'zz-probe-one-decision', 'accountant', 'ZZ DEMO a probe improvement', '{"probe":true}'::jsonb);
  v_err := null;
  begin
    update public.ceo_improvement set status = 'dropped', closed_at = now(), done_evidence = 'dropped' where id = v_i;
    v_bad := v_bad || 'I_reasonless_drop_stored'::text;
  exception when others then v_err := sqlerrm; end;
  r := r || jsonb_build_object('I', v_err);
  if coalesce(v_err, '') !~ 'REASONLESS_DECISION' then v_bad := v_bad || 'I_refused_for_the_wrong_reason'::text; end if;

  -- ── J. seat_deliberation_turn: a CEO comparison stripped of its reasons ────────────────────────────────
  v_d := public.fn_seat_deliberation_open('zz_probe.one_decision', 'accountant', 'ceo', 'ZZ DEMO probe: judge the accountant''s call',
           '{"facts":"a probe fact"}'::jsonb, '{"answer":"a probe answer"}'::jsonb, 'deterministic', null, 'zz_probe', 'one_decision', true);
  insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, model, verdict, steelman_against)
  values (v_d, 1, 'blind', 'ceo', 'recorded', c_ceo, 'approve', 'the customer may have been answered by phone outside the platform');
  insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, model, verdict, steelman_against, agreements, disagreements)
  values (v_d, 1, 'compare', 'ceo', 'recorded', c_ceo, 'approve', 'a phone answer would leave no trace we could ever check',
          'the window closed with no supplier reply on any channel we can read', 'none')
  returning id into v_turn;
  v_err := null;
  begin
    update public.seat_deliberation_turn set agreements = 'ok' where id = v_turn;
    v_bad := v_bad || 'J_turn_update_stored'::text;
  exception when others then v_err := sqlerrm; end;
  r := r || jsonb_build_object('J', v_err);
  if coalesce(v_err, '') !~ 'REASONLESS_DECISION' then v_bad := v_bad || 'J_refused_for_the_wrong_reason'::text; end if;

  -- ── K. NOTHING HERE REACHED A PERSON ────────────────────────────────────────────────────────────────────
  if exists (select 1 from public.refunds where id = any(v_rf) and (customer_id is not null or supplier_lead_id is not null)) then
    v_bad := v_bad || 'a_probe_refund_names_a_person'::text;
  end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED' end, 'bad', v_bad, 'r', r);
end $probe$;
