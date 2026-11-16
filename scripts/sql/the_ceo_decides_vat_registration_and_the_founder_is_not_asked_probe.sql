-- PROBE for the_ceo_decides_vat_registration_and_the_founder_is_not_asked.sql (accountant; built by it_engineer L3_IT,
-- 16 Nov 2026, ledger 1557). Pure probe: always raises CHK<<...>>, so its ZZ DEMO revenue journal, the threshold settings it
-- sets and the CEO report are rolled back. LOCAL Postgres 16 only. Before the file: "the founder was asked to decide VAT".
do $p$
declare v_fail text := ''; v_j bigint; v_r jsonb; v_before int;
begin
  -- a bare local copy has no reporting line; production's accountant reports to the ceo (fn_support_report_to_ceo reads org_reporting_edge)
  insert into public.org_reporting_edge (child_role_id, parent_role_id, established_by, reason)
  select 'accountant', 'ceo', 'probe', 'ZZ DEMO probe: a bare local copy has no reporting line'
   where not exists (select 1 from public.org_reporting_edge where child_role_id = 'accountant');
  select count(*) into v_before from public.agent_actions where detail->>'dedupe_key' like 'vat_decision:%';
  insert into public.gl_settings (key, num_value) values ('vat_registration_threshold_aed', 375000)
    on conflict (key) do update set num_value = 375000;
  insert into public.decision_policy (key, value) values ('vat_threshold_report_fractions', '["0.5", "0.8", "1"]')
    on conflict (key) do update set value = excluded.value;
  insert into public.decision_policy (key, value) values ('vat_threshold_founder_decision_fraction', '0.8')
    on conflict (key) do update set value = excluded.value;
  insert into public.gl_accounts (code, name, type, normal_balance) values ('zz4999', 'ZZ DEMO revenue', 'revenue', 'C'), ('zz1999', 'ZZ DEMO bank', 'asset', 'D')
    on conflict do nothing;
  insert into public.gl_journal (memo, source, status) values ('ZZ DEMO probe turnover', 'manual', 'draft') returning id into v_j;
  insert into public.gl_journal_lines (journal_id, line_no, account_code, debit, credit) values (v_j, 1, 'zz1999', 320000, 0), (v_j, 2, 'zz4999', 0, 320000);
  update public.gl_journal set status = 'posted', posted_at = now() where id = v_j;
  v_r := public.fn_accountant_vat_threshold_check(true);
  if coalesce((v_r->>'fraction_reached')::numeric, 0) < 0.8 then v_fail := v_fail || 'the probe did not reach the decision fraction: ' || left(v_r::text, 300) || '; '; end if;
  if (select count(*) from public.agent_actions where detail->>'dedupe_key' like 'vat_decision:%') <> v_before then
    v_fail := v_fail || 'the founder was asked to decide VAT; '; end if;
  if not coalesce((v_r->>'reported_to_ceo')::boolean, false) then v_fail := v_fail || 'the CEO was not told: ' || left(v_r::text, 300) || '; '; end if;
  if not exists (select 1 from public.support_ceo_report where idempotency_key like 'vat_threshold:%' and requested_outcome like 'Decide whether QuotesDone registers%') then
    v_fail := v_fail || 'the CEO report does not ask the CEO to decide; '; end if;
  if v_fail <> '' then raise exception 'CHK<<PROBE FAILED: %>>', v_fail; end if;
  raise exception 'CHK<<PROBE OK: VAT at % of the threshold reaches the CEO as a decision, no founder request>>', v_r->>'fraction_reached';
end $p$;
