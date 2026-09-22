-- THE WHATSAPP MENU ANSWERS LIKE A SENIOR MEMBER OF STAFF: the right name, the right portal, a case that
-- is followed to its close, a person who really takes over, and a question that is understood.
--
-- Assigned: customer_support (owns WhatsApp, support cases and every send). 22 Sep 2026.
-- Founder_instruction 763, after testing the live menu of #841 (wa_messages 252-257), five defects.
--
-- MEASURED 22 Sep 2026 (production, read-only):
--   1. Welcome: "Good day management@quotesdone.com". fn_identify_contact returns the founder's admin
--      EMAIL as his name (app_secrets.admin_emails); fn_wa_menu_context passed it through.
--   2. Follow up: "There are no open requests on your account ... https://quotesdone.com/portal". /portal
--      renders SupplierPortal for every visitor ("Supplier portal — QuotesDone"); the customer portal is
--      /me ("My requests"). The founder's number is not a customer, so the list was empty and honest,
--      but the words did not say it plainly and the link was the wrong portal (fixed in menu.ts).
--   3. Report a problem: fn_wa_problem_report wrote a support_case and nothing else: no handoff, no
--      reply clock, no check for a case already open from the same person, and closing a case told
--      nobody.
--   4. Talk to a person: notification 45683 (WhatsApp) provider_status 'read'; 45682 (email) status
--      'sent' at 13:30:57Z, from info@quotesdone.com to management@quotesdone.com, the same sender and
--      recipient as every other founder mail (founder_brief, it_new_bug, board_report in the same three
--      days). quotesdone.com MX is Microsoft 365, DMARC p=quarantine; Resend signs with
--      resend._domainkey.quotesdone.com (DKIM present) and bounces through send.quotesdone.com (SPF
--      include:amazonses.com), so the mail aligns. Inbox vs Junk placement cannot be read from here —
--      only the mailbox shows it. The subject carried his own address ("[Attention] WhatsApp:
--      management@quotesdone.com asked ..."); it now names the contact. Nothing marked the
--      conversation as handed over: the seat kept answering, no handoff existed, nobody followed up.
--   5. General questions: wa_inbound called fn_faq_answer(p_text) with NO embedding. fn_faq_answer's
--      semantic branch accepted the nearest neighbour on cosine alone (>= 0.86). Measured with the live
--      gte-small: "can i trust the suppliers on your site" -> "Can I invite my own supplier?" at 0.8885,
--      a wrong answer the site assistant would have given; "is it free for suppliers" was answered by
--      KEYWORD with "When do I pay?" (0.3367) instead of "Is there a subscription fee for suppliers?".
--      20 of 150 English and all 23 Arabic approved FAQ rows had no embedding, the fee rows among them.
--
-- WHAT THIS CHANGES
--   A. fn_wa_menu_context: the greeting name is the person (customer full_name; supplier contact_name,
--      else company_name; the founder's app_secrets.founder_name) and NEVER an address. Requests carry
--      their id so the reply links straight to each one.
--   B. fn_wa_problem_report: links the case to the confirmed party and the request number it mentions;
--      a report from the same number or account while a case is open (last N days,
--      decision_policy support_case_append_days, default 7) is ADDED to that case and the reporter is
--      told its reference; a new case opens a handoff support.case_open to customer_support with the
--      first-reply clock (decision_policy support_first_reply_sla_hours = 24, measured) and returns it.
--   C. Closing a case (any path) completes the handoff and emails the account address; the founder's
--      WhatsApp command "close QD-S-XXXXXX <reason>" (fn_support_case_close) also tells the reporter on
--      WhatsApp. Cases live in public.support_case; their loop in public.agent_actions (kind handoff).
--   D. fn_wa_human_request: the conversation is marked handed_to_human (wa_conversation.thread_state),
--      a support.human_requested handoff is opened with a 24-hour clock, and the founder is alerted
--      with an actionable message. fn_wa_human_hold keeps the seat quiet meanwhile. The founder closes it
--      with "DONE +971..." (fn_wa_human_request_close). fn_wa_human_request_tick, run by
--      fn_seat_clocks_tick: 23 hours on with no close, the seat politely follows up inside the
--      WhatsApp session window, hands the chat back to the automatic replies and alerts the founder
--      again. An open request past its clock is reported by fn_it_handoff_sla_items (the IT duties).
--   E. fn_faq_answer: with an embedding, a semantic answer must be CORROBORATED by the asker's own
--      words (fn_faq_concepts folds a few: "charge", "cost", "free" all read as fee), and it is preferred
--      to a keyword match unless the keyword match's own question carries more of the asker's concepts.
--      Without an embedding, unchanged.
--
-- WHAT THIS DOES NOT CHANGE
--   - The founder brief (fn_founder_brief, "seven things", his approved format): open requests reach
--     the IT/CEO view through the handoff clock, not a new section.
--   - No new IT alarm: nothing here calls fn_it_engineer_finding_upsert (every_alarm_is_quiet_on_a_healthy_day).
--   - The embeddings: scripts/kb/embed_sales_knowledge.mjs --table=company_faq fills the 43 missing
--     vectors (free, in-region); until it runs, an unembedded row can still answer by keyword.
--   - ai_gateway keeps passing 0.86; it now also needs corroboration, which only removes answers.
--
--   node scripts/apply_sql.mjs scripts/sql/the_whatsapp_menu_answers_like_a_senior_member_of_staff.sql --apply --ddl
--   then: scripts/sql/the_whatsapp_menu_answers_like_a_senior_member_of_staff_probe.sql (verdict row)

-- ── 0. THE TWO CONVERSATIONS THE SEAT HOLDS WITH ITSELF ─────────────────────────────────────────
-- Both wait for a PERSON to answer: the handler reports what it waits for and the handoff stays open
-- until the case is closed / the founder closes the request.
create or replace function public.fn_customer_support_waits_for_a_person(p_id bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('waiting', coalesce(a.detail ->> 'waiting_for', 'a person to answer'))
    from public.agent_actions a where a.id = p_id
$fn$;
revoke execute on function public.fn_customer_support_waits_for_a_person(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
values
  ('support.case_open', 'customer_support', 'customer_support',
   'Someone reported a problem on WhatsApp and was given a case reference: answer them within the first-reply clock. Open until the case is closed; closing it tells the reporter.',
   'fn_customer_support_waits_for_a_person', interval '24 hours', false,
   'scripts/sql/the_whatsapp_menu_answers_like_a_senior_member_of_staff.sql'),
  ('support.human_requested', 'customer_support', 'customer_support',
   'Someone chose "Talk to a person" on WhatsApp: automatic replies to them are paused until the founder or the CEO answers and closes it (DONE +number), or 23 hours pass and the seat follows up.',
   'fn_customer_support_waits_for_a_person', interval '24 hours', false,
   'scripts/sql/the_whatsapp_menu_answers_like_a_senior_member_of_staff.sql')
on conflict (type, from_seat, to_seat) do update
  set meaning = excluded.meaning, handler = excluded.handler, reply_within = excluded.reply_within,
      originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

-- ── A. WHO IS WRITING, BY NAME, AND THEIR OWN OPEN REQUESTS ─────────────────────────────────────
create or replace function public.fn_wa_menu_context(p_phone text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id json; v_aud text; v_cust uuid; v_lead bigint; v_name text; v_company text; v_reqs jsonb := '[]'::jsonb;
begin
  v_id  := public.fn_identify_contact(p_phone);
  v_aud := coalesce(v_id ->> 'audience', 'unknown');
  if v_aud = 'founder' then
    select nullif(btrim(value), '') into v_name from public.app_secrets where key = 'founder_name';
  elsif v_aud in ('customer', 'supplier') then
    -- fn_identify_contact already confirmed the number; this reads the same owner row for its ids.
    select o.customer_id, o.lead_id into v_cust, v_lead from public.fn_whatsapp_owner(p_phone) o limit 1;
    if v_aud = 'supplier' then
      select nullif(btrim(contact_name), ''), nullif(btrim(company_name), '') into v_name, v_company
        from public.leads where id = v_lead;
    else
      select nullif(btrim(full_name), '') into v_name from public.customers where id = v_cust;
    end if;
  end if;
  -- A greeting never carries an address (22 Sep: "Good day management@quotesdone.com").
  if v_name ~ '@' then v_name := null; end if;
  if v_company ~ '@' then v_company := null; end if;
  if v_aud = 'customer' and v_cust is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'rfq_no', i.rfq_no, 'status', i.status, 'created_at', i.created_at)
                              order by i.created_at desc), '[]'::jsonb)
      into v_reqs
      from (select id, rfq_no, status, created_at from public.inquiries
             where customer_id = v_cust and completed_at is null
               and coalesce(status, '') not in ('closed', 'cancelled', 'completed', 'lost')
             order by created_at desc limit 5) i;
  end if;
  return jsonb_build_object('audience', v_aud, 'name', coalesce(v_name, v_company), 'company', v_company,
                            'approved', coalesce((v_id ->> 'approved')::boolean, false), 'requests', v_reqs);
end $fn$;
revoke execute on function public.fn_wa_menu_context(text) from public, anon, authenticated;

-- ── B. "REPORT A PROBLEM": ONE CASE PER PERSON, LINKED, ON A CLOCK ─────────────────────────────
create or replace function public.fn_wa_problem_report(p_phone text, p_text text, p_lang text default 'en')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';   -- 32 symbols, no 0/O/1/I (as fn_complaint_open)
  v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_days int := greatest(1, public.fn_seat_clock_policy('support_case_append_days', 7)::int);
  v_sla numeric := public.fn_seat_clock_policy('support_first_reply_sla_hours', 24);
  v_lang text := case when p_lang = 'ar' then 'ar' else 'en' end;
  v_kind text; v_cust uuid; v_lead bigint; v_party text; v_ref text; v_id bigint; v_inq text; v_bytes bytea;
  v_case public.support_case; v_report jsonb; i int; attempt int := 0;
begin
  if coalesce(btrim(p_text), '') = '' then raise exception 'fn_wa_problem_report: empty report'; end if;
  select o.party_kind, o.customer_id, o.lead_id into v_kind, v_cust, v_lead from public.fn_whatsapp_owner(p_phone) o limit 1;
  v_party  := coalesce(v_cust::text, v_lead::text, '+' || v_digits);
  v_report := jsonb_build_object('at', now(), 'text', left(btrim(p_text), 4000));

  -- The request the report names, when it is one of this customer's own.
  if v_cust is not null then
    select i.rfq_no::text into v_inq from public.inquiries i
     where i.customer_id = v_cust and i.rfq_no is not null and p_text ~ ('(^|[^0-9])' || i.rfq_no::text || '([^0-9]|$)')
     order by i.created_at desc limit 1;
  end if;

  -- An open case from this number or this account in the last v_days days takes the report.
  select c.* into v_case from public.support_case c
   where c.state <> 'closed' and c.opened_at > now() - make_interval(days => v_days)
     and c.party_id in (v_party, '+' || v_digits)
   order by c.opened_at desc limit 1;
  if found then
    update public.support_case set last_activity_at = now(), inquiry_ref = coalesce(inquiry_ref, v_inq)
     where case_id = v_case.case_id;
    update public.agent_actions
       set detail = jsonb_set(detail, '{reports}', coalesce(detail -> 'reports', '[]'::jsonb) || v_report)
     where kind = 'handoff' and target_id = 'support.case_open:' || v_case.case_id;
    return jsonb_build_object('case_ref', v_case.case_ref, 'case_id', v_case.case_id, 'appended', true,
                              'sla_hours', v_sla, 'party_kind', v_case.party_kind);
  end if;

  loop
    attempt := attempt + 1;
    v_bytes := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
    v_ref := 'QD-S-';
    for i in 0..5 loop v_ref := v_ref || substr(alphabet, (get_byte(v_bytes, i) % 32) + 1, 1); end loop;
    begin
      insert into public.support_case (case_ref, party_kind, party_id, inquiry_ref, subject, state, identity_verified, verified_how, owner_role_id)
      values (v_ref, coalesce(v_kind, 'unknown'), v_party, v_inq,
              'WhatsApp problem report (' || v_lang || '): ' || left(btrim(p_text), 4000),
              'open', v_kind is not null, case when v_kind is not null then 'confirmed WhatsApp number' end, 'customer_support')
      returning case_id into v_id;
      exit;
    exception when unique_violation then
      if attempt >= 5 then raise; end if;
    end;
  end loop;

  perform public.fn_seat_handoff('customer_support', 'customer_support', 'support.case_open', 'support_case', v_id::text,
    jsonb_build_object('case_ref', v_ref, 'phone_digits', v_digits, 'lang', v_lang, 'party_kind', coalesce(v_kind, 'unknown'),
                       'inquiry_ref', v_inq, 'reports', jsonb_build_array(v_report), 'sla_hours', v_sla,
                       'waiting_for', 'the first reply to case ' || v_ref || ' (reporter +' || v_digits || ')'));
  return jsonb_build_object('case_ref', v_ref, 'case_id', v_id, 'appended', false, 'sla_hours', v_sla,
                            'party_kind', coalesce(v_kind, 'unknown'), 'inquiry_ref', v_inq);
end $fn$;
revoke execute on function public.fn_wa_problem_report(text, text, text) from public, anon, authenticated;

-- ── C. CLOSING A CASE TELLS THE REPORTER ────────────────────────────────────────────────────────
-- Any path that closes a case (the founder's command, a seat, a hand edit) completes its handoff and
-- emails the address on the confirmed account. WhatsApp outside the reporter's 24-hour window needs an
-- approved template this company does not have for case closures, so the WhatsApp notice is sent by
-- the founder's close command in wa_inbound (in-session) and never queued in the template-only outbox.
create or replace function public.fn_support_case_closed_tells_the_reporter()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_h public.agent_actions; v_email text; v_lang text; v_notif bigint;
begin
  if new.state <> 'closed' or old.state = 'closed' then return null; end if;
  select * into v_h from public.agent_actions where kind = 'handoff' and target_id = 'support.case_open:' || new.case_id limit 1;
  v_lang := coalesce(v_h.detail ->> 'lang', 'en');
  if new.party_kind = 'customer' then
    select c.email into v_email from public.customers c where c.id::text = new.party_id;
  elsif new.party_kind = 'supplier' then
    select l.email into v_email from public.leads l where l.id::text = new.party_id;
  end if;
  if v_email ~ '@' then
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
drop trigger if exists trg_support_case_closed_tells_the_reporter on public.support_case;
create trigger trg_support_case_closed_tells_the_reporter after update of state on public.support_case
  for each row execute function public.fn_support_case_closed_tells_the_reporter();

create or replace function public.fn_support_case_close(p_ref text, p_reason text, p_by text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_case public.support_case; v_h public.agent_actions;
begin
  update public.support_case
     set state = 'closed', closed_at = now(), last_activity_at = now(),
         close_reason = left(coalesce(nullif(btrim(p_reason), ''), 'resolved') || ' (closed by ' || coalesce(nullif(btrim(p_by), ''), 'customer_support') || ')', 1000)
   where case_ref = upper(btrim(p_ref)) and state <> 'closed'
  returning * into v_case;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no open case ' || coalesce(p_ref, '')); end if;
  select * into v_h from public.agent_actions where kind = 'handoff' and target_id = 'support.case_open:' || v_case.case_id limit 1;
  return jsonb_build_object('ok', true, 'case_ref', v_case.case_ref, 'close_reason', coalesce(nullif(btrim(p_reason), ''), 'resolved'),
                            'phone_digits', v_h.detail ->> 'phone_digits', 'lang', coalesce(v_h.detail ->> 'lang', 'en'),
                            'handoff_status', (select status from public.agent_actions where id = v_h.id));
end $fn$;
revoke execute on function public.fn_support_case_close(text, text, text) from public, anon, authenticated;

-- ── D. "TALK TO A PERSON" HANDS THE CONVERSATION OVER ───────────────────────────────────────────
create or replace function public.fn_wa_human_request(p_phone text, p_hold boolean, p_event text, p_detail text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'); v_h bigint; v_ok boolean := true; v_err text;
begin
  if length(v_digits) < 9 then return jsonb_build_object('ok', false, 'reason', 'no usable number'); end if;
  if p_hold then
    insert into public.wa_conversation (phone_e164, party_kind, message_count, thread_state, handed_to)
    values (v_digits, 'unknown', 0, 'handed_to_human', 'customer_support')
    on conflict (phone_e164) do update set thread_state = 'handed_to_human', handed_to = 'customer_support', last_seen_at = now();
  end if;
  select id into v_h from public.agent_actions
   where kind = 'handoff' and status = 'pending' and detail ->> 'type' = 'support.human_requested' and detail ->> 'phone_digits' = v_digits
   order by id desc limit 1;
  if v_h is null then
    v_h := public.fn_seat_handoff('customer_support', 'customer_support', 'support.human_requested', 'wa_conversation',
      v_digits || ':' || to_char(now() at time zone 'UTC', 'YYYYMMDDHH24MISS'),
      jsonb_build_object('phone_digits', v_digits, 'held', p_hold, 'event', p_event,
                         'waiting_for', 'a person to answer +' || v_digits || ' on WhatsApp'));
  end if;
  begin
    perform public.fn_notify_founder(p_event => p_event, p_detail => p_detail, p_level => 'high', p_kind => 'whatsapp_human_request',
                                     p_dedupe_key => 'wa_human:' || v_digits || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD'),
                                     p_owner_agent => 'customer_support');
  exception when others then v_ok := false; v_err := left(sqlerrm, 300);
  end;
  return jsonb_build_object('ok', true, 'handoff_id', v_h, 'held', p_hold, 'notified', v_ok, 'notify_error', v_err);
end $fn$;
revoke execute on function public.fn_wa_human_request(text, boolean, text, text) from public, anon, authenticated;

create or replace function public.fn_wa_human_hold(p_phone text)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((select thread_state = 'handed_to_human' from public.wa_conversation
                    where phone_e164 = regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')), false)
$fn$;
revoke execute on function public.fn_wa_human_hold(text) from public, anon, authenticated;

create or replace function public.fn_wa_human_request_close(p_phone text, p_by text, p_note text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'); r record; n int := 0;
begin
  -- The founder may type 050..., 50... or 971...: the last nine digits name the number.
  update public.wa_conversation set thread_state = 'open', handed_to = null
   where right(phone_e164, 9) = right(v_digits, 9) and thread_state = 'handed_to_human';
  for r in select id from public.agent_actions
            where kind = 'handoff' and status = 'pending' and detail ->> 'type' = 'support.human_requested'
              and right(detail ->> 'phone_digits', 9) = right(v_digits, 9) loop
    perform public.fn_seat_handoff_complete(r.id, jsonb_build_object('closed_by', coalesce(p_by, 'founder'), 'note', p_note, 'closed_at', now()));
    n := n + 1;
  end loop;
  return jsonb_build_object('closed', n);
end $fn$;
revoke execute on function public.fn_wa_human_request_close(text, text, text) from public, anon, authenticated;

-- 23 hours after the request with nobody closing it: follow up with the contact while WhatsApp still
-- allows a free-form reply (the session window their last message opened lasts 24 hours), hand the
-- chat back to the automatic replies, and alert the founder again. The send is queued with pg_net to
-- send_whatsapp's direct path under resilience_ping's credential, because resilience_ping is the
-- process that runs this tick (fn_seat_clocks_tick); its result is recorded on the handoff.
create or replace function public.fn_wa_human_request_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v_conv public.wa_conversation; v_ref text; v_secret text; v_req bigint; v_body text; v_lang text; n int := 0; v_sent int := 0;
begin
  select value into v_ref from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_fn_resilience_ping';
  for r in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail ->> 'type' = 'support.human_requested'
              and a.created_at < now() - interval '23 hours' and not (a.detail ? 'followed_up_at')
              and coalesce(a.detail ->> 'held', 'true') = 'true'
            order by a.id limit 20 loop
    n := n + 1; v_req := null;
    update public.wa_conversation set thread_state = 'open', handed_to = null
     where phone_e164 = r.detail ->> 'phone_digits' and thread_state = 'handed_to_human'
    returning * into v_conv;
    if v_conv.id is null then select * into v_conv from public.wa_conversation where phone_e164 = r.detail ->> 'phone_digits'; end if;
    v_lang := case when coalesce(v_conv.language, '') = 'ar' then 'ar' else 'en' end;
    v_body := case when v_lang = 'ar'
      then 'نعتذر عن تأخر ردنا عليكم. لم يتمكن أحد أعضاء الفريق من التواصل معكم بعد، وقد أبلغناه مجددًا بطلبكم. وإلى حين ذلك عادت إليكم خدمة الردود الفورية في هذه المحادثة، فتفضلوا بإرسال كلمة «قائمة» لعرض الخيارات أو كتابة استفساركم.' || E'\n\nفريق خدمة العملاء في QuotesDone'
      else 'We are sorry you have not heard from us yet. A member of the team has not been able to reach you, and we have reminded them of your request. Meanwhile, instant answers are back on in this chat: reply MENU for the options or type your question.' || E'\n\nQuotesDone Customer Support' end;
    if v_conv.window_expires_at > now() and v_ref is not null and v_secret is not null then
      select net.http_post(
        url := 'https://' || v_ref || '.supabase.co/functions/v1/send_whatsapp',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object('__secret', v_secret, 'to', '+' || (r.detail ->> 'phone_digits'), 'body', v_body),
        timeout_milliseconds := 15000) into v_req;
      v_sent := v_sent + 1;
    end if;
    begin
      perform public.fn_notify_founder(p_event => 'WhatsApp: +' || (r.detail ->> 'phone_digits') || ' has waited 23 hours for a person',
        p_detail => 'Nobody closed the request from +' || (r.detail ->> 'phone_digits') || ' (' || coalesce(r.detail ->> 'event', 'Talk to a person') || ').'
        || case when v_req is not null then ' They were sent a polite follow-up and automatic replies are back on.'
                else ' Their WhatsApp window has closed, so no follow-up could be sent; call them or email them.' end
        || E'\nReply now: https://wa.me/' || (r.detail ->> 'phone_digits')
        || E'\nWhen handled, send DONE +' || (r.detail ->> 'phone_digits') || ' to the QuotesDone WhatsApp number.',
        p_level => 'high', p_kind => 'whatsapp_human_request', p_dedupe_key => 'wa_human_followup:' || r.id,
        p_owner_agent => 'customer_support');
    exception when others then null;   -- the follow-up is recorded below either way
    end;
    update public.agent_actions
       set detail = detail || jsonb_build_object('followed_up_at', now(), 'followup_request_id', v_req,
                                                 'followup_skipped', case when v_req is null then 'the 24-hour WhatsApp window had closed' end)
     where id = r.id;
  end loop;
  return jsonb_build_object('ok', true, 'due', n, 'followups_queued', v_sent);
end $fn$;
revoke execute on function public.fn_wa_human_request_tick() from public, anon, authenticated;

-- The seat clocks now include the human-request clock (canonical definition moves here from
-- complaints_quotes_reveals_and_support_replies_each_run_on_a_clock.sql; the four clocks are unchanged).
create or replace function public.fn_seat_clocks_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_out jsonb := '{}'::jsonb; v jsonb; k text; v_ok boolean := true;
begin
  foreach k in array array['complaints', 'short_quotes', 'reveal_outcome', 'reply_watch', 'human_requests'] loop
    begin
      v := case k when 'complaints' then public.fn_complaint_clock_tick(false)
                  when 'short_quotes' then public.fn_rfq_short_of_quotes_tick(false)
                  when 'reveal_outcome' then public.fn_reveal_outcome_check_tick(false)
                  when 'reply_watch' then public.fn_support_reply_watch_tick()
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

-- ── E. A NEAREST NEIGHBOUR IS NOT AN ANSWER UNTIL THE ASKER'S OWN WORDS AGREE ───────────────────
-- A text's CONCEPTS: its lexemes as the english / arabic(fn_ar_norm) configurations produce them
-- (measured 22 Sep 2026), with a few words people use for the same thing folded into one concept, so
-- "how much do you charge" and a record about "fees" share one. The arabic configuration has no
-- stopword list, so the Arabic function words are dropped here.
create or replace function public.fn_faq_concepts(p_text text, p_ar boolean)
returns text[] language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with fold(lexeme, concept) as (values
      ('fee','fee'),('charg','fee'),('cost','fee'),('price','fee'),('pay','fee'),('paid','fee'),('payment','fee'),
      ('much','fee'),('commiss','fee'),('free','fee'),('subscript','fee'),('expens','fee'),('cheap','fee'),
      ('رسوم','fee'),('رسم','fee'),('تكلف','fee'),('تكلفه','fee'),('سعر','fee'),('اسعار','fee'),('عمول','fee'),
      ('مجا','fee'),('دفع','fee'),('اشتر','fee'),
      ('supplier','supplier'),('vendor','supplier'),('contractor','supplier'),('مورد','supplier'),('موردين','supplier'))
  select coalesce(array_agg(distinct coalesce(f.concept, l)), '{}')
    from unnest(tsvector_to_array(case when p_ar then to_tsvector('arabic', public.fn_ar_norm(coalesce(p_text, '')))
                                       else to_tsvector('english', coalesce(p_text, '')) end)) l
    left join fold f on f.lexeme = l
   where not (p_ar and l = any (array['كم','هل','ما','هي','هو','كيف','مع','في','من','على','عن','الي','او','لا','متي','ماذا','لماذا','اين','انا','نحن','انتم','لكم','لي']))
$fn$;
revoke execute on function public.fn_faq_concepts(text, boolean) from public, anon, authenticated;

create or replace function public.fn_faq_answer(p_text text, p_min_rank numeric default 0.15, p_embedding vector default null::vector, p_min_similarity numeric default 0.86)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare r record; v_q tsquery; k_q text; k_a text; k_src text; k_rank numeric; v_tpl record; v_ar boolean; v_qc text[]; v_best numeric; v_kq int;
begin
  if p_text is null or length(btrim(p_text)) < 2 then
    return jsonb_build_object('answered', false, 'reason', 'input too short');
  end if;

  v_ar := p_text ~ '[\u0600-\u06FF]';

  -- 1. Fixed intents. No retrieval, no model.
  select * into v_tpl from response_template
   where active and (
     (intent='greeting' and (p_text ~* '^\s*(hi|hey|hello|salam|marhaba|good (morning|afternoon|evening))\W*$'
                             or public.fn_ar_norm(p_text) ~ '^\s*(مرحبا|اهلا|السلام عليكم|صباح الخير|مساء الخير)\s*[؟!.]*\s*$')) or
     (intent='thanks'   and (p_text ~* '^\s*(thanks|thank you|thx|shukran|much appreciated)\W*$'
                             or public.fn_ar_norm(p_text) ~ '^\s*(شكرا|شكرا لك|شكرا جزيلا|مشكور)\s*[؟!.]*\s*$'))
   ) limit 1;
  if found then
    update response_template set used_count = used_count + 1 where key = v_tpl.key;
    return jsonb_build_object('answered', true, 'source', 'template', 'key', v_tpl.key,
                              'answer', v_tpl.body, 'confidence', 1.0);
  end if;

  -- 2. Keyword match, in the asker's language (Arabic records for an Arabic question, English
  --    records otherwise), exactly as before. Held in k, not returned yet.
  if v_ar then
    v_q := websearch_to_tsquery('arabic', public.fn_ar_norm(p_text));
    if v_q is not null then
      select f.question, f.answer, 'faq_keyword_ar',
             ts_rank(to_tsvector('arabic', public.fn_ar_norm(coalesce(f.question,'')||' '||coalesce(f.answer,''))), v_q) as rank
        into k_q, k_a, k_src, k_rank
        from company_faq f
       where f.public and f.status='approved' and f.language = 'ar'
         and to_tsvector('arabic', public.fn_ar_norm(coalesce(f.question,'')||' '||coalesce(f.answer,''))) @@ v_q
       order by rank desc limit 1;
      if k_rank < p_min_rank then k_q := null; end if;
    end if;
  end if;
  if k_q is null then
    v_q := websearch_to_tsquery('english', p_text);
    if v_q is not null then
      select f.question, f.answer, 'faq_keyword',
             ts_rank(to_tsvector('english', coalesce(f.question,'')||' '||coalesce(f.answer,'')), v_q) as rank
        into k_q, k_a, k_src, k_rank
        from company_faq f
       where f.public and f.status='approved' and f.language = 'en'
         and to_tsvector('english', coalesce(f.question,'')||' '||coalesce(f.answer,'')) @@ v_q
       order by rank desc limit 1;
      if k_rank < p_min_rank then k_q := null; end if;
    end if;
  end if;

  -- 3. Semantic, CORROBORATED (22 Sep 2026, instruction 763). Of the five nearest records in the
  --    asker's language, one is accepted only if cosine >= p_min_similarity, its own QUESTION carries at
  --    least one of the asker's concepts, and the record carries at least half of them (two when the
  --    asker used three or more; ALL of them for an Arabic question). Measured with the live gte-small:
  --      - "can i trust the suppliers on your site" -> "Can I invite my own supplier?" at 0.8885 with one
  --        concept of three: refused (the previous rule answered it);
  --      - "كم رسومكم" -> "متى يتم الكشف عن هويتي؟" 0.8873 (only its answer mentions the fee) lost to
  --        "ما هي رسوم المنصة؟" 0.8816 once the question's own concepts rank first;
  --      - gte-small is an English model: "ما هو سعر الذهب اليوم" (today's gold price) met "هل يمكنني
  --        استرداد المبلغ؟" at 0.9091 with two of three concepts. Arabic therefore needs every concept.
  if p_embedding is not null then
    v_qc := public.fn_faq_concepts(p_text, v_ar);
    select c.question, c.answer, c.sim,
           cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(c.question || ' ' || c.answer, v_ar)))) hits,
           cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(c.question, v_ar)))) qhits,
           cardinality(v_qc) nq
      into r
      from (select f.question, coalesce(f.answer, '') answer, round((1 - (f.embedding_gte <=> p_embedding))::numeric, 4) sim
              from company_faq f
             where f.public and f.status = 'approved' and f.embedding_gte is not null
               and f.language = case when v_ar then 'ar' else 'en' end
             order by f.embedding_gte <=> p_embedding limit 5) c
     where c.sim >= p_min_similarity
       and cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(c.question, v_ar)))) >= 1
       and cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(c.question || ' ' || c.answer, v_ar))))
           >= case when v_ar then cardinality(v_qc) when cardinality(v_qc) >= 3 then greatest(2, ceil(cardinality(v_qc) / 2.0)::int)
                   else ceil(cardinality(v_qc) / 2.0)::int end
     order by 5 desc, 3 desc limit 1;
    -- The keyword match keeps the answer when ITS question carries more of the asker's concepts:
    -- "what documents does a supplier need for verification" is that FAQ's own question, and the
    -- semantic neighbour "Supplier onboarding policy" shares one concept with it (measured on the site
    -- assistant's real questions, 22 Sep 2026).
    if r.question is not null then
      v_kq := case when k_q is null then -1
                   else cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(k_q, v_ar)))) end;
      if v_kq <= r.qhits then
        return jsonb_build_object('answered', true, 'source', 'faq_semantic', 'question', r.question,
                                  'answer', r.answer, 'confidence', r.sim, 'corroborated', r.hits || '/' || r.nq);
      end if;
    else
      select round(max(1 - (f.embedding_gte <=> p_embedding))::numeric, 4) into v_best from company_faq f
       where f.public and f.status = 'approved' and f.embedding_gte is not null and f.language = case when v_ar then 'ar' else 'en' end;
    end if;
  end if;

  if k_q is not null then
    return jsonb_build_object('answered', true, 'source', k_src, 'question', k_q,
                              'answer', k_a, 'confidence', round(k_rank::numeric, 4));
  end if;
  return jsonb_build_object('answered', false, 'reason', 'no confident FAQ match', 'best_similarity', v_best);
end $function$;
revoke execute on function public.fn_faq_answer(text, numeric, vector, numeric) from public, anon, authenticated;
