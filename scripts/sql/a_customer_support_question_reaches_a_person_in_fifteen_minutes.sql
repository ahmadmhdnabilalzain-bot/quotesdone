-- A CUSTOMER_SUPPORT QUESTION REACHES A PERSON IN FIFTEEN MINUTES, THE PERSON IS TOLD SO, AND THE CEO SEAT ANSWERS IT.
-- Seat: customer_support (the router and the acknowledgement); the CEO duty is filed for the ceo seat. 19 Oct 2026.
--
-- MEASURED BEFORE THIS FILE (production, 19 Oct 2026):
--   * 703 agent_actions of kind held_question / held_question_expired, every one 'pending'; not one was ever decided.
--     fn_reason_held_escalate and fn_reason_held_expire FILE them, and no routine, cron job or edge function reads them.
--   * customer_support: 28 pending (16 anonymous site-widget turns 30 Sep-2 Oct, 12 internal seat duties, 2 of whose
--     questions were already applied) and 54 held questions not applied/closed/answered.
--   * fn_reason_held_escalate selects only 'held' and 'failed' rows, so a row the sweep marks 'expired' (a visitor
--     chat past its hour) is never escalated: 21 site-widget rows since 6 Oct reached no queue at all.
--   * none of the 54 carries a contact (no email, phone, customer, lead or conversation in its request): no person
--     could have been reached.
--   * nothing reads pending agent_actions where agent = 'ceo' either (the CEO queue in general is being diagnosed
--     separately); so this file brings its OWN CEO duty for the one kind it files.
--
-- WHAT THIS ADDS
-- A. fn_cs_held_question_route(), every 5 minutes. For every customer_support held question not applied, closed or
--    answered, and every pending held_question* action on it:
--   1. its question was applied/answered by its own surface   -> the action is 'done'.
--   2. a fixture (ZZ DEMO / example.invalid / qd_run)          -> tagged result.demo_purge (ruling 1199, the #1348 list);
--                                                                 action 'dismissed'. Nothing is deleted.
--   3. an internal seat duty (audience internal, or a customer_support.* surface) older than 7 days -> 'dismissed':
--      the duty re-files itself on its next run, so the old copy waits for nothing.
--   4. a visitor with no contact                               -> 'dismissed', reason named: no route to the person.
--   5. ANYONE ELSE (a reachable customer or supplier)         -> customer_support's for 15 minutes, then:
--      - the person is ACKNOWLEDGED once through the outbox (email, else WhatsApp) in their language: a supplier always
--        English (ruling 1008), a customer the language of the request (context.language, else the question's script);
--      - a support_question_handover item is filed for the CEO seat, once; still unanswered 4 hours later -> a second,
--        high-risk overdue item, once.
--      Never the founder: rulings 1254 and 8 Sep keep his WhatsApp for a person who explicitly asks for one, which the
--      WhatsApp "Talk to a person" menu already routes.
-- B. fn_ceo_support_handover_duty(), every 5 minutes, the CEO's duty for support_question_handover:
--   - the held question was answered meanwhile             -> the handover is 'done'.
--   - not yet picked up                                     -> a ceo.support_handover reasoning is filed (fn_seat_duty_reason),
--                                                              its id recorded on the item (picked up).
--   - that reasoning came back                              -> its answer is sent to the person through the outbox in their
--                                                              language, the held question is marked answered, the item
--                                                              'done'; 'reply_and_refer' also files a sales_engineer item.
--
-- THE FIXTURES FOR THE #1348 PURGE (ruling 1199), by exact key, re-measured 19 Oct 2026 after review: the only
-- customer_support fixture held questions that exist are
--   public.reasoning_held_question id 23995 and 24299 (both 'ZZ DEMO', site_assistant.person, expired).
-- (Three ZZ DEMO wa_inbound rows counted earlier the same day no longer exist.) Later rows carry
-- result ->> 'demo_purge' = 'founder ruling 1199: the #1348 purge list'. Nothing here deletes them.
--
-- Prevented by: scripts/sql/a_customer_support_question_reaches_a_person_in_fifteen_minutes_probe.sql (verdict probe,
-- aborted transaction): a reachable question is acknowledged and handed over, the CEO duty picks it up and, once its
-- reasoning returns, replies and closes it; an anonymous one is not handed over; a fixture is tagged, not deleted; no
-- founder-kind notification is written.

-- The person behind a held question: where to reach them and in which language. No contact -> nulls.
create or replace function public.fn_cs_held_question_contact(p_id bigint)
returns jsonb
language plpgsql stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h public.reasoning_held_question; c jsonb; v_email text; v_phone text; v_supplier boolean; v_lang text;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if h.id is null then return null; end if;
  c := coalesce(h.request -> 'context', '{}'::jsonb) || coalesce(h.subject, '{}'::jsonb);
  v_supplier := coalesce(c ->> 'audience', '') = 'supplier' or c ? 'lead_id' or c ? 'supplier_id';
  v_email := coalesce(nullif(c ->> 'email', ''),
    (select email from public.customers where id::text = c ->> 'customer_id'),
    (select email from public.leads where id::text = coalesce(c ->> 'lead_id', c ->> 'supplier_id')));
  v_phone := coalesce(nullif(c ->> 'phone', ''), nullif(c ->> 'phone_e164', ''), nullif(c ->> 'wa_from', ''),
    (select phone from public.customers where id::text = c ->> 'customer_id'),
    (select phone from public.leads where id::text = coalesce(c ->> 'lead_id', c ->> 'supplier_id')));
  v_lang := case when v_supplier then 'en'                                         -- ruling 1008: suppliers English
                 when c ->> 'language' in ('ar', 'en') then c ->> 'language'
                 when h.question ~ '[؀-ۿ]' then 'ar' else 'en' end;
  return jsonb_build_object('email', v_email, 'phone', v_phone, 'lang', v_lang, 'supplier', v_supplier);
end $fn$;
revoke execute on function public.fn_cs_held_question_contact(bigint) from public, anon, authenticated;
grant execute on function public.fn_cs_held_question_contact(bigint) to service_role;

-- One message to the person behind a held question, through the outbox (email, else WhatsApp). Returns the row id.
create or replace function public.fn_cs_held_question_message(p_id bigint, p_kind text, p_subject text, p_body text)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare k jsonb := public.fn_cs_held_question_contact(p_id); v bigint;
begin
  if k is null or (k ->> 'email' is null and k ->> 'phone' is null) then return null; end if;
  insert into public.notifications (type, kind, channel, to_email, to_phone, subject, body, lang, sender, requested_by)
  values (p_kind, p_kind, case when k ->> 'email' is not null then 'email' else 'whatsapp' end,
          k ->> 'email', case when k ->> 'email' is null then k ->> 'phone' end, p_subject, p_body, k ->> 'lang',
          'customer_support', 'customer_support')   -- requested_by must be an active seat
  returning id into v;
  return v;
end $fn$;
revoke execute on function public.fn_cs_held_question_message(bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_cs_held_question_message(bigint, text, text, text) to service_role;

create or replace function public.fn_cs_held_question_route()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  r record;
  v_out text;
  v_lang text;
  n jsonb := '{}'::jsonb;
  v_fx constant text := 'ZZ DEMO|@example\.invalid|qd_run';
begin
  if not pg_try_advisory_xact_lock(hashtext('fn_cs_held_question_route')) then
    return jsonb_build_object('skipped', 'another run is going');
  end if;

  for r in
    select h.*,
           coalesce(h.request -> 'context' ->> 'audience', '') audience,
           (k ->> 'email' is not null or k ->> 'phone' is not null) reachable,
           (h.question ~* v_fx or h.request::text ~* v_fx or h.subject::text ~* v_fx) fixture
      from public.reasoning_held_question h
      cross join lateral (select public.fn_cs_held_question_contact(h.id) k) kk
     where h.seat = 'customer_support'
       and (h.status not in ('applied', 'closed', 'answered')
            or exists (select 1 from public.agent_actions a where a.target_table = 'reasoning_held_question'
                        and a.target_id = h.id::text and a.kind like 'held_question%' and a.status = 'pending'))
       and coalesce(h.result ->> 'cs_route', '') not in ('done', 'dismissed', 'overdue_alerted')
  loop
    v_out := case
      when r.status in ('applied', 'answered') then 'done'
      when r.fixture then 'dismissed'
      when (r.audience = 'internal' or r.surface like 'customer_support.%') and r.created_at < now() - interval '7 days'
        then 'dismissed'
      when r.audience = 'internal' or r.surface like 'customer_support.%' then null   -- a fresh duty: its seat works it
      when not r.reachable then 'dismissed'
      when coalesce(r.result ->> 'cs_route', '') = 'handed_to_ceo'
           and (r.result ->> 'cs_route_at')::timestamptz < now() - interval '4 hours' then 'overdue_alerted'
      when coalesce(r.result ->> 'cs_route', '') = 'handed_to_ceo' then null
      when r.created_at < now() - interval '15 minutes' then 'handed_to_ceo'
      else null end;
    continue when v_out is null;

    if v_out = 'handed_to_ceo' then
      -- the person is told, once, that a person has their question (and the WhatsApp holding notice is not sent twice)
      v_lang := public.fn_cs_held_question_contact(r.id) ->> 'lang';
      perform public.fn_cs_held_question_message(r.id, 'support_question_ack',
        case when v_lang = 'ar' then 'سؤالكم لدى فريقنا' else 'Your question is with our team' end,
        case when v_lang = 'ar'
             then 'شكرًا لصبركم. سؤالكم لدى فريقنا الآن ويتابعه شخص مختص، وسنعود إليكم بالإجابة قريبًا.'
             else 'Thank you for your patience. Your question is now with our team and a person is handling it; we will reply shortly.' end);
      update public.reasoning_held_question set notice_delivered_at = coalesce(notice_delivered_at, now()) where id = r.id;
    end if;

    if v_out in ('handed_to_ceo', 'overdue_alerted') then
      -- no personal data in the item: the id and the surface; the CEO duty reads the held question for the rest
      insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id, escalated, escalation_reason)
      values ('ceo', 'support_question_handover', 'pending', case when v_out = 'overdue_alerted' then 'high' else 'medium' end,
              case when v_out = 'overdue_alerted' then 'OVERDUE: a customer_support question has waited 4 hours for a person'
                   else 'A customer_support question needs a person' end,
              jsonb_build_object('held_id', r.id, 'surface', r.surface, 'asked_at', r.created_at, 'model_reason', r.reason,
                                 'needed', 'reply to the person who asked, then mark the held question answered'),
              'reasoning_held_question', r.id::text, true, 'from customer_support: ' || v_out);
    end if;

    update public.reasoning_held_question h
       set result = coalesce(h.result, '{}'::jsonb)
                    || jsonb_build_object('cs_route', v_out, 'cs_route_at', now())
                    || case when r.fixture then jsonb_build_object('demo_purge', 'founder ruling 1199: the #1348 purge list')
                            else '{}'::jsonb end
     where h.id = r.id;

    update public.agent_actions a
       set status = case when v_out = 'done' then 'done' when v_out = 'dismissed' then 'dismissed' else a.status end,
           decided_at = case when v_out in ('done', 'dismissed') then now() else a.decided_at end,
           decided_by = case when v_out in ('done', 'dismissed') then 'customer_support:fn_cs_held_question_route' else a.decided_by end,
           escalated = a.escalated or v_out in ('handed_to_ceo', 'overdue_alerted'),
           escalation_reason = case
             when v_out = 'done' then 'answered by its own surface'
             when r.fixture then 'test fixture: listed for the ruling 1199 purge, not deleted'
             when v_out = 'dismissed' and not r.reachable and r.audience <> 'internal' and r.surface not like 'customer_support.%'
               then 'no contact on the request: there is no route to the person who asked'
             when v_out = 'dismissed' then 'internal seat duty older than 7 days: its next run re-files it'
             when v_out = 'handed_to_ceo' then 'acknowledged to the person and handed to the ceo seat at ' || now()
             else 'overdue: unanswered 4 hours after it was handed to the ceo seat' end
     where a.target_table = 'reasoning_held_question' and a.target_id = r.id::text
       and a.kind like 'held_question%' and a.status = 'pending';

    n := n || jsonb_build_object(v_out, coalesce((n ->> v_out)::int, 0) + 1);
  end loop;
  return n;
end $fn$;
revoke execute on function public.fn_cs_held_question_route() from public, anon, authenticated;
grant execute on function public.fn_cs_held_question_route() to service_role;

-- THE CEO'S DUTY for support_question_handover: pick it up, have it reasoned, reply, close.
create or replace function public.fn_ceo_support_handover_duty()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a record; h public.reasoning_held_question; q public.reasoning_held_question; v_rid bigint; v_lang text;
        n jsonb := '{}'::jsonb; v_out text;
begin
  if not pg_try_advisory_xact_lock(hashtext('fn_ceo_support_handover_duty')) then
    return jsonb_build_object('skipped', 'another run is going');
  end if;
  for a in select * from public.agent_actions
            where agent = 'ceo' and kind = 'support_question_handover' and status = 'pending' order by created_at
  loop
    select * into h from public.reasoning_held_question where id = (a.detail ->> 'held_id')::bigint;
    v_rid := nullif(a.detail ->> 'reasoning_id', '')::bigint;
    q := null;
    if v_rid is not null then select * into q from public.reasoning_held_question where id = v_rid; end if;
    v_out := null;

    if h.id is null or h.status in ('answered', 'applied', 'closed') then
      v_out := 'done';                                    -- answered by a person or its own surface meanwhile
    elsif v_rid is null then
      v_lang := public.fn_cs_held_question_contact(h.id) ->> 'lang';
      v_rid := public.fn_seat_duty_reason('ceo', 'ceo.support_handover',
        'A ' || coalesce(h.request -> 'context' ->> 'audience', 'customer') || ' asked customer_support a question the '
          || 'model could not answer, and is waiting. Write the reply they will receive, in '
          || case when v_lang = 'ar' then 'Arabic' else 'English' end || ', from what the company knows; say plainly what '
          || 'is not known. Choose reply_and_refer when the sales engineer must also act on it. The question: '
          || left(h.question, 2000),
        ('[{"id":"reply","meaning":"the reply answers the question"},'
        || '{"id":"reply_and_refer","meaning":"reply, and the sales engineer must also act on it"}]')::jsonb,
        jsonb_build_object('held_id', h.id, 'surface', h.surface, 'question', left(h.question, 2000), 'language', v_lang),
        jsonb_build_object('handover_id', a.id, 'held_id', h.id), 'ceo_support_handover:' || h.id);
      update public.agent_actions set detail = detail || jsonb_build_object('reasoning_id', v_rid, 'picked_up_at', now())
       where id = a.id;
      v_out := 'picked_up';
    elsif q.status in ('reasoned', 'applied') and coalesce(q.result ->> 'answer', '') <> '' then
      v_lang := public.fn_cs_held_question_contact(h.id) ->> 'lang';
      perform public.fn_cs_held_question_message(h.id, 'support_question_reply',
        case when v_lang = 'ar' then 'الرد على سؤالكم' else 'The answer to your question' end, q.result ->> 'answer');
      update public.reasoning_held_question
         set status = 'applied', applied_at = now(), result = coalesce(result, '{}'::jsonb)
                                           || jsonb_build_object('cs_route', 'done', 'answered_by', 'ceo', 'answer_from', q.id)
       where id = h.id;
      update public.reasoning_held_question set status = 'applied', applied_at = now() where id = q.id;
      if q.result -> 'decision' ->> 'choice' = 'reply_and_refer' then
        insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
        values ('sales_engineer', 'support_referral', 'pending', 'medium', 'The CEO answered a support question and refers it to you',
                jsonb_build_object('held_id', h.id, 'ceo_reasoning', q.id), 'reasoning_held_question', h.id::text);
      end if;
      v_out := 'done';
    end if;

    if v_out = 'done' then
      update public.agent_actions set status = 'done', decided_at = now(), decided_by = 'ceo:fn_ceo_support_handover_duty'
       where id = a.id;
      -- the overdue twin of the same question closes with it
      update public.agent_actions set status = 'done', decided_at = now(), decided_by = 'ceo:fn_ceo_support_handover_duty'
       where agent = 'ceo' and kind = 'support_question_handover' and status = 'pending' and target_id = a.target_id;
    end if;
    if v_out is not null then n := n || jsonb_build_object(v_out, coalesce((n ->> v_out)::int, 0) + 1); end if;
  end loop;
  return n;
end $fn$;
revoke execute on function public.fn_ceo_support_handover_duty() from public, anon, authenticated;
grant execute on function public.fn_ceo_support_handover_duty() to service_role;

select cron.schedule('cs_held_question_route', '*/5 * * * *',
  $CRON$select public.fn_cs_held_question_route(); select public.fn_ceo_support_handover_duty();$CRON$);
insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('cs_held_question_route', 'customer_support held questions reach a person', 'Support',
   'Every 5 minutes. A customer_support question the model could not answer is acknowledged to the person and handed '
   || 'to the CEO seat within 15 minutes when the person can be reached, flagged again if unanswered after 4 hours; '
   || 'the CEO duty then has it reasoned, replies through the outbox and closes it. Fixtures are tagged for the ruling '
   || '1199 purge; anonymous widget turns and stale internal duties are closed with their reason.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
