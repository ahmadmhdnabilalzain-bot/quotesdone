-- THE FOUNDER MAIL POLICY KEEPS ITS HISTORY, SO A FOUNDER EMAIL IS JUDGED BY THE RULE IN FORCE WHEN IT WAS QUEUED.
--
-- Assigned: it_engineer. 22 Sep 2026. Review finding on #825.
--
-- MEASURED: public.founder_mail_policy (69 rows) holds one row per kind and no history. #825 taught
-- scripts/checks/the_founder_is_emailed_exceptions_only.test.mjs to exempt a founder-bound email queued
-- before its kind's updated_at, because twelve it_new_bug emails of 21 Sep (sent while the kind was allowed)
-- were being read against the 'false' set at 23:22:21 UTC that night by the_founder_hears_from_it_once_a_day.sql.
-- WRONG WITH THAT: updated_at is bumped by cosmetic edits too. The same file re-wrote the reason of four
-- emergency kinds and bumped their updated_at without changing allowed_to_email. So a reason or owner_role edit
-- to a DISALLOWED kind, made after a genuine violation, would move updated_at past the violation and the check
-- would stop seeing it. The exemption was keyed on the wrong event.
--
-- WHAT THIS CHANGES:
--   1. public.founder_mail_policy_history (kind, allowed_to_email, valid_from, changed_by, source, reason):
--      one row each time a kind's allowed_to_email is SET -- an insert, a real flip, or a delete (recorded as
--      false, because an unregistered kind is never emailed). RLS on, deny-all policy, revoked from anon and
--      authenticated: service-role only, like the policy table itself.
--   2. trg_founder_mail_policy_history, AFTER INSERT/UPDATE/DELETE on founder_mail_policy, writes it through
--      fn_founder_mail_policy_history_write(). An UPDATE writes a row ONLY when allowed_to_email is distinct
--      from its old value, so a reason / owner_role / updated_at edit leaves history untouched.
--   3. Backfill: every current kind gets its present value from its present updated_at (the latest moment
--      the value is known to hold); it_new_bug and it_engineer_handover also get the 'true' they held before
--      the 21 Sep 23:22:21 UTC flip (registered true by the_it_engineer_closes_every_loop_it_opens.sql and
--      the_it_engineer_hands_the_founder_a_session_he_can_start_from.sql), from -infinity because the exact
--      moment of registration was not recorded.
--   4. public.fn_founder_mail_policy_at(kind, at) -> the allowed_to_email in force at that moment: the latest
--      history row with valid_from <= at; NULL when the moment is before the kind's first history row (not
--      known, so not judged); FALSE for a kind that was never registered (the gate never emails one).
--      The check calls this, so the check and the probe judge by one definition.
--
-- WHAT THIS DOES NOT CHANGE: the gate a10_notifications_founder_mail_policy, fn_notify_founder,
-- fn_founder_mail_route, and every writer of founder_mail_policy -- they keep writing the policy row exactly
-- as before; the trigger records the history for them. No policy value changes.
-- KNOWN CEILING OF THE BACKFILL: for a kind whose updated_at was last bumped cosmetically, the moments between
-- its real last flip and that updated_at are before its first history row and are not judged. The check looks
-- back 24 hours, so that gap closes one day after apply; every change from the apply on is recorded exactly.
--
-- Probe: scripts/sql/the_founder_mail_policy_keeps_its_history_probe.sql (verdict row, all rolled back).

create table if not exists public.founder_mail_policy_history (
  id               bigserial primary key,
  kind             text        not null,
  allowed_to_email boolean     not null,
  valid_from       timestamptz not null,
  changed_by       text        not null default current_user,
  source           text        not null,
  reason           text,
  recorded_at      timestamptz not null default now()
);
create index if not exists founder_mail_policy_history_kind_valid_from
  on public.founder_mail_policy_history (kind, valid_from desc);

alter table public.founder_mail_policy_history enable row level security;
drop policy if exists founder_mail_policy_history_service_role_only on public.founder_mail_policy_history;
create policy founder_mail_policy_history_service_role_only on public.founder_mail_policy_history
  as permissive for all to public using (false) with check (false);
revoke all on public.founder_mail_policy_history from anon, authenticated;
revoke all on sequence public.founder_mail_policy_history_id_seq from anon, authenticated;

-- ------------------------------------------------------------------------------------------------------------
create or replace function public.fn_founder_mail_policy_history_write()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  -- valid_from is clock_timestamp(), not now(): several changes inside one transaction keep their order.
  -- ponytail: a flip is visible to other sessions at COMMIT, a few ms after valid_from; a founder email
  -- queued in that gap is judged by the new value. Upgrade path: track_commit_timestamp.
  if TG_OP = 'DELETE' then
    insert into public.founder_mail_policy_history (kind, allowed_to_email, valid_from, source, reason)
    values (OLD.kind, false, clock_timestamp(), 'delete (an unregistered kind is never emailed)', OLD.reason);
    return OLD;
  end if;
  if TG_OP = 'INSERT' or OLD.allowed_to_email is distinct from NEW.allowed_to_email
     or OLD.kind is distinct from NEW.kind then
    insert into public.founder_mail_policy_history (kind, allowed_to_email, valid_from, source, reason)
    values (NEW.kind, NEW.allowed_to_email, clock_timestamp(), lower(TG_OP), NEW.reason);
  end if;
  return NEW;
end $function$;
revoke execute on function public.fn_founder_mail_policy_history_write() from public, anon, authenticated;

drop trigger if exists trg_founder_mail_policy_history on public.founder_mail_policy;
create trigger trg_founder_mail_policy_history
  after insert or update or delete on public.founder_mail_policy
  for each row execute function public.fn_founder_mail_policy_history_write();

-- ------------------------------------------------------------------------------------------------------------
create or replace function public.fn_founder_mail_policy_at(p_kind text, p_at timestamptz)
returns boolean
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select case
           when not exists (select 1 from public.founder_mail_policy_history h where h.kind = p_kind) then false
           else (select h.allowed_to_email from public.founder_mail_policy_history h
                  where h.kind = p_kind and h.valid_from <= p_at
                  order by h.valid_from desc, h.id desc limit 1)
         end
$function$;
revoke execute on function public.fn_founder_mail_policy_at(text, timestamptz) from public, anon, authenticated;

-- ------------------------------------------------------------------------------------------------------------
-- BACKFILL, idempotent: a kind that already has history is left alone.
insert into public.founder_mail_policy_history (kind, allowed_to_email, valid_from, changed_by, source, reason)
select p.kind, true, '-infinity'::timestamptz, 'backfill',
       'backfill: registered true (the_it_engineer_closes_every_loop_it_opens.sql / the_it_engineer_hands_the_founder_a_session_he_can_start_from.sql); registration moment not recorded',
       null
  from public.founder_mail_policy p
 where p.kind in ('it_new_bug', 'it_engineer_handover')
   and not exists (select 1 from public.founder_mail_policy_history h where h.kind = p.kind);

insert into public.founder_mail_policy_history (kind, allowed_to_email, valid_from, changed_by, source, reason)
select p.kind, p.allowed_to_email, p.updated_at, 'backfill',
       case when p.kind in ('it_new_bug', 'it_engineer_handover')
            then 'backfill: set false by the_founder_hears_from_it_once_a_day.sql (instruction 642) at its updated_at'
            else 'backfill: current value, known to hold from its updated_at' end,
       p.reason
  from public.founder_mail_policy p
 where not exists (select 1 from public.founder_mail_policy_history h
                    where h.kind = p.kind and h.valid_from > '-infinity'::timestamptz);
