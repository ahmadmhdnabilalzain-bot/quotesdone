-- PROBE (pure, no DDL, aborted transaction) for a_company_registered_by_a_colleague_is_not_nudged_at_its_invited_address.sql.
-- Run AFTER the definition (or with it, rolled back, through scripts/lib/safe_replay.mjs replaySql). It always ends in
-- raise exception 'CHK<<json>>', so every row it writes rolls back. Its subjects are ZZ DEMO leads at @example.invalid,
-- created here. The real outreach population (25 leads on 28 Oct) is counted before and after and must not move.
--   a  invited, unclaimed; a colleague registered the same company under another spelling -> a registered twin
--   b  the colleague's claimed lead                                                       -> never its own twin
--   c  invited, unclaimed, another company                                                 -> no twin (control)
-- fn_supplier_outreach_reachable answers false for every fixture by design, so the twin rule is asked directly, and the
-- live gate is asked whether it calls it.
do $$
declare a bigint; b bigint; c bigint; fail text := ''; v_before int; v_after int; v_gate boolean;
begin
  select count(*) into v_before from public.leads l
   where l.invite_clicked_at is not null or l.id in (select n.lead_id from public.notifications n
         where n.type in ('supplier_invite','supplier_invite_nudge','supplier_registration_reminder') and n.lead_id is not null and n.status = 'sent')
     and public.fn_supplier_outreach_reachable(l, l.email);
  insert into public.leads (company_name, email, invite_status) values ('ZZ DEMO Twin Probe Aluminium LLC', 'zz-demo-twin-a@example.invalid', 'sent') returning id into a;
  insert into public.leads (company_name, email, claimed, claimed_by) values ('ZZ DEMO Twin-Probe Aluminium L.L.C.', 'zz-demo-twin-b@example.invalid', true, 'zz-demo-twin-b@example.invalid') returning id into b;
  insert into public.leads (company_name, email, invite_status) values ('ZZ DEMO Other Probe Glass LLC', 'zz-demo-twin-c@example.invalid', 'sent') returning id into c;
  if not public.fn_supplier_name_registered_by_another((select l from public.leads l where l.id = a)) then fail := fail || 'a (registered twin) not seen; '; end if;
  if public.fn_supplier_name_registered_by_another((select l from public.leads l where l.id = b)) then fail := fail || 'b (the claimed lead) is its own twin; '; end if;
  if public.fn_supplier_name_registered_by_another((select l from public.leads l where l.id = c)) then fail := fail || 'c (another company) has a twin; '; end if;
  v_gate := pg_get_functiondef('public.fn_supplier_outreach_reachable(public.leads,text)'::regprocedure) ilike '%fn_supplier_name_registered_by_another(p)%';
  if not v_gate then fail := fail || 'fn_supplier_outreach_reachable does not call the twin rule; '; end if;
  delete from public.leads where id in (a, b, c);
  select count(*) into v_after from public.leads l
   where l.invite_clicked_at is not null or l.id in (select n.lead_id from public.notifications n
         where n.type in ('supplier_invite','supplier_invite_nudge','supplier_registration_reminder') and n.lead_id is not null and n.status = 'sent')
     and public.fn_supplier_outreach_reachable(l, l.email);
  if v_after <> v_before then fail := fail || 'the real reachable population moved; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'a', a, 'b', b, 'c', c, 'gate_calls_rule', v_gate, 'real_reachable_before', v_before, 'real_reachable_after', v_after);
end $$;
