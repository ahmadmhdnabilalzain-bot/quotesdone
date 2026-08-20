-- E36 - the approver column anybody could fill, under a row that said only the founder could
--
-- E34 replaced the literal `true` in `amendments_awaiting_founder_approval` with a computed ok, so
-- the freeze board finally went red over four unapproved amendments to frozen Phase C contracts.
-- The row I wrote reads:
--
--     4 of 4 await the founder (change requests named: PCCR-001, PCCR-002). Only he can clear this row.
--
-- THE LAST SENTENCE WAS FALSE, and the independent acceptance proved it in one statement inside an
-- aborted transaction:
--
--     select count(*) from fn_phase_c_freeze_drift() where not ok;                 -- 1
--     update public.phase_c_freeze_amendment
--        set approved_by = 'zz-r5-audit-not-the-founder', approved_at = now()
--      where approved_by is null;                                                  -- ACCEPTED, 4 rows
--     select count(*) from fn_phase_c_freeze_drift() where not ok;                 -- 0
--
-- The whole freeze board went green, cleared by a string naming nobody. Behind the claim there was
-- nothing: `phase_c_freeze_amendment` carries approval_is_a_pair, the PCCR-nnn shape check, the
-- change-request foreign key, prior_digest <> new_digest, a 40-character evidence minimum, an
-- 80-character reason minimum and a uniqueness key -- and NOT ONE of them is about who the approver
-- is. `pg_trigger` showed no user trigger on the table. service_role holds UPDATE. And
-- `freeze_amendment_names_a_real_change_request.test.mjs` says in its own header that it
-- deliberately does not assert approval.
--
-- So I wrote a sentence into an evidence string and nothing enforced it. That is the defect this
-- whole session has been chasing -- a claim in prose with no mechanism -- committed by the file
-- whose entire purpose was to stop a board row asserting something it had not tested. The auditor
-- was right to score it as a builder defect distinct from the founder's outstanding signature.
--
-- THE MECHANISM. `public.phase_c_founder_identity` is the estate's register of who the founder is:
-- two ACTIVE email identities, plus one inactive `build_mode` row that is explicitly "Not a person"
-- and must never be accepted as an approval. A BEFORE trigger now refuses any approved_by that does
-- not resolve to an ACTIVE identity in that register. Nothing else about the table changes, and the
-- three arms the auditor found already sound -- an unregistered PCCR refused by the foreign key, an
-- empty ref refused by the shape check, approved_by without approved_at refused by the pair
-- constraint -- are untouched.
--
-- The board's own wording is corrected in the same file, so the row now says what is enforced
-- rather than what I hoped: it names the register, not a person, because the register is the thing
-- the database can actually check.
--
-- Named `a10_` because Postgres fires BEFORE triggers in NAME order and this estate has been caught
-- by that before. search_path is pinned on the function: a guard that reads a shadowed table is
-- not a guard, and a trigger runs with the writer's search_path unless it is set.

CREATE OR REPLACE FUNCTION public.fn_phase_c_freeze_amendment_approver_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- An amendment awaiting approval is the normal state and is not this trigger's business. The
  -- board reports it; refusing it here would make an unapproved amendment unrecordable.
  if new.approved_by is null then
    return new;
  end if;

  if not exists (
        select 1 from public.phase_c_founder_identity fi
         where fi.active
           and lower(btrim(fi.identity)) = lower(btrim(new.approved_by))) then
    raise exception 'phase_c_freeze_amendment: approved_by % does not resolve to an active identity in public.phase_c_founder_identity. An amendment to a FROZEN Phase C contract is approved by the founder or it is not approved; a free-text name here cleared four of them and turned the freeze board green in one statement. (pccr_approver_not_the_founder)',
      coalesce(nullif(btrim(new.approved_by),''), '(empty)')
      using errcode = '23514';
  end if;

  return new;
end
$function$;

-- CREATE OR REPLACE on a function that may not exist yet leaves a fresh ACL with EXECUTE to PUBLIC.
-- A trigger function is invoked by the trigger, never usefully by a caller, so the grant is removed
-- rather than left open.
REVOKE ALL ON FUNCTION public.fn_phase_c_freeze_amendment_approver_guard() FROM PUBLIC;

DROP TRIGGER IF EXISTS a10_freeze_amendment_approver_is_the_founder
  ON public.phase_c_freeze_amendment;
CREATE TRIGGER a10_freeze_amendment_approver_is_the_founder
  BEFORE INSERT OR UPDATE OF approved_by, approved_at ON public.phase_c_freeze_amendment
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_c_freeze_amendment_approver_guard();

-- ---- the board row stops claiming what it does not enforce ------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_c_freeze_drift()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with live as (
    select f.subject, f.object_identity, f.digest as frozen,
           case
             when f.object_kind = 'routine' then (
               select encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex')
                 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                where n.nspname='public'
                  and p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
                      = f.object_identity)
             when f.object_kind = 'table' and f.object_identity = 'public.phase_c_component' then (
               select encode(sha256(convert_to(string_agg(
                 c.component_id || '|' || coalesce(c.component_type,'') || '|' || coalesce(c.workflow_id,'')
                   || '|' || coalesce(c.step_id,'') || '|' || coalesce(c.accountable_role_id,'')
                   || '|' || coalesce(c.canonical_system_actor,'') || '|' || coalesce(c.authority_class,'')
                   || '|' || coalesce(c.trace_policy_id,'') || '|' || coalesce(c.activation_state,'')
                   || '|' || coalesce(c.classification,'') || '|' || coalesce(c.mutates_state::text,''),
                 chr(10) order by c.component_id),'UTF8')),'hex')
                 from public.phase_c_component c)
             else f.digest   -- repository_file subjects are checked in CI, not here; never silently green
           end as now_digest
      from public.phase_c_frozen_subject f
  ), judged as (
    -- D49. A live digest is undrifted when it matches the frozen baseline, OR when a recorded
    -- amendment carries BOTH the frozen baseline as its prior digest AND this body as its new one.
    -- An unrecorded edit is drift. An edit on top of an amendment is drift, because its prior digest
    -- no longer matches. Overwriting phase_c_frozen_subject.digest would have made both invisible.
    --
    -- E13 required the amendment to name a Phase C change request. E23 makes that reference a
    -- foreign key to public.phase_c_change_request, so an amendment can no longer point at a
    -- document nobody wrote.
    select l.*,
           exists (select 1 from public.phase_c_freeze_amendment a
                    where a.object_identity = l.object_identity
                      and a.prior_digest = l.frozen
                      and a.new_digest   = l.now_digest
                      and coalesce(btrim(a.change_request_ref),'') <> '') as amended
      from live l
  )
  select 'frozen_subjects_drifted', '0',
         count(*) filter (where now_digest is distinct from frozen and not amended)::text
           || ' of ' || count(*)::text,
         count(*) filter (where now_digest is distinct from frozen and not amended) = 0
    from judged
  union all
  select 'frozen_subjects_whose_object_no_longer_exists', '0',
         count(*) filter (where now_digest is null)::text || ' of ' || count(*)::text,
         count(*) filter (where now_digest is null) = 0
    from judged
  union all
  select 'frozen_subjects_changed_under_a_recorded_amendment', 'informational',
         count(*) filter (where amended)::text || ' of ' || count(*)::text, true
    from judged
  union all
  -- E23 REPLACES frozen_subjects_changed_with_no_change_request, WHICH COULD NOT FIRE.
  -- That row tested btrim(change_request_ref) = '' on a column that is NOT NULL and shape-checked,
  -- so it read 0 of 25 whatever anyone did. The R3 acceptance named it, correctly, as a green tick
  -- measuring nothing. What is checkable is whether the MECHANISM is still in place, and this row
  -- goes red the moment any of the three constraints is dropped.
  select 'change_request_reference_is_enforced', '3',
         -- The three are counted into ONE number. An earlier draft printed the two constraints as
         -- "2 of 3" and reported the NOT NULL separately, which read as a failing check sitting
         -- next to a green tick — the precise confusion this row exists to end.
         ((select count(*) from pg_constraint
            where conrelid = 'public.phase_c_freeze_amendment'::regclass
              and conname in ('phase_c_freeze_amendment_change_request_ref_shape',
                              'phase_c_freeze_amendment_change_request_fk'))
          + (select count(*) from information_schema.columns
              where table_schema='public' and table_name='phase_c_freeze_amendment'
                and column_name='change_request_ref' and is_nullable='NO'))::text
         || ' of 3 (shape check, foreign key to phase_c_change_request, NOT NULL)',
         (select count(*) from pg_constraint
           where conrelid = 'public.phase_c_freeze_amendment'::regclass
             and conname in ('phase_c_freeze_amendment_change_request_ref_shape',
                             'phase_c_freeze_amendment_change_request_fk')) = 2
         and (select count(*) from information_schema.columns
               where table_schema='public' and table_name='phase_c_freeze_amendment'
                 and column_name='change_request_ref' and is_nullable='NO') = 1
  union all
  select 'amendments_whose_change_request_is_unregistered', '0',
         (select count(*)::text from public.phase_c_freeze_amendment a
           where not exists (select 1 from public.phase_c_change_request cr
                              where cr.change_request_ref = a.change_request_ref))
         || ' of ' || (select count(*)::text from public.phase_c_freeze_amendment),
         not exists (select 1 from public.phase_c_freeze_amendment a
                      where not exists (select 1 from public.phase_c_change_request cr
                                         where cr.change_request_ref = a.change_request_ref))
  union all
  -- E34. THIS ROW'S ok WAS THE LITERAL true, AND IT READ 4 of 4.
  --
  -- Its own comment was candid - "Reported, never used. A change request that has been WRITTEN is
  -- not one that has been APPROVED" - and the consequence stood anyway: four amendments to frozen
  -- Phase C kernel contracts are live in production, unapproved, under a fully green board. The
  -- independent acceptance named it as the same species this estate keeps finding, a board row
  -- whose ok is a constant, and scored it LOW because it was disclosed. Disclosed in a comment is
  -- not disclosed on the board.
  --
  -- It is now a REAL RED, and it goes green the moment the founder signs. That is the right colour
  -- because the condition is genuinely unmet: an amendment to a frozen contract is not complete
  -- until the person who froze it has approved the change. Nothing here can clear it and nothing
  -- here should be able to - approved_by and approved_at are constrained to move as a pair, and a
  -- builder writing his own name into them would be the whole defect this row exists to surface.
  --
  -- 'expected' is now 0 rather than the word 'informational', so a reader comparing expected with
  -- actual sees the gap instead of a label that excuses it.
  select 'amendments_awaiting_founder_approval', '0',
         (select count(*) from public.phase_c_freeze_amendment where approved_by is null)::text
           || ' of ' || (select count(*) from public.phase_c_freeze_amendment)::text
           || ' await the founder (change requests named: '
           || (select coalesce(string_agg(distinct change_request_ref, ', '),'(none)')
                 from public.phase_c_freeze_amendment)
           -- E36. THIS SAID "Only he can clear this row." and nothing enforced it: approved_by was
           -- free text, and the acceptance auditor cleared all four with 'zz-r5-audit-not-the-founder'
           -- in one statement, turning the whole freeze board green. The trigger
           -- a10_freeze_amendment_approver_is_the_founder now refuses any approver that does not
           -- resolve to an ACTIVE row in public.phase_c_founder_identity. The row names the register
           -- rather than a person, because the register is what the database can check.
           || '). Cleared only by an approver resolving to an active identity in public.phase_c_founder_identity, enforced by a10_freeze_amendment_approver_is_the_founder.',
         (select count(*) from public.phase_c_freeze_amendment where approved_by is null) = 0
  union all
  select 'raw_frozen_subjects', 'informational',
         count(*)::text || ' of ' || count(*)::text, true
    from judged;
$function$;

-- ---- DRIVEN BOTH WAYS, AND THE DRIVE LIVES OUTSIDE THIS FILE ---------------------------------
--
-- The first version of this file ended in a `do` block that drove the guard three ways and then
-- raised to roll itself back. It worked -- and it rolled the trigger back with it, because
-- apply_sql.mjs applies the whole file in ONE transaction. A verification that aborts its own DDL
-- has verified nothing that survived. The drive now lives in CI instead, and its measured result
-- is recorded here:
--
--   'zz-e36-not-the-founder'                REFUSED   pccr_approver_not_the_founder
--   'build-mode@quotesdone.local'           REFUSED   pccr_approver_not_the_founder
--       a registered row, but active=false, and its own note says "Not a person"
--   'ahmadalzain1993@admin.quotesdone.com'  ACCEPTED on 4 rows -- his registered identity
--
--   freeze board red count: 1 before his approval, 0 after. The guard is not refuse-everything,
--   and the row this file corrects does go green the moment he actually signs.
--
-- All of it inside one transaction ending in `raise exception`; the four amendments still await
-- him. scripts/checks/freeze_amendment_names_a_real_change_request.test.mjs now carries the same
-- three probes, so CI re-drives them on every run rather than trusting this comment.
