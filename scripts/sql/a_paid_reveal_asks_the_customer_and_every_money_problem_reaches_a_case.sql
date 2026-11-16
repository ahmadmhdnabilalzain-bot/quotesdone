-- A PAID REVEAL ASKS THE CUSTOMER WHETHER THE SUPPLIER CALLED, AND EVERY MONEY PROBLEM AFTER IT REACHES A CASE.
-- Seat: customer_support (agent AFTER_REVEAL, customer_support builder), with the sales_engineer's ladder, the CEO's decision and
-- the accountant's refund as touch points. Founder ledgers 1711-1713 (16 Nov 2026): "everyone knows what the other is doing because
-- they are colleagues in the same company". Hole hunt SP/holes/CUSTOMER.md items 1, 2, 3, 4 and 12.
--
-- WHAT WE PROMISED (the published text in src/content/legal.json, quoted so every behaviour below can be held to it):
--   Terms of Service v11, clause 5: "A Supplier is treated as having "responded" if they reply by any reasonable means, including
--     the on-platform message thread, telephone, email or WhatsApp." / "If the Supplier has failed to respond both to you and to
--     QuotesDone within five (5) working days of your payment and does not respond to that final contact attempt, everything you
--     paid for that Reveal is refunded" / "No refund, re-match or credit is due where: the Supplier has responded; ... you are
--     dissatisfied with the Supplier's price, quotation or terms; or you have simply changed your mind." / "You may also raise a
--     complaint through the Platform at any time".
--   Terms v11, clause 10: the automated systems "decide refund requests and disputes under QuotesDone's published rules".
--   Terms v11, clause 18: "Every complaint receives a ticket number ... We will acknowledge your complaint within two (2) working
--     days and give a substantive response within ten (10) working days".
--   Refund & Cancellation Policy v1.9, section 5: "You can still tell us at any time that the supplier is not responding ... and we
--     will chase the supplier immediately." Section 4: not refundable "where the supplier's pricing or terms no longer suit you".
--   Complaints Policy v1.4, section 4: "Where a dispute concerns the supplier's quote, pricing, quality, licensing, conduct or
--     completion of works, that is a matter between you and the supplier. Our role is limited to reasonable facilitation, such as
--     sharing relevant Platform records or helping reconnect the parties."
--   Supplier Agreement v17, clause 8: "The Supplier shall: honour every quotation it submits and any agreed timeline; respond to
--     revealed Customers professionally and promptly". Clause 9: "the Supplier is bound by a quotation that is revealed within that
--     validity period". Clause 13: "Customers and QuotesDone may rate and review performance". Clause 19: "QuotesDone may suspend or
--     terminate access for breach of this Agreement ... or conduct harmful to the Platform or its users." Clause 33: the supplier
--     "must respond to that Customer within five (5) working days of the Reveal, by the on-platform message thread, telephone,
--     email or other reasonable means".
--
-- WHAT WAS MEASURED (16 Nov 2026; light production SELECTs, counts only): 1 revealed sale, 1 with supplier_ack_at; 0 customer_followup
-- rows; 0 post_reveal_dispute; wa_reply_intent has 22 active rows and none is about a revealed job; seat_handoff_kind holds
-- sales.escalation sales_engineer -> ceo (fn_ceo_takes_sales_escalation, escalation 'disputed_reveal'); the follow-up runs as duty
-- sales_engineer.followup (fn_customer_support_followup_tick). On origin/main (READ): fn_refund_state counted supplier_ack_at or an
-- on-platform supplier message and nothing else, so a supplier's one click stopped the ladder and a supplier who phoned was refunded
-- against (Terms clause 5 says a phone call IS a response); fn_customer_followup_answer wrote a review whatever the customer said,
-- and fn_refund_open_from_customer then refused with supplier_rated; fn_customer_support_dispute_consider and _open had no caller;
-- supplier_ack told role 'admin' only.
--
-- WHAT THIS FILE DOES
--   1. reveal_contact_statement: the CUSTOMER's word on whether the revealed supplier contacted him, one row per statement, on
--      every door (the one-tap page, WhatsApp, the widget, the portal). fn_reveal_contact_word reads it beside the supplier's
--      claim (supplier_ack_at, an on-platform message). "Responded" (Terms clause 5) is: the customer says yes; or the supplier
--      claims contact and the customer has not denied it since. A denial AFTER the supplier's claim is a conflict: the ladder keeps
--      running and the CEO is handed both statements (sales.escalation / disputed_reveal, the existing conversation).
--   2. fn_refund_state reads that word, so the ladder sweep and the CEO's refund checklist (item 4 reads fn_refund_state) both see
--      it without a change to either. fn_reveal_contact_word is a separate routine the checklist can show as evidence.
--   3. Working day 2: fn_customer_support_contact_check_tick asks "has <supplier> contacted you?" in his language, through the one
--      door (duty_send; fn_wa_fanout twins it on his confirmed WhatsApp). Duty sales_engineer.contact_check (the ladder's owner;
--      support delivers), every 2 hours.
--   4. The supplier's "I have contacted the customer" (fn_supplier_ack_record, called by supplier_ack) is told to the CUSTOMER with
--      a one-tap "they have not" link, and recorded by customer_support (its duty message and delivery), not sent to role admin.
--   5. The day-3 follow-up asks the contact question first. A "never contacted" answer writes no review (a rating is a record of
--      dealing only when contact happened: Supplier Agreement clause 13 is about performance) and goes to the ladder as the
--      customer's word; a low rating or a "not hired" with words, after contact, goes to the dispute intake, where the MODEL reads it.
--      fn_refund_open_from_customer's supplier_rated refusal now asks fn_refund_rating_shows_dealing.
--   6. ONE door for "a problem with this job": fn_customer_after_reveal_message (portal, WhatsApp intent after_reveal, the signed-in
--      widget). It calls fn_customer_support_dispute_consider with the revealed quotation on record (price, scope, exclusions,
--      warranty, lead time, validity, payment terms). The model chooses: the supplier contacted him / did not contact him (the
--      refund door) / a dispute (the case) / nothing for a case. No keyword decides.
--   7. fn_ceo_decides_post_reveal_dispute acts on its decision: a strike event on an upheld complaint (supplier standing), and what
--      the CEO chose: a refund of the reveal fee (fn_refund_request), the next reveal on the request refunded (a goodwill refund,
--      filed by duty accountant.dispute_remedy when he pays it), a formal warning, or matching paused under clause 19.
--   8. fn_customer_money_cases(customer): his open refunds, disputes, waiting intakes and each revealed job's ladder state, for every
--      channel's facts. A separate routine: fn_customer_inquiry_facts belongs to another branch, so the main session wires it.
--
-- Every new routine: SECURITY DEFINER, search_path pinned, EXECUTE revoked from public, anon and authenticated, granted to
-- service_role. A routine whose signature changes is dropped first and its new signature revoked. The new table: RLS on, a
-- service-role-only policy, revoked from anon and authenticated.
-- Probe: a_paid_reveal_asks_the_customer_and_every_money_problem_reaches_a_case_probe.sql (local Postgres 16 from the mirror, twice).
-- Prevented by: scripts/checks/a_paid_reveal_asks_the_customer_and_every_money_problem_reaches_a_case.test.mjs,
--   supabase/functions/customer_followup/page.test.ts, supabase/functions/supplier_ack/token.test.ts,
--   supabase/functions/site_assistant/after_reveal_door.test.ts, supabase/functions/customer_api/job_problem.test.ts.
--   node scripts/apply_sql.mjs scripts/sql/a_paid_reveal_asks_the_customer_and_every_money_problem_reaches_a_case.sql --apply --ddl --seat customer_support

set local lock_timeout = '3s';

-- ── 1. THE CUSTOMER'S WORD ON CONTACT ───────────────────────────────────────────────────────────────────────────────
create table if not exists public.reveal_contact_statement (
  id             bigint generated always as identity primary key,
  transaction_id uuid not null references public.transactions (id) on delete cascade,
  said           text not null check (said in ('yes', 'no', 'not_yet')),
  channel        text not null check (channel in ('followup_page', 'whatsapp', 'widget', 'portal', 'email')),
  words          text check (words is null or length(words) <= 2000),
  source_ref     text,
  said_at        timestamptz not null default clock_timestamp()
);
create index if not exists reveal_contact_statement_tx_idx on public.reveal_contact_statement (transaction_id, said_at desc);
alter table public.reveal_contact_statement enable row level security;
drop policy if exists reveal_contact_statement_service_role_only on public.reveal_contact_statement;
create policy reveal_contact_statement_service_role_only on public.reveal_contact_statement
  as permissive for all to public using (false) with check (false);
revoke all on public.reveal_contact_statement from anon, authenticated;
comment on table public.reveal_contact_statement is
  'The customer''s own word on whether the revealed supplier contacted him (Terms v11 clause 5: any reasonable means). One row per statement; fn_reveal_contact_word reads it beside supplier_ack_at.';

-- exported every day with its subject (the customer's own statements on a paid reveal are business records, like customer_followup)
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('reveal_contact_statement', true, 'customer', 'the customer''s own word on whether the revealed supplier contacted him, read by the refund ladder beside the supplier''s acknowledgement', 'customer_support')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- the follow-up gains its working-day-2 stage and the contact answer
alter table public.customer_followup drop constraint if exists customer_followup_stage_check;
alter table public.customer_followup add constraint customer_followup_stage_check
  check (stage in ('day_two_contact', 'day_three', 'day_fourteen'));
alter table public.customer_followup add column if not exists contacted text;
alter table public.customer_followup drop constraint if exists customer_followup_contacted_check;
alter table public.customer_followup add constraint customer_followup_contacted_check
  check (contacted is null or contacted in ('yes', 'no', 'not_yet'));

-- a dispute carries the quotation it is about, the door it came through, and what the CEO's decision did
alter table public.post_reveal_dispute add column if not exists job_facts jsonb;
alter table public.post_reveal_dispute add column if not exists channel text;
alter table public.post_reveal_dispute add column if not exists remedy text;
alter table public.post_reveal_dispute add column if not exists supplier_action text;
alter table public.post_reveal_dispute add column if not exists effect jsonb;
alter table public.post_reveal_dispute add column if not exists remedy_transaction_id uuid;
alter table public.post_reveal_dispute add column if not exists remedy_done_at timestamptz;
alter table public.post_reveal_dispute drop constraint if exists post_reveal_dispute_remedy_check;
alter table public.post_reveal_dispute add constraint post_reveal_dispute_remedy_check
  check (remedy is null or remedy in ('none', 'refund_reveal_fee', 'next_reveal_free'));
alter table public.post_reveal_dispute drop constraint if exists post_reveal_dispute_supplier_action_check;
alter table public.post_reveal_dispute add constraint post_reveal_dispute_supplier_action_check
  check (supplier_action is null or supplier_action in ('none', 'warning', 'pause_matching'));

-- the supplier's standing record gains the upheld complaint (append-only, like its strikes; it changes no strike count)
alter table public.supplier_strike_event drop constraint if exists supplier_strike_event_kind_check;
alter table public.supplier_strike_event add constraint supplier_strike_event_kind_check
  check (kind in ('strike', 'cleared', 'dispute_upheld'));

-- ── 2. THE JOB ON RECORD: the revealed quotation the supplier is bound by (Supplier Agreement v17 clause 9) ─────────
create or replace function public.fn_reveal_job_facts(p_transaction uuid)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_strip_nulls(jsonb_build_object(
           'transaction_id', t.id, 'rfq_no', i.rfq_no, 'trade', coalesce(i.category, i.trades[1]),
           'revealed_at', t.revealed_at, 'supplier', l.company_name, 'reveal_fee_paid_aed', round(coalesce(t.total_charged, t.reveal_fee, 0), 2),
           'quote', jsonb_strip_nulls(jsonb_build_object(
              'quote_id', q.id, 'amount_aed', q.quote_amount, 'price_ex_vat_aed', q.price_ex_vat, 'vat_aed', q.vat_amount,
              'discount_aed', q.discount_amount, 'scope', left(q.scope, 1500), 'exclusions', left(q.exclusions, 800),
              'conditions', left(q.conditions, 800), 'warranty', left(q.warranty, 400), 'lead_time', left(q.lead_time, 200),
              'validity', left(q.validity, 200), 'payment_terms', left(q.payment_terms, 400), 'submitted_at', q.created_at)),
           'binding_rule', 'Supplier Agreement v17 clause 9: the supplier is bound by a quotation revealed within its validity; clause 8: honour every quotation and any agreed timeline'))
    from public.transactions t
    left join public.quotes q on q.id = t.quote_id
    left join public.inquiries i on i.id = t.inquiry_id
    left join public.leads l on l.id = t.supplier_id
   where t.id = p_transaction
$fn$;
revoke execute on function public.fn_reveal_job_facts(uuid) from public, anon, authenticated;
grant execute on function public.fn_reveal_job_facts(uuid) to service_role;

-- ── 3. THE CUSTOMER'S WORD BESIDE THE SUPPLIER'S CLAIM ─────────────────────────────────────────────────────────────
-- responded: the customer said yes at least once (a call is a response, Terms clause 5); or the supplier claims contact (the
-- one-click acknowledgement, a message on the platform) and the customer has not said no SINCE that claim.
-- conflict: the customer's latest definite word is no, he never said yes, and it came after the supplier's claim. The ladder
-- keeps running (responded is false) and the CEO is handed both statements by fn_reveal_contact_record.
create or replace function public.fn_reveal_contact_word(p_transaction uuid)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with t as (select x.* from public.transactions x where x.id = p_transaction),
  msg as (select min(m.created_at) as first_at, max(m.created_at) as last_at
            from public.messages m, t
           where m.inquiry_id = t.inquiry_id and m.supplier_id = t.supplier_id and m.sender = 'supplier'
             and coalesce(m.blocked, false) = false and t.revealed_at is not null and m.created_at > t.revealed_at),
  yes as (select min(s.said_at) as first_at from public.reveal_contact_statement s where s.transaction_id = p_transaction and s.said = 'yes'),
  def as (select s.* from public.reveal_contact_statement s where s.transaction_id = p_transaction and s.said in ('yes', 'no')
           order by s.said_at desc, s.id desc limit 1),
  lst as (select s.* from public.reveal_contact_statement s where s.transaction_id = p_transaction order by s.said_at desc, s.id desc limit 1),
  w0 as (select t.id, t.supplier_ack_at, msg.first_at as msg_first, msg.last_at as msg_last, yes.first_at as yes_at,
               greatest(t.supplier_ack_at, msg.last_at) as claim_at,
               (select said from def) as def_said, (select said_at from def) as def_at,
               (select said from lst) as last_said, (select said_at from lst) as last_at,
               (select channel from lst) as last_channel, (select words from lst) as last_words,
               (select count(*) from public.reveal_contact_statement s where s.transaction_id = p_transaction) as n
          from t, msg, yes),
  w as (select w0.*,
               -- every comparison is closed against null: no word, no claim or no date is "not denied after a claim"
               coalesce(w0.yes_at is null and w0.def_said = 'no' and w0.claim_at is not null and w0.def_at >= w0.claim_at, false) as denied_after_claim
          from w0)
  select jsonb_build_object(
           'transaction_id', w.id,
           'customer_said', case when w.yes_at is not null then 'yes' else coalesce(w.def_said, w.last_said) end,
           'customer_confirms_contact', w.yes_at is not null,
           'customer_denies_contact', w.yes_at is null and coalesce(w.def_said = 'no', false),
           'customer_said_at', coalesce(w.yes_at, w.def_at, w.last_at),
           'customer_last_word', w.last_said, 'customer_last_channel', w.last_channel, 'customer_last_words', left(w.last_words, 500),
           'statements', w.n,
           'supplier_ack_at', w.supplier_ack_at, 'supplier_message_at', w.msg_first,
           'supplier_claims_contact', w.claim_at is not null,
           'conflict', w.denied_after_claim,
           'responded', w.yes_at is not null or (w.claim_at is not null and not w.denied_after_claim),
           'basis', case
             when w.yes_at is not null then 'the customer told us the supplier contacted him (Terms v11 clause 5: any reasonable means)'
             when w.denied_after_claim
               then 'the supplier claims contact and the customer says there was none: a conflict for the CEO; the ladder keeps running'
             when w.claim_at is not null then 'the supplier claims contact (acknowledgement or a platform message) and the customer has not denied it since'
             when coalesce(w.def_said = 'no', false) then 'the customer says the supplier has not contacted him'
             else 'no word from the customer and no claim from the supplier' end)
    from w
$fn$;
revoke execute on function public.fn_reveal_contact_word(uuid) from public, anon, authenticated;
grant execute on function public.fn_reveal_contact_word(uuid) to service_role;

-- ── 4. RECORDING A STATEMENT; A DENIAL AFTER A CLAIM GOES TO THE CEO WITH BOTH ──────────────────────────────────────
create or replace function public.fn_reveal_contact_record(p_transaction uuid, p_said text, p_channel text,
  p_words text default null, p_source_ref text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.transactions; v_prev public.reveal_contact_statement; v_id bigint; v_word jsonb; v_h bigint; v_words text;
begin
  if p_said is null or p_said not in ('yes', 'no', 'not_yet') then
    raise exception 'the customer''s word on contact is yes, no or not_yet, not %', coalesce(p_said, 'nothing') using errcode = '22023';
  end if;
  if p_channel is null or p_channel not in ('followup_page', 'whatsapp', 'widget', 'portal', 'email') then
    raise exception 'a contact statement names its door (followup_page, whatsapp, widget, portal, email), not %', coalesce(p_channel, 'nothing') using errcode = '22023';
  end if;
  select * into t from public.transactions where id = p_transaction;
  if not found or t.revealed_at is null then
    raise exception 'a contact statement is about a revealed job; % is not one', p_transaction using errcode = '22023';
  end if;
  v_words := nullif(left(btrim(coalesce(p_words, '')), 2000), '');
  -- the same word through the same door within ten minutes is one statement (a double tap, a retry, the refund door after the intake)
  select * into v_prev from public.reveal_contact_statement where transaction_id = t.id order by id desc limit 1;
  if v_prev.id is not null and v_prev.said = p_said and v_prev.channel = p_channel and v_prev.said_at > now() - interval '10 minutes' then
    return jsonb_build_object('recorded', false, 'duplicate', true, 'statement_id', v_prev.id, 'word', public.fn_reveal_contact_word(t.id));
  end if;
  insert into public.reveal_contact_statement (transaction_id, said, channel, words, source_ref)
  values (t.id, p_said, p_channel, v_words, p_source_ref) returning id into v_id;
  v_word := public.fn_reveal_contact_word(t.id);
  if p_said = 'no' and coalesce((v_word->>'conflict')::boolean, false) then
    -- THE CEO GETS BOTH STATEMENTS, through the conversation that already exists for a disputed reveal (fn_ceo_takes_sales_escalation).
    -- The ladder belongs to the sales engineer, so the escalation is its; nothing here decides who is right.
    v_h := public.fn_seat_handoff('sales_engineer', 'ceo', 'sales.escalation', 'transactions', t.id || ':contact_conflict:' || v_id,
      jsonb_build_object('escalation', 'disputed_reveal', 'transaction_id', t.id, 'customer_id', t.customer_id, 'supplier_id', t.supplier_id,
        'inquiry_id', t.inquiry_id,
        'case', jsonb_build_object(
          'what', 'The customer says the revealed supplier has not contacted him; the supplier says it has. The refund ladder keeps running on the customer''s word until you decide.',
          'customer_statement', jsonb_build_object('said', p_said, 'channel', p_channel, 'words', left(v_words, 1000), 'at', now()),
          'supplier_statement', jsonb_build_object('acknowledged_at', t.supplier_ack_at, 'platform_message_at', v_word->'supplier_message_at'),
          'ladder', public.fn_refund_state(t.id),
          'rule', 'Terms v11 clause 5: a supplier responded if it replied by any reasonable means; no refund is due where the supplier has responded. Supplier Agreement v17 clause 33.')));
  end if;
  return jsonb_build_object('recorded', true, 'statement_id', v_id, 'word', v_word, 'conflict_handoff', v_h);
end $fn$;
revoke execute on function public.fn_reveal_contact_record(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_reveal_contact_record(uuid, text, text, text, text) to service_role;

-- ── 5. THE LADDER READS THE CUSTOMER'S WORD ────────────────────────────────────────────────────────────────────────
-- The live body (the mirror) with ONE change: v_responded comes from fn_reveal_contact_word, which keeps the old two signals (the
-- acknowledgement, a platform message after the reveal) and adds the customer's own word, and the output carries both statements.
create or replace function public.fn_refund_state(p_transaction uuid)
returns jsonb language plpgsql stable set search_path to 'public', 'pg_temp' as $fn$
declare t record; v_window int; v_chase int; v_notify_days int; v_min int; v_max int;
        v_responded boolean; v_chase_at timestamptz; v_final_at timestamptz; v_notify_at timestamptz;
        v_chased_at timestamptz; v_final_sent_at timestamptz; v_state text; v_word jsonb;
begin
  select * into t from transactions where id = p_transaction;
  if not found then return jsonb_build_object('error','transaction_not_found'); end if;

  -- THE LADDER (founder, 6 Sep 2026): the clock starts when the customer PAYS (revealed_at), never at
  -- a nudge or a notice. Day 3 without a supplier response: the owning employee chases. Day 5: the
  -- founder is notified for the final call and the refund becomes approvable. All from pricing_config.
  select refund_window_working_days, chase_after_working_days,
         bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_window, v_chase, v_min, v_max from pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);
  v_notify_days := coalesce((select value::text::int from decision_policy where key='refund_notify_after_working_days'),1);

  -- RESPONDED (16 Nov 2026, AFTER_REVEAL): the customer's word beside the supplier's claim (fn_reveal_contact_word). A customer
  -- who says the supplier called stops the ladder; a customer who says no after the supplier's click keeps it running.
  v_word := public.fn_reveal_contact_word(t.id);
  v_responded := coalesce((v_word->>'responded')::boolean, false);

  v_chase_at  := case when t.revealed_at is null then null else public.fn_add_working_days(t.revealed_at, v_chase) end;
  v_final_at  := case when t.revealed_at is null then null
                      else coalesce(t.refund_deadline, public.fn_add_working_days(t.revealed_at, v_window)) end;
  v_notify_at := case when t.revealed_at is null then null else public.fn_add_working_days(t.revealed_at, v_notify_days) end;

  select min(n.created_at) into v_chased_at from notifications n
   where n.type = 'supplier_no_response_chase' and n.channel = 'email'
     and n.inquiry_id = t.inquiry_id and n.lead_id = t.supplier_id
     and t.revealed_at is not null and n.created_at > t.revealed_at;
  -- The day-5 final call is the sales engineer's notice delivered by support (type refund_final_notice).
  -- The founder_alerts marker the ladder wrote before 14 Sep is still honoured for cases already on it.
  select least((select min(n.created_at) from notifications n
                 where n.type = 'refund_final_notice' and n.inquiry_id = t.inquiry_id and n.lead_id = t.supplier_id
                   and t.revealed_at is not null and n.created_at > t.revealed_at),
               (select min(f.created_at) from founder_alerts f where f.dedupe_key = 'refund_final_call:' || t.id::text))
    into v_final_sent_at;

  v_state := case
    when t.revealed_at is null                                                          then 'not_revealed'
    when v_responded                                                                    then 'supplier_responded'
    when coalesce(t.refund_status,'') in ('approved','refunded','processing','succeeded') then 'refunded'
    when coalesce(t.refund_status,'') = 'rejected'                                      then 'refund_rejected'
    when now() < v_chase_at                                                             then 'waiting'
    when now() < v_final_at then case when v_chased_at is null then 'chase_due' else 'chased' end
    else case when v_final_sent_at is null then 'final_call_due' else 'final_call_sent' end end;

  return jsonb_build_object(
    'transaction_id', t.id,
    'state', v_state,
    'revealed_at', t.revealed_at,
    'supplier_responded', v_responded,
    'responded_basis', v_word->>'basis',
    'customer_said', v_word->>'customer_said',
    'customer_said_at', v_word->'customer_said_at',
    'supplier_ack_at', t.supplier_ack_at,
    'contact_conflict', coalesce((v_word->>'conflict')::boolean, false),
    'refund_window_working_days', v_window,
    'chase_after_working_days', v_chase,
    'chase_due_at', v_chase_at,
    'chased_at', v_chased_at,
    'founder_call_due_at', v_final_at,
    'final_call_sent_at', v_final_sent_at,
    'refund_deadline', t.refund_deadline,
    'notify_available_at', v_notify_at,
    'can_notify', (t.revealed_at is not null and not v_responded and t.customer_notified_at is null
                   and now() >= v_notify_at and v_state not in ('refunded','refund_rejected')),
    'notified_at', t.customer_notified_at,
    'auto_nudged_at', t.nudged_24_at,
    'refund_approvable', v_state in ('final_call_due','final_call_sent'),
    'refund_status', t.refund_status,
    'working_days_since_reveal', case when t.revealed_at is null then 0
                                      else public.fn_working_days_between(t.revealed_at, now()) end,
    'working_days_since_notice', case when t.customer_notified_at is null then 0
                                      else public.fn_working_days_between(t.customer_notified_at, now()) end,
    'bank_settlement_working_days', coalesce(v_min,7)::text || '-' || coalesce(v_max,14)::text
  );
end $fn$;
revoke execute on function public.fn_refund_state(uuid) from public, anon, authenticated;
grant execute on function public.fn_refund_state(uuid) to service_role;

-- ── 6. A RATING IS A RECORD OF DEALING ONLY WHEN CONTACT HAPPENED ──────────────────────────────────────────────────
-- For fn_refund_open_from_customer (here) and the CEO's refund checklist item 5 (another branch: the main session swaps its
-- `exists (select 1 from public.reviews ...)` for this). A review stands as dealing unless the customer has told us the supplier
-- never contacted him and never said otherwise.
create or replace function public.fn_refund_rating_shows_dealing(p_transaction uuid)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select exists (select 1 from public.reviews v where v.transaction_id = p_transaction)
     and not coalesce((public.fn_reveal_contact_word(p_transaction)->>'customer_denies_contact')::boolean, false)
$fn$;
revoke execute on function public.fn_refund_rating_shows_dealing(uuid) from public, anon, authenticated;
grant execute on function public.fn_refund_rating_shows_dealing(uuid) to service_role;

-- ── 7. THE CUSTOMER'S REFUND DOOR: the rating exclusion reads the word, the door names its channel, and its "the supplier is not
--      responding" is recorded as the customer's word (Refund Policy v1.9 section 5: tell us at any time). The live body otherwise.
drop function if exists public.fn_refund_open_from_customer(uuid, text, text);
create or replace function public.fn_refund_open_from_customer(p_transaction_id uuid, p_requested_by text, p_reason_note text default null,
  p_channel text default 'portal')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.transactions; c record; v_id bigint; v_open bigint; v_locale text; v_code text; v_en text; v_ar text;
  v_later boolean := false; v_paid text; v_decide text; v_req bigint; v_amt numeric; v_out bigint; v_word jsonb;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'no_such_transaction', 'locale', 'en', 'can_claim_later', false,
      'message_en', 'We could not find that reveal on your account.', 'message_ar', 'لم نعثر على عملية الكشف هذه في حسابكم.');
  end if;
  select id, email into c from public.customers where id = t.customer_id;
  v_locale := coalesce(public.fn_registered_locale('customer', t.customer_id, null, c.email), 'en');
  v_amt := round(coalesce(t.total_charged, t.reveal_fee, 0), 2);
  v_paid := to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY');
  v_decide := to_char(t.refund_deadline at time zone 'Asia/Dubai', 'DD Mon YYYY');

  -- ONE CLAIM PER PAYMENT: a second press, or a retry, returns the case already open.
  select id into v_open from public.refunds
   where transaction_id = t.id and status not in ('rejected', 'failed', 'cancelled')
     and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe')
   order by id limit 1;
  if v_open is not null then
    return jsonb_build_object('ok', true, 'duplicate', true, 'refund_id', v_open, 'locale', v_locale, 'decision_after', t.refund_deadline,
      'message_en', 'Your refund case QD-RF-' || v_open || ' is already open. Our chief executive decides it after ' || coalesce(v_decide, 'the fifth working day') || '; you do not need to do anything else.',
      'message_ar', 'حالة الاسترداد QD-RF-' || v_open || ' مفتوحة بالفعل، وسيبتّ فيها رئيسنا التنفيذي بعد ' || coalesce(v_decide, 'يوم العمل الخامس') || '، ولا يلزمكم أي إجراء آخر.');
  end if;

  -- THE REFUSALS, each with the reason and whether a claim can come later.
  if t.revealed_at is null then
    v_code := 'not_revealed'; v_later := true;
    v_en := 'This reveal has not completed yet. You can ask for a refund once the payment has gone through and the supplier''s details are shown to you.';
    v_ar := 'لم تكتمل عملية الكشف بعد. يمكنكم طلب الاسترداد بعد إتمام الدفع وظهور بيانات المورّد لكم.';
  elsif coalesce(btrim(t.payment_ref), '') = '' then
    v_code := 'no_payment'; v_later := true;
    v_en := 'We have no recorded payment for this reveal yet, so there is nothing to refund. If you were charged, reply to your payment receipt and we will match it; you can ask again once it is recorded.';
    v_ar := 'لا يوجد لدينا دفع مسجّل لعملية الكشف هذه حتى الآن، فلا مبلغ يُسترد. وإن خُصم منكم أي مبلغ، فيُرجى الرد على إيصال الدفع لنطابقه، ويمكنكم تقديم الطلب مجددًا بعد تسجيله.';
  elsif coalesce(t.refund_status, '') in ('approved', 'refunded', 'processing', 'succeeded') then
    v_code := 'already_refunded';
    v_en := 'This reveal has already been refunded (AED ' || coalesce(t.refund_amount_aed, v_amt) || '). Banks take 7 to 14 working days to show it.';
    v_ar := 'سبق أن استُردّت رسوم عملية الكشف هذه (' || coalesce(t.refund_amount_aed, v_amt) || ' درهم)، وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهار المبلغ.';
  -- MONEY ALREADY RETURNED ON THIS PAYMENT (3 Nov 2026, accountant, gap #8 R4): a refund issued in the Stripe dashboard leaves the
  -- sale's refund_status empty; the answer is a refusal in words, the rest is the CEO's refund_incident.
  elsif (select coalesce(sum(r.amount_fils), 0) from public.refunds r
          where (r.transaction_id = t.id or r.stripe_payment_intent = t.payment_ref)
            and r.status not in ('rejected', 'failed', 'cancelled')) > 0 then
    v_out := (select coalesce(sum(r.amount_fils), 0) from public.refunds r
               where (r.transaction_id = t.id or r.stripe_payment_intent = t.payment_ref)
                 and r.status not in ('rejected', 'failed', 'cancelled'));
    v_code := 'already_refunded';
    v_en := 'AED ' || round(v_out / 100.0, 2) || ' of this payment has already been refunded to your original payment method, so a new refund case cannot be opened for it. Banks take 7 to 14 working days to show it. If you think more is owed, write to us from your portal and we will check the record.';
    v_ar := 'سبق أن استُردّ ' || round(v_out / 100.0, 2) || ' درهم من هذه الدفعة إلى وسيلة الدفع الأصلية، لذا لا يمكن فتح حالة استرداد جديدة لها. وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهار المبلغ. وإن رأيتم أن هناك مبلغًا آخر مستحقًا، فيُرجى مراسلتنا من بوابتكم لنراجع السجل.';
  elsif exists (select 1 from public.refunds r where r.transaction_id = t.id and r.status = 'rejected'
                  and lower(coalesce(r.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe')) then
    v_code := 'already_declined';
    v_en := 'Our chief executive has already decided this case and declined it; the reason is shown on your refund case. Under section 5 of the Terms a decided case is not reopened by a new request. If you think the record is wrong, reply to the decision email.';
    v_ar := 'سبق أن بتّ رئيسنا التنفيذي في هذه الحالة ورفضها، والسبب مبيّن في حالة الاسترداد. ووفق البند 5 من الشروط، لا يُعاد فتح حالة بُتّ فيها بطلب جديد. وإن رأيتم أن السجل غير صحيح، فيُرجى الرد على رسالة القرار.';
  elsif exists (select 1 from public.inquiries i where i.id = t.inquiry_id and i.status in ('completed', 'closed') and i.hired_supplier_id = t.supplier_id) then
    v_code := 'job_completed';
    v_en := 'This job is marked as completed with this supplier, so the supplier responded and the reveal fee is not refundable (Terms, section 5).';
    v_ar := 'هذا العمل مسجّل مكتملًا مع هذا المورّد، ما يعني أنه استجاب، لذا لا تُسترد رسوم الكشف (الشروط، البند 5).';
  -- A RATING BARS THE REFUND ONLY AS A RECORD OF DEALING (16 Nov 2026): our own day-3 survey wrote a review from "No, never called,
  -- 1 star", and this then refused the refund the Terms promise on exactly that case.
  elsif public.fn_refund_rating_shows_dealing(t.id) then
    v_code := 'supplier_rated';
    v_en := 'You have rated this supplier, which records that you dealt with them, so the reveal fee is not refundable (Terms, section 5).';
    v_ar := 'قيّمتم هذا المورّد، وهو ما يُثبت تعاملكم معه، لذا لا تُسترد رسوم الكشف (الشروط، البند 5).';
  end if;
  if v_code is not null then
    -- Recorded, so a refusal is as visible to the seats as a case: who asked, when, and why not.
    perform public.fn_emit('refund.request_refused', 'transaction', t.id::text, coalesce(p_requested_by, 'customer'),
      jsonb_build_object('transaction_id', t.id, 'customer_id', t.customer_id, 'code', v_code, 'can_claim_later', v_later, 'reason', v_en,
                         'channel', p_channel));
    return jsonb_build_object('ok', false, 'code', v_code, 'can_claim_later', v_later, 'locale', v_locale, 'message_en', v_en, 'message_ar', v_ar);
  end if;

  -- THE CUSTOMER'S WORD: "the supplier is not responding" is his statement on contact, read by the ladder beside the supplier's claim.
  if coalesce(p_requested_by, 'customer') = 'customer' then
    v_word := public.fn_reveal_contact_record(t.id, 'no', case when p_channel in ('followup_page', 'whatsapp', 'widget', 'portal', 'email') then p_channel else 'portal' end,
                coalesce(p_reason_note, 'The customer reported that the revealed supplier has not responded.'), 'refund_door');
  end if;

  -- THE CASE. The amount is what the customer paid (total_charged); a00 holds it to that figure and to
  -- the payment's own Stripe reference. trg_emit_refund_requested and z30 put it on the bus and hand
  -- it to the accountant.
  insert into public.refunds
    (transaction_id, quote_id, inquiry_id, customer_id, supplier_lead_id,
     stripe_payment_intent, amount_fils, currency, reason_code, reason_note,
     status, requested_by, requested_at, amount_source)
  values
    (t.id, t.quote_id, t.inquiry_id, t.customer_id, t.supplier_id,
     t.payment_ref, round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint, 'AED',
     'supplier_unresponsive',
     coalesce(p_reason_note, 'The customer reported that the revealed supplier has not responded.'),
     'requested', coalesce(p_requested_by, 'customer'), now(), 'in_platform_request')
  returning id into v_id;

  -- The sale follows the case, never the other way round.
  update public.transactions
     set refund_status = 'requested', refund_requested_at = coalesce(refund_requested_at, now())
   where id = t.id;

  -- The confirmation: the sales engineer writes it, customer support delivers it in the customer's
  -- registered language (fn_sales_engineer_writes -> delivery.request).
  v_req := public.fn_sales_engineer_writes('refund_request_received', 'customer', c.email, null, t.customer_id, t.inquiry_id, t.quote_id,
    'Your refund case QD-RF-' || v_id || ' is open',
    'We have opened refund case QD-RF-' || v_id || ' for the supplier you revealed on ' || coalesce(v_paid, 'your payment date') || '. You do not need to do anything else.' || E'\n\n'
      || 'The supplier has until ' || coalesce(v_decide, 'the fifth working day after your payment') || ' to respond. We chase them on the third working day and copy you. '
      || 'If there is still no response, our chief executive makes a final call and then decides your case on the record. '
      || 'If the refund is due, everything you paid (AED ' || v_amt || ') is returned to your original payment method; banks take 7 to 14 working days to show it.',
    'فتحنا حالة الاسترداد QD-RF-' || v_id,
    'فتحنا حالة الاسترداد QD-RF-' || v_id || ' بشأن المورّد الذي كشفتم عنه في ' || coalesce(v_paid, 'تاريخ الدفع') || '. لا يلزمكم أي إجراء آخر.' || E'\n\n'
      || 'أمام المورّد حتى ' || coalesce(v_decide, 'يوم العمل الخامس بعد الدفع') || ' للرد، وسنتابعه في يوم العمل الثالث مع نسخة إليكم، '
      || 'فإن لم يردّ، فسيوجّه إليه رئيسنا التنفيذي نداءً أخيرًا ثم يبتّ في حالتكم استنادًا إلى السجل. '
      || 'وإن ثبت استحقاق الاسترداد، فسيُردّ إليكم كامل ما دفعتموه (' || v_amt || ' درهم) إلى وسيلة الدفع الأصلية، وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهاره.',
    '{}', 'refund_request_received:' || t.id, null,
    jsonb_build_object('step', 'customer_request', 'transaction_id', t.id, 'refund_id', v_id));

  return jsonb_build_object('ok', true, 'refund_id', v_id, 'status', 'requested', 'locale', v_locale,
    'decision_after', t.refund_deadline, 'delivery_request', v_req, 'contact', v_word,
    'message_en', 'Refund case QD-RF-' || v_id || ' is open. Our chief executive decides it after ' || coalesce(v_decide, 'the fifth working day') || ', and if it is due everything you paid is refunded. We have emailed you the details.',
    'message_ar', 'فتحنا حالة الاسترداد QD-RF-' || v_id || '، وسيبتّ فيها رئيسنا التنفيذي بعد ' || coalesce(v_decide, 'يوم العمل الخامس') || '، وإن ثبت استحقاق الاسترداد فسيُردّ إليكم كامل ما دفعتموه. وقد أرسلنا إليكم التفاصيل بالبريد الإلكتروني.');
end $fn$;
revoke execute on function public.fn_refund_open_from_customer(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_refund_open_from_customer(uuid, text, text, text) to service_role;

-- ── 8. THE QUESTIONS: working day 2 asks about contact; day 3 asks it first ─────────────────────────────────────────
create or replace function public.fn_customer_followup_copy(p_stage text, p_lang text, p_name text, p_company text, p_rfq_no integer, p_trade text, p_link text)
returns jsonb language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
declare v_ar boolean := p_lang = 'ar'; v_name text; v_co text; v_when_en text; v_when_ar text;
begin
  v_name := coalesce(nullif(btrim(p_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
  v_co := coalesce(nullif(btrim(p_company), ''), case when v_ar then 'المورّد' else 'the supplier' end);
  -- WORKING DAY 2 (16 Nov 2026): the one person who knows whether the supplier called is asked, in plain words. The promise is
  -- clause 5 of the Terms as written: the chase on day 3, the refund if the supplier responds neither to him nor to us by day 5.
  if p_stage = 'day_two_contact' then
    if v_ar then
      return jsonb_build_object('lang', 'ar',
        'subject', 'هل تواصل معكم ' || v_co || '؟',
        'body', 'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
          || 'قبل يومي عمل كشفتم بيانات ' || v_co || ' لطلبكم رقم ' || coalesce(p_rfq_no::text, '-')
          || coalesce(' (' || nullif(btrim(p_trade), '') || ')', '') || '. هل تواصل معكم حتى الآن، هاتفيًا أو عبر واتساب أو البريد الإلكتروني أو بزيارة؟' || chr(10) || chr(10)
          || 'أخبرونا بنقرة واحدة: ' || p_link || chr(10) || chr(10)
          || 'وإن لم يتواصل معكم، فلا يلزمكم أي إجراء آخر: سنتابعه نيابةً عنكم في يوم العمل الثالث مع نسخة إليكم، وإن لم يردّ عليكم ولا علينا حتى يوم العمل الخامس بعد الدفع، فسيُردّ إليكم كامل ما دفعتموه مقابل الكشف (البند 5 من الشروط).' || chr(10) || chr(10)
          || 'وإن كنتم لا ترغبون في تلقّي مثل هذه الرسائل، فيكفي أن تردّوا على هذه الرسالة لنتوقف عن إرسالها.' || chr(10) || chr(10)
          || 'وتفضلوا بقبول فائق الاحترام والتقدير،');
    end if;
    return jsonb_build_object('lang', 'en',
      'subject', 'Has ' || v_co || ' contacted you?',
      'body', 'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Two working days ago you revealed ' || v_co || ' for your request RFQ-' || coalesce(p_rfq_no::text, '-')
        || coalesce(' (' || nullif(btrim(p_trade), '') || ')', '') || '. Have they contacted you yet, by phone, WhatsApp, e-mail or a visit?' || chr(10) || chr(10)
        || 'Tell us with one tap: ' || p_link || chr(10) || chr(10)
        || 'If they have not, you do not need to do anything else. We chase them for you on the third working day and copy you, and if they respond neither to you nor to us by the fifth working day after your payment, everything you paid for the reveal is refunded (clause 5 of our Terms).' || chr(10) || chr(10)
        || 'If you would rather not hear from us like this, reply to this e-mail and we will stop.');
  end if;
  v_when_en := case when p_stage = 'day_three' then 'A few days ago' else 'Two weeks ago' end;
  v_when_ar := case when p_stage = 'day_three' then 'قبل أيام' else 'قبل أسبوعين' end;
  if v_ar then
    return jsonb_build_object('lang', 'ar',
      'subject', 'هل تعاقدتم مع ' || v_co || '؟',
      'body', 'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || v_when_ar || ' كشفتم بيانات ' || v_co || ' لطلبكم رقم ' || coalesce(p_rfq_no::text, '-')
        || coalesce(' (' || nullif(btrim(p_trade), '') || ')', '') || '. هل تواصل معكم، وهل تعاقدتم معه، وكيف كانت تجربتكم مع المورّد؟' || chr(10) || chr(10)
        || 'أخبرونا بنقرة واحدة: ' || p_link || chr(10) || chr(10)
        || 'تساعدنا إجابتكم على مطابقتكم، ومطابقة كل عميل بعدكم، مع موردين أفضل.' || chr(10) || chr(10)
        || 'وإن كنتم لا ترغبون في تلقّي مثل هذه الرسائل، فيكفي أن تردّوا على هذه الرسالة لنتوقف عن إرسالها.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،');
  end if;
  return jsonb_build_object('lang', 'en',
    'subject', 'Did you hire ' || v_co || '?',
    'body', 'Dear ' || v_name || ',' || chr(10) || chr(10)
      || v_when_en || ' you revealed ' || v_co || ' for your request RFQ-' || coalesce(p_rfq_no::text, '-')
      || coalesce(' (' || nullif(btrim(p_trade), '') || ')', '') || '. Did they contact you, did you hire them, and how was the supplier?' || chr(10) || chr(10)
      || 'Tell us with one tap: ' || p_link || chr(10) || chr(10)
      || 'Your answer helps us match you, and every customer after you, with better suppliers.' || chr(10) || chr(10)
      || 'If you would rather not hear from us like this, reply to this e-mail and we will stop.');
end $fn$;
revoke execute on function public.fn_customer_followup_copy(text, text, text, text, integer, text, text) from public, anon, authenticated;
grant execute on function public.fn_customer_followup_copy(text, text, text, text, integer, text, text) to service_role;

create or replace function public.fn_customer_followup_view(p_token uuid)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((
    select jsonb_build_object('ok', true, 'lang', f.lang, 'stage', f.stage, 'company', l.company_name,
             'rfq_no', i.rfq_no, 'trade', public.fn_trade_label(coalesce(i.category, i.trades[1]), f.lang),
             'answered', f.answered_at is not null, 'hired', f.hired, 'stars', f.stars, 'contacted', f.contacted,
             -- the contact question is asked again only while the customer has not told us the supplier did contact him
             'contact_known', coalesce((public.fn_reveal_contact_word(t.id)->>'customer_confirms_contact')::boolean, false))
      from public.customer_followup f
      join public.transactions t on t.id = f.transaction_id
      left join public.leads l on l.id = t.supplier_id
      left join public.inquiries i on i.id = t.inquiry_id
     where f.token = p_token), jsonb_build_object('ok', false, 'reason', 'not_found'))
$fn$;
revoke execute on function public.fn_customer_followup_view(uuid) from public, anon, authenticated;
grant execute on function public.fn_customer_followup_view(uuid) to service_role;

-- ── 9. THE ANSWER: the contact word first; "never contacted" writes no review; a complaint after contact is read by the model ──
drop function if exists public.fn_customer_followup_answer(uuid, text, integer, text);
create or replace function public.fn_customer_followup_answer(p_token uuid, p_hired text, p_stars integer default null, p_comment text default null,
  p_contacted text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare f public.customer_followup; t public.transactions; v_comment text; v_reason text; v_out jsonb := '{}'::jsonb; v_won int := 0;
  v_rec jsonb; v_no_contact boolean := false; v_held bigint; v_statement text;
begin
  if p_contacted is not null and p_contacted not in ('yes', 'no', 'not_yet') then
    raise exception 'contacted is yes, no or not_yet' using errcode = '22023';
  end if;
  if p_stars is not null and p_stars not between 1 and 5 then
    raise exception 'stars are 1 to 5' using errcode = '22023';
  end if;
  select * into f from public.customer_followup where token = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select * into t from public.transactions where id = f.transaction_id;
  v_comment := nullif(left(btrim(coalesce(p_comment, '')), 1000), '');

  -- WORKING DAY 2: only the contact question. A "yes" stands; a "no" or "not yet" may be given again (after the supplier's click).
  if f.stage = 'day_two_contact' then
    if p_contacted is null then raise exception 'the working-day-2 question is answered yes, no or not_yet' using errcode = '22023'; end if;
    if f.contacted = 'yes' then return jsonb_build_object('ok', true, 'already', true, 'contacted', f.contacted); end if;
    v_rec := public.fn_reveal_contact_record(t.id, p_contacted, 'followup_page', v_comment, 'customer_followup:' || f.id);
    update public.customer_followup
       set answered_at = now(), contacted = p_contacted, comment = coalesce(v_comment, comment),
           outcome = coalesce(outcome, '{}'::jsonb) || jsonb_build_object('contact', v_rec)
     where id = f.id;
    return jsonb_build_object('ok', true, 'contacted', p_contacted, 'recorded', jsonb_build_object('contact', v_rec));
  end if;

  if p_hired is null or p_hired not in ('yes', 'no', 'not_yet') then
    raise exception 'hired is yes, no or not_yet' using errcode = '22023';
  end if;
  -- the first definite answer stands; a second tap on an old e-mail changes nothing
  if f.hired in ('yes', 'no') then return jsonb_build_object('ok', true, 'already', true, 'hired', f.hired); end if;

  -- THE CONTACT WORD FIRST (16 Nov 2026). "Never contacted" is the customer's word for the ladder, and it is not a record of dealing.
  if p_contacted is not null then
    v_rec := public.fn_reveal_contact_record(t.id, p_contacted, 'followup_page', v_comment, 'customer_followup:' || f.id);
    v_out := v_out || jsonb_build_object('contact', v_rec);
  end if;
  v_no_contact := coalesce((public.fn_reveal_contact_word(t.id)->>'customer_denies_contact')::boolean, false);

  if p_hired in ('yes', 'no') then
    v_reason := 'customer answered on ' || replace(f.stage, '_', ' ') || ': '
      || case when p_hired = 'yes' then 'hired the revealed supplier' else 'did not hire the revealed supplier' end
      || case when v_no_contact then ' (says the supplier never contacted them)' else '' end
      || coalesce(', rated ' || p_stars || '/5', '') || coalesce(': ' || left(v_comment, 300), '');
    if t.inquiry_id is not null then
      v_out := v_out || jsonb_build_object('inquiry', public.fn_outcome_record('inquiries', t.inquiry_id::text,
        case when p_hired = 'yes' then 'hired' else 'not_hired' end, p_hired = 'yes', v_reason, 'sales_engineer', 'inquiry', null));
    end if;
    if t.quote_id is not null then
      v_out := v_out || jsonb_build_object('quote', public.fn_outcome_record('quotes', t.quote_id::text,
        case when p_hired = 'yes' then 'hired' else 'not_hired' end, p_hired = 'yes', v_reason, 'sales_engineer', 'quote', null));
    end if;
    -- 10 Nov 2026 (sales_engineer): "yes, I hired them" COMPLETES the request, exactly as the portal's Hire does, and tells the
    -- losing suppliers. The write is the lock, as Hire's.
    if p_hired = 'yes' and t.inquiry_id is not null then
      update public.inquiries
         set status = 'completed', outcome = 'hired', completed_at = coalesce(completed_at, now()), hired_supplier_id = t.supplier_id
       where id = t.inquiry_id and (hired_supplier_id is null or hired_supplier_id = t.supplier_id)
         and coalesce(status, '') <> 'completed';
      get diagnostics v_won = row_count;
      if v_won > 0 then
        v_out := v_out || jsonb_build_object('completed', true, 'losers', public.fn_sales_engineer_tells_losing_suppliers(t.inquiry_id, t.supplier_id));
      end if;
    end if;
  end if;

  -- HOW WAS THE SUPPLIER: one rating per reveal, and only a rating of a supplier who did contact him (Supplier Agreement clause 13 is
  -- about performance). A "never contacted" answer keeps its stars and words on the follow-up row and goes to the ladder instead.
  if p_stars is not null and not v_no_contact and not exists (select 1 from public.reviews r where r.transaction_id = t.id) then
    insert into public.reviews (supplier_id, customer_id, inquiry_id, transaction_id, rating, comment)
    values (t.supplier_id, t.customer_id, t.inquiry_id, t.id, p_stars, case when length(v_comment) >= 10 then v_comment end);
    v_out := v_out || jsonb_build_object('review', true);
  elsif p_stars is not null and v_no_contact then
    v_out := v_out || jsonb_build_object('review', false, 'why_no_review', 'the customer says the supplier never contacted him');
  end if;

  -- A COMPLAINT AFTER CONTACT IS A CASE TO CONSIDER, READ BY THE MODEL (fn_customer_support_dispute_consider): a low rating, or a "not
  -- hired" with the customer's own words. Whether it needs a case is the model's reading of what he wrote, never a keyword.
  if not v_no_contact and (coalesce(p_stars, 5) <= 2 or (p_hired = 'no' and v_comment is not null)) then
    v_statement := 'Answered the follow-up on ' || replace(f.stage, '_', ' ') || ': '
      || case p_hired when 'yes' then 'hired the supplier' when 'no' then 'did not hire the supplier' else 'not decided yet' end
      || coalesce(', rated ' || p_stars || '/5', '') || coalesce('. In their words: ' || v_comment, '');
    v_held := public.fn_customer_support_dispute_consider(t.id, 'customer', v_statement, 'followup_page');
    v_out := v_out || jsonb_build_object('dispute_intake', v_held);
  end if;

  update public.customer_followup
     set answered_at = now(), hired = p_hired, stars = coalesce(p_stars, stars), comment = coalesce(v_comment, comment),
         contacted = coalesce(p_contacted, contacted), outcome = v_out
   where id = f.id;
  return jsonb_build_object('ok', true, 'hired', p_hired, 'contacted', p_contacted, 'recorded', v_out);
end $fn$;
revoke execute on function public.fn_customer_followup_answer(uuid, text, integer, text, text) from public, anon, authenticated;
grant execute on function public.fn_customer_followup_answer(uuid, text, integer, text, text) to service_role;

-- ── 10. WORKING DAY 2: ASK ─────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_customer_support_contact_check_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; r record; v jsonb; m jsonb;
  v_lang text; v_tok uuid; v_seen int := 0; v_sent int := 0;
  v_window int := coalesce((select refund_window_working_days from public.pricing_config order by id limit 1), 5);
begin
  for r in select t.id as tx, t.inquiry_id, t.revealed_at, c.id as cid, c.full_name, c.email, c.locale as customer_locale,
                  l.company_name, i.rfq_no, coalesce(i.category, i.trades[1]) as trade
             from public.transactions t
             join public.customers c on c.id = t.customer_id
             left join public.leads l on l.id = t.supplier_id
             left join public.inquiries i on i.id = t.inquiry_id
            where t.revealed_at is not null and coalesce(t.total_charged, t.reveal_fee, 0) > 0
              and t.revealed_at > now() - interval '21 days'
              -- from working day 2 until the ladder's own day 5: after that the final call has the floor
              and now() >= public.fn_add_working_days(t.revealed_at, 2)
              and now() < public.fn_add_working_days(t.revealed_at, v_window)
              -- a refund or a dispute is its own conversation (refund_status is 'window_open' on every reveal)
              and t.refund_requested_at is null
              and coalesce(t.refund_status, '') not in ('requested', 'pending', 'approved', 'processing', 'refunded', 'succeeded')
              and not exists (select 1 from public.post_reveal_dispute d where d.transaction_id = t.id)
              -- asked once (the supplier's acknowledgement notice carries the same question and counts)
              and not exists (select 1 from public.customer_followup f where f.transaction_id = t.id and f.stage = 'day_two_contact')
              -- nothing to ask when he already told us, on any door, that the supplier called, or he hired the supplier
              and not exists (select 1 from public.reveal_contact_statement s where s.transaction_id = t.id and s.said = 'yes')
              and not exists (select 1 from public.inquiries x where x.id = t.inquiry_id and x.hired_supplier_id = t.supplier_id)
              and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
            order by t.revealed_at limit 200 loop
    v_seen := v_seen + 1;
    -- the CUSTOMER's language (the request's, else the registered one); the supplier is only named in the copy
    v_lang := public.fn_customer_message_lang(r.inquiry_id, r.customer_locale);
    v_tok := gen_random_uuid();
    m := public.fn_customer_followup_copy('day_two_contact', v_lang, r.full_name, r.company_name, r.rfq_no,
           public.fn_trade_label(r.trade, v_lang), 'https://quotesdone.ae/u/followup?t=' || v_tok);
    v := public.fn_customer_support_duty_send('followup.day_two_contact', r.tx::text, 'customer', r.email, v_lang,
           m->>'subject', m->>'body', r.cid, null, r.inquiry_id);
    if coalesce((v->>'sent')::boolean, false) then
      insert into public.customer_followup (transaction_id, stage, token, lang) values (r.tx, 'day_two_contact', v_tok, v_lang)
      on conflict (transaction_id, stage) do nothing;
      v_sent := v_sent + 1;
    end if;
  end loop;
  return jsonb_build_object('due', v_seen, 'asked', v_sent, 'fixture', v_fx);
end $fn$;
revoke execute on function public.fn_customer_support_contact_check_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_contact_check_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.contact_check', 'sales_engineer', interval '2 hours', 'fn_customer_support_contact_check_tick',
   'on working day 2 after a reveal, support asks the customer whether the supplier has contacted him; his word is read by the refund ladder',
   'scripts/sql/a_paid_reveal_asks_the_customer_and_every_money_problem_reaches_a_case.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- ── 11. THE SUPPLIER'S "I HAVE CONTACTED THE CUSTOMER" GOES TO THE CUSTOMER (and to customer_support's record), NOT TO ADMIN ──
create or replace function public.fn_supplier_ack_record(p_transaction uuid)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.transactions; c record; v_co text; v_rfq int; v_lang text; v_tok uuid; v_link text; v jsonb; v_ar boolean; v_name text;
begin
  -- the moment of the click (clock time), so it orders against the customer's word exactly
  update public.transactions set supplier_ack_at = clock_timestamp() where id = p_transaction and supplier_ack_at is null returning * into t;
  if not found then return jsonb_build_object('recorded', false, 'already', true); end if;
  select cu.id, cu.full_name, cu.email, cu.locale, cu.banned into c from public.customers cu where cu.id = t.customer_id;
  select l.company_name into v_co from public.leads l where l.id = t.supplier_id;
  select i.rfq_no into v_rfq from public.inquiries i where i.id = t.inquiry_id;
  v_lang := public.fn_customer_message_lang(t.inquiry_id, c.locale);
  v_ar := v_lang = 'ar';
  -- the same one-tap question as working day 2: a customer who says "not contacted" after this click is a conflict for the CEO
  insert into public.customer_followup (transaction_id, stage, lang) values (t.id, 'day_two_contact', v_lang)
  on conflict (transaction_id, stage) do nothing;
  select f.token into v_tok from public.customer_followup f where f.transaction_id = t.id and f.stage = 'day_two_contact';
  v_link := 'https://quotesdone.ae/u/followup?t=' || v_tok;
  v_name := coalesce(nullif(btrim(c.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
  v_co := coalesce(nullif(btrim(v_co), ''), case when v_ar then 'المورّد' else 'the supplier' end);
  if not coalesce(c.banned, false) then
    v := public.fn_customer_support_duty_send('supplier_ack.customer', t.id::text, 'customer', c.email, v_lang,
      case when v_ar then v_co || ' يؤكد أنه تواصل معكم' else v_co || ' says they have contacted you' end,
      case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'أبلغنا ' || v_co || ' بأنه تواصل معكم بشأن طلبكم رقم ' || coalesce(v_rfq::text, '-') || '. إن كان ذلك صحيحًا، فلا يلزمكم أي إجراء.' || chr(10) || chr(10)
        || 'وإن لم يتواصل معكم، فأخبرونا بنقرة واحدة: ' || v_link || chr(10)
        || 'وسنواصل متابعته نيابةً عنكم، وإن لم يردّ عليكم ولا علينا حتى يوم العمل الخامس بعد الدفع، فسيُردّ إليكم كامل ما دفعتموه مقابل الكشف (البند 5 من الشروط).' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || v_co || ' has told us they have contacted you about your request RFQ-' || coalesce(v_rfq::text, '-') || '. If that is right, there is nothing you need to do.' || chr(10) || chr(10)
        || 'If they have not contacted you, tell us with one tap: ' || v_link || chr(10)
        || 'We keep chasing them for you, and if they respond neither to you nor to us by the fifth working day after your payment, everything you paid for the reveal is refunded (clause 5 of our Terms).' end,
      t.customer_id, null, t.inquiry_id);
  end if;
  return jsonb_build_object('recorded', true, 'transaction_id', t.id, 'customer_told', coalesce((v->>'sent')::boolean, false),
                            'delivery', v, 'contact', public.fn_reveal_contact_word(t.id));
end $fn$;
revoke execute on function public.fn_supplier_ack_record(uuid) from public, anon, authenticated;
grant execute on function public.fn_supplier_ack_record(uuid) to service_role;

-- ── 12. THE INTAKE: the quotation on record goes with the message, and the model chooses among four readings ───────
drop function if exists public.fn_customer_support_dispute_consider(uuid, text, text);
create or replace function public.fn_customer_support_dispute_consider(p_transaction_id uuid, p_party text, p_message text, p_channel text default 'email')
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.transactions; v_demo boolean; v_options jsonb;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found or t.revealed_at is null then raise exception 'a dispute is about a revealed job; % is not one', p_transaction_id; end if;
  if p_party not in ('customer', 'supplier') then raise exception 'the party is the customer or the supplier, not %', p_party; end if;
  if p_channel is null or p_channel not in ('followup_page', 'whatsapp', 'widget', 'portal', 'email') then
    raise exception 'the intake names its door (followup_page, whatsapp, widget, portal, email), not %', coalesce(p_channel, 'nothing');
  end if;
  select coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email) into v_demo from public.customers c where c.id = t.customer_id;
  v_options := case when p_party = 'customer' then jsonb_build_array(
      jsonb_build_object('id', 'supplier_contacted', 'meaning', 'the customer says the revealed supplier HAS contacted them (a call, a WhatsApp, an e-mail, a visit or a message) and raises nothing that needs a case'),
      jsonb_build_object('id', 'supplier_not_contacted', 'meaning', 'the customer says the revealed supplier has NOT contacted them since the reveal, or wants the reveal fee back because the supplier is silent'),
      jsonb_build_object('id', 'dispute', 'meaning', 'the supplier did deal with them, and the customer complains about the supplier''s conduct or work on this job and wants it put right: for example a price above the revealed quotation, a no-show, unfinished or poor work, or a warranty not honoured'),
      jsonb_build_object('id', 'not_dispute', 'meaning', 'a question, feedback or a request support can answer without opening a case'))
    else jsonb_build_array(
      jsonb_build_object('id', 'dispute', 'meaning', 'the party complains about the other party''s conduct or work on this job and wants it put right'),
      jsonb_build_object('id', 'not_dispute', 'meaning', 'a question, feedback or a request support can answer without involving the other party')) end;
  return public.fn_seat_duty_reason('customer_support', 'customer_support.dispute_intake',
    case when v_demo then 'ZZ DEMO ' else '' end
    || 'A party to a revealed job wrote to customer support. Read what they wrote beside the job on record (the revealed quotation the supplier is bound by, the supplier''s acknowledgement and the customer''s earlier word on contact). Which of these is it?',
    v_options,
    jsonb_build_object('party', p_party, 'channel', p_channel, 'message', left(p_message, 4000), 'revealed_at', t.revealed_at,
                       'transaction_id', t.id, 'inquiry_id', t.inquiry_id, 'job_on_record', public.fn_reveal_job_facts(t.id),
                       'contact_on_record', public.fn_reveal_contact_word(t.id)),
    jsonb_build_object('transaction_id', t.id, 'party', p_party, 'statement', left(p_message, 4000), 'channel', p_channel),
    'dispute_intake:' || t.id || ':' || md5(p_party || coalesce(p_message, '')));
end $fn$;
revoke execute on function public.fn_customer_support_dispute_consider(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_customer_support_dispute_consider(uuid, text, text, text) to service_role;

-- ── 13. THE CASE CARRIES THE QUOTATION, AND BOTH NOTICES SAY WHAT WAS QUOTED (Complaints Policy s.4: sharing the records) ──
create or replace function public.fn_customer_support_dispute_open(p_transaction_id uuid, p_raised_by text, p_statement text, p_intake_question_id bigint default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.transactions; d public.post_reveal_dispute; c record; s record; v_ref text; v_rfq text; v_due text; v_job jsonb;
  v_quote_en text; v_quote_ar text; v_channel text;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found or t.revealed_at is null then raise exception 'a dispute is about a revealed job; % is not one', p_transaction_id; end if;
  select * into d from public.post_reveal_dispute where transaction_id = t.id and stage <> 'decided';
  if found then return jsonb_build_object('dispute_id', d.id, 'opened', false, 'reason', 'a case is already open on this job'); end if;
  v_job := public.fn_reveal_job_facts(t.id);
  v_channel := (select h.subject->>'channel' from public.reasoning_held_question h where h.id = p_intake_question_id);
  insert into public.post_reveal_dispute (transaction_id, inquiry_id, customer_id, supplier_id, raised_by, statement,
                                          evidence_due, intake_question_id, job_facts, channel)
  values (t.id, t.inquiry_id, t.customer_id, t.supplier_id, p_raised_by, left(p_statement, 4000),
          public.fn_add_working_days(now(), 5), p_intake_question_id, v_job, v_channel)
  returning * into d;
  if p_raised_by = 'customer' then d.customer_evidence := jsonb_build_object('statement', d.statement, 'at', now());
  else d.supplier_evidence := jsonb_build_object('statement', d.statement, 'at', now()); end if;
  update public.post_reveal_dispute set customer_evidence = d.customer_evidence, supplier_evidence = d.supplier_evidence where id = d.id;

  v_ref := 'QD-D-' || lpad(d.id::text, 5, '0');
  select coalesce(i.rfq_no::text, left(i.id::text, 8)) into v_rfq from public.inquiries i where i.id = t.inquiry_id;
  v_due := to_char(d.evidence_due at time zone 'Asia/Dubai', 'DD/MM/YYYY HH24:MI');
  -- THE QUOTATION ON RECORD, in one sentence each side reads (the supplier is bound by it: Supplier Agreement v17 clause 9)
  v_quote_en := 'The quotation on record: AED ' || coalesce(v_job->'quote'->>'amount_aed', '-')
    || coalesce('; warranty: ' || (v_job->'quote'->>'warranty'), '') || coalesce('; lead time: ' || (v_job->'quote'->>'lead_time'), '')
    || coalesce('; validity: ' || (v_job->'quote'->>'validity'), '') || '. ';
  v_quote_ar := 'عرض السعر المسجّل لدينا: ' || coalesce(v_job->'quote'->>'amount_aed', '-') || ' درهم'
    || coalesce('، الضمان: ' || (v_job->'quote'->>'warranty'), '') || coalesce('، مدة التنفيذ: ' || (v_job->'quote'->>'lead_time'), '')
    || coalesce('، الصلاحية: ' || (v_job->'quote'->>'validity'), '') || '. ';
  select c2.email, c2.locale into c from public.customers c2 where c2.id = t.customer_id;
  select coalesce(l.claimed_by, l.email) as email into s from public.leads l where l.id = t.supplier_id;
  perform public.fn_customer_support_duty_send('dispute.opened', d.id || ':' || role, role, email,
      case when locale = 'ar' then 'ar' else 'en' end,
      case when locale = 'ar' then 'فُتحت القضية ' || v_ref || ' بشأن مشروعكم على QuotesDone'
           else 'Dispute ' || v_ref || ' opened on your QuotesDone job' end,
      case when locale = 'ar' then
        'السادة المحترمين،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'فُتحت القضية ' || v_ref || ' بشأن المشروع المرتبط بالطلب رقم ' || coalesce(v_rfq, '') || '، ولن يُتخذ أي قرار قبل الاستماع إلى الطرفين. '
        || v_quote_ar
        || 'نرجو الرد على هذه الرسالة بروايتكم لما حدث، مع ما يدعمها من مستندات أو صور أو مراسلات، في موعد أقصاه ' || v_due || ' بتوقيت دبي. '
        || 'وإن لم يصلنا شيء حتى ذلك الموعد، فستُراجَع القضية بناءً على ما لدينا.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Hello,' || chr(10) || chr(10)
        || 'Dispute ' || v_ref || ' has been opened about the job for request ' || coalesce(v_rfq, '') || '. Nothing will be decided before both sides are heard. '
        || v_quote_en
        || 'Please reply to this e-mail with your account of what happened and any documents, photos or messages that support it by ' || v_due || ' Dubai time. '
        || 'If nothing arrives by then, the case is reviewed on what we already have.' end,
      case when role = 'customer' then t.customer_id end, case when role = 'supplier' then t.supplier_id end, t.inquiry_id)
    from (values ('customer', c.email, coalesce(public.fn_inquiry_locale(t.inquiry_id), c.locale)),   -- the customer: the inquiry's language (28 Sep 2026)
          ('supplier', s.email, 'en')   -- suppliers are always written in English (founder, 28 Sep 2026)
         ) p(role, email, locale);
  return jsonb_build_object('dispute_id', d.id, 'ref', v_ref, 'opened', true, 'evidence_due', d.evidence_due);
end $fn$;
revoke execute on function public.fn_customer_support_dispute_open(uuid, text, text, bigint) from public, anon, authenticated;
grant execute on function public.fn_customer_support_dispute_open(uuid, text, text, bigint) to service_role;

-- ── 14. WHAT THE INTAKE'S READING DOES ─────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_reason_apply_customer_support__dispute_intake(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_tx uuid; v_ch text; v_stmt text;
  v_rec jsonb; v_rf jsonb; v_c record; v_lang text; v_told jsonb;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if v_choice is null or v_choice not in ('dispute', 'not_dispute', 'supplier_contacted', 'supplier_not_contacted')
     or (coalesce(h.subject->>'party', 'customer') = 'supplier' and v_choice not in ('dispute', 'not_dispute')) then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again.
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  v_tx := (h.subject->>'transaction_id')::uuid;
  v_ch := coalesce(h.subject->>'channel', 'email');
  v_stmt := h.subject->>'statement';
  if v_choice = 'not_dispute' then return jsonb_build_object('applied', true, 'opened', false); end if;
  if v_choice = 'supplier_contacted' then
    v_rec := public.fn_reveal_contact_record(v_tx, 'yes', v_ch, v_stmt, 'held_question:' || p_id);
    return jsonb_build_object('applied', true, 'opened', false, 'contact', v_rec);
  end if;
  if v_choice = 'supplier_not_contacted' then
    -- his word, then the one refund door (Refund Policy v1.9 s.5: tell us at any time). The door records the same word itself;
    -- the ten-minute rule in fn_reveal_contact_record keeps it one statement.
    v_rec := public.fn_reveal_contact_record(v_tx, 'no', v_ch, v_stmt, 'held_question:' || p_id);
    v_rf := public.fn_refund_open_from_customer(v_tx, 'customer', 'The customer wrote (' || v_ch || '): ' || left(v_stmt, 1500), v_ch);
    if not coalesce((v_rf->>'ok')::boolean, false) then
      -- a refusal reached through a message is told to him in his language, with its reason: nobody is left waiting on nothing
      select cu.id, cu.email, cu.locale, t.inquiry_id into v_c from public.transactions t join public.customers cu on cu.id = t.customer_id where t.id = v_tx;
      v_lang := coalesce(v_rf->>'locale', 'en');
      v_told := public.fn_customer_support_duty_send('refund.refused_after_message', p_id::text, 'customer', v_c.email, v_lang,
        case when v_lang = 'ar' then 'بشأن رسالتكم عن المورّد' else 'About your message on the supplier' end,
        case when v_lang = 'ar' then v_rf->>'message_ar' else v_rf->>'message_en' end, v_c.id, null, v_c.inquiry_id);
    end if;
    return jsonb_build_object('applied', true, 'opened', coalesce((v_rf->>'ok')::boolean, false), 'contact', v_rec, 'refund', v_rf, 'told', v_told);
  end if;
  return public.fn_customer_support_dispute_open(v_tx, h.subject->>'party', v_stmt, p_id);
end $fn$;
revoke execute on function public.fn_reason_apply_customer_support__dispute_intake(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_customer_support__dispute_intake(bigint, jsonb) to service_role;

-- ── 15. THE ONE DOOR: "A PROBLEM WITH THIS JOB" (portal, WhatsApp, the signed-in widget) ────────────────────────────
create or replace function public.fn_customer_after_reveal_message(p_customer uuid, p_message text, p_channel text, p_transaction uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.customers; t public.transactions; v_body text; v_n int; v_refs text; v_held bigint; v_rfq text; v_lang text;
  v_open_d text; v_open_r text;
begin
  if p_channel is null or p_channel not in ('portal', 'whatsapp', 'widget', 'email', 'followup_page') then
    raise exception 'the door is portal, whatsapp, widget, email or followup_page, not %', coalesce(p_channel, 'nothing') using errcode = '22023';
  end if;
  select * into c from public.customers where id = p_customer;
  if not found then return jsonb_build_object('ok', false, 'code', 'no_customer'); end if;
  if btrim(coalesce(p_message, '')) = '' then
    return jsonb_build_object('ok', false, 'code', 'empty', 'locale', coalesce(c.locale, 'en'),
      'message_en', 'Tell us what happened with the supplier, in your own words, and we will take it from there.',
      'message_ar', 'أخبرونا بما حدث مع المورّد بكلماتكم، وسنتولى الأمر من هناك.');
  end if;
  if p_transaction is not null then
    select * into t from public.transactions where id = p_transaction and customer_id = p_customer and revealed_at is not null;
    if not found then return jsonb_build_object('ok', false, 'code', 'not_your_revealed_job', 'locale', coalesce(c.locale, 'en'),
      'message_en', 'We could not find that revealed job on your account.', 'message_ar', 'لم نعثر على هذا العمل المكشوف في حسابكم.'); end if;
  else
    -- WHICH JOB: a request number he wrote (format, read as fn_wa_customer_request_answer reads one), else his only revealed job.
    v_body := translate(coalesce(p_message, ''), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789');
    select x.* into t from public.transactions x join public.inquiries i on i.id = x.inquiry_id
     where x.customer_id = p_customer and x.revealed_at is not null and x.revealed_at > now() - interval '400 days'
       and exists (select 1 from regexp_matches(v_body, '(?<![0-9])([0-9]{2,9})(?![0-9])', 'g') m where m[1]::bigint = i.rfq_no)
     order by x.revealed_at desc limit 1;
    if t.id is null then
      select count(*), string_agg(coalesce(i.rfq_no::text, '?'), ', ' order by x.revealed_at desc) into v_n, v_refs
        from public.transactions x left join public.inquiries i on i.id = x.inquiry_id
       where x.customer_id = p_customer and x.revealed_at is not null and x.revealed_at > now() - interval '400 days';
      if v_n = 0 then
        return jsonb_build_object('ok', false, 'code', 'no_revealed_job', 'locale', coalesce(c.locale, 'en'),
          'message_en', 'You have no revealed supplier on your account, so there is no job to open a case on. If this is about a request before a reveal, tell us its number.',
          'message_ar', 'لا يوجد في حسابكم مورّد مكشوف، فلا يوجد عمل نفتح بشأنه قضية. وإن كان الأمر يتعلق بطلب قبل الكشف، فأخبرونا برقمه.');
      elsif v_n > 1 then
        return jsonb_build_object('ok', false, 'code', 'which_job', 'refs', v_refs, 'locale', coalesce(c.locale, 'en'),
          'message_en', 'Which request is this about? Your requests with a revealed supplier: ' || v_refs || '. Reply with the request number and what happened.',
          'message_ar', 'بأي طلب يتعلق الأمر؟ طلباتكم التي كشفتم فيها مورّدًا: ' || v_refs || '. يُرجى الرد برقم الطلب وما حدث.');
      end if;
      select x.* into t from public.transactions x
       where x.customer_id = p_customer and x.revealed_at is not null and x.revealed_at > now() - interval '400 days' limit 1;
    end if;
  end if;
  select i.rfq_no::text into v_rfq from public.inquiries i where i.id = t.inquiry_id;
  v_lang := public.fn_customer_message_lang(t.inquiry_id, c.locale);
  -- a case already open on this job is named, and the message still goes to the intake (it may be new evidence or a new matter)
  select 'QD-D-' || lpad(d.id::text, 5, '0') into v_open_d from public.post_reveal_dispute d where d.transaction_id = t.id and d.stage <> 'decided' limit 1;
  select 'QD-RF-' || r.id into v_open_r from public.refunds r where r.transaction_id = t.id and r.status not in ('rejected', 'failed', 'cancelled')
     and r.settled_at is null and lower(coalesce(r.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by r.id limit 1;
  v_held := public.fn_customer_support_dispute_consider(t.id, 'customer', p_message, p_channel);
  return jsonb_build_object('ok', true, 'transaction_id', t.id, 'rfq_no', v_rfq, 'held_question_id', v_held, 'fixture', v_held is null,
    'open_dispute', v_open_d, 'open_refund', v_open_r, 'locale', v_lang,
    'message_en', 'Thank you. What you wrote about request ' || coalesce(v_rfq, '') || ' is with customer support, together with the supplier''s quotation on record (its price, scope and warranty). '
      || coalesce('Your case ' || coalesce(v_open_d, v_open_r) || ' is already open and this is added to it. ', '')
      || 'Support reads it and either opens a case and gives you its reference, or answers you directly, within two working days, as our Complaints Policy promises.',
    'message_ar', 'شكرًا لكم. وصل ما كتبتموه بشأن الطلب رقم ' || coalesce(v_rfq, '') || ' إلى خدمة العملاء، ومعه عرض السعر المسجّل للمورّد (السعر والنطاق والضمان). '
      || coalesce('وقضيتكم ' || coalesce(v_open_d, v_open_r) || ' مفتوحة بالفعل، وأُضيفت إليها رسالتكم. ', '')
      || 'وستقرؤها خدمة العملاء، فإما أن تفتح قضية وتبلغكم برقمها، أو تردّ عليكم مباشرة، خلال يومي عمل كما تَعِد سياسة الشكاوى لدينا.');
end $fn$;
revoke execute on function public.fn_customer_after_reveal_message(uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function public.fn_customer_after_reveal_message(uuid, text, text, uuid) to service_role;

-- ── 16. THE CEO'S DECISION ACTS ────────────────────────────────────────────────────────────────────────────────────
-- The live body (the mirror) plus: what the CEO chose for the customer (p_remedy) and for the supplier (p_supplier_action), both only
-- on an upheld or shared complaint; a strike event on the supplier's standing record whenever the complaint is upheld or shared.
--   refund_reveal_fee: fn_refund_request (reason fraud_or_dispute, requested_by ceo_dispute_decision), the one refund door.
--   next_reveal_free:  the next supplier he reveals on this request is refunded in full (reason goodwill), filed by
--                      fn_accountant_dispute_remedy_tick when he pays it. No zero-fee reveal exists, so the refund is the remedy.
--   warning:           a formal warning in the supplier's decision notice (Supplier Agreement v17 clauses 8 and 19).
--   pause_matching:    leads.matching_blocked with reason dispute_upheld (clause 19: suspend for breach); lifted by a person.
drop function if exists public.fn_ceo_decides_post_reveal_dispute(bigint, text, text);
create or replace function public.fn_ceo_decides_post_reveal_dispute(p_id bigint, p_outcome text, p_note text,
  p_remedy text default 'none', p_supplier_action text default 'none')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.post_reveal_dispute; t public.transactions; c record; s record; v_ref text; v_en text; v_ar text; v_effect jsonb := '{}'::jsonb;
  v_rem_en text := ''; v_rem_ar text := ''; v_sup_en text := ''; v_upheld boolean; v_rf jsonb; v_strikes int; v_paused int := 0;
begin
  if p_outcome is null or p_outcome not in ('customer_upheld', 'supplier_upheld', 'shared', 'no_fault') then
    raise exception 'the outcome is customer_upheld, supplier_upheld, shared or no_fault, not %', p_outcome;
  end if;
  if coalesce(p_remedy, 'none') not in ('none', 'refund_reveal_fee', 'next_reveal_free') then
    raise exception 'the remedy is none, refund_reveal_fee or next_reveal_free, not %', p_remedy;
  end if;
  if coalesce(p_supplier_action, 'none') not in ('none', 'warning', 'pause_matching') then
    raise exception 'the supplier action is none, warning or pause_matching, not %', p_supplier_action;
  end if;
  v_upheld := p_outcome in ('customer_upheld', 'shared');
  if not v_upheld and (coalesce(p_remedy, 'none') <> 'none' or coalesce(p_supplier_action, 'none') <> 'none') then
    raise exception 'a remedy or a supplier action follows only a complaint that is upheld or shared, not %', p_outcome;
  end if;
  update public.post_reveal_dispute set stage = 'decided', outcome = p_outcome, outcome_note = p_note,
         decided_by = 'ceo', decided_at = now(), remedy = coalesce(p_remedy, 'none'), supplier_action = coalesce(p_supplier_action, 'none')
   where id = p_id and stage in ('review', 'ceo_decision') returning * into d;
  if not found then raise exception 'dispute % is not awaiting a decision', p_id; end if;
  update public.it_engineer_finding set closed_at = now(), close_note = 'the CEO decided the dispute'
   where issue_key = 'dispute_decision_overdue:' || p_id and closed_at is null;
  select * into t from public.transactions where id = d.transaction_id;
  v_ref := 'QD-D-' || lpad(d.id::text, 5, '0');

  -- SUPPLIER STANDING: an upheld (or shared) complaint is on the supplier's record, append-only; the count of chat strikes (the
  -- no-quote rule) is not changed by it.
  if v_upheld then
    select coalesce(l.chat_strikes, 0) into v_strikes from public.leads l where l.id = d.supplier_id;
    insert into public.supplier_strike_event (lead_id, inquiry_id, kind, strikes_after, detail)
    values (d.supplier_id, d.inquiry_id, 'dispute_upheld', coalesce(v_strikes, 0),
            jsonb_build_object('dispute_id', d.id, 'ref', v_ref, 'outcome', p_outcome, 'supplier_action', coalesce(p_supplier_action, 'none'),
                               'rule', 'Supplier Agreement v17 clauses 8 and 19'));
    v_effect := v_effect || jsonb_build_object('strike_event', true);
  end if;
  if p_supplier_action = 'pause_matching' then
    update public.leads set matching_blocked = true, matching_block_reason = 'dispute_upheld'
     where id = d.supplier_id and not coalesce(matching_blocked, false);
    get diagnostics v_paused = row_count;
    v_effect := v_effect || jsonb_build_object('matching_paused', v_paused > 0);
    v_sup_en := ' Under clause 19 of the Supplier Agreement your account is paused from new requests until we have reviewed it with you; reply to this e-mail to arrange that.';
  elsif p_supplier_action = 'warning' then
    v_sup_en := ' This is a formal warning under clauses 8 and 19 of the Supplier Agreement: a supplier must honour every quotation it submits and any agreed timeline, and a further breach may lead to suspension.';
  end if;

  -- THE CUSTOMER'S REMEDY
  if p_remedy = 'refund_reveal_fee' then
    if exists (select 1 from public.refunds r where r.transaction_id = t.id and r.status not in ('rejected', 'failed', 'cancelled')) then
      v_effect := v_effect || jsonb_build_object('refund', 'already_open');
    else
      v_rf := public.fn_refund_request(round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint, 'fraud_or_dispute', 'ceo_dispute_decision',
        t.inquiry_id, t.customer_id, t.supplier_id, t.quote_id, t.payment_ref, null,
        'Dispute ' || v_ref || ' decided ' || p_outcome || ' by the CEO, who chose to refund the reveal fee. ' || coalesce(left(p_note, 1500), ''), t.id);
      v_effect := v_effect || jsonb_build_object('refund', v_rf);
    end if;
    update public.post_reveal_dispute set remedy_transaction_id = t.id, remedy_done_at = now() where id = d.id;
    v_rem_en := ' As a result, everything you paid for this reveal is refunded to your original payment method; banks take 7 to 14 working days to show it.';
    v_rem_ar := ' وبناءً عليه، يُردّ إليكم كامل ما دفعتموه مقابل هذا الكشف إلى وسيلة الدفع الأصلية، وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهاره.';
  elsif p_remedy = 'next_reveal_free' then
    v_rem_en := ' As a result, if you reveal another supplier''s quotation on this request, everything you pay for that reveal is refunded in full; the refund is filed as soon as you pay.';
    v_rem_ar := ' وبناءً عليه، إن كشفتم عرض مورّد آخر على هذا الطلب، فسيُردّ إليكم كامل ما تدفعونه مقابل ذلك الكشف، ويُقدَّم طلب الاسترداد فور الدفع.';
  end if;
  update public.post_reveal_dispute set effect = v_effect where id = d.id;

  v_en := case p_outcome when 'customer_upheld' then 'the customer''s complaint is upheld'
    when 'supplier_upheld' then 'the supplier''s position is upheld' when 'shared' then 'responsibility is shared by both parties'
    else 'no fault was found on either side' end;
  v_ar := case p_outcome when 'customer_upheld' then 'قُبلت شكوى العميل'
    when 'supplier_upheld' then 'ثبت موقف المورّد' when 'shared' then 'المسؤولية مشتركة بين الطرفين'
    else 'لم يثبت تقصير على أي من الطرفين' end;
  select c2.email, c2.locale into c from public.customers c2 where c2.id = d.customer_id;
  select coalesce(l.claimed_by, l.email) as email into s from public.leads l where l.id = d.supplier_id;
  perform public.fn_customer_support_duty_send('dispute.decided', d.id || ':' || role, role, email,
      case when locale = 'ar' then 'ar' else 'en' end,
      case when locale = 'ar' then 'القرار في القضية ' || v_ref else 'Dispute ' || v_ref || ': the decision' end,
      case when locale = 'ar' then
        'السادة المحترمين،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'راجعنا القضية ' || v_ref || ' بعد الاطلاع على أقوال الطرفين ومستنداتهما، وانتهت المراجعة إلى أنه ' || v_ar || '.' || v_rem_ar || ' '
        || 'وإن كان لديكم اعتراض على القرار، فيسعدنا أن تردّوا على هذه الرسالة خلال عشرة أيام عمل.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Hello,' || chr(10) || chr(10)
        || 'We have reviewed dispute ' || v_ref || ' on the statements and evidence of both parties. The outcome: ' || v_en || '.'
        || case when role = 'customer' then v_rem_en else v_sup_en end || ' '
        || 'If you disagree with the decision, reply to this e-mail within 10 working days.' end,
      case when role = 'customer' then d.customer_id end, case when role = 'supplier' then d.supplier_id end, d.inquiry_id)
    from (values ('customer', c.email, coalesce(public.fn_inquiry_locale(d.inquiry_id), c.locale)),   -- the customer: the inquiry's language (28 Sep 2026)
          ('supplier', s.email, 'en')   -- suppliers are always written in English (founder, 28 Sep 2026)
         ) p(role, email, locale);
  return jsonb_build_object('dispute_id', d.id, 'outcome', p_outcome, 'remedy', coalesce(p_remedy, 'none'),
                            'supplier_action', coalesce(p_supplier_action, 'none'), 'effect', v_effect);
end $fn$;
revoke execute on function public.fn_ceo_decides_post_reveal_dispute(bigint, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_decides_post_reveal_dispute(bigint, text, text, text, text) to service_role;

-- ── 17. THE NEXT REVEAL REFUNDED: filed when he pays it ────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_dispute_remedy_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; d record; x public.transactions;
  v_rf jsonb; v_seen int := 0; v_filed int := 0;
begin
  for d in select p.*, 'QD-D-' || lpad(p.id::text, 5, '0') as ref from public.post_reveal_dispute p
             join public.customers c on c.id = p.customer_id
            where p.stage = 'decided' and p.remedy = 'next_reveal_free' and p.remedy_done_at is null
              and p.decided_at > now() - interval '180 days'
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
            order by p.id for update of p skip locked loop
    v_seen := v_seen + 1;
    select t.* into x from public.transactions t
     where t.customer_id = d.customer_id and t.id <> d.transaction_id and t.revealed_at > d.decided_at
       and coalesce(t.total_charged, t.reveal_fee, 0) > 0 and coalesce(btrim(t.payment_ref), '') <> ''
       and t.inquiry_id in (select i.id from public.inquiries i, public.inquiries root
                             where root.id = d.inquiry_id and coalesce(i.parent_inquiry_id, i.id) = coalesce(root.parent_inquiry_id, root.id))
     order by t.revealed_at limit 1;
    continue when x.id is null;
    if not exists (select 1 from public.refunds r where r.transaction_id = x.id and r.status not in ('rejected', 'failed', 'cancelled')) then
      v_rf := public.fn_refund_request(round(coalesce(x.total_charged, x.reveal_fee, 0) * 100)::bigint, 'goodwill', 'ceo_dispute_decision',
        x.inquiry_id, x.customer_id, x.supplier_id, x.quote_id, x.payment_ref, null,
        'Dispute ' || d.ref || ' was decided ' || d.outcome || ' by the CEO with the remedy: the next reveal on this request is refunded in full. This is that reveal.', x.id);
      v_filed := v_filed + 1;
    end if;
    update public.post_reveal_dispute set remedy_transaction_id = x.id, remedy_done_at = now(),
           effect = coalesce(effect, '{}'::jsonb) || jsonb_build_object('next_reveal_refund', coalesce(v_rf, '"already open"'::jsonb))
     where id = d.id;
  end loop;
  return jsonb_build_object('due', v_seen, 'filed', v_filed, 'fixture', v_fx);
end $fn$;
revoke execute on function public.fn_accountant_dispute_remedy_tick() from public, anon, authenticated;
grant execute on function public.fn_accountant_dispute_remedy_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('accountant.dispute_remedy', 'accountant', interval '1 hour', 'fn_accountant_dispute_remedy_tick',
   'a dispute the CEO decided with "the next reveal refunded": when the customer pays that reveal, its refund is filed through fn_refund_request',
   'scripts/sql/a_paid_reveal_asks_the_customer_and_every_money_problem_reaches_a_case.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- ── 18. WHAT A DISPUTE REFUND STANDS ON (for the CEO's refund checklist, another branch: wired by the main session) ──
-- A refund filed by the CEO's own dispute decision is not a non-response refund; the checklist's item 5 must not exclude it as
-- "price dissatisfaction". The main session adds: `and public.fn_refund_dispute_basis(t.id) is null` to that exclusion.
create or replace function public.fn_refund_dispute_basis(p_transaction uuid)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('dispute_id', d.id, 'ref', 'QD-D-' || lpad(d.id::text, 5, '0'), 'outcome', d.outcome, 'remedy', d.remedy,
                            'decided_at', d.decided_at, 'decided_by', d.decided_by)
    from public.post_reveal_dispute d
   where d.stage = 'decided' and d.outcome in ('customer_upheld', 'shared')
     and ((d.remedy = 'refund_reveal_fee' and d.transaction_id = p_transaction)
       or (d.remedy = 'next_reveal_free' and d.remedy_transaction_id = p_transaction))
   order by d.id desc limit 1
$fn$;
revoke execute on function public.fn_refund_dispute_basis(uuid) from public, anon, authenticated;
grant execute on function public.fn_refund_dispute_basis(uuid) to service_role;

-- ── 19. HIS MONEY CASES, FOR EVERY CHANNEL'S FACTS (wired by the main session beside fn_customer_inquiry_facts) ──────
create or replace function public.fn_customer_money_cases(p_customer uuid)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'customer_id', p_customer, 'as_of', now(),
    'refunds', coalesce((select jsonb_agg(jsonb_build_object(
        'ref', 'QD-RF-' || r.id, 'rfq_no', i.rfq_no, 'status', r.status, 'reason', r.reason_code, 'requested_at', r.requested_at,
        'decide_after', t.refund_deadline, 'decided_at', r.decided_at, 'settled_at', r.settled_at,
        'amount_aed', round(coalesce(r.amount_fils, 0) / 100.0, 2), 'open', r.decided_at is null or r.settled_at is null) order by r.id desc)
      from public.refunds r left join public.transactions t on t.id = r.transaction_id left join public.inquiries i on i.id = coalesce(r.inquiry_id, t.inquiry_id)
     where r.customer_id = p_customer and lower(coalesce(r.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe')
       and (r.settled_at is null or r.settled_at > now() - interval '90 days')
       and r.status not in ('cancelled')), '[]'::jsonb),
    'disputes', coalesce((select jsonb_agg(jsonb_build_object(
        'ref', 'QD-D-' || lpad(d.id::text, 5, '0'), 'rfq_no', i.rfq_no, 'stage', d.stage, 'raised_by', d.raised_by, 'opened_at', d.opened_at,
        'evidence_due', d.evidence_due, 'decision_due', d.decision_due, 'outcome', d.outcome, 'remedy', d.remedy, 'decided_at', d.decided_at)
        order by d.id desc)
      from public.post_reveal_dispute d left join public.inquiries i on i.id = d.inquiry_id
     where d.customer_id = p_customer and (d.decided_at is null or d.decided_at > now() - interval '90 days')), '[]'::jsonb),
    'being_read', coalesce((select jsonb_agg(jsonb_build_object('since', h.created_at, 'rfq_no', i.rfq_no, 'what', 'his message about a revealed job is with customer support to read'))
      from public.reasoning_held_question h join public.transactions t on t.id = (h.subject->>'transaction_id')::uuid
      left join public.inquiries i on i.id = t.inquiry_id
     where h.surface = 'customer_support.dispute_intake' and h.status = 'held' and t.customer_id = p_customer), '[]'::jsonb),
    'revealed_jobs', coalesce((select jsonb_agg(jsonb_build_object(
        'rfq_no', i.rfq_no, 'revealed_at', t.revealed_at, 'supplier', l.company_name,
        'ladder', st->>'state', 'refund_window_ends', t.refund_deadline, 'supplier_ack_at', t.supplier_ack_at,
        'customer_said', st->>'customer_said', 'contact_conflict', (st->>'contact_conflict')::boolean) order by t.revealed_at desc)
      from public.transactions t left join public.inquiries i on i.id = t.inquiry_id left join public.leads l on l.id = t.supplier_id
      cross join lateral (select public.fn_refund_state(t.id) as st) z
     where t.customer_id = p_customer and t.revealed_at > now() - interval '120 days'), '[]'::jsonb))
$fn$;
revoke execute on function public.fn_customer_money_cases(uuid) from public, anon, authenticated;
grant execute on function public.fn_customer_money_cases(uuid) to service_role;

-- ── 20. WHATSAPP: ONE REASONED INTENT, ACTED ON BY THE DOOR ───────────────────────────────────────────────────────
-- The model reads which intent a message is (wa_inbound/classification.ts whatsappReadings, by the row's label); match_patterns are
-- not read since 23 Sep 2026. The template is for a sender who is not a confirmed customer (a supplier, an unknown number).
insert into public.wa_reply_intent (intent_key, label, sort, match_patterns, requires_identity, scope, answer_template, resolver_note, active)
values ('after_reveal',
  'about a job whose supplier they already revealed and paid for: whether the supplier has contacted them, the reveal fee back because the supplier is silent, or a problem with that supplier (a price above the quotation, a no-show, unfinished or poor work, a warranty not honoured)',
  95, '{}'::text[], true, 'own_records',
  'If this is about a job whose supplier you revealed, tell me the request number and what happened, and customer support opens a case with the quotation on record.',
  'a confirmed customer: fn_customer_after_reveal_message (the dispute intake with the quotation on record); anyone else: this template',
  true)
on conflict (intent_key) do update set label = excluded.label, sort = excluded.sort, requires_identity = excluded.requires_identity,
  scope = excluded.scope, answer_template = excluded.answer_template, resolver_note = excluded.resolver_note, active = true;

-- fn_wa_answer: the live body (the mirror) plus ONE branch, before a confirmed customer's own-record answers.
create or replace function public.fn_wa_answer(p_from text, p_body text, p_intent text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_body     text := lower(btrim(coalesce(p_body, '')));
  v_intent   public.wa_reply_intent;
  v_reply    text;
  v_lead     record;
  v_lead_id  bigint;
  v_cust     uuid;
  v_ident_k  text := 'unknown';
  v_ident_id text := null;
  v_id       bigint;
  v_missing  text;
  v_cfg      record;
  v_log      bigint;
  v_ans      jsonb;
begin
  if v_body = '' then
    return jsonb_build_object('ok', false, 'reason', 'Empty message.');
  end if;

  select standard_reveal_rate, supplier_free_count, supplier_reg_fee into v_cfg
    from public.pricing_config order by id limit 1;

  -- WHO IS ASKING. Identity gates every 'own_records' answer, so one supplier can never be told
  -- another supplier's business by sending a lucky message.
  v_lead_id := public.fn_wa_lead_id(p_from);
  if v_lead_id is not null then
    select * into v_lead from public.leads where id = v_lead_id;
    v_ident_k := 'lead'; v_ident_id := v_lead_id::text;
  else
    -- 3 Nov 2026: a CONFIRMED customer is known too (fn_whatsapp_owner: one party or nobody).
    select o.customer_id into v_cust from public.fn_whatsapp_owner(p_from) o where o.party_kind = 'customer';
    if v_cust is not null then v_ident_k := 'customer'; v_ident_id := v_cust::text; end if;
  end if;

  -- A CONFIRMATION OF A PENDING CANCEL is the cancel conversation, whatever the classifier made of "yes 1043" (8a).
  if v_cust is not null and p_intent is distinct from 'change_request'
     and public.fn_wa_is_cancel_confirmation(v_body) and public.fn_wa_pending_cancel(v_cust) is not null then
    p_intent := 'cancel_request';
  end if;

  -- THE INTENT, AS REASONED. Read by key from the active rows; the body is not read for meaning.
  select * into v_intent from public.wa_reply_intent where active and intent_key = p_intent;

  -- NOTHING TO ANSWER FROM. An honest refusal that names what it would need. Never a guess.
  if not found then
    v_reply := public.fn_wa_unmatched_reply();
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, false, v_reply,
            case when p_intent is null
                 then 'Not reasoned yet (the model hold). The meaning waits in customer_support''s queue and is answered on WhatsApp when it is reasoned.'
                 when p_intent = 'none' then 'Reasoned: no intent row fits. This row is the backlog: a real question with no resolver.'
                 else 'Reasoned as ' || p_intent || ': answered outside the intent table (size statement, trade list), not backlog.' end)
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', false, 'reply', v_reply, 'log_id', v_log,
                              'intent_decided_by', case when p_intent is null then 'held: not yet reasoned' else 'reasoning' end);
  end if;

  -- IDENTITY REQUIRED BUT UNKNOWN.
  if v_intent.requires_identity and v_lead_id is null and v_cust is null then
    v_reply := 'I do not recognise this number yet, so I cannot look up your records. Reply with the '
            || 'email address you registered with, or REGISTER to start a new registration.';
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply,
            'Intent reasoned but the sender is not a known party.')
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', true, 'intent', v_intent.intent_key, 'reply', v_reply, 'log_id', v_log);
  end if;

  -- A PROBLEM WITH A REVEALED JOB (16 Nov 2026, AFTER_REVEAL): the reasoned intent after_reveal, from a confirmed customer, goes to the
  -- one door (fn_customer_after_reveal_message): the dispute intake with the quotation on record, where the model reads whether the
  -- supplier contacted him, did not (the refund door), or a dispute needs a case. The reply is the door's own account of what it did.
  if v_cust is not null and v_intent.intent_key = 'after_reveal' then
    v_ans := public.fn_customer_after_reveal_message(v_cust, p_body, 'whatsapp', null);
    v_reply := case when v_ans->>'locale' = 'ar' then coalesce(v_ans->>'message_ar', v_ans->>'message_en') else v_ans->>'message_en' end;
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply,
            case when not coalesce((v_ans->>'ok')::boolean, false) then 'after_reveal: ' || coalesce(v_ans->>'code', 'not opened') end)
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', true, 'intent', v_intent.intent_key,
      'identity_kind', v_ident_k, 'identity_id', v_ident_id, 'reply', v_reply,
      'actions', jsonb_build_array(jsonb_build_object('after_reveal', v_ans - 'message_en' - 'message_ar')),
      'log_id', v_log, 'answered_by', 'deterministic', 'intent_decided_by', 'reasoning');
  end if;

  -- A CONFIRMED CUSTOMER'S OWN REQUESTS (3 Nov 2026): answered from their rows, and the ask is acted on.
  if v_cust is not null and (v_intent.requires_identity or v_intent.scope in ('own_records', 'by_id')
                             or v_intent.intent_key in ('my_requests', 'my_status', 'my_quotes', 'my_jobs', 'my_documents', 'by_id', 'change_request', 'cancel_request')) then
    v_ans := public.fn_wa_customer_request_answer(v_cust, p_from, v_intent.intent_key, p_body);
    v_reply := v_ans->>'reply';
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply,
            case when v_ans ? 'pending_cancel' then 'awaiting cancel confirmation:' || (v_ans->>'pending_cancel') end)
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', true, 'intent', v_intent.intent_key,
      'identity_kind', v_ident_k, 'identity_id', v_ident_id, 'reply', v_reply, 'actions', v_ans->'actions',
      'log_id', v_log, 'answered_by', 'deterministic', 'intent_decided_by', 'reasoning');
  end if;

  v_reply := v_intent.answer_template;

  -- COMPANY SLOTS, the same for everyone.
  v_reply := replace(v_reply, '{{reveal_rate}}', coalesce(round(v_cfg.standard_reveal_rate * 100, 1)::text || '%', '3%'));
  v_reply := replace(v_reply, '{{free_count}}',  coalesce(v_cfg.supplier_free_count::text, '1000'));
  v_reply := replace(v_reply, '{{reg_fee}}',     coalesce(round(v_cfg.supplier_reg_fee)::text, '1000'));

  -- THE APPROVED PUBLIC CONTACT, read from the settings that say publication in their names -- never from
  -- founder_mobile. Absent, the slot ADMITS it rather than rendering an empty string.
  v_reply := replace(v_reply, '{{founder_public_phone}}',
    coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
             '(no approved public contact is configured yet)'));
  v_reply := replace(v_reply, '{{founder_public_name}}',
    coalesce((select value from public.app_secrets where key = 'founder_public_name'),
             'the owner'));

  -- OWN-RECORD SLOTS, read from this sender's row only.
  if v_lead_id is not null then
    v_reply := replace(v_reply, '{{company_name}}', coalesce(v_lead.company_name, 'your company'));
    v_reply := replace(v_reply, '{{reg_status}}',   coalesce(v_lead.registration_status, 'not started'));
    v_reply := replace(v_reply, '{{approval_status}}', coalesce(v_lead.approval_status, 'not yet reviewed'));

    -- The founder's mandatory six, not the ten the scoring view happens to list.
    select string_agg(m, ', ') into v_missing from (
      select 'a UAE mobile number' as m where coalesce(btrim(v_lead.phone_e164), '') = ''
      union all select 'an email address' where coalesce(btrim(v_lead.email), '') = ''
      union all select 'your trade licence' where coalesce(btrim(v_lead.license_doc_path), '') = ''
      union all select 'your company profile' where coalesce(btrim(v_lead.company_profile_doc_path), '') = ''
      union all select 'a signed copy of our terms' where coalesce(btrim(v_lead.signed_terms_path), '') = ''
    ) x;
    v_reply := replace(v_reply, '{{missing_list}}', coalesce(v_missing, 'nothing, your file is complete'));
    v_reply := replace(v_reply, '{{missing_line}}',
      case when v_missing is null then 'Your file is complete.'
           else 'We still need: ' || v_missing || '.' end);

    v_reply := replace(v_reply, '{{quote_count}}', '0');
    v_reply := replace(v_reply, '{{quote_detail}}',
      'No quotes yet. Once a buyer posts a request in your category you will be invited to quote.');
    v_reply := replace(v_reply, '{{awarded_count}}', '0');
    v_reply := replace(v_reply, '{{awarded_detail}}',
      'No jobs awarded yet. You will get a message here the moment one is.');
  end if;

  -- BY-ID LOOKUP. A number in the body is resolved against the real records, and returned ONLY to a
  -- party who appears on that record. The digits are FORMAT: the first standalone run of 2 to 9, Arabic-Indic and Persian
  -- digits read as Western (review of #1844: an unbounded run overflowed bigint on an IBAN and lost the answer).
  if v_intent.scope = 'by_id' then
    v_id := (regexp_match(translate(v_body, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789'), '(?<![0-9])([0-9]{2,9})(?![0-9])'))[1]::bigint;
    if v_id is null then
      v_reply := 'Send me the number and I will look it up. For example: quote 1234, or job 5678.';
    else
      v_reply := replace(v_reply, '{{id_answer}}',
        'I could not find a record numbered ' || v_id || ' that you are a party to. Check the number, '
        || 'or reply HUMAN and the team will look into it.');
    end if;
  end if;

  insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply)
  values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply)
  returning id into v_log;

  return jsonb_build_object(
    'ok', true, 'matched', true, 'intent', v_intent.intent_key,
    'identity_kind', v_ident_k, 'identity_id', v_ident_id,
    'reply', v_reply, 'log_id', v_log, 'answered_by', 'deterministic', 'intent_decided_by', 'reasoning'
  );
end;
$fn$;
revoke execute on function public.fn_wa_answer(text, text, text) from public, anon, authenticated;
grant execute on function public.fn_wa_answer(text, text, text) to service_role;

-- ── 21. THE FINDING ON A DISPUTE READS THE QUOTATION TOO (the live body plus 'job_on_record' in the case) ──────────
create or replace function public.fn_sales_engineer_disputes_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; d record; v_q bigint;
  v_review int := 0; v_overdue int := 0;
begin
  for d in select p.*, (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) as demo
             from public.post_reveal_dispute p left join public.customers c on c.id = p.customer_id
            where p.stage = 'evidence'
              and ((p.customer_evidence is not null and p.supplier_evidence is not null) or now() > p.evidence_due)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
            order by p.id for update of p skip locked loop
    v_q := public.fn_seat_duty_reason('sales_engineer', 'sales_engineer.dispute_fault',
      case when d.demo then 'ZZ DEMO ' else '' end
      || 'A customer and a supplier disagree about a job after the supplier''s details were revealed. On the statements and evidence of both parties, which finding does the evidence support?',
      jsonb_build_array(
        jsonb_build_object('id', 'customer_upheld', 'meaning', 'the customer''s complaint is supported: the supplier fell short of what was agreed'),
        jsonb_build_object('id', 'supplier_upheld', 'meaning', 'the supplier''s position is supported: the supplier did what was agreed'),
        jsonb_build_object('id', 'shared', 'meaning', 'both parties contributed to the problem'),
        jsonb_build_object('id', 'no_fault', 'meaning', 'the evidence shows no fault by either party, or is too thin to find one')),
      jsonb_build_object('raised_by', d.raised_by, 'opened_at', d.opened_at, 'evidence_due', d.evidence_due,
                         'customer', d.customer_evidence, 'supplier', d.supplier_evidence,
                         -- 16 Nov 2026: what was agreed is on record: the revealed quotation the supplier is bound by
                         'job_on_record', d.job_facts),
      jsonb_build_object('dispute_id', d.id), 'dispute_fault:' || d.id);
    update public.post_reveal_dispute set stage = 'review', fault_question_id = v_q where id = d.id;
    v_review := v_review + 1;
  end loop;

  for d in select p.id, p.decision_due, p.finding from public.post_reveal_dispute p
             left join public.customers c on c.id = p.customer_id
            where p.stage = 'ceo_decision' and now() > p.decision_due
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx loop
    perform public.fn_it_engineer_finding_upsert('dispute_decision_overdue:' || d.id,
      'Post-reveal dispute QD-D-' || lpad(d.id::text, 5, '0') || ' is past its decision date',
      'public.post_reveal_dispute / fn_ceo_decides_post_reveal_dispute', 'agent_facing', 1,
      jsonb_build_object('dispute_id', d.id, 'decision_due', d.decision_due, 'owner_seat', 'ceo'),
      '{}'::text[], array['the CEO''s decision: public.fn_ceo_decides_post_reveal_dispute with the dispute id, the outcome, a note, the remedy (none, refund_reveal_fee, next_reveal_free) and the supplier action (none, warning, pause_matching)'],
      'sales_engineer');
    v_overdue := v_overdue + 1;
  end loop;
  return jsonb_build_object('to_review', v_review, 'decision_overdue', v_overdue);
end $fn$;
revoke execute on function public.fn_sales_engineer_disputes_tick() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_disputes_tick() to service_role;
