-- EVERY INBOUND MESSAGE IS ANSWERED OR CLOSED WITH ITS REASON, AND A COMPLAINT ON ANY CHANNEL IS REGISTERED.
-- Seat: customer_support. Agent: INBOUND_COMPLAINTS (16 Nov 2026, founder ledgers 1711-1713, COO holes H1 and H2).
--
-- H1. WHY "NOBODY ANSWERS SOME INBOUND MAIL" (SELECT on production 16 Nov 2026, counts and kinds only):
--   * The 7 supplier@ mails reported unanswered (32-114 h): 6 carry Auto-Submitted (auto-generated 5, auto-replied 1: a
--     supplier's ticketing system or an out-of-office), 1 was read by the model as automated_notice. The supplier-mailbox
--     reading (email_triage/supplier_mailbox_reading.ts, ruling 1633) had rightly decided "no answer" for every one.
--   * customer_support.unanswered_inbound (fn_customer_support_unanswered_inbound_tick) never read that decision: it put
--     every unreplied mail into a support case "owed a reply" with a support.case_open hand-off whose handler is
--     fn_customer_support_waits_for_a_person -- no seat, no model, nobody. customer_support.case_idle_close closes only
--     waiting_customer cases (an answered case), so these stay open for ever.
--   * Its 68 rows: 67 never answered. Email 20: machine mail 15 (auto-replied 9, auto-generated 5, model automated_notice 1),
--     the founder's own test replies 4 (test_reply), 1 read 'unclear' from a KNOWN supplier and held "for a person" that does
--     not exist (the one genuinely owed), 1 answered. WhatsApp 47: 29 from the reserved fixture range (+97150000000xx,
--     captured, never sent) and 18 whose wa_messages row is gone; the duty's fixture test read only the profile name.
--   * The weekly review (fn_customer_support_case_review_tick) took its p50/p90 over replied mail only, so seven owed or
--     closed messages produced "p90 first reply 0 min".
--   The new same-day supplier answer (every_interested_supplier_reply_is_answered_the_same_day_and_the_parked_get_one_last_note.sql,
--   live) covers a supplier's interested/question reply and excludes automatic replies: it does not reconcile the support case,
--   the 'unclear' reading, the founder's tests, the WhatsApp fixtures or the figure. This file closes only that remainder and
--   leaves a mail that routine owns to it (supplier_reply_same_day state owed/escalated).
--
-- WHAT H1 DOES:
--   1. fn_inbound_email_reply_owed(id): what a mail is owed, read from the readings already made (never a word list):
--      answered | no_reply_needed (the mailbox reading or the triage said no answer, with its reason) | with_sales_engineer |
--      decide (read 'unclear') | owed.
--   2. the duty now closes a no_reply_needed mail with its reason (no case, no hand-off), leaves a same-day supplier reply to
--      the sales engineer, asks email_triage for a SECOND READING of an 'unclear' mail from a known sender (the model must then
--      decide answer or not, supplier_mailbox_reading.ts SECOND_READING), and hands anything still owed past
--      support_first_reply_sla_hours (24) to the CEO seat (review.requested) once. Rows it opened before are reconciled the
--      same way and their cases closed with the reason when nothing else is on them; fixture-range WhatsApp and rows that are
--      gone are closed as such.
--   3. the weekly review and the 24 h watch count an owed message as "open for N minutes" in the percentiles; a message
--      closed with a reason is counted apart and is not owed.
--
-- H2. A COMPLAINT BY E-MAIL, WHATSAPP, WIDGET OR PORTAL CHAT NEVER REACHED THE REGISTER (READ): only contact_submit called
--   fn_complaint_open; complaint_tickets has 0 rows (SELECT). The reading each door already makes now carries a complaint
--   reading in the same model call (reasoned_decisions.ts COMPLAINT_OPTIONS on e-mail, WhatsApp and the widget; the portal's
--   turn reading, inquiry_reading.ts) and opens the ticket through fn_complaint_open_from_message: idempotent per message
--   (complaint_tickets.source_key), linked to the person (party, e-mail or phone as the channel holds them, never an e-mail
--   looked up from a phone; on WhatsApp the confirmed owner of the number) and to their open case, and to the job numbers they name that are THEIR OWN (an exact match on
--   inquiries.rfq_no of their requests or quotes; another person's number is never linked). The acknowledgement is owed on the
--   channel: the reply the model writes carries the ticket (fn_complaint_acknowledge once it went), else the deadline duty has
--   the model write it by e-mail when an address is known (customer_support_voice_owed, ruling 1339).
--
-- prevented by: every_inbound_message_is_answered_or_closed_with_its_reason_and_a_complaint_on_any_channel_is_registered_probe.sql
-- (LOCAL, run twice), _shared/complaint_register.test.ts, _shared/complaint_register_scenarios.test.ts,
-- email_triage/supplier_mailbox_second_reading.test.ts, email_triage/complaint.test.ts, _shared/inquiry_reading.test.ts,
-- resilience_ping/email_case_catchup.test.ts.
-- APPLY ORDER: after every_interested_supplier_reply_is_answered_the_same_day_and_the_parked_get_one_last_note.sql (reads
-- supplier_reply_same_day). Deploy email_triage, wa_inbound, site_assistant and sales_engineer AFTER this apply (they call
-- fn_complaint_open_from_message / fn_complaint_acknowledge; before it they get "function does not exist" and file nothing,
-- the reply is unaffected: registerComplaint never throws).
-- LOCKS: complaint_tickets (0 rows) and customer_support_inbound_drive (68 rows) gain columns; routines are replaced.
set local lock_timeout = '1500ms';

-- ── H2.1 THE REGISTER TAKES A COMPLAINT FROM ANY CHANNEL ─────────────────────────────────────────────────────────────
alter table public.complaint_tickets alter column email drop not null;
alter table public.complaint_tickets add column if not exists channel text not null default 'contact_form';
alter table public.complaint_tickets add column if not exists source_key text;
alter table public.complaint_tickets add column if not exists phone text;
alter table public.complaint_tickets add column if not exists party_kind text;
alter table public.complaint_tickets add column if not exists party_id text;
alter table public.complaint_tickets add column if not exists case_ref text;
alter table public.complaint_tickets add column if not exists inquiry_refs text[] not null default '{}';
alter table public.complaint_tickets add column if not exists reading text;
alter table public.complaint_tickets add column if not exists lang text;
alter table public.complaint_tickets add column if not exists acknowledged_how text;
alter table public.complaint_tickets add column if not exists fixture boolean not null default false;
comment on column public.complaint_tickets.source_key is
  'The message a channel complaint came from (email:<inbound id>, whatsapp:<sid>, widget:<hash>, portal:<conversation>:<turn>): one ticket per message.';
comment on column public.complaint_tickets.reading is 'Why the model read the message as a complaint (the door''s own reading), or the contact form.';
create unique index if not exists complaint_tickets_source_key on public.complaint_tickets (source_key) where source_key is not null;

do $guard$
begin
  if not exists (select 1 from pg_constraint where conname = 'complaint_tickets_channel_known' and conrelid = 'public.complaint_tickets'::regclass) then
    alter table public.complaint_tickets add constraint complaint_tickets_channel_known
      check (channel in ('contact_form', 'email', 'whatsapp', 'widget', 'portal'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'complaint_tickets_party_kind_known' and conrelid = 'public.complaint_tickets'::regclass) then
    alter table public.complaint_tickets add constraint complaint_tickets_party_kind_known
      check (party_kind is null or party_kind in ('customer', 'supplier'));
  end if;
  -- the contact form always has an address; a channel complaint has the channel's own key, and a widget visitor may have nothing more
  if not exists (select 1 from pg_constraint where conname = 'complaint_tickets_has_a_source' and conrelid = 'public.complaint_tickets'::regclass) then
    alter table public.complaint_tickets add constraint complaint_tickets_has_a_source
      check ((channel = 'contact_form' and email is not null) or (channel <> 'contact_form' and source_key is not null));
  end if;
end $guard$;

-- ── H2.2 OPEN A TICKET FROM THE MESSAGE A DOOR READ AS A COMPLAINT ────────────────────────────────────────────────────
create or replace function public.fn_complaint_open_from_message(
  p_channel text, p_source_key text, p_message text, p_reading text default null,
  p_email text default null, p_phone text default null, p_name text default null,
  p_party_kind text default null, p_party_id text default null, p_case_ref text default null,
  p_lang text default null, p_fixture boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';   -- 32 symbols, no 0/O/1/I (as fn_complaint_open)
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_kind text := case when p_party_kind in ('customer', 'supplier') and nullif(btrim(coalesce(p_party_id, '')), '') is not null then p_party_kind end;
  v_id text := case when p_party_kind in ('customer', 'supplier') then nullif(btrim(coalesce(p_party_id, '')), '') end;
  v_case text := nullif(upper(btrim(coalesce(p_case_ref, ''))), '');
  v_refs text[] := '{}'; v_row public.complaint_tickets; v_no text; v_bytes bytea; i int; attempt int := 0;
begin
  if p_channel not in ('email', 'whatsapp', 'widget', 'portal') then
    return jsonb_build_object('ok', false, 'reason', 'channel must be email, whatsapp, widget or portal (the contact form uses fn_complaint_open)');
  end if;
  if coalesce(btrim(p_source_key), '') = '' then return jsonb_build_object('ok', false, 'reason', 'no source key: a ticket is opened once per message'); end if;
  if coalesce(btrim(p_message), '') = '' then return jsonb_build_object('ok', false, 'reason', 'empty message'); end if;
  select * into v_row from public.complaint_tickets where source_key = btrim(p_source_key);
  if found then
    return jsonb_build_object('ok', true, 'duplicate', true, 'ticket', v_row.ticket_no, 'respond_due', v_row.respond_due,
                              'acknowledge_due', v_row.acknowledge_due, 'acknowledged', v_row.acknowledged_at is not null);
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then v_email := null; end if;
  -- the person: what the door knows; else an e-mail the channel itself holds names a customer or a supplier (exact address).
  -- On WhatsApp the person is the CONFIRMED owner of the number, exactly as the door identifies them (fn_whatsapp_owner, the
  -- reading behind fn_identify_contact; #322: only a confirmed WhatsApp number names a supplier or a customer). No e-mail is
  -- ever looked up from a phone, and an unconfirmed number names nobody.
  if v_kind is null and p_channel = 'whatsapp' and length(v_digits) >= 9 then
    select o.party_kind, coalesce(o.lead_id::text, o.customer_id::text) into v_kind, v_id
      from public.fn_whatsapp_owner(p_phone) o where o.party_kind in ('customer', 'supplier') limit 1;
    if v_id is null then v_kind := null; end if;
  end if;
  if v_kind is null and v_email is not null then
    select 'customer', c.id::text into v_kind, v_id from public.customers c where lower(c.email) = v_email order by c.created_at limit 1;
    if v_kind is null then
      select 'supplier', l.id::text into v_kind, v_id from public.leads l
       where lower(l.email) = v_email or lower(btrim(coalesce(l.claimed_by, ''))) = v_email order by l.id limit 1;
    end if;
  end if;
  -- their open case, when the door did not name it
  if v_case is null and v_kind is not null then
    select c.case_ref into v_case from public.support_case c
     where c.party_kind = v_kind and c.party_id = v_id and c.state <> 'closed' order by c.last_activity_at desc limit 1;
  end if;
  -- the job numbers they name that are THEIR OWN: an exact number of one of their requests (customer) or of a request they
  -- quoted on (supplier). Code checks an identifier against their own records; it reads no meaning.
  if v_kind = 'customer' and v_id ~ '^[0-9a-f-]{36}$' then
    select coalesce(array_agg(distinct q.rfq_no::text), '{}') into v_refs from public.inquiries q
     where q.customer_id = v_id::uuid and q.rfq_no is not null and p_message ~ ('(^|[^0-9])' || q.rfq_no::text || '([^0-9]|$)');
  elsif v_kind = 'supplier' and v_id ~ '^[0-9]+$' then
    select coalesce(array_agg(distinct q.rfq_no::text), '{}') into v_refs from public.quotes x join public.inquiries q on q.id = x.inquiry_id
     where x.supplier_id = v_id::bigint and q.rfq_no is not null and p_message ~ ('(^|[^0-9])' || q.rfq_no::text || '([^0-9]|$)');
  end if;
  loop
    attempt := attempt + 1;
    v_bytes := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
    v_no := 'QD-C-';
    for i in 0..5 loop v_no := v_no || substr(alphabet, (get_byte(v_bytes, i) % 32) + 1, 1); end loop;
    begin
      insert into public.complaint_tickets
        (ticket_no, email, name, message, status, acknowledge_due, respond_due, acknowledged_at,
         channel, source_key, phone, party_kind, party_id, case_ref, inquiry_refs, reading, lang, fixture)
      values
        (v_no, v_email, nullif(btrim(coalesce(p_name, '')), ''), left(p_message, 4000), 'acknowledged',
         public.fn_add_working_days(now(), 2), public.fn_add_working_days(now(), 10), null,
         p_channel, btrim(p_source_key), case when length(v_digits) >= 9 then '+' || v_digits end, v_kind, v_id, v_case,
         coalesce(v_refs, '{}'), left(nullif(btrim(coalesce(p_reading, '')), ''), 600),
         case when p_lang in ('en', 'ar') then p_lang end, coalesce(p_fixture, false))
      returning * into v_row;
      exit;
    exception when unique_violation then
      -- the same message read twice at once: the other read opened it
      select * into v_row from public.complaint_tickets where source_key = btrim(p_source_key);
      if found then
        return jsonb_build_object('ok', true, 'duplicate', true, 'ticket', v_row.ticket_no, 'respond_due', v_row.respond_due,
                                  'acknowledge_due', v_row.acknowledge_due, 'acknowledged', v_row.acknowledged_at is not null);
      end if;
      if attempt >= 5 then raise; end if;
    end;
  end loop;
  return jsonb_build_object('ok', true, 'duplicate', false, 'ticket', v_row.ticket_no, 'status', v_row.status,
    'created_at', v_row.created_at, 'acknowledge_due', v_row.acknowledge_due, 'respond_due', v_row.respond_due,
    'party_kind', v_row.party_kind, 'case_ref', v_row.case_ref, 'inquiry_refs', to_jsonb(v_row.inquiry_refs), 'acknowledged', false);
end $fn$;
revoke execute on function public.fn_complaint_open_from_message(text, text, text, text, text, text, text, text, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.fn_complaint_open_from_message(text, text, text, text, text, text, text, text, text, text, text, boolean) to service_role;

-- The acknowledgement went (a reply that carried the ticket, or the model-written e-mail): stamped once.
create or replace function public.fn_complaint_acknowledge(p_ticket text, p_how text)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  update public.complaint_tickets
     set acknowledged_at = now(), acknowledged_how = left(coalesce(nullif(btrim(p_how), ''), 'acknowledged'), 200)
   where ticket_no = upper(btrim(coalesce(p_ticket, ''))) and acknowledged_at is null;
  return found;
end $fn$;
revoke execute on function public.fn_complaint_acknowledge(text, text) from public, anon, authenticated;
grant execute on function public.fn_complaint_acknowledge(text, text) to service_role;

-- A ticket is a fixture by its marker (the contact form's example.invalid address, or a channel's fixture flag).
create or replace function public.fn_complaint_is_fixture(p_email text, p_fixture boolean)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(p_fixture, false) or coalesce(public.fn_is_demo_email(p_email), false)
$fn$;
revoke execute on function public.fn_complaint_is_fixture(text, boolean) from public, anon, authenticated;

-- ── H2.3 THE DEADLINE DUTY OWES THE ACKNOWLEDGEMENT OF A CHANNEL COMPLAINT, AND READS FIXTURES BY THEIR MARKER ──────────
-- Unchanged from customer_support_acts_on_a_complaint_before_its_deadline.sql except: the fixture test (a channel ticket may
-- have no e-mail), and step 0: a ticket not yet acknowledged is stamped once its model-written acknowledgement went, or owed
-- one (fn_customer_support_voice_owe; the model writes it, the draft only on an outage) when the channel gave an address.
create or replace function public.fn_customer_support_complaint_deadline_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_warn int := public.fn_seat_clock_policy('complaint_seat_warning_working_days', 2)::int;
  t public.complaint_tickets; v_due text; v_ar boolean; v_r jsonb; v_clock jsonb; v_role text;
  n_update int := 0; n_ceo int := 0; n_ack_owed int := 0; n_ack_seen int := 0;
begin
  for t in select * from public.complaint_tickets
            where status <> 'final_response' and public.fn_complaint_is_fixture(email, fixture) = v_fx order by id loop
    v_due := to_char(t.respond_due at time zone 'Asia/Dubai', 'YYYY-MM-DD');
    v_ar := coalesce(t.lang, '') = 'ar' or coalesce(t.message, '') ~ '[؀-ۿ]';
    v_role := case when t.party_kind = 'supplier' then 'supplier' else 'customer' end;

    -- 0. a channel complaint's acknowledgement
    if t.acknowledged_at is null then
      if exists (select 1 from public.customer_support_duty_message d
                  where d.stage = 'complaint.acknowledge' and d.subject_key = t.ticket_no and d.outcome = 'queued') then
        perform public.fn_complaint_acknowledge(t.ticket_no, 'e-mail written by the model (customer_support.complaint_deadlines)');
        n_ack_seen := n_ack_seen + 1;
      elsif public.fn_customer_support_voice_owe('complaint.acknowledge', t.ticket_no, 'complaint.acknowledge:' || t.ticket_no, v_role, t.email,
        case when v_ar then 'ar' else 'en' end,
        case when v_ar then 'شكواكم ' || t.ticket_no || ': تم التسجيل' else 'Your complaint ' || t.ticket_no || ': registered' end,
        case when v_ar then
          'عزيزنا ' || coalesce(nullif(btrim(t.name), ''), 'العميل') || '،' || chr(10) || chr(10)
          || 'سجّلنا شكواكم برقم المرجع ' || t.ticket_no || '. ستصلكم إجابتنا النهائية في موعد أقصاه ' || v_due
          || '. يُرجى ذكر المرجع عند الرد على هذه الرسالة.' || chr(10) || chr(10) || 'فريق QuotesDone'
        else
          'Dear ' || coalesce(nullif(btrim(t.name), ''), 'customer') || ',' || chr(10) || chr(10)
          || 'We have registered your complaint under reference ' || t.ticket_no || '. You will have our final response by ' || v_due
          || '. Please quote the reference if you reply to this email.' || chr(10) || chr(10) || 'The QuotesDone team' end,
        'Acknowledge the complaint they sent us: it is registered under the reference in the facts, and our final response will reach them by the date in the facts. Address them by name when the facts give one. Invite them to reply with anything they want to add, quoting the reference. Do not discuss the merits.',
        'COMPLAINT REFERENCE: ' || t.ticket_no || chr(10) || 'CUSTOMER NAME: ' || coalesce(nullif(btrim(t.name), ''), '(not given)')
          || chr(10) || 'RECEIVED BY: ' || t.channel || chr(10) || 'FINAL RESPONSE DUE BY: ' || v_due,
        array[t.ticket_no, v_due]) then n_ack_owed := n_ack_owed + 1; end if;
    end if;

    if now() >= t.created_at + (t.respond_due - t.created_at) / 2 then
      if t.status = 'acknowledged' then perform public.fn_complaint_set_status(t.ticket_no, 'in_review'); end if;
      if public.fn_customer_support_voice_owe('complaint.update', t.ticket_no, 'complaint.update:' || t.ticket_no, v_role, t.email,
        case when v_ar then 'ar' else 'en' end,
        case when v_ar then 'شكواكم ' || t.ticket_no || ': قيد المراجعة' else 'Your complaint ' || t.ticket_no || ': in review' end,
        case when v_ar then
          'عزيزنا ' || coalesce(nullif(btrim(t.name), ''), 'العميل') || '،' || chr(10) || chr(10)
          || 'نودّ إعلامكم بأن شكواكم ذات المرجع ' || t.ticket_no || ' قيد المراجعة الآن. ستصلكم إجابتنا النهائية في موعد أقصاه ' || v_due
          || '. إن كانت لديكم أي معلومات إضافية، يُرجى الرد على هذه الرسالة مع ذكر المرجع.' || chr(10) || chr(10) || 'فريق QuotesDone'
        else
          'Dear ' || coalesce(nullif(btrim(t.name), ''), 'customer') || ',' || chr(10) || chr(10)
          || 'Your complaint, reference ' || t.ticket_no || ', is now in review. You will have our final response by ' || v_due
          || '. If you have anything to add, reply to this email and quote the reference.' || chr(10) || chr(10) || 'The QuotesDone team' end,
        -- what the model writes, from these facts only (nothing internal: ledger 1338)
        'Write the customer an update on their complaint: it is now in review, and our final response will reach them by the date in the facts. Address them by name when the facts give one. Invite them to reply to this e-mail with anything they want to add, quoting the reference.',
        'COMPLAINT REFERENCE: ' || t.ticket_no || chr(10) || 'CUSTOMER NAME: ' || coalesce(nullif(btrim(t.name), ''), '(not given)')
          || chr(10) || 'STATUS: in review' || chr(10) || 'FINAL RESPONSE DUE BY: ' || v_due,
        array[t.ticket_no, v_due]) then n_update := n_update + 1; end if;
    end if;

    if not v_fx and public.fn_working_days_between(now(), t.respond_due) <= v_warn and now() <= t.respond_due then
      v_r := public.fn_support_report_to_ceo(
        'complaint_due_soon:' || t.ticket_no, 'elevated',
        'Complaint ' || t.ticket_no || ' needs its final response by ' || v_due || ' Dubai',
        jsonb_build_object('ticket', t.ticket_no, 'created_at', t.created_at, 'respond_due', t.respond_due, 'status', t.status,
                           'channel', t.channel, 'case_ref', t.case_ref, 'jobs', to_jsonb(t.inquiry_refs),
                           'complaint', left(coalesce(t.message, ''), 1500),
                           'policy', 'Complaints Policy: acknowledgement within 2 working days, substantive response within 10'),
        jsonb_build_array('acknowledged on ' || coalesce(t.acknowledged_at::text, '(not yet)'), 'the customer was told the due date'),
        'Decide the final response on ' || t.ticket_no || ' before ' || v_due || ' and have customer_support give it (fn_complaint_set_status).',
        p_case_ref => t.ticket_no, p_source_agent => 'customer_support');
      if coalesce((v_r->>'ok')::boolean, false) and not coalesce((v_r->>'duplicate')::boolean, false) then n_ceo := n_ceo + 1; end if;
    end if;
  end loop;

  v_clock := public.fn_complaint_clock_tick(v_fx);
  return jsonb_build_object('ok', true, 'fixture', v_fx, 'acknowledgements_owed', n_ack_owed, 'acknowledgements_seen', n_ack_seen,
                            'updates_owed', n_update, 'decisions_asked_before_lapse', n_ceo, 'clock', v_clock);
end $fn$;
revoke execute on function public.fn_customer_support_complaint_deadline_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_complaint_deadline_tick() to service_role;

-- fn_complaint_clock_tick: unchanged except the fixture test (a channel ticket may have no e-mail).
create or replace function public.fn_complaint_clock_tick(p_include_fixtures boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.complaint_tickets; h record; r jsonb;
  v_warn int := public.fn_seat_clock_policy('complaint_seat_warning_working_days', 2)::int;
  v_due timestamptz; v_owed text; v_seat int := 0; v_ceo int := 0; v_closed int := 0; v_refused jsonb := '[]'::jsonb;
begin
  for t in select * from public.complaint_tickets
            where status <> 'final_response' and (p_include_fixtures or not public.fn_complaint_is_fixture(email, fixture))
            order by id loop
    if t.acknowledged_at is null then v_due := t.acknowledge_due; v_owed := 'acknowledgement';
    else v_due := t.respond_due; v_owed := 'final response'; end if;
    if public.fn_working_days_between(now(), v_due) > v_warn and now() <= v_due then continue; end if;

    perform public.fn_seat_handoff('customer_support', 'customer_support', 'complaint.due', 'complaint_tickets', t.ticket_no,
      jsonb_build_object('ticket', t.ticket_no, 'due', v_due, 'owed', v_owed, 'status', t.status,
        'waiting_for', 'the ' || v_owed || ' on complaint ' || t.ticket_no || ' (fn_complaint_set_status), due '
                       || to_char(v_due at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai'));
    v_seat := v_seat + 1;

    if now() > v_due then
      r := public.fn_support_report_to_ceo(
        'complaint_overdue:' || t.ticket_no || ':' || replace(v_owed, ' ', '_'), 'elevated',
        'Complaint ' || t.ticket_no || ' is past its ' || v_owed || ' deadline ('
          || to_char(v_due at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai)',
        jsonb_build_object('ticket', t.ticket_no, 'created_at', t.created_at, 'due', v_due, 'owed', v_owed, 'status', t.status,
                           'channel', t.channel, 'case_ref', t.case_ref,
                           'policy', 'Complaints Policy: acknowledgement within 2 working days, substantive response within 10'),
        jsonb_build_array('customer_support has held complaint.due for ' || t.ticket_no || ' since '
                          || v_warn || ' working day(s) before the deadline'),
        'Decide the ' || v_owed || ' on ' || t.ticket_no || ' and have customer_support give it (fn_complaint_set_status). The customer can see the missed date on the status page.',
        p_case_ref => t.ticket_no, p_source_agent => 'customer_support');
      if not coalesce((r->>'ok')::boolean, false) then
        v_refused := v_refused || jsonb_build_array(jsonb_build_object('ticket', t.ticket_no, 'reason', r->>'reason'));
      elsif not coalesce((r->>'duplicate')::boolean, false) then v_ceo := v_ceo + 1;
      end if;
    end if;
  end loop;

  for h in select a.id from public.agent_actions a
             join public.complaint_tickets c on a.target_id = 'complaint.due:' || c.ticket_no
            where a.kind = 'handoff' and a.agent = 'customer_support' and a.status not in ('done', 'failed')
              and c.status = 'final_response' loop
    perform public.fn_seat_handoff_complete(h.id, jsonb_build_object('final_response_given', true));
    v_closed := v_closed + 1;
  end loop;

  return jsonb_build_object('ok', jsonb_array_length(v_refused) = 0, 'on_seat_clock', v_seat,
                            'raised_to_ceo', v_ceo, 'closed', v_closed, 'refused', v_refused);
end $fn$;
revoke execute on function public.fn_complaint_clock_tick(boolean) from public, anon, authenticated;
grant execute on function public.fn_complaint_clock_tick(boolean) to service_role;

-- ── H1.1 WHAT AN INBOUND MAIL IS OWED, FROM THE READINGS ALREADY MADE ─────────────────────────────────────────────────
alter table public.customer_support_inbound_drive add column if not exists no_reply_reason text;
alter table public.customer_support_inbound_drive add column if not exists closed_at timestamptz;
alter table public.customer_support_inbound_drive add column if not exists reread_requested_at timestamptz;
alter table public.customer_support_inbound_drive add column if not exists escalated_at timestamptz;
alter table public.customer_support_inbound_drive add column if not exists escalation_handoff_id bigint;
comment on column public.customer_support_inbound_drive.no_reply_reason is
  'Closed without a reply, and why: the reading already made (the supplier-mailbox reading, the triage, a code rule on a header) said no answer is owed; or a fixture/gone WhatsApp row.';

-- fn_inbound_email_reply_owed(id) is defined in H1.3 below (the tick reads it at run time).

-- Close a case the duty opened when everything on it was closed with a reason (nothing was owed), with that reason.
create or replace function public.fn_customer_support_close_case_nothing_owed(p_case_ref text)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.support_case; v_rows int; v_open int; v_reason text;
begin
  select * into c from public.support_case where case_ref = p_case_ref and state <> 'closed';
  if not found or c.outbound_count > 0 then return false; end if;
  select count(*), count(*) filter (where i.closed_at is null and i.answered_at is null),
         string_agg(distinct left(i.no_reply_reason, 160), '; ')
    into v_rows, v_open, v_reason
    from public.customer_support_inbound_drive i where i.case_ref = p_case_ref;
  -- every inbound on the case is one of these rows, and each was closed with its reason; or the case is a reserved fixture
  -- number's (every message on it is test traffic: wa_messages' own case touch counts more inbound than the duty drove)
  if v_rows = 0 or v_open > 0 then return false; end if;
  if c.inbound_count > v_rows and not exists (select 1 from public.support_customer_profile p
                                               where p.id = c.customer_profile_id and public.fn_is_demo_phone('0' || p.phone_tail)) then
    return false;
  end if;
  -- SILENT (review 16 Nov 2026): nobody was owed a reply, so nobody is asked to rate it (trg_support_case_closed_asks_for_the_rating)
  -- or told it closed (trg_support_case_closed_tells_the_reporter). Measured: the first run would have mailed "How did we do?" to an
  -- out-of-office sender, an auto-generated sender and a Microsoft vendor address, and the reason above is internal text (ledger 1338).
  update public.support_case set csat_requested_at = now(), csat_request_error = 'not asked: closed because no reply was owed'
   where case_ref = c.case_ref and csat_requested_at is null;
  perform set_config('qd.support_case_close_silently', 'on', true);
  perform public.fn_support_case_close(p_case_ref, left('no reply was owed: ' || coalesce(v_reason, 'see customer_support_inbound_drive'), 900), 'customer_support');
  perform set_config('qd.support_case_close_silently', '', true);
  return true;
end $fn$;
revoke execute on function public.fn_customer_support_close_case_nothing_owed(text) from public, anon, authenticated;

-- The reporter is told of a close, except a silent one (above). Live body (nothing_a_person_sends_us_waits_without_a_seat_that_acts.sql)
-- with only the qd.support_case_close_silently test added; the hand-off is still completed.
create or replace function public.fn_support_case_closed_tells_the_reporter()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$

declare v_h public.agent_actions; v_email text; v_lang text; v_notif bigint;
begin
  if new.state <> 'closed' or old.state = 'closed' then return null; end if;
  select * into v_h from public.agent_actions where kind = 'handoff'
     and target_id in ('support.case_open:' || new.case_ref, 'support.case_open:' || new.case_id) limit 1;
  v_lang := coalesce(v_h.detail ->> 'lang', 'en');
  if new.party_kind = 'customer' then
    select c.email into v_email from public.customers c where c.id::text = new.party_id;
  elsif new.party_kind = 'supplier' then
    select l.email into v_email from public.leads l where l.id::text = new.party_id;
  end if;
  if v_email ~ '@' and coalesce(current_setting('qd.support_case_close_silently', true), '') <> 'on' then
   begin   -- a refused notice (a guard on notifications) must never undo the close itself
    insert into public.notifications (type, kind, to_email, to_role, channel, lang, subject, body, requested_by, sender)
    values ('support_case_closed', 'support_case_closed', v_email, new.party_kind, 'email', v_lang,
            case when v_lang = 'ar' then 'إغلاق البلاغ رقم ' || new.case_ref else 'Your case ' || new.case_ref || ' is closed' end,
            case when v_lang = 'ar'
                 then 'نفيدكم بإغلاق البلاغ رقم ' || new.case_ref || '، وملخص المعالجة: ' || new.close_reason
                      || E'.\nإن لم تُحلّ المشكلة فتفضلوا بالرد على هذه الرسالة وسنعيد فتحه.'
                 else 'Your case ' || new.case_ref || ' is now closed: ' || new.close_reason
                      || E'.\nIf the problem is not solved, just reply to this message and we will reopen it.' end,
            'customer_support', 'customer_support')
    returning id into v_notif;
   exception when others then
    raise warning 'fn_support_case_closed_tells_the_reporter: the email for % was refused: %', new.case_ref, sqlerrm;
   end;
  end if;
  if v_h.id is not null and v_h.status <> 'done' then
    perform public.fn_seat_handoff_complete(v_h.id, jsonb_build_object(
      'closed_at', new.closed_at, 'close_reason', new.close_reason,
      'reporter_email_notification', v_notif, 'reporter_phone_digits', v_h.detail ->> 'phone_digits'));
  end if;
  return null;
end $fn$;
revoke execute on function public.fn_support_case_closed_tells_the_reporter() from public, anon, authenticated;

-- ── H1.2 THE DUTY: A REPLY, OR A CLOSE WITH ITS REASON, WITHIN THE SLA ────────────────────────────────────────────────
create or replace function public.fn_customer_support_unanswered_inbound_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_cut timestamptz := now() - make_interval(hours => greatest(1, public.fn_seat_clock_policy('support_unanswered_drive_hours', 2)::int));
  v_sla int := public.fn_seat_clock_policy('support_first_reply_sla_hours', 24)::int;
  v_founder text[]; m record; w record; d record; v_t jsonb; v_ref text; v_h bigint; v_st jsonb; v_state text; v_why text;
  v_known text; v_from text;
  n_email int := 0; n_wa int := 0; n_answered int := 0; n_noid int := 0; n_closed int := 0; n_cases_closed int := 0;
  n_reread int := 0; n_sales int := 0; n_escalated int := 0;
begin
  select coalesce(array_agg(right(regexp_replace(value, '[^0-9]', '', 'g'), 9)), '{}') into v_founder
    from public.app_secrets where key in ('founder_mobile', 'founder_public_phone', 'admin_mfa_phone')
     and length(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g')) >= 9;

  -- 1. every row still open: answered since, closed with its reason, or (past the SLA) the CEO's
  for d in select i.* from public.customer_support_inbound_drive i
            where i.answered_at is null and i.closed_at is null and i.fixture = v_fx order by i.acted_at limit 200 loop
    v_state := null; v_why := null;
    if d.channel = 'email' then
      v_st := public.fn_inbound_email_reply_owed(d.message_id); v_state := v_st->>'state'; v_why := v_st->>'reason';
    else
      select case when x.id is null then 'gone'
                  when x.reply is not null and coalesce(x.sent, false) then 'answered'
                  when public.fn_is_demo_phone(x.wa_from) then 'fixture'
                  when coalesce(btrim(x.meta->>'no_autoreply_reason'), '') <> '' then 'recorded'
                  else 'owed' end,
             left(x.meta->>'no_autoreply_reason', 300)
        into v_state, v_why from (select 1) one left join public.wa_messages x on x.id = d.message_id;
      -- 'recorded': wa_inbound kept it with no reply of its own and said why (a burst answered by its first message, a thank-you,
      -- a stopped machine loop, an unverified webhook: wa_inbound/burst.ts, arrival.ts)
      v_why := case v_state when 'gone' then 'the WhatsApp message is no longer on file'
                            when 'fixture' then 'a reserved fixture number (+97150000000xx): test traffic, never sent to a person'
                            when 'recorded' then 'wa_inbound recorded it with no reply of its own: ' || v_why end;
      if v_state in ('gone', 'fixture', 'recorded') then v_state := 'no_reply_needed'; end if;
    end if;
    if v_state = 'answered' then
      update public.customer_support_inbound_drive set answered_at = now() where channel = d.channel and message_id = d.message_id;
      if d.handoff_id is not null and exists (select 1 from public.agent_actions a where a.id = d.handoff_id and a.status not in ('done', 'failed')) then
        perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('answered', true, 'channel', d.channel, 'message_id', d.message_id));
      end if;
      n_answered := n_answered + 1;
    elsif v_state = 'no_reply_needed' then
      update public.customer_support_inbound_drive
         set closed_at = now(), no_reply_reason = v_why, outcome = left('no reply needed: ' || v_why, 500)
       where channel = d.channel and message_id = d.message_id;
      if d.handoff_id is not null and exists (select 1 from public.agent_actions a where a.id = d.handoff_id and a.status not in ('done', 'failed')) then
        perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('no_reply_needed', true, 'reason', v_why, 'channel', d.channel, 'message_id', d.message_id));
      end if;
      if d.case_ref is not null and public.fn_customer_support_close_case_nothing_owed(d.case_ref) then n_cases_closed := n_cases_closed + 1; end if;
      n_closed := n_closed + 1;
    elsif d.channel = 'email' and v_state = 'decide' and d.reread_requested_at is null then
      -- read 'unclear': a SECOND READING by the model, told who the sender is (supplier_mailbox_reading.ts SECOND_READING)
      update public.inbound_messages
         set triaged_at = null, ai_category = null, owner_role = null, needs_review = true,
             raw = coalesce(raw, '{}'::jsonb) || jsonb_build_object('second_reading_requested_at', now())
       where id = d.message_id and replied_at is null;
      update public.customer_support_inbound_drive set reread_requested_at = now(),
             outcome = 'read unclear: a second reading by the model was asked (it decides an answer or no answer, with its reason)'
       where channel = d.channel and message_id = d.message_id;
      n_reread := n_reread + 1;
    elsif v_state in ('owed', 'decide') and d.escalated_at is null
          and (select coalesce(x.created_at, d.acted_at) from (select 1) one
                 left join public.inbound_messages x on d.channel = 'email' and x.id = d.message_id) < now() - make_interval(hours => v_sla) then
      -- still owed past the seat's SLA: the CEO seat decides the answer (never silent, never for a fixture)
      if not v_fx then
        v_h := public.fn_seat_handoff('customer_support', 'ceo', 'review.requested', 'inbound_messages', d.message_id::text,
          jsonb_build_object('inbound_message_id', d.message_id, 'channel', d.channel, 'case_ref', d.case_ref, 'state', v_state, 'why', v_why,
            'ask', 'This message has had no reply and no reasoned close within ' || v_sla || ' h. Decide the answer and have it sent in the thread, or close it with the reason.'));
        update public.customer_support_inbound_drive set escalated_at = now(), escalation_handoff_id = v_h
         where channel = d.channel and message_id = d.message_id;
        n_escalated := n_escalated + 1;
      end if;
    end if;
  end loop;

  -- 2. email still unanswered past the drive threshold: closed with its reason, the sales engineer's, or a case
  for m in select x.* from public.inbound_messages x
            where x.replied_at is null and x.created_at < v_cut and x.created_at > now() - interval '30 days'
              and public.fn_support_email_is_a_customer_contact(x.from_email, x.to_email, x.owner_role, x.subject, v_fx)
              and not exists (select 1 from public.customer_support_inbound_drive i where i.channel = 'email' and i.message_id = x.id)
            order by x.id limit 50 loop
    v_st := public.fn_inbound_email_reply_owed(m.id); v_state := v_st->>'state'; v_why := v_st->>'reason';
    if v_state = 'answered' then continue; end if;
    if v_state = 'no_reply_needed' then
      insert into public.customer_support_inbound_drive (channel, message_id, outcome, no_reply_reason, closed_at, fixture)
      values ('email', m.id, left('no reply needed: ' || v_why, 500), v_why, now(), v_fx);
      n_closed := n_closed + 1; continue;
    end if;
    if v_state = 'with_sales_engineer' then
      insert into public.customer_support_inbound_drive (channel, message_id, outcome, fixture)
      values ('email', m.id, left('owed: ' || v_why, 500), v_fx);
      n_sales := n_sales + 1; continue;
    end if;
    v_t := public.fn_support_touch('email', 'in', 'unknown', null, m.from_email, null,
                                   coalesce(m.subject, '') || ' ' || left(coalesce(m.body, ''), 1000));
    v_ref := v_t->>'case_ref';
    if v_ref is null then
      insert into public.customer_support_inbound_drive (channel, message_id, outcome, fixture) values ('email', m.id, 'no identity: ' || coalesce(v_t->>'reason', '?'), v_fx);
      n_noid := n_noid + 1; continue;
    end if;
    v_h := public.fn_seat_handoff('customer_support', 'customer_support', 'support.case_open', 'support_case', v_ref,
      jsonb_build_object('case_ref', v_ref, 'channel', 'email', 'message_id', m.id,
                         'waiting_for', 'an answer to email #' || m.id || ' (case ' || v_ref || '), owed within ' || v_sla || ' h of ' || m.created_at));
    insert into public.customer_support_inbound_drive (channel, message_id, case_ref, acknowledged, handoff_id, outcome, fixture)
    values ('email', m.id, v_ref, false, v_h, left('case opened (' || v_state || ': ' || v_why || '); the reply is the model''s (ruling 1339)', 500), v_fx);
    n_email := n_email + 1;
  end loop;

  -- 3. WhatsApp still unanswered past the drive threshold (a reserved fixture number is a fixture, whatever its profile name)
  for w in select x.* from public.wa_messages x
            where x.created_at < v_cut and x.created_at > now() - interval '30 days'
              and coalesce(btrim(x.inbound), '') <> '' and (x.reply is null or not coalesce(x.sent, false))
              and coalesce(btrim(x.meta->>'no_autoreply_reason'), '') = ''
              and not (right(regexp_replace(coalesce(x.wa_from, ''), '[^0-9]', '', 'g'), 9) = any (v_founder))
              and (coalesce(x.profile_name, '') like 'ZZ DEMO%' or public.fn_is_demo_phone(x.wa_from)) = v_fx
              and not exists (select 1 from public.customer_support_inbound_drive i where i.channel = 'whatsapp' and i.message_id = x.id)
            order by x.id limit 50 loop
    v_t := public.fn_support_touch('whatsapp', 'in', 'unknown', null, null, w.wa_from, w.inbound);
    v_ref := v_t->>'case_ref';
    if v_ref is null then
      insert into public.customer_support_inbound_drive (channel, message_id, outcome, fixture) values ('whatsapp', w.id, 'no identity: ' || coalesce(v_t->>'reason', '?'), v_fx);
      n_noid := n_noid + 1; continue;
    end if;
    v_h := public.fn_seat_handoff('customer_support', 'customer_support', 'support.case_open', 'support_case', v_ref,
      jsonb_build_object('case_ref', v_ref, 'channel', 'whatsapp', 'message_id', w.id,
                         'waiting_for', 'an answer to WhatsApp #' || w.id || ' (case ' || v_ref || '), owed within ' || v_sla || ' h of ' || w.created_at));
    insert into public.customer_support_inbound_drive (channel, message_id, case_ref, handoff_id, outcome, fixture)
    values ('whatsapp', w.id, v_ref, v_h, 'case opened', v_fx);
    n_wa := n_wa + 1;
  end loop;

  return jsonb_build_object('ok', true, 'fixture', v_fx, 'email_driven', n_email, 'whatsapp_driven', n_wa,
                            'answered_since', n_answered, 'closed_no_reply_needed', n_closed, 'cases_closed', n_cases_closed,
                            'second_readings_asked', n_reread, 'with_sales_engineer', n_sales, 'escalated_to_ceo', n_escalated,
                            'no_identity', n_noid);
end $fn$;
revoke execute on function public.fn_customer_support_unanswered_inbound_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_unanswered_inbound_tick() to service_role;

update public.seat_duty
   set what = 'CS-C01: every inbound email or WhatsApp message still unanswered after support_unanswered_drive_hours gets a reply or a reasoned close: a mail the reading already said needs no answer is closed with that reason; a same-day supplier reply is the sales engineer''s; an ''unclear'' reading is read again by the model; anything else is a case in the seat''s inbox (the reply is the model''s, ruling 1339), and still owed past support_first_reply_sla_hours goes to the CEO seat',
       owner_file = 'scripts/sql/every_inbound_message_is_answered_or_closed_with_its_reason_and_a_complaint_on_any_channel_is_registered.sql'
 where duty = 'customer_support.unanswered_inbound';

-- ── H1.3 A KNOWN PERSON'S MAIL STAMPED "AUTO-GENERATED" IS READ BY THE MODEL, NOT REFUSED BY THE HEADER ALONE ───────────
-- MEASURED (SELECT 16 Nov 2026): the 4 mails from known suppliers refused by hard rule auto_submitted all carry
-- "Auto-Submitted: auto-generated"; one is a "Re:" to our mail with a 2.8k-character body. Helpdesk and CRM systems stamp a
-- person's message auto-generated, so the header alone was deciding WHAT a known supplier's mail is (ruling 1663: the model
-- understands, code only checks). For a sender known as a customer or a supplier, "auto-generated" is now a FACT the reading is
-- given (supplier_mailbox_reading.ts) and the model decides; "auto-replied" (RFC 3834's automatic response: an out-of-office),
-- X-Autoreply and Precedence auto_reply still refuse by code, for everyone. Loop guards are untouched (auto_reply_loop.ts, the
-- daily cap). Body otherwise identical to the live routine (a_reply_from_the_supplier_mailbox_leaves_only_when_the_reading_said_answer.sql).
create or replace function public.fn_mailbox_reply_hard_rule(p_inbound_id bigint)
returns text
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare m public.inbound_messages; v_addr text; v_local text; v_irt text; v_key text; v_last record; v_lastkey text; v_auto text; v_known text;
begin
  select * into m from public.inbound_messages where id = p_inbound_id;
  if not found then raise exception 'fn_mailbox_reply_hard_rule: no inbound message %', p_inbound_id; end if;
  v_addr := lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'));
  if v_addr is null then return 'machine_sender'; end if;
  v_local := split_part(v_addr, '@', 1);
  if public.fn_inbound_is_bounce(m.from_email, m.subject, m.raw) then return 'bounce'; end if;
  v_known := public.fn_mail_sender_known(v_addr);
  if public.fn_is_founder_own_inbox(v_addr) or v_known = 'staff' then return 'founder_inbox'; end if;
  if split_part(v_addr, '@', 2) ~ '(^|\.)quotesdone\.(com|ae)$' then return 'own_domain'; end if;
  if public.fn_is_machine_sender(m.from_email)
     or v_local ~ '(^|[-_.+])(no-?reply|do-?not-?reply|donotreply|notifications?|notify|alerts?|mailer|newsletters?)([-_.+0-9]|$)' then
    return 'machine_sender';
  end if;
  v_auto := lower(btrim(coalesce(m.raw->>'auto_submitted', '')));
  if (v_auto not in ('', 'no') and not (v_auto = 'auto-generated' and coalesce(v_known, '') in ('customer', 'supplier')))
     or btrim(coalesce(m.raw->>'x_autoreply', '')) <> ''
     or lower(btrim(coalesce(m.raw->>'precedence', ''))) = 'auto_reply' then
    return 'auto_submitted';
  end if;
  -- resend_inbound stores List-Unsubscribe, else List-Id, as list_unsubscribe (steps/supplier_docs.ts); list_id if it ever does
  if btrim(coalesce(m.raw->>'list_unsubscribe', '')) <> '' or btrim(coalesce(m.raw->>'list_id', '')) <> ''
     or lower(btrim(coalesce(m.raw->>'precedence', ''))) in ('bulk', 'list', 'junk') then
    return 'list_mail';
  end if;
  -- the founder writes from this mailbox in Outlook by hand: a reply to that mail names a Message-ID we never sent and
  -- quotes our mailbox as its From (inbound 1483: In-Reply-To <...PROD.OUTLOOK.COM>, "From: ... <supplier@quotesdone.com>")
  v_irt := nullif(btrim(coalesce(m.raw->>'in_reply_to', '')), '');
  if v_irt is not null and not public.fn_mail_reply_target_is_ours(v_irt, v_addr)
     and coalesce(m.body, '') ~* 'from:[^\n]{0,200}<?(supplier@quotesdone\.com|suppliers@mail\.quotesdone\.com)' then
    return 'replies_to_mail_sent_by_hand';
  end if;
  -- the last answer in this thread was a person's: the Inbox send of a person, or a reply whose author is no seat
  v_key := public.fn_mail_thread_key(m.raw);
  select i.replied_by into v_last from public.inbound_messages i
   where i.id <> m.id and i.replied_at is not null and i.created_at <= m.created_at
     and position(v_addr in lower(coalesce(i.from_email, ''))) > 0
     and v_key <> '' and public.fn_mail_thread_key(i.raw) = v_key
   order by i.replied_at desc limit 1;
  if found and (v_last.replied_by is null or v_last.replied_by = 'founder'
                or not exists (select 1 from public.org_role r where r.role_id = v_last.replied_by)) then
    return 'person_in_thread';
  end if;
  select n.dedupe_key into v_lastkey from public.notifications n
   where n.type = 'inbound_reply' and n.channel = 'email' and lower(btrim(n.to_email)) = v_addr and n.created_at <= now()
   order by n.id desc limit 1;
  if v_lastkey like 'mailbox_person_reply:%' then return 'person_in_thread'; end if;
  if exists (select 1 from public.notifications n where n.dedupe_key = public.fn_mailbox_auto_reply_key(m.id)) then return 'daily_cap'; end if;
  return null;
end $fn$;
revoke execute on function public.fn_mailbox_reply_hard_rule(bigint) from public, anon, authenticated;

-- What an inbound mail is owed, read from the readings already made: answered | no_reply_needed (with the reading's reason) |
-- with_sales_engineer | decide ('unclear', or a code rule that decided it and no longer decides it alone: the model reads it) | owed.
create or replace function public.fn_inbound_email_reply_owed(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare m public.inbound_messages; d public.mailbox_reply_decision; v_same text;
begin
  select * into m from public.inbound_messages where id = p_id;
  if not found then return jsonb_build_object('state', 'no_reply_needed', 'reason', 'the message is no longer on file'); end if;
  if m.replied_at is not null then
    return jsonb_build_object('state', 'answered', 'reason', 'answered by ' || coalesce(m.replied_by, 'the inbox'), 'at', m.replied_at);
  end if;
  select * into d from public.mailbox_reply_decision where inbound_message_id = p_id;
  if found and d.reading = 'unclear' then
    return jsonb_build_object('state', 'decide', 'reason', 'the supplier-mailbox reading could not tell (' || left(coalesce(d.why, ''), 300) || ')');
  end if;
  if found and d.method = 'code' and d.hard_rule is not null and public.fn_mailbox_reply_hard_rule(p_id) is null then
    return jsonb_build_object('state', 'decide', 'reason', 'decided by the code rule ' || d.hard_rule || ', which no longer decides it alone: the model reads it');
  end if;
  if found and not d.may_reply then
    return jsonb_build_object('state', 'no_reply_needed', 'reason',
      left('the supplier-mailbox reading (' || d.method || coalesce(', ' || d.model, '') || ') said no answer: ' || d.reading
           || coalesce(' (' || d.hard_rule || ')', '') || ': ' || coalesce(d.why, ''), 600));
  end if;
  if m.ai_category = 'no_auto_reply' then
    return jsonb_build_object('state', 'no_reply_needed', 'reason', left(coalesce(nullif(m.ai_summary, ''), 'not answered automatically (customer_mail.ts noAutoReply)'), 600));
  end if;
  if m.ai_category = 'test_reply' then
    return jsonb_build_object('state', 'no_reply_needed', 'reason', 'the founder''s own mailbox writing to us (a test reply, trg_a05_test_reply_leaves_review)');
  end if;
  if m.ai_category in ('spam', 'opt_out') then
    return jsonb_build_object('state', 'no_reply_needed', 'reason', left('the triage model read it as ' || m.ai_category || coalesce(': ' || nullif(m.ai_summary, ''), ''), 600));
  end if;
  select s.state into v_same from public.supplier_reply_same_day s where s.inbound_message_id = p_id;
  if v_same in ('owed', 'escalated') then
    return jsonb_build_object('state', 'with_sales_engineer', 'reason', 'a supplier''s reply the sales engineer answers the same working day (supplier_reply_same_day ' || v_same || ')');
  end if;
  return jsonb_build_object('state', 'owed', 'reason', coalesce('triaged as ' || m.ai_category, 'not yet triaged'));
end $fn$;
revoke execute on function public.fn_inbound_email_reply_owed(bigint) from public, anon, authenticated;

-- ── H1.4 THE E-MAIL CASE SUMMARY A REPLY OWES IS CAUGHT UP TOO (the beat read WhatsApp only) ─────────────────────────────
-- email_triage writes the case summary after the reply, past the response (recordCaseExchange, never awaited): a worker ended
-- first leaves it owed, exactly as on WhatsApp, and fn_support_case_summaries_owed reads only WhatsApp cases. This lists the
-- e-mail cases owed one, with the exchange itself (their last answered mail and the reply that went), so resilience_ping's
-- caseCatchup step writes it through the same summariseExchange (ticks/customer_support.ts emailCaseCatchup).
create or replace function public.fn_support_case_email_summaries_owed(p_limit integer default 3)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.last_inbound_at), '[]'::jsonb)
    from (
      select c.case_ref, c.summary_text, c.summary_version, c.last_inbound_at, p.id as profile,
             left(coalesce(m.subject, '') || E'\n' || coalesce(m.body, ''), 1500) as their_message,
             left(n.body, 1500) as our_reply
        from public.support_case c
        join public.support_customer_profile p on p.id = c.customer_profile_id
        cross join lateral (
          select i.* from public.inbound_messages i
           where p.email is not null and lower(substring(coalesce(i.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)')) = lower(p.email)
             and i.replied_at is not null and i.created_at >= c.last_inbound_at - interval '2 minutes'
           order by i.replied_at desc limit 1) m
        cross join lateral (
          select x.body from public.notifications x
           where x.type = 'inbound_reply' and x.channel = 'email' and lower(btrim(x.to_email)) = lower(p.email)
             and x.created_at >= m.replied_at - interval '2 minutes' and coalesce(btrim(x.body), '') <> ''
           order by x.id limit 1) n
       where c.state <> 'closed' and c.last_channel = 'email'
         and c.last_inbound_at between now() - interval '24 hours' and now() - interval '5 minutes'
         and not exists (select 1 from public.support_case c2
                          where c2.customer_profile_id = c.customer_profile_id and c2.summary_updated_at >= c.last_inbound_at)
         -- each catch-up is a paid model call: a fixture address only while a rehearsal window is open
         and (not public.fn_is_demo_email(p.email)
              or coalesce((select (d.value #>> '{}')::boolean from public.decision_policy d where d.key = 'demo_rehearsal_active'), false))
       order by c.last_inbound_at
       limit greatest(1, least(coalesce(p_limit, 3), 20))
    ) x;
$fn$;
revoke execute on function public.fn_support_case_email_summaries_owed(integer) from public, anon, authenticated;
grant execute on function public.fn_support_case_email_summaries_owed(integer) to service_role;

-- ── H1.5 THE WEEKLY REVIEW COUNTS OWED MESSAGES IN THE RESPONSE TIME ─────────────────────────────────────────────────────
-- Live body (the_case_review_counts_only_customers_and_times_the_whatsapp_reply.sql) with: e-mail and WhatsApp percentiles over
-- answered AND owed messages (an owed one at its age so far), the closed-with-a-reason count apart, reserved fixture numbers as
-- fixtures, complaints by channel and read as fixtures by their marker.
create or replace function public.fn_customer_support_case_review_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_from timestamptz := now() - interval '7 days';
  v_week date := (now() at time zone 'Asia/Dubai')::date;
  v_founder text[]; v_email jsonb; v_wa jsonb; v_chat jsonb; v_repeat jsonb; v_complaints jsonb; v_knowledge jsonb;
  v_metrics jsonb; g record; v_gap jsonb; v_filed int := 0;
begin
  select coalesce(array_agg(right(regexp_replace(value, '[^0-9]', '', 'g'), 9)), '{}') into v_founder
    from public.app_secrets where key in ('founder_mobile', 'founder_public_phone', 'admin_mfa_phone')
     and length(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g')) >= 9;

  -- email: a customer contact only (fn_support_email_is_a_customer_contact names every exclusion). AN OWED MAIL COUNTS AS OPEN FOR
  -- N MINUTES (16 Nov 2026, COO hole H1): the percentiles were taken over replied mail only, so a week of unanswered mail read
  -- "p90 first reply 0 min". Each mail is answered, closed with its reason (the reading said no answer: not owed, counted apart),
  -- or owed (no reply yet: its age so far is its first-reply time, a floor that grows until it is answered).
  select jsonb_build_object(
           'received', count(*), 'replied', count(*) filter (where s.st = 'answered'),
           'unanswered', count(*) filter (where m.replied_at is null),
           'closed_no_reply_needed', count(*) filter (where s.st = 'no_reply_needed'),
           'owed_unanswered', count(*) filter (where s.st in ('owed', 'decide', 'with_sales_engineer')),
           'oldest_owed_hours', round((max(extract(epoch from now() - m.created_at) / 3600) filter (where s.st in ('owed', 'decide', 'with_sales_engineer')))::numeric, 1),
           'median_first_reply_minutes', round((percentile_cont(0.5) within group (order by extract(epoch from coalesce(m.replied_at, now()) - m.created_at) / 60)
                                                filter (where s.st <> 'no_reply_needed'))::numeric),
           'p90_first_reply_minutes', round((percentile_cont(0.9) within group (order by extract(epoch from coalesce(m.replied_at, now()) - m.created_at) / 60)
                                             filter (where s.st <> 'no_reply_needed'))::numeric),
           'times_include_owed', true)
    into v_email
    from public.inbound_messages m
    cross join lateral (select public.fn_inbound_email_reply_owed(m.id)->>'state' as st) s
   where m.created_at >= v_from
     and public.fn_support_email_is_a_customer_contact(m.from_email, m.to_email, m.owner_role, m.subject, v_fx);

  -- whatsapp: timed from replied_at (wa_inbound waRow, from 30 Sep 2026); an untimed answered row is not guessed, and an
  -- unanswered one counts as open for N minutes (as e-mail above). A reserved fixture number is a fixture (fn_is_demo_phone).
  select jsonb_build_object(
           'received', count(*), 'replied', count(*) filter (where w.reply is not null and coalesce(w.sent, false)),
           'unanswered', count(*) filter (where w.reply is null or not coalesce(w.sent, false)),
           'timed', count(w.replied_at),
           'median_first_reply_minutes', round((percentile_cont(0.5) within group (order by extract(epoch from
               case when w.reply is not null and coalesce(w.sent, false) then w.replied_at else now() end - w.created_at) / 60)
               filter (where w.replied_at is not null or w.reply is null or not coalesce(w.sent, false)))::numeric, 1),
           'p90_first_reply_minutes', round((percentile_cont(0.9) within group (order by extract(epoch from
               case when w.reply is not null and coalesce(w.sent, false) then w.replied_at else now() end - w.created_at) / 60)
               filter (where w.replied_at is not null or w.reply is null or not coalesce(w.sent, false)))::numeric, 1),
           'times_include_owed', true)
    into v_wa
    from public.wa_messages w
   where w.created_at >= v_from and coalesce(btrim(w.inbound), '') <> ''
     -- a row kept on purpose with no reply of its own (burst, thank-you, loop, unverified) is not a message waiting for one
     and coalesce(btrim(w.meta->>'no_autoreply_reason'), '') = ''
     and not (right(regexp_replace(coalesce(w.wa_from, ''), '[^0-9]', '', 'g'), 9) = any (v_founder))
     and (coalesce(w.profile_name, '') like 'ZZ DEMO%' or public.fn_is_demo_phone(w.wa_from)) = v_fx;

  -- repeat contact: the same person on two or more distinct Dubai days of the week
  select jsonb_build_object('people', count(*), 'contacts', coalesce(sum(r.days), 0))
    into v_repeat
    from (select who, count(distinct d) days from (
            select 'email:' || lower(btrim(m.from_email)) who, (m.created_at at time zone 'Asia/Dubai')::date d
              from public.inbound_messages m
             where m.created_at >= v_from and coalesce(btrim(m.from_email), '') <> ''
               and public.fn_support_email_is_a_customer_contact(m.from_email, m.to_email, m.owner_role, m.subject, v_fx)
            union all
            select 'whatsapp:' || right(regexp_replace(w.wa_from, '[^0-9]', '', 'g'), 9), (w.created_at at time zone 'Asia/Dubai')::date
              from public.wa_messages w
             where w.created_at >= v_from and coalesce(btrim(w.inbound), '') <> '' and coalesce(btrim(w.wa_from), '') <> ''
               and not (right(regexp_replace(w.wa_from, '[^0-9]', '', 'g'), 9) = any (v_founder))
               and (coalesce(w.profile_name, '') like 'ZZ DEMO%' or public.fn_is_demo_phone(w.wa_from)) = v_fx) c
          group by who having count(distinct d) >= 2) r;

  select jsonb_build_object('opened', count(*) filter (where t.created_at >= v_from),
                            'final_response_given', count(*) filter (where t.final_response_at >= v_from),
                            'past_respond_due', count(*) filter (where t.final_response_at is null and t.respond_due < now()),
                            'by_channel', (select coalesce(jsonb_object_agg(z.channel, z.n), '{}'::jsonb) from (select t2.channel, count(*) n from public.complaint_tickets t2
                                            where t2.created_at >= v_from and public.fn_complaint_is_fixture(t2.email, t2.fixture) = v_fx group by t2.channel) z))
    into v_complaints
    from public.complaint_tickets t
   where public.fn_complaint_is_fixture(t.email, t.fixture) = v_fx
     and (t.created_at >= v_from or t.final_response_at >= v_from or t.final_response_at is null);

  -- UNANSWERED QUESTIONS BECOME KNOWLEDGE REQUESTS, through the one door, once.
  for g in select a.id, a.message from public.assistant_logs a
            where a.answered = false and a.gap_task_id is null and a.created_at >= v_from
              and coalesce(btrim(a.message), '') <> '' and (coalesce(a.message, '') like 'ZZ DEMO%') = v_fx
            order by a.id for update of a skip locked loop
    v_gap := public.fn_support_knowledge_gap(g.message, 'weekly_case_review', 'website_widget');
    if coalesce((v_gap->>'ok')::boolean, false) and v_gap->>'task_id' is not null then
      update public.assistant_logs set gap_task_id = (v_gap->>'task_id')::bigint where id = g.id;
      v_filed := v_filed + 1;
    end if;
  end loop;

  -- counted AFTER the filing loop, so "filed" covers what site_assistant filed at refusal and what this review filed
  select jsonb_build_object('questions', count(*), 'answered', count(*) filter (where g2.answered),
                            'not_answered', count(*) filter (where not g2.answered),
                            'not_answered_filed', count(*) filter (where not g2.answered and g2.gap_task_id is not null),
                            'not_answered_unfiled', count(*) filter (where not g2.answered and g2.gap_task_id is null))
    into v_chat
    from public.assistant_logs g2
   where g2.created_at >= v_from and (coalesce(g2.message, '') like 'ZZ DEMO%') = v_fx;

  select jsonb_build_object('opened_this_week', count(*) filter (where k.first_asked_at >= v_from),
                            'asked_again_this_week', count(*) filter (where k.first_asked_at < v_from and k.last_asked_at >= v_from),
                            'still_open', count(*) filter (where k.status = 'open'),
                            'filed_by_this_review', v_filed)
    into v_knowledge
    from public.sales_knowledge_gap k
   where (k.question like 'ZZ DEMO%') = v_fx and (k.last_asked_at >= v_from or k.status = 'open');

  v_metrics := jsonb_build_object('from', v_from, 'to', now(), 'email', v_email, 'whatsapp', v_wa, 'chat', v_chat,
                                  'repeat_contacts', v_repeat, 'complaints', v_complaints, 'knowledge', v_knowledge);
  -- a fixture run never overwrites the real week's row
  if not v_fx or not exists (select 1 from public.customer_support_case_review where week_ending = v_week and not fixture) then
    insert into public.customer_support_case_review (week_ending, metrics, knowledge_filed, fixture)
    values (v_week, v_metrics, v_filed, v_fx)
    on conflict (week_ending) do update
      set metrics = excluded.metrics, knowledge_filed = customer_support_case_review.knowledge_filed + excluded.knowledge_filed,
          fixture = excluded.fixture, reviewed_at = now();
  end if;
  return jsonb_build_object('week_ending', v_week, 'knowledge_filed', v_filed, 'fixture', v_fx) || v_metrics;
end $fn$;
revoke execute on function public.fn_customer_support_case_review_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_case_review_tick() to service_role;

-- The 24 h first-reply watch: live body (fn_support_reply_watch_tick) with the same two exclusions: a mail closed with its reason,
-- and a reserved fixture number.
create or replace function public.fn_support_reply_watch_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_sla numeric := public.fn_seat_clock_policy('support_first_reply_sla_hours', 24);
  v_cut timestamptz; v_founder text[]; c text; v_n int; v_oldest timestamptz; v_ids jsonb; v_median numeric;
  v_out jsonb := '{}'::jsonb;
begin
  v_cut := now() - make_interval(secs => (v_sla * 3600)::double precision);
  select coalesce(array_agg(right(regexp_replace(value, '[^0-9]', '', 'g'), 9)), '{}') into v_founder
    from public.app_secrets where key in ('founder_mobile', 'founder_public_phone', 'admin_mfa_phone')
     and length(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g')) >= 9;

  foreach c in array array['email', 'whatsapp', 'chat'] loop
    if c = 'email' then
      select count(*), min(m.created_at), coalesce(jsonb_agg(m.id order by m.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.inbound_messages m
       where m.created_at > now() - interval '30 days' and m.created_at < v_cut and m.replied_at is null
         and coalesce(m.to_email, '') !~* '^expenses@' and coalesce(m.owner_role, '') <> 'accountant'
         -- 19 Oct 2026: a machine sender cannot be answered, and calendar+ is the founder's own approval inbox.
         -- 27 Oct 2026: the machine word is matched anywhere in the sender's LOCAL PART as a whole token (start,
         -- or bounded by hyphen/underscore), not only at its start: security-noreply@ waited 30 days as a customer.
         -- A dot does not bound it on the left, so a person whose name merely contains the word stays counted.
         -- 27 Oct 2026 (review of #1684): the local part is read from the address inside <...> first, so a quoted
         -- display name that itself looks like a machine address cannot hide the real sender, and the word must
         -- END at a separator, digit or the end of the local part, so a longer word that merely starts with it is
         -- a person.
         and coalesce(m.to_email, '') !~* '^calendar\+'
         and not public.fn_is_machine_sender(m.from_email)
         and not public.fn_is_demo_email(m.from_email)
         -- 16 Nov 2026 (H1): a mail the reading already closed as needing no answer is not waiting for one
         and public.fn_inbound_email_reply_owed(m.id)->>'state' <> 'no_reply_needed';
      select percentile_cont(0.5) within group (order by extract(epoch from m.replied_at - m.created_at) / 60) into v_median
        from public.inbound_messages m
       where m.replied_at is not null and m.created_at > now() - interval '7 days'
         and coalesce(m.to_email, '') !~* '^expenses@' and coalesce(m.owner_role, '') <> 'accountant';
    elsif c = 'whatsapp' then
      select count(*), min(w.created_at), coalesce(jsonb_agg(w.id order by w.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.wa_messages w
       where w.created_at > now() - interval '30 days' and w.created_at < v_cut
         and coalesce(btrim(w.inbound), '') <> '' and (w.reply is null or not coalesce(w.sent, false))
         and not (right(regexp_replace(coalesce(w.wa_from, ''), '[^0-9]', '', 'g'), 9) = any (v_founder))
         and not public.fn_is_demo_phone(w.wa_from);   -- a reserved fixture number is never a customer waiting (16 Nov 2026)
      v_median := null;   -- the WhatsApp reply is written in the same row as the inbound: minutes are not recorded
    else
      select count(*), min(g.created_at), coalesce(jsonb_agg(g.id order by g.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.assistant_logs g
        left join public.org_tasks t on t.id = g.gap_task_id
       where g.answered = false and g.created_at > now() - interval '30 days' and g.created_at < v_cut
         and coalesce(t.status, 'open') not in ('done', 'cancelled');
      select percentile_cont(0.5) within group (order by extract(epoch from t.updated_at - g.created_at) / 60) into v_median
        from public.assistant_logs g join public.org_tasks t on t.id = g.gap_task_id
       where g.answered = false and t.status = 'done' and t.updated_at > g.created_at and g.created_at > now() - interval '7 days';
    end if;

    if v_n > 0 then
      perform public.fn_it_engineer_finding_upsert('support_reply_sla:' || c,
        v_n || ' ' || c || ' message(s) have waited more than ' || v_sla || ' h for a first reply (oldest '
          || to_char(v_oldest at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai)',
        'customer_support first-reply watch (fn_support_reply_watch_tick) -> ' || c, 'customer_facing', v_n,
        jsonb_build_object('channel', c, 'sla_hours', v_sla, 'waiting', v_n, 'oldest', v_oldest,
                           'ids', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select x from jsonb_array_elements(v_ids) x limit 20) z),
                           'median_first_reply_minutes_7d', round(v_median), 'owner_seat', 'customer_support', 'duty', 'reply_time'),
        '{}'::text[], array['whether the customer was answered on another channel'], 'customer_support');
    elsif exists (select 1 from public.it_engineer_finding where issue_key = 'support_reply_sla:' || c and closed_at is null) then
      -- 27 Oct 2026: the note says what cleared each message it last listed (answered, aged out, no longer
      -- counted, gone), never a reply that did not happen.
      perform public.fn_it_engineer_finding_close('support_reply_sla:' || c,
        public.fn_support_reply_watch_close_note(c,
          (select f.evidence from public.it_engineer_finding f where f.issue_key = 'support_reply_sla:' || c and f.closed_at is null),
          v_sla));
    end if;
    v_out := v_out || jsonb_build_object(c, jsonb_build_object('over_sla', v_n, 'median_first_reply_minutes_7d', round(v_median)));
  end loop;
  return jsonb_build_object('ok', true, 'sla_hours', v_sla) || v_out;
end $fn$;
revoke execute on function public.fn_support_reply_watch_tick() from public, anon, authenticated;
grant execute on function public.fn_support_reply_watch_tick() to service_role;
