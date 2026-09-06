// Does the frozen Phase B registry actually REFUSE the two STATE injections, and does it accept a
// change that carries a real change reason? Both directions, in one aborted transaction.
import { probe } from './probe.mjs';

const arm = (name, body) => `
  begin
    ${body}
    v_out := v_out || '${name}=ACCEPTED; ';
  exception when others then
    v_out := v_out || '${name}=' || left(regexp_replace(SQLERRM,'[|<>;]',' ','g'), 150) || '; ';
  end;`;

console.log(await probe(`do $p$
declare v_out text := ''; v_step text; v_owner text;
begin
  select step_id, accountable_role_id into v_step, v_owner
    from public.phase_b_workflow_step where workflow_id='W04' order by step_no limit 1;
  v_out := 'subject=' || v_step || '/' || v_owner || ' :: ';
${arm('state004_blank_owner', "update public.phase_b_workflow_step set accountable_role_id = '' where step_id = v_step;")}
${arm('state003_flip_closure', "update public.phase_b_workflow_step set is_closure_step = not is_closure_step where step_id = v_step;")}
${arm('state004_with_reason', "perform set_config('app.phase_b_change_reason','PBCR-probe: not a real change request', true); update public.phase_b_workflow_step set accountable_role_id = '' where step_id = v_step;")}
  raise exception 'SF<<%>>', v_out;
end $p$;`, 'SF'));
