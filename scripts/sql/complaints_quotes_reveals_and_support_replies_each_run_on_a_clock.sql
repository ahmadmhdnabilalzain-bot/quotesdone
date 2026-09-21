-- COMPLAINTS, SHORT QUOTES, REVEALS AND SUPPORT REPLIES EACH RUN ON A CLOCK (22 Sep 2026, ceo).
--
-- Founder instruction 583 (seat tasks), gaps 2-5. Four duties that had no clock, each on the seat that
-- owns it, all deterministic (no model), all on the company heartbeat through ONE step (seatClocks), all
-- through the existing machinery: fn_seat_handoff, fn_customer_support_takes_delivery (the outbox),
-- fn_support_report_to_ceo, fn_it_engineer_finding_upsert. Nothing here ever addresses the founder.
--
-- MEASURED 22 Sep 2026 on production (htdblwldjkcgjvmqkbeh), read-only:
--   * Complaints: public.complaint_tickets stamps acknowledge_due (2 working days) and respond_due (10
--     working days) -- the Complaints Policy's own promise, legal.json -- but the only readers of
--     respond_due are fn_complaint_lookup and fn_complaint_open. Nothing checks a deadline on a schedule.
--     0 tickets today.
--   * Quotes: no RFQ carries a deadline. app_secrets.sla_quote_hours = 24 exists and NOTHING reads it
--     (no routine, no function). inquiries.no_quote_notified exists and nothing writes it. The top-3 rule
--     (the comparison report is the top 3; founder rule) has no sweep: 8 inquiries, all fixtures, one
--     ('ZZ' customer qd-12ddadff…) with 6 invited suppliers and 0 quotes.
--   * Reveals: transactions.revealed_at is the reveal; the only post-reveal ask is the rating request,
--     21 days after (app_secrets.rating_request_days_after_reveal; memory: "Support emails 3 weeks after
--     the reveal date"). Nothing asks whether the job went ahead; customer_api action complete_inquiry
--     ("I hired this supplier" / «تعاقدتُ مع هذا المورّد») records it when the customer presses it.
--   * Support replies: nothing measures time to first reply. Email: inbound_messages.replied_at
--     (20 rows, all to the expenses mailbox). WhatsApp: wa_messages (13 rows; the one unsent reply is the
--     founder's own "Test" on 10 Sep). Chat: assistant_logs.answered=false opens a gap task in org_tasks
--     (18 such questions, every task done or cancelled today).
--
-- WHAT THIS CHANGES:
--   1. decision_policy rows the CEO can change (inserted once, never overwritten by a re-apply):
--      complaint_seat_warning_working_days 2, rfq_short_sweep_hours_before_deadline 8,
--      reveal_outcome_check_days 7, support_first_reply_sla_hours 24. The RFQ deadline itself is the
--      existing app_secrets.sla_quote_hours (24), read for the first time here, counted from the first
--      supplier invitation (min inquiry_matches.sent_at). The target of 3 quotes is the founder's top-3
--      rule and is a constant, not a setting.
--   2. fn_complaint_clock_tick (customer_support): from 2 working days before a ticket's due date the
--      seat holds a complaint.due handoff (closed by this tick when the final response is given); once the
--      due date passes the matter is reported to the CEO (support_ceo_report, once per ticket and stage).
--   3. fn_rfq_short_of_quotes_tick (sales_engineer): an open request with fewer than 3 live quotes, from
--      8 h before its deadline: (a) ONCE, invites more suppliers from the same matcher
--      (fn_match_capability, exact trades via fn_taxonomy_trades_for, up to decision_policy
--      match_max_fanout more, the grant's gates untouched -- no padding, no nearest trade); (b) reminds
--      every invited supplier who has not quoted, once; (c) at the deadline tells the customer, once,
--      how many quotes arrived and that the request stays open. Never a fixture and a real party together.
--   4. fn_reveal_outcome_check_tick (customer_support): 7 days after a reveal, once, asks the customer
--      whether they contacted/hired the supplier, pointing at the portal's "I hired this supplier". Only
--      inside the window before the 21-day rating ask, never after it, never on a refunded reveal, never
--      when the outcome is already recorded. It is an outcome check, not a rating.
--   5. fn_support_reply_watch_tick (customer_support): per channel (email, whatsapp, chat), any inbound
--      still without a first reply after the SLA is the IT finding support_reply_sla:<channel>, owned by
--      customer_support; closed when the channel is clear. Median first-reply minutes (7 days) is in the
--      evidence.
--   6. fn_seat_clocks_tick runs the four, each isolated; resilience_step 'seatClocks' every 30 min.
--
-- THE GATE THAT KEEPS REAL PEOPLE OUT (fn_seat_clock_refusal): a message is written only when the
-- subject and the recipient are the same kind -- a fixture subject (ZZ DEMO / is_demo / @example.invalid)
-- may only ever write to a fixture address, which zzzz_notifications_demo_capture records 'suppressed' and
-- never sends; a real subject only to a real, sendable address. Today every inquiry, reveal and ticket is
-- a fixture, so nothing reaches a person; the daily run also skips fixtures entirely (p_include_fixtures
-- exists for the probe). The EN and AR texts are written, not translated: formal Gulf business Arabic.
--
-- WHAT IT DOES NOT CHANGE: fn_complaint_open's 2/10 working-day stamps; the rating request; the matcher,
-- its fanout policy and the grant; customer_api's rfq_no_supplier alert (another seat); inquiries'
-- status. A customer who did NOT go ahead can say so only by replying (support's inbox) -- the portal has
-- no "did not proceed" button; this file does not add one.
--
-- ORDER: deploy resilience_ping (STEP_RUN gains seatClocks) BEFORE applying this file -- a schedule row
-- for a step the deployed code lacks fails every tick (every_tick_step_is_scheduled.mjs). Then run
-- scripts/sql/complaints_quotes_reveals_and_support_replies_each_run_on_a_clock_probe.sql -> its verdict row reads OK (the change file itself returns no verdict).
--   node scripts/apply_sql.mjs scripts/sql/complaints_quotes_reveals_and_support_replies_each_run_on_a_clock.sql --apply --ddl

-- ── 1. the settings the CEO can change ────────────────────────────────────────────────────────────
insert into public.decision_policy (key, value, description) values
  ('complaint_seat_warning_working_days', '2'::jsonb,
   'fn_complaint_clock_tick: customer_support holds a complaint.due handoff from this many working days before the ticket''s due date. Past the due date the ticket is reported to the CEO. The due dates themselves are the Complaints Policy''s (2 / 10 working days).'),
  ('rfq_short_sweep_hours_before_deadline', '8'::jsonb,
   'fn_rfq_short_of_quotes_tick: hours before an RFQ''s deadline (first invitation + app_secrets.sla_quote_hours) at which a request with fewer than 3 quotes is widened once and its invited suppliers reminded once.'),
  ('reveal_outcome_check_days', '7'::jsonb,
   'fn_reveal_outcome_check_tick: days after a reveal at which customer_support asks, once, whether the customer contacted or hired the supplier. Must stay below app_secrets.rating_request_days_after_reveal (21): the check is never sent once the rating ask is due.'),
  ('support_first_reply_sla_hours', '24'::jsonb,
   'fn_support_reply_watch_tick: an inbound email, WhatsApp message or unanswered chat question still without a first reply after this many hours is the finding support_reply_sla:<channel>.')
on conflict (key) do nothing;

create or replace function public.fn_seat_clock_policy(p_key text, p_default numeric)
returns numeric
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce((select case when jsonb_typeof(value) = 'number' then (value #>> '{}')::numeric end
                     from public.decision_policy where key = p_key), p_default)
$fn$;
revoke execute on function public.fn_seat_clock_policy(text, numeric) from public, anon, authenticated;

-- ── 2. the gate ───────────────────────────────────────────────────────────────────────────────────
-- WHAT A SUPPRESSION STOPS, IN SQL. The rule is the founder's (instruction 632) and its definition is
-- supabase/functions/_shared/suppression_policy.ts (PR #804): reason 'unsubscribe' is a preference and stops
-- only the cold outreach in OPT_OUT_TYPES; a bounce, a complaint or a guardrail block stops everything.
-- fn_email_sendable refuses on ANY suppression row, so a supplier who opted out of the campaign would also
-- lose the reminder for a request he was matched to -- and the agreement charges for non-response. This is
-- the SQL mirror; every_duty_has_an_owner_and_a_clock.test.mjs fails if the two lists or the two answers
-- ever disagree. 'supplier_rfq_widened_invite' is this file's cold invitation (a supplier matched only by
-- the short-of-quotes sweep, who never asked for this request) and is added to the TS list in the same PR.
create or replace function public.fn_opt_out_types()
returns text[]
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select array['supplier_invite', 'supplier_registration_reminder', 'supplier_rfq_widened_invite']::text[]
$fn$;
revoke execute on function public.fn_opt_out_types() from public, anon, authenticated;

create or replace function public.fn_suppression_stops(p_reason text, p_type text)
returns boolean
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select lower(btrim(coalesce(p_reason, ''))) <> 'unsubscribe' or coalesce(p_type, '') = any (public.fn_opt_out_types())
$fn$;
revoke execute on function public.fn_suppression_stops(text, text) from public, anon, authenticated;

-- Same kind or nothing. The reveal-receipt probe of 10 Sep wrote about a fixture to a REAL supplier; this
-- makes that shape impossible here rather than cleaned up afterwards. Returns NULL when the message may be
-- written, otherwise the reason it may not (which the caller records -- a skip is never silent).
-- The address checks are fn_email_sendable's own tables (email_suppressions, email_domain_mx,
-- email_block_pattern), with the suppression read through the policy above instead of "any row".
create or replace function public.fn_seat_clock_refusal(p_subject_is_fixture boolean, p_to text, p_type text)
returns text
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_e text := lower(btrim(coalesce(p_to, ''))); v_reason text;
begin
  if v_e !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+[.][a-z]{2,}$' then return 'no valid address'; end if;
  if p_subject_is_fixture then
    return case when public.fn_is_demo_email(v_e) then null else 'a fixture subject may not write to a real address' end;
  end if;
  if public.fn_is_demo_email(v_e) then return 'a real subject may not write to a fixture address'; end if;
  if v_e in (select lower(btrim(x)) from public.app_secrets s, unnest(string_to_array(coalesce(s.value, ''), ',')) x
              where s.key = 'admin_emails') then return 'the founder is never addressed by a seat clock'; end if;
  select s.reason into v_reason from public.email_suppressions s
   where lower(s.email) = v_e and public.fn_suppression_stops(s.reason, p_type) limit 1;
  if found then
    return case when lower(btrim(coalesce(v_reason, ''))) = 'unsubscribe' then 'opted out (unsubscribe) of ' || p_type
                else 'suppressed: ' || coalesce(v_reason, 'no reason recorded') end;
  end if;
  if exists (select 1 from public.email_domain_mx m where m.domain = split_part(v_e, '@', 2)
              and m.has_mx = false and m.kind in ('nxdomain', 'no_records')) then return 'the domain does not accept mail'; end if;
  select b.reason into v_reason from public.email_block_pattern b where b.active and v_e ~ b.pattern limit 1;
  if found then return 'blocked: ' || coalesce(v_reason, 'block pattern'); end if;
  return null;
end
$fn$;
revoke execute on function public.fn_seat_clock_refusal(boolean, text, text) from public, anon, authenticated;

-- Already asked? Read from the delivery requests themselves (fn_seat_handoff's own key), not a status column.
create or replace function public.fn_seat_clock_asked(p_dedupe_key text)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select exists (select 1 from public.agent_actions a
                  where a.kind = 'handoff' and a.agent = 'customer_support'
                    and a.target_id = 'delivery.request:' || p_dedupe_key and a.status <> 'failed')
$fn$;
revoke execute on function public.fn_seat_clock_asked(text) from public, anon, authenticated;

create or replace function public.fn_seat_clock_lead_is_fixture(p public.leads)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(p.is_demo, false) or coalesce(p.company_name, '') ~* '^\s*zz\s*demo'
      or public.fn_is_demo_email(p.email) or public.fn_is_demo_email(p.claimed_by)
$fn$;
revoke execute on function public.fn_seat_clock_lead_is_fixture(public.leads) from public, anon, authenticated;

create or replace function public.fn_seat_clock_customer_is_fixture(p public.customers)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(p.is_demo, false) or coalesce(p.full_name, '') ~* '^\s*zz\s*demo' or public.fn_is_demo_email(p.email)
$fn$;
revoke execute on function public.fn_seat_clock_customer_is_fixture(public.customers) from public, anon, authenticated;

-- ── 3. the words, EN and AR ───────────────────────────────────────────────────────────────────────
-- Written as Gulf business correspondence (the register of app_secrets.invite_body_ar and the supplier
-- reminders): السادة/ … المحترمين، تحية طيبة وبعد، … وتفضلوا بقبول فائق الاحترام والتقدير. No customer free text
-- reaches a supplier: a supplier is told the trade and the emirate only (customer_api AUDIT 1.5).
create or replace function public.fn_seat_clock_compose(p_kind text, p_lang text, p jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_ar boolean := coalesce(p_lang, '') like 'ar%';
  v_lang text := case when coalesce(p_lang, '') like 'ar%' then 'ar' else 'en' end;
  v_site text; v_link text; v_trade text; v_trade_ar text; v_em text; v_em_ar text; v_where text; v_where_ar text;
  v_name text := nullif(btrim(coalesce(p->>'name', '')), '');
  v_n int := coalesce((p->>'quotes')::int, 0);
  v_due text; v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_link := coalesce(v_site, 'https://quotesdone.com') || '/' || v_lang || '/portal';
  select t.label, coalesce(t.label_ar, t.label) into v_trade, v_trade_ar
    from public.taxonomy_trade t
   where t.code = (public.fn_taxonomy_trades_for(array[coalesce(p->>'category', '')]))[1];
  v_trade := coalesce(v_trade, nullif(p->>'category', ''), 'your trade');
  v_trade_ar := coalesce(v_trade_ar, nullif(p->>'category', ''), 'تخصصكم');
  v_em := nullif(btrim(coalesce(p->>'emirate', '')), '');
  v_em_ar := case lower(coalesce(v_em, '')) when 'dubai' then 'دبي' when 'abu dhabi' then 'أبوظبي' when 'sharjah' then 'الشارقة'
               when 'ajman' then 'عجمان' when 'umm al quwain' then 'أم القيوين' when 'ras al khaimah' then 'رأس الخيمة'
               when 'fujairah' then 'الفجيرة' else v_em end;
  v_where := v_trade || coalesce(' in ' || v_em, '');
  v_where_ar := v_trade_ar || coalesce(' في ' || v_em_ar, '');
  v_due := to_char((p->>'deadline')::timestamptz at time zone 'Asia/Dubai', case when v_ar then 'DD/MM/YYYY HH24:MI' else 'DD Mon YYYY, HH24:MI' end);

  if p_kind = 'rfq_invite' then
    if v_ar then
      v_subj := 'طلب عرض سعر جديد: ' || v_where_ar || ' — QuotesDone';
      v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'السادة الكرام،') || E'\n\nتحية طيبة وبعد،\n\n'
        || 'يسرّنا إفادتكم بأن أحد العملاء يطلب عروض أسعار في مجال ' || v_where_ar || '، وقد تمّت مطابقة طلبه مع نطاق أعمال شركتكم المسجّل لدينا. '
        || 'ويُرجى الاطّلاع على تفاصيل الطلب وتقديم عرضكم عبر بوابة الموردين:' || E'\n\n' || v_link
        || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
    else
      v_subj := 'New request for quotation: ' || v_where || ' — QuotesDone';
      v_body := coalesce('Dear ' || v_name || ',', 'Dear Sir or Madam,') || E'\n\n'
        || 'A customer is requesting quotations for ' || v_where || ', and the request matches the scope your company registered with us. '
        || 'Please review the details and submit your quotation in your supplier portal:' || E'\n\n' || v_link;
    end if;
  elsif p_kind = 'rfq_quote_reminder' then
    if v_ar then
      v_subj := 'تذكير: العميل بانتظار عرضكم — ' || v_where_ar;
      v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'السادة الكرام،') || E'\n\nتحية طيبة وبعد،\n\n'
        || 'نودّ تذكيركم بطلب عرض السعر في مجال ' || v_where_ar || ' الذي أُرسل إليكم عبر QuotesDone، إذ لم يصلنا عرضكم بعد. '
        || 'والعميل بانتظار العروض، ونأمل تقديم عرضكم في أقرب وقت، ويُفضَّل قبل ' || v_due || ' بتوقيت دبي.'
        || E'\n\nيمكنكم تقديم عرضكم عبر بوابة الموردين:\n\n' || v_link
        || E'\n\nوفي حال عدم رغبتكم في التقدّم بعرض لهذا الطلب، يُرجى إبلاغنا بذلك عبر البوابة أو بالرد على هذه الرسالة.'
        || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
    else
      v_subj := 'Reminder: the customer is waiting for your quotation — ' || v_where;
      v_body := coalesce('Dear ' || v_name || ',', 'Dear Sir or Madam,') || E'\n\n'
        || 'This is a reminder of the request for quotation for ' || v_where || ' sent to you through QuotesDone; we have not yet received your quotation. '
        || 'The customer is waiting for quotations, and we would appreciate yours as soon as possible, ideally before ' || v_due || ' (Dubai time).'
        || E'\n\nSubmit your quotation in your supplier portal:\n\n' || v_link
        || E'\n\nIf you would rather not quote for this request, please let us know in the portal or by replying to this e-mail.';
    end if;
  elsif p_kind = 'rfq_short_of_quotes' then
    if v_ar then
      v_subj := 'مستجدات طلب عروض الأسعار الخاص بكم — ' || v_where_ar;
      v_body := coalesce('السيد/ة ' || v_name || ' المحترم/ة،', 'عميلنا العزيز،') || E'\n\nتحية طيبة وبعد،\n\n'
        || case when v_n = 0 then 'نفيدكم بأن طلبكم في مجال ' || v_where_ar || ' لم يتلقَّ أي عرض سعر حتى الآن. '
                when v_n = 1 then 'نفيدكم بأن طلبكم في مجال ' || v_where_ar || ' تلقّى حتى الآن عرض سعر واحدًا، ونسعى إلى أن تصلكم ثلاثة عروض على الأقل للمقارنة. '
                else 'نفيدكم بأن طلبكم في مجال ' || v_where_ar || ' تلقّى حتى الآن عرضَي سعر، ونسعى إلى أن تصلكم ثلاثة عروض على الأقل للمقارنة. ' end
        || 'وقد دعونا موردين إضافيين مطابقين لطلبكم، وذكّرنا الموردين المدعوين بتقديم عروضهم، وسيبقى طلبكم مفتوحًا لاستلام العروض.'
        || E'\n\nيمكنكم متابعة العروض فور وصولها عبر بوابتكم:\n\n' || v_link
        || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
    else
      v_subj := 'An update on your request for quotations — ' || v_where;
      v_body := coalesce('Dear ' || v_name || ',', 'Dear Customer,') || E'\n\n'
        || case when v_n = 0 then 'Your request for ' || v_where || ' has not received a quotation yet. '
                when v_n = 1 then 'Your request for ' || v_where || ' has received one quotation so far; we aim for at least three for you to compare. '
                else 'Your request for ' || v_where || ' has received two quotations so far; we aim for at least three for you to compare. ' end
        || 'We have invited more suppliers who match your request, reminded the suppliers already invited, and your request stays open for quotations.'
        || E'\n\nYou can follow the quotations as they arrive in your portal:\n\n' || v_link;
    end if;
  elsif p_kind = 'reveal_outcome_check' then
    if v_ar then
      v_subj := 'هل تواصلتم مع ' || coalesce(p->>'supplier', 'المورّد') || '؟ — QuotesDone';
      v_body := coalesce('السيد/ة ' || v_name || ' المحترم/ة،', 'عميلنا العزيز،') || E'\n\nتحية طيبة وبعد،\n\n'
        || 'مضى أسبوع على اطّلاعكم على بيانات التواصل مع ' || coalesce(p->>'supplier', 'المورّد')
        || ' بشأن طلبكم في مجال ' || v_trade_ar || '، ونودّ الاطمئنان على سير الأمور: هل تواصلتم معهم؟ وهل أُسند العمل إليهم؟'
        || E'\n\nإذا تمّ التعاقد معهم، يُرجى تأكيد ذلك من بوابتكم باختيار «تعاقدتُ مع هذا المورّد» على عرضهم:\n\n' || v_link
        || E'\n\nوإن لم يتواصلوا معكم، أو قرّرتم عدم المضي قدمًا، يكفي الرد على هذه الرسالة وسنتابع الأمر معكم.'
        || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
    else
      v_subj := 'Did you get in touch with ' || coalesce(p->>'supplier', 'the supplier') || '? — QuotesDone';
      v_body := coalesce('Dear ' || v_name || ',', 'Dear Customer,') || E'\n\n'
        || 'It has been a week since you revealed the contact details of ' || coalesce(p->>'supplier', 'the supplier')
        || ' for your ' || v_trade || ' request. We would like to know how it is going: have you been in touch, and did you award them the work?'
        || E'\n\nIf you hired them, please confirm it in your portal by choosing "I hired this supplier" on their quotation:\n\n' || v_link
        || E'\n\nIf they have not contacted you, or you decided not to go ahead, simply reply to this e-mail and we will follow it up with you.';
    end if;
  else
    raise exception 'fn_seat_clock_compose: unknown kind %', p_kind;
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$fn$;
revoke execute on function public.fn_seat_clock_compose(text, text, jsonb) from public, anon, authenticated;

-- One message through customer_support's delivery door, or a reason it was not written.
create or replace function public.fn_seat_clock_deliver(
  p_seat text, p_type text, p_to_role text, p_to text, p_subject_is_fixture boolean, p_lang text, p_kind text, p jsonb,
  p_dedupe_key text, p_inquiry_id uuid default null, p_quote_id uuid default null, p_lead_id bigint default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare m jsonb; v jsonb; v_why text; v_key text := 'seat_clock_not_written:' || p_dedupe_key;
begin
  if public.fn_seat_clock_asked(p_dedupe_key) then return jsonb_build_object('ok', true, 'already', true); end if;
  v_why := public.fn_seat_clock_refusal(p_subject_is_fixture, p_to, p_type);
  if v_why is null then
    m := public.fn_seat_clock_compose(p_kind, p_lang, p);
    v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', p_type, 'requested_by', p_seat, 'channel', 'email', 'to_email', lower(btrim(p_to)), 'to_role', p_to_role,
      'lead_id', p_lead_id, 'inquiry_id', p_inquiry_id, 'quote_id', p_quote_id, 'lang', m->>'lang',
      'subject', m->>'subject', 'body', m->>'body', 'dedupe_key', p_dedupe_key)));
    if coalesce(v->0->>'status', '') <> 'failed' then
      return jsonb_build_object('ok', true, 'delivery', v->0, 'lang', m->>'lang');
    end if;
    v_why := 'the delivery request failed: ' || coalesce(v->0->>'error', 'no error recorded');
  end if;
  -- A SKIP IS RECORDED, NEVER ONLY COUNTED: one finding per message, owned by the seat that wanted to send
  -- it. An opt-out is the recipient's own choice (instruction 632) -- recorded and closed at once, so it is
  -- on the ledger without paging anybody; anything else stays open for the seat to act on. The same opt-out
  -- seen again on the next tick is already on the ledger and is not re-written.
  if v_why like 'opted out%' and exists (select 1 from public.it_engineer_finding
                                          where issue_key = v_key and closed_at is not null and evidence->>'reason' = v_why) then
    return jsonb_build_object('ok', false, 'reason', v_why, 'recorded_as', v_key);
  end if;
  perform public.fn_it_engineer_finding_upsert(v_key,
    left('Not sent (' || p_type || ' to the ' || p_to_role || '): ' || v_why, 300),
    'seat clock ' || p_seat || ' -> fn_seat_clock_deliver', case when v_why like 'opted out%' then 'agent_facing' else 'customer_facing' end, 1,
    jsonb_build_object('type', p_type, 'to_role', p_to_role, 'reason', v_why, 'dedupe_key', p_dedupe_key,
                       'inquiry_id', p_inquiry_id, 'quote_id', p_quote_id, 'lead_id', p_lead_id,
                       'owner_seat', p_seat, 'duty', 'seat_clock', 'demo', p_subject_is_fixture),
    '{}'::text[], '{}'::text[], p_seat);
  if v_why like 'opted out%' then
    perform public.fn_it_engineer_finding_close(v_key, 'recorded: the recipient opted out of this kind of mail, which is the rule (instruction 632)');
  end if;
  return jsonb_build_object('ok', false, 'reason', v_why, 'recorded_as', v_key);
end
$fn$;
revoke execute on function public.fn_seat_clock_deliver(text, text, text, text, boolean, text, text, jsonb, text, uuid, uuid, bigint) from public, anon, authenticated;

-- ── 4. complaints (customer_support) ──────────────────────────────────────────────────────────────
-- The handler for the seat's own complaint.due item: it waits, open in the seat's queue, until
-- fn_complaint_clock_tick sees the final response and completes it.
create or replace function public.fn_complaint_due_waits_for_the_response(p_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object('waiting', coalesce(a.detail->>'waiting_for', 'the final response on this complaint'))
    from public.agent_actions a where a.id = p_id
$fn$;
revoke execute on function public.fn_complaint_due_waits_for_the_response(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
values ('complaint.due', 'customer_support', 'customer_support',
        'A complaint ticket is within complaint_seat_warning_working_days of its due date (Complaints Policy: acknowledge in 2, respond in 10 working days). Open until the final response is given; past the due date the CEO also gets a report.',
        'fn_complaint_due_waits_for_the_response', null, false,
        'scripts/sql/complaints_quotes_reveals_and_support_replies_each_run_on_a_clock.sql')
on conflict (type, from_seat, to_seat) do update
   set meaning = excluded.meaning, handler = excluded.handler, owner_file = excluded.owner_file;

create or replace function public.fn_complaint_clock_tick(p_include_fixtures boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  t public.complaint_tickets; h record; r jsonb;
  v_warn int := public.fn_seat_clock_policy('complaint_seat_warning_working_days', 2)::int;
  v_due timestamptz; v_owed text; v_seat int := 0; v_ceo int := 0; v_closed int := 0; v_refused jsonb := '[]'::jsonb;
begin
  for t in select * from public.complaint_tickets
            where status <> 'final_response' and (p_include_fixtures or not public.fn_is_demo_email(email))
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
end
$fn$;
revoke execute on function public.fn_complaint_clock_tick(boolean) from public, anon, authenticated;

-- ── 5. requests short of quotes (sales_engineer) ──────────────────────────────────────────────────
create or replace function public.fn_rfq_short_of_quotes_tick(p_include_fixtures boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  -- the top-3 rule: the comparison report is the top 3 (founder rule). A constant, not a setting.
  c_target constant int := 3;
  v_window numeric; v_lead numeric := public.fn_seat_clock_policy('rfq_short_sweep_hours_before_deadline', 8);
  v_fanout int := coalesce(public.fn_seat_clock_policy('match_max_fanout', 5), 5)::int;
  r record; s record; l public.leads; v jsonb; v_codes text[]; v_need text; v_value numeric; v_new int;
  v_swept int := 0; v_invited int := 0; v_reminded int := 0; v_told int := 0; v_skipped jsonb := '[]'::jsonb;
begin
  select nullif(regexp_replace(coalesce(value, ''), '[^0-9.]', '', 'g'), '')::numeric into v_window
    from public.app_secrets where key = 'sla_quote_hours';
  v_window := coalesce(v_window, 24);

  for r in
    with open_rfq as (
      select i.*, c.email as cemail, c.locale as clocale, c.full_name as cname,
             public.fn_seat_clock_customer_is_fixture(c) as fixture,
             (select min(m.sent_at) from public.inquiry_matches m where m.inquiry_id = i.id) as first_sent,
             (select count(*) from public.quotes q where q.inquiry_id = i.id
                and coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled')
                and q.stale_at is null)::int as live_quotes
        from public.inquiries i
        join public.customers c on c.id = i.customer_id
       where i.status in ('sent', 'quoted')
    )
    select o.*, o.first_sent + make_interval(secs => (v_window * 3600)::double precision) as deadline
      from open_rfq o
     where o.first_sent is not null
       and o.live_quotes < c_target
       and now() >= o.first_sent + make_interval(secs => ((v_window - v_lead) * 3600)::double precision)
       and now() <  o.first_sent + interval '14 days'
       and (p_include_fixtures or not o.fixture)
     order by o.first_sent
  loop
    v_swept := v_swept + 1;

    -- (a) widen ONCE, from the same matcher, same-kind suppliers only.
    if not coalesce(r.routing ? 'short_sweep', false) then
      v_new := 0;
      v_codes := public.fn_taxonomy_trades_for(case when coalesce(cardinality(r.trades), 0) > 0 then r.trades
                                                    else array[coalesce(r.category, '')] end);
      if coalesce(cardinality(v_codes), 0) > 0 then
        v_need := case when coalesce(r.scope_type, '') ilike '%turnkey%' then 'whole_scope'
                       when coalesce(r.scope_type, '') || ' ' || coalesce(r.role_needed, '') ~* 'supply|material|product' then 'supplies'
                       else 'executes' end;
        v_value := coalesce(r.expected_value, nullif(regexp_replace(coalesce(r.budget, ''), '[^0-9.]', '', 'g'), '')::numeric);
        if v_value is not null and v_value <= 0 then v_value := null; end if;
        for s in select m.supplier_id, m.score, m.why
                   from public.fn_match_capability(v_codes, v_need, '{}'::text[], '{}'::text[], r.scope_type, v_value, r.emirate, 60) m
                   join public.leads ld on ld.id = m.supplier_id
                  where not exists (select 1 from public.inquiry_matches x where x.inquiry_id = r.id and x.supplier_id = m.supplier_id)
                    and public.fn_seat_clock_lead_is_fixture(ld) = r.fixture
                  order by m.score desc
                  limit v_fanout loop
          insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, match_reason)
          values (r.id, s.supplier_id, least(1, greatest(0, round(s.score / 100, 3))),
                  left('short-of-quotes sweep (fn_rfq_short_of_quotes_tick): ' || coalesce(s.why, ''), 400))
          on conflict (inquiry_id, supplier_id) do nothing;
          if found then
            v_new := v_new + 1;
            select * into l from public.leads where id = s.supplier_id;
            v := public.fn_seat_clock_deliver('sales_engineer', 'supplier_rfq_widened_invite', 'supplier',
                   lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))), r.fixture, l.locale, 'rfq_invite',
                   jsonb_build_object('name', l.company_name, 'category', r.category, 'emirate', r.emirate),
                   'rfq_invite:' || r.id || ':' || l.id, r.id, null, l.id);
          end if;
        end loop;
      end if;
      update public.inquiries
         set routing = coalesce(routing, '{}'::jsonb) || jsonb_build_object('short_sweep', jsonb_build_object(
               'at', now(), 'quotes_then', r.live_quotes, 'invited', v_new, 'trades', to_jsonb(v_codes),
               'by', 'sales_engineer (fn_rfq_short_of_quotes_tick)'))
       where id = r.id;
      v_invited := v_invited + v_new;
    end if;

    -- (b) remind each invited supplier who has not quoted, once. Not one invited in the last 2 hours.
    for l in select ld.* from public.inquiry_matches m join public.leads ld on ld.id = m.supplier_id
              where m.inquiry_id = r.id and m.sent_at < now() - interval '2 hours'
                and not exists (select 1 from public.quotes q where q.inquiry_id = r.id and q.supplier_id = m.supplier_id)
                and public.fn_seat_clock_lead_is_fixture(ld) = r.fixture loop
      v := public.fn_seat_clock_deliver('sales_engineer', 'rfq_quote_reminder', 'supplier',
             lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))), r.fixture, l.locale, 'rfq_quote_reminder',
             jsonb_build_object('name', l.company_name, 'category', r.category, 'emirate', r.emirate, 'deadline', r.deadline),
             'rfq_quote_reminder:' || r.id || ':' || l.id, r.id, null, l.id);
      if coalesce((v->>'ok')::boolean, false) and not coalesce((v->>'already')::boolean, false) then v_reminded := v_reminded + 1; end if;
    end loop;

    -- (c) at the deadline, tell the customer once.
    if now() >= r.deadline then
      v := public.fn_seat_clock_deliver('sales_engineer', 'rfq_short_of_quotes', 'customer', r.cemail, r.fixture, r.clocale,
             'rfq_short_of_quotes',
             jsonb_build_object('name', r.cname, 'category', r.category, 'emirate', r.emirate, 'quotes', r.live_quotes),
             'rfq_short_of_quotes:' || r.id, r.id);
      if coalesce((v->>'ok')::boolean, false) and not coalesce((v->>'already')::boolean, false) then v_told := v_told + 1;
      elsif not coalesce((v->>'ok')::boolean, false) then
        v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('inquiry_id', r.id, 'reason', v->>'reason'));
      end if;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'swept', v_swept, 'invited', v_invited, 'reminded', v_reminded,
                            'customers_told', v_told, 'not_written', v_skipped,
                            'deadline_hours', v_window, 'sweep_from_hours_before', v_lead);
end
$fn$;
revoke execute on function public.fn_rfq_short_of_quotes_tick(boolean) from public, anon, authenticated;

-- ── 6. seven days after a reveal (customer_support) ───────────────────────────────────────────────
create or replace function public.fn_reveal_outcome_check_tick(p_include_fixtures boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_days numeric := public.fn_seat_clock_policy('reveal_outcome_check_days', 7);
  v_rating int; d record; v jsonb; v_asked int := 0; v_skipped jsonb := '[]'::jsonb;
begin
  select nullif(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g'), '')::int into v_rating
    from public.app_secrets where key = 'rating_request_days_after_reveal';
  v_rating := coalesce(v_rating, 21);

  for d in
    select t.id as tx_id, t.quote_id, t.inquiry_id, t.supplier_id, c.email as cemail, c.locale as clocale,
           c.full_name as cname, public.fn_seat_clock_customer_is_fixture(c) as fixture,
           l.company_name, i.category
      from public.transactions t
      join public.customers c on c.id = t.customer_id
      left join public.leads l on l.id = t.supplier_id
      left join public.inquiries i on i.id = t.inquiry_id
     where t.revealed_at is not null and t.quote_id is not null
       and t.revealed_at <= now() - make_interval(days => v_days::int)
       -- the rating ask owns day 21 onwards; the outcome check never lands on or after it
       and t.revealed_at >  now() - make_interval(days => v_rating)
       -- the same allowlist as fn_support_request_ratings_due: never a refunded or disputed reveal
       and coalesce(t.refund_status, 'none') in ('none', 'window_open', 'declined')
       and coalesce(i.outcome, '') = '' and coalesce(i.status, '') <> 'completed'
       and (p_include_fixtures or not public.fn_seat_clock_customer_is_fixture(c))
       and not public.fn_seat_clock_asked('reveal_outcome_check:' || t.quote_id)
     order by t.revealed_at
  loop
    v := public.fn_seat_clock_deliver('customer_support', 'reveal_outcome_check', 'customer', d.cemail, d.fixture, d.clocale,
           'reveal_outcome_check',
           jsonb_build_object('name', d.cname, 'supplier', d.company_name, 'category', d.category),
           'reveal_outcome_check:' || d.quote_id, d.inquiry_id, d.quote_id, d.supplier_id);
    if coalesce((v->>'ok')::boolean, false) then v_asked := v_asked + 1;
    else v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('transaction_id', d.tx_id, 'reason', v->>'reason'));
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'asked', v_asked, 'not_written', v_skipped, 'days_after_reveal', v_days,
                            'rating_ask_day', v_rating);
end
$fn$;
revoke execute on function public.fn_reveal_outcome_check_tick(boolean) from public, anon, authenticated;

-- ── 7. time to first reply (customer_support) ─────────────────────────────────────────────────────
-- Three channels, each its own finding (one number per class, not one aggregate): email to any support
-- mailbox (not the expenses mailbox, which the accountant reads), WhatsApp (not the founder's own numbers:
-- WhatsApp is his command channel), chat questions the widget could not answer (their gap task is the reply).
create or replace function public.fn_support_reply_watch_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
         and not public.fn_is_demo_email(m.from_email);
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
         and not (right(regexp_replace(coalesce(w.wa_from, ''), '[^0-9]', '', 'g'), 9) = any (v_founder));
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
      perform public.fn_it_engineer_finding_close('support_reply_sla:' || c,
        'every ' || c || ' message older than ' || v_sla || ' h has a first reply');
    end if;
    v_out := v_out || jsonb_build_object(c, jsonb_build_object('over_sla', v_n, 'median_first_reply_minutes_7d', round(v_median)));
  end loop;
  return jsonb_build_object('ok', true, 'sla_hours', v_sla) || v_out;
end
$fn$;
revoke execute on function public.fn_support_reply_watch_tick() from public, anon, authenticated;

-- ── 8. one heartbeat step for the four clocks ─────────────────────────────────────────────────────
-- Each clock in its own subtransaction: one failing does not silence the other three, and the failure
-- is on the step's result (ok:false + the clock's name) where the heartbeat and the IT engineer read it.
create or replace function public.fn_seat_clocks_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_out jsonb := '{}'::jsonb; v jsonb; k text; v_ok boolean := true;
begin
  foreach k in array array['complaints', 'short_quotes', 'reveal_outcome', 'reply_watch'] loop
    begin
      v := case k when 'complaints' then public.fn_complaint_clock_tick(false)
                  when 'short_quotes' then public.fn_rfq_short_of_quotes_tick(false)
                  when 'reveal_outcome' then public.fn_reveal_outcome_check_tick(false)
                  else public.fn_support_reply_watch_tick() end;
    exception when others then
      v := jsonb_build_object('ok', false, 'error', left(sqlerrm, 300));
    end;
    v_ok := v_ok and coalesce((v->>'ok')::boolean, false);
    v_out := v_out || jsonb_build_object(k, v);
  end loop;
  return jsonb_build_object('ok', v_ok) || v_out;
end
$fn$;
revoke execute on function public.fn_seat_clocks_tick() from public, anon, authenticated;

insert into public.resilience_step (step, every, budget_ms, place, rank, note) values
  ('seatClocks', interval '30 min', 1500, 'plan', 0,
   'ceo: the four seat clocks (fn_seat_clocks_tick) -- complaint deadlines (customer_support), requests short of 3 quotes (sales_engineer), the 7-day reveal outcome check (customer_support), time to first support reply (customer_support). Writes mail, so it runs before the outbox drain (place=last)')
on conflict (step) do update
   set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place, rank = excluded.rank, note = excluded.note;
