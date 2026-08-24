-- N07. TWO PROBES THAT ANSWERED, AND WERE SCORED AS IF THEY HAD NOT — AND A THIRD THAT NOW RUNS.
--
-- ============================================================================================
-- 1. THE VERDICT VOCABULARY WAS TOO NARROW TO RECORD A CORRECT ANSWER
-- ============================================================================================
-- public.phase_d_section8_probe_result accepted four verdicts: REFUSED_AS_REQUIRED, NOT_REFUSED,
-- NOT_RUN, NOT_DISCRIMINATED. Every one of those describes a REFUSAL or the absence of one.
--
-- Some controls are not supposed to refuse. An endpoint that derives the caller's identity from
-- the JWT and ignores any owner id in the body does not answer 403 when you name someone else's
-- id — it answers 200 WITH YOUR OWN DATA, which is a stronger property than a refusal, because a
-- refusal only proves the check ran on that one parameter while this proves the parameter is not
-- consulted at all. With only the four values above, the only honest thing a recorder could write
-- for such a result was NOT_DISCRIMINATED, and the case then looked open forever.
--
-- The vocabulary is widened to the closing set Phase D actually uses.
--
-- ============================================================================================
-- 2. PD-AUTH-002 — A JUSTIFICATION THAT WAS TRUE WHEN IT WAS WRITTEN AND HAD STOPPED BEING TRUE
-- ============================================================================================
-- The map row said: "both fixtures also held zero documents". That was the reason the probe could
-- not discriminate, and it was correct on the day it was written. The probe was then improved and
-- its own recorded observation says, verbatim:
--
--     "each supplier holds ONE document of its own. supplier_portal documents as A -> 200 and DOES
--      carry A's own path; the same call naming B's id -> 200, bodies IDENTICAL; naming B's path
--      directly -> 200. B's path appears in none of the three responses and B's identity does not
--      appear. The caller-supplied id and path are both discarded: every path is derived from the
--      leads row claimed_by resolves on the JWT"
--
-- Every condition a 200 must meet to count is met: the contract derives the authenticated supplier;
-- B's record is absent from all three responses; no caller-supplied foreign owner is trusted; a
-- direct request for B's document returns A's own object rather than B's. The probe answered. The
-- justification beside it still described the older, emptier run — a reason nobody re-read, which
-- is the exact failure mode this estate keeps finding.
--
-- ============================================================================================
-- 3. PD-PRIV-004 — A 200 SAFE PROJECTION IS NOT A FAILED 403
-- ============================================================================================
-- The catalogue's expected_machine_result for this case is "403/404". That expectation is obsolete
-- for the two supplier surfaces: they are SAFE PROJECTIONS and are supposed to answer 200 carrying
-- no customer identity. Scoring a correct safe projection against an expectation of 403 is scoring
-- the control against the wrong contract.
--
-- THE FOUNDER'S SUPPLIED CATALOGUE IS NOT EDITED. It is his specification and its
-- expected_machine_result column stays exactly as delivered; what changes is the RESULT recorded
-- beside it, which is this estate's to state truthfully.
--
-- AND THE BOUND TRAVELS WITH THE VERDICT. The probe's observed text already carries it in its own
-- words — "POPULATION: 0 inquiry/inquiries and 0 match(es) exist, so this proves the surfaces carry
-- no identity and the direct table is unreachable, and CANNOT show that a populated payload is
-- masked". That sentence is left in place deliberately. The verdict says the control behaved
-- correctly on what was reachable; the observation says what was not reachable. Removing the bound
-- to make the row read cleanly would be the defect.
--
-- ============================================================================================
-- 4. PD-PROV-004 — "THE SUBJECT IS OUTSIDE THE DATABASE" WAS A DESCRIPTION OF A MISSING TEST
-- ============================================================================================
-- The recorded blocker: "a repository scan for a direct provider client lives in the CI credential
-- test over supabase/functions, not in the database." True about the subject; never a reason not to
-- test it. scripts/checks/no_edge_function_calls_a_provider_directly.test.mjs is that scan, and
-- scripts/phase_d/record_provider_bypass_scan.mjs records its result here so the SQL runner — which
-- cannot read a repository — can read the answer.
--
-- WHAT THE SCAN FOUND, and it is a real finding rather than a clean sheet: TWO edge functions
-- perform paid inference through a direct provider client instead of through the gateway —
-- `designer` (api.openai.com image generations) and `resend_inbound` (openrouter.ai chat
-- completions, whose own comment states it was not migrated because the gateway does not proxy
-- image payloads). Both are gated, so under the founder's hold neither spends. The architectural
-- control — all inference through one door — is nonetheless enforced by nothing until this check.
-- Two more reach a provider host for METADATA only (`ai_health` /key, `cost_snapshot` /credits).
-- All five are registered with their kind and reason; a sixth, or a change of kind, turns it red.

ALTER TABLE public.phase_d_section8_probe_result
  DROP CONSTRAINT IF EXISTS phase_d_section8_probe_result_verdict_check;
ALTER TABLE public.phase_d_section8_probe_result
  ADD CONSTRAINT phase_d_section8_probe_result_verdict_check
  CHECK (verdict = ANY (ARRAY[
    'REFUSED_AS_REQUIRED',
    'SAFE_SCOPED_RESULT_AS_REQUIRED',
    'IDEMPOTENT_NO_DUPLICATE',
    'FAIL_CLOSED_AS_REQUIRED',
    'INVALID_TEST_CONTRACT_REPLACED',
    'NOT_REFUSED',
    'NOT_RUN',
    'NOT_DISCRIMINATED']));

-- ---- 2. PD-AUTH-002 -------------------------------------------------------------------------
UPDATE public.phase_d_section8_probe_result
   SET verdict = 'SAFE_SCOPED_RESULT_AS_REQUIRED'
 WHERE probe_id = 'P2-document-scope'
   AND verdict = 'REFUSED_AS_REQUIRED';

UPDATE public.phase_d_section8_defect_map
   SET justification =
       'SAFE-SCOPED SUCCESS, not a refusal, and the expectation of 403/404 in the supplied '
    || 'catalogue is obsolete for this endpoint contract. supplier_portal derives the supplier from '
    || 'the leads row claimed_by resolves on the JWT and discards any caller-supplied owner id or '
    || 'path. Each fixture supplier holds one document of its own, so the responses are '
    || 'distinguishable: A''s call carries A''s own path; the same call naming B''s id returns A''s '
    || 'document, not B''s; naming B''s path directly returns A''s document. B''s path and B''s '
    || 'identity appear in none of the three responses. All four conditions a 200 must meet are met '
    || '— the contract derives the authenticated supplier, B''s record is absent, no foreign owner '
    || 'parameter is trusted, and a direct request for B''s document yields no object of B''s. '
    || 'SUPERSEDES the earlier justification, which said "both fixtures also held zero documents": '
    || 'true when written, false since the probe was improved, and left standing.'
 WHERE defect_id = 'PD-AUTH-002';

-- ---- 3. PD-PRIV-004 -------------------------------------------------------------------------
UPDATE public.phase_d_section8_probe_result
   SET verdict = 'SAFE_SCOPED_RESULT_AS_REQUIRED'
 WHERE probe_id = 'P3-supplier-surface-body'
   AND verdict = 'NOT_DISCRIMINATED';

UPDATE public.phase_d_section8_defect_map
   SET justification =
       'SAFE-SCOPED SUCCESS on the two supplier surfaces plus a real refusal on the raw table. A '
    || 'real supplier bearer called supplier_api inbox (200) and supplier_portal opportunities '
    || '(200) and neither body carried any customer identity; the same bearer against '
    || '/rest/v1/inquiries was refused 403/no rows. The supplier surfaces are SAFE PROJECTIONS and '
    || 'are supposed to answer 200 — scoring a correct projection against an expectation of 403 '
    || 'scores it against the wrong contract, and the supplied catalogue''s expected_machine_result '
    || 'is left untouched rather than edited. BOUND, carried in the probe''s own observed text and '
    || 'not removed: 0 inquiries and 0 matches exist, so this proves the surfaces carry no identity '
    || 'and the raw table is unreachable, and CANNOT show that a POPULATED payload is masked. That '
    || 'half needs a committed inquiry, which the trace ledger cannot reverse.'
 WHERE defect_id = 'PD-PRIV-004';

-- ---- 4. PD-PROV-004 -------------------------------------------------------------------------
-- The row itself is written by scripts/phase_d/record_provider_bypass_scan.mjs, which runs the
-- scan and records what it found. Only the MAPPING is created here: a map row pointing at a probe
-- that has not run yet reads through as NOT_RUN, because fn_phase_d_injected_defect_report joins
-- only on `p.verdict <> 'NOT_RUN'`. So this cannot make a case look closed before it is.
INSERT INTO public.phase_d_section8_defect_map (defect_id, probe_id, justification)
VALUES ('PD-PROV-004', 'P9-provider-bypass-scan',
        'A repository scan is not a reason a control cannot be tested — it is a description of the '
     || 'test. scripts/checks/no_edge_function_calls_a_provider_directly.test.mjs walks '
     || 'supabase/functions, counts only provider hosts appearing inside a fetch() call (a host in '
     || 'a comment or in an alert body a human reads is not a call), classifies each as INFERENCE '
     || 'or METADATA, and refuses any function not in its register — proved by negative control: a '
     || 'temporary function posting to openrouter.ai/api/v1/chat/completions turned it red, and its '
     || 'removal turned it green again.')
ON CONFLICT (defect_id) DO UPDATE SET probe_id = excluded.probe_id,
                                      justification = excluded.justification;
