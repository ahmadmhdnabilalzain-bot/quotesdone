-- G04 — the rule about money was asking the register that does not model money
--
-- BR-033, frozen: "Unknown, conflicting or unreconciled monetary states are blocked/quarantined and
-- cannot be treated as success." Its implementation read the allowed_states of the
-- TRANSACTION_RECORD object family: open, pending, settled, refunded, failed, reconciled. The
-- money ladder public.phase_d_payment_state — what public.transactions.fee_status holds and what
-- BR-020 reads — is checkout_created, payment_initiated, provider_success, payment_confirmed,
-- payment_reconciled, reveal_authorized.
--
-- MEASURED: the two sets do not share a single value. W16-S01 refused with "monetary state
-- reveal_authorized matches 0 allowed state(s) of the TRANSACTION_RECORD object family", and
-- payment_reconciled — the founder-approved bar in BR-020 — would have refused the same way, while
-- 'settled' would have passed for a payment that never reconciled. Two rules about one transaction,
-- structurally unable to agree about any transaction.
--
-- The rule now reads the ladder, and reads authorizes_reveal for the "unreconciled" half of its own
-- frozen sentence. Strictly tighter: five words that say nothing about reconciliation stop passing,
-- and the two that mean reconciled start passing. public.phase_d_object_state_contract is NOT
-- amended — the founder's section 5 forbids putting reveal_authorized into the TRANSACTION_RECORD
-- family to make this rule green, and nothing here does.
--
-- One anchor, required to match exactly once. The rest of the routine is byte-identical.
CREATE OR REPLACE FUNCTION public.fn_phase_d_rule_check(p_rule_id text, p_context jsonb)
 RETURNS TABLE(state text, ok boolean, rule_type text, enforced boolean, reason text, refusal_code text, evidence_absent boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r public.phase_b_business_rule%rowtype;
  e public.phase_d_rule_enforcement%rowtype;
  v_missing text[]; v_n bigint; v_txt text; v_ok boolean; v_reason text;
  -- E30. A second count and a second string. A reference that must RESOLVE is two questions --
  -- is it shaped like the thing it claims to be, and does it name something that exists -- and
  -- more than once the answer lives in two relations.
  v_n2 bigint; v_txt2 text;
begin
  -- E19. FALSE UNLESS A BRANCH SAYS OTHERWISE. An OUT parameter left unset is NULL, and a null
  -- read as "not evidence-absent" by one caller and as "unknown" by another is how one column
  -- ends up meaning two things.
  evidence_absent := false;
  select * into r from public.phase_b_business_rule where rule_id = p_rule_id;
  if not found then
    state := 'NOT_IMPLEMENTED'; ok := false; rule_type := 'unknown'; enforced := false;
    reason := format('unknown business rule %s — fail closed', p_rule_id);
    refusal_code := 'unknown_rule'; return next; return;
  end if;
  rule_type := r.rule_type;

  select * into e from public.phase_d_rule_enforcement where rule_id = p_rule_id;
  if not found then
    state := 'NOT_IMPLEMENTED'; ok := false; enforced := false;
    reason := format('rule %s has no row in phase_d_rule_enforcement — fail closed rather than assume it is satisfied', p_rule_id);
    refusal_code := 'rule_unregistered'; return next; return;
  end if;
  refusal_code := e.refusal_code;
  enforced := (e.status = 'ENFORCED');

  -- ============================ the predicates ============================================
  -- Each reads the relation D2 bound for the object it governs. A rule whose evidence is absent
  -- REFUSES; it never passes for want of data.

  if p_rule_id in ('BR-001','BR-005') then
    v_ok := public.fn_phase_c_actor_may_own(p_context->>'accountable_role_id');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('%s: owner %s %s', p_rule_id, coalesce(p_context->>'accountable_role_id','(none)'),
                     case when v_ok then 'resolves to one active canonical role'
                          else 'does not resolve to an active canonical role' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-004' then
    v_ok := coalesce((select kind from public.fn_phase_c_resolve_actor(p_context->>'actor_role_id')),'') = 'canonical';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-004: actor %s %s', coalesce(p_context->>'actor_role_id','(none)'),
                     case when v_ok then 'is canonical' else 'is not canonical; aliases are input compatibility only' end);
    return next; return;
  end if;

  if p_rule_id in ('BR-002','BR-030','BR-031','BR-037','BR-038') then
    v_ok := public.fn_kernel_reviewer_independent(p_context->>'accountable_role_id', p_context->>'reviewer_role_id');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('%s: %s and %s %s', p_rule_id, coalesce(p_context->>'accountable_role_id','(none)'),
                     coalesce(p_context->>'reviewer_role_id','(none)'),
                     case when v_ok then 'are different effective identities'
                          else 'resolve to the same effective identity' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-048' then
    v_ok := not exists (select 1 from public.phase_c_overlay_binding ob
                         where ob.live_role_id = (select role_id from public.fn_phase_c_resolve_actor(p_context->>'actor_role_id')));
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then 'BR-048: the acting identity is not a category overlay'
                   else format('BR-048: %s is a category overlay and may not dispatch, approve suppliers, reveal identity or change policy',
                               p_context->>'actor_role_id') end;
    return next; return;
  end if;

  if p_rule_id in ('BR-053','BR-054') then
    v_ok := not coalesce((public.fn_kernel_paid_provider_gate('openai/gpt-4o-mini')->>'allowed')::boolean, true);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('%s: the paid-provider gate %s', p_rule_id,
                     case when v_ok then 'refuses a paid route' else 'ALLOWED a paid route' end);
    return next; return;
  end if;

  -- E28. BR-003 CHECKED THAT A KEY WAS PRESENT, NEVER THAT IT MEANT ANYTHING.
  -- It fell through to the generic CONTEXT_REQUIRED branch, whose whole test is "is the key present
  -- and non-empty". Measured 2026-08-20: BR-003 returned ENFORCED_PASS for
  -- founder_authority_ref = 'ZZ DEMO — founder_authority_ref for W16-S01', and for the single word
  -- 'banana'. A rule whose name is "founder-reserved decisions require founder authority" was
  -- satisfied by any non-empty string, which means the harness driving the workflow deliverable was
  -- forging founder authority and being told it had it. The founder's standing rule, written into
  -- this estate's own injected-defect catalogue, is that a fixture may never forge one.
  --
  -- The reference must now RESOLVE. 'founder_command:<id>' has to name a row in
  -- public.founder_command; nothing else is accepted, and the refusal says which of the two
  -- failures it is so a caller can tell "you named nothing" from "you named something that is not
  -- a founder decision". Fixing it here rather than in the harness closes it for every caller.
  if p_rule_id = 'BR-003' then
    v_txt := btrim(coalesce(p_context->>'founder_authority_ref',''));
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-003 requires [founder_authority_ref] and the call names none of it.';
      return next; return;
    end if;
    v_ok := exists (select 1 from public.founder_command fc
                     where 'founder_command:' || fc.command_id::text = v_txt);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok
                   then format('BR-003: %s resolves to a founder command on record', v_txt)
                   else format('BR-003: %s does not resolve to any row in public.founder_command. A founder-reserved decision needs the founder''s actual decision, not a string in its shape.', v_txt) end;
    return next; return;
  end if;

  if p_rule_id = 'BR-043' then
    -- E30. BR-043 REFUSED NOTHING, FOR TWO INDEPENDENT REASONS, AND BOTH HAD TO GO.
    -- (1) Applicability keyed on 'policy_exception', which is NOT in its required_context, so the
    --     rule was NOT_APPLICABLE on every call the estate actually makes -- including calls that
    --     named an exception authority.
    -- (2) The authority test was "is the string non-empty", so 'banana' authorised an exception.
    -- Bound, applicable and ACTUALLY REFUSES are three different questions. A brief and two
    -- audits named this rule as a blocker; it had only ever answered the first.
    v_txt  := btrim(coalesce(p_context->>'policy_exception',''));
    v_txt2 := btrim(coalesce(p_context->>'exception_authority_ref',''));
    if v_txt = '' and v_txt2 = '' then
      state := 'NOT_APPLICABLE'; ok := true;
      reason := 'BR-043: the call proposes no policy exception and names no exception authority, so there is no exception to authorise';
      return next; return;
    end if;
    if v_txt2 = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := format('BR-043: exception %s is proposed with no exception_authority_ref', v_txt);
      return next; return;
    end if;
    -- Does the exception reach founder-reserved subject matter? public.founder_reserved_decision
    -- carries the eleven decision keys and their match terms. That table is the boundary list;
    -- it is not a literal typed into this predicate, so the predicate follows it when it moves.
    select count(*) into v_n from public.founder_reserved_decision d
     where v_txt <> ''
       and (position(lower(replace(d.decision_key,'_',' ')) in lower(replace(v_txt,'_',' '))) > 0
            or exists (select 1 from unnest(d.match_any) t
                        where btrim(t) <> '' and position(lower(btrim(t)) in lower(v_txt)) > 0));
    -- The founder's own authority, resolved exactly as E28 resolved BR-003.
    v_n2 := case when exists (select 1 from public.founder_command fc
                               where 'founder_command:' || fc.command_id::text = v_txt2)
                 then 1 else 0 end;
    if v_n > 0 then
      -- "cannot bypass ... founder boundaries": a delegated authority is not enough here.
      v_ok := (v_n2 = 1);
      reason := format('BR-043: exception %s touches %s founder-reserved decision(s) and names authority %s, which %s',
                       v_txt, v_n, v_txt2,
                       case when v_ok then 'resolves to a founder command on record'
                            else 'does not resolve to any row in public.founder_command -- a delegated authority cannot clear a founder boundary' end);
    else
      v_ok := (v_n2 = 1)
              or exists (select 1 from public.employee_authority ea
                          where 'employee_authority:' || ea.agent_key || ':' || ea.action_class = v_txt2);
      reason := format('BR-043: exception %s names authority %s, which %s',
                       coalesce(nullif(v_txt,''),'(unnamed)'), v_txt2,
                       case when v_ok then 'resolves to a founder command or a granted employee authority'
                            else 'resolves to no row in public.founder_command or public.employee_authority' end);
    end if;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    return next; return;
  end if;

  if p_rule_id in ('BR-021','BR-022','BR-023','BR-024') then
    -- E31. THE SAME DEFECT E30 FOUND IN BR-043, IN THE FOUR RULES E29 HAD JUST FIXED.
    -- E29 made the AUTHORITY resolve, and that half holds. But applicability still keyed on
    -- 'commercial_policy_change', which is NOT in these rules' required_context -- all four
    -- declare only [founder_authority_ref]. So a call that named a founder authority and no
    -- commercial_policy_change was NOT_APPLICABLE, and the authority E29 taught the rule to
    -- resolve was never looked at. Measured after E30: feeding every rule 'banana' for each key
    -- it declares, BR-021..BR-024 were four of the five remaining passes, and all four passed as
    -- NOT_APPLICABLE rather than on the merits.
    --
    -- Bound, applicable and ACTUALLY REFUSES are three questions. E28 and E29 answered the third
    -- for these rules and left the second. A rule is now applicable when EITHER key is named: if
    -- a call in a founder-gated workflow asserts a founder authority, that assertion is judged.
    if coalesce(btrim(p_context->>'commercial_policy_change'),'') = ''
       and coalesce(btrim(p_context->>'founder_authority_ref'),'') = '' then
      state := 'NOT_APPLICABLE'; ok := true;
      reason := format('%s: the call proposes no change to a founder-reserved commercial term and asserts no founder authority', p_rule_id);
      return next; return;
    end if;
    -- E29. THE SAME DEFECT E28 FOUND IN BR-003, IN FOUR MORE RULES.
    -- This tested only that founder_authority_ref was non-empty, so BR-021 through BR-024 --
    -- the rules guarding founder-reserved COMMERCIAL terms -- returned ENFORCED_PASS for the
    -- literal string 'banana'. Measured 2026-08-20: 17 of the 30 rules that declare a
    -- required_context pass on that string. These four are the ones where the consequence is a
    -- forged founder decision on pricing, and they get the same resolution E28 gave BR-003.
    v_txt := btrim(coalesce(p_context->>'founder_authority_ref',''));
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := format('%s: change %s names no founder authority', p_rule_id,
                       coalesce(nullif(btrim(p_context->>'commercial_policy_change'),''),'(unnamed)'));
      return next; return;
    end if;
    v_ok := exists (select 1 from public.founder_command fc
                     where 'founder_command:' || fc.command_id::text = v_txt);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('%s: change %s %s', p_rule_id,
                     coalesce(nullif(btrim(p_context->>'commercial_policy_change'),''),'(unnamed)'),
                     case when v_ok then format('carries founder authority %s, which resolves to a founder command on record', v_txt)
                          else format('names %s, which does not resolve to any row in public.founder_command', v_txt) end);
    return next; return;
  end if;

  -- ---------------- BR-020: reveal only after reconciliation -------------------------------
  if p_rule_id = 'BR-020' then
    if p_context->>'transaction_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-020: no transaction_id in context. A reveal decision with no transaction to reconcile is refused.';
      return next; return;
    end if;
    -- Aliased for the same reason as the lookup inside fn_phase_d_reveal_permitted: this
    -- function's OUT parameter is also called `reason`, so an unqualified reference is ambiguous
    -- between the plpgsql variable and the callee's returned column.
    select rp.permitted, rp.reason into v_ok, v_reason
      from public.fn_phase_d_reveal_permitted(p_context->>'transaction_id') rp;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := v_reason;
    return next; return;
  end if;

  -- ---------------- the object-backed rules D2 unblocked -----------------------------------
  if p_rule_id = 'BR-011' then           -- no customer identity in a supplier-facing payload
    v_txt := coalesce(p_context->>'supplier_payload','');
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-011: no supplier_payload named. A payload nobody showed cannot be certified free of customer identity.';
      return next; return;
    end if;
    select count(*) into v_n from public.customers c
     where (coalesce(c.email,'') <> '' and position(lower(c.email) in lower(v_txt)) > 0)
        or (coalesce(c.phone,'') <> '' and position(c.phone   in v_txt) > 0)
        or (coalesce(c.full_name,'') <> '' and length(c.full_name) > 3
            and position(lower(c.full_name) in lower(v_txt)) > 0);
    -- The test is simply whether any customer identity appears in the payload. An earlier draft
    -- also ORed in a reveal_state check, which collapsed to the same expression under operator
    -- precedence and read as if it were doing something it was not.
    -- E30. I DID NOT CHANGE WHAT THIS RULE MEANS, BECAUSE ITS 'banana' PASS IS A TRUE PASS: the
    -- string 'banana' carries no customer identity, and BR-011 is a content test, not a reference
    -- test. What was wrong is that its only evidence source is a table held at zero. The row-match
    -- arm answers 0 for every payload ever shown to it, and 0 is also what it would answer if it
    -- were broken. So the SHAPE is tested too: a supplier-facing payload carrying an email address
    -- or a dialable UAE mobile is a customer identity leak whether or not that person is a row in
    -- this estate yet.
    v_txt2 := regexp_replace(v_txt, '[^0-9]', '', 'g');
    v_n2 := (case when v_txt ~* '[A-Z0-9._%+-]+@[A-Z0-9.-]+[.][A-Z]{2,}' then 1 else 0 end)
          + (case when v_txt2 ~ '(971|0)5[0-9]{8}' then 1 else 0 end);
    v_ok := (v_n = 0 and v_n2 = 0);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-011: %s customer identity match(es) over %s customer row(s) searched for email, phone and full name, and %s identity-shaped token(s) -- an email address or a UAE mobile -- found in the payload itself',
                     v_n, (select count(*) from public.customers), v_n2);
    return next; return;
  end if;

  if p_rule_id = 'BR-012' then           -- an approved immutable supplier-safe package exists
    -- E30. This asked only whether two strings were non-empty, so 'banana' approved by 'banana'
    -- was an approved immutable supplier-safe package. supplier_safe_package is a REGISTERED
    -- business object of the IMMUTABLE_REVISION family: the ref must name one of those records in
    -- the approved state, and the approver must be someone who may own work here.
    v_txt  := btrim(coalesce(p_context->>'safe_package_ref',''));
    v_txt2 := btrim(coalesce(p_context->>'safe_package_approved_by',''));
    if v_txt = '' or v_txt2 = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-012: no approved supplier-safe package named, or no approver named. No assignment or notification may be created without one.';
      return next; return;
    end if;
    select count(*) into v_n from public.phase_d_object_record o
     where o.object_id = 'supplier_safe_package' and o.state = 'approved' and o.superseded_by is null
       and (o.business_key = v_txt or 'supplier_safe_package:' || o.business_key = v_txt);
    v_ok := (v_n >= 1) and public.fn_phase_c_actor_may_own(v_txt2);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-012: package %s resolves to %s approved supplier_safe_package record(s) in public.phase_d_object_record, and approver %s %s',
                     v_txt, v_n, v_txt2,
                     case when public.fn_phase_c_actor_may_own(v_txt2)
                          then 'resolves to an active canonical role'
                          else 'does not resolve to an active canonical role' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-013' then           -- the inquiry is quote-ready
    if p_context->>'inquiry_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-013: no inquiry_id named; readiness cannot be measured against nothing.';
      return next; return;
    end if;
    select count(*) into v_n from public.inquiries i
     where i.id::text = p_context->>'inquiry_id'
       and coalesce(i.status,'') in ('quote_ready','dispatched','quoted','completed');
    v_ok := (v_n = 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-013: inquiry %s %s', p_context->>'inquiry_id',
                     case when v_ok then 'is in a quote-ready state'
                          else 'is not quote-ready; mandatory qualification, route or document blockers remain' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-014' then           -- only a CONFIRMED route authorises dispatch
    v_ok := lower(coalesce(btrim(p_context->>'route_state'),'')) = 'confirmed';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-014: route state %s. Proposed, ambiguous, rejected and excluded routes cannot authorise dispatch.',
                     coalesce(nullif(btrim(p_context->>'route_state'),''),'(unstated)'));
    return next; return;
  end if;

  if p_rule_id = 'BR-015' then           -- only an approved, eligible supplier is dispatched to
    if p_context->>'supplier_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-015: no supplier_id named.'; return next; return;
    end if;
    select count(*) into v_n from public.leads l
     where l.id::text = p_context->>'supplier_id'
       and coalesce(l.approval_status,'') = 'approved' and coalesce(l.verified,false);
    v_ok := (v_n = 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-015: supplier %s %s. public.leads already enforces approved implies verified as a CHECK constraint.',
                     p_context->>'supplier_id',
                     case when v_ok then 'is approved and verified' else 'is not an approved, verified supplier' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-016' then           -- one assignment per supplier per inquiry version
    if p_context->>'inquiry_id' is null or p_context->>'supplier_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-016: inquiry_id and supplier_id are both required to decide duplicate assignment.';
      return next; return;
    end if;
    select count(*) into v_n from public.inquiry_matches m
     where m.inquiry_id::text = p_context->>'inquiry_id'
       and m.supplier_id::text = p_context->>'supplier_id';
    v_ok := (v_n <= 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-016: %s existing assignment(s) for that supplier and inquiry. NOTE: public.inquiry_matches carries no version column and no unique constraint, so this is enforced here and NOT structurally — recorded as the D2 REPAIR on supplier_assignment.', v_n);
    return next; return;
  end if;

  if p_rule_id = 'BR-017' then           -- a refused assignment is not a contact
    v_ok := lower(coalesce(btrim(p_context->>'assignment_result'),'')) in ('delivered','accepted','sent');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-017: assignment result %s. Refused and failed assignments are not counted as contacted and create no success notification.',
                     coalesce(nullif(btrim(p_context->>'assignment_result'),''),'(unstated)'));
    return next; return;
  end if;

  if p_rule_id = 'BR-018' then           -- the supplier's own revision is never platform-edited
    v_ok := coalesce(btrim(p_context->>'quote_revision_ref'),'') <> ''
            and coalesce(p_context->>'platform_edited','true') = 'false';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-018: revision %s is supplier-authored and unedited; normalisation is separate',
                                         p_context->>'quote_revision_ref')
                   else 'BR-018: no unedited supplier revision named. The platform may normalise for comparison but never alter the original.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-019' then           -- a customer sees only their own published comparison
    if p_context->>'comparison_id' is null or p_context->>'caller_customer_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-019: comparison_id and caller_customer_id are both required.'; return next; return;
    end if;
    select count(*) into v_n from public.quote_comparisons qc
     where qc.id::text = p_context->>'comparison_id'
       and qc.customer_id::text = p_context->>'caller_customer_id';
    v_ok := (v_n = 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-019: comparison %s %s the calling customer', p_context->>'comparison_id',
                     case when v_ok then 'belongs to' else 'does NOT belong to' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-025' then           -- acceptance names the exact version and hash
    -- E30. "the exact displayed version AND hash" was tested as "two non-empty strings", so
    -- 'banana' was an exact hash of version 'banana'. public.legal_documents holds the displayed
    -- documents and their versions. The hash must be a real SHA-256 digest, and it must be the
    -- digest OF THAT DOCUMENT AT THAT VERSION -- a hash that matches nothing is not a reference
    -- to anything specific, which is the whole of what this rule asks for.
    v_txt  := btrim(coalesce(p_context->>'terms_version',''));
    v_txt2 := lower(btrim(coalesce(p_context->>'terms_hash','')));
    if v_txt = '' or v_txt2 = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-025: acceptance must reference the exact displayed version AND hash; one without the other is not an acceptance of anything specific.';
      return next; return;
    end if;
    if v_txt2 !~ '^[0-9a-f]{64}$' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := format('BR-025: terms_hash %s is not a SHA-256 digest (64 hexadecimal characters), so it was never computed over the displayed terms.',
                       left(v_txt2, 24));
      return next; return;
    end if;
    select count(*) into v_n from public.legal_documents d
     where d.version = v_txt
       and encode(sha256(convert_to(coalesce(d.body_html,''), 'UTF8')), 'hex') = v_txt2;
    v_ok := (v_n >= 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-025: acceptance names version %s at digest %s, which matches %s row(s) in public.legal_documents whose displayed body hashes to exactly that digest',
                     v_txt, left(v_txt2, 12), v_n);
    return next; return;
  end if;

  if p_rule_id = 'BR-026' then           -- no certificate before an acceptance record
    -- E30. The reason string read "acceptance record %s exists" while the predicate had only
    -- checked that a string was non-empty -- evidence stating the premise it never tested.
    -- customer_terms_acceptance and supplier_terms_acceptance are registered APPEND_ONLY business
    -- objects; the ref must name one of those records.
    v_txt := btrim(coalesce(p_context->>'acceptance_ref',''));
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-026: no acceptance record named. A certificate generated before acceptance would assert a fact that has not happened.';
      return next; return;
    end if;
    select count(*) into v_n from public.phase_d_object_record o
     where o.object_id in ('customer_terms_acceptance','supplier_terms_acceptance')
       and (o.business_key = v_txt or o.object_id || ':' || o.business_key = v_txt);
    v_ok := (v_n >= 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-026: acceptance_ref %s resolves to %s terms-acceptance record(s) in public.phase_d_object_record. A certificate may not precede one.',
                     v_txt, v_n);
    return next; return;
  end if;

  if p_rule_id = 'BR-029' then           -- conflicting evidence is preserved, not overwritten
    -- E30. Two arms, both weak. conflict_preserved='true' was the CALLER asserting its own
    -- compliance, which is not evidence of it; and evidence_authority was tested for
    -- non-emptiness, so 'banana' was an authority ranking. This rule is about RANK -- lower
    -- authority may not overwrite higher -- and this estate has a ranking:
    -- public.mep_evidence_weight, with its weight keys, evidence sources and source authorities.
    -- An authority that is not in the ranking cannot be ordered against another, so it cannot be
    -- preserved against one either.
    v_txt := btrim(coalesce(p_context->>'evidence_authority',''));
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-029: no evidence authority named. Lower-authority evidence may not silently overwrite higher, and an unranked authority cannot be ordered against any other.';
      return next; return;
    end if;
    select count(*) into v_n from public.mep_evidence_weight w
     where w.weight_key = v_txt or w.evidence_source = v_txt or w.source_authority = v_txt;
    v_ok := (v_n >= 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-029: evidence authority %s matches %s row(s) in the public.mep_evidence_weight ranking (weight_key, evidence_source or source_authority)%s',
                     v_txt, v_n,
                     case when v_ok then ', so conflicting evidence can be retained in rank order'
                          else ' -- it is not a ranked authority in this estate' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-032' then           -- provider events are unique and replay-safe
    if coalesce(btrim(p_context->>'provider_event_id'),'') = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-032: no provider_event_id named; duplicate delivery cannot be decided without one.';
      return next; return;
    end if;
    -- E30. THE TEST WAS "appears AT MOST once", so an event id appearing ZERO times satisfied a
    -- rule about the safety of REAL provider events -- one never delivered, or the literal
    -- 'banana'. Zero cannot tell an unknown event from a safe one. It must resolve to EXACTLY ONE
    -- recorded delivery, in the provider event log or in the registered provider_event object.
    v_txt := btrim(coalesce(p_context->>'provider_event_id',''));
    select count(*) into v_n  from public.stripe_events se where se.event_id = v_txt;
    select count(*) into v_n2 from public.phase_d_object_record o
     where o.object_id = 'provider_event'
       and (o.business_key = v_txt or 'provider_event:' || o.business_key = v_txt);
    v_ok := (v_n + v_n2) = 1;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-032: provider event %s resolves to %s row(s) in public.stripe_events and %s registered provider_event record(s). Exactly one is replay-safe: zero is an event nobody received, more than one is a duplicate.',
                     v_txt, v_n, v_n2);
    return next; return;
  end if;

  if p_rule_id = 'BR-033' then           -- unknown money is quarantined, never success
    -- E30. A DENY-LIST OF THREE WORDS LEFT EVERY OTHER STRING AS A GOOD MONETARY STATE. The
    -- acceptance audit watched the harness hand this rule 'checkout_created' and get ok=true;
    -- 'banana' did just as well. An unrecognised monetary state IS an unknown one, which is
    -- precisely what this rule exists to quarantine. The permitted set is read from the state
    -- contracts of the TRANSACTION_RECORD family -- the money-carrying objects -- and not typed
    -- in here, so it follows the registry instead of drifting from it.
    -- G04. THE RULE ABOUT MONEY WAS ASKING THE REGISTER THAT DOES NOT MODEL MONEY.
    --
    -- E30 corrected a deny-list of three words by reading the allowed_states of the
    -- TRANSACTION_RECORD family, which was right about the method and wrong about the register.
    -- Two vocabularies describe a transaction in this estate:
    --
    --   public.phase_d_object_state_contract  open, pending, settled, refunded, failed, reconciled
    --       the generic OBJECT-RECORD lifecycle, derived from policy_family and applied identically
    --       to dispatch_batch, payment_transaction, reveal_transaction and supplier_assignment.
    --   public.phase_d_payment_state          checkout_created, payment_initiated, provider_success,
    --       payment_confirmed, payment_reconciled, reveal_authorized -- a SIX-RUNG LADDER, each rung
    --       carrying authorizes_reveal and a stated reason, and it is what public.transactions
    --       .fee_status actually holds and what BR-020 reads.
    --
    -- MEASURED: the intersection of those two sets is EMPTY. Not "different in places" -- no value
    -- appears in both. So BR-033 refused every real monetary state this estate can produce,
    -- including payment_reconciled, the founder-approved bar in BR-020, and would have PASSED
    -- 'settled' or 'refunded' for a payment that never reconciled. Two rules about one transaction,
    -- unable to agree about any transaction, because one of them was reading the wrong register.
    --
    -- THE FROZEN TEXT DECIDES WHICH REGISTER IS RIGHT: "Unknown, conflicting or unreconciled
    -- monetary states are blocked/quarantined and cannot be treated as success." Recognised, and
    -- reconciled. The ladder is the register of recognised monetary states and authorizes_reveal is
    -- the ladder's own mark for the reconciled rungs, so both halves of the frozen sentence are
    -- read from the register that states them.
    --
    -- THIS IS STRICTLY TIGHTER THAN WHAT IT REPLACES, and that is the test of it. Before: five
    -- words passed that say nothing about reconciliation. After: an unrecognised state is refused
    -- as unrecognised, a recognised state below reconciliation is refused as unreconciled, and the
    -- three quarantine words are refused by name as they always were. Only payment_reconciled and
    -- reveal_authorized pass, which is the relationship the founder's section 5 asked BR-020 and
    -- BR-033 to evaluate between them.
    --
    -- public.phase_d_object_state_contract IS NOT AMENDED. The founder's section 5 forbids putting
    -- reveal_authorized into the TRANSACTION_RECORD family to make this rule green, and nothing
    -- here does: the family keeps the generic lifecycle it describes, and this rule stops asking
    -- it a question it was never the register for.
    v_txt := lower(coalesce(btrim(p_context->>'monetary_state'),''));
    select count(*) into v_n
      from public.phase_d_payment_state ps
     where lower(ps.state_key) = v_txt and ps.authorizes_reveal;
    v_ok := v_txt <> '' and v_txt not in ('unknown','conflicting','unreconciled') and v_n >= 1;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-033: monetary state %s matches %s reconciled rung(s) of the payment ladder public.phase_d_payment_state (%s of its %s rungs are reconciled: %s). Unknown, conflicting, unreconciled and unrecognised states are blocked and quarantined, never treated as success.',
                     coalesce(nullif(v_txt,''),'(unstated)'), v_n,
                     (select count(*) from public.phase_d_payment_state where authorizes_reveal),
                     (select count(*) from public.phase_d_payment_state),
                     (select string_agg(ps2.state_key, ', ' order by ps2.rung)
                        from public.phase_d_payment_state ps2 where ps2.authorizes_reveal));
    return next; return;
  end if;

  if p_rule_id = 'BR-034' then           -- consent and suppression are respected
    if coalesce(btrim(p_context->>'notify_email'),'') = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-034: no notify_email named; consent cannot be decided for an unnamed recipient.';
      return next; return;
    end if;
    -- E30. 'banana' is not in the suppression list, so 'banana' was a consenting recipient. A
    -- string that cannot be an email address cannot have been checked for consent: it has to be
    -- an address before the suppression lookup means anything at all.
    v_txt := btrim(coalesce(p_context->>'notify_email',''));
    if v_txt !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+[.][A-Z]{2,}$' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := format('BR-034: %s is not an email address, so no consent or suppression decision about it exists to respect.', v_txt);
      return next; return;
    end if;
    select count(*) into v_n from public.email_suppressions s
     where lower(s.email) = lower(v_txt);
    v_ok := (v_n = 0);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-034: %s is %s in public.email_suppressions (%s matching row(s) over %s suppression(s) on record)',
                     v_txt,
                     case when v_ok then 'not suppressed' else 'SUPPRESSED and must not be contacted' end,
                     v_n, (select count(*) from public.email_suppressions));
    return next; return;
  end if;

  if p_rule_id = 'BR-035' then           -- only the approved revision publishes
    -- E30. Feeding the same junk string to both keys satisfied this rule, because equality of two
    -- unresolved strings is not evidence that either names an approved revision. The approved ref
    -- must resolve to an IMMUTABLE_REVISION business object record in the approved state -- the
    -- estate's own registry of revisions -- and the revision being published must be that one.
    v_txt  := btrim(coalesce(p_context->>'approved_revision_ref',''));
    v_txt2 := btrim(coalesce(p_context->>'publishing_revision_ref',''));
    if v_txt = '' or v_txt2 = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-035: the revision being published is not the independently approved revision, or neither was named.';
      return next; return;
    end if;
    if v_txt <> v_txt2 then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := format('BR-035: the publishing revision %s is not the approved revision %s', v_txt2, v_txt);
      return next; return;
    end if;
    select count(*) into v_n from public.phase_d_object_record o
      join public.phase_d_object_state_contract c on c.object_id = o.object_id
     where c.policy_family = 'IMMUTABLE_REVISION' and o.state = 'approved'
       and (o.business_key = v_txt or o.object_id || ':' || o.business_key = v_txt);
    v_ok := (v_n >= 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-035: the publishing revision is the approved one (%s), and that reference resolves to %s approved IMMUTABLE_REVISION record(s) in public.phase_d_object_record',
                     v_txt, v_n);
    return next; return;
  end if;

  if p_rule_id = 'BR-036' then           -- review inspects the artifact, not the brief
    -- E30. The acceptance audit caught this one from the other end: it read back
    -- "review names artifact ZZ DEMO - artifact_ref at digest ZZ DEMO - artifact_sha256" and got
    -- ok=true. A SHA-256 is 64 hexadecimal characters; a value that is not one was never computed
    -- over any artifact. And the digest must be OF something -- an artifact_review row, or a
    -- business object record carrying it. In an estate whose vision model once listed eight
    -- identifiers verbatim from a solid black rectangle, the digest is the only part of an
    -- artifact review that cannot be imagined.
    v_txt  := btrim(coalesce(p_context->>'artifact_ref',''));
    v_txt2 := lower(btrim(coalesce(p_context->>'artifact_sha256','')));
    if v_txt = '' or v_txt2 = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-036: the review names no artifact and digest. A verifier that reads the brief instead of the artifact has already produced a false pass in this estate.';
      return next; return;
    end if;
    if v_txt2 !~ '^[0-9a-f]{64}$' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := format('BR-036: artifact_sha256 %s is not a SHA-256 digest (64 hexadecimal characters), so it was not computed over any artifact.',
                       left(v_txt2, 24));
      return next; return;
    end if;
    select count(*) into v_n  from public.artifact_review ar where lower(ar.artifact_sha256) = v_txt2;
    select count(*) into v_n2 from public.phase_d_object_record o
     where lower(o.payload->>'artifact_sha256') = v_txt2;
    v_ok := (v_n + v_n2) >= 1;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-036: review names artifact %s at digest %s, which resolves to %s artifact_review row(s) and %s business object record(s) carrying exactly that digest',
                     v_txt, left(v_txt2, 12), v_n, v_n2);
    return next; return;
  end if;

  if p_rule_id = 'BR-039' then           -- a release needs an executable rollback
    -- E30. The rule says DEFINED AND EXECUTABLE; the predicate tested only that a string had been
    -- typed, so 'banana' was an executable rollback path. Executable means the estate can name the
    -- thing that would run: a registered action class carrying a compensating action, or a routine
    -- that exists in this database.
    v_txt := btrim(coalesce(p_context->>'rollback_ref',''));
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-039: no rollback or recovery path named. A consequential release without one is not approvable.';
      return next; return;
    end if;
    select count(*) into v_n from public.org_action_executor x
     where x.action_class = v_txt and coalesce(btrim(x.compensation_action_class),'') <> '';
    select count(*) into v_n2 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = regexp_replace(v_txt, '^public[.]', '');
    v_ok := (v_n + v_n2) >= 1;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-039: rollback path %s resolves to %s registered action class(es) carrying a compensating action and %s routine(s) in this database%s',
                     v_txt, v_n, v_n2,
                     case when v_ok then '' else ' -- nothing that could be executed to undo the release' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-041' then           -- activity is not outcome
    -- E30. "when a business outcome is DEFINED" was tested as "a string was typed that differs
    -- from the activity metric", so 'banana' was a business outcome. public.metric_definition IS
    -- this estate's register of defined metrics. A metric that is not in it has not been defined,
    -- and success declared on it is exactly the vanity claim this rule forbids.
    v_txt  := btrim(coalesce(p_context->>'outcome_metric',''));
    v_txt2 := coalesce(p_context->>'activity_metric','');
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-041: no business outcome metric named.';
      return next; return;
    end if;
    if v_txt = v_txt2 then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := format('BR-041: the declared outcome metric %s IS the activity metric under another name', v_txt);
      return next; return;
    end if;
    select count(*) into v_n from public.metric_definition m where m.metric_key = v_txt;
    v_ok := (v_n = 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-041: success is declared on outcome metric %s, distinct from the activity metric, and that key resolves to %s row(s) in public.metric_definition (of %s defined metrics)',
                     v_txt, v_n, (select count(*) from public.metric_definition));
    return next; return;
  end if;

  if p_rule_id = 'BR-049' then           -- inquiry accountability does not drift
    v_ok := coalesce(btrim(p_context->>'inquiry_owner'),'') = 'rfq_qualification_manager'
            or coalesce(btrim(p_context->>'accountability_transfer_approved'),'') = 'true';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-049: inquiry owner is %s. Specialist and document handoffs do not move overall inquiry accountability away from rfq_qualification_manager without an approved workflow that says so.',
                     coalesce(nullif(btrim(p_context->>'inquiry_owner'),''),'(unstated)'));
    return next; return;
  end if;

  -- ---------------- D47. FIVE RULES THAT NOW DECIDE FOR THEMSELVES --------------------------
  -- BR-027, BR-040 and BR-042 were SCHEMA_ENFORCED fall-throughs returning ENFORCED_PASS with the
  -- reason "is enforced ... later in this same call". True, and useless: the schema they deferred
  -- to checked presence and emptiness only, so none of the three could refuse anything. D46 gave
  -- the validator declared types and domains; these three read the same facts directly.

  if p_rule_id = 'BR-027' then           -- a finding names the evidence it rests on
    v_ok := jsonb_typeof(p_context->'evidence_refs') = 'array'
            and jsonb_array_length(coalesce(p_context->'evidence_refs','[]'::jsonb)) > 0;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-027: %s evidence reference(s) named',
                                         jsonb_array_length(p_context->'evidence_refs'))
                   else 'BR-027: no evidence_refs array. A finding that names no evidence is an assertion.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-040' then           -- a ratio states its formula and its denominator
    -- THE DENOMINATOR IS TYPED HERE, not merely present. jsonb_typeof('"0"') is 'string', so a
    -- denominator of "0" as text satisfied every presence check in this estate and still divided
    -- something by nothing. least(100, NULL) = 100 is the same defect in another costume.
    v_ok := coalesce(btrim(p_context->>'formula'),'') <> ''
            and jsonb_typeof(p_context->'denominator') = 'number'
            and (p_context->>'denominator')::numeric > 0;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-040: formula %L over a numeric denominator of %s',
                                         p_context->>'formula', p_context->>'denominator')
                   else format('BR-040: formula %L, denominator %s of type %s. A ratio needs a stated formula and a numeric denominator greater than zero.',
                               coalesce(p_context->>'formula','(none)'),
                               coalesce(p_context->>'denominator','(none)'),
                               coalesce(jsonb_typeof(p_context->'denominator'),'absent')) end;
    return next; return;
  end if;

  if p_rule_id = 'BR-042' then           -- an analysis states its assumptions
    -- AND THEY MAY NOT BE THE ONES THE EXECUTOR WRITES FOR ITSELF. fn_phase_d_handler_execute
    -- writes ANALYSIS_HANDLER's assumptions unconditionally as the fixed one-element literal
    -- 'only the inputs named in this call were used; no external source was consulted'. A rule
    -- satisfied by a constant its own caller supplies is a rule that cannot fail, so that exact
    -- value is refused by name.
    v_ok := jsonb_typeof(p_context->'assumptions') = 'array'
            and jsonb_array_length(coalesce(p_context->'assumptions','[]'::jsonb)) > 0
            and p_context->'assumptions' <> jsonb_build_array(
                  'only the inputs named in this call were used; no external source was consulted');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-042: %s assumption(s) stated',
                                         jsonb_array_length(p_context->'assumptions'))
                   when p_context->'assumptions' = jsonb_build_array(
                          'only the inputs named in this call were used; no external source was consulted')
                     then 'BR-042: the only assumption stated is the executor''s own boilerplate. A constant the caller writes for itself is not a stated assumption.'
                   else 'BR-042: no assumptions array. An analysis that states no assumptions has hidden them.' end;
    return next; return;
  end if;

  -- D51. BR-008 HAD ITS PREDICATE REMOVED AGAIN, AND THE REGISTRY WAS RIGHT THE FIRST TIME.
  -- D47 gave it one because fn_phase_d_handoff_packet_valid is STABLE and therefore callable.
  -- Callable is not the same as answerable HERE. The packet is what the SENDING STEP PRODUCES;
  -- at the moment fn_phase_d_rule_check runs — the step has just opened and nobody has done it —
  -- the packet does not exist yet. So the predicate refused 29 of 30 first steps, then 15 of 30
  -- once the applicability rule was added, and every one of those refusals was the rule being
  -- asked a question the lifecycle had not reached.
  --
  -- Its enforcement_kind was KERNEL_ENFORCED for exactly that reason: the kernel checks the packet
  -- when the handoff is accepted, which is when there is one to check. It falls through to the
  -- delegated branch below, where it is honestly labelled rather than given a pass or a refusal it
  -- has not earned. BR-044 keeps its predicate: an SLA due time IS computable when the step opens.
  if p_rule_id = 'BR-044' then           -- an SLA has a computable due time
    if coalesce(btrim(p_context->>'sla_policy_id'),'') = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-044: no sla_policy_id named, so no due time can be computed.';
      return next; return;
    end if;
    -- D51. THE DELEGATE DEFAULTS, SO "is not null" COULD NEVER FAIL. fn_kernel_sla_due ends in
    -- coalesce(<the policy lookup>, 24), so an sla_policy_id that exists nowhere silently gets a
    -- 24-hour deadline and a non-null answer. Measured: fn_kernel_sla_due('zz-demo-no-such-policy')
    -- returns a timestamp 24 hours out. The predicate therefore asks the question the default hides:
    -- is this policy REGISTERED, and does it then compute a due time. The 24-hour fallback lives in
    -- a frozen kernel routine and is not changed here; it is named so it can be seen.
    v_ok := exists (select 1 from public.phase_b_sla_policy sp
                     where sp.sla_policy_id = p_context->>'sla_policy_id')
            and public.fn_kernel_sla_due(p_context->>'sla_policy_id', now()) is not null;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-044: policy %s resolves to a due time',
                                         p_context->>'sla_policy_id')
                   else format('BR-044: policy %L computes no due time', p_context->>'sla_policy_id') end;
    return next; return;
  end if;
  -- ---------------- structurally enforced elsewhere ----------------------------------------
  if e.enforcement_kind in ('SCHEMA_ENFORCED','EXECUTOR_ENFORCED') then
    state := 'ENFORCED_PASS'; ok := true;
    reason := format('%s is enforced at %s later in this same call, which refuses with %s',
                     p_rule_id, e.enforcement_point, e.refusal_code);
    return next; return;
  end if;
  if e.enforcement_kind in ('KERNEL_ENFORCED','TRIGGER_ENFORCED') then
    -- D47. THIS USED TO SAY ENFORCED_PASS, AND THE PLAN ASKED FOR THE DELEGATE TO BE INVOKED
    -- INSTEAD. Measured, that is possible for two of these and impossible for the other eleven:
    --
    --   BR-006 BR-007 BR-009 BR-045  public.fn_kernel_step_complete(jsonb)  VOLATILE SECDEF, writes
    --   BR-046                       public.fn_kernel_cancel(jsonb)         VOLATILE SECDEF, writes
    --   BR-010                       public.fn_phase_c_trace_append_only()  returns trigger
    --   BR-047                       public.fn_org_authority_guard()        returns trigger
    --   BR-050 BR-051 BR-052         public.fn_kernel_write_guard()         returns trigger
    --
    -- A routine returning trigger cannot be called at all, and a volatile writer cannot be called
    -- from this STABLE predicate without performing the very act it is being asked about. BR-008
    -- and BR-044 CAN be called, and now are, above.
    --
    -- So these get a state of their own rather than a pass they did not earn. Nothing about the
    -- runtime changes: fn_phase_d_handler_execute refuses on ENFORCED_FAIL and NOT_IMPLEMENTED, and
    -- DELEGATED_TO_KERNEL_GUARD is neither. What changes is the count that may be claimed. A rule
    -- enforced by a guard this call never reaches is not a rule this predicate enforces.
    state := 'DELEGATED_TO_KERNEL_GUARD'; ok := true;
    reason := format('%s is enforced at %s, which raises %s. That routine %s, so this predicate cannot invoke it: the guard decides and this call does not.',
                     p_rule_id, e.enforcement_point, e.refusal_code,
                     case when e.enforcement_kind = 'TRIGGER_ENFORCED'
                          then 'returns trigger' else 'is a volatile writer' end);
    return next; return;
  end if;
  if e.enforcement_kind = 'CONTEXT_REQUIRED' then
    select array_agg(k order by k) into v_missing
      from unnest(e.required_context) k
     where not (p_context ? k) or coalesce(btrim(p_context->>k),'') = '';
    v_ok := (v_missing is null);
    -- E19. THE REFUSAL STANDS; ONLY ITS NAME CHANGES. This branch fires when the call names none of
    -- the evidence the rule reads, which is not the same event as the rule reading that evidence and
    -- finding it violates policy. Both refuse. The state stays ENFORCED_FAIL so that every existing
    -- reader -- fn_phase_d_handler_execute, fn_phase_d_rule_can_refuse, fn_phase_d_rule_state --
    -- behaves exactly as before; evidence_absent is the new fact, and it is what lets
    -- fn_phase_d_dispatch_step record REFUSED_EVIDENCE_ABSENT instead of REFUSED. A reader could
    -- previously take an absence of evidence for a business violation, and the 2026-08-20
    -- acceptance audit did exactly that and said so in finding 3.
    evidence_absent := not v_ok;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('%s: the call names %s', p_rule_id, array_to_string(e.required_context,', '))
                   else format('%s requires [%s] and the call names none of it.', p_rule_id, array_to_string(v_missing,', ')) end;
    return next; return;
  end if;

  -- ---------------- NO PREDICATE. This is the answer that used to be `true`. ----------------
  state := 'NOT_IMPLEMENTED'; ok := false; enforced := false;
  reason := format('%s has no predicate in fn_phase_d_rule_check. NOT_IMPLEMENTED is not a pass.', p_rule_id);
  refusal_code := coalesce(e.refusal_code, 'rule_not_implemented');
  return next;
end $function$

