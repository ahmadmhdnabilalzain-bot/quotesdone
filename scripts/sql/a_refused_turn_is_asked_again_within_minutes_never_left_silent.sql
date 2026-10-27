-- A REFUSED TURN IS ASKED AGAIN WITHIN MINUTES; NO CUSTOMER OR SUPPLIER IS LEFT SILENT (27 Oct 2026).
-- Assigned: customer_support (the WhatsApp turn, the pg_cron job) and sales_engineer (the portal chat and the supplier
-- quotation thread). Founder ruling 1339, 27 Oct 2026, verbatim: "the engineer and customer support never replies without
-- llm unless the server of open router is down".
--
-- THE GAP (independent review of #1640 at 4d5c6cfd0, which contains #1647; measured by reading the code and the schema
-- mirror, 27 Oct 2026): a turn where the model is UP but every draft and the retry were refused gets no reply.
--   * portal: sales_engineer `assist` answered 503 outage:false, nothing was filed and nothing asked the model again;
--   * the request chat (inquiry_intake, #1646): on the held-for-trade path a refused intakeVoice (by 'none') pushed an
--     EMPTY assistant message and filed nothing;
--   * WhatsApp (wa_inbound.unwritten_reply) and the supplier thread (supplier_api.quote_review_unwritten) were filed, but
--     the only re-ask was resilience_ping's replay: every 15 minutes, think() first, then the same writer the same way.
--     When that writer refused again the delivery was via 'none', and fn_reason_held_delivered marks a via-'none' row
--     'applied': closed, never escalated (fn_reason_held_escalate reads 'held' and 'failed' only), the person silent.
--   * qhash keys a held question on surface + question + context; two people sending the same words were ONE question,
--     and fn_reason_hold returns an earlier FAILED row of that hash instead of filing the second person's turn.
--
-- CHANGE (the edge half is supabase/functions/_shared/reask.ts; the callers add context.turn_id and request.reask):
--   1. fn_reask_due(p_limit): claims the due rows of the three re-ask surfaces (first ~30 s after filing, then each minute,
--      3 attempts; never under the founder's hold; never a row already being sent). A row whose send started and never
--      recorded (5 minutes) is NOT sent again: it is handed to its seat (one reply per turn, never two).
--   2. fn_reask_record(p_id, p_outcome): 'sending' (claimed for one send), delivered (applied), an outage (the attempt is
--      returned: nothing code-written goes out from the re-ask), refused (its problems kept for the next ask; the third
--      refusal hands the turn to its seat now: status failed, escalated, a held_question item for the seat, and the portal
--      row reads 'with_team'). A reviewed reply that fails the gates stays with the seat with its problems.
--   3. fn_reask_reviewed_reply(p_id, p_reply, p_by): the hand-off's reply (a person, or the CEO seat) goes back through the
--      same door and gates; never sent around them.
--   4. fn_reask_kick(): pg_cron every minute; calls sales_engineer `reask_turns` ONLY when fn_reask_any_due() says
--      fn_reask_due would act (never under the founder's hold), with the gateway key from fn_gateway_client_key().
--   5. fn_reason_held_due: the 15-minute think() replay no longer claims the re-ask surfaces (one asker per turn).
--   6. fn_reason_held_escalate: the portal surface joins the 15-minute rule (a stopped re-ask still reaches the seat).
-- Every routine: SECURITY DEFINER, search_path pinned, EXECUTE revoked from public, anon and authenticated (the two
-- redefinitions are CREATE OR REPLACE and keep their ACL). Bodies of 5 and 6 are the schema mirror's (production) with
-- only the marked lines changed.
-- APPLY ORDER: deploy sales_engineer, wa_inbound and supplier_api FIRST (reask_turns must exist before the job calls it).
-- prevented by: supabase/functions/_shared/reask.test.ts,
--               scripts/checks/a_refused_turn_is_asked_again_never_left_silent.test.mjs,
--               scripts/sql/a_refused_turn_is_asked_again_within_minutes_never_left_silent_probe.sql

create or replace function public.fn_reask_surfaces()
returns text[]
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select array['wa_inbound.unwritten_reply', 'supplier_api.quote_review_unwritten', 'sales_engineer.portal_unwritten',
               'inquiry_intake.unwritten_reply']::text[];
$fn$;
revoke execute on function public.fn_reask_surfaces() from public, anon, authenticated;

create or replace function public.fn_reask_due(p_limit integer default 5)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_gate jsonb; v jsonb;
begin
  -- a send that started and never recorded is never repeated: the seat has it (one reply per turn). The marker moves to
  -- reask_send_unrecorded_at (review of #1657, 27 Oct 2026): left in place, this row matched the kick's predicate for ever,
  -- and the kick posted to sales_engineer every minute while this update rewrote the same row every minute.
  update public.reasoning_held_question
     set status = 'failed',
         result = coalesce(result, '{}'::jsonb) - 'reask_sending_at'
                  || jsonb_build_object('reask_send_unrecorded_at', result ->> 'reask_sending_at',
                                        'reask_handed_off', 'its send started at '
                  || (result ->> 'reask_sending_at') || ' and never recorded an outcome; not sent again'),
         notice_delivered_at = coalesce(notice_delivered_at, now())   -- the person may have the answer: no notice on top
   where surface = any(public.fn_reask_surfaces()) and status in ('held', 'failed')
     and (result ->> 'reask_sending_at')::timestamptz < now() - interval '5 minutes';

  v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
  if coalesce(v_gate->>'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state') then
    return '[]'::jsonb;
  end if;
  with due as (
    select h.id from public.reasoning_held_question h
     where h.surface = any(public.fn_reask_surfaces())
       and h.result ->> 'reask_sending_at' is null
       and (   (h.status = 'held' and h.attempts < 3 and h.created_at <= now() - interval '30 seconds'
                and (h.last_attempt_at is null or h.last_attempt_at <= now() - interval '50 seconds'))
            -- a reviewed reply after the hand-off: the row is 'failed' (handed off) or 'held'; fn_reason_held_sweep turns
            -- a held row at 3 attempts into 'failed', so both are open here
            or  (h.status in ('held', 'failed') and h.result ->> 'reviewed_state' = 'due'))
     order by h.created_at
     limit greatest(1, least(coalesce(p_limit, 5), 20))
     for update skip locked
  ), claimed as (
    update public.reasoning_held_question h
       set attempts = h.attempts + case when h.result ->> 'reviewed_state' = 'due' then 0 else 1 end, last_attempt_at = now()
      from due where h.id = due.id
    returning h.id, h.seat, h.surface, h.request, h.subject, h.attempts, h.result, h.created_at
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into v from claimed;
  return v;
end $fn$;
revoke execute on function public.fn_reask_due(integer) from public, anon, authenticated;

create or replace function public.fn_reask_record(p_id bigint, p_outcome jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h public.reasoning_held_question; v_problems jsonb; v_log text; v_title text;
begin
  select * into h from public.reasoning_held_question where id = p_id for update;
  if h.id is null then return jsonb_build_object('id', p_id, 'status', 'missing'); end if;
  if not (h.surface = any(public.fn_reask_surfaces())) then
    raise exception 'fn_reask_record: % is not a re-ask surface', h.surface using errcode = '22023';
  end if;
  v_log := h.subject ->> 'log_id';

  -- 0. a run that LOST the 'sending' claim to another run sent nothing and owns nothing: no change (review of #1657, 27 Oct
  --    2026). Recorded as an ordinary failure, it fell into branch 3 below on the WINNER's marker: the row was failed and
  --    handed to the seat while the winner was still delivering, and the winner's own failure could no longer be told.
  if p_outcome ->> 'via' = 'not_yours' then
    return jsonb_build_object('id', p_id, 'status', 'not_yours');
  end if;

  -- 1. claimed for ONE send: an open row nobody else is sending. 'failed' is open too: fn_reason_held_sweep turns a held
  --    row at 3 attempts into 'failed' while its third re-ask is running, and a reviewed reply is sent from 'failed'.
  if p_outcome ->> 'phase' = 'sending' then
    if h.status not in ('held', 'failed') or h.result ? 'reask_sending_at' then
      return jsonb_build_object('id', p_id, 'status', 'not_yours');
    end if;
    update public.reasoning_held_question set result = coalesce(result, '{}'::jsonb) || jsonb_build_object('reask_sending_at', now())
     where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'sending');
  end if;

  -- 2. delivered into the conversation: the turn is answered, no holding notice is owed
  if coalesce((p_outcome ->> 'delivered')::boolean, false) then
    update public.reasoning_held_question
       set status = 'applied', applied_at = now(), notice_delivered_at = coalesce(notice_delivered_at, now()),
           result = coalesce(result, '{}'::jsonb) - 'reask_sending_at'
                    || jsonb_build_object('reask_delivery', p_outcome, 'reask_delivered_at', now(),
                                          'reviewed_state', case when h.result ->> 'reviewed_state' = 'due' then 'sent' else h.result ->> 'reviewed_state' end)
     where id = p_id;
    -- the seat's open item for this turn (if it was handed off) is done: the person has their reply
    update public.agent_actions set status = 'done', decided_at = now(), decided_by = 'fn_reask_record'
     where target_table = 'reasoning_held_question' and target_id = p_id::text and kind = 'held_question' and status = 'pending';
    return jsonb_build_object('id', p_id, 'status', 'delivered');
  end if;

  -- 3. a send that started and failed (the channel refused it): the seat has it, never sent a second time
  if h.result ? 'reask_sending_at' then
    update public.reasoning_held_question
       set status = 'failed', result = result - 'reask_sending_at' || jsonb_build_object('reask_delivery', p_outcome,
             'reask_handed_off', 'the send failed: ' || coalesce(p_outcome ->> 'detail', p_outcome ->> 'via', '?'))
     where id = p_id;
    perform public.fn_reask_hand_off(p_id);
    return jsonb_build_object('id', p_id, 'status', 'handed_off');
  end if;

  -- 4. a reviewed reply the gates refused: it stays with the seat, with what was wrong
  if coalesce((p_outcome ->> 'reviewed')::boolean, false) then
    update public.reasoning_held_question
       set status = 'failed', result = coalesce(result, '{}'::jsonb) || jsonb_build_object('reviewed_state', 'refused',
             'reviewed_problems', coalesce(p_outcome -> 'problems', '[]'::jsonb), 'reviewed_refused_at', now())
     where id = p_id;
    perform public.fn_reask_hand_off(p_id);
    return jsonb_build_object('id', p_id, 'status', 'handed_off');
  end if;

  -- 5. OpenRouter down: the attempt is given back; nothing code-written goes out from here (the turn's own notice did).
  --    BOUNDED (review of #1657, 27 Oct 2026): for the turn's first 24 hours only. A re-ask row has no expires_at (only
  --    fn_reason_held_due sets one, and it no longer claims these surfaces), and 'deadline' counts as an outage, so a
  --    model that kept answering past the 45 s clock was asked every minute for ever, each call possibly billed. After
  --    24 hours an outage spends its attempt like a refusal; at 3 the sweep fails the row and the seat has it.
  if coalesce((p_outcome ->> 'outage')::boolean, false) then
    update public.reasoning_held_question
       set attempts = case when created_at > now() - interval '24 hours' then greatest(attempts - 1, 0) else attempts end,
           result = coalesce(result, '{}'::jsonb) || jsonb_build_object('reask_last', p_outcome, 'reask_last_at', now())
     where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'outage');
  end if;

  -- 6. the model answered and nothing passed: keep its problems for the next ask; the last attempt hands it off
  select coalesce(jsonb_agg(distinct x), '[]'::jsonb) into v_problems
    from (select x from jsonb_array_elements_text(coalesce(h.result -> 'reask_problems', '[]'::jsonb)) x
          union select x from jsonb_array_elements_text(case when jsonb_typeof(p_outcome -> 'problems') = 'array' then p_outcome -> 'problems' else '[]'::jsonb end) x) z;
  update public.reasoning_held_question
     set result = coalesce(result, '{}'::jsonb) || jsonb_build_object('reask_problems', v_problems, 'reask_last', p_outcome, 'reask_last_at', now())
   where id = p_id;
  if h.attempts >= 3 then
    update public.reasoning_held_question
       set status = 'failed', result = result || jsonb_build_object('reask_handed_off', h.attempts || ' re-asks, every answer refused by the guards')
     where id = p_id;
    perform public.fn_reask_hand_off(p_id);
    return jsonb_build_object('id', p_id, 'status', 'handed_off');
  end if;
  return jsonb_build_object('id', p_id, 'status', 'asked_again_later', 'attempts', h.attempts);
end $fn$;

-- THE HAND-OFF, ONCE: the same item fn_reason_held_escalate files (agent_actions held_question for the owning seat), now
-- rather than at the next 15-minute tick; the portal turn reads 'with_team'. A WhatsApp person is told by the re-ask tick
-- in the model's words (reasoned_delivery.holdingNotice); a code-written notice goes only on an outage.
create or replace function public.fn_reask_hand_off(p_id bigint)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h public.reasoning_held_question;
begin
  update public.reasoning_held_question set escalated_at = now()
   where id = p_id and escalated_at is null
  returning * into h;
  if h.id is null then return; end if;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values (h.seat, 'held_question', 'pending', 'medium',
          left('A ' || coalesce(h.request -> 'context' ->> 'audience', 'customer') || ' on ' || h.surface
               || ' has no reply: every model answer was refused. Write the reply.', 200),
          jsonb_build_object('held_id', h.id, 'surface', h.surface, 'question', left(h.question, 1000), 'subject', h.subject,
                             'held_since', h.created_at, 'status', h.status,
                             'refused_for', coalesce(h.result -> 'reask_problems', '[]'::jsonb),
                             'needed', 'write the reply and pass it to public.fn_reask_reviewed_reply(' || h.id
                                       || ', <reply>, <who>): it is checked by the same gates and delivered into the same conversation'),
          'reasoning_held_question', h.id::text);
  if h.subject ->> 'log_id' ~ '^[0-9]+$' then
    update public.assistant_logs set path = 'portal:with_team'
     where id = (h.subject ->> 'log_id')::bigint and reply is null and path = 'portal:pending';
  end if;
end $fn$;
revoke execute on function public.fn_reask_hand_off(bigint) from public, anon, authenticated;
revoke execute on function public.fn_reask_record(bigint, jsonb) from public, anon, authenticated;

create or replace function public.fn_reask_reviewed_reply(p_id bigint, p_reply text, p_by text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h public.reasoning_held_question;
begin
  if btrim(coalesce(p_reply, '')) = '' or btrim(coalesce(p_by, '')) = '' then
    raise exception 'fn_reask_reviewed_reply: a reply and who wrote it are required' using errcode = '22023';
  end if;
  select * into h from public.reasoning_held_question where id = p_id for update;
  if h.id is null or not (h.surface = any(public.fn_reask_surfaces())) then
    raise exception 'fn_reask_reviewed_reply: % is not a held re-ask turn', p_id using errcode = '22023';
  end if;
  if h.status not in ('held', 'failed') then return jsonb_build_object('id', p_id, 'status', 'closed: ' || h.status); end if;
  update public.reasoning_held_question
     set result = coalesce(result, '{}'::jsonb) - 'reask_sending_at'
                  || jsonb_build_object('reviewed_reply', left(p_reply, 4000), 'reviewed_by', left(p_by, 120),
                                        'reviewed_at', now(), 'reviewed_state', 'due')
   where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'queued_for_the_gates');
end $fn$;
revoke execute on function public.fn_reask_reviewed_reply(bigint, text, text) from public, anon, authenticated;

-- WHEN THE KICK MAY SPEND A REQUEST (review of #1657, 27 Oct 2026). The kick's own predicate had drifted from
-- fn_reask_due's: it fired for a row inside its 50-second pause (every row, once per attempt), under the founder's hold
-- (every minute for as long as the hold lasted), and for a stale 'sending' row that fn_reask_due never cleared (every
-- minute, for ever). Each was an edge invocation that claimed nothing. This is now true only when fn_reask_due would
-- claim a row or clear a stale send, and never under the hold.
create or replace function public.fn_reask_any_due()
returns boolean
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_gate jsonb;
begin
  if exists (select 1 from public.reasoning_held_question
              where surface = any(public.fn_reask_surfaces()) and status in ('held', 'failed')
                and (result ->> 'reask_sending_at')::timestamptz < now() - interval '5 minutes') then
    return true;   -- a stale send to hand to the seat (fn_reask_due's first statement; no model call)
  end if;
  v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
  if coalesce(v_gate->>'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state') then
    return false;
  end if;
  return exists (select 1 from public.reasoning_held_question h
                  where h.surface = any(public.fn_reask_surfaces())
                    and h.result ->> 'reask_sending_at' is null
                    and (   (h.status = 'held' and h.attempts < 3 and h.created_at <= now() - interval '30 seconds'
                             and (h.last_attempt_at is null or h.last_attempt_at <= now() - interval '50 seconds'))
                         or (h.status in ('held', 'failed') and h.result ->> 'reviewed_state' = 'due')));
end $fn$;
revoke execute on function public.fn_reask_any_due() from public, anon, authenticated;

create or replace function public.fn_reask_kick()
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_ref text; v_key text; v_cred text;
begin
  -- no request unless fn_reask_due would act: no edge call, no cost
  if not public.fn_reask_any_due() then
    return null;
  end if;
  select value into v_ref  from public.app_secrets where key = 'project_ref';
  -- the gateway key through the one helper (the_lead_sourcing_kick_sends_the_publishable_key_not_the_legacy_anon_jwt.sql):
  -- the legacy anon JWT is signed with the leaked HS256 secret, which can be revoked only once no routine sends it
  v_key := public.fn_gateway_client_key();
  select value into v_cred from public.app_secrets where key = 'cred_fn_sales_engineer';
  if v_ref is null or v_key is null or v_cred is null then
    raise exception 'fn_reask_kick: project_ref, publishable_key (or anon_key) or cred_fn_sales_engineer missing from app_secrets';
  end if;
  return net.http_post(url := 'https://' || v_ref || '.supabase.co/functions/v1/sales_engineer',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key, 'apikey', v_key),
    body := jsonb_build_object('__secret', v_cred, 'action', 'reask_turns'), timeout_milliseconds := 140000);
end $fn$;
revoke execute on function public.fn_reask_kick() from public, anon, authenticated;

-- 5. The 15-minute think() replay leaves the re-ask surfaces to fn_reask_due (one asker per turn). Body: schema mirror.
CREATE OR REPLACE FUNCTION public.fn_reason_held_due(p_limit integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_gate jsonb; v jsonb;
begin
  perform public.fn_reason_held_sweep();
  v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
  if coalesce(v_gate->>'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state') then
    return '[]'::jsonb;
  end if;
  with lead as (
    select distinct on (surface, coalesce(qhash, id::text)) id, attempts, last_attempt_at, created_at
      from public.reasoning_held_question
     where status = 'held' and attempts < 3
       and not (surface = any(public.fn_reask_surfaces()))   -- 27 Oct 2026: asked again by fn_reask_due, every minute
     order by surface, coalesce(qhash, id::text), attempts desc, id
  ), due as (
    select h.id from public.reasoning_held_question h
     where h.id in (select id from lead where last_attempt_at is null or last_attempt_at < now() - interval '10 minutes')
     -- 6 Oct: the NEWEST due question first; a retry (last_attempt_at set) still waits its 10 minutes, then goes
     -- behind untried rows exactly as before, so it is never starved past its three tries.
     order by h.last_attempt_at nulls first, h.created_at desc
     limit greatest(1, least(coalesce(p_limit, 3), 10))
     for update skip locked
  ), claimed as (
    -- 6 Oct: the first claim starts the 14-day clock (a question waits out the hold without ageing)
    update public.reasoning_held_question h set attempts = h.attempts + 1, last_attempt_at = now(),
           expires_at = case when h.attempts = 0 and h.surface not like 'site_assistant.%'
                             then now() + interval '14 days' else h.expires_at end
      from due where h.id = due.id
    returning h.id, h.seat, h.surface, h.request, h.subject, h.created_at
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into v from claimed;
  return v;
end $function$;

-- 6. A stopped re-ask still reaches the seat in 15 minutes: the portal surface joins the rule. Body: schema mirror.
CREATE OR REPLACE FUNCTION public.fn_reason_held_escalate(p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb;
begin
  with stale as (
    select id from public.reasoning_held_question
     where escalated_at is null
       and (status = 'failed'
            or (status = 'held' and created_at <= now() - interval '48 hours')
            -- a person is waiting on a conversation reply no model could write: 15 minutes, not 48 hours
            or (status = 'held' and surface = any(public.fn_reask_surfaces())
                and created_at <= now() - interval '15 minutes'))
     order by created_at
     limit greatest(1, least(coalesce(p_limit, 20), 100))
     for update skip locked
  ), marked as (
    update public.reasoning_held_question h set escalated_at = now()
      from stale where h.id = stale.id
    returning h.id, h.seat, h.surface, h.question, h.subject, h.status, h.created_at
  ), filed as (
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    select m.seat, 'held_question', 'pending', 'low',
           left('A question held ' || case when m.status = 'failed' then 'after 5 failed reasonings'
                                           when m.surface = any(public.fn_reask_surfaces())
                                             then '15 minutes with no model-written reply'
                                           else 'for 48 hours' end
                || ' on ' || m.surface || ' needs you', 200),
           jsonb_build_object('held_id', m.id, 'surface', m.surface, 'question', left(m.question, 1000), 'subject', m.subject,
                              'held_since', m.created_at, 'status', m.status,
                              'waiting_for', m.seat || ' to answer or act on it; it is also replayed the moment the model hold lifts'),
           'reasoning_held_question', m.id::text
      from marked m
    returning id
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'seat', m.seat, 'surface', m.surface, 'question', left(m.question, 500),
                                              'subject', m.subject, 'status', m.status)), '[]'::jsonb)
    into v from marked m where (select count(*) from filed) >= 0;
  -- the portal turn reads 'with_team' once its seat has it
  update public.assistant_logs l set path = 'portal:with_team'
    from public.reasoning_held_question h
   where h.surface = 'sales_engineer.portal_unwritten' and h.escalated_at is not null and h.status <> 'applied'
     and h.subject ->> 'log_id' ~ '^[0-9]+$' and l.id = (h.subject ->> 'log_id')::bigint
     and l.reply is null and l.path = 'portal:pending';
  return v;
end $function$;

-- 4. The job: every minute, a request only when a turn is due. Owned by customer_support (the conversations' seat).
select cron.schedule('reask_refused_turns', '* * * * *', $CRON$select public.fn_reask_kick();$CRON$);
insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('reask_refused_turns', 'a refused reply is asked again within minutes', 'Support',
   'Every minute; a request only when a turn is due. A portal, WhatsApp or supplier-thread turn whose every model answer '
   || 'was refused is asked again (another model family, the refused drafts'' problems named, every guard again) and the '
   || 'answer is delivered into the same conversation; after 3 refused re-asks the turn goes to its seat. Ruling 1339.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'reask_refused_turns', 'customer_support',
   'Every minute: fn_reask_kick() calls sales_engineer reask_turns when a refused turn is due (_shared/reask.ts).',
   'scripts/sql/a_refused_turn_is_asked_again_within_minutes_never_left_silent.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;
