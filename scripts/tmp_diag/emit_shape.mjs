import { probe } from './probe.mjs';
console.log(await probe(`do $p$
declare v jsonb; v_id bigint; r record; v_out text;
begin
  v := public.fn_kernel_outbox_emit(jsonb_build_object(
    'event_id','EV-W01-STARTED','workflow_id','W01',
    'producer','zz-phase-d-canary',
    'accountable_role_id','chief_of_staff',
    'correlation_id', gen_random_uuid(), 'causation_id', gen_random_uuid(), 'source_id','zz-phase-d-canary',
    'dedupe_value','zz-phase-d-canary-shape-probe',
    'payload', jsonb_build_object('fact','PHASE_D_FIXTURE_DO_NOT_PUBLISH shape probe')));
  select o.outbox_id, o.status, o.next_attempt_at, o.max_attempts, o.dedupe_value
    into r from public.phase_c_event_outbox o order by o.outbox_id desc limit 1;
  v_out := 'emit=' || left(v::text, 200) || ' || row: id=' || coalesce(r.outbox_id::text,'-')
        || ' status=' || coalesce(r.status,'-')
        || ' next_attempt_at=' || coalesce(r.next_attempt_at::text,'(null)')
        || ' max_attempts=' || coalesce(r.max_attempts::text,'-');
  raise exception 'SH<<%>>', v_out;
end $p$;`, 'SH'));
