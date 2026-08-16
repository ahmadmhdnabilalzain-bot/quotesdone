-- ---------------------------------------------------------------------------------------------
-- fn_os_command: the escalations page gets the label too.
--
-- Third and last of the three surfaces that were handed a bare machine key. Same resolution
-- (public.fn_ui_label), same reason: one label, resolved once, so the founder reads the same words
-- for the same thing wherever it appears. Only the attention jsonb_build_object changed.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_os_command()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_health jsonb; v_ops jsonb; v_counts jsonb; v_attention jsonb; v_pipeline jsonb;
begin
  v_health := to_jsonb(fn_health_index());
  v_ops    := to_jsonb(fn_ops_dashboard());

  select jsonb_build_object(
    'suppliers_total', (select count(*) from leads),
    'rfqs_total',      (select count(*) from inquiries),
    'rfqs_active',     (select count(*) from inquiries where status = 'quoted'),
    'rfqs_revealed',   (select count(*) from inquiries where status = 'revealed'),
    'rfqs_cancelled',  (select count(*) from inquiries where status = 'cancelled'),
    'quotes_total',    (select count(*) from quotes),
    'decisions_7d',    (select count(*) from decision_log where created_at > now() - interval '7 days'),
    'decisions_24h',   (select count(*) from decision_log where created_at > now() - interval '24 hours')
  ) into v_counts;

  select jsonb_build_object(
    'sent',      (select count(*) from inquiries where status = 'sent' and parent_inquiry_id is null),
    'matched',   (select count(distinct im.inquiry_id) from inquiry_matches im join inquiries i on i.id = im.inquiry_id where i.status = 'sent'),
    'quoted',    (select count(*) from inquiries where status = 'quoted'),
    'revealed',  (select count(*) from inquiries where status = 'revealed'),
    'completed', (select count(*) from inquiries where status in ('completed','won'))
  ) into v_pipeline;

  select coalesce(jsonb_agg(x order by created_at desc), '[]'::jsonb) into v_attention
  from (
    select id, actor, kind, decision, confidence, route_to, created_at,
           -- kind_label: the same human label the bell and the founder queue resolve, so the
           -- escalations page cannot print "Action Gate" while another screen says something else.
           jsonb_build_object('id', id, 'actor', actor, 'kind', kind,
             'kind_label', public.fn_ui_label('action_kind', kind), 'decision', decision,
             'policies', public.fn_action_policies(kind, confidence),
             'confidence', confidence, 'route_to', route_to, 'created_at', created_at,
             'os', public.fn_owning_os(actor),
             'reasons', reasons,
             'alternatives', alternatives,
             'outcome', case when exists (select 1 from public.agent_actions a where a.decision_log_id = decision_log.id)
                  then (select coalesce(a.status,'recorded') || ' — ' || coalesce(a.title,'action taken')
                          from public.agent_actions a where a.decision_log_id = decision_log.id
                         order by a.created_at desc limit 1)
                  else 'held for ' || coalesce(route_to,'review') || ', no follow-up action recorded since ' || created_at::date end
           ) as x
    from decision_log where route_to is not null and route_to <> 'auto'
    order by created_at desc limit 8
  ) t;

  return jsonb_build_object(
    'ok', true, 'generated_at', now(),
    'health', v_health, 'ops', v_ops, 'counts', v_counts,
    'pipeline', v_pipeline, 'attention', v_attention
  );
end;
$function$
;
