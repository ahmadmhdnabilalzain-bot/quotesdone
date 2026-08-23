// K01 — GATE-005 asked for half of the evidence its own frozen text names.
//
// Generates scripts/sql/phase_d_k01_*.sql from the LIVE bodies.
import { writeFileSync } from 'node:fs';
import { liveBody, splice } from './splice.mjs';

const HEADER = `-- K01 — the founder boundary gate asked for half of the evidence its own frozen text names
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh.  W05-S07 "Decide qualification status" was the one
-- founder-gated step of the 257 that produced no declared effect:
--
--   gate005_founder_boundary :: GATE-005 (Founder boundary) requires [founder_authority_ref] and
--   the call names none of it.
--
-- GATE-005's frozen required_evidence, in public.phase_b_gate, is TWO alternatives:
--
--   "Decision is within delegated authority OR founder approval exists."
--
-- public.phase_d_gate_contract implements only the second.  Its evidence_keys are
-- ["step_id","founder_authority_ref"], and public.fn_phase_d_step_context answered that key from a
-- founder command and from nothing else.  A step whose run no founder instructed could therefore
-- never satisfy the gate, however plainly the decision was delegated.
--
-- WHICH STEPS THIS IS ABOUT, measured rather than assumed.  GATE-005 applies where the frozen step
-- declares a founder_gate other than 'none' -- 18 of the 257 steps, in 14 workflows.  Cross those
-- 14 workflows against the founder's own frozen boundary register, public.phase_b_founder_boundary:
--
--   16 of the 18 sit in a workflow at least one boundary scopes.  W17-S07 is FDR-002 and FDR-010,
--      W01-S04 is FDR-001/003/004/005/006, and so on.  For those the founder HAS reserved the
--      decision and only a founder command can answer.  Nothing below changes them.
--   W05-S07 and W18-S05 sit in workflows NO boundary scopes.  FDR-001..FDR-010 name
--      W01;W02;W03;W04;W09;W15;W16;W17;W20;W21;W23;W24;W25;W27;W28;W29;W30 between them, and
--      neither W05 nor W18 is among them.
--
-- W05 is the inquiry qualification workflow.  Its run is started in production by
-- trg_inquiry_received_a when a customer's inquiry arrives -- source_kind 'trigger', command_id
-- null -- so if GATE-005 could only be answered by a founder command, every customer inquiry in
-- production would block at qualification waiting for an approval the founder does not give.  His
-- ruling of 17 Aug 2026 is that he approves refunds.  A founder command attached to a run a
-- customer's inquiry started would be a forgery, and this file does not create one.
--
-- WHAT THE DELEGATION REFERENCE IS.  public.phase_b_founder_boundary is the founder-approved,
-- Phase-B-frozen, digest-guarded statement of what he reserves.  A decision in a workflow that
-- register does not name is delegated BY THAT REGISTER -- a positive fact read off an approved
-- artefact, not an absence.  fn_phase_d_founder_authority returns it as one immutable canonical
-- reference naming the artefact and its digest:
--
--   founder_policy:phase_b_founder_boundary@<digest>
--
-- and the digest is public.fn_phase_b_structure_digest()'s own 'founder_boundaries' row, the same
-- value public.org_phase_baseline holds for phase B and the same one fn_phase_b_baseline_drift
-- compares.  If the register changes, the reference changes and stops matching the approved
-- baseline, and the authority is refused until the founder approves the new register.  That is what
-- "exists, is current, and covers the action" means here, and each of the three is a separate
-- column of the answer.
--
-- AND GATE-005 NOW CHECKS IT.  The evaluator's body for GATE-005 was \`v_ok := true\` -- presence of
-- a string, never its validity, so any caller could have handed it any text.  It now resolves the
-- authority itself and requires the presented reference to be the one that resolves.
--
-- THE DEAD LOOKUP.  fn_phase_d_step_context read
-- \`founder_command_workflow_link.command_id where run_id = sr.run_id\` first, and
-- fn_phase_d_drive_workflow inserted that link with (command_id, workflow_id) and no run_id: 15 of
-- 15 rows in the table carry run_id null, so that branch had never matched anything and every
-- resolution that ever succeeded came from the fallback.  The run_id is now stamped, and ONLY where
-- the kernel's own row says the command started the run -- never onto a run some other arrival
-- started, which is the forgery above.
--
-- ROLLBACK: scripts/sql/down/phase_d_k01_the_gate_asked_for_half_the_evidence_its_text_names_down.sql
-- re-applies the previous bodies of fn_phase_d_step_context, fn_phase_d_gate_evaluate and
-- fn_phase_d_drive_workflow and drops fn_phase_d_founder_authority.
--
-- GENERATED from the live bodies by scripts/tmp_diag/gen_k01.mjs.
`;

// ---- 1. the resolver ---------------------------------------------------------------------------
const RESOLVER = `
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
  v_covers  := v_reserved is null;

  if not v_covers then
    return jsonb_build_object(
      'ref', null, 'kind', 'FOUNDER_RESERVED',
      'source', 'public.phase_b_founder_boundary',
      'artefact', 'public.phase_b_founder_boundary@' || coalesce(left(v_digest, 16), '(none)'),
      'reserved_by', v_reserved,
      'exists', v_exists, 'current', v_current, 'covers', false, 'valid', false,
      'why', format('%s is reserved to the founder by %s and no founder command instructed this run',
                    v_wf, v_reserved));
  end if;

  return jsonb_build_object(
    'ref',     'founder_policy:phase_b_founder_boundary@' || coalesce(left(v_digest, 16), 'unknown'),
    'kind',    'DELEGATED_AUTHORITY',
    'source',  'public.phase_b_founder_boundary, the founder-approved frozen register of what he '
            || 'reserves: it names no boundary over ' || v_wf || ', so the decision is delegated '
            || 'to the step''s accountable role',
    'artefact','public.phase_b_founder_boundary@' || coalesce(left(v_digest, 16), 'unknown'),
    'reserved_by', null,
    'exists',  v_exists, 'current', v_current, 'covers', true,
    'valid',   v_exists and v_current,
    'why', format('the founder-approved boundary register (%s rows, digest %s) %s the Phase B '
               || 'baseline and reserves no decision in %s',
                  (select count(*) from public.phase_b_founder_boundary),
                  coalesce(left(v_digest, 16), '(none)'),
                  case when v_current then 'matches' else 'DOES NOT match' end, v_wf));
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_founder_authority(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_founder_authority(bigint, text) TO service_role;
`;

// ---- 2. fn_phase_d_step_context ----------------------------------------------------------------
const ctx = splice(await liveBody('fn_phase_d_step_context'), [
  [`  v_cmd    bigint;`,
   `  v_cmd    bigint;\n  v_auth   jsonb;   -- K01`],
  [`    elsif v_k = 'founder_authority_ref' then
      select l.command_id into v_cmd from public.founder_command_workflow_link l
        where l.run_id = sr.run_id limit 1;
      if v_cmd is null then v_cmd := r.command_id; end if;
      if v_cmd is not null then
        v_val := to_jsonb('founder_command:' || v_cmd::text);
        v_src := 'founder_command that started this run';
      end if;`,
   `    elsif v_k = 'founder_authority_ref' then
      -- K01. GATE-005's frozen evidence is "Decision is within delegated authority OR founder
      -- approval exists", and this resolved only the second half, so a step whose run no founder
      -- instructed could never answer it. One resolver now answers both, from the founder's own
      -- frozen boundary register where no command instructed the run, and it reports the reference
      -- only when that reference is valid -- exists, current, and covering this workflow.
      v_auth := public.fn_phase_d_founder_authority(sr.run_id, sr.step_id);
      if coalesce((v_auth->>'valid')::boolean, false) then
        v_val := to_jsonb(v_auth->>'ref');
        v_src := v_auth->>'source';
      end if;`],
]);

// ---- 3. fn_phase_d_gate_evaluate ---------------------------------------------------------------
const gate = splice(await liveBody('fn_phase_d_gate_evaluate'), [
  [`  v_missing text[]; v_n bigint; v_ok boolean; v_txt text;`,
   `  v_missing text[]; v_n bigint; v_ok boolean; v_txt text;\n  v_auth jsonb;   -- K01`],
  [`  elsif p_gate_id = 'GATE-005' then
    select * into s from public.phase_b_workflow_step where step_id = p_evidence->>'step_id';
    v_ok := true;
    reason := format('GATE-005: step declares founder_gate %s and the call names authority %s',
                     left(coalesce(s.founder_gate,'none'),60), p_evidence->>'founder_authority_ref');`,
   `  elsif p_gate_id = 'GATE-005' then
    -- K01. THIS WAS \`v_ok := true\`. The gate checked that a string was present and never that it
    -- meant anything, so any caller could have handed it any text and passed the founder boundary.
    -- It now resolves the authority for itself, from the founder command that instructed the run or
    -- from the founder-approved frozen boundary register, and requires the reference the call
    -- presents to be the one that resolves.
    select * into s from public.phase_b_workflow_step where step_id = p_evidence->>'step_id';
    v_auth := public.fn_phase_d_founder_authority(
                nullif(p_evidence->>'run_id','')::bigint, p_evidence->>'step_id');
    v_ok := coalesce((v_auth->>'valid')::boolean, false)
            and v_auth->>'ref' is not null
            and (p_evidence->>'founder_authority_ref') = (v_auth->>'ref');
    reason := format('GATE-005: step declares founder_gate %s; the call names authority %s; the '
                  || 'estate resolves %s (%s) -- %s',
                     left(coalesce(s.founder_gate,'none'),60),
                     coalesce(p_evidence->>'founder_authority_ref','(none)'),
                     coalesce(v_auth->>'ref','(none)'), coalesce(v_auth->>'kind','-'),
                     coalesce(v_auth->>'why','(no reason stated)'));`],
]);

// ---- 4. fn_phase_d_drive_workflow --------------------------------------------------------------
const drive = splice(await liveBody('fn_phase_d_drive_workflow'), [
  [`    insert into public.founder_command_workflow_link (command_id, workflow_id)
    values (v_founder_cmd, v_wf) on conflict do nothing;`,
   `    -- K01. THE run_id WAS NEVER WRITTEN. fn_phase_d_step_context reads this table by run_id
    -- first, and all 15 rows carried run_id null, so that read had never matched a row in the
    -- estate's history. It is stamped here -- and ONLY where the kernel's own row says this command
    -- started this run. Where the arrival started the run first (H06) the command did not instruct
    -- it, and claiming otherwise would put founder authority under a customer's inquiry.
    insert into public.founder_command_workflow_link (command_id, workflow_id, run_id)
    values (v_founder_cmd, v_wf,
            (select r2.run_id from public.phase_c_workflow_run r2
              where r2.run_id = v_run and r2.command_id = v_founder_cmd))
    on conflict (command_id, workflow_id) do update
      set run_id = excluded.run_id
      where public.founder_command_workflow_link.run_id is null
        and excluded.run_id is not null;`],
]);

writeFileSync(
  'scripts/sql/phase_d_k01_the_gate_asked_for_half_the_evidence_its_text_names.sql',
  HEADER + RESOLVER + '\n' + ctx + ';\n\n' + gate + ';\n\n' + drive + ';\n');
console.log('written');
