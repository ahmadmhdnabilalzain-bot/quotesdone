-- N01. THE WRITER'S OWN GATE NEVER ASKED WHETHER THE SUPPLIER WAS APPROVED.
--
-- public.inquiry_matches is where an inquiry is assigned to a supplier. Two BEFORE INSERT triggers
-- guard it, and they fire in name order:
--
--   a00_unsafe_match_eligibility  -> public.fn_unsafe_match_eligibility_guard()   (this file)
--   gate_incomplete_match         -> public.trg_gate_incomplete_match()           (readiness, K05)
--
-- BR-015 ("only an approved, eligible supplier is dispatched to") and GATE-014 both read
--
--     coalesce(l.approval_status,'') = 'approved' and coalesce(l.verified,false)
--
-- and refuse anything else. The WRITER'S OWN GATE read banned, matching_blocked,
-- permanently_closed and license_expiry, and never approval_status at all. So the rule and the gate
-- agreed with each other and the trigger underneath them agreed with neither: when a caller wrote
-- the assignment WITHOUT consulting the gate, an unapproved supplier was accepted.
--
-- Measured on htdblwldjkcgjvmqkbeh, 24 Aug 2026:
--
--     select approval_status, count(*) from public.leads group by 1;
--       (null)     20464
--       approved       1
--
-- 20,464 of 20,465 suppliers carry no approval decision at all, and every one of them passed this
-- guard. That is this estate's "absent input scores as satisfied" again: the guard did not read the
-- column, so a supplier nobody had approved was indistinguishable from one somebody had.
--
-- THE ABSENT SUPPLIER WAS ANSWERED 'PASS'. The old body's first branch, when public.leads held no
-- row for new.supplier_id, published verdict PASS with the reason "this gate judges eligibility and
-- has no row". The insert is refused a moment later by inquiry_matches_supplier_id_fkey, so no row
-- landed -- but the VERDICT KEY the caller reads said PASS about a supplier that does not exist.
-- A gate that publishes PASS for a subject it could not find is stating something it did not
-- measure. It now publishes BLOCKED_MISSING_MATCH_EVIDENCE, which is what it actually knows, and
-- the foreign key remains the thing that stops the row.
--
-- WHAT IS NOT RENAMED, DELIBERATELY. BLOCKED_INELIGIBLE_SUPPLIER is the verdict K05 gave the
-- standing-bar cases and scripts/checks/phase_d_the_three_steps_that_had_no_effect.test.mjs already
-- asserts it by name. Approval is a different fact from a standing bar -- a supplier can be
-- perfectly eligible and simply not approved yet -- so it gets its own verdict,
-- BLOCKED_SUPPLIER_NOT_APPROVED, rather than being folded into a string that already means
-- something else. The vocabulary grows by one value; nothing existing changes meaning.
--
-- THE THREE APPROVAL STATES ARE DISTINGUISHED, because the 23 Aug hand-over recorded that BR-015
-- and GATE-014 "refuse pending, rejected and expired ALIKE and distinguish none of the three".
-- They still return one boolean each -- they are the rule and the gate, and their contract is a
-- verdict -- but the REASON this guard publishes now names which of the three it found, so the
-- correction owner is told what to correct.
--
-- REGISTRATION EXPIRY IS NOW READ. leads.registration_expires_at was read by no rule, no gate and
-- no trigger in the estate (measured 24 Aug 2026), so "expired" had no representation any of them
-- could see. It is a standing bar exactly like an expired licence and is judged with it.
--
-- WHY THIS DOES NOT MOVE THE PHASE D HEADLINE. The fixture scenario builds its supplier approved
-- and verified -- measured, supplier 48387, approval_status=approved, verified=true -- so W12-S06
-- keeps producing its declared effect. The guard gets stricter and the harness was already
-- building a supplier the business rules accept. If that had not been true the correct repair
-- would have been the fixture, not this guard.
--
-- CREATE OR REPLACE preserves the ACL, so no REVOKE belongs in this file.

CREATE OR REPLACE FUNCTION public.fn_unsafe_match_eligibility_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare l record; v_reason text; v_verdict text;
begin
  select id, company_name, banned, matching_blocked, permanently_closed, license_expiry,
         approval_status, verified, registration_expires_at
    into l from public.leads where id = new.supplier_id;

  if l.id is null then
    -- N01. The supplier is not on record. The old body published PASS here; a gate that cannot
    -- find its subject has measured nothing, and saying PASS about it is a claim, not a finding.
    -- inquiry_matches_supplier_id_fkey is what refuses the row; this is what tells the caller why.
    perform set_config('app.inquiry_match_gate_verdict', 'BLOCKED_MISSING_MATCH_EVIDENCE', true);
    perform set_config('app.inquiry_match_gate_reason',
      format('supplier %s is not in public.leads; eligibility cannot be judged against a supplier that does not exist',
             new.supplier_id), true);
    raise warning 'a00_unsafe_match_eligibility: BLOCKED_MISSING_MATCH_EVIDENCE — supplier % is not on record',
      new.supplier_id;
    return null;
  end if;

  -- (1) A STANDING BAR on the supplier: banned, blocked, closed, or a lapsed credential.
  v_reason := case
    when coalesce(l.banned,false)             then 'supplier is banned'
    when coalesce(l.matching_blocked,false)   then 'supplier is blocked from matching'
    when coalesce(l.permanently_closed,false) then 'supplier is permanently closed'
    when l.license_expiry is not null and l.license_expiry < current_date
                                              then 'supplier licence expired ' || l.license_expiry
    when l.registration_expires_at is not null and l.registration_expires_at < now()
                                              then 'supplier registration expired ' || l.registration_expires_at
    else null end;
  if v_reason is not null then
    v_verdict := 'BLOCKED_INELIGIBLE_SUPPLIER';
  else
    -- (2) APPROVAL, which is a different question from eligibility and was never asked here.
    --     The three states BR-015 and GATE-014 cannot tell apart are named separately.
    v_reason := case
      when coalesce(btrim(coalesce(l.approval_status,'')),'') = ''
        then 'supplier has no approval decision on record (pending)'
      when l.approval_status <> 'approved'
        then format('supplier approval_status is %s', l.approval_status)
      when not coalesce(l.verified,false)
        then 'supplier is approved but not verified'
      else null end;
    if v_reason is not null then
      v_verdict := 'BLOCKED_SUPPLIER_NOT_APPROVED';
    end if;
  end if;

  if v_reason is null then
    perform set_config('app.inquiry_match_gate_verdict', 'PASS', true);
    perform set_config('app.inquiry_match_gate_reason',
      format('supplier %s is approved, verified and eligible to receive a match', new.supplier_id), true);
    return new;
  end if;

  -- K05. A REFUSAL THAT STATES ITSELF. The ledger row below is the safety record; this is the
  -- verdict the writer and the caller read, on the same key the readiness gate publishes.
  perform set_config('app.inquiry_match_gate_verdict', v_verdict, true);
  perform set_config('app.inquiry_match_gate_reason',
    format('supplier %s: %s', new.supplier_id, v_reason), true);

  perform public.fn_unsafe_block(
    'ineligible_supplier_match', 'trigger:a00_unsafe_match_eligibility',
    'inquiry_matches', coalesce(new.inquiry_id::text,'') || '/' || new.supplier_id::text,
    'insert match row',
    jsonb_build_object('supplier_id', new.supplier_id, 'company', l.company_name,
                       'inquiry_id', new.inquiry_id, 'reason', v_reason, 'verdict', v_verdict));
  raise warning 'unsafe_block: refused match of inquiry % to supplier % — % (%)',
        new.inquiry_id, new.supplier_id, v_reason, v_verdict;
  return null;   -- row not inserted; the ledger row survives
end $function$;
