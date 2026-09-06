// N06 PROVED IN THREE DIRECTIONS on ONE gate, so the three outcomes are distinguishable and the
// refusal is about the fault rather than about the gate refusing everything.
import { probe } from './probe.mjs';

const arm = (name, setup, evidence) => `
  ${setup}
  select g.state, g.passed, g.refusal_code, g.evidence_absent, left(g.reason,90)
    into v_state, v_passed, v_code, v_absent, v_reason
    from public.fn_phase_d_gate_evaluate('GATE-001', ${evidence}) g;
  v_out := v_out || '${name}: state=' || coalesce(v_state,'-')
        || ' passed=' || coalesce(v_passed::text,'-')
        || ' code=' || coalesce(v_code,'-')
        || ' evidence_absent=' || coalesce(v_absent::text,'-')
        || ' | ' || coalesce(v_reason,'-') || chr(10);`;

console.log(await probe(`do $p$
declare v_state text; v_passed boolean; v_code text; v_absent boolean; v_reason text; v_out text := chr(10);
begin
${arm('read_and_passed', "perform set_config('app.phase_d_gate_read_fault','', true);", `jsonb_build_object('step_id','W01-S01')`)}
${arm('evidence_absent', "perform set_config('app.phase_d_gate_read_fault','', true);", `'{}'::jsonb`)}
${arm('READ_FAILED   ', "perform set_config('app.phase_d_gate_read_fault','GATE-001', true);", `jsonb_build_object('step_id','W01-S01')`)}
${arm('other_gate_ok ', "perform set_config('app.phase_d_gate_read_fault','GATE-001', true);", `jsonb_build_object('actor_role_id','chief_of_staff')`).replace(/GATE-001', jsonb_build_object\('actor_role_id/, "GATE-002', jsonb_build_object('actor_role_id")}
  raise exception 'N06<<%>>', v_out;
end $p$;`, 'N06'));
