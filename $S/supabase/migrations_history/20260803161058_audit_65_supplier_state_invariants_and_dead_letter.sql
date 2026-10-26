-- AUDIT 6.5 — "no permanent dead queue": three supplier states with no shipped exit, a queue with
-- no reader, and a terminal notification status.
--
-- LIVE STATE FIRST, because it decides the whole approach: leads = 20,464 rows, EVERY ONE with
-- approval_status NULL. Zero action_required, zero open exception windows, zero held notifications.
-- Not one supplier has been through the approval flow yet. So all six defects are LATENT, there is
-- nothing to drain, and hard invariants can be added with no legacy rows to violate them. That will
-- not be true once onboarding starts, which is the argument for doing it now rather than later.
--
-- (a) action_required + exception_due_at NULL — both sweep loops require exception_due_at is not
--     null, so such a supplier is never reminded and never closed. Reachable because supplier_api
--     commits the status BEFORE the try/catch that opens the window, and the migration that added
--     the columns had no backfill.
-- (b) approved/verified WITH an open window — the window is opened regardless of the approval
--     guard. Every sweep loop and both views filter approval_status='action_required', so it is
--     invisible; and fn_supplier_exception_open then reports 'already open' forever, so a later
--     demotion inherits a months-old due date and is auto-rejected IMMEDIATELY with zero reminders.
-- (c) the same for verified=true with pending/NULL status.
-- (e) notifications.status='held' is terminal — send_outbox sets it when supplier mail is disabled
--     and never selects it again, so re-enabling supplier mail does not release anything.
--
-- The fix for (a)(b)(c) is not another sweep. It is to make the states unrepresentable, in the
-- database, so no caller's statement ordering can produce them.

-- =============================================================================================
-- 1. The invariant: an exception window is open IF AND ONLY IF the supplier is action_required.
-- =============================================================================================
create or replace function public.fn_leads_exception_invariant()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_days   int := public.fn_supplier_exception_days();
  v_now    timestamptz := now();
  v_needs  boolean;
  v_isopen boolean;
begin
  v_needs  := coalesce(new.approval_status, '') = 'action_required';
  v_isopen := new.exception_opened_at is not null and new.exception_closed_at is null;

  if v_needs and not v_isopen then
    -- (a) OPEN IT HERE. supplier_api commits the status first and opens the window afterwards
    -- inside a try/catch that swallows failures; if that RPC never lands, the supplier is stranded
    -- in a state no sweep can see. Opening it in the same statement that sets the status removes
    -- the ordering problem entirely, whatever the caller does.
    new.exception_opened_at        := v_now;
    new.exception_due_at           := v_now + make_interval(days => v_days);
    new.exception_reminders        := 0;
    new.exception_last_reminder_at := null;
    new.exception_closed_at        := null;
    new.exception_outcome          := null;

  elsif v_needs and v_isopen and new.exception_due_at is null then
    -- Open but with no deadline: same invisibility, different route in.
    new.exception_due_at := v_now + make_interval(days => v_days);

  elsif (not v_needs) and v_isopen then
    -- (b)(c) CLOSE IT HERE. An approved or verified supplier must not carry an open window: it is
    -- invisible to every sweep, and it poisons the NEXT demotion with a stale due date.
    new.exception_closed_at := v_now;
    new.exception_outcome   := case
      when coalesce(new.approval_status,'') in ('approved','verified') or new.verified is true then 'resolved'
      when coalesce(new.approval_status,'') = 'rejected' then coalesce(new.exception_outcome, 'closed_rejected')
      else 'closed_status_change' end;
    if new.exception_outcome = 'resolved' then new.licence_gate_reason := null; end if;
  end if;

  -- Backstop. If the branches above ever stop covering a case, fail loudly here rather than
  -- writing a row that no queue can see. A CHECK constraint cannot express this (it depends on
  -- two column groups at once) and would also have blocked the legacy rows this trigger repairs.
  if (coalesce(new.approval_status,'') = 'action_required')
     <> (new.exception_opened_at is not null and new.exception_closed_at is null) then
    raise exception
      'leads %: exception window and approval_status disagree (status=%, open=%). An open window '
      'must mean action_required and nothing else — otherwise the supplier is in a state no sweep '
      'and no view can see.', new.id, new.approval_status,
      (new.exception_opened_at is not null and new.exception_closed_at is null)
      using errcode = 'check_violation';
  end if;

  if coalesce(new.approval_status,'') = 'action_required' and new.exception_due_at is null then
    raise exception 'leads %: action_required with no exception_due_at — both sweep loops skip it.', new.id
      using errcode = 'check_violation';
  end if;

  return new;
end $fn$;
revoke all on function public.fn_leads_exception_invariant() from public, anon, authenticated;

drop trigger if exists trg_leads_exception_invariant on public.leads;
create trigger trg_leads_exception_invariant
  before insert or update of approval_status, verified, exception_opened_at, exception_closed_at,
                             exception_due_at
  on public.leads
  for each row execute function public.fn_leads_exception_invariant();

-- =============================================================================================
-- 2. One canonical answer to "may this supplier receive work?" (defect (f)'s missing predicate)
-- =============================================================================================
create or replace function public.fn_supplier_matchable(p_lead_id bigint)
returns boolean
language sql stable
security definer
set search_path = public, pg_temp
as $$
  -- submit_quote already forbids an action_required supplier from quoting. Matching did not know
  -- that, so such suppliers were still sent RFQs they were structurally unable to answer — the
  -- worst of both: the customer waits, the supplier is blamed for silence.
  select coalesce(l.approval_status, '') <> 'action_required'
     and coalesce(l.approval_status, '') <> 'rejected'
    from public.leads l where l.id = p_lead_id;
$$;
comment on function public.fn_supplier_matchable(bigint) is
  'Canonical matchability. match_suppliers_kw and match_suppliers must consult this rather than '
  'each carrying their own predicate; see v_supplier_match_exclusions for who it currently excludes.';

create or replace view public.v_supplier_match_exclusions as
select l.id, l.company_name, l.approval_status, l.licence_gate_reason,
       l.exception_due_at,
       greatest(0, extract(day from (l.exception_due_at - now()))::int) as days_remaining
  from public.leads l
 where coalesce(l.approval_status,'') in ('action_required','rejected');
comment on view public.v_supplier_match_exclusions is
  'Suppliers that must not be matched, and why. Empty today because no supplier has been through '
  'the approval flow; it is the reader that proves the exclusion is real once they have.';

-- =============================================================================================
-- 3. (e) A permanent dead queue that someone can actually read, and a way OUT of held.
-- =============================================================================================
create table if not exists public.dead_letter (
  id             bigserial primary key,
  source         text not null,             -- 'notifications', 'org_tasks', ...
  source_id      text,
  kind           text,
  reason         text not null,
  payload        jsonb,
  first_failed_at timestamptz not null default now(),
  attempts       int not null default 1,
  created_at     timestamptz not null default now(),
  resolved_at    timestamptz,
  resolved_by    text,
  resolution     text
);
create index if not exists dead_letter_open_idx on public.dead_letter (source, created_at desc) where resolved_at is null;
alter table public.dead_letter enable row level security;
revoke all on public.dead_letter from anon, authenticated;
comment on table public.dead_letter is
  'Terminally failed work, with somewhere to land and a reader. Audit 6.5: the failure was not that '
  'work failed, it was that failed work vanished into a status nothing ever selected again.';

create or replace view public.v_dead_letter_open as
select source, kind, reason, count(*) as items, min(first_failed_at) as oldest, max(created_at) as newest
  from public.dead_letter where resolved_at is null
 group by source, kind, reason order by count(*) desc;

-- Release: when supplier mail is re-enabled, held notifications must come back rather than sit
-- forever in a status send_outbox never selects.
create or replace function public.fn_notifications_release_held(p_max int default 500)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare v_released int;
begin
  with picked as (
    select id from public.notifications where status = 'held' order by id limit greatest(1, p_max)
  )
  update public.notifications n set status = 'queued'
    from picked p where n.id = p.id
  returning 1 into v_released;
  get diagnostics v_released = row_count;
  return jsonb_build_object('ok', true, 'released', v_released);
end $fn$;

-- Dead-letter: anything still held after p_days has been paused longer than it is worth sending.
create or replace function public.fn_notifications_dead_letter_held(p_days int default 30)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare v_moved int := 0;
begin
  with old as (
    select * from public.notifications
     where status = 'held' and created_at < now() - make_interval(days => greatest(1, p_days))
  ), ins as (
    insert into public.dead_letter (source, source_id, kind, reason, payload, first_failed_at)
    select 'notifications', o.id::text, o.type,
           'held longer than ' || p_days || ' days; supplier mail was disabled and never re-enabled',
           to_jsonb(o) - 'body', o.created_at
      from old o
    returning 1
  )
  update public.notifications n set status = 'dead'
    from old o where n.id = o.id;
  get diagnostics v_moved = row_count;
  return jsonb_build_object('ok', true, 'dead_lettered', v_moved);
end $fn$;

revoke all on function public.fn_notifications_release_held(int) from public, anon, authenticated;
revoke all on function public.fn_notifications_dead_letter_held(int) from public, anon, authenticated;

-- =============================================================================================
-- 4. (d) The queue gets a reader that states the answer, not just the rows.
-- =============================================================================================
create or replace view public.v_supplier_exception_board as
select
  l.id, l.company_name, l.approval_status, l.licence_gate_reason,
  l.exception_opened_at, l.exception_due_at, l.exception_reminders, l.exception_last_reminder_at,
  greatest(0, extract(day from (l.exception_due_at - now()))::int) as days_remaining,
  (l.exception_due_at <= now())                                    as overdue,
  case
    when l.exception_due_at <= now()                          then 'auto-reject is due'
    when extract(day from (l.exception_due_at - now())) <= 2   then 'final days'
    else 'in window' end                                           as urgency
  from public.leads l
 where coalesce(l.approval_status,'') = 'action_required'
   and l.exception_opened_at is not null and l.exception_closed_at is null
 order by l.exception_due_at;
comment on view public.v_supplier_exception_board is
  'The supplier exception queue in the words an operator needs. Audit 6.5(d): the previous views '
  'existed and were empty, but nothing read them, so the queue depth was visible to no one.';;
