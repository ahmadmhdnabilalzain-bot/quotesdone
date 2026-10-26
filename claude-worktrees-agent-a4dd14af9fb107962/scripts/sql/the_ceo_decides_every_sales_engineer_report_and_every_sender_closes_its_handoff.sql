-- THE CEO DECIDES EVERY SALES ENGINEER REPORT, AND EVERY SENDER CLOSES ITS HANDOFF.
--
-- Assigned: ceo (the reading and the decisions); the re-verification steps are each originating seat's
-- (sales_engineer, accountant), run by the IT engineer's tick like every other loop step.
--
-- The founder: "nothing is one-way" -- every handoff or report is tracked, replied to, re-verified and
-- closed by the one who sent it (14 Sep 2026: "always make sure things are in loop. nothing literally
-- should ever be a one way communication"). And all approvals, refunds included, are the CEO's.
--
-- WHAT WAS MEASURED (production, 15 Sep 2026 07:57 UTC).
--   1. 680 support_ceo_report rows from the sales engineer, all status 'sent', all 'elevated', all
--      'delivery_undelivered:<request>' filed by fn_originator_checks_delivery from 14 Sep 14:45 on, and
--      still being filed (748 when the review read them). Nothing read them: fn_ceo_it_reports_sweep
--      reads it_engineer only, fn_ceo_accountant_reports_sweep reads the accountant only, and the
--      ceo_agent runtime has been idle since 9 Sep. What the 680 were:
--        409  the request they name no longer exists (ids 13565-23934, filed 14 Sep 15:00-21:45):
--             new_inquiry 120, quote_coaching 74, new_quote 73, quote_spec_released/regenerated/hold
--             46 each, spec_offer_offer 4. The row, its words and its address are gone.
--        263  ZZ DEMO fixtures addressed to @example.invalid (supplier 226, customer 37).
--          8  rfq_no_supplier addressed to recipient_role 'admin' (management@quotesdone.com): an
--             identity no seat is, and not a kind the founder may be emailed.
--          0  addressed to a real customer or supplier. (customers holds 1 real row today.)
--   2. 33 of the 40 seat_handoff_kind rows had no reply window and closed the moment the receiving
--      seat answered (fn_seat_handoff_act): nobody who SENT one ever checked what became of it.
--   3. founder_mail_policy still let refund_approval, refund_decision and spend_approval_needed email
--      the founder. Four more rows named an owner_role that is not a seat.
--   4. function_owner had 18 rows owned by 'website', agent_action_kind_policy named cto,
--      general_counsel, chief_operating_officer, customer_success_director, cfo and
--      chief_revenue_officer (10 rows) and no role at all (15), and org_agents said the IT engineer
--      "reports to the founder only; there is no line to the CEO" while org_reporting_edge has
--      it_engineer -> ceo and the IT loop files to the CEO every tick.
--
-- WHAT THIS CHANGES.
--   A. The CEO reads each report and DECIDES it, with a receipt naming what it read and what it
--      decided (fn_ceo_sales_engineer_report_decide, fn_ceo_accountant_notice_report_decide). A report
--      whose request is gone, a ZZ DEMO fixture, a notice to an identity no seat is: recorded that it
--      need not go, and why. A real customer or supplier: a 'delivery.remediate' handoff to the sales
--      engineer, who tries another channel on file; the CEO re-verifies the resend and closes it. A
--      handler that never answered, or a send with no outcome: a defect, raised as an IT finding that
--      goes round the IT loop. fn_ceo_sales_engineer_reports_sweep decides at most 100 a tick, one row
--      at a time, so one bad row cannot hold the rest back.
--   B. The handoff kinds, per kind, as data (the decision table is section 1).
--   C. fn_originators_reverify_handoffs: the sales engineer checks the accountant answered its
--      question, and the accountant checks each money notice it asked for actually arrived. Every row
--      ends: answered or reached; or reported to the CEO and closed with the CEO's decision.
--   D. The sender closes its report once the CEO's receipt, and any remediation, is on it
--      (fn_sales_engineer_reports_complete; fn_accountant_reports_complete already does it for the
--      accountant). fn_ceo_accountant_reports_sweep no longer acknowledges the accountant's notice
--      escalations with a generic receipt: those are decided in A.
--   E. fn_it_loop_tick gains three steps: originators, ceo_sales, ceo_accountant. The last runs the
--      accountant's report sweep, whose only caller (the accountant runtime) has left 3 reports unread
--      since 9 Sep.
--   F. The founder mail policy, the stale owners and the IT engineer's role text (sections 8-11).
--
-- WHAT THIS DOES NOT DO. It closes none of the 92 IT reports the CEO accepted: they wait on code
-- fixes, and the IT loop closes each when its finding clears. It does not touch fn_originator_checks_
-- delivery, the delivery watch, resilience_ping or the backup build. It gives no reader to reports
-- filed under customer_support (delivery_overdue) or to a CEO-sent delivery that fails (the ceo seat
-- has no reporting edge, so that escalation is refused): 0 such rows exist today. It does not drop
-- 'website' from function_owner_owner_ck: the founder said of those functions "if they belong to the
-- website then leave them" (8 Sep 2026) -- nothing is deleted, each now names the seat that answers
-- for it. If the_it_engineer_closes_every_loop_it_opens.sql is ever re-applied, its INSERT ... ON
-- CONFLICT resets section 1; scripts/checks/every_report_and_handoff_comes_back.test.mjs fails then.
--
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_decides_every_sales_engineer_report_and_every_sender_closes_its_handoff.sql --apply --ddl

-- ── 0. WHAT BECAME OF ONE SEND ──────────────────────────────────────────────────────────────────
-- Read from the request row the sender's own check writes (fn_originator_checks_delivery: detail.loop).
-- A failed send has a delivery_undelivered report, keyed on the retry when there was one.
create or replace function public.fn_delivery_request_outcome(p_request_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare q public.agent_actions; v_loop text;
begin
  select * into q from public.agent_actions where id = p_request_id and kind = 'handoff';
  if not found then return jsonb_build_object('state', 'missing', 'request_id', p_request_id); end if;
  v_loop := q.detail->>'loop';
  return jsonb_build_object('request_id', q.id, 'loop', v_loop,
    'state', case
      when v_loop in ('confirmed', 'retry_confirmed', 'handled_by_the_ladder', 'retry_handled_by_the_ladder') then 'reached'
      -- escalation_refused filed no report, so it reads as waiting and the 24-hour escalation takes over.
      when v_loop in ('escalated', 'retry_escalated') then 'failed'
      when v_loop in ('routed', 'stubbed', 'digested', 'cancelled', 'retry_routed', 'retry_stubbed', 'retry_digested', 'retry_cancelled') then 'ended'
      else 'waiting' end,
    'report_key', 'delivery_undelivered:' || coalesce(q.detail->>'retry_request_id', q.id::text),
    'fixture', q.detail::text ilike '%ZZ DEMO%'
               or coalesce(q.detail->'prepared'->>'to_email', q.detail->>'to_email', '') ilike '%@example.invalid');
end $fn$;
revoke execute on function public.fn_delivery_request_outcome(bigint) from public, anon, authenticated;

-- ── 1. THE SALES ENGINEER'S ANSWER TO A REMEDIATION ──────────────────────────────────────────────
-- Another channel on file, in the order the delivery loop already uses: the confirmed WhatsApp number,
-- SMS to the verified mobile, then the email on file if it differs from the one that failed. A fixture
-- is refused here, not merely never sent here: nothing addressed to ZZ DEMO or example.invalid resends.
create or replace function public.fn_sales_engineer_answers_delivery_remediate(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; req public.agent_actions; n public.notifications;
  v_role text; v_failed_email text; v_failed_ch text; v_cust uuid; v_lead bigint; v_subject text; v_body text;
  v_ch text; v_phone text; v_email text; v_rs bigint; v_type text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff' and detail->>'type' = 'delivery.remediate';
  if not found then raise exception 'fn_sales_engineer_answers_delivery_remediate: % is not a delivery.remediate handoff', p_id; end if;
  select * into req from public.agent_actions where id = (a.detail->>'request_id')::bigint;
  if req.id is null then
    return jsonb_build_object('waiting', 'ceo re-verification', 'resend_request_id', null,
      'reply', 'sales_engineer: request ' || coalesce(a.detail->>'request_id', '?') || ' no longer exists, so there is nothing to resend.');
  end if;
  select * into n from public.notifications
   where id = coalesce((req.detail->>'retry_notification_id')::bigint, (req.evidence->>'notification_id')::bigint);
  v_role := coalesce(req.detail->>'recipient_role', n.to_role);
  v_failed_email := coalesce(n.to_email, req.detail->'prepared'->>'to_email', req.detail->>'to_email');
  if req.detail::text ilike '%ZZ DEMO%' or coalesce(v_failed_email, '') ilike '%@example.invalid' then
    return jsonb_build_object('waiting', 'ceo re-verification', 'resend_request_id', null,
      'reply', 'sales_engineer: a ZZ DEMO fixture; nothing is resent to a fixture address.');
  end if;
  v_failed_ch := coalesce(n.channel, req.detail->'prepared'->>'channel', 'email');
  v_cust := (req.detail->>'customer_id')::uuid;
  v_lead := coalesce((req.detail->>'supplier_id')::bigint, n.lead_id);
  v_type := coalesce(n.type, req.detail->>'msg_type');
  v_subject := coalesce(n.subject, req.detail->'prepared'->>'subject', req.detail->>'subject_en');
  v_body := coalesce(n.body, req.detail->'prepared'->>'body', req.detail->>'body_en');
  if coalesce(btrim(v_body), '') = '' then
    return jsonb_build_object('waiting', 'ceo re-verification', 'resend_request_id', null,
      'reply', 'sales_engineer: the words of the ' || coalesce(v_type, 'notice') || ' are gone, so it cannot be resent.');
  end if;

  if v_failed_ch <> 'whatsapp' then
    v_phone := public.fn_whatsapp_destination(v_role, v_cust, v_lead, v_failed_email);
    if v_phone is not null then v_ch := 'whatsapp'; end if;
  end if;
  if v_ch is null and v_failed_ch <> 'sms' then
    v_phone := public.fn_verified_mobile(v_role, v_cust, v_lead, v_failed_email);
    if v_phone is not null then v_ch := 'sms'; end if;
  end if;
  if v_ch is null then
    v_email := case v_role when 'customer' then (select c.email from public.customers c where c.id = v_cust)
                           when 'supplier' then (select coalesce(l.claimed_by, l.email) from public.leads l where l.id = v_lead) end;
    if coalesce(v_email, '') ~ '@' and v_email !~* '@example\.invalid$'
       and lower(btrim(v_email)) is distinct from lower(btrim(coalesce(v_failed_email, ''))) then
      v_ch := 'email';
    end if;
  end if;
  if v_ch is null then
    return jsonb_build_object('waiting', 'ceo re-verification', 'resend_request_id', null,
      'reply', 'sales_engineer: no other channel is on file for this ' || coalesce(v_role, 'recipient')
               || ' (the ' || v_failed_ch || ' send failed; no confirmed WhatsApp, verified mobile or other email).');
  end if;

  -- retry_of makes fn_originator_checks_delivery escalate rather than retry again if this one fails too.
  v_rs := public.fn_seat_handoff('sales_engineer', 'customer_support', 'delivery.request', 'notifications', 'remediate:' || a.id,
    jsonb_build_object('retry_of', req.id, 'remediate_handoff_id', a.id, 'msg_type', v_type, 'recipient_role', v_role,
      'to_email', coalesce(v_email, v_failed_email), 'supplier_id', v_lead, 'customer_id', v_cust,
      'inquiry_id', coalesce(n.inquiry_id::text, req.detail->>'inquiry_id'), 'quote_id', coalesce(n.quote_id::text, req.detail->>'quote_id'),
      'prepared', jsonb_build_object('type', v_type, 'kind', n.kind, 'to_role', v_role, 'lead_id', v_lead,
        'inquiry_id', coalesce(n.inquiry_id::text, req.detail->>'inquiry_id'), 'quote_id', coalesce(n.quote_id::text, req.detail->>'quote_id'),
        'subject', v_subject, 'body', v_body, 'lang', coalesce(n.lang, req.detail->>'locale', 'en'), 'channel', v_ch,
        'to_email', case when v_ch = 'email' then v_email else v_failed_email end,
        'to_phone', case when v_ch in ('whatsapp', 'sms') then v_phone end)));
  return jsonb_build_object('waiting', 'ceo re-verification', 'resend_request_id', v_rs, 'channel', v_ch,
    'reply', 'sales_engineer resent the ' || coalesce(v_type, 'notice') || ' to the ' || coalesce(v_role, 'recipient')
             || ' by ' || v_ch || ' (request ' || v_rs || ').');
end $fn$;
revoke execute on function public.fn_sales_engineer_answers_delivery_remediate(bigint) from public, anon, authenticated;

-- ── 2. THE HANDOFF KINDS, DECIDED PER KIND ───────────────────────────────────────────────────────
-- The test for each kind: must the SENDER verify the outcome, and can the receiving seat's reply leave
-- the row pending without breaking a routine that reads it?
--
--   REPLY WINDOW + ONLY THE ORIGINATOR CLOSES (17 kinds; closer: fn_originators_reverify_handoffs)
--     sales_engineer -> accountant  refund.requested, billing.question, charge.disputed        1 hour
--       The sales engineer asked about money on a customer's or supplier's behalf; the accountant
--       answers at once with its own handoff back. It closes when that answer exists, or with the
--       CEO's decision once an unanswered question has been reported.
--     accountant -> sales_engineer  reveal.paid, payment.failed, payment.received, refund.request_checked,
--       refund.declined, refund.in_progress, subscription.due, billing.answer, charge.dispute_answer,
--       nonresponse.charge_reminder, nonresponse.final_demand, subscription.dunning,
--       subscription.payment_failed, subscription.renewal_reminder                           24 hours
--       Money the customer or supplier must be told about. The accountant closes each when the
--       delivery loop shows every notice arrived (both of them on reveal.paid), or with the CEO's
--       decision on the failure. 24 hours is the delivery watch's own overdue line.
--   RE-VERIFIED BY THE ORIGINATOR, FLAG LEFT OFF (3 kinds): refund.paid, nonresponse.charge_raised,
--       charge.corrected. fn_ceo_incident_fix_round, fn_accountant_applies_incident_fix and
--       fn_ceo_refund_checklist read status 'done' on these as "this notice went out" (to supersede it
--       with a correction, or to pass customer_told / supplier_told). A pending reply would hide a sent
--       notice. The accountant verifies them all the same and records its verdict on the row
--       (detail.originator_verdict), escalating to the CEO exactly as for the flagged kinds.
--   ALREADY CLOSED BY THE SENDER'S OWN CHECK (12 kinds, unchanged):
--     delivery.request (5 senders): fn_customer_support_delivery_watch reads only done or failed requests,
--       so a pending request would never get its result. The sender closes the loop on the request row
--       itself (fn_originator_checks_delivery writes loop, closed_by, close_check).
--     delivery.result (5 receivers): it IS the reply to a delivery.request, acted on the moment it arrives.
--       A loop around a reply would need a reply to the reply.
--     refund.remediate (2): the CEO re-measures its checklist (fn_ceo_refund_loop_sweep) and closes, and
--       fn_sales_engineer_attaches_delivery_result closes the sales engineer's on its delivery result,
--       after which fn_ceo_refund_loop_advance reviews it as the CEO. Neither names itself as closer, so
--       the flag would make z61 refuse both.
--   CLOSED BY ANOTHER SEAT ON PURPOSE (2 kinds, unchanged):
--     incident.fix: the accountant (or its runtime, for a Stripe fix) closes; every completion runs
--       fn_ceo_incident_advance, which re-verifies the whole refund checklist as the CEO.
--     backup.remediate: only the IT engineer closes it, after verifying every file (z60); the CEO then
--       completes its report (fn_ceo_backup_escalation_sweep). The flag would require the IT engineer
--       to close in the CEO's name.
--   NEW: delivery.remediate (ceo -> sales_engineer), 24 hours, closed by the CEO (section 4).
do $kinds$
declare n int;
begin
  update public.seat_handoff_kind k set reply_within = v.win, originator_closes = true
    from (values
      ('refund.requested',              'sales_engineer', 'accountant',     interval '1 hour'),
      ('billing.question',              'sales_engineer', 'accountant',     interval '1 hour'),
      ('charge.disputed',               'sales_engineer', 'accountant',     interval '1 hour'),
      ('reveal.paid',                   'accountant',     'sales_engineer', interval '24 hours'),
      ('payment.failed',                'accountant',     'sales_engineer', interval '24 hours'),
      ('payment.received',              'accountant',     'sales_engineer', interval '24 hours'),
      ('refund.request_checked',        'accountant',     'sales_engineer', interval '24 hours'),
      ('refund.declined',               'accountant',     'sales_engineer', interval '24 hours'),
      ('refund.in_progress',            'accountant',     'sales_engineer', interval '24 hours'),
      ('subscription.due',              'accountant',     'sales_engineer', interval '24 hours'),
      ('billing.answer',                'accountant',     'sales_engineer', interval '24 hours'),
      ('charge.dispute_answer',         'accountant',     'sales_engineer', interval '24 hours'),
      ('nonresponse.charge_reminder',   'accountant',     'sales_engineer', interval '24 hours'),
      ('nonresponse.final_demand',      'accountant',     'sales_engineer', interval '24 hours'),
      ('subscription.dunning',          'accountant',     'sales_engineer', interval '24 hours'),
      ('subscription.payment_failed',   'accountant',     'sales_engineer', interval '24 hours'),
      ('subscription.renewal_reminder', 'accountant',     'sales_engineer', interval '24 hours')
    ) v(type, from_seat, to_seat, win)
   where k.type = v.type and k.from_seat = v.from_seat and k.to_seat = v.to_seat;
  get diagnostics n = row_count;
  if n <> 17 then raise exception 'expected 17 seat_handoff_kind rows to flip, found %', n; end if;
  -- The three verified without the flag carry the window the accountant's check reads.
  update public.seat_handoff_kind set reply_within = interval '24 hours', originator_closes = false
   where from_seat = 'accountant' and to_seat = 'sales_engineer' and type in ('refund.paid', 'nonresponse.charge_raised', 'charge.corrected');
  get diagnostics n = row_count;
  if n <> 3 then raise exception 'expected 3 verify-only rows, found %', n; end if;
end
$kinds$;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
values ('delivery.remediate', 'ceo', 'sales_engineer',
        'The CEO read that a notice did not reach a real customer or supplier: reach them on another channel on file, or say none exists. The CEO re-verifies the resend and closes.',
        'fn_sales_engineer_answers_delivery_remediate', interval '24 hours', true,
        'scripts/sql/the_ceo_decides_every_sales_engineer_report_and_every_sender_closes_its_handoff.sql')
on conflict (type, from_seat, to_seat) do update
  set meaning = excluded.meaning, handler = excluded.handler, reply_within = excluded.reply_within,
      originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

-- ── 3. THE CEO DECIDES ONE REPORT ───────────────────────────────────────────────────────────────
-- A defect goes round the IT loop: the finding names the seat that owns the broken step, the IT
-- engineer hands it there, re-verifies, and the founder hears of it only as a new bug nobody fixed.
create or replace function public.fn_ceo_sales_engineer_report_decide(p_report_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r public.support_ceo_report; req public.agent_actions; h public.agent_actions;
  v_addr text; v_h bigint; v_receipt text; v_decision text; v_key text; v_what text; v_acc jsonb;
begin
  select * into r from public.support_ceo_report where id = p_report_id and source_agent = 'sales_engineer' for update;
  if not found or r.status <> 'sent' then
    return jsonb_build_object('ok', false, 'reason', 'no open sales engineer report ' || p_report_id);
  end if;

  if r.idempotency_key like 'handoff\_unanswered:%' then
    select * into h from public.agent_actions where id = (r.verified_evidence->>'handoff_id')::bigint;
    v_key := 'monitor:handoff_unanswered:' || coalesce(h.detail->>'type', 'unknown') || ':' || coalesce(h.agent, 'unknown');
    perform public.fn_it_engineer_finding_upsert(v_key,
      'The ' || coalesce(h.agent, 'receiving seat') || ' did not answer "' || coalesce(h.detail->>'type', '?') || '" from the sales engineer within its window',
      'public.' || coalesce((select k.handler from public.seat_handoff_kind k
                              where k.type = h.detail->>'type' and k.from_seat = h.detail->>'from' and k.to_seat = h.agent), 'fn_seat_handoff_act'),
      'agent_facing', 1,
      jsonb_build_object('owner_seat', h.agent, 'handoff_id', h.id, 'report_id', r.id, 'handoff_status', h.status, 'error', h.detail->>'error'),
      '{}'::text[], array['why the handler did not answer handoff ' || coalesce(h.id::text, '?')], 'fn_ceo_sales_engineer_report_decide');
    v_decision := 'defect_raised';
    v_receipt := 'ceo: decided. "' || coalesce(h.detail->>'type', '?') || '" (handoff ' || coalesce(h.id::text, '?') || ') went unanswered past its window, '
      || 'so the handler is at fault: raised as IT finding ' || v_key || ', which the IT loop hands to the ' || coalesce(h.agent, 'owning seat')
      || ' and re-verifies; it clears when the next conversation of this kind works.';

  elsif r.idempotency_key not like 'delivery\_undelivered:%' then
    v_decision := 'read';
    v_receipt := 'ceo: read the sales engineer''s ' || r.severity || ' report "' || left(r.subject, 140) || '" with its evidence.';

  else
    select * into req from public.agent_actions where id = (r.verified_evidence->>'request_id')::bigint;
    v_addr := coalesce(req.detail->'prepared'->>'to_email', req.detail->>'to_email', '');
    v_what := coalesce(req.detail->>'msg_type', substring(r.subject from '^A (\S+)'), 'notice');
    if req.id is null then
      v_decision := 'need_not_go_request_gone';
      v_receipt := 'ceo: decided it need not go. Request ' || coalesce(r.verified_evidence->>'request_id', '?') || ' (a ' || v_what
        || ') no longer exists: its words and its address are gone, so nothing can be resent.';
    elsif req.detail ? 'remediate_handoff_id' then
      v_decision := 'part_of_remediation';
      v_receipt := 'ceo: read. This is the resend for remediation handoff ' || (req.detail->>'remediate_handoff_id')
        || ', and it is decided there.';
    elsif req.detail::text ilike '%ZZ DEMO%' or v_addr ilike '%@example.invalid' then
      v_decision := 'need_not_go_fixture';
      v_receipt := 'ceo: decided it need not go. A ZZ DEMO fixture ' || v_what || ' addressed to ' || coalesce(nullif(v_addr, ''), 'a fixture')
        || ': example.invalid is never delivered, and no real person was meant to receive it.';
    elsif coalesce(req.detail->>'recipient_role', '') not in ('customer', 'supplier') then
      v_decision := 'need_not_go_internal';
      v_receipt := 'ceo: decided it need not go. A ' || v_what || ' addressed to ''' || coalesce(req.detail->>'recipient_role', 'nobody')
        || ''', which is no seat and not a kind the founder is emailed; the CEO has read it here, which is the delivery it needed.';
    else
      v_h := public.fn_seat_handoff('ceo', 'sales_engineer', 'delivery.remediate', 'support_ceo_report', r.id::text,
        jsonb_build_object('report_id', r.id, 'request_id', req.id, 'msg_type', v_what,
                           'recipient_role', req.detail->>'recipient_role', 'result', r.verified_evidence->>'result'));
      v_decision := 'remediate';
      v_receipt := 'ceo: decided. The ' || v_what || ' did not reach the ' || (req.detail->>'recipient_role') || ' ('
        || coalesce(r.verified_evidence->>'result', '?') || '): the sales engineer reaches them on another channel on file (handoff '
        || v_h || '), and the CEO closes it when the resend is confirmed or no channel exists.';
    end if;
  end if;

  v_acc := public.fn_ceo_accept_support_report(r.id, v_receipt, v_decision);
  if not coalesce((v_acc->>'ok')::boolean, false) then
    raise exception 'fn_ceo_sales_engineer_report_decide: report % was not accepted: %', r.id, v_acc->>'reason';
  end if;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'decision', v_decision, 'remediation_handoff', v_h);
end $fn$;
revoke execute on function public.fn_ceo_sales_engineer_report_decide(bigint) from public, anon, authenticated;

-- The accountant's notice escalations (section 6 files them). A notice that did not ARRIVE is decided
-- on the sales engineer's delivery_undelivered report, where a real recipient gets a remediation; these
-- two are the cases that report cannot cover: the notice never left, or its send has no outcome.
create or replace function public.fn_ceo_accountant_notice_report_decide(p_report_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r public.support_ceo_report; h public.agent_actions; v_fixture boolean; v_key text; v_owner text;
  v_decision text; v_receipt text; v_acc jsonb;
begin
  select * into r from public.support_ceo_report where id = p_report_id and source_agent = 'accountant' for update;
  if not found or r.status <> 'sent'
     or not (r.idempotency_key like 'notice\_undelivered:%' or r.idempotency_key like 'notice\_unverified:%') then
    return jsonb_build_object('ok', false, 'reason', 'no open accountant notice report ' || p_report_id);
  end if;
  select * into h from public.agent_actions where id = (r.verified_evidence->>'handoff_id')::bigint;
  v_fixture := h.detail::text ilike '%ZZ DEMO%'
    or coalesce((public.fn_delivery_request_outcome((h.evidence->>'delivery_request')::bigint)->>'fixture')::boolean, false)
    or exists (select 1 from public.customers c where c.id::text = h.detail->>'customer_id' and c.email ilike '%@example.invalid')
    or exists (select 1 from public.leads l where l.id::text = h.detail->>'supplier_id'
                                            and (l.company_name ilike '%ZZ DEMO%' or coalesce(l.claimed_by, l.email, '') ilike '%@example.invalid'));

  if v_fixture then
    v_decision := 'need_not_go_fixture';
    v_receipt := 'ceo: decided it need not go. The ' || coalesce(h.detail->>'type', '?') || ' notice (handoff ' || coalesce(h.id::text, '?')
      || ') is about a ZZ DEMO fixture: no real person was meant to receive it.';
  elsif r.idempotency_key like 'notice\_unverified:%'
        and jsonb_array_length(coalesce(r.verified_evidence->'sends', '[]'::jsonb)) > 0
        and not exists (select 1 from jsonb_array_elements(r.verified_evidence->'sends') o
                         where public.fn_delivery_request_outcome((o->>'request_id')::bigint)->>'state' not in ('reached', 'ended', 'failed')) then
    -- Every send (both on a reveal) reached an outcome between the report and this decision: nothing is
    -- broken. A send that failed is carried by the sales engineer's delivery_undelivered report.
    v_decision := 'arrived_late';
    v_receipt := 'ceo: read. Every send of the ' || coalesce(h.detail->>'type', '?') || ' notice (handoff ' || coalesce(h.id::text, '?')
      || ') reached an outcome after it was reported, so there is no defect to raise'
      || case when exists (select 1 from jsonb_array_elements(r.verified_evidence->'sends') o
                            where public.fn_delivery_request_outcome((o->>'request_id')::bigint)->>'state' = 'failed')
              then '; a send that did not arrive is decided on its delivery_undelivered report.' else '.' end;
  elsif r.idempotency_key like 'notice\_undelivered:%' and h.status is distinct from 'failed' then
    v_decision := 'unreachable_recorded';
    v_receipt := 'ceo: decided. The ' || coalesce(h.detail->>'type', '?') || ' notice (handoff ' || coalesce(h.id::text, '?')
      || ') could not be written because no address is on file for the ' || case when h.evidence->>'customer_reachable' = 'false' then 'customer'
                                                                    when h.evidence->>'supplier_reachable' = 'false' or h.detail ? 'supplier_id' then 'supplier'
                                                                    else 'customer' end
      || '. Recorded that it cannot go until one exists; the portal shows the same facts when they sign in.';
  else
    -- The sales engineer's handler raised, or the send never reached an outcome: a defect.
    v_owner := case when r.idempotency_key like 'notice\_undelivered:%' then 'sales_engineer' else 'customer_support' end;
    v_key := 'monitor:' || split_part(r.idempotency_key, ':', 1) || ':' || coalesce(h.detail->>'type', 'unknown');
    perform public.fn_it_engineer_finding_upsert(v_key,
      case when v_owner = 'sales_engineer'
           then 'The sales engineer could not write a ' || coalesce(h.detail->>'type', '?') || ' notice the accountant asked for'
           else 'A ' || coalesce(h.detail->>'type', '?') || ' notice has no delivery outcome after its window' end,
      case when v_owner = 'sales_engineer' then 'public.' || coalesce((select k.handler from public.seat_handoff_kind k
                                                    where k.type = h.detail->>'type' and k.from_seat = 'accountant' and k.to_seat = 'sales_engineer'), 'fn_seat_handoff_act')
           else 'public.fn_customer_support_delivery_watch' end,
      'agent_facing', 1,
      jsonb_build_object('owner_seat', v_owner, 'handoff_id', h.id, 'report_id', r.id, 'handoff_status', h.status,
                         'error', h.detail->>'error', 'delivery_loop', r.verified_evidence->>'delivery_loop'),
      '{}'::text[], array['why handoff ' || coalesce(h.id::text, '?') || ' produced no delivered notice'], 'fn_ceo_accountant_notice_report_decide');
    v_decision := 'defect_raised';
    v_receipt := 'ceo: decided. The ' || coalesce(h.detail->>'type', '?') || ' notice (handoff ' || coalesce(h.id::text, '?') || ') '
      || case when v_owner = 'sales_engineer' then 'was never written' else 'has no delivery outcome' end
      || ', which is a defect: raised as IT finding ' || v_key || ', which the IT loop hands to ' || v_owner || ' and re-verifies; it clears when the next conversation of this kind works.';
  end if;

  v_acc := public.fn_ceo_accept_support_report(r.id, v_receipt, v_decision);
  if not coalesce((v_acc->>'ok')::boolean, false) then
    raise exception 'fn_ceo_accountant_notice_report_decide: report % was not accepted: %', r.id, v_acc->>'reason';
  end if;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'decision', v_decision);
end $fn$;
revoke execute on function public.fn_ceo_accountant_notice_report_decide(bigint) from public, anon, authenticated;

-- Live definition (the_accountant_closes_every_month_and_the_ceo_signs_for_it.sql lineage) with the
-- notice escalations left out: reading them is not deciding them.
create or replace function public.fn_ceo_accountant_reports_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.support_ceo_report; n int := 0;
begin
  -- A dispute review is NOT acknowledged here: reading it is not approving it. It stays open until the
  -- CEO approves the submission (fn_ceo_approve_dispute_submission) or the accountant submits at T-24h.
  -- A notice escalation is decided by fn_ceo_accountant_notice_report_decide, not acknowledged here.
  for r in select * from public.support_ceo_report where source_agent = 'accountant' and status = 'sent'
              and idempotency_key not like 'dispute\_review:%'
              and idempotency_key not like 'notice\_undelivered:%' and idempotency_key not like 'notice\_unverified:%'
            order by id loop
    perform public.fn_ceo_accept_support_report(r.id,
      'ceo: read the accountant''s ' || r.severity || ' report "' || left(r.subject, 140) || '" with its evidence ('
        || (select count(*) from jsonb_object_keys(r.verified_evidence)) || ' field(s))');
    n := n + 1;
  end loop;
  return jsonb_build_object('acknowledged', n);
end $fn$;
revoke execute on function public.fn_ceo_accountant_reports_sweep() from public, anon, authenticated;

-- ── 4. THE CEO'S SWEEP: DECIDE, THEN RE-VERIFY WHAT IT HANDED BACK ────────────────────────────────
-- One row at a time in its own sub-transaction: a row that raises is named in 'errors' (the tick turns
-- that into an IT finding) and the other 99 still get decided.
-- ponytail: 100 reports a tick bounds the tick's time inside resilience_ping; the backlog clears in
-- about eight ticks. Raise the limit only if reports arrive faster than 400 an hour.
create or replace function public.fn_ceo_sales_engineer_reports_sweep(p_limit int default 100)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; h public.agent_actions; rs public.agent_actions; v jsonb; k text; v_verdict text; v_window interval;
        n jsonb := '{}'::jsonb; n_closed int := 0; n_wait int := 0; v_err jsonb := '[]'::jsonb;
begin
  for r in select s.id, s.source_agent from public.support_ceo_report s
            where s.status = 'sent'
              and (s.source_agent = 'sales_engineer'
                   or (s.source_agent = 'accountant'
                       and (s.idempotency_key like 'notice\_undelivered:%' or s.idempotency_key like 'notice\_unverified:%')))
              -- a report whose decision raised waits an hour, so it cannot hold the head of the queue
              and (s.last_delivery_error is null or s.next_review_at <= now())
            order by s.id limit greatest(coalesce(p_limit, 100), 1) loop
    begin
      v := case when r.source_agent = 'accountant' then public.fn_ceo_accountant_notice_report_decide(r.id)
                else public.fn_ceo_sales_engineer_report_decide(r.id) end;
      k := coalesce(v->>'decision', 'not_decided');
      n := n || jsonb_build_object(k, coalesce((n->>k)::int, 0) + 1);
    exception when others then
      v_err := v_err || jsonb_build_object('report_id', r.id, 'error', left(sqlerrm, 300));
      update public.support_ceo_report
         set last_delivery_error = left('ceo decision failed: ' || sqlerrm, 300), next_review_at = now() + interval '1 hour'
       where id = r.id;
    end;
  end loop;

  select reply_within into v_window from public.seat_handoff_kind
   where type = 'delivery.remediate' and from_seat = 'ceo' and to_seat = 'sales_engineer';
  v_window := coalesce(v_window, interval '24 hours');
  for h in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'delivery.remediate' and detail->>'from' = 'ceo'
              and status in ('pending', 'failed') order by id loop
    begin
      rs := null;
      if (h.evidence->>'resend_request_id') is not null then
        select * into rs from public.agent_actions where id = (h.evidence->>'resend_request_id')::bigint;
      end if;
      v_verdict := case
        when h.status = 'failed' then
          'unreachable: the sales engineer could not act (' || coalesce(h.detail->>'error', 'no error recorded') || ')'
        when rs.id is not null and rs.detail->>'loop' in ('confirmed', 'handled_by_the_ladder') then
          'reached: the resend by ' || coalesce(h.evidence->>'channel', '?') || ' was confirmed (request ' || rs.id || ')'
        when rs.id is not null and rs.detail ? 'loop' then
          'unreachable: the resend by ' || coalesce(h.evidence->>'channel', '?') || ' ended ' || (rs.detail->>'loop') || ' (request ' || rs.id || ')'
        when rs.id is null and h.detail ? 'replied_at' then
          'unreachable: ' || coalesce(h.evidence->>'reply', 'no other channel on file')
        when now() > h.created_at + v_window then
          'unreachable: no outcome within ' || v_window
      end;
      if v_verdict is null then n_wait := n_wait + 1; continue; end if;
      perform set_config('qd.handoff_closer', 'ceo', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'ceo', 'verified_at', now(), 'verdict', v_verdict));
      perform set_config('qd.handoff_closer', '', true);
      n_closed := n_closed + 1;
    exception when others then
      v_err := v_err || jsonb_build_object('remediation_handoff', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;

  return jsonb_build_object('decided', n, 'remediations_closed', n_closed, 'remediations_waiting', n_wait, 'errors', v_err,
    'still_unread', (select count(*) from public.support_ceo_report where source_agent = 'sales_engineer' and status = 'sent'));
end $fn$;
revoke execute on function public.fn_ceo_sales_engineer_reports_sweep(int) from public, anon, authenticated;

-- ── 5. THE SALES ENGINEER CLOSES ITS REPORT ONCE THE CEO'S ANSWER IS ON IT ─────────────────────────
-- The sender of a report closes it, as the accountant and the IT engineer do theirs. A report with a
-- remediation still open waits for it; the remediation's verdict goes into the completion note.
create or replace function public.fn_sales_engineer_reports_complete(p_report_id bigint default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n int;
begin
  update public.support_ceo_report r
     set status = 'completed', completed_at = now(),
         completion_note = 'sales_engineer saw the CEO''s receipt: ' || r.acceptance_receipt
           || coalesce(' Outcome: ' || (select a.evidence->>'verdict' from public.agent_actions a
                                         where a.kind = 'handoff' and a.agent = 'sales_engineer'
                                           and a.target_id = 'delivery.remediate:' || r.id and a.status = 'done'
                                         order by a.id desc limit 1), '')
   where r.source_agent = 'sales_engineer' and r.status = 'accepted' and r.acceptance_receipt is not null
     and (p_report_id is null or r.id = p_report_id)
     and not exists (select 1 from public.agent_actions a
                      where a.kind = 'handoff' and a.agent = 'sales_engineer'
                        and a.target_id = 'delivery.remediate:' || r.id and a.status <> 'done');
  get diagnostics n = row_count;
  return jsonb_build_object('completed_after_receipt', n);
end $fn$;
revoke execute on function public.fn_sales_engineer_reports_complete(bigint) from public, anon, authenticated;

-- ── 6. EVERY SENDER RE-VERIFIES WHAT IT HANDED ON ───────────────────────────────────────────────
-- Every row ends one of two ways: answered / reached, or reported to the CEO and closed with the CEO's
-- decision once that report is decided. Rows not yet reported are scanned first, so rows waiting on a
-- CEO decision cannot crowd out new ones. Each row runs in its own sub-transaction.
create or replace function public.fn_originators_reverify_handoffs(p_limit int default 200)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  c_questions constant text[] := array['refund.requested', 'billing.question', 'charge.disputed'];
  c_notices constant text[] := array['reveal.paid', 'payment.failed', 'payment.received', 'refund.request_checked', 'refund.paid',
    'refund.declined', 'refund.in_progress', 'nonresponse.charge_raised', 'charge.corrected', 'subscription.due', 'billing.answer',
    'charge.dispute_answer', 'nonresponse.charge_reminder', 'nonresponse.final_demand', 'subscription.dunning',
    'subscription.payment_failed', 'subscription.renewal_reminder'];
  h public.agent_actions; k public.seat_handoff_kind; rep public.support_ceo_report; v_rep jsonb; v_answer bigint;
  v_reqs bigint[]; v_outs jsonb; v_verdict text; v_waiting boolean; v_failed jsonb; v_undecided int;
  n_answered int := 0; n_q_closed_by_ceo int := 0; n_q_reported int := 0; n_q_wait int := 0;
  n_closed int := 0; n_recorded int := 0; n_reported int := 0; n_wait int := 0; v_err jsonb := '[]'::jsonb;
  f record; v_type text; v_ok boolean; n_cleared int := 0;
begin
  -- 1. THE SALES ENGINEER: did the accountant answer the question it was asked?
  for h in select * from public.agent_actions a
            where a.kind = 'handoff' and a.detail->>'from' = 'sales_engineer' and a.agent = 'accountant'
              and a.detail->>'type' = any (c_questions) and a.status in ('pending', 'failed')
            order by (a.detail ? 'escalated_report_id'), a.id limit greatest(coalesce(p_limit, 200), 1) loop
    begin
      select * into k from public.seat_handoff_kind where type = h.detail->>'type' and from_seat = 'sales_engineer' and to_seat = 'accountant';
      -- An answer counts whatever became of it afterwards: relaying it is the accountant's notice loop.
      v_answer := null;
      select a.id into v_answer from public.agent_actions a
       where a.kind = 'handoff' and a.agent = 'sales_engineer' and a.detail->>'from' = 'accountant'
         and a.target_id = case h.detail->>'type'
                             when 'refund.requested' then 'refund.request_checked:' || (h.detail->>'subject_id')
                             when 'billing.question' then 'billing.answer:' || h.id end
       limit 1;
      if v_answer is null and h.detail->>'type' = 'charge.disputed' then
        select a.id into v_answer from public.agent_actions a
         where a.kind = 'handoff' and a.agent = 'sales_engineer' and a.detail->>'type' = 'charge.dispute_answer'
           and a.target_id like 'charge.dispute\_answer:%:' || h.id
         limit 1;
      end if;
      rep := null;
      if h.detail ? 'escalated_report_id' then
        select * into rep from public.support_ceo_report where id = (h.detail->>'escalated_report_id')::bigint;
      end if;
      v_verdict := case
        when v_answer is not null then 'answered by the accountant (handoff ' || v_answer || ')'
        when rep.status in ('accepted', 'completed') then 'unanswered; the CEO decided: ' || left(rep.acceptance_receipt, 400)
      end;

      if v_verdict is not null then
        perform set_config('qd.handoff_closer', 'sales_engineer', true);
        perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
          'verified_by', 'sales_engineer', 'verified_at', now(), 'verdict', v_verdict));
        perform set_config('qd.handoff_closer', '', true);
        if v_answer is not null then n_answered := n_answered + 1; else n_q_closed_by_ceo := n_q_closed_by_ceo + 1; end if;
      elsif rep.id is null and (h.status = 'failed' or now() > h.created_at + coalesce(k.reply_within, interval '1 hour')) then
        v_rep := public.fn_support_report_to_ceo('handoff_unanswered:' || h.id, 'serious',
          'The accountant did not answer "' || (h.detail->>'type') || '" from the sales engineer (handoff ' || h.id || ')',
          jsonb_build_object('handoff_id', h.id, 'type', h.detail->>'type', 'handoff_status', h.status,
                             'error', h.detail->>'error', 'asked_at', h.created_at, 'reply', h.evidence),
          jsonb_build_array('sales_engineer asked the accountant at ' || to_char(h.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai)'),
          'Decide what fixes the accountant''s answer. The sales engineer closes the question with your decision.',
          'agent_actions#' || h.id, p_review_in => interval '4 hours', p_source_agent => 'sales_engineer');
        if not coalesce((v_rep->>'ok')::boolean, false) then
          raise exception 'the CEO report for handoff % was refused: %', h.id, v_rep->>'reason';
        end if;
        update public.agent_actions set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
         where id = h.id;
        n_q_reported := n_q_reported + 1;
      else
        n_q_wait := n_q_wait + 1;
      end if;
    exception when others then
      v_err := v_err || jsonb_build_object('handoff', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;

  -- 2. THE ACCOUNTANT: did the money notice it asked for reach the customer or supplier?
  for h in select * from public.agent_actions a
            where a.kind = 'handoff' and a.detail->>'from' = 'accountant' and a.agent = 'sales_engineer'
              and a.detail->>'type' = any (c_notices) and not (a.detail ? 'originator_verdict')
              and (a.status in ('done', 'failed') or (a.status = 'pending' and a.detail ? 'replied_at'))
            order by (a.detail ? 'escalated_report_id'), a.id limit greatest(coalesce(p_limit, 200), 1) loop
    begin
      select * into k from public.seat_handoff_kind where type = h.detail->>'type' and from_seat = 'accountant' and to_seat = 'sales_engineer';
      v_verdict := null; rep := null;
      -- Every send the notice made: the one the handler names, and on a reveal the supplier's as well.
      v_reqs := array_remove(array[(h.evidence->>'delivery_request')::bigint,
                  case when h.detail->>'type' = 'reveal.paid' then
                    (select a.id from public.agent_actions a where a.agent = 'customer_support' and a.kind = 'handoff'
                      and a.target_id = 'delivery.request:quote_accepted:' || (h.detail->>'subject_id') order by a.id desc limit 1) end], null);
      if h.detail ? 'escalated_report_id' then
        select * into rep from public.support_ceo_report where id = (h.detail->>'escalated_report_id')::bigint;
      end if;

      if h.detail ? 'superseded_by_incident' then
        v_verdict := 'superseded by refund incident ' || (h.detail->>'superseded_by_incident');
      elsif rep.id is not null then
        -- Reported already: it ends with the CEO's decision.
        -- A send recorded on the report that has since failed is decided on its own delivery_undelivered
        -- report; the notice waits for that decision too, and carries it in the verdict.
        if rep.status = 'completed'
           and not exists (select 1 from jsonb_array_elements(coalesce(rep.verified_evidence->'sends', '[]'::jsonb)) o
                            cross join lateral public.fn_delivery_request_outcome((o->>'request_id')::bigint) oc
                            where oc->>'state' = 'failed'
                              and not exists (select 1 from public.support_ceo_report s
                                               where s.idempotency_key = oc->>'report_key' and s.status = 'completed')) then
          v_verdict := 'the CEO decided: ' || left(coalesce(rep.completion_note, rep.acceptance_receipt), 400)
            || coalesce(' | ' || (select string_agg(left(coalesce(s.completion_note, s.acceptance_receipt), 300), ' | ')
                                    from jsonb_array_elements(coalesce(rep.verified_evidence->'sends', '[]'::jsonb)) o
                                    cross join lateral public.fn_delivery_request_outcome((o->>'request_id')::bigint) oc
                                    join public.support_ceo_report s on s.idempotency_key = oc->>'report_key'
                                   where oc->>'state' = 'failed'), '');
        end if;
      elsif h.status = 'failed' or cardinality(v_reqs) = 0
            or (h.detail->>'type' = 'reveal.paid'
                and (h.evidence->>'customer_reachable' = 'false' or h.evidence->>'supplier_reachable' = 'false')) then
        -- The notice never left: no address on file, or the sales engineer could not write it.
        v_rep := public.fn_support_report_to_ceo('notice_undelivered:' || h.id, 'elevated',
          'A ' || (h.detail->>'type') || ' notice the accountant asked for was not sent (handoff ' || h.id || ')',
          jsonb_build_object('handoff_id', h.id, 'type', h.detail->>'type', 'handoff_status', h.status,
                             'reply', h.evidence, 'error', h.detail->>'error'),
          jsonb_build_array('accountant asked the sales engineer at ' || to_char(h.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai)'),
          'Decide how this customer or supplier learns of it: an address to use, another channel, or record that it cannot go.',
          'agent_actions#' || h.id, p_review_in => interval '1 day', p_source_agent => 'accountant');
        if not coalesce((v_rep->>'ok')::boolean, false) then
          raise exception 'the CEO report for handoff % was refused: %', h.id, v_rep->>'reason';
        end if;
        update public.agent_actions set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
         where id = h.id;
        n_reported := n_reported + 1;
      else
        select coalesce(jsonb_agg(public.fn_delivery_request_outcome(x)), '[]'::jsonb) into v_outs from unnest(v_reqs) x;
        v_waiting := exists (select 1 from jsonb_array_elements(v_outs) o where o->>'state' in ('waiting', 'missing'));
        v_failed := (select coalesce(jsonb_agg(o), '[]'::jsonb) from jsonb_array_elements(v_outs) o where o->>'state' = 'failed');
        if v_waiting then
          if now() > h.created_at + coalesce(k.reply_within, interval '24 hours') then
            v_rep := public.fn_support_report_to_ceo('notice_unverified:' || h.id, 'elevated',
              'A ' || (h.detail->>'type') || ' notice has no delivery outcome after ' || coalesce(k.reply_within, interval '24 hours') || ' (handoff ' || h.id || ')',
              jsonb_build_object('handoff_id', h.id, 'type', h.detail->>'type', 'sends', v_outs,
                                 'delivery_loop', (select string_agg(o->>'loop', ', ') from jsonb_array_elements(v_outs) o)),
              jsonb_build_array('accountant asked the sales engineer at ' || to_char(h.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai)'),
              'Find out what became of this send. The accountant closes the notice with your decision.',
              'agent_actions#' || h.id, p_review_in => interval '1 day', p_source_agent => 'accountant');
            if not coalesce((v_rep->>'ok')::boolean, false) then
              raise exception 'the CEO report for handoff % was refused: %', h.id, v_rep->>'reason';
            end if;
            update public.agent_actions set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
             where id = h.id;
            n_reported := n_reported + 1;
          end if;
        elsif jsonb_array_length(v_failed) > 0 then
          -- It did not arrive: the sales engineer's delivery_undelivered report carries it to the CEO.
          -- The notice closes with the CEO's decision on that report once it is decided and completed.
          select count(*) into v_undecided from jsonb_array_elements(v_failed) o
           where not exists (select 1 from public.support_ceo_report s where s.idempotency_key = o->>'report_key' and s.status = 'completed');
          if v_undecided = 0 then
            v_verdict := 'did not arrive; the CEO decided: ' || (select string_agg(left(coalesce(s.completion_note, s.acceptance_receipt), 300), ' | ')
              from jsonb_array_elements(v_failed) o join public.support_ceo_report s on s.idempotency_key = o->>'report_key');
          end if;
        else
          -- Only a send that arrived is 'reached'; a stubbed, routed or cancelled one ended without arriving.
          v_verdict := case when exists (select 1 from jsonb_array_elements(v_outs) o where o->>'state' <> 'reached')
                            then 'ended: ' else 'reached: ' end || (select string_agg((o->>'loop') || ' (request ' || (o->>'request_id') || ')', ', ') from jsonb_array_elements(v_outs) o);
        end if;
      end if;

      if v_verdict is null then
        n_wait := n_wait + 1;
      else
        -- Only a pending row is closed; a done or failed row is already terminal and gets the verdict recorded.
        if h.status = 'pending' and k.originator_closes then
          perform set_config('qd.handoff_closer', 'accountant', true);
          perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
            'verified_by', 'accountant', 'verified_at', now(), 'verdict', v_verdict));
          perform set_config('qd.handoff_closer', '', true);
          n_closed := n_closed + 1;
        else
          n_recorded := n_recorded + 1;
        end if;
        update public.agent_actions
           set detail = detail || jsonb_build_object('originator_verdict', v_verdict, 'originator_verified_by', 'accountant', 'originator_verified_at', now())
         where id = h.id;
      end if;
    exception when others then
      v_err := v_err || jsonb_build_object('handoff', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;

  -- 3. A DEFECT THE CEO RAISED CLEARS WHEN THE SAME CONVERSATION WORKS AGAIN. The finding's key names
  -- the conversation; it closes when the latest one of that kind was answered (a question), written
  -- (a notice the sales engineer could not write) or delivered (a notice with no outcome). Closing it
  -- lets the IT loop close its own handoff. What was missed while broken is not re-sent automatically:
  -- the CEO's decision on each is on its report.
  for f in select q.issue_key from public.it_engineer_finding q
            where q.closed_at is null
              and (q.issue_key like 'monitor:handoff\_unanswered:%' or q.issue_key like 'monitor:notice\_undelivered:%'
                   or q.issue_key like 'monitor:notice\_unverified:%') loop
    begin
      v_type := split_part(f.issue_key, ':', 3);
      h := null;
      if f.issue_key like 'monitor:handoff\_unanswered:%' then
        select * into h from public.agent_actions a
         where a.kind = 'handoff' and a.detail->>'type' = v_type and a.detail->>'from' = 'sales_engineer'
           and a.agent = split_part(f.issue_key, ':', 4) and a.status = 'done'
         order by a.id desc limit 1;
        v_ok := h.evidence->>'verdict' like 'answered%';
      elsif f.issue_key like 'monitor:notice\_undelivered:%' then
        select * into h from public.agent_actions a
         where a.kind = 'handoff' and a.detail->>'type' = v_type and a.detail->>'from' = 'accountant'
           and (a.status <> 'pending' or a.detail ? 'replied_at')
         order by a.id desc limit 1;
        v_ok := h.status <> 'failed' and (h.evidence->>'delivery_request') is not null;
      else
        select * into h from public.agent_actions a
         where a.kind = 'handoff' and a.detail->>'type' = v_type and a.detail->>'from' = 'accountant'
           and a.detail ? 'originator_verdict'
         order by a.id desc limit 1;
        -- 'ended' (routed, stubbed, digested, cancelled) is an outcome too: the finding was "no outcome".
        v_ok := h.detail->>'originator_verdict' ~ '^(reached|ended): ';
      end if;
      if coalesce(v_ok, false) then
        perform public.fn_it_engineer_finding_close(f.issue_key,
          'handoff ' || h.id || ' of the same kind worked again, re-checked by fn_originators_reverify_handoffs');
        n_cleared := n_cleared + 1;
      end if;
    exception when others then
      v_err := v_err || jsonb_build_object('finding', f.issue_key, 'error', left(sqlerrm, 300));
    end;
  end loop;

  return jsonb_build_object(
    'defects_cleared', n_cleared,
    'sales_engineer', jsonb_build_object('answered', n_answered, 'closed_with_ceo_decision', n_q_closed_by_ceo,
                                         'reported', n_q_reported, 'waiting', n_q_wait),
    'accountant', jsonb_build_object('closed', n_closed, 'recorded', n_recorded, 'reported', n_reported, 'waiting', n_wait),
    'errors', v_err);
end $fn$;
revoke execute on function public.fn_originators_reverify_handoffs(int) from public, anon, authenticated;

-- ── 7. THE TICK ─────────────────────────────────────────────────────────────────────────────────
-- Live definition (the_it_engineer_closes_every_loop_it_opens.sql) with three steps added after
-- reverify: originators, ceo_sales (the CEO decides, then the sales engineer completes) and
-- ceo_accountant (the accountant's reports are read on every tick, not only when its runtime runs).
-- A row that failed inside a step is reported the same way a failed step is (fn_it_loop_stage).
create or replace function public.fn_it_loop_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare f record; o jsonb := '{}'::jsonb; n_open int := 0; v_err jsonb := '[]'::jsonb; v_step text; x jsonb;
begin
  -- ONE DEFINITION OF OPEN, CALLED, NOT COPIED (22 Sep 2026, it_engineer, UNSOLVED-11). The predicate
  -- (unclosed, and not 'warn' by fn_it_engineer_severity) now lives in fn_it_open_findings, defined in
  -- the_founder_gets_one_it_digest_per_tick.sql, which the founder's brief counts as well — the brief used
  -- to keep its own copy and said 9-10 where this loop said 8. The extra condition below is this loop's own
  -- and stays here: it is about what to RAISE on this tick, not about what is open.
  for f in select q.issue_key, q.started_at from public.fn_it_open_findings() q
            where not exists (select 1 from public.agent_actions a
                               where a.kind = 'handoff' and a.detail->>'type' = 'it.finding'
                                 and a.detail->>'issue_key' = q.issue_key
                                 and (a.detail->>'occurrence_started_at')::timestamptz = q.started_at)
            order by q.started_at loop
    begin
      continue when public.fn_it_playbook_first(f.issue_key, f.started_at);
      perform public.fn_it_loop_open(f.issue_key);
      n_open := n_open + 1;
    exception when others then
      v_err := v_err || jsonb_build_object('step', 'open', 'issue_key', f.issue_key, 'error', sqlerrm);
    end;
  end loop;
  o := o || jsonb_build_object('opened', n_open);

  begin o := o || jsonb_build_object('reverify', public.fn_it_loop_reverify());
  exception when others then v_err := v_err || jsonb_build_object('step', 'reverify', 'error', sqlerrm); end;
  begin
    x := public.fn_originators_reverify_handoffs();
    o := o || jsonb_build_object('originators', x);
    if jsonb_array_length(coalesce(x->'errors', '[]'::jsonb)) > 0 then
      v_err := v_err || jsonb_build_object('step', 'originators', 'error', left((x->'errors')::text, 600));
    end if;
  exception when others then v_err := v_err || jsonb_build_object('step', 'originators', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('ceo', public.fn_ceo_it_reports_sweep());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo', 'error', sqlerrm); end;
  begin
    x := public.fn_ceo_sales_engineer_reports_sweep();
    o := o || jsonb_build_object('ceo_sales', x, 'sales_engineer_completed', public.fn_sales_engineer_reports_complete());
    if jsonb_array_length(coalesce(x->'errors', '[]'::jsonb)) > 0 then
      v_err := v_err || jsonb_build_object('step', 'ceo_sales', 'error', left((x->'errors')::text, 600));
    end if;
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo_sales', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('ceo_accountant', public.fn_ceo_accountant_reports_sweep(),
                                     'accountant_completed', public.fn_accountant_reports_complete());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo_accountant', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('ceo_silence', public.fn_it_ceo_silence_watch());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo_silence', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('daily', public.fn_it_daily_line());
  exception when others then v_err := v_err || jsonb_build_object('step', 'daily', 'error', sqlerrm); end;
  -- Last, so everything this tick escalated leaves in the one message.
  begin o := o || jsonb_build_object('digest', public.fn_customer_support_sends_the_it_digest());
  exception when others then v_err := v_err || jsonb_build_object('step', 'digest', 'error', sqlerrm); end;

  foreach v_step in array array['open', 'reverify', 'originators', 'ceo', 'ceo_sales', 'ceo_accountant', 'ceo_silence', 'daily', 'digest'] loop
    perform public.fn_it_loop_stage(v_step,
      (select string_agg(coalesce(e->>'issue_key' || ': ', '') || (e->>'error'), '; ')
         from jsonb_array_elements(v_err) e where e->>'step' = v_step));
  end loop;
  return o || jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'errors', v_err);
end $fn$;
revoke execute on function public.fn_it_loop_tick() from public, anon, authenticated;

-- ── 8. NO APPROVAL EMAILS THE FOUNDER ───────────────────────────────────────────────────────────
-- All approvals, refunds included, are the CEO's (founder, 8 Sep 2026). These three still said the
-- founder decides. The routines that name them (fn_event_dispatch, fn_action_invoke_dispatch,
-- fn_ea_agenda, fn_company_self_knowledge_sync) now get a refusal from the policy, not a send.
do $mail$
declare n int;
begin
  update public.founder_mail_policy
     set allowed_to_email = false, owner_role = 'ceo', updated_at = now(),
         reason = 'Retired 15 Sep 2026 (ceo): all approvals, refunds included, are the CEO''s (founder, 8 Sep 2026), so this never emails him. Was: ' || reason
   where kind in ('refund_approval', 'refund_decision', 'spend_approval_needed') and allowed_to_email;
  get diagnostics n = row_count;
  if n not in (0, 3) then raise exception 'expected the 3 approval kinds to be switched off together, switched %', n; end if;

  update public.founder_mail_policy p
     set owner_role = v.seat, updated_at = now(),
         reason = p.reason || ' [owner ' || v.seat || ' from 15 Sep 2026: ' || v.why || ']'
    from (values
      ('customer_escalation', 'customer_support', 'a customer escalation is support''s to resolve'),
      ('customer_welcome',    'sales_engineer',   'the portal welcome is the portal''s voice'),
      ('refund_complaint',    'sales_engineer',   'the sales engineer runs the supplier follow-up ladder'),
      ('rfq_sla_breach',      'sales_engineer',   'an RFQ past its SLA is the matching seat''s to chase')
    ) v(kind, seat, why)
   where p.kind = v.kind and p.owner_role is distinct from v.seat;
end
$mail$;

-- ── 9. EVERY FUNCTION NAMES THE SEAT THAT ANSWERS FOR IT ─────────────────────────────────────────
-- fn_it_loop_open hands a finding to function_owner.owner; a 'website' owner is no seat, so every
-- finding on these 18 fell to the CEO. The functions stay deployed; each now names its seat.
-- Homepage and site pages: customer_support (the homepage is support's surface). Either portal, its
-- sign-in and its access rules: sales_engineer. The terms: ceo. Outbound SMS: customer_support, the
-- only sender. The heartbeat: it_engineer.
do $owners$
declare n int;
begin
  update public.function_owner o
     set owner = v.seat, note = o.note || ' Owner ' || v.seat || ' from 15 Sep 2026: ' || v.why || '.'
    from (values
      ('about',             'customer_support', 'a public page on the homepage surface'),
      ('faq',               'customer_support', 'a public page on the homepage surface'),
      ('home',              'customer_support', 'the homepage is support''s surface'),
      ('home-ar',           'customer_support', 'the homepage is support''s surface'),
      ('i18n_get',          'customer_support', 'serves the site''s strings'),
      ('public_stats',      'customer_support', 'the numbers on the public pages'),
      ('contact_submit',    'customer_support', 'the contact form is support''s own notice'),
      ('send_sms',          'customer_support', 'customer_support is the only sender on every channel'),
      ('legal',             'ceo',              'the terms and policies are the CEO''s'),
      ('portal',            'sales_engineer',   'either portal is the sales engineer''s'),
      ('auth_api',          'sales_engineer',   'portal sessions and accounts'),
      ('login_otp',         'sales_engineer',   'portal sign-in'),
      ('mobile_otp',        'sales_engineer',   'portal sign-in'),
      ('voice_otp',         'sales_engineer',   'portal sign-in'),
      ('voice_otp_capture', 'sales_engineer',   'portal sign-in'),
      ('role_guard',        'sales_engineer',   'decides what a portal identity may see'),
      ('sup_dob',           'sales_engineer',   'supplier verification is the sales engineer''s'),
      ('resilience_ping',   'it_engineer',      'the heartbeat that runs the IT engineer''s detectors and loop')
    ) v(slug, seat, why)
   where o.function_slug = v.slug and o.owner = 'website';
  get diagnostics n = row_count;
  if exists (select 1 from public.function_owner where owner = 'website') then
    raise exception 'function_owner still has website rows after reassigning %: %', n,
      (select string_agg(function_slug, ', ') from public.function_owner where owner = 'website');
  end if;
end
$owners$;

-- ── 10. EVERY KIND OF WORK NAMES A SEAT WITH AUTHORITY OVER IT ──────────────────────────────────
-- fn_agent_action_work_sweep routes officer and notify kinds to authority_role, and the OS boards read
-- it through fn_action_holder. Six roles here were retired and 15 kinds had none. Approvals are the
-- CEO's, money is the accountant's, the platform is the IT engineer's.
do $authority$
begin
  update public.agent_action_kind_policy p set authority_role = v.seat
    from (values
      ('ai_improvement',           'it_engineer'),
      ('autonomy_stall',           'it_engineer'),
      ('backup_alert',             'it_engineer'),
      ('incident',                 'it_engineer'),
      ('security_incident',        'it_engineer'),
      ('finance_alert',            'accountant'),
      ('customer_escalation',      'customer_support'),
      ('coverage_gap',             'sales_engineer'),
      ('decision.route_category',  'sales_engineer'),
      ('supply_health',            'sales_engineer'),
      ('compliance_update',        'ceo'),
      ('legal_flag',               'ceo'),
      ('finance_marketing_budget', 'ceo'),
      ('prompt_approval',          'ceo'),
      ('simulation_apply',         'ceo'),
      ('doc_task',                 'ceo'),
      ('handoff',                  'ceo'),
      ('improvement_question',     'ceo'),
      ('knowledge_task',           'ceo'),
      ('marketing_recommendation', 'ceo'),
      ('objective_step',           'ceo'),
      ('ops_recommendation',       'ceo'),
      ('report_recommendation',    'ceo'),
      ('report_task',              'ceo'),
      ('strategy_rec',             'ceo')
    ) v(kind, seat)
   where p.kind = v.kind;
  if exists (select 1 from public.agent_action_kind_policy
              where authority_role is null or authority_role not in ('ceo', 'customer_support', 'sales_engineer', 'accountant', 'it_engineer')) then
    raise exception 'agent_action_kind_policy still names no seat for: %',
      (select string_agg(kind, ', ') from public.agent_action_kind_policy
        where authority_role is null or authority_role not in ('ceo', 'customer_support', 'sales_engineer', 'accountant', 'it_engineer'));
  end if;
end
$authority$;

-- ── 11. THE IT ENGINEER'S ROLE SAYS WHAT IT DOES ────────────────────────────────────────────────
update public.org_agents
   set role = 'IT Engineer AI -- monitors everything in the app and the website, diagnoses what it finds, hands each fault to the seat that owns it and re-verifies before it closes. Reports to the CEO (support_ceo_report, it_engineer -> ceo); the founder is emailed only for a new bug no seat could fix (it_new_bug).'
 where agent_key = 'it_engineer' and role is distinct from 'IT Engineer AI -- monitors everything in the app and the website, diagnoses what it finds, hands each fault to the seat that owns it and re-verifies before it closes. Reports to the CEO (support_ceo_report, it_engineer -> ceo); the founder is emailed only for a new bug no seat could fix (it_new_bug).';

-- ── 12. PROOF, ON ZZ DEMO ROWS THAT CANNOT REACH ANYONE ─────────────────────────────────────────
-- This file defines routines, so each probe removes its own rows, asserts they are gone and ends in a
-- notice. The probes call the one-report routines and the one-report completion, never a sweep, so no
-- real report or handoff is touched here.
do $probe_decide$
declare v_req bigint; v_rep bigint; v jsonb; r public.support_ceo_report; v_h int; v_left int;
begin
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('customer_support', 'handoff', 'done', 'low', 'ZZ DEMO ceo report probe',
          jsonb_build_object('type', 'delivery.request', 'from', 'sales_engineer', 'to', 'customer_support', 'recipient_role', 'customer',
                             'msg_type', 'zz_demo_probe', 'to_email', 'zz-demo-ceo-probe@example.invalid'),
          'notifications', 'delivery.request:zz_demo_ceo_probe:' || txid_current())
  returning id into v_req;
  insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions,
                                         requested_outcome, owner_role_id, next_review_at)
  values ('delivery_undelivered:' || v_req, 'sales_engineer', 'elevated', 'A zz_demo_probe for the customer did not arrive (not_sent)',
          jsonb_build_object('request_id', v_req, 'result', 'not_sent'), '[]'::jsonb, 'ZZ DEMO probe: decide.', 'sales_engineer', now() + interval '1 day')
  returning id into v_rep;

  v := public.fn_ceo_sales_engineer_report_decide(v_rep);
  perform public.fn_sales_engineer_reports_complete(v_rep);
  select * into r from public.support_ceo_report where id = v_rep;
  select count(*) into v_h from public.agent_actions where kind = 'handoff' and target_id = 'delivery.remediate:' || v_rep;

  delete from public.support_ceo_report where id = v_rep;
  delete from public.agent_actions where id = v_req;
  select (select count(*) from public.support_ceo_report where id = v_rep) + (select count(*) from public.agent_actions where id = v_req) into v_left;
  if v->>'decision' is distinct from 'need_not_go_fixture' or r.status is distinct from 'completed'
     or r.acceptance_receipt not ilike '%ZZ DEMO%' or v_h <> 0 or v_left <> 0 then
    raise exception 'CEO decision probe failed: decision=%, status=%, receipt=%, remediations=%, rows left=%',
      v->>'decision', r.status, r.acceptance_receipt, v_h, v_left;
  end if;
  raise notice 'the CEO decided a ZZ DEMO report "need not go" with a receipt, the sales engineer completed it, nothing was handed on; probe rows removed.';
end
$probe_decide$;

do $probe_accountant$
declare v_h bigint; v_rep bigint; v jsonb; r public.support_ceo_report; v_left int;
begin
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('sales_engineer', 'handoff', 'failed', 'low', 'ZZ DEMO accountant notice probe',
          jsonb_build_object('type', 'payment.received', 'from', 'accountant', 'to', 'sales_engineer', 'kind', 'ZZ DEMO probe'),
          'leads', 'payment.received:zz_demo_probe:' || txid_current())
  returning id into v_h;
  insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions,
                                         requested_outcome, owner_role_id, next_review_at)
  values ('notice_undelivered:' || v_h, 'accountant', 'elevated', 'ZZ DEMO probe notice was not sent',
          jsonb_build_object('handoff_id', v_h), '[]'::jsonb, 'ZZ DEMO probe: decide.', 'accountant', now() + interval '1 day')
  returning id into v_rep;

  v := public.fn_ceo_accountant_notice_report_decide(v_rep);
  select * into r from public.support_ceo_report where id = v_rep;

  delete from public.support_ceo_report where id = v_rep;
  delete from public.agent_actions where id = v_h;
  select (select count(*) from public.support_ceo_report where id = v_rep) + (select count(*) from public.agent_actions where id = v_h) into v_left;
  if v->>'decision' is distinct from 'need_not_go_fixture' or r.status is distinct from 'accepted' or v_left <> 0 then
    raise exception 'accountant notice probe failed: decision=%, status=%, rows left=%', v->>'decision', r.status, v_left;
  end if;
  raise notice 'the CEO decided a ZZ DEMO accountant notice escalation with a receipt and raised nothing; probe rows removed.';
end
$probe_accountant$;

do $probe_close$
declare v_id bigint; v_refused boolean := false; v_status text; v_left int;
begin
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('accountant', 'handoff', 'pending', 'low', 'ZZ DEMO originator probe',
          jsonb_build_object('type', 'billing.question', 'from', 'sales_engineer', 'to', 'accountant', 'party', 'customer', 'replied_at', now()),
          'agent_actions', 'billing.question:zz_demo_probe:' || txid_current())
  returning id into v_id;
  begin
    perform set_config('qd.handoff_closer', 'accountant', true);
    update public.agent_actions set status = 'done' where id = v_id;
  exception when others then v_refused := true; end;
  perform set_config('qd.handoff_closer', 'sales_engineer', true);
  update public.agent_actions set status = 'done' where id = v_id;
  perform set_config('qd.handoff_closer', '', true);
  select status into v_status from public.agent_actions where id = v_id;
  delete from public.agent_actions where id = v_id;
  select count(*) into v_left from public.agent_actions where id = v_id;
  if not v_refused or v_status <> 'done' or v_left <> 0 then
    raise exception 'originator probe failed: receiver close refused=%, originator close=%, rows left=%', v_refused, v_status, v_left;
  end if;
  raise notice 'z61 refused the accountant''s close of a billing.question and accepted the sales engineer''s; probe row removed.';
end
$probe_close$;

do $probe_remediate$
declare v_req bigint; v_h bigint; v jsonb; v_sent int; v_left int;
begin
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('customer_support', 'handoff', 'done', 'low', 'ZZ DEMO remediation probe request',
          jsonb_build_object('type', 'delivery.request', 'from', 'sales_engineer', 'to', 'customer_support', 'recipient_role', 'customer',
                             'msg_type', 'zz_demo_probe', 'to_email', 'zz-demo-remediate-probe@example.invalid',
                             'subject_en', 'ZZ DEMO', 'body_en', 'ZZ DEMO probe body'),
          'notifications', 'delivery.request:zz_demo_remediate_probe:' || txid_current())
  returning id into v_req;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('sales_engineer', 'handoff', 'pending', 'low', 'ZZ DEMO remediation probe',
          jsonb_build_object('type', 'delivery.remediate', 'from', 'ceo', 'to', 'sales_engineer', 'request_id', v_req),
          'support_ceo_report', 'delivery.remediate:zz_demo_probe:' || txid_current())
  returning id into v_h;

  v := public.fn_sales_engineer_answers_delivery_remediate(v_h);
  select count(*) into v_sent from public.agent_actions where kind = 'handoff' and target_id = 'delivery.request:remediate:' || v_h;

  delete from public.agent_actions where id in (v_h, v_req);
  select count(*) into v_left from public.agent_actions where id in (v_h, v_req);
  if (v->>'resend_request_id') is not null or v_sent <> 0 or v->>'reply' not ilike '%ZZ DEMO%' or v_left <> 0 then
    raise exception 'remediation probe failed: reply=%, resends=%, rows left=%', v, v_sent, v_left;
  end if;
  raise notice 'the sales engineer refused to resend a ZZ DEMO notice and said so; probe rows removed.';
end
$probe_remediate$;
