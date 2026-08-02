-- PHASE 1.3 - supplier exception handling with a real deadline.
--
-- Context. On 2 Aug the founder chose fully automatic supplier approval: no human queue. A supplier
-- whose licence cannot be read goes to approval_status='action_required' with licence_gate_reason
-- naming the problem, and self-serves by re-uploading. That closed the "queue nobody works" problem
-- but opened a quieter one: an account can sit in action_required forever. It is neither approved
-- nor refused, it occupies a company name and an email, and nobody - supplier or founder - can tell
-- whether it is alive. A state with no exit is not automation; it is a queue with the label removed.
--
-- So: a 14-day window, reminders inside it, automatic rejection at the end, and the depth of the
-- window visible. Re-uploading a readable licence at any point re-runs the existing gate in
-- supplier_api and clears everything below. Nothing here approves anybody.

alter table public.leads
  add column if not exists exception_opened_at   timestamptz,
  add column if not exists exception_due_at      timestamptz,
  add column if not exists exception_reminders   integer not null default 0,
  add column if not exists exception_last_reminder_at timestamptz,
  add column if not exists exception_closed_at   timestamptz,
  add column if not exists exception_outcome     text;

comment on column public.leads.exception_due_at is
  'When an action_required registration is automatically rejected if the supplier has not supplied a readable, in-date trade licence. 14 days from the moment the exception opened. Re-uploading a valid licence clears this by way of the normal approval path in supplier_api.';

create index if not exists leads_exception_due_idx
  on public.leads (exception_due_at) where exception_closed_at is null;

-- How long the supplier gets. In app_secrets so it can be changed without a deploy, and read
-- through this function so nothing hardcodes 14 in two places.
insert into app_secrets (key, value) values ('supplier_exception_days','14')
on conflict (key) do update set value = excluded.value;

create or replace function public.fn_supplier_exception_days()
returns integer language sql stable as $$
  select greatest(1, coalesce((select nullif(btrim(value),'')::int from app_secrets where key='supplier_exception_days'), 14));
$$;

-- OPEN. Called when supplier_api sets action_required. Idempotent: re-opening an already-open
-- exception does not restart the clock, because that would let a supplier extend their own deadline
-- indefinitely by re-saving a still-unreadable licence.
create or replace function public.fn_supplier_exception_open(p_lead_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_days int := public.fn_supplier_exception_days(); r public.leads;
begin
  select * into r from public.leads where id = p_lead_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'lead_not_found'); end if;

  if r.exception_opened_at is not null and r.exception_closed_at is null then
    return jsonb_build_object('ok', true, 'reopened', false, 'due_at', r.exception_due_at,
                              'note', 'already open - the clock does not restart on a repeat failure');
  end if;

  update public.leads
     set exception_opened_at = now(),
         exception_due_at = now() + make_interval(days => v_days),
         exception_reminders = 0, exception_last_reminder_at = null,
         exception_closed_at = null, exception_outcome = null,
         licence_gate_reason = coalesce(p_reason, licence_gate_reason)
   where id = p_lead_id;

  return jsonb_build_object('ok', true, 'reopened', true,
                            'due_at', now() + make_interval(days => v_days), 'days', v_days);
end $$;

-- CLOSE. Called on approval, or by the expiry sweep, or if the supplier withdraws.
create or replace function public.fn_supplier_exception_close(p_lead_id bigint, p_outcome text)
returns void language sql security definer set search_path = public as $$
  update public.leads
     set exception_closed_at = now(),
         exception_outcome = p_outcome,
         licence_gate_reason = case when p_outcome = 'resolved' then null else licence_gate_reason end
   where id = p_lead_id and exception_closed_at is null;
$$;

-- THE SWEEP. Reminders at day 3, 7 and 12; automatic rejection the moment the window closes.
-- Deliberately does NOT delete anything: the row becomes approval_status='rejected' with a reason
-- and a closed exception, so the supplier can still be found, appealed and re-opened by a human if
-- one ever looks. Automatic rejection is a decision, not an erasure.
create or replace function public.fn_supplier_exception_sweep()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_reminded int := 0; v_rejected int := 0; r record; v_days int := public.fn_supplier_exception_days();
begin
  -- reminders
  for r in
    select l.id, l.company_name, l.claimed_by, l.exception_due_at, l.exception_reminders, l.licence_gate_reason
    from public.leads l
    where l.approval_status = 'action_required'
      and l.exception_closed_at is null
      and l.exception_due_at is not null
      and l.exception_due_at > now()
      and l.claimed_by is not null
      and (l.exception_last_reminder_at is null or l.exception_last_reminder_at < now() - interval '48 hours')
      and (
        (l.exception_reminders = 0 and now() >= l.exception_opened_at + interval '3 days') or
        (l.exception_reminders = 1 and now() >= l.exception_opened_at + interval '7 days') or
        (l.exception_reminders = 2 and now() >= l.exception_opened_at + interval '12 days')
      )
  loop
    insert into public.notifications (type, to_email, to_role, lead_id, subject, body, channel, status)
    values ('supplier_exception_reminder', r.claimed_by, 'supplier', r.id,
            'Action needed to activate your QuotesDone account',
            'Your registration for ' || coalesce(r.company_name,'your company') ||
            ' is not active yet: ' || coalesce(r.licence_gate_reason, 'we could not read a valid, in-date trade licence') ||
            E'.\n\nUpload a clear copy of your current trade licence in your supplier portal and your account activates automatically - there is no approval queue.' ||
            E'\n\nIf we do not receive one by ' || to_char(r.exception_due_at, 'DD Mon YYYY') ||
            ', this registration will be closed automatically. You can register again at any time.',
            'email', 'queued');
    update public.leads
       set exception_reminders = exception_reminders + 1, exception_last_reminder_at = now()
     where id = r.id;
    v_reminded := v_reminded + 1;
  end loop;

  -- expiry -> automatic rejection
  for r in
    select l.id, l.company_name, l.claimed_by, l.licence_gate_reason
    from public.leads l
    where l.approval_status = 'action_required'
      and l.exception_closed_at is null
      and l.exception_due_at is not null
      and l.exception_due_at <= now()
  loop
    update public.leads
       set approval_status = 'rejected',
           rejection_reason = 'Automatically closed after ' || v_days ||
                              ' days without a readable, in-date trade licence (' ||
                              coalesce(r.licence_gate_reason,'licence unreadable') || ')',
           exception_closed_at = now(), exception_outcome = 'expired_auto_rejected'
     where id = r.id;

    if r.claimed_by is not null then
      insert into public.notifications (type, to_email, to_role, lead_id, subject, body, channel, status)
      values ('supplier_exception_expired', r.claimed_by, 'supplier', r.id,
              'Your QuotesDone registration has been closed',
              'We could not activate ' || coalesce(r.company_name,'your registration') || ' because ' ||
              coalesce(r.licence_gate_reason,'we could not read a valid, in-date trade licence') ||
              ', and ' || v_days || ' days have passed.' ||
              E'\n\nNothing is lost - you can register again whenever you have a clear copy of your current trade licence, and activation is immediate once we can read it.' ||
              E'\n\nIf you believe this is a mistake, reply to this email.',
              'email', 'queued');
    end if;

    -- telemetry, not a ticket. The auto-rejection rate is the cost of the fully-automatic policy
    -- and the founder asked for it to stay measurable.
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('onboarding', 'supplier_exception_expired', 'logged', 'medium',
            'Registration auto-closed after ' || v_days || ' days - ' || coalesce(r.company_name, 'supplier #' || r.id),
            'No action required. Recorded so the auto-rejection rate stays visible; if genuine businesses appear here, the fully-automatic policy needs revisiting.',
            jsonb_build_object('lead_id', r.id, 'reason', r.licence_gate_reason, 'days', v_days),
            'leads', r.id::text);
    v_rejected := v_rejected + 1;
  end loop;

  return jsonb_build_object('reminded', v_reminded, 'auto_rejected', v_rejected, 'window_days', v_days);
end $$;

-- QUEUE DEPTH, visible. Not a work queue - nobody is meant to action these - but the depth and the
-- age distribution are the honest measure of how well fully-automatic onboarding is working.
create or replace view public.v_supplier_exception_queue as
select l.id, l.company_name, l.claimed_by as supplier_email, l.emirate,
       l.licence_gate_reason as reason,
       l.exception_opened_at, l.exception_due_at,
       greatest(0, extract(day from (l.exception_due_at - now()))::int) as days_remaining,
       l.exception_reminders as reminders_sent,
       case when l.exception_due_at <= now() then 'overdue'
            when l.exception_due_at <= now() + interval '3 days' then 'closing_soon'
            else 'open' end as urgency
from public.leads l
where l.approval_status = 'action_required' and l.exception_closed_at is null
order by l.exception_due_at nulls first;

create or replace view public.v_supplier_exception_health as
select (select count(*) from public.v_supplier_exception_queue) as open_now,
       (select count(*) from public.v_supplier_exception_queue where urgency='overdue') as overdue,
       (select count(*) from public.v_supplier_exception_queue where urgency='closing_soon') as closing_within_3_days,
       (select count(*) from public.leads where exception_outcome='expired_auto_rejected') as auto_rejected_total,
       (select count(*) from public.leads where exception_outcome='resolved') as self_resolved_total,
       (select count(*) from public.leads where registration_submitted_at is not null) as registrations_total,
       (select public.fn_supplier_exception_days()) as window_days;

comment on view public.v_supplier_exception_health is
  'Command Center tile. self_resolved vs auto_rejected is the number that decides whether fully-automatic supplier approval is working. If auto_rejected climbs against real registrations, the policy is refusing genuine businesses and needs revisiting.';

revoke all on function public.fn_supplier_exception_open(bigint,text) from public, anon, authenticated;
revoke all on function public.fn_supplier_exception_close(bigint,text) from public, anon, authenticated;
revoke all on function public.fn_supplier_exception_sweep() from public, anon, authenticated;
grant execute on function public.fn_supplier_exception_open(bigint,text) to service_role;
grant execute on function public.fn_supplier_exception_close(bigint,text) to service_role;
grant execute on function public.fn_supplier_exception_sweep() to service_role;
