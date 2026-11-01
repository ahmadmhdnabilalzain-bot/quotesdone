-- Assigned: sales_engineer. A pure probe on ZZ DEMO requests; it always raises, so nothing survives. It needs nothing from the authority file.
-- Known-bad controls: a request held for its specs, and one younger than 14 days, must stay open; the message must promise no quote.
do $probe$
declare v_i uuid; v_c uuid; v_y uuid; r jsonb; s text; v_bad text := ''; m jsonb; v_real int;
begin
  select count(*) into v_real from public.inquiries i join public.customers c on c.id = i.customer_id
   where c.email not ilike '%@example.invalid' and i.created_at < now() - interval '14 days'
     and coalesce(i.status, '') not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
     and not exists (select 1 from public.inquiry_matches x where x.inquiry_id = i.id);
  select i.id into v_i from public.inquiries i join public.customers c on c.id = i.customer_id
   where c.email ilike '%@example.invalid' and i.parent_inquiry_id is null and not exists (select 1 from public.quotes q where q.inquiry_id = i.id)
     and not exists (select 1 from public.inquiries k where k.parent_inquiry_id = i.id) order by i.created_at limit 1;
  select i.id into v_c from public.inquiries i join public.customers c on c.id = i.customer_id
   where c.email ilike '%@example.invalid' and i.parent_inquiry_id is null and i.id is distinct from v_i and not exists (select 1 from public.quotes q where q.inquiry_id = i.id)
     and not exists (select 1 from public.inquiries k where k.parent_inquiry_id = i.id) order by i.created_at limit 1;
  select i.id into v_y from public.inquiries i join public.customers c on c.id = i.customer_id
   where c.email ilike '%@example.invalid' and i.parent_inquiry_id is null and i.id not in (v_i, v_c) and not exists (select 1 from public.quotes q where q.inquiry_id = i.id)
     and not exists (select 1 from public.inquiries k where k.parent_inquiry_id = i.id) order by i.created_at limit 1;
  if v_i is null or v_c is null or v_y is null then raise exception 'CHK<<PROBE FAILED: fewer than three ZZ DEMO requests with no quote>>'; end if;
  delete from public.inquiry_matches where inquiry_id in (v_i, v_c, v_y);
  update public.inquiries set status = 'open', rfq_ready = true, created_at = '2020-01-01' where id = v_i;
  update public.inquiries set status = 'open', rfq_ready = false, created_at = '2020-01-02' where id = v_c;
  update public.inquiries set status = 'open', rfq_ready = true, created_at = now() where id = v_y;

  if public.fn_inquiry_awaits_specs(v_i) then v_bad := v_bad || ' ready_reads_held'; end if;
  if not public.fn_inquiry_awaits_specs(v_c) then v_bad := v_bad || ' held_reads_ready'; end if;
  r := public.fn_sales_engineer_closes_unreached_requests(now());
  select status into s from public.inquiries where id = v_i;
  if s <> 'expired' then v_bad := v_bad || ' unreached_not_closed=' || s; end if;
  select status into s from public.inquiries where id = v_c;
  if s = 'expired' then v_bad := v_bad || ' spec_held_was_closed'; end if;
  select status into s from public.inquiries where id = v_y;
  if s = 'expired' then v_bad := v_bad || ' young_was_closed'; end if;
  if not exists (select 1 from public.notifications n where n.inquiry_id = v_i and n.type = 'request_closed_no_supplier') then v_bad := v_bad || ' customer_not_told'; end if;
  if exists (select 1 from public.notifications n where n.inquiry_id = v_i and n.type = 'request_closed_no_supplier' and n.status <> 'suppressed') then v_bad := v_bad || ' notice_not_suppressed'; end if;

  update public.inquiries set status = 'open' where id = v_i;
  m := public.fn_customer_concierge_message(v_i, 'finding_suppliers');
  if coalesce(m ->> 'body', '') !~ '(cannot promise a quote|نعدكم)' then v_bad := v_bad || ' message_promises:' || left(coalesce(m::text, ''), 80); end if;
  m := public.fn_customer_concierge_message(v_c, 'finding_suppliers');
  if coalesce(m ->> 'body', '') ~ '(registering suppliers|نسجّل الموردين)' then v_bad := v_bad || ' spec_held_told_no_supplier'; end if;
  m := public.fn_sales_engineer_stalled_inquiry_notice('en', jsonb_build_object('reason', 'no_reachable_supplier', 'category', 'aluminium', 'pool', 0));
  if m ->> 'body' !~ 'cannot promise a quotation' then v_bad := v_bad || ' notice_promises'; end if;

  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK closed=% real_over_14d=%>>', r, v_real;
end $probe$;
