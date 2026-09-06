// Build O07 by splicing the live bodies of fn_phase_d_rule_check and fn_phase_d_gate_evaluate.
// Anchors are COMPLETE emits (through `return next; return; end if;`) so a partial match cannot
// leave a half-rewritten branch. Every replacement is asserted to have applied exactly once.
import { q } from './q.mjs';
import { writeFileSync } from 'node:fs';

const body = async (name) => (await q(
  `select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
    and p.proname='${name}'`))[0].prosrc;

let rule = await body('fn_phase_d_rule_check');
let gate = await body('fn_phase_d_gate_evaluate');

const swap = (src, find, repl, label) => {
  const n = src.split(find).length - 1;
  if (n !== 1) { console.error(`ANCHOR ${label}: matched ${n} time(s), expected 1`); process.exit(1); }
  return src.replace(find, repl);
};

// ---------------------------------------------------------------- BR-011 (hidden metadata + PII)
rule = swap(rule,
`    v_txt2 := regexp_replace(v_txt, '[^0-9]', '', 'g');
    v_n2 := (case when v_txt ~* '[A-Z0-9._%+-]+@[A-Z0-9.-]+[.][A-Z]{2,}' then 1 else 0 end)
          + (case when v_txt2 ~ '(971|0)5[0-9]{8}' then 1 else 0 end);
    v_ok := (v_n = 0 and v_n2 = 0);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-011: %s customer identity match(es) over %s customer row(s) searched for email, phone and full name, and %s identity-shaped token(s) -- an email address or a UAE mobile -- found in the payload itself',
                     v_n, (select count(*) from public.customers), v_n2);
    return next; return;
  end if;`,
`    -- O04/O07. THE TWO REGEX CLASSES WERE A LIST INSIDE THIS PREDICATE, AND THE LIST WAS SHORT.
    -- Measured on the live body, 24 Aug 2026: the payload
    --   '/Author (Omar Bin Faisal) /Title (Villa 42 plot 345-8871) /Creator (AL NAHDA CONSULTANTS)'
    -- returned ok = TRUE. The row arm searches public.customers, which holds 0 rows, and the shape
    -- arm tested an email and a UAE mobile and nothing else -- so the exact injection PD-PRIV-005
    -- names, a customer's NAME in a PDF /Info dictionary, passed the one rule that names it.
    --
    -- The classes now come from public.phase_d_personal_identifier_class, so extending the list is
    -- a row and not a redeploy, and the scanner in scripts/phase_d/metadata_scan.mjs reads the same
    -- table -- the rule and the scanner cannot disagree about what a personal identifier is.
    select count(*) into v_n2
      from public.phase_d_personal_identifier_class pic
     where pic.detection = 'REGEX' and not pic.supplier_facing_allowed
       and v_txt ~* pic.pattern;

    -- AND A FILE REVISION, WHERE ONE IS NAMED. A payload is text; the file that goes with it
    -- carries metadata this predicate cannot see. Where the caller names the revision, its recorded
    -- scan is part of the same answer, and a revision that is named and not dispatchable refuses
    -- here rather than at the point the file is already on its way.
    v_txt3 := btrim(coalesce(p_context->>'file_revision_ref',''));
    if v_txt3 <> '' then
      select fr.dispatchable, fr.refusal_code, fr.reason into v_rev_ok, v_rev_code, v_rev_why
        from public.fn_phase_d_file_revision_dispatchable(v_txt3) fr;
    else
      v_rev_ok := true; v_rev_code := null; v_rev_why := 'no file revision named in this context';
    end if;

    v_ok := (v_n = 0 and v_n2 = 0 and v_rev_ok);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    if not v_rev_ok then refusal_code := v_rev_code; end if;
    reason := format('BR-011: %s customer identity match(es) over %s customer row(s) searched for email, phone and full name; %s of %s registered machine-decidable identifier class(es) matched the payload itself; file revision %s. %s of the registered classes are HUMAN_REVIEW and are never scored automatically as absent.',
                     v_n, (select count(*) from public.customers), v_n2,
                     (select count(*) from public.phase_d_personal_identifier_class
                       where detection = 'REGEX' and not supplier_facing_allowed),
                     coalesce(nullif(v_txt3,''),'(none named)') || ': ' || coalesce(v_rev_why,''),
                     (select count(*) from public.phase_d_personal_identifier_class
                       where detection = 'HUMAN_REVIEW'));
    return next; return;
  end if;`, 'BR-011');

// ---------------------------------------------------------------- BR-012 (redaction of the file set)
rule = swap(rule,
`    v_ok := (v_n >= 1) and public.fn_phase_c_actor_may_own(v_txt2);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-012: package %s resolves to %s approved supplier_safe_package record(s) in public.phase_d_object_record, and approver %s %s',
                     v_txt, v_n, v_txt2,
                     case when public.fn_phase_c_actor_may_own(v_txt2)
                          then 'resolves to an active canonical role'
                          else 'does not resolve to an active canonical role' end);
    return next; return;
  end if;`,
`    -- O04/O07. THE FILE SET WAS NEVER OPENED. This counted an approved package record and resolved
    -- the approver string, and stopped. Measured before the change: a package whose drawing carried
    -- an unapproved redaction and one whose drawing was clean returned the IDENTICAL ENFORCED_PASS.
    -- An identical answer to the injection and its control is the defect PD-PRIV-002 names, whatever
    -- the answer happens to be.
    --
    -- The leg below is the whole of the change: every LIVE revision registered against this package
    -- must be redaction-approved AND metadata-clean AT THE APPROVED DIGEST. The package answer is
    -- the WORST revision answer -- one leaking file in a set is a leak, so this is never an average
    -- and never a majority.
    select pr.dispatchable, pr.refusal_code, pr.reason into v_rev_ok, v_rev_code, v_rev_why
      from public.fn_phase_d_package_revisions_dispatchable(v_txt) pr;

    v_ok := (v_n >= 1) and public.fn_phase_c_actor_may_own(v_txt2) and v_rev_ok;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    if not v_rev_ok then refusal_code := v_rev_code; end if;
    reason := format('BR-012: package %s resolves to %s approved supplier_safe_package record(s) in public.phase_d_object_record, approver %s %s, and its file set: %s',
                     v_txt, v_n, v_txt2,
                     case when public.fn_phase_c_actor_may_own(v_txt2)
                          then 'resolves to an active canonical role'
                          else 'does not resolve to an active canonical role' end,
                     coalesce(v_rev_why,'(no verdict)'));
    return next; return;
  end if;`, 'BR-012');

// ---------------------------------------------------------------- BR-018 (normalisation)
rule = swap(rule,
`    v_ok := coalesce(btrim(p_context->>'quote_revision_ref'),'') <> ''
            and coalesce(p_context->>'platform_edited','true') = 'false';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-018: revision %s is supplier-authored and unedited; normalisation is separate',
                                         p_context->>'quote_revision_ref')
                   else 'BR-018: no unedited supplier revision named. The platform may normalise for comparison but never alter the original.' end;
    return next; return;
  end if;`,
`    -- O06/O07. THIS COMPARED NOTHING. The whole predicate was
    --   quote_revision_ref is non-empty AND platform_edited = 'false'
    -- which reads the CALLER'S OWN CLAIM ABOUT ITSELF: a normalisation that genuinely overwrote the
    -- supplier's figure and reported platform_edited = false passed. It is now a comparison of two
    -- records -- the live quotation_revision payload against the digest every live normalisation
    -- says it was derived from -- so an original that moved after it was normalised is visible
    -- whatever the caller says about itself.
    v_txt := btrim(coalesce(p_context->>'quote_revision_ref',''));
    select qi.intact, qi.refusal_code, qi.reason into v_rev_ok, v_rev_code, v_rev_why
      from public.fn_phase_d_quote_original_intact(v_txt) qi;
    v_ok := v_rev_ok;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    if not v_ok then refusal_code := v_rev_code; end if;
    reason := 'BR-018: ' || coalesce(v_rev_why, 'no verdict returned by fn_phase_d_quote_original_intact');
    return next; return;
  end if;`, 'BR-018');

// ---------------------------------------------------------------- BR-019 (publication)
rule = swap(rule,
`    select count(*) into v_n from public.quote_comparisons qc
     where qc.id::text = p_context->>'comparison_id'
       and qc.customer_id::text = p_context->>'caller_customer_id';
    v_ok := (v_n = 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-019: comparison %s %s the calling customer', p_context->>'comparison_id',
                     case when v_ok then 'belongs to' else 'does NOT belong to' end);
    return next; return;
  end if;`,
`    -- O06/O07. THIS TESTED OWNERSHIP AND CALLED IT PUBLICATION. The rule is "a customer sees only
    -- their own PUBLISHED comparison" and the predicate was count(*) ... where id = ? and
    -- customer_id = ?. A customer's own unpublished comparison passed, so the injection
    -- PD-QUOTE-004 names changed nothing a control could separate. Ownership is still tested --
    -- fn_phase_d_comparison_visible tests it FIRST and refuses an unrelated customer on a published
    -- comparison too, which is the arm proving the publication leg did not replace the ownership leg.
    select cv.visible, cv.refusal_code, cv.reason into v_rev_ok, v_rev_code, v_rev_why
      from public.fn_phase_d_comparison_visible(
             p_context->>'comparison_id', p_context->>'caller_customer_id',
             coalesce(nullif(btrim(p_context->>'caller_kind'),''), 'customer')) cv;
    v_ok := v_rev_ok;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    if not v_ok then refusal_code := v_rev_code; end if;
    reason := 'BR-019: ' || coalesce(v_rev_why, 'no verdict returned by fn_phase_d_comparison_visible');
    return next; return;
  end if;`, 'BR-019');

// declare the new variables the four branches use
rule = swap(rule,
  'declare\n',
  'declare\n  v_txt3 text; v_rev_ok boolean; v_rev_code text; v_rev_why text;   -- O07\n', 'rule declare');

// ---------------------------------------------------------------- GATE-013
gate = swap(gate,
`  elsif p_gate_id = 'GATE-013' then
    v_ok := public.fn_kernel_reviewer_independent(
              coalesce(p_evidence->>'actor_role_id', 'unknown'),
              p_evidence->>'safe_package_approved_by');
    reason := format('GATE-013: package %s approved by %s; independence %s',
                     p_evidence->>'safe_package_ref', p_evidence->>'safe_package_approved_by',
                     case when v_ok then 'holds' else 'FAILS — the approver is the author' end);`,
`  elsif p_gate_id = 'GATE-013' then
    -- O04/O07. THIS NEVER DEREFERENCED safe_package_ref. The value was required present by the
    -- generic evidence_keys loop and then used only inside format() for the reason string, so the
    -- gate could be satisfied by any package at all provided the approver was not the author.
    -- It now consults the same file-set verdict BR-012 does.
    select pr.dispatchable, pr.refusal_code, pr.reason into v_g13_ok, v_g13_code, v_g13_why
      from public.fn_phase_d_package_revisions_dispatchable(p_evidence->>'safe_package_ref') pr;
    v_ok := public.fn_kernel_reviewer_independent(
              coalesce(p_evidence->>'actor_role_id', 'unknown'),
              p_evidence->>'safe_package_approved_by')
            and v_g13_ok;
    if not v_g13_ok then refusal_code := v_g13_code; end if;
    reason := format('GATE-013: package %s approved by %s; independence %s; file set %s',
                     p_evidence->>'safe_package_ref', p_evidence->>'safe_package_approved_by',
                     case when public.fn_kernel_reviewer_independent(
                            coalesce(p_evidence->>'actor_role_id','unknown'),
                            p_evidence->>'safe_package_approved_by')
                          then 'holds' else 'FAILS — the approver is the author' end,
                     coalesce(v_g13_why,'(no verdict)'));`, 'GATE-013');

// ---------------------------------------------------------------- GATE-018
gate = swap(gate,
`  elsif p_gate_id = 'GATE-018' then
    select count(*) into v_n from public.quote_comparisons qc
     where qc.id::text = p_evidence->>'comparison_id'
       and qc.customer_id::text = p_evidence->>'caller_customer_id';
    v_ok := (v_n = 1);
    reason := format('GATE-018: comparison %s %s the calling customer', p_evidence->>'comparison_id',
                     case when v_ok then 'belongs to' else 'does NOT belong to' end);`,
`  elsif p_gate_id = 'GATE-018' then
    -- O06/O07. The byte-identical ownership count BR-019 carried, with the same defect: its
    -- refusal_code is gate018_comparison_not_publishable and it never read publishability.
    -- Changed with the rule and not after it -- fixing only one leaves the gate green on the same
    -- unpublished comparison, which is how a pair of predicates disagrees in silence.
    select cv.visible, cv.refusal_code, cv.reason into v_g13_ok, v_g13_code, v_g13_why
      from public.fn_phase_d_comparison_visible(
             p_evidence->>'comparison_id', p_evidence->>'caller_customer_id',
             coalesce(nullif(btrim(p_evidence->>'caller_kind'),''), 'customer')) cv;
    v_ok := v_g13_ok;
    if not v_ok then refusal_code := v_g13_code; end if;
    reason := 'GATE-018: ' || coalesce(v_g13_why, 'no verdict returned by fn_phase_d_comparison_visible');`, 'GATE-018');

// ---------------------------------------------------------------- GATE-027 / GATE-028
gate = swap(gate,
`  elsif p_gate_id in ('GATE-022','GATE-023','GATE-024','GATE-025','GATE-026','GATE-027',
                      'GATE-028','GATE-029','GATE-030') then
    v_ok := true;`,
`  elsif p_gate_id in ('GATE-027','GATE-028') then
    -- O03/O07. THE LEGAL AND TAX CURRENCY LEG, AND WHAT IT DELIBERATELY DOES NOT DO.
    --
    -- GATE-027 binds 10 W27 steps and GATE-028 binds 9 W28 steps. Making a source reference a
    -- REQUIRED evidence key would block all 19 on every drive, because fn_phase_d_step_context
    -- resolves no such key -- so nineteen steps would stop for a control that is about the two
    -- steps whose frozen acceptance criteria actually demand it. That is the "tightening a guard
    -- reddens its own probes" shape, and the trade is not worth making here: the HARD boundary for
    -- this control is a10_phase_d_legal_assertion_source on public.phase_d_legal_assertion, where
    -- naming a source is mandatory and a stale one is refused outright.
    --
    -- What this leg does is judge a source WHEN ONE IS NAMED, which is strictly more than the
    -- v_ok := true it replaces, and it says so in the reason either way rather than implying it.
    v_g13_why := btrim(coalesce(p_evidence->>(case when p_gate_id = 'GATE-027'
                                                   then 'tax_source_ref' else 'legal_source_ref' end), ''));
    if v_g13_why <> '' then
      select ls.usable, ls.refusal_code, ls.reason into v_g13_ok, v_g13_code, v_g13_why
        from public.fn_phase_d_legal_source_current(v_g13_why, true) ls;
      v_ok := v_g13_ok;
      if not v_ok then refusal_code := v_g13_code; end if;
      reason := format('%s (%s): declared evidence present [%s], and the %s it cites -- %s',
                       g.gate_id, g.gate_name, array_to_string(c.evidence_keys, ', '),
                       case when p_gate_id = 'GATE-027' then 'tax authority' else 'legal source' end,
                       coalesce(v_g13_why,'(no verdict)'));
    else
      v_ok := true;
      reason := format('%s (%s): all declared evidence is present and non-empty [%s]. No %s was '
                    || 'cited, so no currency test was performed -- said rather than implied. A '
                    || 'legal or tax assertion itself is refused at public.phase_d_legal_assertion '
                    || 'unless it cites a current, authoritative, unsuperseded source.',
                       g.gate_id, g.gate_name, array_to_string(c.evidence_keys, ', '),
                       case when p_gate_id = 'GATE-027' then 'tax_source_ref' else 'legal_source_ref' end);
    end if;

  elsif p_gate_id in ('GATE-022','GATE-023','GATE-024','GATE-025','GATE-026',
                      'GATE-029','GATE-030') then
    v_ok := true;`, 'GATE-027/028');

gate = swap(gate,
  'declare\n',
  'declare\n  v_g13_ok boolean; v_g13_code text; v_g13_why text;   -- O07\n', 'gate declare');

const head = (name, args, ret) => `CREATE OR REPLACE FUNCTION public.${name}(${args})
 RETURNS ${ret}
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$`;

writeFileSync(process.argv[2],
  head('fn_phase_d_rule_check', 'p_rule_id text, p_context jsonb',
       'TABLE(state text, ok boolean, rule_type text, enforced boolean, reason text, refusal_code text, evidence_absent boolean)')
  + rule + '$function$;\n\n'
  + head('fn_phase_d_gate_evaluate', 'p_gate_id text, p_evidence jsonb',
       'TABLE(state text, passed boolean, gate_type text, reason text, refusal_code text, evidence_absent boolean)')
  + gate + '$function$;\n');
console.log('spliced ok ->', process.argv[2]);
