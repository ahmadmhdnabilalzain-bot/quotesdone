-- `fn_sla_watch` runs HOURLY, detects an RFQ that has had no supplier quote past the SLA window,
-- writes a founder alert and an email — and tells the bus nothing. `ops_director` subscribes to
-- `sla.breached` ("OS interface: Operations OS consumes sla.breached") and has never received one.
--
-- One emit inside the loop it already runs. It cannot fire spuriously: the same row already gates on
-- status='sent', no live quote, past the configured hour count, and no duplicate founder alert in 48
-- hours. With `inquiries` at zero rows it stays silent until the first real RFQ goes unanswered —
-- which is the moment Operations most needs to hear it.
--
-- NOT done here: `department.conflict`, whose subscriber (`brief`, "Cross-department conflict
-- resolution") is also dead. `fn_decision_conflict_scan` finds the same ACTOR reaching two verdicts
-- on one kind, which is a decision inconsistency, not two departments disagreeing. Emitting
-- department.conflict for it would be mislabelling to make a subscription look alive. That name
-- needs a real detector.
create or replace function public.fn_sla_watch()
returns json language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare
  v_hours int;
  v_admin text;
  v_flagged int := 0;
  r record;
begin
  v_hours := coalesce((select nullif(value,'')::int from app_secrets where key='sla_quote_hours'), 24);
  v_admin := coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'), 'management@quotesdone.com');
  for r in
    select i.id, i.category, i.emirate, i.created_at
    from inquiries i
    where i.status = 'sent'
      and i.created_at < (now() - make_interval(hours => v_hours))
      and coalesce(i.scope_type,'') <> 'combined'
      and not exists (
        select 1 from quotes q where q.inquiry_id = i.id
          and coalesce(q.status,'') not in ('draft','rejected','void','cancelled'))
      and not exists (
        select 1 from founder_alerts fa where fa.event='rfq_sla_breach'
          and fa.detail like ('%inquiry '||i.id||':%')
          and fa.created_at > (now() - interval '48 hours'))
    order by i.created_at asc
    limit 50
  loop
    insert into founder_alerts(level, event, detail, channel)
      values('warn','rfq_sla_breach',
        'inquiry '||r.id||': no supplier quote after '||v_hours||'h ('||coalesce(r.category,'?')||' / '||coalesce(r.emirate,'?')||'). Widen the pool or recruit this category.',
        'system');
    insert into notifications(type, to_email, to_role, channel, subject, body, status)
      values('rfq_sla_breach', v_admin, 'admin', 'email',
        'RFQ past SLA — no quotes yet',
        'Inquiry #'||r.id||' ('||coalesce(r.category,'?')||' in '||coalesce(r.emirate,'?')||') has had NO supplier quote for over '||v_hours||' hours. Consider widening the emirate/trade or recruiting suppliers in this category. Open it in the OS to re-dispatch.',
        'queued');
    -- Added 10 Aug 2026. The founder was told and Operations was not, because this routine has
    -- never put anything on the bus.
    perform fn_emit('sla.breached', 'inquiry', r.id::text, 'sla_watch',
      jsonb_build_object('sla_hours', v_hours, 'category', r.category, 'emirate', r.emirate,
                         'raised_at', r.created_at, 'quotes', 0));
    v_flagged := v_flagged + 1;
  end loop;
  return json_build_object('sla_hours', v_hours, 'flagged', v_flagged, 'ran_at', now());
end $function$;
