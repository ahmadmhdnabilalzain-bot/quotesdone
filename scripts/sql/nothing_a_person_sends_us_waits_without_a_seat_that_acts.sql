-- NOTHING A PERSON SENDS US WAITS WITHOUT A SEAT THAT ACTS: THE CONTACT FORM, A NOT-SURE SPEC, AN EXPIRING QUESTION.
-- And the queues of 2 Nov are settled row by row, each by its exact key, each with its reason.
-- Seat: customer_support with sales_engineer. 2 Nov 2026, founder ledger 1436, 1447; audit sections A, B, item 8.
--
-- MEASURED 1-2 Nov 2026 (production, read-only):
--   * contact_messages: 4 rows, all ZZ DEMO, status 'new', and no reader. contact_submit mailed the founder's inbox instead.
--   * spec.not_sure: 5 pending, handler only says 'waiting'. Their 5 intakes and 5 customers no longer exist.
--   * reasoning_held_question: fn_reason_held_expire marks a person-facing question expired and files an action nobody reads.
--     586 sales_engineer rows expired so; 0 of them carried a person (fixture 8 on wa_inbound.unwritten_reply). Build it now.
--   * support.case_open 39: 21 are WhatsApp 'ZZ DEMO' from fixture numbers +9715000000xx; 14 are widget rehearsals whose
--     customer ids no longer exist; 3 are the founder's seed inboxes; 1 is 666realestate, closed by the reply seat.
--   * knowledge.request 56: read one by one. 51 are a person's answer to a spec question ("Within 2 weeks.", "Oak, 14 mm"),
--     not a question the company lacks knowledge for. 5 are real questions and stay with their seat (195, 237, 212, 213, 214).
--   * backup: doc_backups 445197 has no source to re-file from; the CEO's instruction on #170341 says to mark it abandoned.
--   * the public number was the founder's mobile, also in app_secrets.founder_public_phone and 5 agent_knowledge rows.
--     Replaced by the company's WhatsApp line, app_secrets.twilio_wa_from. admin_mfa_phone is his sign-in and is untouched.
--
-- Closing a case here must not reach anyone: a rating is asked on close (fn_support_case_closed_asks_for_the_rating) and
-- would go to a fixture number, so each close presets csat_requested_at first.
--
-- Prevented by: scripts/checks/nothing_a_person_sends_us_waits.test.mjs and
-- scripts/sql/nothing_a_person_sends_us_waits_without_a_seat_that_acts_probe.sql

-- 1. THE CONTACT FORM: a message becomes an inbound row, which email_triage answers on its 15-minute tick.
create or replace function public.trg_z55_contact_message_reaches_customer_support()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if public.fn_is_demo_email(new.email) or coalesce(new.message, '') like 'ZZ DEMO%' then
    update public.contact_messages set status = 'demo' where id = new.id;
    return null;
  end if;
  if coalesce(new.source, '') = 'complaint' then return null; end if;  -- fn_complaint_open owns it, with its two clocks
  begin
    insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, raw)
    values (new.email, 'contact-form@quotesdone.com', left('Contact form: ' || coalesce(nullif(new.name, ''), new.email), 200),
            new.message || coalesce(E'\n\nPhone given: ' || nullif(new.phone, ''), ''), true,
            jsonb_build_object('source', 'contact_form', 'contact_message_id', new.id, 'sender_authenticated', false));
    update public.contact_messages set status = 'with_customer_support' where id = new.id;
  exception when others then
    -- the message is stored either way; a row left 'new' is what the check below reads
    raise warning 'trg_z55_contact_message_reaches_customer_support: contact_messages % was not handed over: %', new.id, sqlerrm;
  end;
  return null;
end $fn$;
revoke execute on function public.trg_z55_contact_message_reaches_customer_support() from public, anon, authenticated;
drop trigger if exists z55_contact_message_reaches_customer_support on public.contact_messages;
create trigger z55_contact_message_reaches_customer_support after insert on public.contact_messages
  for each row execute function public.trg_z55_contact_message_reaches_customer_support();
update public.contact_messages set status = 'demo' where id in (14, 15, 16, 17) and status = 'new' and public.fn_is_demo_email(email);

-- 2. SPEC.NOT_SURE: the sales engineer writes to the customer, once, and the handoff closes on it.
create or replace function public.fn_sales_engineer_spec_handoff_waits(p_id bigint)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions; i public.inquiry_intake; v_to text; v_ar boolean; v_specs text; v_out jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  select * into i from public.inquiry_intake where id::text = a.detail->>'intake_id';
  if i.id is null then return jsonb_build_object('action', 'none', 'reason', 'the request no longer exists: nobody is waiting'); end if;
  v_to := coalesce((select c.email from public.customers c where c.id = i.customer_id), i.email);
  if v_to is null or public.fn_is_demo_email(v_to) then
    return jsonb_build_object('action', 'none', 'reason', 'a fixture or no address: nobody to write to');
  end if;
  v_specs := (select string_agg(replace(value, '_', ' '), ', ') from jsonb_array_elements_text(coalesce(a.detail->'not_sure', '[]'::jsonb)));
  v_ar := coalesce(i.raw_input, '') ~ '[؀-ۿ]';
  v_out := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
    'type', 'clarification_requested', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', v_to, 'to_role', 'customer',
    'lang', case when v_ar then 'ar' else 'en' end,
    'subject', case when v_ar then 'نساعدكم في تحديد مواصفات طلبكم' else 'We can help you settle the details of your request' end,
    'body', case when v_ar
      then 'لا بأس إن لم تكونوا متأكدين من: ' || coalesce(v_specs, 'بعض التفاصيل') || E'.\n\nأرسلوا لنا ردًا بصورة أو مخطط أو بما تعرفونه عنها، وسنساعدكم في تحديدها حتى يتمكن الموردون من التسعير بدقة.'
      else 'It is fine not to be sure about: ' || coalesce(v_specs, 'some of the details') || E'.\n\nReply with a photo, a drawing or whatever you know about it, and we will help you settle it so suppliers can price exactly.' end,
    'dedupe_key', 'spec_not_sure_help:' || p_id)));
  return jsonb_build_object('action', 'wrote to the customer', 'delivery', v_out->0);
end $fn$;
update public.seat_handoff_kind
   set meaning = 'A customer answered "not sure" on a spec their request needs: the sales engineer writes to them with how to settle it, and the handoff closes on that.',
       owner_file = 'scripts/sql/nothing_a_person_sends_us_waits_without_a_seat_that_acts.sql'
 where type = 'spec.not_sure';
select public.fn_seat_handoff_act(x.id) from (values (157019::bigint), (249675), (252897), (252913), (253077)) x(id);

-- 3. A QUESTION WITH A PERSON BEHIND IT DOES NOT EXPIRE: it is kept and they are told, once.
create or replace function public.fn_reason_held_expire(p_ids bigint[], p_by text, p_why text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare n_exp int; n_handoff int; n_kept int := 0; h record; c jsonb; v_ids bigint[] := p_ids;
begin
  for h in select id from public.reasoning_held_question where id = any(p_ids) and status = 'held' loop
    c := public.fn_cs_held_question_contact(h.id);
    if (nullif(c->>'email', '') is not null and not public.fn_is_demo_email(c->>'email'))
       or (nullif(c->>'phone', '') is not null and c->>'phone' !~ '^\+?97150000') then
      update public.reasoning_held_question
         set expires_at = now() + interval '14 days',
             result = coalesce(result, '{}'::jsonb) || jsonb_build_object('kept_for_a_person_at', now(), 'would_have_expired_because', p_why)
       where id = h.id;
      perform public.fn_cs_held_question_message(h.id, 'support_question_ack',
        case when c ->> 'lang' = 'ar' then 'سؤالكم لدى فريقنا' else 'Your question is with our team' end,
        case when c ->> 'lang' = 'ar' then 'وصلنا سؤالكم وهو لدى فريقنا، وسنعود إليكم بالإجابة. لا حاجة لأي إجراء إضافي منكم.'
             else 'We have your question and it is with our team. We will reply here; there is nothing more you need to do.' end);
      v_ids := array_remove(v_ids, h.id);
      n_kept := n_kept + 1;
    end if;
  end loop;
  with gone as (
    update public.reasoning_held_question h
       set status = 'expired', result = coalesce(h.result, '{}'::jsonb) || jsonb_build_object('expired_by', p_by, 'why', p_why)
     where h.id = any(v_ids) and h.status = 'held'
    returning h.id, h.seat, h.surface, h.question, h.subject, h.created_at,
              coalesce(h.request -> 'context' ->> 'audience', '') audience
  ), filed as (
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    select g.seat, 'held_question_expired', 'pending', 'low',
           left('A ' || coalesce(nullif(g.audience, ''), 'person-facing') || ' question on ' || g.surface
                || ' expired unanswered: reply through the deterministic path', 200),
           jsonb_build_object('held_id', g.id, 'surface', g.surface, 'audience', g.audience,
                              'question', left(g.question, 1000), 'subject', g.subject, 'held_since', g.created_at,
                              'why_expired', p_why,
                              'needed', 'the person who asked still gets a reply: send the deterministic answer for this '
                                        || 'surface, or answer by hand; the model will not be asked this question again'),
           'reasoning_held_question', g.id::text
      from gone g
     where g.audience <> 'internal'
    returning id
  )
  select (select count(*) from gone), (select count(*) from filed) into n_exp, n_handoff;
  return jsonb_build_object('expired', n_exp, 'handoffs', n_handoff, 'kept_for_a_person', n_kept);
end $fn$;

-- 3b. CLOSING A CASE NEVER CLOSED ITS HANDOFF. Measured in the replay of 2 Nov: the handoff's target is
-- 'support.case_open:<case_ref>' (#310870: QD-S-L5MLED), both routines looked for '<case_id>' (1656), so the handoff stayed
-- pending for ever and the reporter's language and phone were lost. Each now matches either form.
create or replace function public.fn_support_case_close(p_ref text, p_reason text, p_by text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_case public.support_case; v_h public.agent_actions;
begin
  update public.support_case
     set state = 'closed', closed_at = now(), last_activity_at = now(),
         close_reason = left(coalesce(nullif(btrim(p_reason), ''), 'resolved') || ' (closed by ' || coalesce(nullif(btrim(p_by), ''), 'customer_support') || ')', 1000)
   where case_ref = upper(btrim(p_ref)) and state <> 'closed'
  returning * into v_case;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no open case ' || coalesce(p_ref, '')); end if;
  select * into v_h from public.agent_actions where kind = 'handoff'
     and target_id in ('support.case_open:' || v_case.case_ref, 'support.case_open:' || v_case.case_id) limit 1;
  return jsonb_build_object('ok', true, 'case_ref', v_case.case_ref, 'close_reason', coalesce(nullif(btrim(p_reason), ''), 'resolved'),
                            'phone_digits', v_h.detail ->> 'phone_digits', 'lang', coalesce(v_h.detail ->> 'lang', 'en'),
                            'handoff_status', (select status from public.agent_actions where id = v_h.id));
end $fn$;

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

-- 4. THE CASES, BY EXACT REF, each with its reason (never a title match).
do $do$
declare r record;
begin
  for r in select * from (values
    ('QD-S-L5MLED','rehearsal: a fixture number, ZZ DEMO'),('QD-S-CWXZLR','rehearsal: a fixture number, ZZ DEMO'),('QD-S-9PLJZY','rehearsal: a fixture number, ZZ DEMO'),
    ('QD-S-4QA8PT','rehearsal: a fixture number, ZZ DEMO'),('QD-S-EX4YFF','rehearsal: a fixture number, ZZ DEMO'),('QD-S-GBG4KP','rehearsal: a fixture number, ZZ DEMO'),
    ('QD-S-PBHKMS','rehearsal: a fixture number, ZZ DEMO'),('QD-S-Q7L3TV','rehearsal: a fixture number, ZZ DEMO'),('QD-S-VY968U','rehearsal: a fixture number, ZZ DEMO'),
    ('QD-S-F65NM9','rehearsal: a fixture number, ZZ DEMO'),('QD-S-H76887','rehearsal: a fixture number, ZZ DEMO'),('QD-S-KBEZ8T','rehearsal: a fixture number, ZZ DEMO'),
    ('QD-S-8SWBHY','rehearsal: a fixture number, ZZ DEMO'),('QD-S-XGQWWY','rehearsal: a fixture number, ZZ DEMO'),('QD-S-LRBMCB','rehearsal: a fixture number, ZZ DEMO'),
    ('QD-S-WQLGQX','rehearsal: a fixture number, ZZ DEMO'),('QD-S-YSKVWN','rehearsal: a fixture number, ZZ DEMO'),('QD-S-H3AVWG','rehearsal: a fixture number, ZZ DEMO'),
    ('QD-S-Q8PSD7','rehearsal: a fixture number, ZZ DEMO'),('QD-S-P5QFP5','rehearsal: a fixture number, ZZ DEMO'),('QD-S-6FZX5R','rehearsal: a fixture number, ZZ DEMO'),
    ('QD-S-EPMESD','rehearsal: the customer no longer exists'),('QD-S-QYWF27','rehearsal: the customer no longer exists'),('QD-S-P7LEWS','rehearsal: the customer no longer exists'),
    ('QD-S-4MCCLR','rehearsal: the customer no longer exists'),('QD-S-Z3U7Z2','rehearsal: the customer no longer exists'),('QD-S-R83U42','rehearsal: the customer no longer exists'),
    ('QD-S-ESJ53M','rehearsal: the customer no longer exists'),('QD-S-AVQZBM','rehearsal: the customer no longer exists'),('QD-S-W6YFYK','rehearsal: the customer no longer exists'),
    ('QD-S-WT3WTD','rehearsal: the customer no longer exists'),('QD-S-AS7LS8','rehearsal: the customer no longer exists'),('QD-S-46KDHJ','rehearsal: the customer no longer exists'),
    ('QD-S-PHVAC9','rehearsal: the customer no longer exists'),('QD-S-T7A43W','rehearsal: the customer no longer exists'),
    ('QD-S-LDQPMH','the founder''s own inbox answering a seed test'),('QD-S-REXE8H','the founder''s own inbox answering a seed test'),('QD-S-CW3YNL','the founder''s own inbox answering a seed test')
  ) v(ref, why) loop
    update public.support_case set csat_requested_at = coalesce(csat_requested_at, now()) where case_ref = r.ref and state <> 'closed';
    perform public.fn_support_case_close(r.ref, r.why, 'customer_support');
  end loop;
end $do$;

-- 5. KNOWLEDGE REQUESTS READ ONE BY ONE: a person's own answer is not a gap. fn customer_support closes each when marked.
update public.sales_knowledge_gap set status = 'not_a_gap', closed_at = now()
 where status = 'open' and id in (218,228,227,229,257,230,231,234,236,232,239,242,285,220,251,255,219,243,250,252,253,260,264,289,238,241,249,211,233,244,245,246,248,254,256,311,215,235,240,247,263,274,284,286,287,288,291,312,313,317,759);

-- 6. THE BACKUP: the CEO's instruction on #170341, by exact id. The IT engineer's re-check closes #161210 and #170341.
update public.doc_backups set error = 'abandoned: no source in storage; the file exists only in Dropbox (' || dropbox_content_hash || ')'
 where id = 445197 and error = 'no_source';

-- 7. THE PUBLIC CONTACT IS THE COMPANY'S WHATSAPP LINE, NOT THE FOUNDER'S MOBILE.
update public.app_secrets set value = '+12183166814' where key = 'founder_public_phone' and value = '+971509319355';
update public.agent_knowledge
   set content = replace(replace(content, '+971 50 931 9355', '+1 218 316 6814'), '+971509319355', '+12183166814'), updated_at = now()
 where id in (10441, 10443, 10444, 10445, 10446);

select case
  when not exists (select 1 from pg_trigger where tgname = 'z55_contact_message_reaches_customer_support') then 'PROBE FAILED: the contact form trigger is missing'
  when (select provolatile from pg_proc where oid = 'public.fn_sales_engineer_spec_handoff_waits(bigint)'::regprocedure) <> 'v' then 'PROBE FAILED: the spec handler is still STABLE'
  when exists (select 1 from public.agent_actions where id in (157019, 249675, 252897, 252913, 253077) and status <> 'done') then 'PROBE FAILED: a spec.not_sure with no request stayed open'
  when exists (select 1 from public.agent_knowledge where id in (10441, 10443, 10444, 10445, 10446) and content ~ '931 ?9355|509319355') then 'PROBE FAILED: the mobile is still in knowledge'
  when exists (select 1 from public.app_secrets where key = 'founder_public_phone' and value ~ '9355') then 'PROBE FAILED: the mobile is still the public contact'
  else 'PROBE OK' end as verdict;
