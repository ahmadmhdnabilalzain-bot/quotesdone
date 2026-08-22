-- E19 — absent evidence and broken policy wore one name
--
-- MEASURED. Driving all 30 workflows through the kernel on 2026-08-20 produced 254 dispatch rows and
-- 252 refusals, and the outcome column said REFUSED for every one of them. It said REFUSED when a
-- rule read its evidence and judged that the call broke policy, and it said REFUSED when the call
-- named no evidence at all and the rule never judged anything. The 2026-08-20 acceptance audit read
-- the second as the first, in finding 3, and it was right to: the refusal texts give it away —
-- "BR-003 requires [founder_authority_ref] and the call names none of it" — and the very same
-- dispatch row lists those keys in its own unresolved_keys column.
--
-- Both are refusals. Neither becomes a pass here. Nothing is weakened: every state, every ok flag
-- and every existing reader is untouched, so fn_phase_d_handler_execute still refuses exactly the
-- same set of steps, and fn_phase_d_rule_can_refuse still counts BR-003 among the rules that can
-- refuse. What changes is that the estate can now tell the two apart:
--
--   * fn_phase_d_rule_check and fn_phase_d_gate_evaluate each gain an evidence_absent column, set
--     true only in the branch that fires when the call named none of the declared evidence;
--   * fn_phase_d_handler_execute raises pd_evidence_absent when EVERY refusal on a step is of that
--     kind, and the existing pd_rule_refused / pd_gate_refused when even one rule or gate judged
--     something. A real violation is not diluted by the absences beside it;
--   * fn_phase_d_dispatch_step records outcome REFUSED_EVIDENCE_ABSENT for the first case.
--
-- Both routines gain an OUT column, so both need DROP before CREATE, and both therefore arrive
-- EXECUTE-to-PUBLIC. ALTER DEFAULT PRIVILEGES does not prevent that here — measured — so the
-- revokes at the foot of this file are the only mechanism, and they are in the same migration.
--
-- The dependency order matters: the two producers are dropped and recreated first, then the two
-- consumers, so that nothing is left referring to a signature that no longer exists.

alter table public.phase_d_dispatch drop constraint if exists phase_d_dispatch_outcome_check;
alter table public.phase_d_dispatch add constraint phase_d_dispatch_outcome_check
  check (outcome = any (array['EXECUTED','REFUSED','REFUSED_EVIDENCE_ABSENT','INPUTS_UNRESOLVED',
                             'DEPTH_LIMIT','DISPATCH_OFF']));

drop function if exists public.fn_phase_d_rule_check(text, jsonb);
drop function if exists public.fn_phase_d_gate_evaluate(text, jsonb);

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

CREATE OR REPLACE FUNCTION public.fn_phase_d_gate_evaluate(p_gate_id text, p_evidence jsonb)
 RETURNS TABLE(state text, passed boolean, gate_type text, reason text, refusal_code text, evidence_absent boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  g public.phase_b_gate%rowtype;
  c public.phase_d_gate_contract%rowtype;
  s public.phase_b_workflow_step%rowtype;
  v_missing text[]; v_n bigint; v_ok boolean; v_txt text;
begin
  evidence_absent := false;   -- E19, see fn_phase_d_rule_check
  select * into g from public.phase_b_gate where gate_id = p_gate_id;
  if not found then
    state := 'NOT_IMPLEMENTED'; passed := false; gate_type := 'unknown';
    reason := format('unknown gate %s — blocked, not defaulted', p_gate_id);
    refusal_code := 'gate_unknown'; return next; return;
  end if;
  gate_type := g.gate_type;

  select * into c from public.phase_d_gate_contract where gate_id = p_gate_id;
  if not found then
    state := 'NOT_IMPLEMENTED'; passed := false;
    reason := format('gate %s has no Phase D evidence contract — blocked', p_gate_id);
    refusal_code := 'gate_uncontracted'; return next; return;
  end if;
  refusal_code := c.refusal_code;

  if cardinality(c.evidence_keys) > 0 then
    select array_agg(k order by k) into v_missing
      from unnest(c.evidence_keys) k
     where p_evidence is null or not (p_evidence ? k)
        or jsonb_typeof(p_evidence->k) = 'null'
        or (jsonb_typeof(p_evidence->k) = 'string' and btrim(p_evidence->>k) = '');
    if v_missing is not null then
      -- E19. Same distinction as the rule side. The gate is BLOCKED either way; this column says
      -- which kind of blocked. Here the gate never saw its evidence -- it did not judge it.
      evidence_absent := true;
      state := 'BLOCKED'; passed := false;
      reason := format('gate %s (%s) requires [%s] and the call names none of it. Declared evidence: %s',
                       g.gate_id, g.gate_name, array_to_string(v_missing, ', '),
                       coalesce(g.required_evidence,'(none stated)'));
      return next; return;
    end if;
  end if;

  if p_gate_id = 'GATE-001' then
    select count(*) into v_n from public.fn_phase_a_baseline_drift();
    v_ok := (v_n = 0) and exists (select 1 from public.org_phase_baseline where phase = 'A');
    reason := format('GATE-001: Phase A drift %s row(s); baseline row %s', v_n,
                     case when exists (select 1 from public.org_phase_baseline where phase='A')
                          then 'present' else 'ABSENT' end);

  elsif p_gate_id = 'GATE-002' then
    v_ok := public.fn_phase_c_actor_may_own(p_evidence->>'actor_role_id');
    reason := format('GATE-002: actor %s %s', p_evidence->>'actor_role_id',
                     case when v_ok then 'resolves to an active canonical role or permitted overlay'
                          else 'does not resolve' end);

  elsif p_gate_id = 'GATE-003' then
    select count(*) into v_n from public.phase_b_workflow_step x
     where x.step_id = p_evidence->>'step_id' and coalesce(btrim(x.accountable_role_id),'') <> '';
    v_ok := (v_n = 1);
    reason := format('GATE-003: step %s has %s accountable owner(s); exactly one is required',
                     p_evidence->>'step_id', v_n);

  elsif p_gate_id = 'GATE-004' then
    select * into s from public.phase_b_workflow_step where step_id = p_evidence->>'step_id';
    v_ok := public.fn_kernel_reviewer_independent(s.accountable_role_id, p_evidence->>'reviewer_role_id');
    reason := format('GATE-004: %s and %s %s', s.accountable_role_id, p_evidence->>'reviewer_role_id',
                     case when v_ok then 'are different effective identities'
                          else 'resolve to the same effective identity' end);

  elsif p_gate_id = 'GATE-005' then
    select * into s from public.phase_b_workflow_step where step_id = p_evidence->>'step_id';
    v_ok := true;
    reason := format('GATE-005: step declares founder_gate %s and the call names authority %s',
                     left(coalesce(s.founder_gate,'none'),60), p_evidence->>'founder_authority_ref');

  elsif p_gate_id = 'GATE-006' then
    if p_evidence->>'from_state' = p_evidence->>'to_state' then
      v_ok := true;
      reason := format('GATE-006: the run stays in %s — this step applies no workflow-state '
                    || 'transition, so there is none to declare. The frozen model holds no '
                    || 'self-transition and 55 of 257 steps declare the state they are already in.',
                       p_evidence->>'from_state');
    else
      select count(*) into v_n from public.phase_b_workflow_transition t
       where t.from_state = p_evidence->>'from_state' and t.to_state = p_evidence->>'to_state';
      v_ok := (v_n > 0);
      reason := format('GATE-006: transition %s -> %s is %s in the frozen model',
                       p_evidence->>'from_state', p_evidence->>'to_state',
                       case when v_ok then 'declared' else 'NOT declared' end);
    end if;

  elsif p_gate_id = 'GATE-007' then
    v_ok := true;
    reason := 'GATE-007: packet, source version and requested action are all present and non-empty';

  elsif p_gate_id = 'GATE-008' then
    -- THE CLOSING STEP IS NOT AN OUTSTANDING PIECE OF WORK. It is necessarily open while it asks,
    -- so counting it made this gate unpassable for all 30 closure steps. Every other open step run
    -- still blocks.
    select count(*) into v_n from public.phase_c_workflow_step_run x
     where x.run_id = (p_evidence->>'run_id')::bigint
       and x.step_run_id is distinct from (p_evidence->>'step_run_id')::bigint
       and x.state not in ('completed','cancelled','failed','superseded','skipped');
    v_ok := (v_n = 0);
    reason := format('GATE-008: %s step run(s) still open on run %s, excluding the closing step run %s itself',
                     v_n, p_evidence->>'run_id', p_evidence->>'step_run_id');

  elsif p_gate_id = 'GATE-009' then
    v_ok := true;
    reason := format('GATE-009: acceptance %s names version %s at hash %s',
                     p_evidence->>'acceptance_ref', p_evidence->>'terms_version',
                     left(p_evidence->>'terms_hash',12));

  elsif p_gate_id = 'GATE-010' then
    v_ok := lower(btrim(p_evidence->>'route_state')) = 'confirmed';
    reason := format('GATE-010: route state %s; only a confirmed route carries dispatch authority',
                     p_evidence->>'route_state');

  elsif p_gate_id = 'GATE-011' then
    select count(*) into v_n from public.inquiries i
     where i.id::text = p_evidence->>'inquiry_id'
       and coalesce(i.status,'') in ('quote_ready','dispatched','quoted','completed');
    v_ok := (v_n = 1);
    reason := format('GATE-011: inquiry %s %s', p_evidence->>'inquiry_id',
                     case when v_ok then 'is quote-ready' else 'is not quote-ready or does not exist' end);

  elsif p_gate_id = 'GATE-012' then
    select count(*) into v_n from public.documents d
     where d.id::text = p_evidence->>'document_id'
       and coalesce(d.status,'') not in ('error','quarantined','rejected')
       and coalesce(d.error,'') = '';
    v_ok := (v_n = 1);
    reason := format('GATE-012: document %s %s', p_evidence->>'document_id',
                     case when v_ok then 'is supported, readable and carries no error'
                          else 'is missing, errored or quarantined' end);

  elsif p_gate_id = 'GATE-013' then
    v_ok := public.fn_kernel_reviewer_independent(
              coalesce(p_evidence->>'actor_role_id', 'unknown'),
              p_evidence->>'safe_package_approved_by');
    reason := format('GATE-013: package %s approved by %s; independence %s',
                     p_evidence->>'safe_package_ref', p_evidence->>'safe_package_approved_by',
                     case when v_ok then 'holds' else 'FAILS — the approver is the author' end);

  elsif p_gate_id = 'GATE-014' then
    select count(*) into v_n from public.leads l
     where l.id::text = p_evidence->>'supplier_id'
       and coalesce(l.approval_status,'') = 'approved' and coalesce(l.verified,false);
    v_ok := (v_n = 1);
    reason := format('GATE-014: supplier %s %s', p_evidence->>'supplier_id',
                     case when v_ok then 'is currently approved and verified'
                          else 'is not an approved, verified supplier' end);

  elsif p_gate_id = 'GATE-015' then
    select count(*) into v_n from public.inquiry_matches m
     where m.inquiry_id::text = p_evidence->>'inquiry_id'
       and m.supplier_id::text = p_evidence->>'supplier_id';
    v_ok := (v_n = 0);
    reason := format('GATE-015: %s existing assignment(s) for that supplier and inquiry; a dispatch would be a duplicate', v_n);

  elsif p_gate_id = 'GATE-016' then
    select count(*) into v_n from public.email_suppressions e
     where lower(e.email) = lower(p_evidence->>'notify_email');
    v_ok := (v_n = 0)
            and lower(coalesce(p_evidence->>'assignment_result','')) in ('delivered','accepted','sent');
    reason := format('GATE-016: %s is %s; assignment result %s',
                     p_evidence->>'notify_email',
                     case when v_n = 0 then 'not suppressed' else 'SUPPRESSED' end,
                     p_evidence->>'assignment_result');

  elsif p_gate_id = 'GATE-017' then
    select count(*) into v_n from public.quotes q
     where q.id::text = p_evidence->>'quote_id'
       and q.quote_amount is not null and coalesce(btrim(q.status),'') <> '';
    v_ok := (v_n = 1);
    reason := format('GATE-017: quote %s %s', p_evidence->>'quote_id',
                     case when v_ok then 'carries a stated amount and status'
                          else 'is missing mandatory commercial fields' end);

  elsif p_gate_id = 'GATE-018' then
    select count(*) into v_n from public.quote_comparisons qc
     where qc.id::text = p_evidence->>'comparison_id'
       and qc.customer_id::text = p_evidence->>'caller_customer_id';
    v_ok := (v_n = 1);
    reason := format('GATE-018: comparison %s %s the calling customer', p_evidence->>'comparison_id',
                     case when v_ok then 'belongs to' else 'does NOT belong to' end);

  elsif p_gate_id = 'GATE-019' then
    select rp.permitted, rp.reason into v_ok, v_txt
      from public.fn_phase_d_reveal_permitted(p_evidence->>'transaction_id') rp;
    reason := coalesce(v_txt, 'GATE-019: no verdict returned by the reveal decision');

  elsif p_gate_id = 'GATE-020' then
    select count(*) into v_n from public.refunds rf
     where rf.id::text = p_evidence->>'refund_id'
       and coalesce(btrim(rf.decided_by),'') <> '' and rf.decided_at is not null;
    v_ok := (v_n = 1);
    reason := format('GATE-020: refund %s %s, financial action key %s',
                     p_evidence->>'refund_id',
                     case when v_ok then 'carries a recorded decision and decider'
                          else 'has no recorded founder decision' end,
                     p_evidence->>'financial_action_key');

  elsif p_gate_id = 'GATE-021' then
    v_ok := public.fn_kernel_reviewer_independent(
              coalesce(p_evidence->>'actor_role_id','unknown'), p_evidence->>'reviewer_role_id');
    reason := format('GATE-021: artifact %s at digest %s reviewed by %s; independence %s',
                     p_evidence->>'artifact_ref', left(p_evidence->>'artifact_sha256',12),
                     p_evidence->>'reviewer_role_id',
                     case when v_ok then 'holds' else 'FAILS' end);

  elsif p_gate_id = 'GATE-031' then
    v_ok := not coalesce((public.fn_kernel_paid_provider_gate('openai/gpt-4o-mini')->>'allowed')::boolean, true);
    select count(*) into v_n from public.llm_attempt where created_at > now() - interval '24 hours';
    v_ok := v_ok and (v_n = 0);
    reason := format('GATE-031: paid-provider gate %s; %s llm_attempt row(s) in 24h',
                     case when v_ok then 'refuses every route' else 'ALLOWED a route' end, v_n);

  elsif p_gate_id = 'GATE-032' then
    select count(*) into v_n from cron.job where active;
    v_ok := (v_n <= 25);
    reason := format('GATE-032: %s active cron job(s) against the selective automation hold ceiling of 25', v_n);

  elsif p_gate_id in ('GATE-022','GATE-023','GATE-024','GATE-025','GATE-026','GATE-027',
                      'GATE-028','GATE-029','GATE-030') then
    v_ok := true;
    reason := format('%s (%s): all declared evidence is present and non-empty [%s]. '
                  || 'The keys are checked; the CONTENT behind them is not yet verifiable from '
                  || 'this database, which is stated rather than implied.',
                     g.gate_id, g.gate_name, array_to_string(c.evidence_keys, ', '));

  else
    state := 'NOT_IMPLEMENTED'; passed := false;
    reason := format('gate %s has no predicate in fn_phase_d_gate_evaluate — blocked', p_gate_id);
    return next; return;
  end if;

  state := case when v_ok then 'PASSED' else 'BLOCKED' end;
  passed := coalesce(v_ok, false);
  return next;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_phase_d_handler_execute(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  b   public.phase_d_handler_binding%rowtype;
  s   public.phase_b_workflow_step%rowtype;
  sr  public.phase_c_workflow_step_run%rowtype;
  ec  public.phase_d_step_effect%rowtype;
  v_step_run bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_actor    text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_idem     text   := nullif(btrim(coalesce(p_input->>'idempotency_key','')),'');
  v_inputs   jsonb  := coalesce(p_input->'inputs','{}'::jsonb);
  v_ctx      text   := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),'production'));
  v_ok       boolean; v_reason text; v_missing text[];
  v_rule     record; v_rule_ok boolean; v_rule_type text; v_rule_reason text;
  v_applies  boolean; v_why text; v_enforced boolean; v_refusal text; v_state text;
  v_ev_absent boolean := false;   -- E19
  v_refused  jsonb := '[]'::jsonb;
  v_skipped  jsonb := '[]'::jsonb;
  v_gate     record; v_gstate text; v_gpassed boolean; v_gtype text;
  v_greason  text; v_grefusal text; v_gapplies boolean; v_gwhy text;
  v_gates    jsonb := '[]'::jsonb;
  v_gblocked jsonb := '[]'::jsonb;
  v_evaluated jsonb := '[]'::jsonb;
  v_output   jsonb;
  v_assert   jsonb;
  v_result   jsonb;
  v_effect   jsonb;
begin
  -- ---- 0. the call itself ------------------------------------------------------------------
  if v_step_run is null or v_actor is null or v_idem is null then
    raise exception 'fn_phase_d_handler_execute: step_run_id, actor_role_id and idempotency_key are all required (got %, %, %) (pd_input_schema_invalid)',
      coalesce(v_step_run::text,'(null)'), coalesce(v_actor,'(null)'), coalesce(v_idem,'(null)')
      using errcode = '22023';
  end if;
  if v_ctx not in ('production','test') then
    raise exception 'fn_phase_d_handler_execute: execution_context must be production or test, got %',
      v_ctx using errcode = '22023';
  end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if not found then
    raise exception 'fn_phase_d_handler_execute: no step run % (pd_step_state_invalid)', v_step_run
      using errcode = '23503';
  end if;

  select * into b from public.phase_d_handler_binding where step_id = sr.step_id;
  if not found then
    raise exception 'fn_phase_d_handler_execute: step % has no Phase D handler binding — fail closed. Every one of the 257 frozen steps must carry exactly one. (pd_input_schema_invalid)',
      sr.step_id using errcode = '23503';
  end if;
  select * into s from public.phase_b_workflow_step where step_id = sr.step_id;

  select * into ec from public.phase_d_step_effect where step_id = sr.step_id;
  if not found then
    raise exception 'fn_phase_d_handler_execute: step % has no declared effect contract. A handler with no declared effect is the schema-only handler this phase exists to remove. (pd_effect_undeclared)',
      sr.step_id using errcode = '23503';
  end if;

  -- ---- 1. TYPED INPUT ----------------------------------------------------------------------
  select valid, reason, missing into v_ok, v_reason, v_missing
    from public.fn_phase_d_schema_validate(b.input_schema_id, v_inputs);
  if not v_ok then
    raise exception 'fn_phase_d_handler_execute: step % input rejected: % (pd_input_schema_invalid)',
      sr.step_id, v_reason using errcode = '22023';
  end if;

  -- ---- 2. RULES IN SCOPE -------------------------------------------------------------------
  -- SCOPE IS NOT APPLICABILITY. The frozen registry scopes rules by WORKFLOW, so BR-002 is in
  -- scope for all 257 steps while only 28 of them name an independent reviewer. Asking
  -- fn_kernel_reviewer_independent about a NULL reviewer returns false, which refused an intake
  -- step for a creator/reviewer collision that could not exist. fn_phase_d_rule_applies decides
  -- both, and records the reason either way.
  --
  -- Refusals are collected rather than short-circuited: a caller told only the first thing wrong
  -- fixes one thing and comes back.
  for v_rule in select unnest(b.rule_ids) rid loop
    select applies, why into v_applies, v_why
      from public.fn_phase_d_rule_applies(v_rule.rid, sr.step_id);
    if not coalesce(v_applies,false) then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'rule_id', v_rule.rid, 'applies', false, 'why', v_why));
      continue;
    end if;

    select state, ok, rule_type, enforced, reason, refusal_code, coalesce(evidence_absent,false)
      into v_state, v_rule_ok, v_rule_type, v_enforced, v_rule_reason, v_refusal, v_ev_absent
      from public.fn_phase_d_rule_check(v_rule.rid,
        jsonb_build_object(
          'accountable_role_id', sr.accountable_role_id,
          'reviewer_role_id',    nullif(b.independent_reviewer_role_id,''),
          'actor_role_id',       v_actor,
          'step_id',             sr.step_id,
          'workflow_id',         b.workflow_id,
          'run_id',              sr.run_id,
          'founder_gate',        b.founder_gate,
          'execution_context',   v_ctx)
        || coalesce(p_input->'context','{}'::jsonb));

    v_evaluated := v_evaluated || jsonb_build_array(jsonb_build_object(
      'rule_id', v_rule.rid, 'state', v_state, 'rule_type', v_rule_type, 'ok', v_rule_ok,
      'enforced', v_enforced, 'reason', v_rule_reason));

    if v_rule_type = 'hard' and v_state in ('ENFORCED_FAIL','NOT_IMPLEMENTED') then
      v_refused := v_refused || jsonb_build_array(jsonb_build_object(
        'rule_id', v_rule.rid, 'state', v_state, 'rule_type', v_rule_type,
        'refusal_code', v_refusal, 'reason', v_rule_reason,
        'evidence_absent', v_ev_absent));
    end if;
  end loop;
  if jsonb_array_length(v_refused) > 0 then
    -- E19. TWO DIFFERENT EVENTS DESERVE TWO DIFFERENT NAMES. If EVERY refusal on this step is an
    -- absence of evidence, the code says so and fn_phase_d_dispatch_step records
    -- REFUSED_EVIDENCE_ABSENT. If even one rule read its evidence and judged it against policy, the
    -- whole refusal is pd_rule_refused: a genuine violation is not diluted by the absences beside
    -- it. Both refuse, and neither is a pass.
    if not exists (select 1 from jsonb_array_elements(v_refused) x
                    where not coalesce((x->>'evidence_absent')::boolean, false)) then
      raise exception 'fn_phase_d_handler_execute: step % refused by % hard business rule(s), every one of them for evidence the call did not name rather than for a policy the call broke: % (pd_evidence_absent)',
        sr.step_id, jsonb_array_length(v_refused), v_refused::text using errcode = '23514';
    end if;
    raise exception 'fn_phase_d_handler_execute: step % refused by % hard business rule(s): % (pd_rule_refused)',
      sr.step_id, jsonb_array_length(v_refused), v_refused::text using errcode = '23514';
  end if;

  -- ---- 2b. GATES IN SCOPE, EACH AGAINST ITS OWN DECLARED EVIDENCE --------------------------
  for v_gate in select unnest(b.gate_ids) gid loop
    select ga.applies, ga.why into v_gapplies, v_gwhy
      from public.fn_phase_d_gate_applies(v_gate.gid, sr.step_id) ga;
    if not coalesce(v_gapplies,false) then
      v_gates := v_gates || jsonb_build_array(jsonb_build_object(
        'gate_id', v_gate.gid, 'state', 'NOT_APPLICABLE', 'why', v_gwhy));
      continue;
    end if;
    select ge.state, ge.passed, ge.gate_type, ge.reason, ge.refusal_code, coalesce(ge.evidence_absent,false)
      into v_gstate, v_gpassed, v_gtype, v_greason, v_grefusal, v_ev_absent
      from public.fn_phase_d_gate_evaluate(v_gate.gid,
        jsonb_build_object('step_id', sr.step_id, 'run_id', sr.run_id,
                           'step_run_id', v_step_run,
                           'step_run_id', v_step_run,
                           'actor_role_id', v_actor,
                           'reviewer_role_id', nullif(b.independent_reviewer_role_id,''))
        || coalesce(p_input->'gate_evidence','{}'::jsonb)) ge;

    v_gates := v_gates || jsonb_build_array(jsonb_build_object(
      'gate_id', v_gate.gid, 'state', v_gstate, 'gate_type', v_gtype,
      'passed', v_gpassed, 'reason', v_greason));

    if v_gtype = 'hard' and v_gstate in ('BLOCKED','NOT_IMPLEMENTED') then
      v_gblocked := v_gblocked || jsonb_build_array(jsonb_build_object(
        'gate_id', v_gate.gid, 'state', v_gstate,
        'refusal_code', v_grefusal, 'reason', v_greason,
        'evidence_absent', v_ev_absent));
    end if;
  end loop;
  if jsonb_array_length(v_gblocked) > 0 then
    if not exists (select 1 from jsonb_array_elements(v_gblocked) x
                    where not coalesce((x->>'evidence_absent')::boolean, false)) then
      raise exception 'fn_phase_d_handler_execute: step % blocked by % hard gate(s), every one of them for evidence the call did not name rather than for a condition the gate judged and rejected: % (pd_evidence_absent)',
        sr.step_id, jsonb_array_length(v_gblocked), v_gblocked::text using errcode = '23514';
    end if;
    raise exception 'fn_phase_d_handler_execute: step % refused by % hard gate(s): % (pd_gate_refused)',
      sr.step_id, jsonb_array_length(v_gblocked), v_gblocked::text using errcode = '23514';
  end if;

  -- ---- 3. CAPABILITY BOUNDARY, FAIL CLOSED -------------------------------------------------
  if b.capability_dependency <> 'NONE' and v_ctx <> 'test' then
    raise exception 'fn_phase_d_handler_execute: step % depends on capability % (matched on the frozen required_action at: %) and no capability provider is available in Phase D. Paid inference is held until Phase E. Refusing rather than completing a business step from a fixture. (pd_capability_unavailable)',
      sr.step_id, b.capability_dependency, coalesce(nullif(b.capability_evidence,''),'(none)')
      using errcode = '23514';
  end if;

  -- ---- 4. PROVIDER BOUNDARY, FAIL CLOSED ---------------------------------------------------
  if b.provider_dependency <> 'NONE' and v_ctx <> 'test' then
    raise exception 'fn_phase_d_handler_execute: step % depends on external provider % which is disabled for the whole of Phase D. (pd_provider_disabled)',
      sr.step_id, b.provider_dependency using errcode = '23514';
  end if;

  -- ---- 5. THE FAMILY HANDLER ---------------------------------------------------------------
  v_assert := (
    select coalesce(jsonb_agg(jsonb_build_object(
             'criterion', btrim(c), 'satisfied_by',
             'named inputs [' || array_to_string(
               (select array_agg(k order by k) from jsonb_object_keys(v_inputs) k), ', ') || ']')
             order by ord), '[]'::jsonb)
      from unnest(string_to_array(coalesce(s.acceptance_criteria,''), ';')) with ordinality u(c, ord)
     where btrim(c) <> '');

  v_output := jsonb_build_object(
    'status', 'completed',
    'output', format('%s — %s', s.step_name, coalesce(s.required_output,'output produced')),
    'acceptance_assertions', case when jsonb_array_length(v_assert) = 0
                                  then jsonb_build_array(jsonb_build_object(
                                         'criterion', coalesce(s.acceptance_criteria,'(none declared)'),
                                         'satisfied_by','named inputs'))
                                  else v_assert end,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
       'step_id', sr.step_id, 'step_run_id', v_step_run, 'run_id', sr.run_id,
       'handler_id', b.handler_id, 'handler_version', b.handler_version,
       'input_schema_id', b.input_schema_id, 'output_schema_id', b.output_schema_id,
       'inputs_named', v_inputs, 'execution_context', v_ctx)))
    || case b.handler_class
         when 'INTAKE_HANDLER' then jsonb_build_object(
           'source_ref', coalesce(p_input->>'source_ref', 'step_run:' || v_step_run),
           'captured_verbatim', v_inputs)
         when 'ANALYSIS_HANDLER' then jsonb_build_object(
           'method', 'deterministic reconciliation of the named inputs against the frozen step contract',
           'inputs_used', v_inputs,
           'findings', jsonb_build_array(coalesce(s.required_action,'')),
           'assumptions', jsonb_build_array(
             'only the inputs named in this call were used; no external source was consulted'))
         when 'EXECUTION_HANDLER' then jsonb_build_object(
           'state_change', coalesce(s.required_output,''),
           'target_object', coalesce(ec.effect_object_id,
             (select primary_object from public.phase_b_workflow w
               where w.workflow_id = b.workflow_id), b.workflow_id),
           'authorization_ref', format('accountable owner %s on step %s',
                                       sr.accountable_role_id, sr.step_id))
         when 'REVIEW_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'verdict', nullif(btrim(coalesce(p_input->>'verdict','')),''),
           'reviewer_role_id', nullif(btrim(coalesce(p_input->>'reviewer_role_id','')),'')))
         when 'DECISION_HANDLER' then jsonb_build_object(
           'decision', coalesce(s.required_output,''),
           'rationale', coalesce(s.acceptance_criteria,''),
           'authority_ref', format('founder_gate=%s; accountable owner %s',
                                   b.founder_gate, sr.accountable_role_id))
         when 'HANDOFF_HANDLER' then jsonb_build_object(
           'packet', v_inputs,
           'receiving_role_id', coalesce((select h.receiving_role_id from public.phase_b_handoff h
                                           where h.from_step_id = sr.step_id limit 1),
                                         sr.accountable_role_id),
           'acceptance_criteria', coalesce(s.acceptance_criteria,''))
         when 'MEASUREMENT_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'metric', coalesce(s.required_output,''),
           'denominator', p_input->'denominator',
           'numerator', p_input->'numerator',
           'formula', nullif(btrim(coalesce(p_input->>'formula','')),''),
           'window', nullif(btrim(coalesce(p_input->>'window','')),'')))
         when 'CLOSURE_HANDLER' then jsonb_build_object(
           'blockers_resolved', jsonb_build_array(
             'the frozen fn_kernel_step_complete measures the four mandatory closure blocker '
             || 'classes itself and raises k3_closure_blocked if any is open'),
           'closure_evidence', coalesce(s.closure_criteria,''))
         else '{}'::jsonb end;

  -- ---- 5a. TWO REFUSALS THE SCHEMA ALONE CANNOT MAKE ---------------------------------------
  if b.handler_class = 'REVIEW_HANDLER'
     and not public.fn_kernel_reviewer_independent(
               sr.accountable_role_id, v_output->>'reviewer_role_id') then
    raise exception 'fn_phase_d_handler_execute: step % is accountable to % and the review names % as reviewer; those resolve to the same effective identity. A creator cannot be the sole independent reviewer of the same output (BR-002). (pd_rule_refused)',
      sr.step_id, sr.accountable_role_id, coalesce(v_output->>'reviewer_role_id','(none)')
      using errcode = '23514';
  end if;

  if b.handler_class = 'MEASUREMENT_HANDLER'
     and jsonb_typeof(v_output->'denominator') = 'number'
     and (v_output->>'denominator')::numeric = 0 then
    raise exception 'fn_phase_d_handler_execute: step % reported a denominator of 0. A ratio over nothing is not a measurement, and reporting it as one is how an unmeasured goal scores as perfect. (pd_output_schema_invalid)',
      sr.step_id using errcode = '22023';
  end if;

  -- ---- 6. TYPED OUTPUT ---------------------------------------------------------------------
  select valid, reason, missing into v_ok, v_reason, v_missing
    from public.fn_phase_d_schema_validate(b.output_schema_id, v_output);
  if not v_ok then
    raise exception 'fn_phase_d_handler_execute: step % produced an output its own contract rejects: % (pd_output_schema_invalid)',
      sr.step_id, v_reason using errcode = '22023';
  end if;

  -- ---- 6b. THE BUSINESS EFFECT -------------------------------------------------------------
  -- D7. Until this line existed, 257 of 257 handlers produced a typed output the kernel accepted
  -- and no business effect whatsoever, and fn_phase_d_handler_state() said so in red.
  --
  -- The effect payload comes from the CALLER, merged over the step's own facts. Nothing about the
  -- business record is invented here: a step that needs a business_key and an owner_ref and is
  -- given neither refuses, because a record written under an owner this routine chose would be
  -- the auto-vivified customer account defect in a new place.
  v_effect := public.fn_phase_d_effect_produce(
    jsonb_build_object(
      'step_run_id', v_step_run, 'idempotency_key', v_idem, 'actor_role_id', v_actor,
      'execution_context', v_ctx)
    || jsonb_strip_nulls(jsonb_build_object(
      'business_key', p_input->>'business_key',
      'owner_ref',    p_input->>'owner_ref',
      'state',        p_input->>'effect_state',
      'state_before', p_input->>'state_before',
      'trace_id',     p_input->>'trace_id'))
    || jsonb_build_object('payload', coalesce(p_input->'effect_payload', v_inputs)));

  v_output := v_output || jsonb_build_object('business_effect', jsonb_build_object(
    'effect_type', v_effect->>'effect_type',
    'effect_object_id', v_effect->'effect_object_id',
    'result_reference', v_effect->>'result_reference',
    'effect_id', v_effect->'effect_id',
    'provider_mode', v_effect->>'provider_mode',
    'replay', v_effect->'replay'));

  -- ---- 7. HAND TO THE FROZEN KERNEL --------------------------------------------------------
  -- Everything from here — idempotency, locks, authority, gates, the task state machine,
  -- progression, handoffs, run state and events — belongs to fn_kernel_step_complete and is not
  -- reimplemented. A handler that wrote any of it would be the parallel engine the spec forbids.
  v_result := public.fn_kernel_step_complete(jsonb_build_object(
    'step_run_id', v_step_run, 'actor_role_id', v_actor, 'outcome', 'pass',
    'idempotency_key', v_idem, 'inputs', v_inputs, 'output', v_output,
    'evidence_ref', format('phase_d:%s:%s:effect=%s',
                           b.handler_id, v_step_run, coalesce(v_effect->>'result_reference','none')),
    'correlation_id', p_input->>'correlation_id',
    'causation_id', coalesce(p_input->>'causation_id', 'phase_d_handler:' || b.handler_id)));

  return v_result || jsonb_build_object(
    'phase_d', jsonb_build_object(
      'handler_id', b.handler_id, 'handler_version', b.handler_version,
      'handler_class', b.handler_class, 'execution_context', v_ctx,
      'input_schema_id', b.input_schema_id, 'output_schema_id', b.output_schema_id,
      'rules_in_scope', cardinality(b.rule_ids),
      'rules_evaluated', v_evaluated, 'rules_not_applicable', v_skipped,
      'rules_enforced_count', (select count(*) from jsonb_array_elements(v_evaluated) e2
                                where (e2->>'enforced')::boolean),
      'rules_outstanding_count', (select count(*) from jsonb_array_elements(v_evaluated) e2
                                   where not (e2->>'enforced')::boolean),
      'gates_in_scope', cardinality(b.gate_ids), 'gates_evaluated', v_gates,
      'capability_dependency', b.capability_dependency,
      'provider_dependency', b.provider_dependency,
      'external_effect_policy', b.external_effect_policy,
      'expected_effect_type', ec.expected_effect_type,
      'implementation_depth', ec.implementation_depth,
      'business_effect', v_effect));
end $function$;

CREATE OR REPLACE FUNCTION public.fn_phase_d_dispatch_step(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sr public.phase_c_workflow_step_run%rowtype;
  v_step_run bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_actor    text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_kind     text   := coalesce(nullif(btrim(p_input->>'opened_by_kind'),''),'(unstated)');
  v_ref      text   := coalesce(nullif(btrim(p_input->>'opened_by_ref'),''),'(unstated)');
  v_idem     text   := coalesce(nullif(btrim(p_input->>'idempotency_key'),''),'');
  v_wf       text;
  v_on       text;
  v_depth    int;
  v_in       jsonb;
  v_cx       jsonb;
  v_res      jsonb;
  v_unres    text[];
  v_err      text;
  v_code     text;
begin
  if v_step_run is null or v_actor is null then
    raise exception 'fn_phase_d_dispatch_step: step_run_id and actor_role_id are required (got %, %)',
      coalesce(v_step_run::text,'(null)'), coalesce(v_actor,'(null)') using errcode = '22023';
  end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if not found then
    raise exception 'fn_phase_d_dispatch_step: no step run %', v_step_run using errcode = '23503';
  end if;

  if not exists (select 1 from public.phase_d_handler_binding hb where hb.step_id = sr.step_id)
     or not exists (select 1 from public.phase_d_step_effect se where se.step_id = sr.step_id) then
    return jsonb_build_object('dispatched', false, 'outcome', 'NO_BINDING', 'step_id', sr.step_id);
  end if;

  select b2.workflow_id into v_wf from public.phase_d_handler_binding b2 where b2.step_id = sr.step_id;
  if v_idem = '' then v_idem := 'kernel|' || sr.run_id || '|' || sr.step_id; end if;

  v_on    := lower(coalesce(nullif(btrim(current_setting('app.phase_d_dispatch', true)),''), 'on'));
  v_depth := coalesce(nullif(btrim(current_setting('app.phase_d_dispatch_depth', true)),'')::int, 0);

  if v_on = 'off' then
    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, refusal_code, reason, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'DISPATCH_OFF', 'pd_dispatch_off',
            'app.phase_d_dispatch is off for this transaction', v_depth);
    return jsonb_build_object('dispatched', false, 'outcome', 'DISPATCH_OFF');
  end if;

  if v_depth >= 64 then
    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, refusal_code, reason, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'DEPTH_LIMIT', 'pd_dispatch_depth_limit',
            format('dispatch depth %s reached at step %s', v_depth, sr.step_id), v_depth);
    return jsonb_build_object('dispatched', false, 'outcome', 'DEPTH_LIMIT', 'depth', v_depth);
  end if;

  perform set_config('app.phase_d_dispatch_depth', (v_depth + 1)::text, true);

  begin
    v_in := public.fn_phase_d_step_inputs(v_step_run);
    select array_agg(x) into v_unres
      from jsonb_array_elements_text(coalesce(v_in->'unresolved','[]'::jsonb)) x;
    v_unres := coalesce(v_unres, '{}');

    if cardinality(v_unres) > 0 then
      insert into public.phase_d_dispatch
        (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
         outcome, refusal_code, reason, unresolved_keys, inputs_provenance, dispatch_depth)
      values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
              'INPUTS_UNRESOLVED', 'pd_input_unresolved',
              format('%s of the %s declared input keys resolve from no real source: %s',
                     cardinality(v_unres),
                     jsonb_array_length(coalesce(v_in->'declared_keys','[]'::jsonb)),
                     array_to_string(v_unres, ', ')),
              v_unres, coalesce(v_in->'provenance','{}'::jsonb), v_depth);
      perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
      return jsonb_build_object('dispatched', false, 'outcome', 'INPUTS_UNRESOLVED',
                                'unresolved', to_jsonb(v_unres));
    end if;

    -- D37. The same treatment for what the RULES and GATES read. Unresolved keys are not supplied,
    -- so a rule that needs one refuses instead of passing on a placeholder.
    v_cx := public.fn_phase_d_step_context(v_step_run);

    v_res := public.fn_phase_d_handler_execute(jsonb_build_object(
      'step_run_id',       v_step_run,
      'actor_role_id',     v_actor,
      'idempotency_key',   v_idem || '|phase_d',
      'inputs',            v_in->'inputs',
      'context',           v_cx->'context',
      'gate_evidence',     v_cx->'context',
      'execution_context', 'production',
      'correlation_id',    p_input->>'correlation_id',
      'causation_id',      'kernel_dispatch:' || v_kind || ':' || v_ref));

    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, inputs_provenance, effect_id, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'EXECUTED',
            coalesce(v_in->'provenance','{}'::jsonb) || coalesce(v_cx->'provenance','{}'::jsonb),
            nullif(v_res#>>'{phase_d,business_effect,effect_id}','')::bigint, v_depth);

    perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
    return jsonb_build_object('dispatched', true, 'outcome', 'EXECUTED',
             'handler_id', v_res#>>'{phase_d,handler_id}',
             'effect_id',  v_res#>'{phase_d,business_effect,effect_id}');

  exception
    when others then
      v_err  := SQLERRM;
      v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1], 'pd_unclassified');
      insert into public.phase_d_dispatch
        (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
         outcome, refusal_code, sqlstate_code, reason, unresolved_keys, inputs_provenance,
         dispatch_depth)
      values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
              -- E19. This column used to say REFUSED whether the handler had judged the evidence
              -- and rejected it, or had never been given any. Those are different events, and the
              -- 2026-08-20 acceptance audit read the second as the first. Both are refusals and
              -- neither is a pass; only the name differs.
              case when v_code = 'pd_evidence_absent' then 'REFUSED_EVIDENCE_ABSENT' else 'REFUSED' end,
              v_code, SQLSTATE, left(v_err, 1000),
              coalesce((select array_agg(x) from jsonb_array_elements_text(
                          coalesce(v_cx->'unresolved','[]'::jsonb)) x), '{}'),
              coalesce(v_cx->'provenance','{}'::jsonb), v_depth);
      perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
      return jsonb_build_object('dispatched', false,
                                'outcome', case when v_code = 'pd_evidence_absent'
                                                then 'REFUSED_EVIDENCE_ABSENT' else 'REFUSED' end,
                                'refusal_code', v_code, 'sqlstate', SQLSTATE);
  end;
end
$function$;

-- A function CREATEd in public arrives EXECUTE-to-PUBLIC. Only the two dropped-and-recreated
-- routines need this; fn_phase_d_handler_execute and fn_phase_d_dispatch_step were CREATE OR
-- REPLACEd and kept their ACLs.
revoke execute on function public.fn_phase_d_rule_check(text, jsonb) from public;
revoke execute on function public.fn_phase_d_rule_check(text, jsonb) from anon;
revoke execute on function public.fn_phase_d_rule_check(text, jsonb) from authenticated;
revoke execute on function public.fn_phase_d_gate_evaluate(text, jsonb) from public;
revoke execute on function public.fn_phase_d_gate_evaluate(text, jsonb) from anon;
revoke execute on function public.fn_phase_d_gate_evaluate(text, jsonb) from authenticated;
