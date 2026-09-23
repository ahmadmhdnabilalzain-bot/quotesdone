-- A VERIFIED SUPPLIER IS TOLD WHAT HIS PORTFOLIO IS MISSING (23 Sep 2026).
-- Assigned: sales_engineer detects and re-verifies; customer_support delivers.
--
-- Founder instruction 858, 23 Sep 2026: "the sales agent already knows their portfolio and he knows what
-- is missing … he will notify the customer support engineer … the customer support will send them on
-- WhatsApp and on email a notification saying there is something missing in your portfolio. So please
-- fill it up. With a small guide of what to do. We always need to be extremely clear with suppliers …
-- This is mandatory after three working days from a supplier being verified. If there is something
-- missing, of course, if someone did it straight away, then we don't need to remind him."
--
-- WHY NOW. Instruction 857 (minutes earlier): a supplier who did not tick a service has not confirmed he
-- does it, so he does not receive inquiries naming it. Most suppliers never open the Services tab, so
-- without this reminder a verified supplier silently stops receiving most inquiries.
--
-- MEASURED 23 Sep 2026 on production (htdblwldjkcgjvmqkbeh), read-only:
--   * Verification is leads.verified = true AND approval_status = 'approved', stamped at approved_at
--     (fn_sales_engineer_verifies_supplier, the_mandatory_six_have_one_definition_and_the_sales_engineer_
--     verifies.sql). 3 suppliers are verified today; all 3 are ZZ DEMO fixtures, 0 are real.
--   * The working-day helper exists: fn_add_working_days(timestamptz, int) walks Asia/Dubai calendar days
--     through fn_is_working_day (ISO Monday-Friday, minus public.public_holidays: 16 rows). Reused here;
--     no second calendar.
--   * The portfolio, as matching reads it (fn_match_capability): nothing reaches a supplier whose
--     supplier_capabilities row is not confirmed (GATE confirmed_at); a declared trade reaches him for a
--     service-naming inquiry only through the services he stated ('<trade>.<code>' keys of an active
--     taxonomy_trade_service row, minus services_removed); a word he typed that is not such a key
--     matches nothing (supplier_services.ts keeps it and files a taxonomy_trade_proposal).
--   * WhatsApp: a supplier email addressed to_role 'supplier' is twinned by trg_wa_fanout to his
--     CONFIRMED number (fn_whatsapp_destination) and send_whatsapp sends it on a template. The template
--     that fits — supplier_account_notice, "QuotesDone update about your supplier account: {{1}}. Please
--     open your supplier portal for the full details and any action needed: {{2}}" (UTILITY, EN + AR,
--     SIDs HX73016b…/HX9ef909… in app_secrets.wa_template_sids) — was asked of Twilio's Content API at
--     2026-09-23T07:21Z: BOTH languages 'received', i.e. still with Meta, not approved (Twilio ticket
--     29665983). send_whatsapp holds a supplier row on an unapproved template queued, never dropped, and
--     sends it the moment the template is approved.
--
-- WHAT "MISSING" MEANS (fn_supplier_portfolio_gaps), each named in words a supplier understands:
--   1. services_not_confirmed  — no confirmed services list at all: no request of any kind reaches him.
--   2. trade_without_service   — per declared trade that HAS services in our list: none of them ticked.
--   3. own_words               — words stored as services that are not a service on our list.
--   A declared trade our list has no services for is not a gap: there is nothing for him to tick, and an
--   inquiry cannot name a service there either.
--
-- WHAT THIS BUILDS
--   1. decision_policy supplier_portfolio_reminder_working_days = 3 (the founder's number).
--   2. fn_supplier_portfolio_gaps(lead) and fn_supplier_portfolio_reminder_compose(lead, gaps): the list
--      above and the message, English and formal Gulf Arabic, with the guide and the options.
--   3. The conversation supplier.portfolio_incomplete, sales_engineer -> customer_support, originator-
--      closed. customer_support's handler RE-READS THE PORTFOLIO when it sends, never the list the sales
--      engineer saw: a supplier who completed it in between gets nothing. What it sends goes through its
--      own delivery door (fn_customer_support_takes_delivery -> the outbox), and it records the WhatsApp
--      leg as queued, pending_template (stamped on the twin row), or why there is none.
--   4. fn_supplier_portfolio_reminder_tick: re-verifies what support answered and closes it (sales_engineer
--      only, qd.handoff_closer), then opens one handoff per supplier per verification whose 3 working days
--      are up and whose portfolio has a gap. Keyed on (lead, approved_at): a re-run is a no-op.
--   5. fn_seat_clocks_tick gains it (the seatClocks heartbeat step, every 30 minutes). This file becomes
--      that routine's canonical definition; the body is the_whatsapp_menu_answers_like_a_senior_member_
--      of_staff.sql's, unchanged apart from the one added duty.
--
-- WHAT THIS DOES NOT DO. No second reminder: the founder asked for one at three working days. No change
-- to matching, to the Services tab, or to the template text. send_whatsapp's tmplKey maps the new type to
-- supplier_account_notice in the same pull request (deploy it before relying on the WhatsApp leg).
--
--   node scripts/apply_sql.mjs scripts/sql/a_verified_supplier_is_told_what_his_portfolio_is_missing.sql --apply --ddl --seat sales_engineer
--   then run scripts/sql/a_verified_supplier_is_told_what_his_portfolio_is_missing_probe.sql (its own verdict row)

-- ── 1. the founder's number ──────────────────────────────────────────────────────────────────────
insert into public.decision_policy (key, value, description) values
  ('supplier_portfolio_reminder_working_days', '3'::jsonb,
   'fn_supplier_portfolio_reminder_tick: working days (Monday-Friday, Dubai, public holidays excluded) after a supplier is verified at which sales_engineer checks his portfolio and, if something is missing, hands customer_support one reminder to send (founder instruction 858).')
on conflict (key) do update set description = excluded.description;

-- ── 2. what is missing ───────────────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_portfolio_gaps(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with sc as (select * from public.supplier_capabilities where supplier_id = p_lead_id and confirmed_at is not null),
  keys as (select s.trade_code, s.trade_code || '.' || s.code as k from public.taxonomy_trade_service s where s.active),
  silent as (
    select t.code, t.label, coalesce(t.label_ar, t.label) as label_ar
      from sc, unnest(coalesce(sc.trades, '{}'::text[])) tr
      join public.taxonomy_trade t on t.code = tr
     where exists (select 1 from keys where keys.trade_code = tr)
       and not exists (select 1 from unnest(coalesce(sc.services, '{}'::text[])) s
                         join keys on keys.k = s
                        where keys.trade_code = tr and s <> all (coalesce(sc.services_removed, '{}'::text[])))
  ),
  own as (
    select distinct btrim(w) as w
      from sc, unnest(coalesce(sc.services, '{}'::text[])) w
     where nullif(btrim(w), '') is not null and w not in (select k from keys)
  )
  select case
    when not exists (select 1 from sc) then jsonb_build_array(jsonb_build_object(
      'code', 'services_not_confirmed',
      'en', 'You have not confirmed the services your company provides yet, so no request can reach you.',
      'ar', 'لم تؤكّدوا بعد الخدمات التي تقدّمها شركتكم، ولذلك لا يصلكم أي طلب.'))
    else
      coalesce((select jsonb_agg(jsonb_build_object(
          'code', 'trade_without_service', 'trade', s.code,
          'en', s.label || ': no service is ticked yet, so requests that name a service in this trade do not reach you.',
          'ar', s.label_ar || ': لم تحدّدوا أي خدمة فيه بعد، ولذلك لا تصلكم الطلبات التي تذكر خدمة في هذا التخصص.')
          order by s.code) from silent s), '[]'::jsonb)
      || coalesce((select jsonb_build_array(jsonb_build_object(
          'code', 'own_words', 'words', jsonb_agg(o.w order by o.w),
          'en', 'Written in your own words and not yet matched to a service on our list: '
                || string_agg('«' || o.w || '»', ', ' order by o.w)
                || '. Our sales engineer is reviewing them; until then they match no request. If one of them is on the list under another name, tick it there.',
          'ar', 'خدمات كتبتموها بأسلوبكم ولم تُطابَق بعد مع أي خدمة في قائمتنا: '
                || string_agg('«' || o.w || '»', '، ' order by o.w)
                || '. ويراجعها مهندس المبيعات حاليًا، ولا تُطابَق مع أي طلب إلى حين اعتمادها. وإن وجدتم أيًّا منها في القائمة باسم آخر، فحدّدوه هناك.'))
          from own o having count(*) > 0), '[]'::jsonb)
  end
$fn$;
revoke execute on function public.fn_supplier_portfolio_gaps(bigint) from public, anon, authenticated;

-- ── 3. the words ─────────────────────────────────────────────────────────────────────────────────
-- The subject is also {{1}} of the WhatsApp template (send_whatsapp varsFor: at most 90 characters), so
-- it says the whole point on its own. The guide names the buttons exactly as servicesCopy.ts and
-- workspaceCopy.ts print them. Services is the portal's landing tab, so /<lang>/portal opens on it.
create or replace function public.fn_supplier_portfolio_reminder_compose(p public.leads, p_gaps jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_ar boolean := lower(coalesce(p.locale, '')) like 'ar%';
  v_lang text := case when lower(coalesce(p.locale, '')) like 'ar%' then 'ar' else 'en' end;
  v_name text := nullif(btrim(coalesce(p.company_name, '')), '');
  v_site text; v_link text; v_items text; v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_link := coalesce(v_site, 'https://quotesdone.com') || '/' || v_lang || '/portal';
  select string_agg('• ' || (g->>v_lang), E'\n' order by o) into v_items
    from jsonb_array_elements(coalesce(p_gaps, '[]'::jsonb)) with ordinality x(g, o);

  if v_ar then
    v_subj := 'خدماتكم لم تُستكمل بعد، وقد تفوتكم طلبات عروض الأسعار';
    v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'السادة الكرام،') || E'\n\nتحية طيبة وبعد،\n\n'
      || 'نشكركم على إتمام توثيق شركتكم لدى QuotesDone. وقد راجع مهندس المبيعات ملف أعمالكم، وتبيّن أن بعض بياناته لم تُستكمل بعد. '
      || 'ولمّا كانت الطلبات لا تصلكم إلا في الخدمات التي أكّدتموها، نرجو استكمال ما يلي:'
      || E'\n\n' || coalesce(v_items, '')
      || E'\n\nطريقة الاستكمال (تستغرق دقيقتين تقريبًا):'
      || E'\n1. سجّلوا الدخول إلى بوابة الموردين: ' || v_link
      || E'\n2. يظهر تبويب «الخدمات» أولًا. حدّدوا تحت كل تخصص جميع الخدمات التي تقدّمها شركتكم.'
      || E'\n3. إن ظهر تخصص لا تعمل فيه شركتكم، فاضغطوا «إزالة هذا التخصص».'
      || E'\n4. إن لم تجدوا في القائمة خدمة تقدّمونها، فاكتبوها في خانة «أضيفوا الخدمات التي تقدّمونها» ثم اضغطوا «إعادة صياغة خدماتي».'
      || E'\n5. اضغطوا «تأكيد خدماتي» لحفظ التغييرات، أو «تحديث خدماتي» إن سبق لكم الحفظ.'
      || E'\n\nالخيارات المتاحة لكم:'
      || E'\n• تحديد الخدمات التي تقدّمونها، فتصلكم الطلبات التي تذكرها.'
      || E'\n• إزالة التخصص الذي لا تعملون فيه، فلا تصلكم طلباته بعد ذلك.'
      || E'\n• إن احتجتم إلى المساعدة، يكفي الرد على هذه الرسالة أو مراسلتنا عبر واتساب، وسيستكمل فريقنا البيانات معكم.'
      || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،\nفريق خدمة العملاء — QuotesDone';
  else
    v_subj := 'Your services are not complete yet, so you may miss requests';
    v_body := coalesce('Dear ' || v_name || ',', 'Dear Sir or Madam,') || E'\n\n'
      || 'Thank you for completing your verification with QuotesDone. Our sales engineer has reviewed your company''s portfolio, and some of it is still missing. '
      || 'Requests reach you only for the services you have confirmed, so please complete the following:'
      || E'\n\n' || coalesce(v_items, '')
      || E'\n\nHow to complete it (about two minutes):'
      || E'\n1. Sign in to your supplier portal: ' || v_link
      || E'\n2. The Services tab opens first. Under each trade, tick every service your company provides.'
      || E'\n3. If a trade is listed that your company does not work in, press "Remove this trade".'
      || E'\n4. If a service you provide is not on the list, write it under "Add the services you provide" and press "Rewrite my services".'
      || E'\n5. Press "Confirm my services" to save, or "Update my services" if you have saved before.'
      || E'\n\nYour options:'
      || E'\n• Tick the services you provide: you will receive the requests that name them.'
      || E'\n• Remove a trade you do not work in: you will no longer receive requests for it.'
      || E'\n• Need help? Reply to this e-mail or message us on WhatsApp, and our team will complete it with you.'
      || E'\n\nKind regards,\nQuotesDone Customer Support';
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$fn$;
revoke execute on function public.fn_supplier_portfolio_reminder_compose(public.leads, jsonb) from public, anon, authenticated;

-- ── 4. customer_support's answer: re-check, then send through its own door ───────────────────────
create or replace function public.fn_customer_support_reminds_supplier_of_portfolio(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  a public.agent_actions; l public.leads; v_gaps jsonb; v_to text; v_fix boolean; v_why text; m jsonb; v jsonb;
  d public.agent_actions; n public.notifications; v_wa_id bigint; v_tmpl text; v_wa jsonb; v_nid bigint;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff' and detail->>'type' = 'supplier.portfolio_incomplete';
  if not found then raise exception 'fn_customer_support_reminds_supplier_of_portfolio: % is not a supplier.portfolio_incomplete handoff', p_id; end if;
  select * into l from public.leads where id = (a.detail->>'lead_id')::bigint;
  if not found then return jsonb_build_object('not_sent', 'the supplier no longer exists'); end if;
  if not (coalesce(l.verified, false) and l.approval_status = 'approved') or coalesce(l.banned, false) then
    return jsonb_build_object('not_sent', 'the supplier is no longer verified');
  end if;

  -- SEND TIME, NOT DETECTION TIME: the portfolio is read again here. Whatever the sales engineer saw.
  v_gaps := public.fn_supplier_portfolio_gaps(l.id);
  if jsonb_array_length(v_gaps) = 0 then
    return jsonb_build_object('not_sent', 'the portfolio was complete when customer_support came to send',
                              'gaps_at_detection', a.detail->'gaps_at_detection');
  end if;

  v_to := lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email, '')));
  v_fix := public.fn_seat_clock_lead_is_fixture(l);
  v_why := public.fn_seat_clock_refusal(v_fix, v_to, 'supplier_portfolio_incomplete');
  if v_why is not null then return jsonb_build_object('not_sent', v_why, 'gaps', v_gaps); end if;

  m := public.fn_supplier_portfolio_reminder_compose(l, v_gaps);
  v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
    'type', 'supplier_portfolio_incomplete', 'requested_by', 'customer_support', 'channel', 'email',
    'to_email', v_to, 'to_role', 'supplier', 'lead_id', l.id, 'lang', m->>'lang',
    'subject', m->>'subject', 'body', m->>'body',
    'dedupe_key', 'supplier_portfolio_reminder:' || (a.detail->>'subject_id'))));
  if coalesce(v->0->>'status', '') = 'failed' then
    return jsonb_build_object('not_sent', 'the delivery request failed: ' || coalesce(v->0->>'error', 'no error recorded'), 'gaps', v_gaps);
  end if;

  select * into d from public.agent_actions where id = (v->0->>'handoff_id')::bigint;
  v_nid := (d.evidence->>'notification_id')::bigint;
  v_wa_id := (d.evidence->'whatsapp_ids'->>0)::bigint;

  -- THE WHATSAPP LEG, AS IT IS AND NOT AS HOPED. A status column is not a delivery record: this names
  -- the twin row and what holds it, and send_whatsapp is what finally sends it.
  if v_wa_id is null then
    v_wa := jsonb_build_object('state', 'no_whatsapp', 'reason',
      case when l.whatsapp_opt = 'none' then 'the supplier chose not to receive WhatsApp messages'
           else 'the supplier has not confirmed a WhatsApp number' end);
  else
    select * into n from public.notifications where id = v_wa_id;
    select t.status into v_tmpl from public.messaging_template t
     where t.sid = (select s.value::jsonb #>> array['supplier_account_notice', coalesce(n.lang, m->>'lang')]
                      from public.app_secrets s where s.key = 'wa_template_sids')
     order by t.last_checked_at desc nulls last limit 1;
    if n.status in ('queued', 'pending') and coalesce(v_tmpl, 'unregistered') <> 'approved' then
      update public.notifications
         set last_error = 'awaiting template: supplier_account_notice is ' || coalesce(v_tmpl, 'unregistered')
                          || ' at Meta (Twilio ticket 29665983). This row stays queued and goes the moment it is approved; the email carried this reminder.'
       where id = v_wa_id;
      v_wa := jsonb_build_object('state', 'pending_template', 'notification_id', v_wa_id,
                                 'template', 'supplier_account_notice', 'template_status', coalesce(v_tmpl, 'unregistered'));
    elsif n.status in ('queued', 'pending') then
      v_wa := jsonb_build_object('state', 'queued', 'notification_id', v_wa_id, 'template', 'supplier_account_notice');
    else
      v_wa := jsonb_build_object('state', n.status, 'notification_id', v_wa_id, 'reason', n.last_error);
    end if;
  end if;

  return jsonb_build_object('sent', true, 'lang', m->>'lang', 'gaps', v_gaps,
                            'delivery_handoff_id', d.id, 'notification_id', v_nid, 'whatsapp', v_wa);
end
$fn$;
revoke execute on function public.fn_customer_support_reminds_supplier_of_portfolio(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
values ('supplier.portfolio_incomplete', 'sales_engineer', 'customer_support',
        'Three working days after verification a supplier''s portfolio still has a gap (fn_supplier_portfolio_gaps). customer_support re-reads it and, if still incomplete, sends one reminder with a guide by email and WhatsApp. sales_engineer re-verifies what was sent and closes (founder instruction 858).',
        'fn_customer_support_reminds_supplier_of_portfolio', null, true,
        'scripts/sql/a_verified_supplier_is_told_what_his_portfolio_is_missing.sql')
on conflict (type, from_seat, to_seat) do update
   set meaning = excluded.meaning, handler = excluded.handler, reply_within = excluded.reply_within,
       originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

-- ── 5. sales_engineer's duty ─────────────────────────────────────────────────────────────────────
-- p_now and p_lead_id exist for the rehearsal (a Thursday verification, one fixture); the clock passes neither.
-- ponytail: suppliers are scanned only while their due date is under 14 days old, so a supplier who was
-- complete on day 3 is not re-read every 30 minutes forever. A tick outage longer than 14 days would miss
-- reminders; widen the window if that ever happens.
create or replace function public.fn_supplier_portfolio_reminder_tick(
  p_include_fixtures boolean default false, p_now timestamptz default now(), p_lead_id bigint default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_days int := public.fn_seat_clock_policy('supplier_portfolio_reminder_working_days', 3)::int;
  h public.agent_actions; l public.leads; v_gaps jsonb; v_due timestamptz; v_ev jsonb; v_email text; v_wa text;
  v_opened int := 0; v_complete int := 0; v_closed int := 0; v_unverified int := 0;
begin
  -- 1. RE-VERIFY WHAT SUPPORT ANSWERED, THEN CLOSE IT. Only the originator closes.
  for h in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.agent = 'customer_support' and a.detail->>'type' = 'supplier.portfolio_incomplete'
              and a.status not in ('done', 'failed') and a.detail ? 'replied_at'
              and (p_lead_id is null or a.detail->>'lead_id' = p_lead_id::text)
            order by a.id loop
    v_ev := coalesce(h.evidence, '{}'::jsonb);
    if v_ev ? 'not_sent' then
      v_ev := v_ev || jsonb_build_object('reverified', 'nothing was sent, and the reason is recorded');
    else
      select n.status into v_email from public.notifications n where n.id = (v_ev->>'notification_id')::bigint;
      select n.status into v_wa from public.notifications n where n.id = (v_ev#>>'{whatsapp,notification_id}')::bigint;
      if v_email is null then v_unverified := v_unverified + 1; continue; end if;   -- stays open: nothing to prove it
      v_ev := v_ev || jsonb_build_object('reverified', 'the email is on the outbox', 'email_status', v_email,
                                         'whatsapp_status', coalesce(v_wa, v_ev#>>'{whatsapp,state}'));
    end if;
    perform set_config('qd.handoff_closer', 'sales_engineer', true);
    perform public.fn_seat_handoff_complete(h.id, v_ev || jsonb_build_object('reverified_by', 'sales_engineer', 'reverified_at', p_now));
    perform set_config('qd.handoff_closer', '', true);
    v_closed := v_closed + 1;
  end loop;

  -- 2. DETECT. One handoff per supplier per verification, never before the third working day.
  for l in select * from public.leads x
            where x.verified and x.approval_status = 'approved' and x.approved_at is not null and not coalesce(x.banned, false)
              and public.fn_add_working_days(x.approved_at, v_days) <= p_now
              and public.fn_add_working_days(x.approved_at, v_days) > p_now - interval '14 days'
              and (p_lead_id is null or x.id = p_lead_id)
              and (p_include_fixtures or not public.fn_seat_clock_lead_is_fixture(x))
              and not exists (select 1 from public.agent_actions a
                               where a.kind = 'handoff' and a.agent = 'customer_support' and a.status <> 'failed'
                                 and a.target_id = 'supplier.portfolio_incomplete:' || x.id || ':' || extract(epoch from x.approved_at)::bigint)
            order by x.id loop
    v_gaps := public.fn_supplier_portfolio_gaps(l.id);
    if jsonb_array_length(v_gaps) = 0 then v_complete := v_complete + 1; continue; end if;   -- did it straight away
    v_due := public.fn_add_working_days(l.approved_at, v_days);
    perform public.fn_seat_handoff('sales_engineer', 'customer_support', 'supplier.portfolio_incomplete', 'leads',
      l.id || ':' || extract(epoch from l.approved_at)::bigint,
      jsonb_build_object('lead_id', l.id, 'verified_at', l.approved_at, 'due_at', v_due, 'gaps_at_detection', v_gaps,
                         'fixture', public.fn_seat_clock_lead_is_fixture(l)));
    v_opened := v_opened + 1;
  end loop;

  return jsonb_build_object('ok', true, 'opened', v_opened, 'complete_at_due', v_complete,
                            'closed', v_closed, 'awaiting_proof', v_unverified);
end
$fn$;
revoke execute on function public.fn_supplier_portfolio_reminder_tick(boolean, timestamptz, bigint) from public, anon, authenticated;

-- ── 6. on the heartbeat ──────────────────────────────────────────────────────────────────────────
create or replace function public.fn_seat_clocks_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_out jsonb := '{}'::jsonb; v jsonb; k text; v_ok boolean := true;
begin
  foreach k in array array['complaints', 'short_quotes', 'reveal_outcome', 'reply_watch', 'human_requests', 'portfolio_reminder'] loop
    begin
      v := case k when 'complaints' then public.fn_complaint_clock_tick(false)
                  when 'short_quotes' then public.fn_rfq_short_of_quotes_tick(false)
                  when 'reveal_outcome' then public.fn_reveal_outcome_check_tick(false)
                  when 'reply_watch' then public.fn_support_reply_watch_tick()
                  when 'portfolio_reminder' then public.fn_supplier_portfolio_reminder_tick(false)
                  else public.fn_wa_human_request_tick() end;
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

update public.resilience_step
   set note = 'ceo: the seat clocks (fn_seat_clocks_tick) -- complaint deadlines (customer_support), requests short of 3 quotes (sales_engineer), the 7-day reveal outcome check (customer_support), time to first support reply (customer_support), WhatsApp requests for a person (customer_support), the 3-working-day portfolio reminder (sales_engineer detects, customer_support sends). Writes mail, so it runs before the outbox drain (place=last)'
 where step = 'seatClocks';
