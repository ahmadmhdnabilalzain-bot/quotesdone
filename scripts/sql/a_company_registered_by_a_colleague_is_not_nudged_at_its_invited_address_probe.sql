-- PROBE (pure, no DDL, aborted transaction) for a_company_registered_by_a_colleague_is_not_nudged_at_its_invited_address.sql.
-- Run with the definition in one rolled-back transaction (node scripts/ci/rehearse_sql.mjs <file> <this>) or after it is
-- applied. It always ends in raise exception 'CHK<<json>>', so every row it writes rolls back. Its subjects are ZZ DEMO leads
-- at example.invalid addresses, created here. The real reachable outreach population is counted before and after and must
-- not move. Rewritten 10 Nov 2026 (customer_support) with the rule.
--   reg  the colleague's claimed lead: licence ZZ-PROBE-7788, Dubai, account at probe-co.example.invalid -> never its own twin
--   lic  invited, the same licence number spelt differently, another name, no emirate            -> twin (licence)
--   nam  invited, the same name key, Dubai                                                         -> twin (name + emirate)
--   oth  invited, the same name key, Sharjah                                                       -> NOT a twin (unsure: keeps nudging)
--   une  invited, the same name key, no emirate                                                    -> NOT a twin (unsure)
--   dom  invited, another name, at probe-co.example.invalid                                       -> twin (corporate domain)
--   ctl  invited, another company everywhere                                                       -> no twin (control)
-- fn_supplier_outreach_reachable answers false for every fixture by design (demo marks), so the rule is asked directly and
-- the live gate and the due list are asked whether they carry it.
do $$
declare reg bigint; lic bigint; nam bigint; oth bigint; une bigint; dom bigint; ctl bigint; fail text := '';
        v_before int; v_after int; v_gate boolean; v_dedupe boolean;
  twin constant text := 'select public.fn_supplier_company_registered_by_another(l, l.email) from public.leads l where l.id = $1';
  t boolean;
begin
  select count(*) into v_before from public.leads l
   where (l.invite_clicked_at is not null or l.id in (select n.lead_id from public.notifications n
         where n.type in ('supplier_invite','supplier_invite_nudge','supplier_registration_reminder') and n.lead_id is not null and n.status = 'sent'))
     and public.fn_supplier_outreach_reachable(l, l.email);
  insert into public.leads (company_name, email, claimed, claimed_by, trade_license_no, emirate)
       values ('ZZ DEMO Twin-Probe Aluminium L.L.C.', 'zz-demo-twin-reg@probe-co.example.invalid', true, 'zz-demo-twin-reg@probe-co.example.invalid', 'ZZ-PROBE-7788', 'Dubai') returning id into reg;
  insert into public.leads (company_name, email, invite_status, trade_license_no) values ('ZZ DEMO Licence Holder Probe Glass', 'zz-demo-twin-lic@lic.example.invalid', 'sent', 'zzprobe 7788') returning id into lic;
  insert into public.leads (company_name, email, invite_status, emirate) values ('ZZ DEMO Twin Probe Aluminium LLC', 'zz-demo-twin-nam@nam.example.invalid', 'sent', 'dubai') returning id into nam;
  insert into public.leads (company_name, email, invite_status, emirate) values ('ZZ DEMO Twin Probe Aluminium LLC ', 'zz-demo-twin-oth@oth.example.invalid', 'sent', 'Sharjah') returning id into oth;
  insert into public.leads (company_name, email, invite_status) values ('ZZ DEMO Twin Probe  Aluminium LLC', 'zz-demo-twin-une@une.example.invalid', 'sent') returning id into une;
  insert into public.leads (company_name, email, invite_status) values ('ZZ DEMO Some Other Name Probe Steel', 'zz-demo-twin-dom@probe-co.example.invalid', 'sent') returning id into dom;
  insert into public.leads (company_name, email, invite_status, emirate) values ('ZZ DEMO Other Probe Glass LLC', 'zz-demo-twin-ctl@ctl.example.invalid', 'sent', 'Dubai') returning id into ctl;

  execute twin into t using reg; if t then fail := fail || 'reg (the claimed lead) is its own twin; '; end if;
  execute twin into t using lic; if not t then fail := fail || 'lic (same licence number) not seen; '; end if;
  execute twin into t using nam; if not t then fail := fail || 'nam (same name, same emirate) not seen; '; end if;
  execute twin into t using oth; if t then fail := fail || 'oth (same name, another emirate) taken for the same company; '; end if;
  execute twin into t using une; if t then fail := fail || 'une (same name, emirate unknown) taken for the same company; '; end if;
  execute twin into t using dom; if not t then fail := fail || 'dom (same corporate domain) not seen; '; end if;
  execute twin into t using ctl; if t then fail := fail || 'ctl (another company) has a twin; '; end if;

  v_gate := pg_get_functiondef('public.fn_supplier_outreach_reachable(public.leads,text)'::regprocedure) ilike '%fn_supplier_company_registered_by_another(p, p_to)%';
  if not v_gate then fail := fail || 'fn_supplier_outreach_reachable does not call the twin rule; '; end if;
  v_dedupe := pg_get_functiondef('public.fn_supplier_invite_nudges_due(timestamptz,boolean)'::regprocedure) ilike '%partition by coalesce(d.company_domain, d.to_email)%';
  if not v_dedupe then fail := fail || 'fn_supplier_invite_nudges_due does not keep one nudge per domain; '; end if;
  -- the due list still answers in fixture mode (the shared fixture domain is not collapsed into one company)
  perform count(*) from public.fn_supplier_invite_nudges_due(now(), true);

  delete from public.leads where id in (reg, lic, nam, oth, une, dom, ctl);
  select count(*) into v_after from public.leads l
   where (l.invite_clicked_at is not null or l.id in (select n.lead_id from public.notifications n
         where n.type in ('supplier_invite','supplier_invite_nudge','supplier_registration_reminder') and n.lead_id is not null and n.status = 'sent'))
     and public.fn_supplier_outreach_reachable(l, l.email);
  if v_after <> v_before then fail := fail || 'the real reachable population moved; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'gate_calls_rule', v_gate, 'due_list_dedupes_domain', v_dedupe, 'real_reachable_before', v_before, 'real_reachable_after', v_after);
end $$;
