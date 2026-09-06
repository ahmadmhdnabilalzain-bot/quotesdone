CREATE OR REPLACE FUNCTION public.fn_phase_c_overlay_invoke(p_overlay_id text, p_ctx jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare b public.phase_c_overlay_binding%rowtype; v_trace bigint; v_missing text;
begin
  select * into b from public.phase_c_overlay_binding where overlay_id = p_overlay_id;
  if not found then
    select * into b from public.phase_c_overlay_binding
      where live_role_id = (select role_id from public.fn_phase_c_resolve_actor(p_overlay_id));
  end if;
  if not found then
    return jsonb_build_object('ok', false, 'error','unknown_overlay', 'overlay_id', p_overlay_id);
  end if;
  v_missing := coalesce((select string_agg(k, ', ') from unnest(array['inquiry_id']) k
                         where not (coalesce(p_ctx,'{}'::jsonb) ? k)), '');
  v_trace := public.fn_phase_c_trace_write('TRACE-CATEGORY-ADVICE', jsonb_build_object(
    'subject_kind','overlay', 'subject_ref', b.overlay_id,
    'actor_role_id', b.live_role_id, 'status', case when v_missing = '' then 'sealed' else 'open' end,
    'evidence_refs', coalesce(p_ctx->'evidence_refs','[]'::jsonb)));
  return jsonb_build_object(
    'ok', v_missing = '', 'overlay_id', b.overlay_id, 'live_role_id', b.live_role_id,
    'inquiry_id', p_ctx->>'inquiry_id',
    'retrieved_fields', coalesce(p_ctx->'retrieved_fields','[]'::jsonb),
    'never_infer_checks', jsonb_build_array('quantity','specification','delivery_date','budget'),
    'missing_fields', v_missing,
    'return_owner', b.result_returns_to_role_id,
    'may_dispatch', false,
    'status', case when v_missing = '' then 'success' else 'empty' end,
    'trace_id', v_trace);
end $function$
