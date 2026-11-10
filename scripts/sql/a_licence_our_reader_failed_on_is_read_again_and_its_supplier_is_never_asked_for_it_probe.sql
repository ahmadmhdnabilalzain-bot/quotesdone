-- Assigned: customer_support
-- PURE PROBE (no DDL) for a_licence_our_reader_failed_on_is_read_again_and_its_supplier_is_never_asked_for_it.sql. It always
-- ends in raise exception 'CHK<<...>>', so every row it writes rolls back. Run it with the file in one rolled-back transaction
-- (node scripts/ci/rehearse_sql.mjs <file> <this>) or after the file is applied.
-- Its subject is ONE approved ZZ DEMO supplier at @example.invalid with the six complete (the convention of the licence probes);
-- the decider is called only when no REAL lead is held for a licence reason, so it cannot write to a real supplier.
--   ours     : a new licence our reader failed on, number blank        -> pending / licence_being_read, failure clock started
--   decider  : asked today                                              -> nothing asked, nothing closed
--   day 4    : asked four days on                                       -> put to the ceo seat once, never asked or closed
--   control  : the same blank number, but the file was read            -> pending / licence_number_unread (asked, as today)
--   sweep    : due (an hour old, no tries)                              -> handed out once in a fixture run, never in a real one
--   clock    : a new licence path                                       -> its tries start again at 0
do $$
declare v_id bigint; v_path text; o public.leads; c public.leads; f public.leads; n public.leads;
        v_real_held int; v_asked int; v_closed int; v_ceo int; v_ceo4 int; v_asked4 int;
        v_real_claim int; v_fx_claim int; v_fx_again int; fail text := '';
begin
  select id, license_doc_path into v_id, v_path from public.leads
   where company_name like 'ZZ DEMO%' and email like '%@example.invalid' and claimed_by like '%@example.invalid'
     and approval_status = 'approved' and license_doc_path is not null and cardinality(public.fn_supplier_mandatory_six(leads)) = 0
   order by id limit 1;
  if v_id is null then raise exception 'CHK<<%>>', jsonb_build_object('verdict', 'PROBE FAILED: no approved ZZ DEMO supplier with a licence to probe'); end if;
  select count(*) into v_real_held from public.leads
   where approval_status = 'pending' and licence_gate_reason like 'licence%' and coalesce(company_name, '') not like 'ZZ DEMO%';

  -- ours: what process_docs now writes when the model failed and the number stayed blank
  -- (held first, as a registration is: z20 re-verifies an APPROVED supplier only when the licence path or name changes, and
  -- the six read the licence path against storage, so the probe keeps the stored one)
  update public.leads set approval_status = 'pending', verified = false, licence_gate_reason = null where id = v_id;
  update public.leads set license_doc_path = v_path, trade_license_no = null, licence_legal_name = company_name,
                          license_expiry = coalesce(license_expiry, current_date + 300), license_authority = coalesce(license_authority, 'Dubai Economy and Tourism'),
                          licence_read_state = 'ours_failed',
                          licence_read_at = now() where id = v_id;
  select * into o from public.leads where id = v_id;
  if not (o.approval_status = 'pending' and o.licence_gate_reason = 'licence_being_read' and not coalesce(o.verified, false)) then
    fail := fail || format('ours: %s/%s; ', o.approval_status, o.licence_gate_reason); end if;
  if o.licence_read_failed_since is null then fail := fail || 'ours: failure clock not started; '; end if;

  if v_real_held = 0 then
    perform public.fn_sales_engineer_decides_held_registrations(now());
    select count(*) filter (where kind = 'held_registration_asked'), count(*) filter (where kind = 'held_registration_decision'),
           count(*) filter (where kind = 'held_registration_for_ceo')
      into v_asked, v_closed, v_ceo from public.agent_actions where target_table = 'leads' and target_id = v_id::text and created_at >= now();
    if v_asked + v_closed + v_ceo > 0 then fail := fail || format('decider today: asked %s closed %s ceo %s; ', v_asked, v_closed, v_ceo); end if;
    perform public.fn_sales_engineer_decides_held_registrations(now() + interval '4 days');
    perform public.fn_sales_engineer_decides_held_registrations(now() + interval '5 days');
    select count(*) filter (where kind = 'held_registration_for_ceo'), count(*) filter (where kind in ('held_registration_asked', 'held_registration_decision'))
      into v_ceo4, v_asked4 from public.agent_actions where target_table = 'leads' and target_id = v_id::text and created_at >= now();
    if v_ceo4 <> 1 then fail := fail || format('day 4: put to the ceo %s times, not once; ', v_ceo4); end if;
    if v_asked4 > 0 then fail := fail || 'day 4: the supplier was asked or closed; '; end if;
    select * into f from public.leads where id = v_id;
    if f.approval_status = 'rejected' then fail := fail || 'day 4: registration closed; '; end if;
  else
    fail := fail || format('%s real leads are held for a licence reason, so the decider was not run; ', v_real_held);
  end if;

  -- control: the same blank number on a licence our reader DID read is the document's, and is asked for as today
  -- (the path is in the SET list, as both readers write it, so z20 re-verifies the now-pending supplier)
  update public.leads set license_doc_path = license_doc_path, licence_read_state = 'read', licence_read_at = now() where id = v_id;
  select * into c from public.leads where id = v_id;
  if not (c.licence_gate_reason = 'licence_number_unread' and c.licence_read_failed_since is null) then
    fail := fail || format('control: %s, clock %s; ', c.licence_gate_reason, c.licence_read_failed_since); end if;

  -- sweep: due an hour on with no tries; a real run never hands out a demo row, a fixture run hands it out once
  update public.leads set licence_read_state = 'ours_failed', licence_read_at = now() - interval '1 hour', licence_read_tries = 0 where id = v_id;
  perform set_config('qd.duty_fixtures', '', true);
  select count(*) into v_real_claim from public.fn_supplier_licence_reread_claim(20) x where x.lead_id = v_id;
  perform set_config('qd.duty_fixtures', 'on', true);
  select count(*) into v_fx_claim from public.fn_supplier_licence_reread_claim(20) x where x.lead_id = v_id;
  select count(*) into v_fx_again from public.fn_supplier_licence_reread_claim(20) x where x.lead_id = v_id;
  perform set_config('qd.duty_fixtures', '', true);
  if v_real_claim <> 0 then fail := fail || 'sweep: a real run handed out a demo licence; '; end if;
  if v_fx_claim <> 1 then fail := fail || format('sweep: handed out %s times, not once; ', v_fx_claim); end if;
  if v_fx_again <> 0 then fail := fail || 'sweep: handed out again inside its back-off; '; end if;
  select * into n from public.leads where id = v_id;
  if n.licence_read_tries <> 1 then fail := fail || format('sweep: tries %s, not 1; ', n.licence_read_tries); end if;

  -- clock: a new licence starts its own count
  update public.leads set license_doc_path = v_path || '.probe-new' where id = v_id;
  select * into n from public.leads where id = v_id;
  if n.licence_read_tries <> 0 then fail := fail || 'clock: a new licence kept the old tries; '; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'supplier', v_id, 'ours', o.licence_gate_reason, 'control', c.licence_gate_reason, 'real_held', v_real_held,
    'ceo_after_4_and_5_days', v_ceo4, 'fixture_claims', v_fx_claim);
end $$;
