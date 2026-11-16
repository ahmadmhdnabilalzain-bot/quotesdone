-- A PERSON'S TIMELINE JOINS ONLY THEIR OWN NUMBER, AND SHOWS AN ATTEMPT TO INSTRUCT THE ASSISTANT.
--
-- Seat: it_engineer for customer_support (wave 3 OPS builder, 16 Nov 2026).
-- 1. THE NUMBER (REVIEW_waveC follow-up 1). fn_contact_timeline found a person's customers and leads by the bare last nine
--    digits of a number, so +971 50 123 4567 and +44 7501 234567 (same tail, two countries, two people) read ONE timeline,
--    and every door that shows "this sender's case" could show one person another's requests, quotes and messages. Now the
--    country prefix must agree as well, the rule fn_whatsapp_owner adopted (a_phone_tail_never_joins_two_people.sql;
--    PROFILE_SPLIT item 2): a number written in a local form names no country and agrees with any. Applied to every
--    tail match in the routine: customers, leads (phone_e164, phone, whatsapp), messages sent, WhatsApp turns, the contact form.
--    The fault branch already reads a support profile only within its country.
-- 2. THE ATTEMPT. Each attempt the model read as trying to instruct the assistant (public.injection_attempt, written by
--    fn_injection_attempt_record) is an event of this person's timeline, so every colleague who answers them next knows.
-- Base: production's body (md5 5b6db75a7a02e3fcacaf6023c03a4fef, read 16 Nov 2026); only the two changes above.
-- Order: after an_attempt_to_instruct_the_assistant_is_on_the_senders_record_and_a_repeat_reaches_the_it_engineer.sql.
-- Probe: a_persons_timeline_joins_only_their_own_number_and_shows_an_attempt_to_instruct_the_assistant_probe.sql
-- Rollback: re-apply production's body (above md5).
set local lock_timeout = '3s';

create or replace function public.fn_contact_timeline(p_contact text, p_limit integer default 60)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_raw text := btrim(coalesce(p_contact, ''));
  v_email text; v_tail text; v_prefix text;
  v_cust uuid[]; v_lead bigint[]; v_inq uuid[]; v_txn uuid[]; v_ref bigint[];
  v_events jsonb; v_counts jsonb; v_faults text[];
begin
  v_raw := regexp_replace(v_raw, '^whatsapp:', '', 'i');
  if position('@' in v_raw) > 0 then
    v_email := lower(v_raw);
  elsif length(regexp_replace(v_raw, '[^0-9]', '', 'g')) >= 7 then
    v_tail := right(regexp_replace(v_raw, '[^0-9]', '', 'g'), 9);   -- +9715..., 05..., 5...
    -- THE COUNTRY PREFIX MUST AGREE AS WELL AS THE LAST NINE DIGITS (16 Nov 2026, the rule fn_whatsapp_owner adopted in
    -- a_phone_tail_never_joins_two_people.sql): +971 50 123 4567 and +44 7501 234567 share a tail and are two people. A number
    -- written in a local form names no country (fn_phone_prefix null) and agrees with any, as there.
    v_prefix := public.fn_phone_prefix(v_raw);
  else
    return jsonb_build_object('contact', v_raw, 'known', false, 'event_count', 0, 'events', '[]'::jsonb);
  end if;

  select coalesce(array_agg(c.id), '{}') into v_cust from public.customers c
   where (v_email is not null and lower(c.email) = v_email)
      or (v_tail is not null and right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail
          and coalesce(public.fn_phone_prefix(c.phone) = v_prefix, true));
  select coalesce(array_agg(l.id), '{}') into v_lead from public.leads l
   where (v_email is not null and (lower(l.email) = v_email or lower(l.claimed_by) = v_email))
      or (v_tail is not null and exists (select 1 from unnest(array[l.phone_e164, l.phone, l.whatsapp]) n(num)
                                          where right(regexp_replace(coalesce(n.num, ''), '[^0-9]', '', 'g'), 9) = v_tail
                                            and coalesce(public.fn_phone_prefix(n.num) = v_prefix, true)));
  select coalesce(array_agg(i.id), '{}') into v_inq from public.inquiries i where i.customer_id = any (v_cust);
  select coalesce(array_agg(t.id), '{}') into v_txn from public.transactions t
   where t.customer_id = any (v_cust) or t.supplier_id = any (v_lead);
  select coalesce(array_agg(r.id), '{}') into v_ref from public.refunds r
   where r.customer_id = any (v_cust) or r.supplier_lead_id = any (v_lead) or r.transaction_id = any (v_txn);
  -- THE FAULTS THIS PERSON TOLD SUPPORT ABOUT, ON ANY CHANNEL (every_door_and_the_ceo_read_the_same_case.sql): the keys support
  -- wrote into their case's linked_refs when it handed the fault over (fn_support_case_links_a_fault; a WhatsApp report carries
  -- no identity of its own), and the reports filed with their e-mail's lead or customer. Read through every support profile that
  -- is theirs, the way fn_support_profile_resolve matches one (customer, lead, e-mail; a number only an unnamed handset profile), and never creating one.
  select coalesce(array_agg(distinct k), '{}') into v_faults from (
    select f ->> 'issue_key' as k
      from public.support_case s
      join public.support_customer_profile p on p.id = s.customer_profile_id
     cross join lateral jsonb_array_elements(case when jsonb_typeof(s.linked_refs -> 'faults') = 'array' then s.linked_refs -> 'faults' else '[]'::jsonb end) f
     where p.customer_id = any (v_cust) or p.lead_id = any (v_lead)
        or (v_email is not null and p.email = v_email)
        -- a number reaches only an unnamed handset profile of the same country (a_phone_tail_never_joins_two_people.sql)
        or (v_tail is not null and p.phone_tail = v_tail and p.customer_id is null and p.lead_id is null and p.email is null
            and (p.phone_prefix is null or public.fn_phone_prefix(v_raw) is null or p.phone_prefix = public.fn_phone_prefix(v_raw)))
    union all
    select r.issue_key from public.support_fault_report r where r.customer_id = any (v_cust) or r.lead_id = any (v_lead)) z
   where k like 'support:fault:%';

  with ev(at, kind, channel, direction, seat, ref, summary) as (
    -- what they asked for
    select i.created_at, 'request', 'portal', 'in', 'sales_engineer', i.id::text,
           coalesce(i.status, '') || ': ' || left(coalesce(i.summary_masked, i.summary, i.category, ''), 140)
      from public.inquiries i where i.id = any (v_inq)
    -- quotes on their requests: state only, never a supplier or an amount (the pre-reveal rule)
    union all
    select q.created_at, 'quote', 'portal', 'in', 'sales_engineer', q.id::text,
           case when exists (select 1 from public.transactions t where t.quote_id = q.id and t.revealed_at is not null)
                then 'released (revealed)' else 'held (' || coalesce(q.status, 'received') || ')' end
      from public.quotes q where q.inquiry_id = any (v_inq)
    -- quotes they submitted, when the contact is a supplier
    union all
    select q.created_at, 'quote_submitted', 'portal', 'out', 'sales_engineer', q.id::text, coalesce(q.status, 'submitted')
      from public.quotes q where q.supplier_id = any (v_lead)
    -- reveals and what was paid
    union all
    select t.revealed_at, 'reveal', 'portal', 'out', 'accountant', t.id::text, 'fee ' || coalesce(t.fee_status, 'unknown')
      from public.transactions t where t.id = any (v_txn) and t.revealed_at is not null
    union all
    select ri.created_at, 'invoice', 'portal', 'out', 'accountant', ri.invoice_no, 'reveal invoice issued'
      from public.reveal_invoices ri where ri.transaction_id = any (v_txn)
    -- refunds, and the CEO's decision on each (the refund loop)
    union all
    select coalesce(r.updated_at, r.created_at), 'refund', 'portal', 'out', 'accountant', r.id::text,
           coalesce(r.status, '') || coalesce(' — ' || r.reason_code, '')
      from public.refunds r where r.id = any (v_ref)
    union all
    select coalesce(rc.updated_at, rc.created_at), 'refund_case', 'internal', 'internal', 'accountant', rc.case_id::text,
           coalesce(rc.state, '') || coalesce(' — ' || rc.decision, '')
      from public.refund_case rc where rc.refund_id = any (v_ref)
    union all
    select a.decided_at, 'ceo_decision', 'internal', 'internal', 'ceo', a.decision_id::text,
           coalesce(a.subject_kind, '') || ': ' || coalesce(a.decision, '')
      from public.ceo_approval a where a.subject_kind ilike 'refund%' and a.subject_id = any (v_ref::text[])
    -- support cases
    union all
    select coalesce(s.last_activity_at, s.opened_at), 'support_case', 'internal', 'internal',
           coalesce(s.owner_role_id, 'customer_support'), s.case_ref, coalesce(s.state, '') || ': ' || left(coalesce(s.subject, ''), 120)
      from public.support_case s
     where (s.party_kind = 'customer' and s.party_id = any (v_cust::text[]))
        or (s.party_kind = 'supplier' and s.party_id = any (v_lead::text[]))
    -- a fault they reported, one event per fault, with where its repair stands: fixed (and whether they were told) or still with
    -- the IT engineer, so "is it fixed?" on another channel is answered from the record. Never their words: the turns stay with IT.
    union all
    select greatest(f.last_reported, f.told_at), 'it_fault', f.channel, 'internal', 'it_engineer', f.issue_key,
           case when f.fixed then 'fixed' || coalesce(': ' || left(f.observed, 100), '')
                                 || case when f.told like 'no_email%' then ' (not told: we hold no address for them)' else ' (they were told)' end
                else 'open: reported on ' || f.channel || ' ' || to_char(f.first_reported at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
                     || ', with the IT engineer, not fixed yet' || coalesce(' (hand-over ' || h.status || ')', '') end
      from (select r.issue_key, min(r.reported_at) as first_reported, max(r.reported_at) as last_reported, max(r.told_at) as told_at,
                   bool_and(r.told_at is not null) as fixed, (array_agg(r.channel order by r.id))[1] as channel,
                   (array_agg(r.fixed_observed order by r.id desc))[1] as observed, (array_agg(r.told order by r.id desc))[1] as told,
                   (array_agg(r.handoff_id order by r.id desc))[1] as handoff_id
              from public.support_fault_report r where r.issue_key = any (v_faults) group by r.issue_key) f
      left join public.agent_actions h on h.id = f.handoff_id
    -- every message the company sent them, and the seat that asked for it
    union all
    select n.created_at, 'message', coalesce(n.channel, 'email'), 'out', coalesce(n.requested_by, 'customer_support'),
           n.id::text, coalesce(n.status, 'queued') || ': ' || left(coalesce(n.subject, n.type, ''), 140)
      from public.notifications n
     where (v_email is not null and lower(n.to_email) = v_email)
        or (v_tail is not null and right(regexp_replace(coalesce(n.to_phone, ''), '[^0-9]', '', 'g'), 9) = v_tail
            and coalesce(public.fn_phone_prefix(n.to_phone) = v_prefix, true))
        or n.lead_id = any (v_lead) or n.inquiry_id = any (v_inq)
    -- every message they sent the company
    union all
    select m.created_at, 'message', 'email', 'in', 'customer_support', m.id::text, left(coalesce(m.subject, ''), 140)
      from public.inbound_messages m
     where (v_email is not null and lower(m.from_email) = v_email) or m.lead_id = any (v_lead)
    union all
    select w.at, 'message', 'whatsapp', w.direction, 'customer_support', w.id::text, left(coalesce(w.transcript, w.body, ''), 140)
      from public.wa_turn w join public.wa_conversation c on c.id = w.conversation_id
     where (v_tail is not null and right(regexp_replace(coalesce(c.phone_e164, ''), '[^0-9]', '', 'g'), 9) = v_tail
            and coalesce(public.fn_phone_prefix(c.phone_e164) = v_prefix, true))
        or (c.party_kind = 'customer' and c.party_id = any (v_cust::text[]))
        or (c.party_kind = 'supplier' and c.party_id = any (v_lead::text[]))
    union all
    select pm.created_at, 'message', 'portal_chat', case when pm.customer_id = any (v_cust) and pm.sender = 'customer' then 'in' else 'out' end,
           'sales_engineer', pm.id::text, left(coalesce(pm.redacted_body, ''), 140)
      from public.messages pm where pm.customer_id = any (v_cust) or pm.supplier_id = any (v_lead)
    -- every handoff between the seats about this party (payments_are_the_accountant_and_it_talks_to_the_
    -- sales_engineer.sql): who handed what to whom, and where it stands, so support reads the money and
    -- the refund loops before it answers — #617's branch, kept here verbatim so the live body is the union
    union all
    select a.created_at, 'handoff', 'internal', 'internal', a.agent, a.id::text,
           coalesce(a.detail->>'type', a.kind) || ' from ' || coalesce(a.detail->>'from', '?') || ' to ' || a.agent || ': ' || a.status
      from public.agent_actions a
     where a.kind = 'handoff'
       and ((a.detail->>'customer_id') = any (v_cust::text[]) or (a.detail->>'supplier_id') = any (v_lead::text[])
            or (a.detail->>'transaction_id') = any (v_txn::text[]) or (a.detail->>'refund_id') = any (v_ref::text[]))
    union all
    select cm.created_at, 'message', 'contact_form', 'in', 'customer_support', cm.id::text, left(coalesce(cm.message, ''), 140)
      from public.contact_messages cm
     where (v_email is not null and lower(cm.email) = v_email)
        or (v_tail is not null and right(regexp_replace(coalesce(cm.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail
            and coalesce(public.fn_phone_prefix(cm.phone) = v_prefix, true))
    -- WHAT THEY TRIED TO MAKE THE ASSISTANT DO (16 Nov 2026, an_attempt_to_instruct_the_assistant_is_on_the_senders_record_and_a_
    -- repeat_reaches_the_it_engineer.sql): the model's own reading of each attempt, on this person's record, so a colleague who
    -- answers them next knows. Nothing was blocked; the it_engineer holds one case per sender from the second attempt.
    union all
    select ia.at, 'injection_attempt', ia.channel, 'in', 'it_engineer', ia.id::text,
           left('tried to instruct the assistant' || coalesce(nullif(': ' || ia.reading, ': '), ''), 140)
      from public.injection_attempt ia
     where ia.customer_id = any (v_cust) or ia.lead_id = any (v_lead)
        or (v_email is not null and ia.email = v_email)
        or (v_tail is not null and ia.phone_tail = v_tail and (ia.phone_prefix is null or v_prefix is null or ia.phone_prefix = v_prefix))
    -- the sales engineer's record of this supplier's collaboration: holds left unanswered at a
    -- decision, resets, the warning, the matching hold and its lifting (founder, 14 Sep 2026)
    union all
    select e.created_at, 'collaboration', 'internal', 'internal', e.actor, e.id::text,
           e.kind || ' — ' || e.consecutive_after || ' in a row' || coalesce(' — RFQ ' || upper(left(e.inquiry_id::text, 8)), '')
      from public.supplier_collaboration_event e where e.lead_id = any (v_lead)
  )
  select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'kind', e.kind, 'channel', e.channel, 'direction', e.direction,
                                               'seat', e.seat, 'ref', e.ref, 'summary', e.summary) order by e.at desc), '[]'::jsonb)
    into v_events
    from (select * from ev where at is not null order by at desc limit greatest(1, least(coalesce(p_limit, 60), 500))) e;

  select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) into v_counts
    from (select x ->> 'kind' k, count(*) n from jsonb_array_elements(v_events) x group by 1) z;

  return jsonb_build_object(
    'contact', coalesce(v_email, v_tail),
    'known', cardinality(v_cust) + cardinality(v_lead) > 0,
    'customer_ids', to_jsonb(v_cust), 'supplier_lead_ids', to_jsonb(v_lead),
    'event_count', jsonb_array_length(v_events), 'counts', v_counts,
    'events', v_events,
    'assembled_by', 'fn_contact_timeline (deterministic; no model)');
end $function$;
revoke execute on function public.fn_contact_timeline(text, integer) from public, anon, authenticated;
