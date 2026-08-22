-- F31 - an approval that does not say how it was given
--
-- The founder's ruling of 22 Aug 2026, section 2, requires: "no unapproved Phase C amendment
-- silently recorded as founder-approved", and section 12 repeats it as a release condition.
--
-- WHAT IS ACTUALLY IN THE TABLE. public.phase_c_freeze_amendment holds five rows. Four
-- (amendment_id 1, 2, 4, 5) have approved_by = null and are honestly red. One (amendment_id 36,
-- PCCR-003) reads approved_by = 'management@quotesdone.com', approved_at = the same instant the
-- change request was raised, written by a migration -- scripts/sql/phase_d_f23_pccr_003_recorded_
-- and_approved.sql -- that the BUILDER ran. The founder never authenticated to this database to
-- place it.
--
-- That record is not a fabrication: F23 quotes his written instruction of 21 Aug 2026 section E
-- verbatim ("The approved design is Supabase Auth JWT identity...") and docs/phase-c/
-- PHASE_C_CHANGE_REQUEST_PCCR-003.md holds it in full. He did approve the design, in writing.
--
-- But the COLUMN cannot tell the two apart, and a reader of the board cannot either. "approved_by
-- = the founder's email" reads as "the founder signed this in the system". That is the estate's
-- recurring shape -- a disposition in prose with no mechanism -- and the remedy here is not to
-- delete his instruction from the record, nor to leave the ambiguity: it is to make the DISTINCTION
-- machine-readable and to put the weaker kind on the board in red until he signs.
--
-- WHAT THIS FILE DOES NOT DO. It does not clear amendment 36. Deleting a truthful record of a
-- written instruction to make a column tidier would lose the thing he actually gave. It does not
-- touch amendments 1, 2, 4 or 5, whose approved_by stays null. It grants nothing and revokes
-- nothing.

begin;

-- 1. THE COLUMN. Two values only, and it is required exactly when an approval is present.
alter table public.phase_c_freeze_amendment
  add column if not exists approval_basis text;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.phase_c_freeze_amendment'::regclass
                    and conname = 'phase_c_freeze_amendment_approval_basis_values') then
    alter table public.phase_c_freeze_amendment
      add constraint phase_c_freeze_amendment_approval_basis_values
      check (approval_basis is null
             or approval_basis in ('AUTHENTICATED_FOUNDER_SESSION', 'WRITTEN_INSTRUCTION'));
  end if;
end $$;

-- 2. BACKFILL BEFORE THE PAIR CONSTRAINT, or the constraint refuses the row it is describing.
update public.phase_c_freeze_amendment
   set approval_basis = 'WRITTEN_INSTRUCTION'
 where approved_by is not null
   and approval_basis is null;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.phase_c_freeze_amendment'::regclass
                    and conname = 'phase_c_freeze_amendment_approval_basis_is_stated') then
    alter table public.phase_c_freeze_amendment
      add constraint phase_c_freeze_amendment_approval_basis_is_stated
      check ((approved_by is null) = (approval_basis is null));
  end if;
end $$;

commit;

-- 3. THE BOARD SAYS IT. A new row, expected 0, red while any approval rests on a written
--    instruction rather than an authenticated founder session. It cannot be cleared by prose and it
--    cannot be cleared by this repository: the only way to 0 is for him to approve through a
--    verified session, which F20 made possible and F21 granted.
--
--    The existing amendments_awaiting_founder_approval row is left computing exactly what it
--    computed before. Its subject is "is there an approver who resolves to an active founder
--    identity", and that is a different question from "how was the approval given". Folding the two
--    would produce one number with two causes, which is the shape this estate has been bitten by.
create or replace function public.fn_phase_c_freeze_drift()
returns table (check_name text, expected text, actual text, ok boolean)
language sql
stable
security definer
set search_path = public, pg_catalog, pg_temp
as $fn$
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
  -- F31. HOW THE APPROVAL WAS GIVEN, WHICH IS NOT THE SAME QUESTION AS WHETHER THERE IS ONE.
  --
  -- The row above asks whether approved_by resolves to an active founder identity. It cannot tell
  -- an approval the founder placed through a verified Supabase Auth session from one a migration
  -- wrote on the strength of an instruction he sent in a message. Both leave the same string in the
  -- same column. F23 wrote the second kind for PCCR-003 and said so in its own header; nothing on
  -- any board repeated it, so a reader saw "approved by the founder" and had no way to learn which.
  --
  -- This row is red while any approval rests on WRITTEN_INSTRUCTION. It is a disclosure, not an
  -- accusation: the instruction is real, quoted verbatim in the change request, and the design it
  -- approves is strictly harder to pass than the one it replaced. What is missing is his signature
  -- through the door F20 built and F21 granted, and that is his to give, not this repository's.
  select 'amendments_approved_on_written_instruction_only', '0',
         (select count(*) from public.phase_c_freeze_amendment
           where approval_basis = 'WRITTEN_INSTRUCTION')::text
         || ' of ' || (select count(*) from public.phase_c_freeze_amendment)::text
         || ' (change requests: '
         || (select coalesce(string_agg(distinct change_request_ref, ', '),'(none)')
               from public.phase_c_freeze_amendment where approval_basis = 'WRITTEN_INSTRUCTION')
         || '). An approval recorded from a written instruction is not a founder session. Cleared '
         || 'only by re-approval through a verified auth subject, which no migration can perform.',
         (select count(*) from public.phase_c_freeze_amendment
           where approval_basis = 'WRITTEN_INSTRUCTION') = 0
  union all
  select 'raw_frozen_subjects', 'informational',
         count(*)::text || ' of ' || count(*)::text, true
    from judged;
$fn$;
