-- THE CEO'S REFUND CHECKLIST READS THE CUSTOMER'S WORD, THE CEO'S OWN DISPUTE DECISION AND EVERY CHANNEL.
-- Seat: ceo (the checklist is the CEO's refund decision), written by the customer_support builder (agent "customer_support builder
-- (after-reveal review fixes)") on review AFTERREVEAL of 16 Nov 2026, items 2 and 3. Founder ledgers 1711-1713: colleagues know what
-- each other know.
--
-- APPLY ORDER (this file REPLACES the fn_ceo_refund_checklist of the second file below, and reads routines both create):
--   1. scripts/sql/a_paid_reveal_asks_the_customer_and_every_money_problem_reaches_a_case.sql   (branch customer_support-a-paid-reveal-
--      has-a-door-for-every-money-problem: fn_reveal_contact_word, fn_refund_rating_shows_dealing, fn_refund_dispute_basis)
--   2. scripts/sql/every_door_and_the_ceo_read_the_same_case.sql   (branch sales_engineer-every-door-reads-the-same-case: fn_contact_timeline's
--      it_fault branch, fn_person_open_promises, and its own fn_ceo_refund_checklist with item 1b)
--   3. THIS FILE.
--
-- BODY: production's (pg_get_functiondef, md5(prosrc) 027da5f6bf69ba10ab4a648c1028b307, read 16 Nov 2026; equal to the mirror) +
-- item 1b exactly as file 2 writes it (guarded: a failed read records nothing and never makes the checklist unavailable) + these:
--   (a) A REFUND THE CEO'S OWN DISPUTE DECISION FILED (fn_refund_dispute_basis is not null) stands on that decision: items 2-4 and the
--       exclusions in item 5 are the non-response rules and do not apply to it. Without this fn_ceo_refund_review DECLINED the CEO's
--       refund_reveal_fee / next_reveal_free refund (item 4 "the supplier responded" is not remediable) after the customer was told
--       "everything you paid is refunded" (review attack D).
--   (b) A CONTESTED WORD IS NOT SILENCE: while the supplier claims contact and the customer denies it (fn_reveal_contact_word.conflict),
--       item 4 passes only once the CEO has answered that disputed_reveal escalation 'refund_review'; unanswered it rests as
--       needs_reasoning (no cycle spent), 'uphold_reveal' declines it. So neither the refund nor the non-response charge that follows
--       it (fn_accountant_refund_settled -> fn_accountant_raise_nonresponse_charge) is levied on the customer's word alone (attack C, C2).
--   (c) Item 4 shows the customer's own word beside the supplier's claim (evidence customer_contact); item 5's rating exclusion is
--       fn_refund_rating_shows_dealing (a rating is a record of dealing only when contact happened).
--   (d) Item 6 and the case read: an overcharge the accountant already returned on the payment is not the case (the case is the
--       latest refund that is not an overcharge_return), and the amount expected is total_charged less that return, as production's
--       fn_refund_open_from_customer files it since 15 Nov.
-- Nothing else changes: every other pass/fail condition is production's.
-- Probe: the_ceo_refund_checklist_reads_the_customers_word_the_dispute_and_every_channel_probe.sql (after files 1, 2 and this, in one
--   rolled-back transaction, local Postgres 16 only; PROBE OK twice, 16 Nov 2026).
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_refund_checklist_reads_the_customers_word_the_dispute_and_every_channel.sql --apply --ddl --seat ceo
set local lock_timeout = '3s';
create or replace function public.fn_ceo_refund_checklist(p_transaction_id uuid, p_phase text, p_record boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions; r public.refunds; rs public.refunds; ap public.ceo_approval; du public.supplier_dues;
  e_chase public.refund_ladder_evidence; e_final public.refund_ladder_evidence;
  v_items jsonb := '[]'::jsonb; v_failed jsonb; v_ok boolean; v_cust text; v_total numeric; v_reason text; v_unresp boolean;
  v_complaint timestamptz; v_in_time boolean; v_cc boolean; v_attached boolean; v_proofs int; v_live boolean; v_proof_ev jsonb;
  v_prior boolean; v_hired boolean; v_rated boolean; v_offp boolean; v_excl text[] := '{}'; v_exp bigint;
  v_succ int; v_succ_fils bigint; v_extra int; v_actual numeric; v_approved numeric; v_loss numeric; v_charge jsonb; v_sent boolean;
  v_told boolean; v_sup_told boolean; v_kind text; v_rid bigint;
  v_offp_text text; v_offp_key text; v_offp_choice text; v_offp_held bigint;   -- item 5, reasoned (23 Sep 2026)
  v_tl jsonb; v_seen jsonb; v_prom jsonb;                                        -- item 1b (16 Nov 2026)
  v_basis jsonb; v_word jsonb; v_conflict boolean := false; v_conf_choice text;   -- AFTER_REVEAL review (a), (b)
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then
    return jsonb_build_object('ok', false, 'phase', p_phase, 'transaction_id', p_transaction_id,
      'failed', jsonb_build_array(jsonb_build_object('item', 'transaction_exists', 'passed', false, 'reason', 'no such transaction', 'remediable', false)));
  end if;
  select * into r from public.refunds where transaction_id = t.id and status not in ('rejected', 'cancelled', 'failed')
     and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe')
     and reason_code is distinct from 'overcharge_return'   -- the accountant's overcharge return is not the case decided here
   order by id desc limit 1;
  select lower(email) into v_cust from public.customers where id = t.customer_id;
  v_total := coalesce(t.total_charged, t.reveal_fee);
  v_reason := coalesce(r.reason_code, t.refund_reason, 'supplier_unresponsive');
  v_unresp := v_reason = 'supplier_unresponsive';
  select * into e_chase from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'chase' order by e.id desc limit 1;
  select * into e_final from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'final_call' order by e.id desc limit 1;

  if p_phase = 'approve' then
    v_rid := r.id;
    v_basis := public.fn_refund_dispute_basis(t.id);
    v_word := public.fn_reveal_contact_word(t.id);
    v_conflict := coalesce((v_word->>'conflict')::boolean, false);
    if v_conflict then
      select a.evidence->>'choice' into v_conf_choice from public.agent_actions a
       where a.kind = 'handoff' and a.status = 'done' and a.detail->>'type' = 'sales.escalation' and a.detail->>'escalation' = 'disputed_reveal'
         and a.detail->>'transaction_id' = t.id::text and a.target_id like '%:contact_conflict:%'
       order by a.id desc limit 1;
    end if;
    -- 1. THE CUSTOMER'S COMPLAINT, ON RECORD OR NOT -- NEVER A CONDITION (14 Sep 2026). This item was
    -- complaint_within_7_days_with_proof and refused every refund where the customer did not complain
    -- within 7 days with proof. Terms v7 §5 and Refund Policy v1.5 §3/§5 say the opposite: "you do not
    -- need to do anything for the clock to start", a complaint may come "at any time", and proof "is
    -- never a condition of the refund". So it now records the evidence and always passes; the conditions
    -- the terms DO set are items 2 to 6.
    v_complaint := least(t.customer_notified_at,
                         (select min(x.requested_at) from public.refunds x where x.transaction_id = t.id and lower(coalesce(x.requested_by, '')) = 'customer'));
    v_cc := exists (select 1 from public.inbound_messages im
                     where v_cust is not null and lower(im.from_email) = v_cust and im.created_at > t.revealed_at
                       and (im.to_email ilike 'supplier@%' or im.raw::text ilike '%supplier@mail.quotesdone.com%'));
    v_attached := exists (select 1 from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'customer_proof');
    v_items := v_items || jsonb_build_object('item', 'customer_complaint_on_record',
      'passed', true,
      'evidence', jsonb_build_object('revealed_at', t.revealed_at, 'complaint_at', v_complaint,
        'customer_emailed_supplier_with_supplier_at_in_copy', v_cc, 'formal_notice_through_portal_at', t.customer_notified_at,
        'proof_attached_by_sales_engineer', v_attached,
        'basis', 'Terms v7 section 5, Refund Policy v1.5 sections 3 and 5: no complaint or proof is required; the ladder runs from payment'),
      'reason', null, 'remedy', 'none needed', 'owner', 'sales_engineer', 'remedy_key', 'customer_proof', 'remediable', true, 'kind', 'information');

    -- 1b. WHAT EVERY SEAT TOLD AND PROMISED HIM, BEFORE THE CEO DECIDES (16 Nov 2026, founder ledgers 1711-1713: colleagues know
    -- what each other know; every_door_and_the_ceo_read_the_same_case.sql). Item 1 reads his e-mail and the notifications only, so
    -- "support told him the CEO decides by Thursday" or his WhatsApp complaint never reached this decision. His timeline since the
    -- reveal (fn_contact_timeline: WhatsApp, portal chat, e-mail, support cases, faults, the seats' hand-overs, every 140-character
    -- summary already masked there) and the promises still open on his cases (fn_person_open_promises) are recorded here as
    -- evidence. Information, like item 1: it never refuses a refund the terms allow, and never approves one they do not.
    -- Guarded (review of 16 Nov): a failed read records nothing here and never makes the checklist unavailable.
    begin
      v_tl := public.fn_contact_timeline(v_cust, 60);
      select coalesce(jsonb_agg(x order by (x ->> 'at')::timestamptz desc), '[]'::jsonb) into v_seen
        from (select x from jsonb_array_elements(coalesce(v_tl -> 'events', '[]'::jsonb)) x
               where t.revealed_at is null or (x ->> 'at')::timestamptz >= t.revealed_at - interval '1 day'
               order by (x ->> 'at')::timestamptz desc limit 30) z;
      v_prom := public.fn_person_open_promises('customer', t.customer_id::text, v_cust, null, 10);
    exception when others then
      v_seen := '[]'::jsonb; v_prom := '[]'::jsonb;
    end;
    v_items := v_items || jsonb_build_object('item', 'what_he_was_told_and_promised_on_every_channel',
      'passed', true,
      'evidence', jsonb_build_object('timeline_since_reveal', v_seen, 'open_promises', v_prom,
        'whatsapp_messages_since_reveal', (select count(*) from jsonb_array_elements(v_seen) x where x ->> 'channel' = 'whatsapp'),
        'support_cases', (select count(*) from jsonb_array_elements(v_seen) x where x ->> 'kind' = 'support_case'),
        'basis', 'the CEO decides knowing what support and the other seats told and promised him (ledgers 1711-1713)'),
      'reason', null, 'remedy', 'none needed', 'owner', 'customer_support', 'remedy_key', 'none', 'remediable', true, 'kind', 'information');

    -- 2 and 3. The day-3 chase and the day-5 final call, as support reported them.
    v_items := v_items || jsonb_build_object('item', 'day3_chase_happened',
      'passed', v_basis is not null or (e_chase.id is not null and e_chase.delivered),
      'evidence', case when e_chase.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_chase.id, 'result', e_chase.result, 'delivered', e_chase.delivered, 'delivery', e_chase.evidence) end,
      'reason', case when e_chase.id is null then 'support has returned no result for a day-3 chase' else 'the day-3 chase was not delivered' end,
      'remedy', 'the sales engineer has support deliver the chase again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'chase', 'remediable', true, 'kind', 'process');
    v_items := v_items || jsonb_build_object('item', 'day5_final_call_happened',
      'passed', v_basis is not null or (e_final.id is not null and e_final.delivered),
      'evidence', case when e_final.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_final.id, 'result', e_final.result, 'delivered', e_final.delivered, 'delivery', e_final.evidence) end,
      'reason', case when e_final.id is null then 'support has returned no result for the day-5 final call' else 'the day-5 final call was not delivered' end,
      'remedy', 'the sales engineer has support deliver the final call again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'final_call', 'remediable', true, 'kind', 'process');

    -- 4. The supplier did not respond to either party, on any channel.
    select count(*), (array_agg(e.evidence order by e.id desc))[1] into v_proofs, v_proof_ev
      from public.refund_ladder_evidence e where e.transaction_id = t.id and e.result = 'proof_of_response';
    v_live := coalesce((public.fn_refund_state(t.id)->>'supplier_responded')::boolean, false)
              or exists (select 1 from public.supplier_response_watch w where w.transaction_id = t.id and w.first_response_at is not null);
    v_items := v_items || jsonb_build_object('item', 'supplier_never_responded',
      'passed', v_basis is not null
                or (v_proofs = 0 and not v_live
                    and coalesce(e_chase.result, '') = 'no_response_confirmation' and coalesce(e_chase.delivered, false)
                    and coalesce(e_final.result, '') = 'no_response_confirmation' and coalesce(e_final.delivered, false)
                    and (not v_conflict or v_conf_choice is not distinct from 'refund_review')),
      'evidence', jsonb_build_object('proofs_of_response', v_proofs, 'latest_proof', v_proof_ev, 'responded_by_live_record', v_live,
                                     'chase_result', e_chase.result, 'final_call_result', e_final.result,
                                     -- 16 Nov 2026 (AFTER_REVEAL): the customer's own word beside the supplier's claim, both statements
                                     'customer_contact', v_word, 'contact_conflict_ceo_choice', v_conf_choice, 'dispute_basis', v_basis),
      'reason', case when v_proofs > 0 or v_live then 'the supplier responded' || coalesce(': ' || (v_proof_ev->'reply')::text, '')
                     when v_conflict and v_conf_choice is distinct from 'refund_review'
                       then 'the supplier says it contacted the customer and the customer says it did not: the CEO answers the disputed reveal first ('
                            || coalesce(v_conf_choice, 'not answered yet') || ')'
                     else 'silence is not confirmed on both steps: a result is missing, or the delivery behind it failed' end,
      'remedy', case when v_conflict and v_conf_choice is null then 'none by hand: the CEO''s answer to the disputed reveal arrives through the reasoning queue'
                     else 'the sales engineer has support make the final call again and return proof or a confirmed no-response' end,
      'owner', case when v_conflict and v_conf_choice is null then 'ceo' else 'sales_engineer' end,
      'remedy_key', case when v_conflict and v_conf_choice is null then 'reasoning' else 'final_call' end,
      'remediable', v_proofs = 0 and not v_live and v_conf_choice is distinct from 'uphold_reveal',
      'kind', case when v_conflict and v_conf_choice is null and v_proofs = 0 and not v_live then 'needs_reasoning' else 'process' end);

    -- 5. None of the exclusions in the signed terms applies.
    v_prior := exists (select 1 from public.transactions x where x.customer_id = t.customer_id and x.supplier_id = t.supplier_id
                         and x.id <> t.id and x.revealed_at < t.revealed_at);
    v_hired := exists (select 1 from public.inquiries i where i.id = t.inquiry_id and i.status in ('completed', 'closed') and i.hired_supplier_id = t.supplier_id);
    -- 16 Nov 2026 (AFTER_REVEAL): a rating is a record of dealing only when contact happened (fn_refund_rating_shows_dealing):
    -- our own day-3 survey wrote a review from "No, never called, 1 star", and this then declined the refund the Terms promise.
    v_rated := public.fn_refund_rating_shows_dealing(t.id);
    -- OFF-PLATFORM ENGAGEMENT IS REASONED FROM WHAT WAS WRITTEN, NEVER SPOTTED (23 Sep 2026,
    -- founder_instruction 886-903). A pattern on the note decided this exclusion, and an exclusion DECLINES
    -- the refund: "they did not use the platform" matched nothing, "not off-platform" matched. The notes are
    -- now read by the CEO seat's reasoning (ceo.refund_off_platform) and the answer is read back by its key.
    -- The platform's own default note is our text, not the customer's, so it asks nothing. Until the
    -- reasoning answers, v_offp stays null: no exclusion is assumed, and item 7 below keeps the refund
    -- waiting (fn_ceo_refund_review neither approves nor declines it, and pages nobody).
    v_offp_text := nullif(concat_ws(E'\n',
        case when btrim(coalesce(r.reason_note, '')) not in ('', 'The customer reported that the revealed supplier has not responded.')
             then 'Refund note: ' || btrim(r.reason_note) end,
        (select string_agg('Support note on the supplier''s response: ' || btrim(w.close_reason), E'\n' order by w.id)
           from public.supplier_response_watch w where w.transaction_id = t.id and btrim(coalesce(w.close_reason, '')) <> '')), '');
    if v_offp_text is null or v_basis is not null then   -- (a): the CEO's dispute decision already read the case
      v_offp := false;
    else
      v_offp_key := 'refund_offp:' || t.id || ':' || md5(v_offp_text);
      v_offp_choice := public.fn_reason_route_answer(v_offp_key);
      if v_offp_choice is null then
        v_offp := null;
        v_offp_held := public.fn_reason_route_ask('ceo', 'ceo.refund_off_platform', v_offp_text,
          jsonb_build_array(
            jsonb_build_object('id', 'engaged_off_platform', 'meaning', 'the note records that the customer dealt with or hired the supplier outside QuotesDone'),
            jsonb_build_object('id', 'not_off_platform', 'meaning', 'the note does not record any dealing with the supplier outside QuotesDone')),
          jsonb_build_object('transaction_id', t.id, 'refund_id', r.id), v_offp_key);
      else
        v_offp := v_offp_choice = 'engaged_off_platform';
      end if;
    end if;
    -- 16 Nov 2026 (AFTER_REVEAL): a refund the CEO's own dispute decision filed (fn_refund_dispute_basis) is not price dissatisfaction.
    if not v_unresp and v_basis is null then v_excl := v_excl || ('the reason is ' || v_reason || ', not supplier non-response (price dissatisfaction and a change of mind are not refundable)'); end if;
    if v_basis is null then   -- (a): the non-response exclusions do not apply to the CEO's own dispute refund
    if v_prior then v_excl := v_excl || 'the customer revealed this same supplier before'::text; end if;
    if v_hired then v_excl := v_excl || 'the customer completed the job with this supplier'::text; end if;
    if v_rated then v_excl := v_excl || 'the customer already rated this supplier'::text; end if;
    if coalesce(v_offp, false) then v_excl := v_excl || 'the customer engaged the supplier off the platform (reasoned by the CEO seat)'::text; end if;
    end if;
    v_items := v_items || jsonb_build_object('item', 'no_refund_exclusion_applies',
      'passed', cardinality(v_excl) = 0,
      'evidence', jsonb_build_object('reason_code', v_reason, 'same_supplier_revealed_before', v_prior, 'job_completed_with_supplier', v_hired,
                                     'supplier_rated', v_rated, 'off_platform_engagement_recorded', v_offp,
                                     'supplier_responded', 'checked by supplier_never_responded', 'dispute_basis', v_basis),
      'reason', array_to_string(v_excl, '; '), 'remedy', 'none: an exclusion in the signed terms means the refund is declined',
      'owner', 'sales_engineer', 'remedy_key', 'decline', 'remediable', false, 'kind', 'process');
    -- 7. The notes on record have been READ (reasoned), so item 5 is a finding and not an assumption.
    if v_offp is null then
      v_items := v_items || jsonb_build_object('item', 'off_platform_engagement_reasoned',
        'passed', false,
        'evidence', jsonb_build_object('held_question_id', v_offp_held, 'dedupe_key', v_offp_key),
        'reason', 'the CEO seat is still reasoning whether the notes on record say the customer dealt with the supplier off the platform',
        'remedy', 'none by hand: the answer arrives through the reasoning queue and the review re-runs itself',
        'owner', 'ceo', 'remedy_key', 'reasoning', 'remediable', true, 'kind', 'needs_reasoning');
    end if;

    -- 6. The amount is exactly what the customer paid, less an overcharge the accountant already returned on this payment
    -- (16 Nov 2026, review AFTERREVEAL: production's fn_refund_open_from_customer files total_charged less that return since 15 Nov,
    -- "exactly what a00 expects", and so does the CEO's dispute refund; an item that still asked for total_charged failed both and
    -- named a remedy that would refund the overcharge twice).
    v_exp := round(coalesce(v_total, 0) * 100)::bigint
             - (select coalesce(sum(o.amount_fils), 0) from public.refunds o
                 where o.reason_code = 'overcharge_return' and o.status not in ('failed', 'rejected', 'cancelled')
                   and (o.transaction_id = t.id or (coalesce(btrim(t.payment_ref), '') <> '' and o.stripe_payment_intent = t.payment_ref)));
    v_items := v_items || jsonb_build_object('item', 'amount_equals_total_charged',
      'passed', r.id is not null and r.amount_fils = v_exp and v_exp > 0,
      'evidence', jsonb_build_object('refund_id', r.id, 'refund_fils', r.amount_fils, 'total_charged_fils', v_exp,
                                     'total_charged_recorded', t.total_charged is not null, 'stripe_reference', t.payment_ref),
      'reason', case when r.id is null then 'there is no open refund request on this payment' else 'the refund amount is not what the customer paid' end,
      'remedy', 'the accountant sets the refund to the payment''s total_charged, less any overcharge already returned on it',
      'owner', 'accountant', 'remedy_key', 'amount', 'remediable', r.id is not null, 'kind', 'money');

  elsif p_phase = 'verify' then
    -- an accountant's overcharge return is settled money on this payment but not this case (as item 6): the case is
    -- total_charged less that return, and the return is neither the refund that moved nor a duplicate of it
    v_total := v_total - (select coalesce(sum(o.amount_fils), 0) from public.refunds o
                           where o.reason_code = 'overcharge_return' and o.status not in ('failed', 'rejected', 'cancelled')
                             and (o.transaction_id = t.id or (coalesce(btrim(t.payment_ref), '') <> '' and o.stripe_payment_intent = t.payment_ref))) / 100.0;
    select count(*), coalesce(sum(x.amount_fils), 0) into v_succ, v_succ_fils
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
       and x.reason_code is distinct from 'overcharge_return';
    -- A top-up the playbook issued is not a duplicate: its Stripe id is on the incident fix.
    select count(*) into v_extra
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
       and x.reason_code is distinct from 'overcharge_return'
       and not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'incident.fix'
                        and a.evidence->>'stripe_refund_id' = x.stripe_refund_id);
    -- The platform refund the CEO approved, whatever state it reached. An external row Stripe reported
    -- (a top-up, a dashboard refund) is never it.
    select * into rs from public.refunds x where x.transaction_id = t.id
       and lower(coalesce(x.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by x.id desc limit 1;
    v_rid := rs.id;
    select * into ap from public.ceo_approval a where a.decision_id = rs.refund_decision_id;
    v_actual := case when v_succ > 0 then round(v_succ_fils / 100.0, 2)
                     when t.refund_status in ('refunded', 'succeeded') then t.refund_amount_aed end;
    v_approved := coalesce(ap.amount_aed, v_total);
    v_loss := coalesce((select sum(l.debit) from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
                         where g.source = 'refund_over_loss' and g.source_ref like t.id::text || ':%' and l.account_code = '6900'), 0);

    v_items := v_items || jsonb_build_object('item', 'ceo_approved_this_refund',
      'passed', ap.decision_id is not null and ap.decision = 'approved' and ap.subject_id = v_rid::text and ap.superseded_by is null,
      'evidence', jsonb_build_object('decision_id', ap.decision_id, 'decision', ap.decision, 'subject_id', ap.subject_id, 'refund_id', v_rid),
      'reason', 'money moved without a CEO approval naming this refund', 'kind', 'moved_without_ceo_approval', 'remediable', false);

    v_items := v_items || jsonb_build_object('item', 'stripe_refund_succeeded',
      'passed', (v_succ > 0 and exists (select 1 from public.refunds x
                                         where (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
                                           and x.status = 'succeeded' and x.stripe_refund_id is not null))
                or (v_succ = 0 and t.refund_stripe_id is not null and t.refund_status in ('refunded', 'succeeded')),
      'evidence', jsonb_build_object('refund_status', rs.status, 'stripe_refund_id', coalesce(rs.stripe_refund_id, t.refund_stripe_id), 'failure_reason', rs.failure_reason),
      'reason', 'Stripe has not settled the refund (' || coalesce(rs.status, t.refund_status, 'unknown') || ')', 'kind', 'stripe_failed_or_pending', 'remediable', true);

    v_kind := case when coalesce(v_actual, 0) = 0 then 'stripe_failed_or_pending'
                   when v_approved is distinct from v_total then 'approved_amount_is_not_total_charged'
                   when v_actual < v_approved then 'under_refund'
                   when v_actual > v_approved then 'over_refund' end;
    v_items := v_items || jsonb_build_object('item', 'money_moved_as_approved',
      'passed', v_actual is not null and v_approved = v_total
                and (v_actual = v_approved or (v_actual > v_approved and v_loss >= v_actual - v_approved)),
      'evidence', jsonb_build_object('approved_aed', v_approved, 'actual_aed', v_actual, 'total_charged_aed', v_total,
                                     'difference_aed', v_actual - v_approved, 'over_refund_loss_booked_aed', v_loss, 'settled_refunds', v_succ),
      'reason', 'approved AED ' || coalesce(v_approved::text, '?') || ', refunded AED ' || coalesce(v_actual::text, 'nothing') || ', total charged AED ' || coalesce(v_total::text, '?'),
      'kind', v_kind, 'remediable', true);

    v_items := v_items || jsonb_build_object('item', 'no_duplicate_refund',
      'passed', v_extra <= 1 or v_loss >= coalesce(v_actual - v_approved, 0),
      'evidence', jsonb_build_object('settled_refunds_not_issued_by_a_fix', v_extra),
      'reason', v_extra || ' refunds settled on one payment', 'kind', 'duplicate_refund', 'remediable', true);

    -- What follows the money (the supplier's charge, the two messages) is checked only once money
    -- actually moved; a refund Stripe has not settled is the retry's business, not a missed message.
    if coalesce(v_actual, 0) > 0 and v_unresp then
      select * into du from public.supplier_dues where transaction_id = t.id and coalesce(status, '') <> 'cancelled' order by id limit 1;
      v_charge := public.fn_accountant_nonresponse_charge(t.id, null);
      v_sent := du.id is not null and exists (
        select 1 from public.agent_actions a join public.notifications n on n.id = (a.evidence->>'notification_id')::bigint
         where a.kind = 'handoff' and a.agent = 'customer_support' and a.target_id = 'delivery.request:nonresponse_charge:' || du.id
           and (n.status = 'sent' or n.sent_at is not null));
      v_items := v_items || jsonb_build_object('item', 'supplier_charge_raised_correctly',
        'passed', du.id is not null and coalesce((v_charge->>'ok')::boolean, false)
                  and du.amount_due = (v_charge->>'charge_aed')::numeric and du.admin_fee = (v_charge->>'admin_fee_aed')::numeric
                  and du.due_date = (v_charge->>'due_date')::date,
        'evidence', jsonb_build_object('due_id', du.id, 'charged', jsonb_build_object('amount_due', du.amount_due, 'admin_fee', du.admin_fee, 'due_date', du.due_date),
                                       'expected', v_charge, 'charge_message_sent', v_sent),
        'reason', case when du.id is null then 'no supplier charge was raised' else 'the supplier charge does not match the refund record' end,
        'kind', case when du.id is null then 'charge_missing' when v_sent then 'wrong_charge_sent' else 'wrong_charge_unsent' end, 'remediable', true);
    end if;

    if coalesce(v_actual, 0) > 0 then
    v_told := exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                        and a.target_id = 'refund.paid:' || t.id and a.status = 'done')
              and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                            and a.target_id = 'delivery.request:refund_issued:' || t.id and a.status = 'done'
                            and coalesce((a.evidence->>'delivered')::boolean, false));
    v_items := v_items || jsonb_build_object('item', 'customer_told',
      'passed', v_told, 'evidence', jsonb_build_object('handoff', 'refund.paid:' || t.id, 'delivery', 'delivery.request:refund_issued:' || t.id),
      'reason', 'the customer''s refund message was not handed off and delivered', 'kind', 'missed_handoff', 'remediable', true);
    if v_unresp and du.id is not null then
      v_sup_told := exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                              and a.target_id in ('nonresponse.charge_raised:' || du.id, 'charge.corrected:' || du.id) and a.status = 'done')
                    and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                                  and a.target_id in ('delivery.request:nonresponse_charge:' || du.id, 'delivery.request:charge_corrected:' || du.id)
                                  and a.status = 'done' and coalesce((a.evidence->>'delivered')::boolean, false));
      v_items := v_items || jsonb_build_object('item', 'supplier_told',
        'passed', v_sup_told, 'evidence', jsonb_build_object('handoff', 'nonresponse.charge_raised:' || du.id),
        'reason', 'the supplier''s charge message was not handed off and delivered', 'kind', 'missed_handoff', 'remediable', true);
    end if;
    end if;
  else
    raise exception 'phase is approve or verify, not %', p_phase;
  end if;

  select coalesce(jsonb_agg(i), '[]'::jsonb) into v_failed from jsonb_array_elements(v_items) i where not coalesce((i->>'passed')::boolean, false);
  v_ok := jsonb_array_length(v_failed) = 0;
  if p_record then
    insert into public.refund_ceo_check (transaction_id, refund_id, phase, item, passed, reason, evidence)
    select t.id, v_rid, p_phase, i->>'item', coalesce((i->>'passed')::boolean, false),
           case when coalesce((i->>'passed')::boolean, false) then null else i->>'reason' end, coalesce(i->'evidence', '{}'::jsonb)
      from jsonb_array_elements(v_items) i;
  end if;
  return jsonb_build_object('ok', v_ok, 'phase', p_phase, 'transaction_id', t.id, 'refund_id', v_rid, 'items', v_items, 'failed', v_failed);
end $function$;
revoke execute on function public.fn_ceo_refund_checklist(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.fn_ceo_refund_checklist(uuid, text, boolean) to service_role;
