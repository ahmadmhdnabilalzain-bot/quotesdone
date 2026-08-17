-- ============================================================================================
-- EVERY REFUND NEEDS THE FOUNDER. TEN DIRHAMS NEEDS THE FOUNDER.
--
-- FOUNDER INSTRUCTION, 17 Aug 2026: "for refunds, change it into always. even for 10 AED it needs
-- founder approval."
--
-- WHAT IT USED TO DO. fn_refund_request auto-approved a refund when it was inside the window the
-- customer was promised at reveal AND at or below a ceiling declared in
-- org_authority(customer_success, refund_within_window) — live at AED 2,000. On that path it wrote:
--
--     refunds.status        = 'approved'
--     refunds.decided_by    = 'policy:auto_window'          <- a decider that is not a person
--     transactions.refund_status = 'approved'
--
-- The third line is the one that mattered. The founder's refund queue lists transactions where
-- refund_status = 'requested' (refunds_api, action 'queue'). An auto-approved refund was therefore
-- never in it: not held, not shown, not declined — simply gone past him. It had never fired, because
-- the refunds table has never held a row, so nothing was reversed by this file. That is luck, not
-- design.
--
-- WHAT IT DOES NOW. Every refund is 'requested'. There is no amount, no window and no ceiling that
-- decides one. Whether the request fell inside the promised window is still RECORDED —
-- refunds.within_auto_window — because it is a fact about the customer's promise and the founder
-- should see it when he decides. It just no longer decides anything by itself.
--
-- THREE MECHANISMS, NOT ONE. This file is written the day the independent acceptance found four
-- routines whose "kernel-internal" status lived only in a prose column, so:
--   1. fn_refund_request never writes 'approved'.
--   2. fn_refund_decide refuses a decider who is not an ACTIVE row in phase_c_founder_identity.
--      It previously accepted any non-empty string, so 'policy:auto_window' — or any operator —
--      satisfied it.
--   3. A trigger on public.refunds refuses ANY write that leaves status = 'approved' without a
--      founder in decided_by. A rule enforced in one routine is one edit from gone.
--
-- org_authority IS DELIBERATELY NOT TOUCHED. The AED 2,000 rows stay. fn_refund_request no longer
-- reads them, but fn_autonomy_class, fn_ops_authority_check and fn_os_portals_gates do, for
-- classification and reporting that has nothing to do with approving a refund. Zeroing a row three
-- other routines read, to make a fourth stop reading it, is how a fix becomes an outage.
--
-- READ-BACK IS THE PROOF:
--   node scripts/checks/refund_single_path.test.mjs
--   node scripts/checks/stripe_refund_events.test.mjs
-- ============================================================================================

create or replace function public.fn_refund_request(
  p_amount_fils bigint, p_reason_code text, p_requested_by text,
  p_inquiry_id uuid default null, p_customer_id uuid default null,
  p_supplier_lead_id bigint default null, p_quote_id uuid default null,
  p_payment_intent text default null, p_charge_id text default null,
  p_note text default null, p_transaction_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $refundreq$
declare v_id bigint; v_in_window boolean := false; t public.transactions;
begin
  if p_amount_fils is null or p_amount_fils <= 0 then
    return jsonb_build_object('ok', false, 'error', 'amount_required');
  end if;

  select * into t from public.transactions
   where (p_transaction_id is not null and id = p_transaction_id)
      or (p_transaction_id is null and p_quote_id is not null and quote_id = p_quote_id)
      or (p_transaction_id is null and p_quote_id is null and p_payment_intent is not null and payment_ref = p_payment_intent)
   order by revealed_at desc nulls last limit 1;

  -- Recorded, never acted on. Whether the request arrived inside the window promised at reveal
  -- (transactions.refund_deadline, computed by fn_add_working_days when the quote was revealed) is
  -- exactly the kind of thing the founder wants in front of him when he decides — and exactly the
  -- kind of thing that must not decide for him.
  if t.id is not null and t.refund_deadline is not null and t.refund_deadline >= now() then
    v_in_window := true;
  end if;

  insert into public.refunds (transaction_id, inquiry_id, customer_id, supplier_lead_id, quote_id,
                              stripe_payment_intent, stripe_charge_id,
                              amount_fils, reason_code, reason_note, requested_by,
                              within_auto_window, status, reconciliation_note)
  values (t.id, coalesce(p_inquiry_id, t.inquiry_id), coalesce(p_customer_id, t.customer_id),
          coalesce(p_supplier_lead_id, t.supplier_id), coalesce(p_quote_id, t.quote_id),
          coalesce(p_payment_intent, t.payment_ref), p_charge_id,
          p_amount_fils, p_reason_code, p_note, p_requested_by,
          v_in_window, 'requested',
          'HELD FOR THE FOUNDER. Every refund waits for his decision, whatever the amount and '
       || 'whether or not it is inside the promised window — founder instruction, 17 Aug 2026. '
       || 'This one is ' || round(p_amount_fils / 100.0, 2) || ' AED and is '
       || case when v_in_window then 'inside' else 'outside' end || ' the window promised at reveal.')
  returning id into v_id;

  if t.id is not null then
    update public.transactions
       set refund_status = 'requested',
           refund_reason = coalesce(refund_reason, p_reason_code),
           refund_requested_at = coalesce(refund_requested_at, now()),
           refund_note = coalesce(p_note, refund_note)
     where id = t.id;
  end if;

  return jsonb_build_object('ok', true, 'refund_id', v_id, 'transaction_id', t.id,
                            'status', 'requested',
                            'within_auto_window', v_in_window,
                            'auto_approved', false,
                            'awaiting', 'founder');
end
$refundreq$;

-- ---------------------------------------------------------------- 2. only a founder may decide
create or replace function public.fn_refund_decide(
  p_refund_id bigint, p_approve boolean, p_decided_by text, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $refunddec$
declare r public.refunds; v_new text;
begin
  select * into r from public.refunds where id = p_refund_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'requested' then
    return jsonb_build_object('ok', false, 'error', 'not_decidable', 'status', r.status);
  end if;
  if coalesce(btrim(p_decided_by),'') = '' then
    return jsonb_build_object('ok', false, 'error', 'decider_required');
  end if;

  -- It used to be enough to be a non-empty string, which is how 'policy:auto_window' decided
  -- refunds. The decider must now be a person the founder identity register knows and has active.
  if not exists (select 1 from public.phase_c_founder_identity f
                  where f.active and lower(f.identity) = lower(btrim(p_decided_by))) then
    return jsonb_build_object('ok', false, 'error', 'founder_required',
      'hint', 'Every refund needs the founder, at any amount. public.phase_c_founder_identity is '
           || 'the register of who that is; ' || btrim(p_decided_by) || ' is not an active row in it.');
  end if;

  v_new := case when p_approve then 'approved' else 'rejected' end;
  update public.refunds set status = v_new, decided_by = p_decided_by, decided_at = now(), decision_note = p_note
   where id = p_refund_id;
  if r.transaction_id is not null then
    update public.transactions set refund_status = v_new, refund_resolved_at = now(),
           refund_note = coalesce(p_note, refund_note) where id = r.transaction_id;
  end if;
  return jsonb_build_object('ok', true, 'refund_id', p_refund_id, 'status', v_new, 'decided_by', p_decided_by);
end
$refunddec$;

-- ---------------------------------------------------------------- 3. the mechanism behind both
create or replace function public.fn_refund_founder_decision_only()
returns trigger language plpgsql security invoker set search_path to 'public', 'pg_temp' as $refundg$
begin
  if new.status <> 'approved' then return new; end if;
  if exists (select 1 from public.phase_c_founder_identity f
              where f.active and lower(f.identity) = lower(btrim(coalesce(new.decided_by, '')))) then
    return new;
  end if;
  raise exception
    'refund %: approved by %, who is not an active founder identity.',
    coalesce(new.id::text, '(new)'), coalesce(nullif(btrim(new.decided_by), ''), '(nobody)')
    using errcode = '42501',
          hint = 'Every refund needs the founder, at any amount — his instruction, 17 Aug 2026. '
              || 'A refund reaches ''approved'' only through fn_refund_decide, and only with a '
              || 'decided_by that is an active row in public.phase_c_founder_identity. '
              || 'Before this guard, fn_refund_request auto-approved anything inside the promised '
              || 'window and under org_authority(customer_success, refund_within_window) — AED '
              || '2,000 — writing decided_by = ''policy:auto_window'' and setting '
              || 'transactions.refund_status = ''approved'', so it never appeared in his queue.';
end
$refundg$;
revoke all on function public.fn_refund_founder_decision_only() from public;
grant execute on function public.fn_refund_founder_decision_only() to service_role;

drop trigger if exists z00_refund_founder_decision_only on public.refunds;
create trigger z00_refund_founder_decision_only
  before insert or update on public.refunds
  for each row execute function public.fn_refund_founder_decision_only();

comment on function public.fn_refund_request(bigint, text, text, uuid, uuid, bigint, uuid, text, text, text, uuid) is
  'Records a refund request. ALWAYS ''requested'' — there is no amount, window or ceiling that '
  'approves one. Whether it fell inside the window promised at reveal is recorded in '
  'within_auto_window as a fact for the founder to weigh, and decides nothing.';
comment on function public.fn_refund_decide(bigint, boolean, text, text) is
  'The only path to an approved or rejected refund. The decider must be an active row in '
  'public.phase_c_founder_identity; any other value is refused with founder_required.';
