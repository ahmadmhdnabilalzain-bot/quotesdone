-- EVERY ORG TASK KIND HAS A HANDLER, AND A DECISION GOES TO THE SEAT THAT OWNS IT.
-- Seat: ceo (the organisation's queue; the CEO owns the handler register). The sales_engineer and customer_support
-- parts are their own rows of the register. 10 Nov 2026, founder ruling 1574.
--
-- MEASURED BEFORE WRITING (production htdblwldjkcgjvmqkbeh, read-only, 10 Nov 2026):
--   public.org_tasks holds 8 'assigned' rows. fn_org_task_consume_tick (v3) finishes knowledge_gap and four kinds of
--   routine_operational_decision (expense_logged, rfq_no_supplier, supplier_registered, sales_rating). Six rows are
--   routine_operational_decision of a founder_mail kind it has no branch for, so each tick answers "no handler is
--   mapped for action_class routine_operational_decision on seat <s>" and backs off:
--     579392, 579393  ceo              supplier_invite_seed   47 days, 71 attempts  a copy of the outgoing invitation ("x")
--     579436          ceo              wa_templates_ready     43 days, 65 attempts  a notice: "No action needed"
--     581515          ceo              invite_m365_seed       14 days, 23 attempts  a copy of the outgoing M365 invitation
--     582156          sales_engineer   invite_paused_bounce    8 days, 16 attempts  invites were auto-paused (2 Nov)
--     582174          customer_support business_health_at_risk 4 days,  9 attempts  "CEO: the AED 1M revenue forecast needs
--                                                                                    your decision (week of 2026-11-02)" - the
--                                                                                    CEO's own weekly paper, MISROUTED
--   invite_enabled reads 'true' today; the CEO's paper names the week of 2 Nov, which ended 9 Nov.
--   The other two are knowledge_gap rows (580964, 581232) waiting on the sales engineer's reasoning: the consumer's.
--
-- WHAT THIS FILE DOES:
--   1. public.org_task_kind_handler: one row per (action_class, founder_mail kind) naming its OWNER seat, its handler
--      and its rule. 'consumer' rows say fn_org_task_consume_tick finishes them; 'information' closes a notice or a copy
--      of our own outgoing mail with nothing to decide; 'condition' closes when its condition is measured gone and
--      otherwise records the reading; '*' as the kind covers the whole class.
--   2. Trigger a06_org_task_goes_to_its_kinds_owner (after a05 fills ownership): a new task of a registered kind is
--      assigned to the kind's owner seat, and the move is recorded on the task. A misroute cannot recur.
--   3. fn_org_task_kind_handlers_tick() (duty ceo.org_task_handlers, hourly): moves an existing misrouted task to its
--      owner, closes 'information' and cleared 'condition' tasks through fn_org_task_close_as_fact with the reading in
--      words, records the reading on a task still open, and raises ONE finding listing any assigned task whose kind has
--      no register row (a new kind is a deliberate act, never a silent default).
--   Guardrail: a task with a customer or a supplier waiting is never closed here (an rfq / inquiry / quote / lead id
--   on the task keeps it with the consumer); nothing is sent; no money moves.
--
-- Prevented by: scripts/checks/every_org_task_kind_has_a_handler.test.mjs (static rules plus a rolled-back replay:
-- the six rows above are handled, the misrouted one reaches the CEO, an unregistered kind raises its finding).
--   node scripts/apply_sql.mjs scripts/sql/every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql --apply --ddl --seat ceo

create table if not exists public.org_task_kind_handler (
  action_class text not null check (btrim(action_class) <> ''),
  mail_kind text not null check (mail_kind = '*' or mail_kind ~ '^[a-z0-9_]+$'),
  owner_seat text not null references public.org_role(role_id),
  handler text not null check (handler in ('consumer', 'information', 'condition')),
  rule text not null check (length(btrim(rule)) >= 20),
  owner_file text not null check (owner_file ~ '^scripts/sql/[a-z0-9_]+\.sql$'),
  recorded_at timestamptz not null default now(),
  primary key (action_class, mail_kind)
);
alter table public.org_task_kind_handler enable row level security;
drop policy if exists org_task_kind_handler_service_role_only on public.org_task_kind_handler;
create policy org_task_kind_handler_service_role_only on public.org_task_kind_handler
  as permissive for all to public using (false) with check (false);
revoke all on public.org_task_kind_handler from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('org_task_kind_handler', true, 'company', 'which seat owns each org_task kind and which handler finishes it (ruling 1574)', 'ceo')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason;

insert into public.org_task_kind_handler (action_class, mail_kind, owner_seat, handler, rule, owner_file) values
  ('knowledge_gap', '*', 'customer_support', 'consumer',
   'fn_org_task_consume_tick answers it from the price guidance, the approved FAQ or the corpus the reasoning chose; the asking seat keeps it',
   'scripts/sql/every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql'),
  ('routine_operational_decision', 'expense_logged', 'accountant', 'consumer',
   'fn_org_task_consume_tick closes it on the exact expense_entries row (vendor, amount, currency and date)',
   'scripts/sql/every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql'),
  ('routine_operational_decision', 'rfq_no_supplier', 'ceo', 'consumer',
   'fn_org_task_consume_tick closes it when the inquiry is gone or has matches; a live unmatched inquiry stays with the CEO',
   'scripts/sql/every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql'),
  ('routine_operational_decision', 'supplier_registered', 'sales_engineer', 'consumer',
   'fn_org_task_consume_tick confirms the announcement against public.leads; a pending approval stays the seat''s decision',
   'scripts/sql/every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql'),
  ('routine_operational_decision', 'sales_rating', 'sales_engineer', 'consumer',
   'fn_org_task_consume_tick decides a 3-5 rating changes nothing; a 1-2 rating stays the sales engineer''s standing judgement',
   'scripts/sql/every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql'),
  ('routine_operational_decision', 'supplier_invite_seed', 'ceo', 'information',
   'a copy of the company''s own outgoing supplier invitation routed here because the kind is not a founder mail kind: nothing to decide',
   'scripts/sql/every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql'),
  ('routine_operational_decision', 'invite_m365_seed', 'ceo', 'information',
   'a copy of the outgoing supplier invitation sent from the M365 mailbox: nothing to decide',
   'scripts/sql/every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql'),
  ('routine_operational_decision', 'wa_templates_ready', 'ceo', 'information',
   'a notice that the WhatsApp templates were approved by Meta, which says itself that no action is needed',
   'scripts/sql/every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql'),
  ('routine_operational_decision', 'invite_paused_bounce', 'sales_engineer', 'condition',
   'closes when invites run again (invite_enabled is true) and the 3-day bounce rate is within invite_max_bounce_rate; else the sales engineer repairs the list',
   'scripts/sql/every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql'),
  ('routine_operational_decision', 'business_health_at_risk', 'ceo', 'condition',
   'the CEO''s own weekly forecast paper: it belongs to the CEO, and it closes when the week it covers has ended (the next week''s paper carries the reading)',
   'scripts/sql/every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql')
on conflict (action_class, mail_kind) do update set owner_seat = excluded.owner_seat, handler = excluded.handler,
  rule = excluded.rule, owner_file = excluded.owner_file;

-- the kind a task carries: the founder_mail tag at the head of its detail, or the router's own record of it
create or replace function public.fn_org_task_mail_kind(p_detail text, p_result jsonb)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(nullif(p_result->'founder_mail'->>'kind', ''), substring(coalesce(p_detail, '') from '^\[founder_mail:([a-z0-9_]+)\]'),
                  case when coalesce(p_result, '{}'::jsonb) ? 'sales_rating' then 'sales_rating' end)
$fn$;
revoke execute on function public.fn_org_task_mail_kind(text, jsonb) from public, anon, authenticated;

create or replace function public.fn_org_task_goes_to_its_kinds_owner()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare k public.org_task_kind_handler;
begin
  select * into k from public.org_task_kind_handler x
   where x.action_class = new.action_class
     and x.mail_kind in (coalesce(public.fn_org_task_mail_kind(new.detail, new.result), '*'), '*')
   order by (x.mail_kind = '*') limit 1;
  if found and k.handler <> 'consumer' and new.assigned_agent is distinct from k.owner_seat then
    new.result := coalesce(new.result, '{}'::jsonb) || jsonb_build_object('routed_to_owner', jsonb_build_object(
      'from', new.assigned_agent, 'to', k.owner_seat, 'rule', k.rule, 'at', now()));
    new.assigned_agent := k.owner_seat;
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_org_task_goes_to_its_kinds_owner() from public, anon, authenticated;
drop trigger if exists a06_org_task_goes_to_its_kinds_owner on public.org_tasks;
create trigger a06_org_task_goes_to_its_kinds_owner before insert on public.org_tasks
  for each row execute function public.fn_org_task_goes_to_its_kinds_owner();

create or replace function public.fn_org_task_kind_handlers_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r record; k public.org_task_kind_handler; v_kind text; v_deliv text; v_reading jsonb; v_close jsonb; v_week date;
  v_sent int; v_bounced int; v_max numeric; v_rate numeric; v_items jsonb := '[]'::jsonb;
  n_moved int := 0; n_closed int := 0; n_open int := 0; n_unregistered int := 0; v_out jsonb := '[]'::jsonb;
  v_local date := (now() at time zone 'Asia/Dubai')::date;
begin
  for r in select o.* from public.org_tasks o where o.status = 'assigned' order by o.id for update of o skip locked loop
    v_kind := public.fn_org_task_mail_kind(r.detail, r.result);
    select * into k from public.org_task_kind_handler x
     where x.action_class = r.action_class and x.mail_kind in (coalesce(v_kind, '*'), '*')
     order by (x.mail_kind = '*') limit 1;
    if not found then
      n_unregistered := n_unregistered + 1;
      v_items := v_items || jsonb_build_object('item', coalesce(r.action_class, 'none') || ':' || coalesce(v_kind, 'none'),
        'owner_seat', 'ceo', 'subject', 'org_tasks', 'blast', 'agent_facing', 'affected', 1, 'config', true,
        'title', 'org_task ' || r.id || ' is of a kind no seat is registered to handle (' || coalesce(r.action_class, 'no class')
                 || coalesce(', ' || v_kind, '') || '); the CEO registers its owner and handler',
        'evidence', jsonb_build_object('task_id', r.id, 'assigned_agent', r.assigned_agent, 'title', left(r.title, 200)));
      continue;
    end if;
    if k.handler = 'consumer' then continue; end if;          -- fn_org_task_consume_tick finishes these

    -- the owner first: a decision sits with the seat that owns it
    if r.assigned_agent is distinct from k.owner_seat then
      update public.org_tasks
         set assigned_agent = k.owner_seat, updated_at = now(),
             result = coalesce(result, '{}'::jsonb) || jsonb_build_object('routed_to_owner', jsonb_build_object(
               'from', r.assigned_agent, 'to', k.owner_seat, 'rule', k.rule, 'at', now()))
       where id = r.id;
      n_moved := n_moved + 1;
      v_out := v_out || jsonb_build_object('task_id', r.id, 'moved', jsonb_build_object('from', r.assigned_agent, 'to', k.owner_seat));
    end if;

    -- the guardrail: a person waiting on this task keeps it open, with the consumer
    if coalesce(r.detail, '') ~* '(inquiry|quote|rfq|lead)[ _]?(id)?: ?[0-9a-f-]{6,}' then
      n_open := n_open + 1; continue;
    end if;

    v_deliv := null; v_reading := jsonb_build_object('kind', v_kind, 'handler', k.handler, 'owner_seat', k.owner_seat);
    if k.handler = 'information' then
      v_deliv := 'INFORMATION, NO DECISION. ' || k.rule || '. The task was ' || coalesce(nullif(btrim(r.title), ''), '(untitled)')
        || ', filed ' || to_char(r.created_at, 'YYYY-MM-DD') || ' and retried ' || coalesce(r.attempts, 0)
        || ' times by a consumer with no branch for it. The ' || k.owner_seat || ' seat closes it on the register''s rule '
        || '(public.org_task_kind_handler), so nothing is left assigned that nobody can finish.';
    elsif v_kind = 'invite_paused_bounce' then
      select h.sent, h.bounced into v_sent, v_bounced from public.fn_invite_send_health(now() - interval '3 days') h;
      v_max := coalesce((select nullif(value, '')::numeric from public.app_secrets where key = 'invite_max_bounce_rate'), 0.08);
      v_rate := round(coalesce(v_bounced, 0)::numeric / greatest(coalesce(v_sent, 0), 1), 3);
      v_reading := v_reading || jsonb_build_object('invite_enabled', (select value from public.app_secrets where key = 'invite_enabled'),
                                                   'sent_3d', v_sent, 'bounced_3d', v_bounced, 'rate_3d', v_rate, 'max_rate', v_max);
      if (select value from public.app_secrets where key = 'invite_enabled') = 'true' and v_rate <= v_max then
        v_deliv := 'THE CONDITION IS GONE. Invites were auto-paused on ' || to_char(r.created_at, 'YYYY-MM-DD') || '. Today invite_enabled is true '
          || 'and the last 3 days bounced ' || coalesce(v_bounced, 0) || ' of ' || coalesce(v_sent, 0) || ' (' || (v_rate * 100) || '%), within the '
          || (v_max * 100) || '% limit, so the pause the task was raised for has ended.';
      end if;
    elsif v_kind = 'business_health_at_risk' then
      v_week := nullif(substring(coalesce(r.title, '') from 'week of (\d{4}-\d{2}-\d{2})'), '')::date;
      v_reading := v_reading || jsonb_build_object('week_of', v_week, 'today_dubai', v_local);
      if v_week is not null and v_week + 7 <= v_local then
        v_deliv := 'THE WEEK HAS ENDED. This is the CEO''s weekly forecast paper for the week of ' || v_week || ', filed in '
          || coalesce(r.assigned_agent, 'another') || ' seat''s queue by the founder-mail router. It is the CEO''s, and the week it '
          || 'covers ended on ' || (v_week + 6) || '; the CEO''s next weekly forecast reads the target again with the current figures. '
          || 'What only the founder can decide in it goes to him in the CEO''s own weekly paper, not from this queue.';
      end if;
    end if;

    if v_deliv is not null then
      update public.org_tasks
         set result = coalesce(result, '{}'::jsonb) || jsonb_build_object('change_made', jsonb_build_object(
               'what', 'the task''s kind was read against its registered handler and the condition it was raised for is resolved',
               'handler', 'fn_org_task_kind_handlers_tick', 'basis', v_reading, 'at', now()))
       where id = r.id;
      v_close := public.fn_org_task_close_as_fact(r.id, 'fn_org_task_kind_handlers_tick', v_deliv,
                   v_reading || jsonb_build_object('owner', k.owner_seat, 'handler', 'org_task_kind_handler'));
      if coalesce((v_close->>'ok')::boolean, false) then
        n_closed := n_closed + 1;
        v_out := v_out || jsonb_build_object('task_id', r.id, 'closed', true, 'kind', v_kind);
      else
        n_open := n_open + 1;
        v_out := v_out || jsonb_build_object('task_id', r.id, 'closed', false, 'refused', v_close->>'reason');
      end if;
    else
      update public.org_tasks
         set result = coalesce(result, '{}'::jsonb) || jsonb_build_object('kind_handler', jsonb_build_object(
               'at', now(), 'rule', k.rule, 'reading', v_reading, 'verdict', 'condition still holds')), updated_at = now()
       where id = r.id;
      n_open := n_open + 1;
      v_out := v_out || jsonb_build_object('task_id', r.id, 'closed', false, 'reading', v_reading);
    end if;
  end loop;
  return jsonb_build_object('moved_to_owner', n_moved, 'closed', n_closed, 'still_open', n_open, 'unregistered', n_unregistered,
                            'tasks', v_out, 'settled', public.fn_it_duty_settle('org_task_kind_unregistered', v_items));
end $fn$;
revoke execute on function public.fn_org_task_kind_handlers_tick() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.org_task_handlers', 'ceo', interval '1 hour', 'fn_org_task_kind_handlers_tick',
   'Every assigned org_task has a registered handler and sits with the seat that owns its kind: a misrouted task moves to its owner, a notice or a copy of our own mail closes as information, a condition closes when it is measured gone, and a kind nobody owns is one finding. Ruling 1574.',
   'scripts/sql/every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- ── VERDICT (read-only) ─────────────────────────────────────────────────────────────────────────────────────────
select case when problems is null then 'PROBE OK' else 'PROBE FAILED: ' || problems end as verdict from (
  select string_agg(p, '; ') problems from (
    select 'a routine is open or unpinned: ' || p.oid::regprocedure::text p from pg_proc p
     where p.oid in ('public.fn_org_task_kind_handlers_tick()'::regprocedure, 'public.fn_org_task_goes_to_its_kinds_owner()'::regprocedure,
                     'public.fn_org_task_mail_kind(text,jsonb)'::regprocedure)
       and (not coalesce(p.proconfig @> array['search_path=public, pg_temp'], false)
            or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
    union all select 'the register is readable by a client'
     where has_table_privilege('anon', 'public.org_task_kind_handler', 'select') or has_table_privilege('authenticated', 'public.org_task_kind_handler', 'select')
    union all select 'the register has no policy' where not exists (select 1 from pg_policy where polrelid = 'public.org_task_kind_handler'::regclass)
    union all select 'the routing trigger is missing' where not exists (select 1 from pg_trigger where tgname = 'a06_org_task_goes_to_its_kinds_owner')
    union all select 'the duty is not registered' where not exists (select 1 from public.seat_duty where duty = 'ceo.org_task_handlers' and enabled)
  ) z) y;
