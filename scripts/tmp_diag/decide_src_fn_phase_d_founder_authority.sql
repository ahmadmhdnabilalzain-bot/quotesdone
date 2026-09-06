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
$function$
