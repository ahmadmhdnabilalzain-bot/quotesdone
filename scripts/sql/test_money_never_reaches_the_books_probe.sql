-- PROBE, ROLLED BACK: test money never reaches the books (scripts/sql/test_money_never_reaches_the_books.sql).
-- Assigned: accountant. Pure probe, no DDL, so it ends in raise exception and every row it wrote is gone.
-- It cannot reach a real person: supplier_dues has no triggers, the ZZ DEMO lead and expense carry the demo
-- markers, and nothing it queues (a finding, a notification) survives the abort.
--
-- Proves, through the live fn_gl_sync_business:
--   a real-shaped due (a lead that exists and is not demo)      -> booked
--   a fixture due (a ZZ DEMO / demo_factory / example.invalid lead) -> not booked, no finding
--   an orphaned due (its supplier does not exist)                -> not booked, an open accountant finding
--   a ZZ DEMO expense                                            -> not booked by the sync or by fn_expense_post_to_gl
--
--   node scripts/qsql.mjs scripts/sql/test_money_never_reaches_the_books_probe.sql   (expect CHK<<...>>)
do $probe$
declare v_real_lead bigint; v_fix_lead bigint; v_gone bigint;
        d_real bigint; d_fix bigint; d_orph bigint; e_demo bigint; r jsonb;
begin
  select min(id) into v_real_lead from public.leads where not coalesce(is_demo, false);
  insert into public.leads (company_name, email, source)
       values ('ZZ DEMO ledger probe', 'qd-probe-ledger@example.invalid', 'demo_factory') returning id into v_fix_lead;
  select coalesce(max(id), 0) + 1000000 into v_gone from public.leads;

  insert into public.supplier_dues (supplier_id, amount_due, admin_fee, status, currency)
       values (v_real_lead, 100, 0, 'due', 'AED') returning id into d_real;
  insert into public.supplier_dues (supplier_id, amount_due, admin_fee, status, currency)
       values (v_fix_lead, 100, 0, 'due', 'AED') returning id into d_fix;
  insert into public.supplier_dues (supplier_id, amount_due, admin_fee, status, currency)
       values (v_gone, 100, 0, 'due', 'AED') returning id into d_orph;
  insert into public.expense_entries (vendor, amount, currency, note)
       values ('ZZ DEMO ledger probe', 1, 'AED', 'probe, rolled back') returning id into e_demo;

  perform public.fn_gl_sync_business();

  r := jsonb_build_object(
    'real_due_booked',       exists (select 1 from public.gl_journal where source = 'commission_accrue' and source_ref = d_real::text),
    'fixture_due_booked',    exists (select 1 from public.gl_journal where source = 'commission_accrue' and source_ref = d_fix::text),
    'orphan_due_booked',     exists (select 1 from public.gl_journal where source = 'commission_accrue' and source_ref = d_orph::text),
    'orphan_finding_open',   exists (select 1 from public.it_engineer_finding where issue_key = 'duty:ledger_orphan:supplier_dues:' || d_orph and closed_at is null),
    'fixture_finding_open',  exists (select 1 from public.it_engineer_finding where issue_key = 'duty:ledger_orphan:supplier_dues:' || d_fix and closed_at is null),
    'demo_expense_booked',   exists (select 1 from public.gl_journal where source = 'expense' and source_ref = e_demo::text),
    'demo_expense_direct',   public.fn_expense_post_to_gl(e_demo),
    'journal_690_status',    (select status from public.gl_journal where id = 690),
    'reversal_of_690',       (select id from public.gl_journal where source = 'reversal' and source_ref = '690'),
    'due_272_status',        (select status from public.supplier_dues where id = 272));
  r := r || jsonb_build_object('pass',
         (r->>'real_due_booked')::boolean and not (r->>'fixture_due_booked')::boolean
         and not (r->>'orphan_due_booked')::boolean and (r->>'orphan_finding_open')::boolean
         and not (r->>'fixture_finding_open')::boolean and not (r->>'demo_expense_booked')::boolean
         and r->>'demo_expense_direct' is null);
  raise exception 'CHK<<%>>', r;
end $probe$;
