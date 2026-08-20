-- E28 — BR-003 checked that a key was present, never that it meant anything
--
-- The R4 independent acceptance failed Gate 3 on this, and it is the most serious thing found in
-- this whole branch. Its measurement, which I reproduced and then made worse:
--
--   fn_phase_d_rule_check('BR-003', {'founder_authority_ref':'ZZ DEMO — founder_authority_ref for W16-S01'})
--     -> ENFORCED_PASS, "BR-003: the call names founder_authority_ref"
--   fn_phase_d_rule_check('BR-003', {'founder_authority_ref':'banana'})
--     -> ENFORCED_PASS
--
-- BR-003 is "founder-reserved decisions require an explicit founder authority". It had no predicate
-- of its own and fell through to the generic CONTEXT_REQUIRED branch, whose entire test is whether
-- the key is present and non-empty. So the rule was satisfied by ANY non-empty string, and
-- fn_phase_d_drive_workflow — the harness behind PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv — was
-- supplying exactly such a string and being told it had founder authority.
--
-- That is forging the founder's decision, and this estate wrote the standard against it itself:
-- PHASE_D_INJECTED_DEFECT_RESULT.csv records, as the blocker on an untested defect, "needs a
-- committed founder decision row to attempt to rewrite. A fixture may never forge one (his standing
-- rule)." The harness was doing the thing the catalogue says may never be done, and the check waved
-- it through.
--
-- I reported 139 business effects and 12 of 30 workflows reaching closure from that harness as
-- progress. Those numbers are fixture output produced under forged authority and I should not have
-- quoted them. The kernel-path number never moved: 254 dispatches, 2 EXECUTED.
--
-- THE FIX IS AT THE CHECK, NOT AT THE HARNESS, because the harness is not the only caller and a
-- rule that can be satisfied by a string is broken for all of them. The reference must RESOLVE:
-- 'founder_command:<id>' has to name a row in public.founder_command. The refusal distinguishes
-- "you named nothing" from "you named something that is not a founder decision", because those are
-- different mistakes.
--
-- This makes Gate 3 HARDER, and it should: steps that appeared to pass BR-003 on a fixture will now
-- refuse. That is the correct direction. A pass bought with a forged authority was never a pass.
--
-- CREATE OR REPLACE preserves the ACL.

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
    if coalesce(btrim(p_context->>'policy_exception'),'') = '' then
      state := 'NOT_APPLICABLE'; ok := true;
      reason := 'BR-043: the call proposes no policy exception, so there is no exception to authorise';
      return next; return;
    end if;
    v_ok := coalesce(btrim(p_context->>'exception_authority_ref'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-043: exception %s %s', p_context->>'policy_exception',
                     case when v_ok then 'carries an authority reference'
                          else 'is proposed with no exception_authority_ref' end);
    return next; return;
  end if;

  if p_rule_id in ('BR-021','BR-022','BR-023','BR-024') then
    if coalesce(btrim(p_context->>'commercial_policy_change'),'') = '' then
      state := 'NOT_APPLICABLE'; ok := true;
      reason := format('%s: the call proposes no change to a founder-reserved commercial term', p_rule_id);
      return next; return;
    end if;
    v_ok := coalesce(btrim(p_context->>'founder_authority_ref'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('%s: change %s %s', p_rule_id, p_context->>'commercial_policy_change',
                     case when v_ok then 'carries founder authority' else 'names no founder authority' end);
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
    v_ok := (v_n = 0);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-011: %s customer identity match(es) found in the supplier-facing payload, over %s customer row(s) searched for email, phone and full name',
                     v_n, (select count(*) from public.customers));
    return next; return;
  end if;

  if p_rule_id = 'BR-012' then           -- an approved immutable supplier-safe package exists
    v_ok := coalesce(btrim(p_context->>'safe_package_ref'),'') <> ''
            and coalesce(btrim(p_context->>'safe_package_approved_by'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-012: package %s approved by %s',
                                         p_context->>'safe_package_ref', p_context->>'safe_package_approved_by')
                   else 'BR-012: no approved supplier-safe package named. No assignment or notification may be created without one.' end;
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
    v_ok := coalesce(btrim(p_context->>'terms_version'),'') <> ''
            and coalesce(btrim(p_context->>'terms_hash'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-025: acceptance names version %s and hash %s',
                                         p_context->>'terms_version', left(p_context->>'terms_hash',12))
                   else 'BR-025: acceptance must reference the exact displayed version AND hash; one without the other is not an acceptance of anything specific.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-026' then           -- no certificate before an acceptance record
    v_ok := coalesce(btrim(p_context->>'acceptance_ref'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-026: acceptance record %s exists', p_context->>'acceptance_ref')
                   else 'BR-026: no acceptance record named. A certificate generated before acceptance would assert a fact that has not happened.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-029' then           -- conflicting evidence is preserved, not overwritten
    v_ok := coalesce(p_context->>'conflict_preserved','') = 'true'
            or coalesce(btrim(p_context->>'evidence_authority'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then 'BR-029: conflicting evidence is retained with its authority ranking'
                   else 'BR-029: no conflict-preservation evidence named. Lower-authority evidence may not silently overwrite higher.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-032' then           -- provider events are unique and replay-safe
    if coalesce(btrim(p_context->>'provider_event_id'),'') = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-032: no provider_event_id named; duplicate delivery cannot be decided without one.';
      return next; return;
    end if;
    select count(*) into v_n from public.stripe_events se
     where se.event_id = p_context->>'provider_event_id';
    v_ok := (v_n <= 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-032: provider event %s appears %s time(s); public.stripe_events keys on event_id with delivery_count, so a duplicate is visible rather than reprocessed.',
                     p_context->>'provider_event_id', v_n);
    return next; return;
  end if;

  if p_rule_id = 'BR-033' then           -- unknown money is quarantined, never success
    v_txt := lower(coalesce(btrim(p_context->>'monetary_state'),''));
    v_ok := v_txt <> '' and v_txt not in ('unknown','conflicting','unreconciled');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-033: monetary state %s. Unknown, conflicting and unreconciled states are blocked and quarantined, never treated as success.',
                     coalesce(nullif(v_txt,''),'(unstated)'));
    return next; return;
  end if;

  if p_rule_id = 'BR-034' then           -- consent and suppression are respected
    if coalesce(btrim(p_context->>'notify_email'),'') = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-034: no notify_email named; consent cannot be decided for an unnamed recipient.';
      return next; return;
    end if;
    select count(*) into v_n from public.email_suppressions s
     where lower(s.email) = lower(p_context->>'notify_email');
    v_ok := (v_n = 0);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-034: %s is %s in public.email_suppressions', p_context->>'notify_email',
                     case when v_ok then 'not suppressed' else 'SUPPRESSED and must not be contacted' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-035' then           -- only the approved revision publishes
    v_ok := coalesce(btrim(p_context->>'approved_revision_ref'),'') <> ''
            and coalesce(p_context->>'approved_revision_ref','') = coalesce(p_context->>'publishing_revision_ref','');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-035: the publishing revision is the approved one (%s)',
                                         p_context->>'approved_revision_ref')
                   else 'BR-035: the revision being published is not the independently approved revision, or neither was named.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-036' then           -- review inspects the artifact, not the brief
    v_ok := coalesce(btrim(p_context->>'artifact_ref'),'') <> ''
            and coalesce(btrim(p_context->>'artifact_sha256'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-036: review names artifact %s at digest %s',
                                         p_context->>'artifact_ref', left(p_context->>'artifact_sha256',12))
                   else 'BR-036: the review names no artifact and digest. A verifier that reads the brief instead of the artifact has already produced a false pass in this estate.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-039' then           -- a release needs an executable rollback
    v_ok := coalesce(btrim(p_context->>'rollback_ref'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-039: rollback path %s is named', p_context->>'rollback_ref')
                   else 'BR-039: no rollback or recovery path named. A consequential release without one is not approvable.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-041' then           -- activity is not outcome
    v_ok := coalesce(btrim(p_context->>'outcome_metric'),'') <> ''
            and coalesce(p_context->>'outcome_metric','') <> coalesce(p_context->>'activity_metric','');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-041: success is declared on the outcome metric %s, distinct from the activity metric',
                                         p_context->>'outcome_metric')
                   else 'BR-041: no business outcome metric named, or it is the activity metric under another name.' end;
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
end $function$;
