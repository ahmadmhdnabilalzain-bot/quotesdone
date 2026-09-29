-- EVERY REFUND APPROVAL GOES THROUGH THE ONE DECISION AND THE SECOND SEAT (29 Sep 2026; seat: accountant).
--
-- WHAT WAS WRONG (read from production 29 Sep 2026, not from a brief):
--   fn_refund_decide(true) holds the second-seat check (fn_high_stakes_gate, instruction 1009), and nothing
--   called it with true. Every approval path skipped it:
--     1. fn_ceo_refund_review, approve branch: writes ceo_approval and refunds.refund_decision_id and leaves the
--        refund 'requested'.
--     2. ceo_agent 'decide' (refund, approved): inserts ceo_approval and links refund_decision_id the same way.
--     3. accountant execute_refunds: pays every refund with a refund_decision_id in ('requested','approved') and
--        moves it straight 'requested' -> 'processing'. z05 accepts that because the decision is cited.
--     4. fn_accountant_reserves_topup + the incident fix: a top-up row cites its parent's decision and is paid
--        'requested' -> 'processing', whether or not the parent ever cleared the second seat.
--     5. fn_refund_settle: a Stripe event matched to a 'requested' platform refund by payment intent moved it to
--        'processing'/'succeeded' with no decision step at all.
--     6. fn_ceo_decide_refund (the refund_case rail): 'ceo_authorized' with no second seat.
--   z05 (fn_refund_execution_requires_ceo_approval) still refused any payment without a matching CEO approval,
--   so no refund could move without the CEO. What was skipped was the second seat.
--
-- WHAT THIS DOES: fn_refund_decide is the ONE place a refund becomes approved, and the database refuses every
-- other route:
--   * fn_refund_decide marks its own transaction (qd.refund_decide = the refund id) before it writes 'approved'.
--   * z04_refund_approval_is_the_one_decision (BEFORE on refunds) refuses 'approved' without that mark, and
--     refuses a platform refund reaching 'processing'/'succeeded' from 'requested' (or on insert): money moves
--     only after 'approved'. A top-up moves only when the refund it tops up has been approved. A retry from
--     'failed' is unchanged (it was approved before it failed). Refunds Stripe issued outside the platform are
--     facts, recorded as before (same exemption as z05).
--   * a00_refund_case_authorisation_is_the_one_decision (BEFORE on refund_case): 'ceo_authorized' only through
--     fn_ceo_decide_refund, which now asks the same second-seat gate on the case. refund_case numbers its cases
--     from its own sequence, so it cannot share fn_refund_decide; it shares the gate instead (code review, 29 Sep).
--   * fn_accountant_reserves_topup tops up only a refund that fn_refund_decide approved.
--   * fn_ceo_refund_review calls fn_refund_decide(true) after recording the approval, and a re-run on an already
--     decided refund asks fn_refund_decide again (so a refund waiting on the second seat is retried, not skipped).
--   * fn_refund_settle no longer claims a 'requested' refund: an out-of-band Stripe refund on a payment whose
--     platform refund is still undecided is recorded as the external fact it is.
--   ceo_agent (decide) and accountant (execute_refunds) change with this file: decide calls fn_refund_decide,
--   execute_refunds asks fn_refund_decide before Stripe when a decided refund is still 'requested'.
-- No money guard is loosened: z00, z05, a00, a01, a05 and the checklist run exactly as before.
--
-- Prevented by: scripts/sql/every_refund_approval_goes_through_the_one_decision_and_the_second_seat_probe.sql
-- (fails against the bodies this file replaces).

-- ── 1. THE ONE DECISION ─────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_refund_decide(p_refund_id bigint, p_approve boolean, p_decided_by text, p_note text default null::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r public.refunds; v_app public.ceo_approval; v_new text; v_gate jsonb;
begin
  select * into r from public.refunds where id = p_refund_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'requested' then return jsonb_build_object('ok', false, 'error', 'not_decidable', 'status', r.status); end if;
  if coalesce(btrim(p_decided_by), '') = '' then return jsonb_build_object('ok', false, 'error', 'decider_required'); end if;
  if lower(btrim(p_decided_by)) like 'policy:%' then
    return jsonb_build_object('ok', false, 'error', 'automatic_decider_refused',
      'hint', 'A refund is decided by an actor, not by a rule. Approvals are the CEO''s.');
  end if;

  if p_approve then
    select * into v_app from public.ceo_approval a
     where a.subject_kind = 'refund' and a.subject_id = p_refund_id::text and a.decision = 'approved' and a.superseded_by is null
     order by a.decision_id desc limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'no_ceo_approval',
        'hint', 'A refund is approved only by a CEO approval that passed the process checklist (fn_ceo_refund_review, or ceo_agent decide). This routine records that decision; it cannot make one.');
    end if;
    -- The window: a00 refuses 'approved' before refund_deadline. Answered here instead of raised, so a CEO review
    -- run early keeps its approval; the accountant asks this routine again before it pays.
    if exists (select 1 from public.transactions t where t.id = r.transaction_id and now() < t.refund_deadline) then
      return jsonb_build_object('ok', false, 'error', 'window_not_open',
        'decision_after', (select t.refund_deadline from public.transactions t where t.id = r.transaction_id));
    end if;
    -- A REFUND IS HIGH STAKES (29 Sep 2026, instruction 1009): a second seat on another family must agree first. While
    -- the model hold is on the refund proceeds and the review is owed; a later disagreement opens a finding.
    v_gate := public.fn_high_stakes_gate('refund', 'ceo', 'refunds', p_refund_id::text,
      'Should this refund be approved as the CEO decided?',
      jsonb_build_object('refund', jsonb_build_object('amount_fils', r.amount_fils, 'currency', r.currency, 'reason_code', r.reason_code,
        'reason_note', left(r.reason_note, 1000), 'requested_by', r.requested_by, 'within_auto_window', r.within_auto_window)),
      jsonb_build_object('decision', 'approve', 'ceo_rationale', left(v_app.rationale, 3000), 'amount_aed', v_app.amount_aed));
    if not coalesce((v_gate->>'proceed')::boolean, false) then
      return jsonb_build_object('ok', false, 'error', 'awaiting_second_seat', 'clearance', v_gate);
    end if;
    -- the mark z04 (refunds) and a00 (refund_case) read: this refund was approved here, after the second seat
    perform set_config('qd.refund_decide', p_refund_id::text, true);
    update public.refunds set status = 'approved', decided_by = v_app.decided_by, decided_at = now(),
           decision_note = coalesce(p_note, v_app.rationale), refund_decision_id = v_app.decision_id
     where id = p_refund_id;
    v_new := 'approved';
  else
    update public.refunds set status = 'rejected', decided_by = p_decided_by, decided_at = now(), decision_note = p_note where id = p_refund_id;
    v_new := 'rejected';
  end if;
  if r.transaction_id is not null then
    update public.transactions set refund_status = v_new, refund_resolved_at = now(), refund_note = coalesce(p_note, refund_note)
     where id = r.transaction_id;
  end if;
  return jsonb_build_object('ok', true, 'refund_id', p_refund_id, 'status', v_new, 'decided_by', coalesce(v_app.decided_by, p_decided_by),
                            'second_seat', v_gate);
end $function$;

-- ── 2. THE GUARD: NO OTHER ROUTE TO 'approved', AND NO MONEY BEFORE IT ──────────────────────────────────────
create or replace function public.fn_refund_approval_is_the_one_decision()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_parent text;
begin
  -- a refund Stripe issued outside the platform is a fact to record, not a request to approve (as z05)
  if lower(coalesce(new.requested_by, '')) in ('stripe_webhook', 'stripe_dashboard', 'stripe') then return new; end if;

  if new.status = 'approved' and (tg_op = 'INSERT' or old.status is distinct from 'approved')
     and coalesce(current_setting('qd.refund_decide', true), '') is distinct from new.id::text then
    raise exception using errcode = 'check_violation',
      message = 'REFUND_NOT_DECIDED: refund ' || coalesce(new.id::text, '(new)') || ' becomes approved only through fn_refund_decide',
      hint = 'fn_refund_decide runs the second-seat check (instruction 1009) before a refund is approved. Write the CEO approval, then call it.';
  end if;

  if new.status in ('processing', 'succeeded')
     and (tg_op = 'INSERT' or old.status not in ('approved', 'processing', 'succeeded', 'failed')) then
    if new.topup_of is not null then
      select status into v_parent from public.refunds where id = new.topup_of;
      if v_parent in ('approved', 'processing', 'succeeded') then return new; end if;
    end if;
    raise exception using errcode = 'check_violation',
      message = 'REFUND_NOT_DECIDED: refund ' || coalesce(new.id::text, '(new)') || ' may not reach ' || new.status
             || ' from ' || case when tg_op = 'INSERT' then 'nothing' else old.status end || '; money moves only after fn_refund_decide approved it',
      hint = case when new.topup_of is not null
                  then 'A top-up moves only after the refund it tops up (#' || new.topup_of || ') was approved; that one is ' || coalesce(v_parent, 'missing') || '.'
                  else 'Approve it through fn_refund_decide first (it runs the second-seat check), then pay it.' end;
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_refund_approval_is_the_one_decision() from public, anon, authenticated;
drop trigger if exists z04_refund_approval_is_the_one_decision on public.refunds;
create trigger z04_refund_approval_is_the_one_decision before insert or update on public.refunds
  for each row execute function public.fn_refund_approval_is_the_one_decision();

create or replace function public.fn_refund_case_authorisation_is_the_one_decision()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
begin
  if new.state = 'ceo_authorized' and (tg_op = 'INSERT' or old.state is distinct from 'ceo_authorized')
     and coalesce(current_setting('qd.refund_case_decide', true), '') is distinct from new.refund_id::text then
    raise exception using errcode = 'check_violation',
      message = 'REFUND_NOT_DECIDED: refund case ' || new.refund_id || ' is authorised only by fn_ceo_decide_refund, after the second seat',
      hint = 'fn_ceo_decide_refund runs the second-seat check (instruction 1009) on the case before it authorises it.';
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_refund_case_authorisation_is_the_one_decision() from public, anon, authenticated;
drop trigger if exists a00_refund_case_authorisation_is_the_one_decision on public.refund_case;
create trigger a00_refund_case_authorisation_is_the_one_decision before insert or update on public.refund_case
  for each row execute function public.fn_refund_case_authorisation_is_the_one_decision();

-- ── 3. THE CEO'S REVIEW APPROVES THROUGH THE ONE DECISION ──────────────────────────────────────────────────
create or replace function public.fn_ceo_refund_review(p_refund_id bigint, p_trigger text default 'manual'::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  r public.refunds; v jsonb; v_cycle int; v_nonrem jsonb; v_rev bigint; v_dec bigint; x record; v_task bigint;
  v_tasks jsonb := '[]'::jsonb; v_rat text; v_deadline timestamptz; v_chase int; v_adv jsonb;
  v_wait boolean := false;   -- a check still being reasoned (23 Sep 2026)
  v_item text := 'refunds:' || p_refund_id; v_ids bigint[] := '{}'; v_cyc jsonb; v_fin jsonb;
begin
  select * into r from public.refunds where id = p_refund_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such refund'); end if;
  if r.status <> 'requested' then return jsonb_build_object('ok', false, 'reason', 'refund is ' || r.status || '; the CEO reviews only an open request'); end if;
  -- Already decided by the CEO but not yet approved: the one decision is asked again (it may have been waiting on
  -- the second seat), never skipped.
  if r.refund_decision_id is not null then
    v_fin := public.fn_refund_decide(r.id, true, 'ceo', null);
    return jsonb_build_object('ok', coalesce((v_fin->>'ok')::boolean, false), 'outcome', 'already_approved',
                              'decision_id', r.refund_decision_id, 'decide', v_fin);
  end if;
  if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'refund.remediate'
               and a.detail->>'refund_id' = r.id::text and a.status = 'pending') then
    return jsonb_build_object('ok', false, 'outcome', 'waiting_on_remediation');
  end if;
  select coalesce(max(cycle), 0) + 1 into v_cycle from public.refund_ceo_review where refund_id = r.id;
  v := public.fn_ceo_refund_checklist(r.transaction_id, 'approve', true);

  if (v->>'ok')::boolean then
    v_rat := 'Cycle ' || v_cycle || ': every pre-approval check passed ('
          || (select string_agg(i->>'item', ', ') from jsonb_array_elements(v->'items') i) || '). Evidence: refund_ceo_check for this transaction.';
    insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
    values ('refund', r.id::text, 'approved', 'ceo', round(r.amount_fils / 100.0, 2), v_rat) returning decision_id into v_dec;
    update public.refunds set refund_decision_id = v_dec, decided_by = 'ceo', decided_at = now(), decision_note = v_rat where id = r.id;
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, decision_id, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'approved', v_dec, p_trigger, true) returning id into v_rev;
    v_cyc := public.fn_ceo_decide('refund', v_item, 'accountant', 'approved', v_rat,
               jsonb_build_object('refund_id', r.id, 'cycle', v_cycle, 'decision_id', v_dec), 'refund_ceo_review', v_rev::text);
    -- THE ONE DECISION (29 Sep 2026): the approval above is the CEO's; the refund becomes approved only through
    -- fn_refund_decide, which runs the second-seat check. Waiting on it leaves the refund requested and decided.
    v_fin := public.fn_refund_decide(r.id, true, 'ceo', v_rat);
    return jsonb_build_object('ok', true, 'outcome', 'approved', 'cycle', v_cycle, 'decision_id', v_dec, 'round', v_cyc, 'decide', v_fin);
  end if;

  select coalesce(jsonb_agg(i), '[]'::jsonb) into v_nonrem from jsonb_array_elements(v->'failed') i where not coalesce((i->>'remediable')::boolean, false);
  if jsonb_array_length(v_nonrem) > 0 then
    v_rat := 'Declined, because these checks cannot be fixed and the refund is not paid: '
          || (select string_agg((i->>'item') || ' — ' || coalesce(i->>'reason', ''), '; ') from jsonb_array_elements(v_nonrem) i);
    v_adv := public.fn_ceo_refund_decline(r.id, v_rat, p_trigger, v->'failed');
    v_cyc := public.fn_ceo_decide('refund', v_item, 'accountant', 'withdrawn', left(v_rat, 3000),
               jsonb_build_object('refund_id', r.id, 'cycle', v_adv->'cycle', 'decision_id', v_adv->'decision_id', 'failed', v->'failed'),
               'refund_ceo_review', v_adv->>'review_id');
    return jsonb_build_object('ok', true, 'outcome', 'declined', 'cycle', v_adv->'cycle', 'reason', v_rat, 'round', v_cyc);
  end if;

  -- A CHECK THAT IS STILL BEING REASONED IS NOT A FAILURE (23 Sep 2026, founder_instruction 886-903).
  -- Under the model hold the off-platform notes wait in the CEO seat's reasoning queue. Counting that as a
  -- rejected cycle would hand work to nobody who can do it. So the refund rests, visible, with no cycle spent;
  -- the reasoned answer re-runs this review (fn_reason_apply_ceo__refund_off_platform).
  -- Only the unread note fails: the refund rests. Other remediable failures still go to their owners below.
  v_wait := exists (select 1 from jsonb_array_elements(v->'failed') i where i->>'kind' = 'needs_reasoning');
  if v_wait and not exists (select 1 from jsonb_array_elements(v->'failed') i where coalesce(i->>'kind', '') <> 'needs_reasoning') then
    return jsonb_build_object('ok', false, 'outcome', 'waiting_on_reasoning',
      'held', (select jsonb_agg(i->'evidence') from jsonb_array_elements(v->'failed') i where i->>'kind' = 'needs_reasoning'));
  end if;

  v_rat := 'Cycle ' || v_cycle || ': these checks still fail and go back to the seats that own them: '
        || (select string_agg((i->>'item') || ' (' || coalesce(i->>'reason', 'no reason recorded') || ')', '; ')
              from jsonb_array_elements(v->'failed') i where coalesce(i->>'kind', '') <> 'needs_reasoning');

  -- THE LOOP GUARD (founder_instruction 1059), in place of the founder page after three cycles: after 4
  -- rejections the CEO approves, replaces or withdraws, with reasons. The escalated row records the stop, once:
  -- while the CEO's choice is owed a re-run answers that and writes nothing. (An approval above is never held by
  -- it: a refund whose checks now pass is approved, which settles what was owed.)
  if (public.fn_ceo_decision_next(v_item)->>'rejections')::int >= 4 then
    -- a check still being reasoned is not a rejection the CEO must act on: the refund rests, as above
    if v_wait then
      return jsonb_build_object('ok', false, 'outcome', 'waiting_on_reasoning', 'at_loop_guard', true);
    end if;
    if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending'
                 and a.detail->>'type' = 'ceo.decision_owed' and a.detail->>'item_key' = v_item) then
      return jsonb_build_object('ok', false, 'outcome', 'awaiting_ceo_replace_or_withdraw', 'cycle', v_cycle - 1);
    end if;
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'escalated', v->'failed', p_trigger, true) returning id into v_rev;
    v_cyc := public.fn_ceo_decide('refund', v_item, 'accountant', 'rejected', v_rat,
               jsonb_build_object('refund_id', r.id, 'cycle', v_cycle, 'failed', v->'failed'), 'refund_ceo_review', v_rev::text);
    return jsonb_build_object('ok', false, 'outcome', 'awaiting_ceo_replace_or_withdraw', 'cycle', v_cycle, 'round', v_cyc);
  end if;

  insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, trigger)
  values (r.id, r.transaction_id, v_cycle, 'rejected', v->'failed', p_trigger) returning id into v_rev;
  select chase_after_working_days into v_chase from public.pricing_config order by id limit 1;
  v_deadline := public.fn_add_working_days(now(), coalesce(v_chase, 3));
  for x in
    select i->>'owner' as owner, i->>'remedy_key' as rk, jsonb_agg(i->>'item') as checks, jsonb_agg(i) as items
      from jsonb_array_elements(v->'failed') i where coalesce(i->>'kind', '') <> 'needs_reasoning' group by 1, 2 order by 1, 2
  loop
    v_task := public.fn_seat_handoff('ceo', x.owner, 'refund.remediate', 'refunds', r.id || ':c' || v_cycle || ':' || x.rk,
      jsonb_build_object('refund_id', r.id, 'transaction_id', r.transaction_id, 'cycle', v_cycle, 'review_id', v_rev,
                         'remedy_key', x.rk, 'checks', x.checks, 'items', x.items, 'deadline', v_deadline));
    v_tasks := v_tasks || jsonb_build_object('handoff_id', v_task, 'owner', x.owner, 'checks', x.checks);
    v_ids := v_ids || v_task;
  end loop;
  update public.refund_ceo_review set sealed = true, tasks = v_tasks where id = v_rev;
  v_cyc := public.fn_ceo_decide('refund', v_item, 'accountant', 'rejected', v_rat,
             jsonb_build_object('refund_id', r.id, 'cycle', v_cycle, 'failed', v->'failed', 'tasks', v_tasks), 'refund_ceo_review', v_rev::text, v_ids);
  v_adv := public.fn_ceo_refund_loop_advance(r.id);
  return jsonb_build_object('ok', false, 'outcome', 'rejected', 'cycle', v_cycle, 'tasks', v_tasks, 'advance', v_adv, 'round', v_cyc);
end $function$;

-- ── 4. THE REFUND_CASE RAIL AUTHORISES THROUGH THE ONE DECISION ─────────────────────────────────────────────
create or replace function public.fn_ceo_decide_refund(p_refund_id bigint, p_approve boolean, p_rationale text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_fin jsonb;
begin
  if coalesce(btrim(p_rationale), '') = '' then
    -- Applies to BOTH directions. The constitution asks for an evidence-based explanation on a
    -- denial specifically, and an approval with no reasoning is just as unauditable.
    return jsonb_build_object('ok', false, 'reason',
      'a rationale is required. A refund decided with no stated reasoning cannot be audited, and a denial owes the customer an explanation.');
  end if;

  select * into r from public.refund_case where refund_id = p_refund_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such refund case'); end if;

  if r.state not in ('eligible','ineligible','requested','investigating') then
    return jsonb_build_object('ok', false, 'reason',
      format('this refund is already %L. Deciding it again would be a second remedy on the same money.', r.state));
  end if;

  -- THE SECOND SEAT (29 Sep 2026, instruction 1009). refund_case numbers its cases from its own sequence
  -- (refund_case_refund_id_seq); they are NOT ids in public.refunds, so this rail cannot hand its case to
  -- fn_refund_decide (that would decide whichever refund shares the number). It asks the same gate on its own
  -- subject, and marks the case so a00 lets only this routine authorise it.
  if p_approve then
    v_fin := public.fn_high_stakes_gate('refund', 'ceo', 'refund_case', p_refund_id::text,
      'Should this refund be approved as the CEO decided?',
      jsonb_build_object('refund_case', jsonb_build_object('amount_aed', r.amount_aed, 'currency', r.currency,
        'requested_reason', left(r.requested_reason, 1000), 'transaction_id', r.transaction_id)),
      jsonb_build_object('decision', 'approve', 'ceo_rationale', left(p_rationale, 3000), 'amount_aed', r.amount_aed));
    if not coalesce((v_fin->>'proceed')::boolean, false) then
      return jsonb_build_object('ok', false, 'reason', 'awaiting_second_seat', 'clearance', v_fin);
    end if;
    perform set_config('qd.refund_case_decide', p_refund_id::text, true);
  end if;

  update public.refund_case
     set state = case when p_approve then 'ceo_authorized' else 'ceo_declined' end,
         decided_by = 'ceo', decided_at = now(),
         decision = case when p_approve then 'approved' else 'declined' end,
         decision_rationale = p_rationale, updated_at = now()
   where refund_id = p_refund_id;

  return jsonb_build_object('ok', true, 'refund_id', p_refund_id,
    'state', case when p_approve then 'ceo_authorized' else 'ceo_declined' end, 'decide', v_fin,
    'note', case when p_approve
                 then 'Authorised. Execution is the payment service''s, and the states stay separate: authorised is not submitted, and submitted is not settled.'
                 else 'Declined with a rationale. Support owes the customer that explanation and an appropriate alternative remedy -- a decline is not the end of the case.' end);
end $function$;

-- ── 5. A STRIPE EVENT NEVER CLAIMS AN UNDECIDED REFUND ──────────────────────────────────────────────────────
-- Unchanged except the payment-intent match: 'requested' is no longer claimed (it would move money-state on a
-- refund nobody approved). search_path gains pg_temp.
create or replace function public.fn_refund_settle(p_stripe_refund_id text, p_status text, p_amount_fils bigint default null::bigint, p_payment_intent text default null::text, p_charge_id text default null::text, p_failure_reason text default null::text, p_amount_source text default 'webhook_event'::text, p_stripe_event_id text default null::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r public.refunds; v_status text; v_amount bigint; v_src text; v_q bigint;
begin
  if coalesce(btrim(p_stripe_refund_id),'') = '' then
    v_q := public.fn_refund_quarantine(null, 'refund', 'event carried no refund id',
             jsonb_build_object('status', p_status, 'payment_intent', p_payment_intent), p_stripe_event_id);
    return jsonb_build_object('ok', false, 'error', 'stripe_refund_id_required', 'quarantined', v_q);
  end if;

  v_status := case lower(coalesce(p_status,''))
                when 'succeeded' then 'succeeded' when 'failed' then 'failed'
                when 'canceled' then 'cancelled'  when 'cancelled' then 'cancelled'
                else 'processing' end;
  v_amount := nullif(coalesce(p_amount_fils, 0), 0);
  v_src    := case when v_amount is null then null else coalesce(p_amount_source, 'webhook_event') end;

  select * into r from public.refunds where stripe_refund_id = p_stripe_refund_id for update;

  if not found then
    select * into r from public.refunds
     where stripe_refund_id is null and p_payment_intent is not null
       and stripe_payment_intent = p_payment_intent and status in ('approved','processing')
     order by created_at limit 1 for update;

    if found then
      update public.refunds set stripe_refund_id = p_stripe_refund_id,
             stripe_charge_id = coalesce(p_charge_id, stripe_charge_id) where id = r.id;
    else
      -- Issued outside the platform. Recorded with whatever is actually known, and NOTHING invented:
      -- if the amount is unknown it stays NULL and the row is marked unreconciled.
      insert into public.refunds (stripe_refund_id, stripe_payment_intent, stripe_charge_id,
                                  amount_fils, amount_source, reason_code, reason_note, requested_by, status,
                                  decided_by, decided_at, decision_note, reconciliation_note)
      values (p_stripe_refund_id, p_payment_intent, p_charge_id, v_amount,
              coalesce(v_src, 'unknown'), 'other',
              'Issued outside QuotesDone (Stripe dashboard or API). Recorded by the webhook.',
              'stripe_webhook', coalesce(v_status, 'processing'), 'stripe_dashboard', now(),
              'No in-platform request existed for this refund.',
              case when v_amount is null
                   then 'AMOUNT UNKNOWN - the event carried none and Stripe could not be read. Excluded from all financial totals until resolved.'
                   else null end)
      returning * into r;

      if v_amount is null then
        perform public.fn_refund_quarantine(p_stripe_refund_id, 'refund',
          'amount unknown: absent from the event and not retrievable from Stripe',
          jsonb_build_object('status', v_status, 'payment_intent', p_payment_intent, 'refund_row', r.id),
          p_stripe_event_id);
      end if;

      return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status, 'applied', true,
                                'created', true, 'amount_known', v_amount is not null);
    end if;
  end if;

  -- Duplicate delivery: same state twice. Cheap, silent, correct - but still take the chance to fill
  -- in an amount we did not have before.
  if r.status = v_status then
    if r.amount_fils is null and v_amount is not null then
      update public.refunds
         set amount_fils = v_amount, amount_source = v_src,
             reconciliation_note = 'amount resolved from a later ' || coalesce(p_amount_source,'event'),
             updated_at = now()
       where id = r.id;
      return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status,
                                'idempotent', true, 'applied', false, 'amount_resolved', true);
    end if;
    return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status,
                              'idempotent', true, 'applied', false);
  end if;

  -- The matrix decides. Not a rank, not an ordering heuristic - a declared policy with a reason
  -- attached to every refusal.
  if not public.fn_refund_transition_allowed(r.status, v_status) then
    v_q := public.fn_refund_quarantine(p_stripe_refund_id, 'refund',
      'transition not permitted: ' || r.status || ' -> ' || v_status || '. '
      || coalesce((select note from public.refund_status_transition
                    where from_status = r.status and to_status = v_status), 'no rule declared for this pair'),
      jsonb_build_object('refund_row', r.id, 'from', r.status, 'to', v_status,
                         'amount_fils', p_amount_fils, 'payment_intent', p_payment_intent),
      p_stripe_event_id);
    update public.refunds
       set reconciliation_note = left(coalesce(reconciliation_note || ' | ', '')
           || 'refused ' || r.status || '->' || v_status || ' at ' || to_char(now(),'YYYY-MM-DD HH24:MI'), 500),
           updated_at = now()
     where id = r.id;
    return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status, 'applied', false,
                              'refused_transition', r.status || '->' || v_status, 'quarantined', v_q);
  end if;

  update public.refunds
     set status = v_status,
         amount_fils   = coalesce(v_amount, amount_fils),
         amount_source = case when v_amount is not null then v_src else amount_source end,
         stripe_charge_id = coalesce(p_charge_id, stripe_charge_id),
         stripe_payment_intent = coalesce(p_payment_intent, stripe_payment_intent),
         settled_at = case when v_status = 'succeeded' then coalesce(settled_at, now()) else settled_at end,
         failure_reason = case when v_status = 'failed' then p_failure_reason else failure_reason end,
         reconciliation_note = case
             when v_status = 'succeeded' and coalesce(v_amount, amount_fils) is null
             then 'AMOUNT UNKNOWN on a settled refund - excluded from all financial totals until resolved.'
             else reconciliation_note end,
         updated_at = now()
   where id = r.id;

  if r.transaction_id is not null then
    update public.transactions
       set refund_status = v_status, refund_stripe_id = p_stripe_refund_id,
           refund_amount_aed = case when v_amount is not null then round(v_amount/100.0, 2) else refund_amount_aed end,
           refund_confirmed_at = case when v_status = 'succeeded' then coalesce(refund_confirmed_at, now())
                                      else refund_confirmed_at end
     where id = r.transaction_id;
  end if;

  return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', v_status, 'applied', true,
                            'amount_known', coalesce(v_amount, r.amount_fils) is not null);
end $function$;

-- ── 5b. A TOP-UP COMPLETES ONLY A REFUND THE ONE DECISION APPROVED ──────────────────────────────────────────
-- Unchanged except the parent: it must be approved/processing/succeeded (so it passed fn_refund_decide). Before,
-- a CEO-decided refund still waiting on the second seat could be topped up, Stripe paid, and z04 then refused the
-- record (code review, 29 Sep 2026).
create or replace function public.fn_accountant_reserves_topup(p_transaction_id uuid, p_amount_fils bigint, p_fix_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare t public.transactions; c public.refunds; x public.refunds; v_cap bigint; v_live bigint; v_amt bigint; v_marker text;
begin
  v_marker := 'incident.fix #' || p_fix_id;
  select * into t from public.transactions where id = p_transaction_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such transaction'); end if;
  select * into x from public.refunds
   where transaction_id = t.id and topup_of is not null and reason_note like v_marker || ':%' order by id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'refund_id', x.id, 'amount_fils', x.amount_fils, 'status', x.status, 'existing', true);
  end if;
  select * into c from public.refunds
   where transaction_id = t.id and topup_of is null and refund_decision_id is not null
     and status in ('approved', 'processing', 'succeeded')
     and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe')
   order by id desc limit 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no approved refund on this payment to top up (a CEO decision still waiting on the second seat is not approved)'); end if;
  v_cap := round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint;
  select coalesce(sum(r.amount_fils), 0) into v_live
    from public.refunds r
   where r.status not in ('failed', 'rejected', 'cancelled')
     and (r.transaction_id = t.id or (coalesce(btrim(t.payment_ref), '') <> '' and r.stripe_payment_intent = t.payment_ref));
  v_amt := least(coalesce(p_amount_fils, 0), v_cap - v_live);
  if v_amt <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'nothing left to refund: ' || v_live || ' of the ' || v_cap || ' fils paid are already refunded or on their way',
                              'refunded_fils', v_live, 'paid_fils', v_cap);
  end if;
  insert into public.refunds
    (transaction_id, quote_id, inquiry_id, customer_id, supplier_lead_id, stripe_payment_intent, amount_fils, currency,
     reason_code, reason_note, status, requested_by, amount_source, topup_of, refund_decision_id, decided_by, decided_at)
  values
    (t.id, t.quote_id, t.inquiry_id, t.customer_id, t.supplier_id, t.payment_ref, v_amt, 'AED',
     c.reason_code, v_marker || ': the CEO''s mismatch playbook tops refund #' || c.id || ' up towards what the customer paid',
     'requested', 'accountant', 'in_platform_request', c.id, c.refund_decision_id, 'ceo', now())
  returning * into x;
  return jsonb_build_object('ok', true, 'refund_id', x.id, 'amount_fils', v_amt, 'capped', v_amt < coalesce(p_amount_fils, 0), 'case_refund_id', c.id);
end $function$;

-- ── 6. THE CEO'S REASONS, WHOEVER WRITES THE ROW (the bypass left by #1128) ─────────────────────────────────
-- #1128 checks reasons inside the routines (fn_ceo_decide, fn_ceo_decision_close, fn_seat_deliberation_record).
-- A direct service_role write skipped them. These BEFORE triggers apply the same fn_ceo_reasons_problem to the
-- row itself.
--   ceo_experiment: leaving 'proposed', or a new approval decision, carries approval.reasons (fn_ceo_decision_close)
--     or approval.reasoning (fn_reason_apply_ceo__experiment_approval). A final verdict (kept/killed) carries the
--     reasoning of its latest ceo_experiment_verdict row, written first by fn_reason_apply_ceo__experiment_verdict.
--   ceo_improvement: 'dropped' is the CEO's decision and carries its reasons in done_evidence (275 of 275 dropped
--     rows on production pass, measured 29 Sep 2026). 'done' is the seat's evidence, not a CEO decision.
--   seat_deliberation_turn: a recorded CEO comparison carries the reasons fn_seat_deliberation_record reads (the side
--     the verdict rests on, with output.reasoning when that is thin). It is append-only; this runs first, so an
--     update that strips the reasons is named for what it is.
create or replace function public.trg_ceo_experiment_carries_its_reasons()
 returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_problem text;
begin
  if (old.status = 'proposed' and new.status <> 'proposed')
     or (new.approval is distinct from old.approval and new.approval ? 'decision'
         and new.approval->'decision' is distinct from old.approval->'decision') then
    v_problem := public.fn_ceo_reasons_problem(coalesce(new.approval->>'reasons', new.approval->>'reasoning'));
  elsif new.status in ('kept', 'killed') and old.status is distinct from new.status then
    v_problem := public.fn_ceo_reasons_problem((select v.reasoning from public.ceo_experiment_verdict v
                                                 where v.experiment_id = new.id and v.decided_at is not null
                                                 order by v.decided_at desc limit 1));
  end if;
  if v_problem is not null then
    raise exception using errcode = 'check_violation',
      message = 'REASONLESS_DECISION: the CEO''s decision on experiment ' || new.id || ' (' || old.status || ' -> ' || new.status || ') says why: ' || v_problem;
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_ceo_experiment_carries_its_reasons() from public, anon, authenticated;
drop trigger if exists a04_ceo_experiment_carries_its_reasons on public.ceo_experiment;
create trigger a04_ceo_experiment_carries_its_reasons before update on public.ceo_experiment
  for each row execute function public.trg_ceo_experiment_carries_its_reasons();

create or replace function public.trg_ceo_improvement_carries_its_reasons()
 returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_problem text;
begin
  if new.status = 'dropped' and (tg_op = 'INSERT' or old.status is distinct from 'dropped') then
    v_problem := public.fn_ceo_reasons_problem(new.done_evidence);
    if v_problem is not null then
      raise exception using errcode = 'check_violation',
        message = 'REASONLESS_DECISION: the CEO drops improvement ' || coalesce(new.id::text, '(new)') || ' only with reasons: ' || v_problem;
    end if;
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_ceo_improvement_carries_its_reasons() from public, anon, authenticated;
drop trigger if exists a04_ceo_improvement_carries_its_reasons on public.ceo_improvement;
create trigger a04_ceo_improvement_carries_its_reasons before insert or update on public.ceo_improvement
  for each row execute function public.trg_ceo_improvement_carries_its_reasons();

create or replace function public.trg_ceo_turn_carries_its_reasons()
 returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.seat_deliberation; v_reasons text; v_problem text;
begin
  if new.phase <> 'compare' or new.status <> 'recorded' then return new; end if;
  select * into d from public.seat_deliberation where id = new.deliberation_id;
  if d.reviewer_seat is distinct from 'ceo' or d.kind = 'marketing.monthly_plan' then return new; end if;
  v_reasons := btrim(coalesce(case when lower(new.verdict) = 'approve' then new.agreements else new.disagreements end, ''));
  if public.fn_ceo_reasons_problem(v_reasons) is not null and coalesce(btrim(new.output->>'reasoning'), '') <> '' then
    v_reasons := btrim(v_reasons || E'\n' || (new.output->>'reasoning'));
  end if;
  v_problem := public.fn_ceo_reasons_problem(v_reasons);
  if v_problem is not null then
    raise exception using errcode = 'check_violation',
      message = 'REASONLESS_DECISION: the CEO''s ' || coalesce(new.verdict, '(no verdict)') || ' on deliberation ' || new.deliberation_id || ' says why: ' || v_problem;
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_ceo_turn_carries_its_reasons() from public, anon, authenticated;
drop trigger if exists a04_ceo_turn_carries_its_reasons on public.seat_deliberation_turn;
create trigger a04_ceo_turn_carries_its_reasons before insert or update on public.seat_deliberation_turn
  for each row execute function public.trg_ceo_turn_carries_its_reasons();
