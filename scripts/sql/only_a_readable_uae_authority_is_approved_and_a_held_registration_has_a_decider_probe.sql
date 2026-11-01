-- Assigned: sales_engineer. A pure probe of the gate and the decider on one ZZ DEMO supplier; it always raises, so nothing survives.
-- Known-bad controls: a foreign and an unknown authority must not approve, and an approved, answered or unknown hold must not close.
do $probe$
declare
  v_id bigint; v jsonb; d jsonb; s text; v_bad text := ''; v_real int;
begin
  select count(*) into v_real from public.leads l where l.approval_status = 'pending' and not coalesce(l.is_demo, false);
  select l.id into v_id from public.leads l
   where l.approval_status = 'approved' and l.is_demo and l.company_name ilike 'ZZ DEMO%' and coalesce(l.email, '') ilike '%@example.invalid'
     and cardinality(public.fn_supplier_mandatory_six(l)) = 0 order by l.id limit 1;
  if v_id is null then raise exception 'CHK<<PROBE FAILED: no ZZ DEMO approved supplier>>'; end if;
  update public.leads set licence_legal_name = company_name, license_expiry = current_date + 400, trade_license_no = coalesce(nullif(trade_license_no, ''), 'ZZPROBE1') where id = v_id;

  -- the gate
  update public.leads set license_authority = 'Department of Economy and Tourism' where id = v_id;
  v := public.fn_sales_engineer_verifies_supplier(v_id, 'save_profile');
  if v ->> 'approval_status' <> 'approved' then v_bad := v_bad || ' uae=' || (v ->> 'reason'); end if;
  update public.leads set license_authority = 'Northern Registry Office' where id = v_id;
  v := public.fn_sales_engineer_verifies_supplier(v_id, 'save_profile');
  if v ->> 'reason' is distinct from 'licence_authority_unconfirmed' then v_bad := v_bad || ' unknown=' || coalesce(v ->> 'reason', v ->> 'approval_status'); end if;
  update public.leads set license_authority = null where id = v_id;
  v := public.fn_sales_engineer_verifies_supplier(v_id, 'save_profile');
  if v ->> 'reason' is distinct from 'licence_authority_unread' then v_bad := v_bad || ' unread=' || coalesce(v ->> 'reason', v ->> 'approval_status'); end if;
  update public.leads set license_authority = 'Ministry of Commerce, Kingdom of Saudi Arabia' where id = v_id;
  v := public.fn_sales_engineer_verifies_supplier(v_id, 'save_profile');
  if v ->> 'reason' is distinct from 'licence_authority_not_uae' then v_bad := v_bad || ' foreign=' || coalesce(v ->> 'reason', v ->> 'approval_status'); end if;

  -- control: ever approved is never closed
  update public.leads set approved_at = now() where id = v_id;
  perform public.fn_sales_engineer_decides_held_registrations(now());
  perform public.fn_sales_engineer_decides_held_registrations(now() + interval '15 days');
  select approval_status into s from public.leads where id = v_id;
  if s <> 'pending' then v_bad := v_bad || ' approved_was_closed=' || s; end if;
  if not exists (select 1 from public.agent_actions a where a.kind = 'held_registration_for_ceo' and a.target_id = v_id::text) then v_bad := v_bad || ' approved_no_ceo_task'; end if;

  -- control: a reply stops the close
  delete from public.agent_actions where kind in ('held_registration_asked', 'held_registration_for_ceo') and target_id = v_id::text;
  update public.leads set approved_at = null where id = v_id;
  perform public.fn_sales_engineer_decides_held_registrations(now());
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, created_at) values (v_id, 'qd-probe@example.invalid', 'supplier@quotesdone.com', 'probe', 'probe', now() + interval '1 second');
  perform public.fn_sales_engineer_decides_held_registrations(now() + interval '15 days');
  select approval_status into s from public.leads where id = v_id;
  if s <> 'pending' then v_bad := v_bad || ' answered_was_closed=' || s; end if;

  -- control: an unknown authority is never closed
  delete from public.inbound_messages where lead_id = v_id and from_email = 'qd-probe@example.invalid';
  delete from public.agent_actions where kind in ('held_registration_asked', 'held_registration_for_ceo') and target_id = v_id::text;
  update public.leads set license_authority = 'Northern Registry Office' where id = v_id;
  perform public.fn_sales_engineer_verifies_supplier(v_id, 'save_profile');
  perform public.fn_sales_engineer_decides_held_registrations(now());
  perform public.fn_sales_engineer_decides_held_registrations(now() + interval '15 days');
  select approval_status into s from public.leads where id = v_id;
  if s <> 'pending' then v_bad := v_bad || ' unknown_was_closed=' || s; end if;

  -- the clock itself: foreign, never approved, silent: asked at 0, 3, 7; closed by the ceo at 14; a save reopens it
  delete from public.agent_actions where kind in ('held_registration_asked', 'held_registration_for_ceo') and target_id = v_id::text;
  update public.leads set license_authority = 'Ministry of Commerce, Kingdom of Saudi Arabia' where id = v_id;
  perform public.fn_sales_engineer_verifies_supplier(v_id, 'save_profile');
  perform public.fn_sales_engineer_decides_held_registrations(now());
  perform public.fn_sales_engineer_decides_held_registrations(now());
  perform public.fn_sales_engineer_decides_held_registrations(now() + interval '3 days');
  perform public.fn_sales_engineer_decides_held_registrations(now() + interval '7 days');
  if (select count(*) from public.agent_actions a where a.kind = 'held_registration_asked' and a.target_id = v_id::text) <> 3 then v_bad := v_bad || ' asks_not_3'; end if;
  perform public.fn_sales_engineer_decides_held_registrations(now() + interval '14 days');
  select approval_status into s from public.leads where id = v_id;
  if s <> 'rejected' then v_bad := v_bad || ' silent_not_closed=' || s; end if;
  update public.leads set license_authority = 'Dubai Department of Economy and Tourism' where id = v_id;
  v := public.fn_sales_engineer_verifies_supplier(v_id, 'save_profile');
  if v ->> 'approval_status' <> 'approved' then v_bad := v_bad || ' not_reopened=' || (v ->> 'approval_status'); end if;

  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK lead=% real_pending_touched=%>>', v_id, v_real;
end $probe$;
