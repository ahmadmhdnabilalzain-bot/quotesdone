-- LIFT ALL PHASE FREEZES. Founder decision, 2026-09-02: "not a single phase should be frozen."
--
-- The QuotesDone company is fully autonomous and must evolve itself like a real company without a
-- founder-signature/amendment gate on every change. This lifts the Phase A, Phase B and Phase C
-- DEVELOPMENT freezes via ONE reversible switch: decision_policy 'phase_freezes_lifted' = true.
-- Flip it back to false and every freeze is enforced again exactly as before -- nothing is dropped.
--
-- A session-local override keeps the machinery testable and reversible: a connection that sets
--   set local app.enforce_phase_freezes = '1'
-- forces the freeze to enforce for that transaction even while the policy is lifted, so the
-- guards-reject-injected-defects tests still prove the guards fire, and any session can re-enforce
-- without flipping the global policy.
--
-- Three enforcers honor the switch:
--   fn_phase_a_freeze_guard  (trigger on org_role, org_departments)  -> advisory when lifted
--   fn_phase_b_freeze_guard  (trigger on 11 phase_b_* baseline tables) -> advisory when lifted
--   fn_phase_c_freeze_drift  (CI board)  -> frozen_subjects_drifted passes when lifted
--
-- DELIBERATELY UNCHANGED -- these are SAFETY/MONEY/AUDIT controls, not development freezes, and the
-- founder's exception plus his standing money rule keep them:
--   * OpenRouter / paid inference stays blocked.
--   * The refund->founder money path and auto_action_max_aed stay (agents do not autonomously spend).
--   * fn_kernel_truncate_guard, parent-delete guards (no data loss).
--   * gl_journal / gl_journal_lines immutability, decision_trace / llm_attempt append-only (accounting
--     and audit integrity).
--   * The forged-approval integrity checks inside fn_phase_c_freeze_drift (only the frozen-subject
--     DIGEST-drift row honors the switch; every approval-authenticity check is untouched).
--
--   node scripts/apply_sql.mjs scripts/sql/lift_all_phase_freezes.sql --apply --ddl

begin;

-- The one switch. Recorded as a founder decision with its date and words.
insert into public.decision_policy (key, value, description)
values ('phase_freezes_lifted', to_jsonb(true),
        'Founder decision 2026-09-02: "not a single phase should be frozen." Lifts the Phase A/B/C development freezes. OpenRouter, money and data-loss/audit controls are unaffected.')
on conflict (key) do update set value = to_jsonb(true), description = excluded.description;

CREATE OR REPLACE FUNCTION public.fn_phase_a_freeze_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare v_reason text; v_depts int; v_roles int; v_overlays int; b public.org_phase_baseline%rowtype;
begin
  -- FREEZES LIFTED (founder decision 2026-09-02: "not a single phase should be frozen").
  if (coalesce((select (value #>> '{}')::boolean from public.decision_policy where key = 'phase_freezes_lifted'), false)
       and coalesce(current_setting('app.enforce_phase_freezes', true), '') <> '1') then
    raise notice 'PHASE A freeze lifted; org shape change allowed';
    return null;
  end if;
  select * into b from public.org_phase_baseline where phase = 'A';
  if not found then return null; end if;   -- nothing approved yet, nothing to freeze

  select count(*) into v_depts from public.org_departments where active;
  select count(*) into v_roles from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay';
  select count(*) into v_overlays from public.org_role where status='active' and runtime_mode = 'knowledge_overlay';

  if v_depts = (b.counts->>'active_departments')::int
     and v_roles = (b.counts->>'canonical_roles')::int
     and v_overlays = (b.counts->>'category_overlays')::int then
    return null;                            -- the shape is unchanged; this was not a Phase A change
  end if;

  v_reason := nullif(btrim(current_setting('app.phase_a_change_reason', true)), '');
  if v_reason is null then
    raise exception
      'PHASE A IS FROZEN. This statement changes the approved organisational shape from %/%/% to %/%/% '
      '(departments/roles/overlays), and the founder approved the first on 2026-08-15. A change needs a '
      'formal Phase A change request with evidence and founder approval. State it in the same transaction: '
      '  set local app.phase_a_change_reason = ''PACR-nnn: <finding, evidence, approver>'';',
      b.counts->>'active_departments', b.counts->>'canonical_roles', b.counts->>'category_overlays',
      v_depts, v_roles, v_overlays;
  end if;

  raise notice 'PHASE A SHAPE CHANGED to %/%/% under change reason: %', v_depts, v_roles, v_overlays, v_reason;
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_phase_b_freeze_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  b public.org_phase_baseline%rowtype;
  v_reason text;
  v_moved text;
  v_count bigint;
begin
  -- FREEZES LIFTED (founder decision 2026-09-02: "not a single phase should be frozen").
  if (coalesce((select (value #>> '{}')::boolean from public.decision_policy where key = 'phase_freezes_lifted'), false)
       and coalesce(current_setting('app.enforce_phase_freezes', true), '') <> '1') then
    raise notice 'PHASE B freeze lifted; workflow architecture change allowed';
    return null;
  end if;
  select * into b from public.org_phase_baseline where phase = 'B';
  if not found then return null; end if;    -- nothing approved yet, nothing to freeze

  -- Which of the founder's frozen subjects moved? Compared against the digest recorded at
  -- approval, using the same function the baseline was built from.
  select string_agg(d.subject || ' (' || left(d.sha256, 12) || ' != '
                    || left(coalesce(b.registry_sha256->'structure'->d.subject->>'database','NONE'), 12) || ')',
                    ', ' order by d.subject)
    into v_moved
  from public.fn_phase_b_structure_digest() d
  where d.sha256 is distinct from (b.registry_sha256->'structure'->d.subject->>'database');

  if v_moved is null then
    return null;                            -- the approved structure is unchanged
  end if;

  v_reason := nullif(btrim(current_setting('app.phase_b_change_reason', true)), '');
  if v_reason is null then
    raise exception
      'PHASE B IS FROZEN. This statement changes the approved workflow architecture: %. '
      'The founder approved this architecture on 2026-08-15 as the final QuotesDone business-workflow '
      'design. A change needs a formal Phase B change request stating the observed problem, evidence, '
      'current workflow and step, proposed change, affected owners, state-machine impact, gate and rule '
      'impact, customer/supplier impact, privacy/legal/financial impact, backward compatibility and '
      'whether founder approval is required. State it in the same transaction: '
      '  set local app.phase_b_change_reason = ''PBCR-nnn: <the above>'';',
      v_moved;
  end if;

  select count(*) into v_count from public.fn_phase_b_structure_digest() d
   where d.sha256 is distinct from (b.registry_sha256->'structure'->d.subject->>'database');
  raise notice 'PHASE B STRUCTURE CHANGED in % subject(s) [%] under change reason: %',
    v_count, v_moved, v_reason;
  return null;
end $function$
;

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
         (count(*) filter (where now_digest is distinct from frozen and not amended) = 0
          or (coalesce((select (value #>> '{}')::boolean from public.decision_policy where key = 'phase_freezes_lifted'), false)
       and coalesce(current_setting('app.enforce_phase_freezes', true), '') <> '1'))   -- freezes lifted: a subject may evolve without an amendment
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
$function$
;

commit;
