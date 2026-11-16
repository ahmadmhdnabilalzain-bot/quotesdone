-- EVERY DOOR AND THE CEO READ THE SAME CASE: A FAULT AND A PROMISE ARE ON THE PERSON'S RECORD, NOT ON ONE CONVERSATION.
-- Seat: sales_engineer (the intake door; agent "sales_engineer builder (every door reads the same case)"), for customer_support
-- (the case and the fault hand-over) and ceo (the refund decision). Founder ledgers 1711-1713 (16 Nov 2026): "everyone knows what
-- the other is doing because they are colleagues in the same company". Audit SP/audit/WHO_KNOWS_WHAT.md items 1, 8 and 9.
--
-- MEASURED BEFORE WRITING (16 Nov 2026; light production SELECTs, counts only): support_case 30 rows, linked_refs used by 0;
-- support_case_promise 0 rows; support_fault_report and fn_support_hands_it_a_fault live (applied 16 Nov). fn_contact_timeline
-- here is the live body (md5 73240acc of pg_get_functiondef, equal to the schema mirror) plus ONE branch; fn_ceo_refund_checklist
-- is the live body (the mirror, canonical file the_nonresponse_charge_is_the_maximum_uae_law_safely_allows.sql) plus ONE item.
--
-- WHAT THIS FILE DOES:
--   1. fn_person_open_promises(kind, party id, e-mail, phone, limit): the promises still open on every case of every support
--      profile that is this person's (matched the way fn_support_profile_resolve matches: customer, lead, e-mail, phone tail).
--      A read: it never creates a profile. The intake chat gives it to its prompt (inquiry_intake/customer_record.ts), and the
--      CEO's refund checklist records it (item 1b below).
--   2. fn_support_case_links_a_fault(kind, party id, e-mail, phone, issue key, channel): when support hands a fault to the IT
--      engineer (_shared/support_fault_handover.ts), the fault's key is written into the person's newest open case's
--      linked_refs.faults (their newest case when none is open). A WhatsApp report carries no identity of its own (its case key
--      is a hash of the number), so this is how another door finds it. Only a key that names a filed report is linked.
--   3. fn_contact_timeline: one more branch, 'it_fault': every fault on the person's cases or filed under their lead or
--      customer, with where its repair stands (fixed, and whether they were told; or open, with the IT engineer). Every door
--      that reads the timeline (WhatsApp, the signed-in widget, the e-mail classifier, the CEO) now sees it.
--   4. fn_ceo_refund_checklist: item 1b, information like item 1: his timeline since the reveal and his open promises, so the
--      CEO decides knowing what support told and promised him. It never changes a pass or a fail.
--
-- Every new routine: SECURITY DEFINER, search_path pinned, EXECUTE revoked from public, anon and authenticated, granted to
-- service_role. The two replaced routines keep their ACL (CREATE OR REPLACE) and are revoked again by signature.
-- Probe: every_door_and_the_ceo_read_the_same_case_probe.sql (local Postgres 16 from the mirror, twice).
-- Prevented by: supabase/functions/_shared/support_fault_handover.test.ts (the link is asked with the person, never without),
--   supabase/functions/inquiry_intake/the_intake_reads_his_whole_record.test.ts, and the probe.
--   node scripts/apply_sql.mjs scripts/sql/every_door_and_the_ceo_read_the_same_case.sql --apply --ddl --seat sales_engineer

-- ── 1. THE PROMISES STILL OPEN ON THIS PERSON'S CASES ───────────────────────────────────────────────────────────────
create or replace function public.fn_person_open_promises(p_party_kind text, p_party_id text, p_email text, p_phone text,
  p_limit integer default 10)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with who as (
    select case when p_party_kind = 'customer' and p_party_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then p_party_id::uuid end as cust,
           case when p_party_kind = 'supplier' and p_party_id ~ '^[0-9]{1,18}$' then p_party_id::bigint end as lead,
           nullif(lower(btrim(coalesce(p_email, ''))), '') as email,
           case when length(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')) >= 9
                then right(regexp_replace(p_phone, '[^0-9]', '', 'g'), 9) end as tail),
  prof as (
    select p.id from public.support_customer_profile p, who
     where (who.cust is not null and p.customer_id = who.cust) or (who.lead is not null and p.lead_id = who.lead)
        or (who.email is not null and p.email = who.email) or (who.tail is not null and p.phone_tail = who.tail))
  select coalesce(jsonb_agg(jsonb_build_object('case_ref', x.case_ref, 'what', x.what, 'due_at', x.due_at, 'due_basis', x.due_basis,
                                               'owner_seat', x.owner_seat, 'kind', x.kind, 'overdue', x.due_at < now(), 'made_at', x.created_at)
                            order by x.due_at), '[]'::jsonb)
    from (select pr.* from public.support_case_promise pr join public.support_case c on c.case_id = pr.case_id
           where pr.status = 'open' and c.state <> 'closed' and c.customer_profile_id in (select id from prof)
           order by pr.due_at limit greatest(1, least(coalesce(p_limit, 10), 50))) x
$fn$;
revoke execute on function public.fn_person_open_promises(text, text, text, text, integer) from public, anon, authenticated;
grant execute on function public.fn_person_open_promises(text, text, text, text, integer) to service_role;

-- ── 2. A FAULT SUPPORT HANDED OVER IS WRITTEN ONTO THE PERSON'S CASE ────────────────────────────────────────────────
create or replace function public.fn_support_case_links_a_fault(p_party_kind text, p_party_id text, p_email text, p_phone text,
  p_issue_key text, p_channel text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_cust uuid; v_lead bigint; v_email text := nullif(lower(btrim(coalesce(p_email, ''))), ''); v_tail text; c public.support_case;
  v_entry jsonb;
begin
  if coalesce(p_issue_key, '') !~ '^support:fault:[0-9a-f]{16}$' then return jsonb_build_object('linked', false, 'reason', 'not a fault key'); end if;
  -- only a fault support really filed is linked: a caller cannot plant a status on someone's case
  if not exists (select 1 from public.support_fault_report r where r.issue_key = p_issue_key) then
    return jsonb_build_object('linked', false, 'reason', 'no filed report has this key');
  end if;
  if p_party_kind = 'customer' and p_party_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then v_cust := p_party_id::uuid; end if;
  if p_party_kind = 'supplier' and p_party_id ~ '^[0-9]{1,18}$' then v_lead := p_party_id::bigint; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+$' then v_email := null; end if;
  if length(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')) >= 9 then v_tail := right(regexp_replace(p_phone, '[^0-9]', '', 'g'), 9); end if;
  if v_cust is null and v_lead is null and v_email is null and v_tail is null then return jsonb_build_object('linked', false, 'reason', 'no identity'); end if;

  -- the newest open case of any profile that is theirs; their newest case when none is open (a read: no profile is created)
  select s.* into c from public.support_case s join public.support_customer_profile p on p.id = s.customer_profile_id
   where (v_cust is not null and p.customer_id = v_cust) or (v_lead is not null and p.lead_id = v_lead)
      or (v_email is not null and p.email = v_email) or (v_tail is not null and p.phone_tail = v_tail)
   order by (s.state <> 'closed') desc, s.last_activity_at desc, s.case_id desc
   limit 1
   for update of s;
  if c.case_id is null then return jsonb_build_object('linked', false, 'reason', 'the person has no case yet'); end if;

  if exists (select 1 from jsonb_array_elements(case when jsonb_typeof(c.linked_refs -> 'faults') = 'array' then c.linked_refs -> 'faults' else '[]'::jsonb end) f
              where f ->> 'issue_key' = p_issue_key) then
    return jsonb_build_object('linked', true, 'case_ref', c.case_ref, 'already', true);
  end if;
  v_entry := jsonb_build_object('issue_key', p_issue_key, 'channel', left(coalesce(p_channel, ''), 20), 'at', now());
  -- newest 20 faults are kept on one case; every other key of linked_refs is left as it is
  update public.support_case
     set linked_refs = jsonb_set(coalesce(linked_refs, '{}'::jsonb), '{faults}',
           (select coalesce(jsonb_agg(e order by n), '[]'::jsonb) from (
              select e, n from jsonb_array_elements(case when jsonb_typeof(linked_refs -> 'faults') = 'array' then linked_refs -> 'faults' else '[]'::jsonb end
                                                    || jsonb_build_array(v_entry)) with ordinality q(e, n)
               order by n desc limit 20) z), true)
   where case_id = c.case_id;
  return jsonb_build_object('linked', true, 'case_ref', c.case_ref);
end $fn$;
revoke execute on function public.fn_support_case_links_a_fault(text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_support_case_links_a_fault(text, text, text, text, text, text) to service_role;

-- ── 3. THE TIMELINE EVERY DOOR READS: THE LIVE BODY, PLUS THE 'it_fault' BRANCH ─────────────────────────────────────
create or replace function public.fn_contact_timeline(p_contact text, p_limit integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_raw text := btrim(coalesce(p_contact, ''));
  v_email text; v_tail text;
  v_cust uuid[]; v_lead bigint[]; v_inq uuid[]; v_txn uuid[]; v_ref bigint[];
  v_events jsonb; v_counts jsonb; v_faults text[];
begin
  v_raw := regexp_replace(v_raw, '^whatsapp:', '', 'i');
  if position('@' in v_raw) > 0 then
    v_email := lower(v_raw);
  elsif length(regexp_replace(v_raw, '[^0-9]', '', 'g')) >= 7 then
    v_tail := right(regexp_replace(v_raw, '[^0-9]', '', 'g'), 9);   -- +9715..., 05..., 5...
  else
    return jsonb_build_object('contact', v_raw, 'known', false, 'event_count', 0, 'events', '[]'::jsonb);
  end if;

  select coalesce(array_agg(c.id), '{}') into v_cust from public.customers c
   where (v_email is not null and lower(c.email) = v_email)
      or (v_tail is not null and right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail);
  select coalesce(array_agg(l.id), '{}') into v_lead from public.leads l
   where (v_email is not null and (lower(l.email) = v_email or lower(l.claimed_by) = v_email))
      or (v_tail is not null and v_tail in (right(regexp_replace(coalesce(l.phone_e164, ''), '[^0-9]', '', 'g'), 9),
                                            right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 9),
                                            right(regexp_replace(coalesce(l.whatsapp, ''), '[^0-9]', '', 'g'), 9)));
  select coalesce(array_agg(i.id), '{}') into v_inq from public.inquiries i where i.customer_id = any (v_cust);
  select coalesce(array_agg(t.id), '{}') into v_txn from public.transactions t
   where t.customer_id = any (v_cust) or t.supplier_id = any (v_lead);
  select coalesce(array_agg(r.id), '{}') into v_ref from public.refunds r
   where r.customer_id = any (v_cust) or r.supplier_lead_id = any (v_lead) or r.transaction_id = any (v_txn);
  -- THE FAULTS THIS PERSON TOLD SUPPORT ABOUT, ON ANY CHANNEL (every_door_and_the_ceo_read_the_same_case.sql): the keys support
  -- wrote into their case's linked_refs when it handed the fault over (fn_support_case_links_a_fault; a WhatsApp report carries
  -- no identity of its own), and the reports filed with their e-mail's lead or customer. Read through every support profile that
  -- is theirs, the way fn_support_profile_resolve matches one (customer, lead, e-mail, phone tail), and never creating one.
  select coalesce(array_agg(distinct k), '{}') into v_faults from (
    select f ->> 'issue_key' as k
      from public.support_case s
      join public.support_customer_profile p on p.id = s.customer_profile_id
     cross join lateral jsonb_array_elements(case when jsonb_typeof(s.linked_refs -> 'faults') = 'array' then s.linked_refs -> 'faults' else '[]'::jsonb end) f
     where p.customer_id = any (v_cust) or p.lead_id = any (v_lead)
        or (v_email is not null and p.email = v_email) or (v_tail is not null and p.phone_tail = v_tail)
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
        or (v_tail is not null and right(regexp_replace(coalesce(n.to_phone, ''), '[^0-9]', '', 'g'), 9) = v_tail)
        or n.lead_id = any (v_lead) or n.inquiry_id = any (v_inq)
    -- every message they sent the company
    union all
    select m.created_at, 'message', 'email', 'in', 'customer_support', m.id::text, left(coalesce(m.subject, ''), 140)
      from public.inbound_messages m
     where (v_email is not null and lower(m.from_email) = v_email) or m.lead_id = any (v_lead)
    union all
    select w.at, 'message', 'whatsapp', w.direction, 'customer_support', w.id::text, left(coalesce(w.transcript, w.body, ''), 140)
      from public.wa_turn w join public.wa_conversation c on c.id = w.conversation_id
     where (v_tail is not null and right(regexp_replace(coalesce(c.phone_e164, ''), '[^0-9]', '', 'g'), 9) = v_tail)
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
        or (v_tail is not null and right(regexp_replace(coalesce(cm.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail)
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

-- ── 4. THE CEO'S REFUND CHECKLIST: THE LIVE BODY, PLUS ITEM 1b ─────────────────────────────────────────────────────
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
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then
    return jsonb_build_object('ok', false, 'phase', p_phase, 'transaction_id', p_transaction_id,
      'failed', jsonb_build_array(jsonb_build_object('item', 'transaction_exists', 'passed', false, 'reason', 'no such transaction', 'remediable', false)));
  end if;
  select * into r from public.refunds where transaction_id = t.id and status not in ('rejected', 'cancelled', 'failed')
     and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by id desc limit 1;
  select lower(email) into v_cust from public.customers where id = t.customer_id;
  v_total := coalesce(t.total_charged, t.reveal_fee);
  v_reason := coalesce(r.reason_code, t.refund_reason, 'supplier_unresponsive');
  v_unresp := v_reason = 'supplier_unresponsive';
  select * into e_chase from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'chase' order by e.id desc limit 1;
  select * into e_final from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'final_call' order by e.id desc limit 1;

  if p_phase = 'approve' then
    v_rid := r.id;
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
      'passed', e_chase.id is not null and e_chase.delivered,
      'evidence', case when e_chase.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_chase.id, 'result', e_chase.result, 'delivered', e_chase.delivered, 'delivery', e_chase.evidence) end,
      'reason', case when e_chase.id is null then 'support has returned no result for a day-3 chase' else 'the day-3 chase was not delivered' end,
      'remedy', 'the sales engineer has support deliver the chase again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'chase', 'remediable', true, 'kind', 'process');
    v_items := v_items || jsonb_build_object('item', 'day5_final_call_happened',
      'passed', e_final.id is not null and e_final.delivered,
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
      'passed', v_proofs = 0 and not v_live
                and coalesce(e_chase.result, '') = 'no_response_confirmation' and coalesce(e_chase.delivered, false)
                and coalesce(e_final.result, '') = 'no_response_confirmation' and coalesce(e_final.delivered, false),
      'evidence', jsonb_build_object('proofs_of_response', v_proofs, 'latest_proof', v_proof_ev, 'responded_by_live_record', v_live,
                                     'chase_result', e_chase.result, 'final_call_result', e_final.result),
      'reason', case when v_proofs > 0 or v_live then 'the supplier responded' || coalesce(': ' || (v_proof_ev->'reply')::text, '')
                     else 'silence is not confirmed on both steps: a result is missing, or the delivery behind it failed' end,
      'remedy', 'the sales engineer has support make the final call again and return proof or a confirmed no-response',
      'owner', 'sales_engineer', 'remedy_key', 'final_call', 'remediable', v_proofs = 0 and not v_live, 'kind', 'process');

    -- 5. None of the exclusions in the signed terms applies.
    v_prior := exists (select 1 from public.transactions x where x.customer_id = t.customer_id and x.supplier_id = t.supplier_id
                         and x.id <> t.id and x.revealed_at < t.revealed_at);
    v_hired := exists (select 1 from public.inquiries i where i.id = t.inquiry_id and i.status in ('completed', 'closed') and i.hired_supplier_id = t.supplier_id);
    v_rated := exists (select 1 from public.reviews v where v.transaction_id = t.id);
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
    if v_offp_text is null then
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
    if not v_unresp then v_excl := v_excl || ('the reason is ' || v_reason || ', not supplier non-response (price dissatisfaction and a change of mind are not refundable)'); end if;
    if v_prior then v_excl := v_excl || 'the customer revealed this same supplier before'::text; end if;
    if v_hired then v_excl := v_excl || 'the customer completed the job with this supplier'::text; end if;
    if v_rated then v_excl := v_excl || 'the customer already rated this supplier'::text; end if;
    if coalesce(v_offp, false) then v_excl := v_excl || 'the customer engaged the supplier off the platform (reasoned by the CEO seat)'::text; end if;
    v_items := v_items || jsonb_build_object('item', 'no_refund_exclusion_applies',
      'passed', cardinality(v_excl) = 0,
      'evidence', jsonb_build_object('reason_code', v_reason, 'same_supplier_revealed_before', v_prior, 'job_completed_with_supplier', v_hired,
                                     'supplier_rated', v_rated, 'off_platform_engagement_recorded', v_offp,
                                     'supplier_responded', 'checked by supplier_never_responded'),
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

    -- 6. The amount is exactly what the customer paid.
    v_exp := round(coalesce(v_total, 0) * 100)::bigint;
    v_items := v_items || jsonb_build_object('item', 'amount_equals_total_charged',
      'passed', r.id is not null and r.amount_fils = v_exp and v_exp > 0,
      'evidence', jsonb_build_object('refund_id', r.id, 'refund_fils', r.amount_fils, 'total_charged_fils', v_exp,
                                     'total_charged_recorded', t.total_charged is not null, 'stripe_reference', t.payment_ref),
      'reason', case when r.id is null then 'there is no open refund request on this payment' else 'the refund amount is not what the customer paid' end,
      'remedy', 'the accountant sets the refund to the payment''s total_charged',
      'owner', 'accountant', 'remedy_key', 'amount', 'remediable', r.id is not null, 'kind', 'money');

  elsif p_phase = 'verify' then
    select count(*), coalesce(sum(x.amount_fils), 0) into v_succ, v_succ_fils
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref));
    -- A top-up the playbook issued is not a duplicate: its Stripe id is on the incident fix.
    select count(*) into v_extra
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
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

-- ── VERDICT (read-only) ─────────────────────────────────────────────────────────────────────────────────────────────
select case when problems is null then 'PROBE OK' else 'PROBE FAILED: ' || problems end as verdict from (
  select string_agg(p, '; ') problems from (
    select 'a routine is open or unpinned: ' || p.oid::regprocedure::text p from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('fn_person_open_promises', 'fn_support_case_links_a_fault', 'fn_contact_timeline', 'fn_ceo_refund_checklist')
       and (not p.prosecdef or not coalesce(p.proconfig @> array['search_path=public, pg_temp'], false)
            or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
    union all select 'the timeline has no fault branch' where pg_get_functiondef('public.fn_contact_timeline(text,integer)'::regprocedure) !~ 'it_fault'
    union all select 'the refund checklist does not read his timeline'
     where pg_get_functiondef('public.fn_ceo_refund_checklist(uuid,text,boolean)'::regprocedure) !~ 'fn_person_open_promises'
  ) z) y;
