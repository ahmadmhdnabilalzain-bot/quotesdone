-- PCCR-006 BOOTSTRAP APPROVAL RECORD.
--
-- NO TRANSACTION CONTROL. One INSERT and one assertion block; rehearsable.
--
-- PCCR-006 closes the door it had to be approved through. Its own §"The bootstrap founder-approval
-- procedure" says that is not circular but needs one stated bootstrap, used exactly once, that is
-- not any of the things PCCR-006 forbids. This file is that record.
--
-- ================================================================================================
-- WHAT THE FOUNDER DID, AND WHAT WAS VERIFIED BEFORE THIS FILE WAS WRITTEN
-- ================================================================================================
--
-- He typed the sentence PCCR-006 asks for into the Command Center as a NEW COMMAND on
-- 2026-08-25 at 16:54:20.940141+00. Every attribute below was read out of production, not asserted:
--
--   command_id            39505
--   message_id            40674
--   channel               command_center
--   founder_identity      management@quotesdone.com   (active, kind email, in phase_c_founder_identity)
--   raw_text_hash         53edf1251bcee9123d587f4f3dc13c11aca184547cac12edd9fc7491511924ad
--   hash recomputed       encode(sha256(convert_to(raw_text,'UTF8')),'hex') = raw_text_hash -> TRUE
--   raw_text (191 chars)  I approve PCCR-006 — governance_approval_authenticity — as set out in
--                         docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md, sha256
--                         c787bfcfe38578010f29e4ed2dcaddc602be42f16eb3a320aab6f75519561ceb.
--   root trace            4329096   (TRACE-FOUNDER-COMMAND, exactly one row for this command)
--   os_audit_log          19027, actor management@quotesdone.com, action founder_command
--   tasks_created         0
--   workflow_ids          []        (interpretation v1 records the empty string)
--   task_ids              []        (0 rows in founder_command_task_link and _workflow_link)
--   external effect       0 notification rows and 0 phase_d_external_attempt rows since 16:50
--   state                 clarification_required / AMBIGUOUS — which is CORRECT: a governance
--                         sentence must not create business work, and this is the same outcome his
--                         acceptance-standard approval produced
--
-- The digest in his sentence equals `sha256sum docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md`
-- at HEAD, byte for byte: c787bfcfe38578010f29e4ed2dcaddc602be42f16eb3a320aab6f75519561ceb.
--
-- ================================================================================================
-- WHY approval_basis IS NOT 'AUTHENTICATED_FOUNDER_SESSION', AND WHY THAT IS THE POINT
-- ================================================================================================
--
-- A `founder_command_message` row records the identity os_api VERIFIED with admin.auth.getUser, as
-- a string. It does not record auth.uid(), because the JWT verification happens in the edge
-- function and not in the database. PCCR-006's own §"The residual weakness in the bootstrap,
-- stated rather than hidden" says exactly this: the row is strong evidence and is NOT self-proving.
--
-- So this row does not claim what it does not have. `AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP` is a
-- third value, and each word of it is load-bearing:
--
--   NOT 'AUTHENTICATED_FOUNDER_SESSION'  — there was no auth.uid() and no bound auth event, and
--                                          a05_freeze_amendment_session_claim_is_verified would
--                                          refuse the claim. Verified: that trigger passes any row
--                                          whose basis is not that literal, so this row is not
--                                          sneaking past a guard — it is outside the claim the
--                                          guard exists to check, permanently and visibly.
--   NOT 'WRITTEN_INSTRUCTION'            — it was not a written instruction. It was an
--                                          authenticated HTTP request that os_api gated on a live
--                                          bearer token and that produced a hashed, immutable,
--                                          traced row. fn_phase_c_freeze_drift counts
--                                          WRITTEN_INSTRUCTION separately and requires 0; this file
--                                          leaves that at 0 and is asserted to.
--
-- USED EXACTLY ONCE. Every governance approval after this one goes through
-- fn_phase_c_governance_decide, which refuses any connection that is not `authenticator` and mints
-- and consumes a purpose-bound, single-use, expiring auth event in the same transaction. This value
-- appearing on a SECOND row is a defect, and the assertion at the end of this file says so.
--
-- ================================================================================================
-- THE DEPLOY ORDER, TRUTHFULLY
-- ================================================================================================
--
--   16:54:20.940141+00   the founder approved
--   16:57 (approx)       scripts/sql/phase_c_pccr006_governance_approval_authenticity.sql applied,
--                        10 routines read back identical to the file
--
-- The approval came FIRST. `deployed_before_approval` is therefore FALSE — which is the order that
-- ought to hold and is recorded here because it did, not because it is preferable.
-- `original_deployment_at` carries the apply timestamp.
--
-- WHAT THIS ROW IS FOR. Amendment A of PCCR-006 is the ONLY frozen Phase C subject the change
-- touches: `founder_authentication` / `fn_phase_c_require_founder(p_actor text)`. Without this row
-- fn_phase_c_freeze_drift reads `frozen_subjects_drifted 1 of 25` — a frozen routine whose digest
-- moved with no amendment recording it, which is exactly the condition the freeze board exists to
-- catch. Both digests below were read from production with pg_get_functiondef, before and after.
--
-- THE TWO DIGESTS ARE BASELINE -> CURRENT, NOT LINK BY LINK, AND THAT IS THE BOARD'S RULE.
-- fn_phase_c_freeze_drift judges a subject undrifted when an amendment carries BOTH
-- phase_c_frozen_subject.digest as its prior_digest AND the live body as its new_digest. Its own
-- comment says why: "An edit on top of an amendment is drift, because its prior digest no longer
-- matches." So prior_digest here is the FROZEN BASELINE b2fff88d695729dd..., not the body this
-- change actually replaced.
--
-- The body it actually replaced was e0f8f63e14238a83..., which is amendment 36's new_digest -- the
-- one PCCR-003 introduced and the founder approved in a verified session on 21 Aug 2026. That fact
-- is not lost: it is stated here and in the reason on the row. Amendment 36 stops matching the
-- live body from now on, which is correct -- it describes a state that has been superseded, and
-- the EXISTS in the board is satisfied by whichever amendment carries baseline -> current.
--
-- A first attempt used e0f8f63e as prior_digest. The migration's own assertion caught it:
--   pccr006_drift_not_closed: frozen_subjects_drifted is still red after recording the amendment

-- ================================================================================================
-- THE VOCABULARY HAD TWO VALUES AND NEITHER WAS TRUE
-- ================================================================================================
--
-- phase_c_freeze_amendment_approval_basis_values was a closed list of exactly two:
--   AUTHENTICATED_FOUNDER_SESSION | WRITTEN_INSTRUCTION
--
-- Claiming the first would be false, and a05_freeze_amendment_session_claim_is_verified would
-- refuse it. Claiming the second would ALSO be false -- this was an authenticated HTTP request that
-- os_api gated on a live bearer token and that produced a hashed, immutable, traced row -- and it
-- would turn fn_phase_c_freeze_drift :: amendments_approved_on_written_instruction_only red, which
-- is a board row that must read 0.
--
-- So the list is widened by ONE value. That is a deliberate act, and three things hold it honest
-- rather than making it a convenience:
--
--   1. the value says what happened and claims nothing more;
--   2. the assertion at the end of this file fails if it is ever on more than one row;
--   3. fn_phase_c_freeze_drift gains a row publishing the count and going RED at anything but
--      exactly 1 -- so a third basis can never be silent, in either direction.
--
-- A closed list widened without all three is how an exemption gets in. This value is the founder's
-- own, named in his instruction of 25 Aug 2026: "approval_basis = authenticated founder command
-- bootstrap".

ALTER TABLE public.phase_c_freeze_amendment
  DROP CONSTRAINT IF EXISTS phase_c_freeze_amendment_approval_basis_values;
ALTER TABLE public.phase_c_freeze_amendment
  ADD CONSTRAINT phase_c_freeze_amendment_approval_basis_values CHECK (
    approval_basis IS NULL OR approval_basis = ANY (ARRAY[
      'AUTHENTICATED_FOUNDER_SESSION',
      'WRITTEN_INSTRUCTION',
      'AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP']));

-- ================================================================================================
-- PCCR-006 IS REGISTERED, AND ITS REGISTER ROW SAYS 'RAISED' ON PURPOSE
-- ================================================================================================
--
-- phase_c_freeze_amendment_change_request_fk requires the change request to exist before an
-- amendment may reference it, and PCCR-006 has never had a row -- PCCR-001 through PCCR-005 do.
--
-- The disposition is RAISED and NOT 'APPROVED', and that is not an understatement of what the
-- founder did. It is the consequence of what PCCR-006 itself now enforces:
--
--   phase_c_change_request_approval_is_derived   CHECK ((approved_by IS NULL) = (governance_decision_id IS NULL))
--   a05_phase_c_change_request_approval_is_derived   refuses any write to disposition or any
--                                                    approval column not derived from this
--                                                    transaction's ledger row
--
-- A governance_decision row can only be written by fn_phase_c_governance_decide, which refuses any
-- connection whose session_user is not 'authenticator'. So the ONE change request that cannot be
-- marked APPROVED in this register is the one that created the register's rules -- and marking it
-- APPROVED anyway would require exactly the unbacked write it exists to forbid.
--
-- THE APPROVAL IS NOT MISSING. It is recorded on the freeze amendment below, with basis
-- AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP, naming command 39505 and its verified hash. The
-- disposition_reason says so in full, so this row cannot be read as 'still pending'. Every change
-- request AFTER this one reaches APPROVED through the canonical service, which is the point.

INSERT INTO public.phase_c_change_request
  (change_request_ref, document_path, subject, raised_at, disposition,
   disposition_reason, disposition_recorded_at)
VALUES (
  'PCCR-006',
  'docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md',
  'governance_approval_authenticity',
  '2026-08-24 00:00:00+00'::timestamptz,
  'RAISED',
  'APPROVED BY THE FOUNDER AND APPLIED -- and it may not say APPROVED in this column, which is '
    || 'PCCR-006 working on itself. He approved it in the Command Center on 2026-08-25 at '
    || '16:54:20.940141+00: command 39505, message 40674, raw_text_hash '
    || '53edf1251bcee9123d587f4f3dc13c11aca184547cac12edd9fc7491511924ad (recomputed on production '
    || 'and equal), root trace 4329096, os_audit_log 19027, quoting document digest '
    || 'c787bfcfe38578010f29e4ed2dcaddc602be42f16eb3a320aab6f75519561ceb. The migration was applied '
    || 'the same afternoon, 10 routines read back identical to the file. '
    || 'phase_c_change_request_approval_is_derived now requires a governance_decision_id beside any '
    || 'approved_by, and only fn_phase_c_governance_decide can create one, and only on a connection '
    || 'whose session_user is authenticator. This change request is the one that created that rule, '
    || 'so it cannot satisfy it retroactively without the unbacked write it forbids. Its approval is '
    || 'recorded on public.phase_c_freeze_amendment with approval_basis '
    || 'AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP, used exactly once and pinned at one by '
    || 'fn_phase_c_freeze_drift. Every change request after PCCR-006 reaches APPROVED through the '
    || 'canonical service. See docs/phase-c/PCCR-006_PRE_APPROVAL_REHEARSAL.md.',
  now())
ON CONFLICT (change_request_ref) DO NOTHING;

INSERT INTO public.phase_c_freeze_amendment
  (subject, object_identity, prior_digest, new_digest, reason, evidence,
   change_request_ref, approved_by, approved_at, approval_basis,
   deployed_before_approval, original_deployment_at,
   approval_route, approval_auth_subject,
   approved_amendment_table_path, approved_amendment_table_digest)
VALUES (
  'founder_authentication',
  'fn_phase_c_require_founder(p_actor text)',
  'b2fff88d695729ddc8134532908ca0dd9fb3697f80bd7457d8ec35ab5a601e24',
  '3fc51958472a20c785214f7142f635c83f0c349e51d8246e4a6ba7c0b42574d6',
  'PCCR-006 Amendment A. One predicate added to Route B of fn_phase_c_require_founder: '
    || 'and e.action_class is null. PCCR-006 introduces purpose-bound founder auth events carrying '
    || 'the change request, the decision and the amendment-table digest; without this predicate a '
    || 'session minted to approve a change request would ALSO satisfy the refund door in the same '
    || 'transaction. Measured on 25 Aug 2026 before the change: running the bind door and then the '
    || 'refund door in one transaction, the refund door ACCEPTED. A session issued for one act must '
    || 'not pay for another. Route A, the signature, the return, the message text and every caller '
    || 'are unchanged.',
  'Founder approval: Command Center command 39505, message 40674, channel command_center, '
    || 'received 2026-08-25 16:54:20.940141+00, founder_identity management@quotesdone.com, '
    || 'raw_text_hash 53edf1251bcee9123d587f4f3dc13c11aca184547cac12edd9fc7491511924ad '
    || '(recomputed on production and equal), root trace 4329096 TRACE-FOUNDER-COMMAND, '
    || 'os_audit_log 19027. tasks_created 0, workflow_ids [], task_ids [], no external effect. '
    || 'Approved document docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md sha256 '
    || 'c787bfcfe38578010f29e4ed2dcaddc602be42f16eb3a320aab6f75519561ceb, quoted verbatim in his '
    || 'sentence. Pre-approval rehearsal and the FD-01 case results: '
    || 'docs/phase-c/PCCR-006_PRE_APPROVAL_REHEARSAL.md. The committed migration did NOT apply as '
    || 'written -- its new CHECK was violated by PCCR-003, the founder approval of 21 Aug that '
    || 'predates the governance ledger -- and was corrected to NOT VALID before application; the '
    || 'PCCR-006 document digest is unchanged by that correction.',
  'PCCR-006',
  'management@quotesdone.com',
  '2026-08-25 16:54:20.940141+00'::timestamptz,
  'AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP',
  false,
  now(),
  -- approval_route IS NULL, AND A SECOND CLOSED LIST IS NOT WIDENED TO AVOID SAYING SO.
  -- phase_c_freeze_amendment_approval_route_values admits three values and every one of them names
  -- a route INTO THE DATABASE: auth.uid(), fn_phase_c_founder_subject_bind, written_instruction.
  -- This approval had none. The verification happened in os_api, against a live bearer token, and
  -- what reached the database was a routine call carrying a verified email as a string. NULL is the
  -- accurate answer to 'which verified database route was used' and inventing a fourth value would
  -- be dressing the absence up as a route. The path is recorded in full in  above, which
  -- is prose and is where a description belongs.
  NULL,
  NULL,
  'docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md',
  'c787bfcfe38578010f29e4ed2dcaddc602be42f16eb3a320aab6f75519561ceb');

-- ================================================================================================
-- THE BOARD PUBLISHES THE THIRD BASIS, PINNED AT EXACTLY ONE
-- ================================================================================================

CREATE OR REPLACE FUNCTION public.fn_phase_c_freeze_drift()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'pg_temp'
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
    from judged
  union all
  -- PCCR-006. AN APPROVED CHANGE REQUEST THAT NO VERIFIED GOVERNANCE DECISION BACKS.
  --
  -- Measured 24 Aug 2026 in aborted transactions, before this change request:
  --   update public.phase_c_change_request set approved_by='<the founder>', approved_at=now()
  --    where change_request_ref='PCCR-004';                                          -> ACCEPTED
  -- and the row came out disposition=APPROVED carrying the DEFERRAL's own reason text, because
  -- a15_phase_c_change_request_disposition_follows_approval rewrote the disposition before the
  -- CHECK phase_c_change_request_deferral_is_not_approval was evaluated. The old board had no row
  -- about phase_c_change_request at all: every governance row it carried was about
  -- phase_c_freeze_amendment.
  --
  -- This row reads the LEDGER and not the column. After PCCR-006 the approval columns are derived
  -- from public.phase_c_governance_decision and a05_phase_c_change_request_approval_is_derived
  -- refuses every other writer, including migration SQL running as postgres.
  select 'approved_change_requests_with_no_verified_governance_decision', '0',
         (select count(*) from public.phase_c_change_request cr
           where cr.disposition = 'APPROVED'
             and not exists (select 1 from public.phase_c_governance_decision d
                              where d.decision_id = cr.governance_decision_id
                                and d.change_request_ref = cr.change_request_ref
                                and d.decision = 'APPROVED'))::text
         || ' of ' || (select count(*) from public.phase_c_change_request
                        where disposition = 'APPROVED')::text
         || ' approved. Read from public.phase_c_governance_decision, which only '
         || 'fn_phase_c_governance_decide can write and only against a purpose-bound, single-use '
         || 'founder auth event consumed in the same transaction.',
         (select count(*) from public.phase_c_change_request cr
           where cr.disposition = 'APPROVED'
             and not exists (select 1 from public.phase_c_governance_decision d
                              where d.decision_id = cr.governance_decision_id
                                and d.change_request_ref = cr.change_request_ref
                                and d.decision = 'APPROVED')) = 0
  union all
  -- PCCR-006. A DEFERRED OR REJECTED REQUEST CARRYING AN APPROVER.
  -- Before this change request the count could never rise, because the trigger re-dispositioned the
  -- row to APPROVED first. It is a real reading only now that nothing rewrites the disposition.
  select 'deferred_or_rejected_change_requests_carrying_an_approver', '0',
         (select count(*) from public.phase_c_change_request
           where disposition = any (array['DEFERRED','DEFER_OR_REJECT','REJECTED','WITHDRAWN'])
             and approved_by is not null)::text
         || ' of ' || (select count(*) from public.phase_c_change_request)::text
         || '. A deferral is not an approval and may not be read as one.',
         (select count(*) from public.phase_c_change_request
           where disposition = any (array['DEFERRED','DEFER_OR_REJECT','REJECTED','WITHDRAWN'])
             and approved_by is not null) = 0
  union all
  -- PCCR-006 BOOTSTRAP. THE ONE APPROVAL THAT DID NOT COME THROUGH A VERIFIED SESSION.
  -- approval_basis was a closed list of two values and neither was true of PCCR-006's own
  -- approval: it was not a verified session (no auth.uid(), no bound event -- PCCR-006's own
  -- section on the residual weakness says so) and it was not a written instruction (it was an
  -- authenticated HTTP request that produced a hashed, immutable, traced founder_command_message
  -- row). AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP is the third value and it is pinned at EXACTLY
  -- ONE, forever: zero would mean the record of how PCCR-006 was approved has gone, and two would
  -- mean the one-time bootstrap was reused for something else. Both are defects, so both are red.
  -- Published here so a third basis can never be silent.
  select 'amendments_approved_on_the_one_time_command_bootstrap', 'exactly 1 -- PCCR-006 itself',
         (select count(*) from public.phase_c_freeze_amendment
           where approval_basis = 'AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP')::text
         || ' of ' || (select count(*) from public.phase_c_freeze_amendment)::text
         || ' amendment(s)'
         || coalesce(' [' || (select string_agg(change_request_ref || ' <- command ' ||
              coalesce(substring(evidence from 'command ([0-9]+)'),'(none)'), ', ')
              from public.phase_c_freeze_amendment
             where approval_basis = 'AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP') || ']', '')
         || '. Every governance approval after this one goes through fn_phase_c_governance_decide, '
         || 'which refuses any connection that is not authenticator.',
         (select count(*) from public.phase_c_freeze_amendment
           where approval_basis = 'AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP') = 1;
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_c_freeze_drift() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_c_freeze_drift() TO service_role;

-- ================================================================================================
-- ASSERTIONS. Counted from the estate, not from this file's intentions.

DO $assert$
DECLARE
  v_bootstrap int; v_written int; v_drifted int; v_cmd int; v_msg_hash text;
BEGIN
  -- (a) USED EXACTLY ONCE.
  SELECT count(*) INTO v_bootstrap FROM public.phase_c_freeze_amendment
   WHERE approval_basis = 'AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP';
  IF v_bootstrap <> 1 THEN
    RAISE EXCEPTION 'PCCR-006 bootstrap: % rows carry AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP. It '
      'is used exactly once, for PCCR-006 itself. Every approval after it goes through '
      'fn_phase_c_governance_decide. (pccr006_bootstrap_reused)', v_bootstrap USING errcode = '23514';
  END IF;

  -- (b) IT DID NOT BECOME A WRITTEN INSTRUCTION. That counter must stay 0.
  SELECT count(*) INTO v_written FROM public.phase_c_freeze_amendment
   WHERE approval_basis = 'WRITTEN_INSTRUCTION';
  IF v_written <> 0 THEN
    RAISE EXCEPTION 'PCCR-006 bootstrap: % amendment(s) read WRITTEN_INSTRUCTION', v_written
      USING errcode = '23514';
  END IF;

  -- (c) THE COMMAND THIS ROW NAMES STILL EXISTS AND STILL HASHES TO WHAT THE ROW SAYS. A record
  --     that points at a command is only worth the command still being there and unaltered.
  SELECT count(*) INTO v_cmd FROM public.founder_command c
    JOIN public.founder_command_message m USING (message_id)
   WHERE c.command_id = 39505 AND m.message_id = 40674
     AND m.founder_identity = 'management@quotesdone.com'
     AND m.raw_text_hash = '53edf1251bcee9123d587f4f3dc13c11aca184547cac12edd9fc7491511924ad'
     AND encode(sha256(convert_to(m.raw_text,'UTF8')),'hex') = m.raw_text_hash
     AND position('c787bfcfe38578010f29e4ed2dcaddc602be42f16eb3a320aab6f75519561ceb' in m.raw_text) > 0;
  IF v_cmd <> 1 THEN
    RAISE EXCEPTION 'PCCR-006 bootstrap: the command this row is attributed to does not verify '
      '(matched % row(s)). (pccr006_bootstrap_command_unverified)', v_cmd USING errcode = '28000';
  END IF;

  -- (d) THE DRIFT THIS ROW EXISTS TO CLOSE IS CLOSED.
  SELECT count(*) INTO v_drifted FROM public.fn_phase_c_freeze_drift()
   WHERE check_name = 'frozen_subjects_drifted' AND NOT ok;
  IF v_drifted <> 0 THEN
    RAISE EXCEPTION 'PCCR-006 bootstrap: frozen_subjects_drifted is still red after recording the '
      'amendment (pccr006_drift_not_closed)' USING errcode = '23514';
  END IF;

  RAISE NOTICE 'PCCR-006 bootstrap recorded once, command 39505 verifies, WRITTEN_INSTRUCTION 0, '
    'frozen_subjects_drifted closed';
END $assert$;
