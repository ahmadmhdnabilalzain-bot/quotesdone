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
-- A. fn_cs_held_question_route(), every heartbeat. For every customer_support held question not applied, closed or
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
--      - a support_question_handover item is filed for the CEO seat, once; still unanswered 4 hours later -> a
--        high-risk overdue alert on the same open item, once.
--      Never the founder: rulings 1254 and 8 Sep keep his WhatsApp for a person who explicitly asks for one, which the
--      WhatsApp "Talk to a person" menu already routes.
-- B. fn_ceo_support_handover_duty(), the CEO's duty for support_question_handover, its ONLY owner (rows claimed FOR
--    UPDATE SKIP LOCKED; scripts/checks/support_question_handover_has_one_owner.test.mjs):
--   - the held question was answered meanwhile             -> the handover is 'done'.
--   - not yet picked up                                     -> a ceo.support_handover reasoning is filed (fn_seat_duty_reason)
--                                                              with context.audience customer/supplier (#1441's leak rule).
-- C. THE REPLY GATE: a returned answer is never sent from SQL. fn_ceo_support_reply_due hands it to resilience_ping's
--    step ceo_support_replies, which runs _shared/ai_reply.ts customerReplyGate (the leak, canned/deferral, policy and
--    language checks every customer reply passes) and records the verdict in fn_ceo_support_reply_record: passed ->
--    sent once, question applied, item done; failed -> held, problems recorded, the item STAYS OPEN.
-- Every message goes only to a CONFIRMED contact (verified email; OTP-confirmed WhatsApp number), once per kind per
-- question (notifications.dedupe_key <kind>:<held_id>, on conflict do nothing). No confirmed contact -> nothing is sent
-- and the question is dismissed as unreachable.
-- SCHEDULE: the router and the CEO duty run on their own pg_cron job (cs_held_question_route, every 5 minutes; pg_cron is
-- live: 12 active jobs, 51 runs in the 30 minutes to 21:44 UTC on 18 Oct). Only the reply gate, which is TypeScript
-- (customerReplyGate), runs in an edge function: resilience_ping's step ceo_support_replies.
-- A KNOWN customer or supplier (customer_id / lead_id / supplier_id) with no confirmed contact is never dismissed: it
-- stays open with customer_support (support_no_confirmed_contact) and becomes the CEO's overdue item at 4 hours; only a
-- truly anonymous visitor is dismissed.
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
  -- ONLY A CONFIRMED CONTACT (review of #1462): an email only when the account verified it, WhatsApp only to the
  -- OTP-confirmed number (whatsapp_verified_at). A contact typed into a chat or carried on the request is never used.
  v_email := coalesce(
    (select email from public.customers where id::text = c ->> 'customer_id' and email_verified is true),
    (select email from public.leads where id::text = coalesce(c ->> 'lead_id', c ->> 'supplier_id') and owner_email_verified is true));
  v_phone := coalesce(
    (select phone from public.customers where id::text = c ->> 'customer_id' and whatsapp_verified_at is not null),
    (select phone from public.leads where id::text = coalesce(c ->> 'lead_id', c ->> 'supplier_id') and whatsapp_verified_at is not null));
  v_lang := case when v_supplier then 'en'                                         -- ruling 1008: suppliers English
                 when c ->> 'language' in ('ar', 'en') then c ->> 'language'
                 when h.question ~ '[؀-ۿ]' then 'ar' else 'en' end;
  return jsonb_build_object('email', v_email, 'phone', v_phone, 'lang', v_lang, 'supplier', v_supplier);
end $fn$;
revoke execute on function public.fn_cs_held_question_contact(bigint) from public, anon, authenticated;
grant execute on function public.fn_cs_held_question_contact(bigint) to service_role;

-- ONE message per kind per question (review of #1462: a retry never double-sends): dedupe_key <kind>:<held_id>.
alter table public.notifications add column if not exists dedupe_key text;
create unique index if not exists notifications_dedupe_key_uidx on public.notifications (dedupe_key) where dedupe_key is not null;

-- One message to the person behind a held question, through the outbox (email, else WhatsApp), to a CONFIRMED
-- contact only. Returns the row id; null when there is no confirmed contact or the message was already queued.
create or replace function public.fn_cs_held_question_message(p_id bigint, p_kind text, p_subject text, p_body text)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare k jsonb := public.fn_cs_held_question_contact(p_id); v bigint;
begin
  if k is null or (k ->> 'email' is null and k ->> 'phone' is null) then return null; end if;
  insert into public.notifications (type, kind, channel, to_email, to_phone, subject, body, lang, sender, requested_by, dedupe_key)
  values (p_kind, p_kind, case when k ->> 'email' is not null then 'email' else 'whatsapp' end,
          k ->> 'email', case when k ->> 'email' is null then k ->> 'phone' end, p_subject, p_body, k ->> 'lang',
          'customer_support', 'customer_support',   -- requested_by must be an active seat
          p_kind || ':' || p_id)
  on conflict (dedupe_key) where dedupe_key is not null do nothing
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
           (coalesce(h.request -> 'context', '{}'::jsonb) || coalesce(h.subject, '{}'::jsonb))
             ?| array['customer_id', 'lead_id', 'supplier_id'] known,
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
      when not r.reachable and not r.known then 'dismissed'               -- a truly anonymous visitor
      -- a KNOWN customer or supplier with no confirmed contact stays open with customer_support (reply on the surface
      -- they asked from, or confirm the contact); 4 hours from the question it becomes the CEO's overdue item
      when not r.reachable and r.created_at < now() - interval '4 hours' then 'overdue_alerted'
      when not r.reachable and coalesce(r.result ->> 'cs_route', '') = 'no_confirmed_contact' then null
      when not r.reachable then 'no_confirmed_contact'
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
              'reasoning_held_question', r.id::text, true, 'from customer_support: ' || v_out)
      -- one pending item per question (agent_actions_dedupe): the overdue alert RAISES the open item, a retry is a no-op
      on conflict (agent, kind, target_id) where status = 'pending'
      do update set risk = excluded.risk, title = excluded.title, escalation_reason = excluded.escalation_reason;
    end if;

    if v_out = 'no_confirmed_contact' then
      -- customer_support keeps it: an open item of its own (one per question), even when no held_question action exists
      insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id, escalation_reason)
      values ('customer_support', 'support_no_confirmed_contact', 'pending', 'medium',
              'A known person is waiting and has no confirmed contact',
              jsonb_build_object('held_id', r.id, 'surface', r.surface, 'asked_at', r.created_at,
                                 'needed', 'reply on the surface they asked from, or have them confirm their email or WhatsApp number'),
              'reasoning_held_question', r.id::text, 'no confirmed contact')
      on conflict (agent, kind, target_id) where status = 'pending' do nothing;
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
             when v_out = 'no_confirmed_contact'
               then 'no confirmed contact: reply on the surface they asked from, or confirm the contact'
             else 'overdue: unanswered 4 hours after it was handed to the ceo seat' end
     where a.target_table = 'reasoning_held_question' and a.target_id = r.id::text
       and a.kind like 'held_question%' and a.status = 'pending';

    n := n || jsonb_build_object(v_out, coalesce((n ->> v_out)::int, 0) + 1);
  end loop;
  return n;
end $fn$;
revoke execute on function public.fn_cs_held_question_route() from public, anon, authenticated;
grant execute on function public.fn_cs_held_question_route() to service_role;

-- THE CEO'S DUTY for support_question_handover: pick it up and have it reasoned; close it when the question is
-- answered. ONE OWNER (review of #1462): only this duty and fn_ceo_support_reply_record settle this kind, and both claim
-- the item FOR UPDATE SKIP LOCKED, so a general CEO worker running at the same moment can never settle it twice
-- (scripts/checks/support_question_handover_has_one_owner.test.mjs asserts no other routine names the kind).
create or replace function public.fn_ceo_support_handover_duty()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a record; h public.reasoning_held_question; v_rid bigint; v_lang text; v_aud text;
        n jsonb := '{}'::jsonb; v_out text;
begin
  for a in select * from public.agent_actions
            where agent = 'ceo' and kind = 'support_question_handover' and status = 'pending'
            order by created_at
            for update skip locked
  loop
    select * into h from public.reasoning_held_question where id = (a.detail ->> 'held_id')::bigint;
    v_out := null;
    if h.id is null or h.status = 'applied' then
      v_out := 'done';                                    -- answered by a person, its own surface or the reply gate
    elsif nullif(a.detail ->> 'reasoning_id', '') is null then
      v_lang := public.fn_cs_held_question_contact(h.id) ->> 'lang';
      v_aud := case when (public.fn_cs_held_question_contact(h.id) ->> 'supplier')::boolean then 'supplier' else 'customer' end;
      v_rid := public.fn_seat_duty_reason('ceo', 'ceo.support_handover',
        'A ' || v_aud || ' asked customer_support a question the model could not answer, and is waiting. Write the '
          || 'reply they will receive, in ' || case when v_lang = 'ar' then 'Arabic' else 'English' end
          || ', from what the company knows; say plainly what is not known. Choose reply_and_refer when the sales '
          || 'engineer must also act on it. The question: ' || left(h.question, 2000),
        ('[{"id":"reply","meaning":"the reply answers the question"},'
        || '{"id":"reply_and_refer","meaning":"reply, and the sales engineer must also act on it"}]')::jsonb,
        jsonb_build_object('held_id', h.id, 'surface', h.surface, 'question', left(h.question, 2000), 'language', v_lang),
        jsonb_build_object('handover_id', a.id, 'held_id', h.id), 'ceo_support_handover:' || h.id);
      -- the answer goes to a person outside the company: think() reads it as that audience, so no other party's case
      -- text reaches the prompt (#1441's rule keys on context.audience)
      update public.reasoning_held_question
         set request = jsonb_set(request, '{context,audience}', to_jsonb(v_aud))
       where id = v_rid;
      update public.agent_actions set detail = detail || jsonb_build_object('reasoning_id', v_rid, 'picked_up_at', now())
       where id = a.id;
      v_out := 'picked_up';
    end if;
    if v_out = 'done' then
      update public.agent_actions set status = 'done', decided_at = now(), decided_by = 'ceo:fn_ceo_support_handover_duty'
       where agent = 'ceo' and kind = 'support_question_handover' and status = 'pending' and target_id = a.target_id;
    end if;
    if v_out is not null then n := n || jsonb_build_object(v_out, coalesce((n ->> v_out)::int, 0) + 1); end if;
  end loop;
  return n;
end $fn$;
revoke execute on function public.fn_ceo_support_handover_duty() from public, anon, authenticated;
grant execute on function public.fn_ceo_support_handover_duty() to service_role;

-- THE REPLY GATE (review of #1462). A reasoned CEO answer is NOT sent from SQL: resilience_ping's step
-- ceo_support_replies takes these rows, runs the same customer-reply gate as every other reply
-- (_shared/ai_reply.ts customerReplyGate: replyProblems' leak, canned/deferral and policy checks, plus the language
-- check) and records the verdict through fn_ceo_support_reply_record. A row is offered again only when its answer
-- changed since the gate last held it.
create or replace function public.fn_ceo_support_reply_due(p_limit integer default 10)
returns jsonb
language plpgsql stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  return coalesce((select jsonb_agg(jsonb_build_object('handover_id', a.id, 'held_id', h.id, 'answer', q.result ->> 'answer',
                                                        'lang', k ->> 'lang', 'supplier', (k ->> 'supplier')::boolean))
    from public.agent_actions a
    join public.reasoning_held_question h on h.id = (a.detail ->> 'held_id')::bigint
    join public.reasoning_held_question q on q.id = nullif(a.detail ->> 'reasoning_id', '')::bigint
    cross join lateral (select public.fn_cs_held_question_contact(h.id) k) kk
   where a.agent = 'ceo' and a.kind = 'support_question_handover' and a.status = 'pending'
     and h.status <> 'applied' and q.status in ('reasoned', 'applied') and coalesce(q.result ->> 'answer', '') <> ''
     and coalesce(a.detail ->> 'gate_held_md5', '') <> md5(q.result ->> 'answer')
   limit greatest(1, least(coalesce(p_limit, 10), 50))), '[]'::jsonb);
end $fn$;
revoke execute on function public.fn_ceo_support_reply_due(integer) from public, anon, authenticated;
grant execute on function public.fn_ceo_support_reply_due(integer) to service_role;

-- The gate's verdict. Passed: the answer is queued to the person (once, dedupe key), the held question is applied,
-- the handover and its overdue twin are done. Held: the problems are recorded on the item, which STAYS OPEN.
create or replace function public.fn_ceo_support_reply_record(p_handover_id bigint, p_problems jsonb)
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions; q public.reasoning_held_question; v_lang text;
begin
  select * into a from public.agent_actions
   where id = p_handover_id and agent = 'ceo' and kind = 'support_question_handover' and status = 'pending'
   for update skip locked;
  if a.id is null then return 'not pending or claimed elsewhere'; end if;
  select * into q from public.reasoning_held_question where id = nullif(a.detail ->> 'reasoning_id', '')::bigint;
  if q.id is null or coalesce(q.result ->> 'answer', '') = '' then return 'no answer yet'; end if;
  -- a passed reply still needs a confirmed contact to go to; without one it is held like a failed one
  if not exists (select 1 from jsonb_each_text(public.fn_cs_held_question_contact((a.detail ->> 'held_id')::bigint)) e
                  where e.key in ('email', 'phone') and e.value is not null)
     and coalesce(jsonb_array_length(case when jsonb_typeof(p_problems) = 'array' then p_problems end), 0) = 0 then
    p_problems := '["no confirmed contact: reply on the surface they asked from, or confirm the contact"]'::jsonb;
  end if;

  if jsonb_typeof(p_problems) = 'array' and jsonb_array_length(p_problems) > 0 then
    update public.agent_actions
       set detail = detail || jsonb_build_object('gate_held', p_problems, 'gate_held_at', now(),
                                                 'gate_held_md5', md5(q.result ->> 'answer'))
     where id = a.id;
    return 'held';
  end if;

  v_lang := public.fn_cs_held_question_contact((a.detail ->> 'held_id')::bigint) ->> 'lang';
  perform public.fn_cs_held_question_message((a.detail ->> 'held_id')::bigint, 'support_question_reply',
    case when v_lang = 'ar' then 'الرد على سؤالكم' else 'The answer to your question' end, q.result ->> 'answer');
  update public.reasoning_held_question
     set status = 'applied', applied_at = now(),
         result = coalesce(result, '{}'::jsonb) || jsonb_build_object('cs_route', 'done', 'answered_by', 'ceo', 'answer_from', q.id)
   where id = (a.detail ->> 'held_id')::bigint;
  update public.reasoning_held_question set status = 'applied', applied_at = now() where id = q.id;
  if q.result -> 'decision' ->> 'choice' = 'reply_and_refer' then
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    values ('sales_engineer', 'support_referral', 'pending', 'medium', 'The CEO answered a support question and refers it to you',
            jsonb_build_object('held_id', a.detail ->> 'held_id', 'ceo_reasoning', q.id), 'reasoning_held_question', a.detail ->> 'held_id');
  end if;
  update public.agent_actions set status = 'done', decided_at = now(), decided_by = 'ceo:fn_ceo_support_reply_record'
   where agent = 'ceo' and kind = 'support_question_handover' and status = 'pending' and target_id = a.target_id;
  return 'sent';
end $fn$;
revoke execute on function public.fn_ceo_support_reply_record(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_ceo_support_reply_record(bigint, jsonb) to service_role;


-- The router and the CEO duty run on pg_cron (live: 12 active jobs, 51 runs in the 30 minutes to 21:44 UTC on 18 Oct);
-- only the TypeScript reply gate runs on resilience_ping (step ceo_support_replies).
select cron.schedule('cs_held_question_route', '*/5 * * * *',
  $CRON$select public.fn_cs_held_question_route(); select public.fn_ceo_support_handover_duty();$CRON$);
insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('cs_held_question_route', 'customer_support held questions reach a person', 'Support',
   'Every 5 minutes. A customer_support question the model could not answer: a person with a confirmed contact is '
   || 'acknowledged and handed to the CEO seat after 15 minutes; a known person without one stays with customer_support; '
   || 'either becomes the CEO''s overdue item at 4 hours. The CEO duty then has it reasoned; the reply is sent only after '
   || 'resilience_ping''s customer-reply gate. Fixtures are tagged for the ruling 1199 purge; anonymous widget turns and '
   || 'stale internal duties are closed with their reason.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
