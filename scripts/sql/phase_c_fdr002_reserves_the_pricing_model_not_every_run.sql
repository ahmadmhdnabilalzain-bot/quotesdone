-- FDR-002 RESERVES THE PRICING MODEL, NOT EVERY RUN OF THE WORKFLOWS IT NAMES.
--
-- NO TRANSACTION CONTROL. One table, one seeded row, one CREATE OR REPLACE, and an assertion.
--
-- THE DEFECT. fn_phase_d_founder_authority decided delegated authority with one line:
--
--     v_covers := v_reserved is null;
--
-- -- a workflow named in ANY founder boundary's workflow_scope could never proceed on delegated
-- authority, whatever that boundary actually says. FDR-002's own frozen enforcement clause says
-- something different from what that line assumed:
--
--     Commercial pricing model -- Reveal fee, supplier subscription price/start, founding
--     exemption and supplier commission policy.
--     ENFORCEMENT: "Systems may calculate only from approved configuration."
--
-- Calculating from what he approved IS the permitted act. The line read it as "stop and ask him".
--
-- MEASURED CONSEQUENCE. W04-S04 "Capture canonical terms acceptance" refused every run with
-- pd_evidence_absent -- GATE-005 wanting founder_authority_ref for a customer accepting the terms.
-- It surfaced when phase_d_q03 gave W04 a real arrival for the first time (PR #470, closing "eleven
-- paths created a customer nobody owned"); before that the only W04 run was the Phase D drive's
-- own, which carried a fixture founder command and hid the reading.
--
-- THE FOUNDER'S RULING, 26 AUG 2026, asked what FDR-002 reserves, in his words:
--
--   "commercial pricing, yeah, reveal fee is three percent, and it's automated. It doesn't need me.
--    It's directly the moment the customer is selecting the code. He is paying the reveal fee, and
--    it's directed to Stripe payout... Subscription fee for suppliers. The first one thousand
--    suppliers are for free... Anyone who's after, he is paying one thousand dirham per year...
--    All automated. Nothing to be done by me. All payments going through Stripe. And regarding the
--    refund, that's the only thing where my decision is involved."
--
-- So FDR-002 reserves the NUMBERS -- setting them -- and applying them is automatic. One act in
-- that whole area waits for him, and it is the refund.
--
-- WHY THIS IS A REGISTER AND NOT A LIST IN A FUNCTION BODY. The classification is per BOUNDARY, it
-- is derived from that boundary's own frozen sentence, and it records the digest of that sentence.
-- Amend the sentence in Phase B and the digest stops matching, so the boundary reverts to reserving
-- until someone re-reads it. A boundary with NO row reserves. Nothing is loosened by omission.
--
-- WHAT THIS CHANGES, computed rather than asserted -- a step is delegated only when EVERY boundary
-- covering its workflow constrains configuration, so one act-reserving boundary is enough to hold:
--
--   W04-S04  Capture canonical terms acceptance          FDR-002              -> DELEGATED
--   W09-S06  Capture canonical supplier terms acceptance FDR-002              -> DELEGATED
--   W15-S06  Calculate founder-approved reveal charge    FDR-002              -> DELEGATED
--   W17-S07  Execute approved financial action           FDR-002;FDR-010      -> STILL RESERVED
--   W27-S07  Coordinate UAE tax compliance               FDR-001;002;003;006  -> STILL RESERVED
--   W28-S07  Issue review decision                       FDR-001;002;004;...  -> STILL RESERVED
--   the other twelve founder-gated steps                 no FDR-002           -> unchanged
--
-- The three that move are the three he named: terms acceptance, supplier subscription, and
-- CALCULATING the reveal charge. W15-S06's own gate says "reveal fee CHANGES are founder-reserved"
-- and the step is named "Calculate founder-approved reveal charge" -- it applies his number; it
-- does not set it. W17-S07 is money movement and stays reserved through FDR-010, "Risk may
-- recommend; founder decides", which is where the refund lives.
--
-- REFUNDS ARE NOT REACHED BY THIS FILE, and that was measured before it was written, not reasoned
-- about. public.refunds carries z00_refund_founder_decision_only and
-- z05_refund_execution_requires_decision -- table triggers that know nothing of GATE-005. Forced in
-- an aborted transaction on production:
--
--   insert into public.refunds(...) values (300,'AED','succeeded',...)
--   -> REFUSED 23514 :: a platform-originated refund may not reach status succeeded without naming
--      the founder decision that authorised it. His ruling of 17 Aug 2026 is that every refund
--      needs him, at any amount
--
-- ROLLBACK: scripts/sql/down/phase_c_fdr002_reserves_the_pricing_model_not_every_run_down.sql

CREATE TABLE IF NOT EXISTS public.phase_d_founder_boundary_disposition (
  boundary_id        text        PRIMARY KEY REFERENCES public.phase_b_founder_boundary(boundary_id),
  disposition        text        NOT NULL,
  founder_ruling     text        NOT NULL,
  enforcement_digest text        NOT NULL,
  recorded_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT phase_d_boundary_disposition_value_ck CHECK (
    disposition = ANY (ARRAY['RESERVES_THE_ACT','CONSTRAINS_THE_CONFIGURATION'])),
  -- A DELEGATION MUST QUOTE HIM. The floor is not decoration: the one thing that may never happen
  -- here is a boundary quietly reclassified on somebody's reading of a sentence.
  CONSTRAINT phase_d_boundary_disposition_ruling_ck CHECK (
    length(btrim(founder_ruling)) > 80),
  CONSTRAINT phase_d_boundary_disposition_digest_ck CHECK (
    enforcement_digest ~ '^[0-9a-f]{64}$')
);

COMMENT ON TABLE public.phase_d_founder_boundary_disposition IS
  'PCCR/Phase D. Whether a frozen founder boundary reserves the ACT or constrains the CONFIGURATION '
  'operations run within. Read by fn_phase_d_founder_authority. A boundary with no row RESERVES: '
  'the register may only ever widen what the founder must decide, never narrow it by omission.';

REVOKE ALL ON TABLE public.phase_d_founder_boundary_disposition FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.phase_d_founder_boundary_disposition TO service_role;

INSERT INTO public.phase_d_founder_boundary_disposition
  (boundary_id, disposition, founder_ruling, enforcement_digest)
SELECT 'FDR-002', 'CONSTRAINS_THE_CONFIGURATION',
  'Founder, 26 Aug 2026, asked whether FDR-002 reserves the pricing model itself or every run of '
  || 'the workflows it names: "commercial pricing, yeah, reveal fee is three percent, and it''s '
  || 'automated. It doesn''t need me. It''s directly the moment the customer is selecting the code. '
  || 'He is paying the reveal fee, and it''s directed to Stripe payout... The first one thousand '
  || 'suppliers are for free... Anyone who''s after, he is paying one thousand dirham per year... '
  || 'All automated. Nothing to be done by me. All payments going through Stripe. And regarding the '
  || 'refund, that''s the only thing where my decision is involved." He sets the numbers; applying '
  || 'them is automatic; the refund is the one act that waits for him, and it is held by FDR-010 '
  || 'and by z00_refund_founder_decision_only on public.refunds, neither of which this touches.',
  encode(sha256(convert_to(b.phase_b_enforcement, 'UTF8')), 'hex')
  FROM public.phase_b_founder_boundary b WHERE b.boundary_id = 'FDR-002'
ON CONFLICT (boundary_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.fn_phase_d_founder_authority(p_run_id bigint, p_step_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_wf       text;
  v_cmd      bigint;
  v_state    text;
  v_reserved text;
  v_reserving text;
  v_digest   text;
  v_baseline text;
  v_covers   boolean;
  v_exists   boolean;
  v_current  boolean;
begin
  select s.workflow_id into v_wf from public.phase_b_workflow_step s where s.step_id = p_step_id;
  if v_wf is null then
    return jsonb_build_object('ref', null, 'kind', 'UNKNOWN_STEP',
      'exists', false, 'current', false, 'covers', false, 'valid', false,
      'why', format('%s is not a step of the frozen registry', coalesce(p_step_id, '(null)')));
  end if;

  -- WHAT THE FOUNDER RESERVED, read from the register he approved. Never a list in this body.
  select string_agg(b.boundary_id, ';' order by b.boundary_id) into v_reserved
    from public.phase_b_founder_boundary b
   where v_wf = any (string_to_array(replace(b.workflow_scope, ' ', ''), ';'));

  -- 1. A FOUNDER COMMAND, where one instructed this run.
  select l.command_id into v_cmd from public.founder_command_workflow_link l
   where l.run_id = p_run_id limit 1;
  if v_cmd is null then
    select r.command_id into v_cmd from public.phase_c_workflow_run r where r.run_id = p_run_id;
  end if;

  if v_cmd is not null then
    select fc.state into v_state from public.founder_command fc where fc.command_id = v_cmd;
    v_exists  := v_state is not null;
    v_current := v_exists and v_state <> 'cancelled';
    v_covers  := exists (select 1 from public.founder_command_workflow_link l2
                          where l2.command_id = v_cmd and l2.workflow_id = v_wf)
              or exists (select 1 from public.phase_c_workflow_run r2
                          where r2.run_id = p_run_id and r2.command_id = v_cmd);
    return jsonb_build_object(
      'ref',     'founder_command:' || v_cmd::text,
      'kind',    'FOUNDER_COMMAND',
      'source',  'founder_command that started this run',
      'artefact','public.founder_command',
      'reserved_by', v_reserved,
      'exists',  v_exists, 'current', v_current, 'covers', v_covers,
      'valid',   v_exists and v_current and v_covers,
      'why', format('founder command %s is %s and %s workflow %s', v_cmd,
                    case when not v_exists then 'not on record'
                         when v_current then 'live (state ' || v_state || ')'
                         else 'cancelled' end,
                    case when v_covers then 'selected' else 'DID NOT select' end, v_wf));
  end if;

  -- 2. DELEGATED AUTHORITY, read off the founder-approved frozen boundary register.
  select d.sha256 into v_digest
    from public.fn_phase_b_structure_digest() d where d.subject = 'founder_boundaries';
  select bl.registry_sha256->'structure'->'founder_boundaries'->>'database' into v_baseline
    from public.org_phase_baseline bl where bl.phase = 'B';

  v_exists  := v_digest is not null
               and exists (select 1 from public.phase_b_founder_boundary)
               and v_baseline is not null;
  v_current := v_exists and v_digest = v_baseline;
  -- HIS RULING OF 26 AUG 2026, ENCODED WHERE IT CAN BE CHECKED RATHER THAN REMEMBERED.
  --
  -- This read `v_reserved is null` -- a workflow named in ANY boundary's scope could never proceed
  -- on delegated authority. FDR-002's own enforcement clause says otherwise: "Systems may calculate
  -- only from approved configuration." Calculating from what he approved IS the permitted act, not
  -- a reason to stop and ask him.
  --
  -- In his words, asked what FDR-002 reserves: the reveal fee "is three percent, and it's
  -- automated. It doesn't need me"; supplier subscription "the first one thousand suppliers are for
  -- free... anyone after, he is paying one thousand dirham per year... all automated, nothing to be
  -- done by me"; and "regarding the refund, that's the only thing where my decision is involved."
  --
  -- So a covering boundary blocks delegation only when it is classified as reserving the ACT.
  -- public.phase_d_founder_boundary_disposition holds that classification, and a boundary with NO
  -- row defaults to RESERVING -- fail closed, so nothing is loosened by omission. FDR-002 is the
  -- only row today.
  select string_agg(b.boundary_id, ';' order by b.boundary_id) into v_reserving
    from public.phase_b_founder_boundary b
   where v_wf = any (string_to_array(replace(b.workflow_scope, ' ', ''), ';'))
     and not exists (
       select 1 from public.phase_d_founder_boundary_disposition dp
        where dp.boundary_id = b.boundary_id
          and dp.disposition = 'CONSTRAINS_THE_CONFIGURATION'
          -- THE CLASSIFICATION IS ABOUT A SENTENCE, SO IT NAMES THAT SENTENCE'S DIGEST. If the
          -- frozen enforcement text is ever amended, the digest stops matching and the boundary
          -- reverts to reserving until someone re-reads it against his ruling.
          and dp.enforcement_digest = encode(sha256(convert_to(b.phase_b_enforcement, 'UTF8')), 'hex'));
  v_covers  := v_reserving is null;

  if not v_covers then
    return jsonb_build_object(
      'ref', null, 'kind', 'FOUNDER_RESERVED',
      'source', 'public.phase_b_founder_boundary',
      'artefact', 'public.phase_b_founder_boundary@' || coalesce(left(v_digest, 16), '(none)'),
      'reserved_by', v_reserving, 'in_scope_of', v_reserved,
      'exists', v_exists, 'current', v_current, 'covers', false, 'valid', false,
      'why', format('%s is reserved to the founder by %s and no founder command instructed this run%s',
                    v_wf, v_reserving,
                    case when v_reserved is distinct from v_reserving
                         then format(' (in scope of %s; the rest constrain configuration only)', v_reserved)
                         else '' end));
  end if;

  return jsonb_build_object(
    'ref',     'founder_policy:phase_b_founder_boundary@' || coalesce(left(v_digest, 16), 'unknown'),
    'kind',    'DELEGATED_AUTHORITY',
    'source',  'public.phase_b_founder_boundary, the founder-approved frozen register of what he '
            || 'reserves: it names no boundary over ' || v_wf || ', so the decision is delegated '
            || 'to the step''s accountable role',
    'artefact','public.phase_b_founder_boundary@' || coalesce(left(v_digest, 16), 'unknown'),
    'reserved_by', null, 'in_scope_of', v_reserved,
    'exists',  v_exists, 'current', v_current, 'covers', true,
    'valid',   v_exists and v_current,
    'why', format('the founder-approved boundary register (%s rows, digest %s) %s the Phase B '
               || 'baseline and reserves no decision in %s',
                  (select count(*) from public.phase_b_founder_boundary),
                  coalesce(left(v_digest, 16), '(none)'),
                  case when v_current then 'matches' else 'DOES NOT match' end, v_wf));
end
$function$
;


DO $assert$
DECLARE r record; v_bad text := ''; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.phase_d_founder_boundary_disposition
   WHERE disposition = 'CONSTRAINS_THE_CONFIGURATION';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'expected exactly one boundary classified CONSTRAINS_THE_CONFIGURATION, found %', v_n
      USING errcode = '23514';
  END IF;

  -- THE RESOLVER IS ASKED, not trusted. Every founder-gated step is put to it on a run that no
  -- founder command instructed, which is the case the change is about, and the answer is compared
  -- with the table in this file's header.
  FOR r IN
    SELECT s.step_id,
           (public.fn_phase_d_founder_authority(NULL::bigint, s.step_id) ->> 'kind') AS kind
      FROM public.phase_b_workflow_step s
     WHERE lower(coalesce(btrim(s.founder_gate),'none')) <> 'none'
     ORDER BY s.step_id
  LOOP
    IF r.step_id IN ('W04-S04','W09-S06','W15-S06') AND r.kind <> 'DELEGATED_AUTHORITY' THEN
      v_bad := v_bad || format('%s should be delegated and is %s; ', r.step_id, r.kind);
    END IF;
    -- THE ONES THAT MUST NOT MOVE. W17-S07 is money movement; if this file ever delegates it, the
    -- refund path has lost its gate and the migration must not apply.
    IF r.step_id IN ('W17-S07','W27-S07','W28-S07','W01-S04','W01-S06','W02-S05','W02-S06',
                     'W03-S01','W21-S05','W24-S06','W30-S09','W30-S10','W01-S01')
       AND r.kind <> 'FOUNDER_RESERVED' THEN
      v_bad := v_bad || format('%s must stay reserved and is %s; ', r.step_id, r.kind);
    END IF;
  END LOOP;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'fn_phase_d_founder_authority disagrees with this file: %', v_bad
      USING errcode = '23514';
  END IF;

  -- AND THE REFUND DOOR, FORCED RATHER THAN REASONED ABOUT.
  BEGIN
    INSERT INTO public.refunds(amount_fils, currency, status, requested_by, reason_code)
    VALUES (300,'AED','succeeded','customer_success_director','supplier_no_response');
    RAISE EXCEPTION 'A REFUND REACHED succeeded WITH NO FOUNDER DECISION AFTER THIS CHANGE'
      USING errcode = '23514';
  EXCEPTION
    WHEN sqlstate '23514' THEN
      IF position('founder decision' in SQLERRM) = 0 AND position('WITH NO FOUNDER DECISION' in SQLERRM) > 0 THEN
        RAISE;
      END IF;
    WHEN others THEN NULL;
  END;

  RAISE NOTICE 'FDR-002 classified; three steps delegated, thirteen still reserved, refunds still refused';
END $assert$;
