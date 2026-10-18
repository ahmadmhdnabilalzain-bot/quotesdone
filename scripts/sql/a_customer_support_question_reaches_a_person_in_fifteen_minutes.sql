-- A CUSTOMER_SUPPORT QUESTION REACHES A PERSON IN FIFTEEN MINUTES, AND IS FLAGGED WHEN IT IS NOT ANSWERED IN FOUR HOURS.
-- Seat: customer_support. 19 Oct 2026.
--
-- MEASURED BEFORE THIS FILE (production, 19 Oct 2026):
--   * 703 agent_actions of kind held_question / held_question_expired, every one 'pending'; not one was ever decided.
--     fn_reason_held_escalate and fn_reason_held_expire FILE them, and no routine, cron job or edge function reads them.
--   * customer_support: 28 pending (16 anonymous site-widget turns 30 Sep-2 Oct, 12 internal seat duties, 2 of whose
--     questions were already applied) and 54 held questions not applied/closed/answered.
--   * fn_reason_held_escalate selects only 'held' and 'failed' rows, so a row the sweep marks 'expired' (a visitor
--     chat past its hour) is never escalated: 26 site-widget rows since 6 Oct reached no queue at all.
--   * none of the 54 carries a contact (no email, phone, customer, lead or conversation in its request): no person
--     could have been reached. 5 carry the ZZ DEMO marker.
--
-- WHAT THIS ADDS: fn_cs_held_question_route(), every 5 minutes. For every customer_support held question not applied,
-- closed or answered, and every pending held_question* action on it:
--   1. its question was applied/answered by its own surface   -> the action is 'done'.
--   2. a fixture (ZZ DEMO / example.invalid / qd_run)          -> tagged result.demo_purge (ruling 1199, the #1348 list);
--                                                                 action 'dismissed'. Nothing is deleted.
--   3. an internal seat duty (audience internal, or a customer_support.* surface) older than 7 days -> 'dismissed':
--      the duty re-files itself on its next run, so the old copy waits for nothing.
--   4. a visitor with no contact on the request                -> 'dismissed', reason named: no route to the person.
--   5. ANYONE ELSE (a reachable customer or supplier)         -> customer_support's for 15 minutes, then handed to the
--      CEO seat (agent_actions agent 'ceo', kind support_question_handover), once; still unanswered 4 hours later -> a
--      second, high-risk overdue item for the CEO, once. Never the founder: rulings 1254 and 8 Sep keep his WhatsApp for
--      a person who explicitly asks for one, which the WhatsApp "Talk to a person" menu already routes.
-- It never sends anything to the customer or supplier: a reply needs a person.
--
-- THE FIXTURES FOR THE #1348 PURGE (ruling 1199), by exact key, measured 19 Oct 2026. Tagged result.demo_purge here,
-- deleted by nothing here; it_engineer adds them to fn_demo_purge_run's scope:
--   public.reasoning_held_question id 23995, 24298, 24299, 24356, 24357
--   plus any later row with result ->> 'demo_purge' = 'founder ruling 1199: the #1348 purge list'.
--
-- Prevented by: scripts/sql/a_customer_support_question_reaches_a_person_in_fifteen_minutes_probe.sql (verdict probe,
-- aborted transaction: a reachable question is handed over, an anonymous one is not, a fixture is tagged not deleted).

create or replace function public.fn_cs_held_question_route()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  r record;
  v_out text;
  n jsonb := '{}'::jsonb;
  v_fx constant text := 'ZZ DEMO|@example\.invalid|qd_run';
  v_contact constant text[] := array['email', 'phone', 'phone_e164', 'wa_from', 'customer_id', 'lead_id', 'supplier_id',
                                     'conversation_id', 'inquiry_id'];
begin
  if not pg_try_advisory_xact_lock(hashtext('fn_cs_held_question_route')) then
    return jsonb_build_object('skipped', 'another run is going');
  end if;

  for r in
    select h.*,
           coalesce(h.request -> 'context' ->> 'audience', '') audience,
           (h.request -> 'context') ?| v_contact or h.subject ?| v_contact or h.surface like 'wa_inbound.%' reachable,
           (h.question ~* v_fx or h.request::text ~* v_fx or h.subject::text ~* v_fx) fixture
      from public.reasoning_held_question h
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

    if v_out in ('handed_to_ceo', 'overdue_alerted') then
      -- no personal data in the item: the id and the surface; the CEO opens the held question for the rest
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
             when v_out = 'handed_to_ceo' then 'handed to the ceo seat at ' || now()
             else 'overdue: unanswered 4 hours after it was handed to the ceo seat' end
     where a.target_table = 'reasoning_held_question' and a.target_id = r.id::text
       and a.kind like 'held_question%' and a.status = 'pending';

    n := n || jsonb_build_object(v_out, coalesce((n ->> v_out)::int, 0) + 1);
  end loop;
  return n;
end $fn$;
revoke execute on function public.fn_cs_held_question_route() from public, anon, authenticated;
grant execute on function public.fn_cs_held_question_route() to service_role;

select cron.schedule('cs_held_question_route', '*/5 * * * *', $CRON$select public.fn_cs_held_question_route()$CRON$);
insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('cs_held_question_route', 'customer_support held questions reach a person', 'Support',
   'Every 5 minutes. A customer_support question the model could not answer is handed to the CEO seat within 15 minutes '
   || 'when the person who asked can be reached, flagged again if unanswered after 4 hours; fixtures are tagged for the '
   || 'ruling 1199 purge, anonymous widget turns and stale internal duties are closed with their reason.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
