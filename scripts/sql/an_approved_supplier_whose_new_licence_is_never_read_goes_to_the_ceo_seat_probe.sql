-- Assigned: sales_engineer
-- PURE PROBE (no DDL) for an_approved_supplier_whose_new_licence_is_never_read_goes_to_the_ceo_seat.sql. It always ends in
-- raise exception 'CHK<<...>>', so every row it writes rolls back. Run it with the file in one rolled-back transaction
-- (node scripts/ci/rehearse_sql.mjs <file> <this>) or after the file is applied.
-- Its subject is ONE approved ZZ DEMO supplier at @example.invalid with the six complete (the convention of the licence probes). The
-- hand-over is called with p_lead_id = that supplier, so it cannot touch a real row; it writes only a ceo_task and an agent_actions
-- row, and the probe counts notifications before and after to prove nothing was queued to anyone.
--   kept     : a new licence our reader failed on, the accepted reading kept (as process_docs now writes) -> still approved, verified
--   day 1    : one day of failure                                     -> nothing handed over
--   day 4    : four days of failure                                   -> put to the ceo seat once (a ceo_task and one clock row)
--   again    : the next day's run on the same file                   -> nothing more
--   standing : after the hand-over                                    -> still approved (the person decides, not the routine)
--   decider  : fn_sales_engineer_decides_held_registrations answers approved_unread_to_ceo (only when no REAL row qualifies)
do $$
declare v_id bigint; v_path text; o public.leads; s public.leads; v_d1 int; v_d4 int; v_again int; v_tasks int; v_clock int;
        v_notes_before bigint; v_notes_after bigint; v_real int; v_out jsonb; fail text := '';
begin
  select id, license_doc_path into v_id, v_path from public.leads
   where company_name like 'ZZ DEMO%' and email like '%@example.invalid' and claimed_by like '%@example.invalid'
     and approval_status = 'approved' and license_doc_path is not null and cardinality(public.fn_supplier_mandatory_six(leads)) = 0
   order by id limit 1;
  if v_id is null then raise exception 'CHK<<%>>', jsonb_build_object('verdict', 'PROBE FAILED: no approved ZZ DEMO supplier with a licence to probe'); end if;
  select count(*) into v_notes_before from public.notifications;
  -- the accepted reading: what an approved supplier's row holds after his licence was read (filled here only where the demo row lacks it)
  update public.leads set licence_legal_name = coalesce(nullif(btrim(licence_legal_name), ''), company_name),
                          trade_license_no = coalesce(nullif(btrim(trade_license_no), ''), 'ZZ-PROBE-0001'),
                          license_expiry = coalesce(license_expiry, current_date + 300),
                          license_authority = coalesce(nullif(btrim(license_authority), ''), 'Dubai Department of Economy and Tourism'),
                          licence_read_state = 'read' where id = v_id;   -- the row is already approved (selected so)

  -- kept: the new file is being read; the accepted reading stays (the path is in the SET list, as process_docs writes it, so z20 runs)
  update public.leads set license_doc_path = v_path, licence_read_state = 'ours_failed', licence_read_at = now() where id = v_id;
  select * into o from public.leads where id = v_id;
  if not (o.approval_status = 'approved' and coalesce(o.verified, false)) then fail := fail || format('kept: %s/%s; ', o.approval_status, o.licence_gate_reason); end if;

  update public.leads set licence_read_failed_since = now() - interval '1 day' where id = v_id;
  v_d1 := public.fn_sales_engineer_hands_unread_approved_licences_to_ceo(now(), v_id);
  if v_d1 <> 0 then fail := fail || format('day 1: handed over %s; ', v_d1); end if;
  update public.leads set licence_read_failed_since = now() - interval '4 days' where id = v_id;
  v_d4 := public.fn_sales_engineer_hands_unread_approved_licences_to_ceo(now(), v_id);
  v_again := public.fn_sales_engineer_hands_unread_approved_licences_to_ceo(now() + interval '1 day', v_id);
  select count(*) into v_clock from public.agent_actions
   where kind = 'held_registration_for_ceo' and target_id = v_id::text and detail ->> 'clock' = 'approved_licence_unread:' || v_path;
  select count(*) into v_tasks from public.ceo_task where title like 'Read the new trade licence of an approved supplier: %' and created_at >= now();
  if v_d4 <> 1 or v_clock <> 1 or v_tasks <> 1 then fail := fail || format('day 4: handed %s, clock rows %s, ceo tasks %s (want 1/1/1); ', v_d4, v_clock, v_tasks); end if;
  if v_again <> 0 then fail := fail || format('again: handed over %s more; ', v_again); end if;
  select * into s from public.leads where id = v_id;
  if s.approval_status <> 'approved' then fail := fail || format('standing: %s; ', s.approval_status); end if;

  -- the decider answers the new key; run only when no real row would qualify for any of its loops (it then writes to no real row)
  select count(*) into v_real from public.leads
   where coalesce(company_name, '') not like 'ZZ DEMO%'
     and ((approval_status = 'pending' and licence_gate_reason like 'licence%')
       or (approval_status = 'approved' and licence_read_state = 'ours_failed'));
  if v_real = 0 then
    v_out := public.fn_sales_engineer_decides_held_registrations(now() + interval '2 days');
    if not (v_out ? 'approved_unread_to_ceo') then fail := fail || 'decider: no approved_unread_to_ceo in its answer; '; end if;
  end if;

  select count(*) into v_notes_after from public.notifications;
  if v_notes_after <> v_notes_before then fail := fail || format('notifications: %s queued; ', v_notes_after - v_notes_before); end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'supplier', v_id, 'kept_approved', o.approval_status = 'approved', 'day1', v_d1, 'day4', v_d4, 'again', v_again,
    'decider_run', v_real = 0, 'decider', v_out, 'notifications_queued', v_notes_after - v_notes_before);
end $$;
