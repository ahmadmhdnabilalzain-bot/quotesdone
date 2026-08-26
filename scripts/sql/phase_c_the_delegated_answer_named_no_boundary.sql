-- THE DELEGATED ANSWER SAID W04 HAD NO BOUNDARY, AND FDR-002 NAMES IT.
--
-- NO TRANSACTION CONTROL. One CREATE OR REPLACE and an assertion.
--
-- phase_c_fdr002_reserves_the_pricing_model_not_every_run.sql made the VERDICT right and left the
-- SENTENCE behind it stale. Read back from production immediately after applying it, for W04-S04:
--
--   kind    DELEGATED_AUTHORITY        in_scope_of  FDR-002
--   source  "...it names no boundary over W04, so the decision is delegated..."
--   why     "...matches the Phase B baseline and reserves no decision in W04"
--
-- FDR-002 DOES name W04 -- the structured field two lines above says so. What is true is that it
-- constrains the configuration rather than reserving the act. A reader taking that sentence at face
-- value would conclude the commercial pricing boundary does not reach customer onboarding at all,
-- which is exactly the wrong conclusion to leave lying around beside a correct verdict.
--
-- This estate has a name for the shape: an instrument reporting on the wrong subject. It is the
-- most repeated defect class in its history, and it does not stop being one because the number next
-- to the sentence happens to be right.
--
-- Both strings now branch on whether any boundary names the workflow, and name them when they do:
--   "every boundary naming W04 (FDR-002) constrains the configuration operations run within
--    rather than reserving the act"
--   "...reserves no ACT in W04 (FDR-002 name it and constrain configuration only)"
--
-- ROLLBACK: scripts/sql/down/phase_c_the_delegated_answer_named_no_boundary_down.sql

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
            || 'reserves: '
            || case when v_reserved is null
                    then 'it names no boundary over ' || v_wf
                    else 'every boundary naming ' || v_wf || ' (' || v_reserved || ') constrains the '
                      || 'configuration operations run within rather than reserving the act' end
            || ', so the decision is delegated to the step''s accountable role',
    'artefact','public.phase_b_founder_boundary@' || coalesce(left(v_digest, 16), 'unknown'),
    'reserved_by', null, 'in_scope_of', v_reserved,
    'exists',  v_exists, 'current', v_current, 'covers', true,
    'valid',   v_exists and v_current,
    'why', format('the founder-approved boundary register (%s rows, digest %s) %s the Phase B '
               || 'baseline and reserves no ACT in %s%s',
                  (select count(*) from public.phase_b_founder_boundary),
                  coalesce(left(v_digest, 16), '(none)'),
                  case when v_current then 'matches' else 'DOES NOT match' end, v_wf,
                  case when v_reserved is null then ''
                       else format(' (%s name it and constrain configuration only)', v_reserved) end));
end
$function$
;

DO $assert$
DECLARE v jsonb;
BEGIN
  v := public.fn_phase_d_founder_authority(NULL::bigint, 'W04-S04');
  IF v->>'kind' <> 'DELEGATED_AUTHORITY' THEN
    RAISE EXCEPTION 'W04-S04 is % and must be DELEGATED_AUTHORITY', v->>'kind' USING errcode = '23514';
  END IF;
  IF position('names no boundary' in (v->>'source')) > 0 THEN
    RAISE EXCEPTION 'the delegated answer still claims W04 has no boundary: %', v->>'source'
      USING errcode = '23514';
  END IF;
  IF position('FDR-002' in (v->>'source')) = 0 OR position('FDR-002' in (v->>'why')) = 0 THEN
    RAISE EXCEPTION 'the delegated answer for W04-S04 does not name FDR-002: source=% why=%',
      v->>'source', v->>'why' USING errcode = '23514';
  END IF;

  -- A WORKFLOW GENUINELY OUTSIDE EVERY BOUNDARY MUST STILL SAY SO, or this file has traded one
  -- untrue sentence for another. W18 is in no boundary's scope at all.
  v := public.fn_phase_d_founder_authority(NULL::bigint, 'W18-S05');
  IF position('names no boundary over W18' in (v->>'source')) = 0 THEN
    RAISE EXCEPTION 'W18-S05 is in no boundary scope and the answer no longer says so: %', v->>'source'
      USING errcode = '23514';
  END IF;

  -- AND A RESERVED ONE MUST STILL REFUSE.
  v := public.fn_phase_d_founder_authority(NULL::bigint, 'W17-S07');
  IF v->>'kind' <> 'FOUNDER_RESERVED' OR (v->>'reserved_by') NOT LIKE '%FDR-010%' THEN
    RAISE EXCEPTION 'W17-S07 must stay reserved by FDR-010 and reads kind=% reserved_by=%',
      v->>'kind', v->>'reserved_by' USING errcode = '23514';
  END IF;

  RAISE NOTICE 'the delegated answer names the boundaries that cover the workflow';
END $assert$;
