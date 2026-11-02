-- PROBE of fn_supplier_invite_candidates_is_one_routine.sql. Always raises CHK<<...>>, so nothing it does stays.
do $probe$
declare p text[] := '{}'; v_old boolean := false; v_list jsonb; v_id bigint;
begin
  if (select count(*) from pg_proc f join pg_namespace n on n.oid = f.pronamespace
       where n.nspname = 'public' and f.proname = 'fn_supplier_invite_candidates') <> 1 then p := p || 'more than one overload is live'::text; end if;
  -- known-bad control: the old call must fail, not reach a body
  begin
    perform * from public.fn_supplier_invite_candidates(1);
    v_old := true;
  exception when undefined_function then null; end;
  if v_old then p := p || 'the one-argument call still answers'::text; end if;
  -- its one caller still runs
  v_list := public.fn_supplier_campaign_next_list(null);
  if v_list is null then p := p || 'fn_supplier_campaign_next_list answered nothing'::text; end if;
  -- the gate is still in the only body: an unchecked lead on a live domain is not a candidate
  insert into public.email_domain_mx(domain, has_mx, kind, hosts) values ('qd-probe-one.ae', true, 'mx', array['mx.qd-probe-one.ae']);
  insert into public.leads(company_name, email) values ('Probe One Routine', 'sales@qd-probe-one.ae') returning id into v_id;
  if exists (select 1 from public.fn_supplier_invite_candidates(100000, null::text[]) c where c.lead_id = v_id) then p := p || 'an unchecked lead is a candidate'::text; end if;
  -- the constraint holds under its new name
  begin
    insert into public.lead_email_check(lead_id, email_md5, verdict, reason, mx_kind) values (v_id, md5('sales@qd-probe-one.ae'), 'verified', 'probe', 'a_implicit');
    p := p || 'verified without an MX was accepted'::text;
  exception when check_violation then
    if sqlerrm !~ 'lead_email_check_verified_needs_mx' then p := p || ('wrong constraint: ' || sqlerrm); end if;
  end;
  if exists (select 1 from pg_constraint where conname = 'lead_email_check_check') then p := p || 'the auto-named check is still there'::text; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when cardinality(p) = 0 then 'PROBE OK' else 'PROBE FAILED' end, 'problems', to_jsonb(p));
end $probe$;
