-- E38 - the register the guard trusted was writable by the caller it was guarding against
--
-- E36 made `approved_by` resolve to an ACTIVE row in public.phase_c_founder_identity, and the
-- re-audit refused every literal vector I had thought of: the R5 string, the inactive build_mode
-- identity, whitespace padding, `set session_replication_role` as service_role (42501), and
-- `alter table ... disable trigger` as service_role (42501). Then it asked the question I had not:
-- WHO CAN WRITE THE REGISTER?
--
--     set local role service_role;
--     insert into public.phase_c_founder_identity(identity, kind, active, note)
--       values ('zz-r6-audit-not-the-founder','email',true,'attack');   -- ACCEPTED
--     update public.phase_c_freeze_amendment
--        set approved_by = 'zz-r6-audit-not-the-founder', approved_at = now()
--      where approved_by is null;                                        -- ACCEPTED, 4 rows
--     delete from public.phase_c_founder_identity
--      where identity = 'zz-r6-audit-not-the-founder';                   -- ACCEPTED
--
-- Four amendments to frozen Phase C contracts approved, the freeze board 1 red -> 0, all boards back
-- to 9 red with no compensating red anywhere, the register restored to its two real founders, and
-- every one of those approvals naming a string that resolves to nobody. Same defect as R5, one layer
-- down, available to exactly the credential the finding was about.
--
-- TWO INDEPENDENT HOLES, AND EITHER ALONE REOPENS THE GATE.
--
-- (1) service_role held INSERT, UPDATE and DELETE on public.phase_c_founder_identity. A guard is
--     only as trustworthy as the register it reads, and this one was writable by its own subject.
--     Measured before revoking: no routine writes the table -- all eight routines naming it only
--     READ it -- and the four repository files that ever wrote it are one-time migration statements
--     applied as postgres, not runtime paths. os_api mentions it in comments and reads it. So SELECT
--     stays and the write grants go.
--
--     This matters well beyond the freeze board. That register is also read by
--     fn_phase_c_require_founder, fn_refund_founder_decision_only, fn_refund_decide,
--     fn_founder_command_submit and fn_control_mode_require. A role that can add itself to it can
--     authorise a REFUND. The founder's standing rule is that every refund needs him, at any amount.
--
-- (2) `amendments_awaiting_founder_approval` asked `approved_by is null`. That is a question about a
--     STORED STRING, not about whether an approval still stands, so the attacker could delete the
--     forged identity afterwards and leave the board green. It now counts an amendment as awaiting
--     unless its approved_by RESOLVES, right now, to an active founder identity. Deleting the
--     approver re-reddens the board in the same statement.
--
--     That second fix is also the backstop for the two owner-class bypasses the auditor reported and
--     correctly excluded from its verdict -- `postgres` can set session_replication_role or disable
--     the trigger, but the board is a derivation, not a trigger, so a forged approver still shows.
--     A guard can be turned off; a question that is asked fresh every time cannot.
--
-- This is the estate's own lens twice over: a check that reads a stored value instead of resolving
-- it, and a grant that made a record stale. Nothing here is weakened -- E36's trigger is untouched
-- and still refuses everything it refused before.

-- ---- (1) the register is not writable by the role the guard is guarding against ----------------
-- REVOKE from PUBLIC first: a grant held through PUBLIC makes a revoke from a named role a silent
-- no-op, and this estate has been caught by exactly that.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_c_founder_identity FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_c_founder_identity FROM anon, authenticated, service_role;

COMMENT ON TABLE public.phase_c_founder_identity IS
  'WHO THE FOUNDER IS. Read by fn_phase_c_require_founder, fn_refund_founder_decision_only, '
  'fn_refund_decide, fn_founder_command_submit, fn_control_mode_require and the freeze amendment '
  'approver guard. E38 revoked INSERT/UPDATE/DELETE from service_role, anon, authenticated and '
  'PUBLIC after an acceptance auditor added itself here as an email identity, approved four '
  'amendments to frozen Phase C contracts with it, and deleted the row again. A register that its '
  'own subject can write is not a register. Changing it is a migration applied as the owner, which '
  'is what every one of the four historical writes already was.';

-- ---- (2) the board asks whether the approval RESOLVES, not whether a string is present ----------
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
  -- E38. THIS ASKED `approved_by is null`, WHICH IS A QUESTION ABOUT A STORED STRING.
  -- An acceptance auditor added itself to public.phase_c_founder_identity as an email identity
  -- (service_role held INSERT), approved all four amendments with it, and DELETED the row again --
  -- leaving four approvals naming a string that resolves to nobody, and this row green. E38 revoked
  -- those write grants; this half asks the question fresh instead of trusting what was stored, so
  -- deleting the approver re-reddens the board in the same statement. It is also the backstop for
  -- an owner disabling the trigger: a guard can be turned off, a derivation cannot.
  select 'amendments_awaiting_founder_approval', '0',
         (select count(*) from public.phase_c_freeze_amendment a
           where a.approved_by is null
              or not exists (select 1 from public.phase_c_founder_identity fi
                              where fi.active
                                and lower(btrim(fi.identity)) = lower(btrim(a.approved_by))))::text
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
           || '). Cleared only while approved_by RESOLVES to one of the '
           || (select count(*)::text from public.phase_c_founder_identity where active)
           || ' active identities in public.phase_c_founder_identity -- asked here on every read, and enforced at write time by a10_freeze_amendment_approver_is_the_founder.',
         (select count(*) from public.phase_c_freeze_amendment a
           where a.approved_by is null
              or not exists (select 1 from public.phase_c_founder_identity fi
                              where fi.active
                                and lower(btrim(fi.identity)) = lower(btrim(a.approved_by)))) = 0
  union all
  select 'raw_frozen_subjects', 'informational',
         count(*)::text || ' of ' || count(*)::text, true
    from judged;
$function$;
