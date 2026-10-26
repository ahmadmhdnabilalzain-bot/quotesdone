-- EVERY QUEUED ACTION HAS AN AUTHOR, AND SELF-APPROVAL FAILS CLOSED (org audit E12).
--
-- MEASURED. action_execution had no author column; the author was a soft convention, request->>'actor',
-- present on 321 of 928 rows. fn_action_head_approve's independence check ("no approver may approve
-- their own authored work") was written "when the author is recorded" — so for ~65% of actions with no
-- recorded author it did nothing, and self-approval independence was silently skipped.
--
-- THIS FILE:
--   * adds action_execution.author, filled at insert by a BEFORE trigger from request->>'actor' /
--     'requested_by' / 'author', and backfills the existing rows.
--   * makes fn_action_head_approve FAIL CLOSED: an action with no recorded author cannot be approved,
--     because its independence cannot be verified; and an author who resolves to the approver is
--     refused (self-approval) as before, now reading the column.
--
-- No production or frozen gate calls fn_action_head_approve (only the org_connectivity harnesses do),
-- so failing closed on an authorless action reddens nothing but a probe that omits an actor.
--
--   node scripts/apply_sql.mjs scripts/sql/every_queued_action_has_an_author.sql --apply --ddl

begin;

alter table public.action_execution add column if not exists author text;

create or replace function public.fn_action_execution_set_author()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
begin
  if new.author is null then
    new.author := coalesce(new.request->>'actor', new.request->>'requested_by', new.request->>'author');
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_action_execution_set_author() from public;

drop trigger if exists t10_action_execution_set_author on public.action_execution;
create trigger t10_action_execution_set_author
  before insert on public.action_execution
  for each row execute function public.fn_action_execution_set_author();

-- backfill the soft author onto the column for the rows that carry one
update public.action_execution
   set author = coalesce(request->>'actor', request->>'requested_by', request->>'author')
 where author is null
   and coalesce(request->>'actor', request->>'requested_by', request->>'author') is not null;

-- ROUTINE REMOVED 7 September 2026. public.fn_action_head_approve was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


commit;
