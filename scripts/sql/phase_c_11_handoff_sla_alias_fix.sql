-- Phase C — a third defect the Phase C tests found in Phase C's own code.
--
-- fn_phase_c_handoff_open declares `p record` (the packet-validity result) and then, in the SLA
-- lookup, aliased public.phase_b_sla_policy as `p` as well.  Inside a plpgsql body the DECLARED
-- name wins, so `p.target` resolved to the record variable and the function failed at run time
-- with `record "p" has no field "target"` — every handoff open, every time.
--
-- It passed the aborted-transaction rehearsal because the rehearsal creates the function and
-- checks the invariants; it never OPENS a handoff.  That is the gap this file exists to record:
-- a routine that compiles and deploys is not a routine that has run.  It was caught by
-- scripts/checks/phase_c_guards_reject_injected_defects.test.mjs, which does open one.
--
-- The alias is now `sp`, and the search_path is pinned as it already was.
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

create or replace function public.fn_phase_c_handoff_open(p_run_id bigint, p_handoff_id text, p_packet jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  h public.phase_b_handoff%rowtype;
  v_id bigint; v_trace bigint; v_hours numeric; v_due timestamptz;
  chk record;
begin
  select * into h from public.phase_b_handoff where handoff_id = p_handoff_id;
  if not found then
    return jsonb_build_object('ok', false, 'error','unknown_handoff', 'handoff_id', p_handoff_id);
  end if;
  select * into chk from public.fn_phase_c_handoff_packet_valid(p_handoff_id, p_packet);
  if not chk.valid then
    return jsonb_build_object('ok', false, 'error','incomplete_packet', 'missing', chk.missing,
      'return_owner', h.return_owner_role_id,
      'message','The sender keeps this. An incomplete packet does not become the receiver''s problem.');
  end if;

  -- The SLA target is prose ("1 minute", "4 business hours", "30 minutes when inputs are
  -- complete").  Parse the leading quantity AND its unit; taking the digits alone would turn
  -- "1 minute" into one hour and "5 minutes" into five, which is the wrong number twice over.
  select case
           when m[2] ilike 'minute%' then m[1]::numeric / 60.0
           when m[2] ilike 'day%'    then m[1]::numeric * 24.0
           when m[2] ilike 'week%'   then m[1]::numeric * 168.0
           else m[1]::numeric
         end
    into v_hours
  from public.phase_b_sla_policy sp,
       lateral regexp_match(sp.target, '(\d+)\s*(?:business\s+|calendar\s+)?(minute|hour|day|week)') m
  where sp.sla_policy_id = h.sla_policy_id;
  v_hours := coalesce(v_hours, 24);
  v_due := now() + make_interval(mins => greatest(1, round(v_hours * 60))::int);

  insert into public.phase_c_handoff_run
    (handoff_id, run_id, sending_role_id, receiving_role_id, business_object_id, object_version,
     packet_hash, requested_action, acceptance_criteria, return_owner_role_id, sla_policy_id,
     due_at, status, accountable_until_accept_role_id)
  values (p_handoff_id, p_run_id, h.sending_role_id, h.receiving_role_id,
          coalesce(p_packet->>'business_object_id',''),
          coalesce((p_packet->>'object_version')::bigint, 1),
          encode(sha256(convert_to(p_packet::text, 'UTF8')), 'hex'),
          coalesce(p_packet->>'requested_action',''), h.receiving_acceptance_criteria,
          h.return_owner_role_id, h.sla_policy_id, v_due, 'open', h.sending_role_id)
  returning handoff_run_id into v_id;
  if v_id is null then
    raise exception 'fn_phase_c_handoff_open wrote no row for %', p_handoff_id using errcode = '23502';
  end if;

  v_trace := public.fn_phase_c_trace_write('TRACE-HANDOFF', jsonb_build_object(
    'subject_kind','handoff', 'subject_ref', v_id::text, 'run_id', p_run_id,
    'actor_role_id', h.sending_role_id, 'state_before','', 'state_after','open',
    'output_hash', encode(sha256(convert_to(p_packet::text, 'UTF8')), 'hex'), 'status','open'));
  update public.phase_c_handoff_run set trace_id = v_trace where handoff_run_id = v_id;

  return jsonb_build_object('ok', true, 'handoff_run_id', v_id, 'sender', h.sending_role_id,
    'receiver', h.receiving_role_id, 'accountable_until_accept', h.sending_role_id,
    'sla_policy_id', h.sla_policy_id, 'sla_hours', v_hours, 'due_at', v_due, 'trace_id', v_trace);
end $$;
