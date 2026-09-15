-- PROBE for a_reversed_supplier_charge_is_never_owed.sql (15 Sep 2026, agent: accountant).
-- A pure probe: no DDL, and it always ends in RAISE EXCEPTION, so everything it does rolls back —
-- the ZZ DEMO supplier, its reversed charge, the recovery-basis flip, and anything the duties write.
-- Result is in the exception text: CHK<<...>> when every assertion held, FAIL<<...>> otherwise.
--
-- What it proves: a REVERSED charge that is 100 days past due, on a ZZ DEMO supplier that exists (so the
-- tick's inner join to leads does not hide it, unlike #272), with the recovery basis switched ON inside
-- the transaction so the reminder and final-demand branches are reachable, is left untouched by the
-- interest accrual, the ban sweep and the collections tick; no handoff, finding, founder alert or
-- notification names it; a court step against it is refused; it is counted by none of the receivable
-- readers; and the real dues are unaffected (owed count before = after, closed rows byte-identical).
--
--   node scripts/qsql.mjs scripts/sql/a_reversed_supplier_charge_is_never_owed_probe.sql
do $probe$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_email text := 'qd-probe-reversed-due@example.invalid';
  v_lead bigint; v_due bigint; v_void bigint;
  n_owed_before int; n_owed_after int; fp_before text; fp_after text;
  max_action bigint; max_notif bigint;
  aging_before jsonb; aging_after jsonb; kpi_before jsonb; kpi_after jsonb;
  fc_before jsonb; fc_after jsonb; fin_before jsonb; fin_after jsonb; pos_before jsonb; pos_after jsonb;
  v_acc int; v_ban int; v_tick jsonb; d public.supplier_dues; v_court text;
  n_actions int; n_findings int; n_alerts int; n_notifs int; v_banned boolean; v_stage text; v_owed boolean;
  v_360 jsonb; v_fail text[] := '{}';
begin
  -- The real rows, before anything is created. Owed rows may legitimately move (interest), so they are
  -- COUNTED; closed rows must not move at all, so they are FINGERPRINTED.
  select count(*) filter (where public.fn_supplier_due_is_owed(status, paid_at)),
         md5(coalesce(string_agg(to_jsonb(s)::text, '|' order by id) filter (where not public.fn_supplier_due_is_owed(status, paid_at)), ''))
    into n_owed_before, fp_before from public.supplier_dues s;
  select coalesce(max(id), 0) into max_action from public.agent_actions;
  select coalesce(max(id), 0) into max_notif from public.notifications;
  -- founder_alerts.id is a uuid: its watermark is the transaction start (created_at defaults to now()).
  aging_before := public.fn_accountant_dues_aging(v_today);
  select to_jsonb(k) - 'cash' into kpi_before from public.finance_kpis k;
  fc_before := public.fn_finance_forecast();
  fin_before := public.fn_ws_finance() -> 'receivables';
  pos_before := public.fn_accountant_recovery_position();

  -- The fixture: a ZZ DEMO supplier (example.invalid) with a reversed charge and a void one.
  -- leads.is_demo is GENERATED from the ZZ DEMO name and the example.invalid address; it is not set here.
  insert into public.leads (company_name, email, source)
       values ('ZZ DEMO reversed charge probe', v_email, 'demo_factory') returning id into v_lead;
  if not (select coalesce(is_demo, false) from public.leads where id = v_lead) then
    raise exception 'FAIL<<the probe supplier is not marked demo; refusing to run the duties against it>>';
  end if;
  insert into public.supplier_dues (transaction_id, supplier_id, amount_due, admin_fee, currency, status, status_reason,
                                    reveal_date, due_date, due_date_30, reminders)
       values (gen_random_uuid(), v_lead, 100, 250, 'AED', 'reversed', 'ZZ DEMO probe: reversed as fictitious, rolled back',
               v_today - 107, v_today - 100, v_today - 77, 0) returning id into v_due;
  insert into public.supplier_dues (transaction_id, supplier_id, amount_due, admin_fee, currency, status, status_reason,
                                    reveal_date, due_date, due_date_30, reminders)
       values (gen_random_uuid(), v_lead, 100, 250, 'AED', 'void', 'ZZ DEMO probe: void, rolled back',
               v_today - 107, v_today - 100, v_today - 77, 0) returning id into v_void;
  -- Inside this transaction only: the recovery basis ON, so reminders and the final demand are reachable.
  update public.decision_policy set value = jsonb_set(value, '{confirmed}', 'true'::jsonb)
   where key = 'supplier_charge_recovery_basis';

  -- The receivable readers do not count the fixture.
  if public.fn_accountant_dues_aging(v_today) is distinct from aging_before then v_fail := v_fail || 'aging counts it'::text; end if;
  if (select to_jsonb(k) - 'cash' from public.finance_kpis k) is distinct from kpi_before then v_fail := v_fail || 'finance_kpis counts it'::text; end if;
  if public.fn_finance_forecast() is distinct from fc_before then v_fail := v_fail || 'forecast counts it'::text; end if;
  if public.fn_ws_finance() -> 'receivables' is distinct from fin_before then v_fail := v_fail || 'ws_finance counts it'::text; end if;
  if public.fn_accountant_recovery_position() is distinct from pos_before then v_fail := v_fail || 'recovery_position counts it'::text; end if;
  v_360 := public.fn_ws_supplier_360(v_lead);
  if coalesce(jsonb_path_query_first(v_360, 'strict $.**.commission_owed') #>> '{}', '0')::numeric <> 0 then
    v_fail := v_fail || ('supplier_360 commission_owed ' || (jsonb_path_query_first(v_360, 'strict $.**.commission_owed') #>> '{}'));
  end if;
  select stage, owed into v_stage, v_owed from public.v_accountant_recovery_ledger where due_id = v_due;
  if v_stage is distinct from 'reversed' or v_owed is distinct from false then
    v_fail := v_fail || ('ledger stage ' || coalesce(v_stage, 'null') || ' owed ' || coalesce(v_owed::text, 'null'));
  end if;

  -- The duties, in the order the ban depends on (it needs legal_escalated_at still null).
  v_acc := public.fn_supplier_dues_accrue_interest(v_today);
  v_ban := public.fn_ban_overdue_dues();
  v_tick := public.fn_accountant_collections_tick(v_today);
  begin
    perform public.fn_accountant_record_court_step(v_due, 'filed', v_today, null);
    v_court := 'accepted';
  exception when others then v_court := sqlerrm;
  end;
  if v_court not like '%is closed%' then v_fail := v_fail || ('court step: ' || v_court); end if;

  -- Nothing touched the fixture rows.
  for d in select * from public.supplier_dues where id in (v_due, v_void) loop
    if coalesce(d.reminders, 0) <> 0 or d.last_reminder_at is not null or d.legal_stage is not null or d.legal_escalated_at is not null
       or d.interest_amount is not null or d.total_claim is not null or d.status not in ('reversed', 'void') then
      v_fail := v_fail || ('due ' || d.id || ' changed: ' || to_jsonb(d)::text);
    end if;
  end loop;
  select count(*) into n_actions from public.agent_actions a
   where a.id > max_action and (a.detail->>'due_id' in (v_due::text, v_void::text)
                                or a.detail::text like '%"due_id": ' || v_due || '%' or a.detail::text like '%"due_id": ' || v_void || '%');
  select count(*) into n_findings from public.it_engineer_finding f
   where f.closed_at is null and (f.issue_key like 'acct:%:' || v_due or f.issue_key like 'acct:%:' || v_void);
  select count(*) into n_alerts from public.founder_alerts x where x.created_at >= now() and x.detail like '%ZZ DEMO reversed charge probe%';
  select count(*) into n_notifs from public.notifications n where n.id > max_notif and to_jsonb(n)::text like '%' || v_email || '%';
  select coalesce(banned, false) into v_banned from public.leads where id = v_lead;
  if n_actions > 0 then v_fail := v_fail || (n_actions || ' handoff(s) name it'); end if;
  if n_findings > 0 then v_fail := v_fail || (n_findings || ' finding(s) name it'); end if;
  if n_alerts > 0 then v_fail := v_fail || (n_alerts || ' founder alert(s)'); end if;
  if n_notifs > 0 then v_fail := v_fail || (n_notifs || ' notification(s)'); end if;
  if v_banned then v_fail := v_fail || 'the ZZ DEMO supplier was banned'::text; end if;

  -- The real dues are unaffected.
  select count(*) filter (where public.fn_supplier_due_is_owed(status, paid_at)),
         md5(coalesce(string_agg(to_jsonb(s)::text, '|' order by id) filter (where not public.fn_supplier_due_is_owed(status, paid_at)
                                                                            and id not in (v_due, v_void)), ''))
    into n_owed_after, fp_after from public.supplier_dues s where s.supplier_id is distinct from v_lead;
  if n_owed_after <> n_owed_before then v_fail := v_fail || ('real owed ' || n_owed_before || ' -> ' || n_owed_after); end if;
  if fp_after <> fp_before then v_fail := v_fail || 'a real closed due changed'::text; end if;
  if public.fn_supplier_due_is_owed('pending', null) is not true or public.fn_supplier_due_is_owed('legal', null) is not true
     or public.fn_supplier_due_is_owed(null, null) is not true or public.fn_supplier_due_is_owed('reversed', null)
     or public.fn_supplier_due_is_owed('void', null) or public.fn_supplier_due_is_owed('pending', now()) then
    v_fail := v_fail || 'the predicate table is wrong'::text;
  end if;

  if array_length(v_fail, 1) is not null then
    raise exception 'FAIL<<%>>', array_to_string(v_fail, ' | ');
  end if;
  raise exception 'CHK<<reversed and void untouched; accrued %, banned %, reminders %, final demands %; handoffs %, findings %, alerts %, notifications %; court step refused; real owed % -> %, closed rows identical; rolled back>>',
    v_acc, v_ban, v_tick->>'reminders', v_tick->>'final_demands', n_actions, n_findings, n_alerts, n_notifs, n_owed_before, n_owed_after;
end $probe$;
