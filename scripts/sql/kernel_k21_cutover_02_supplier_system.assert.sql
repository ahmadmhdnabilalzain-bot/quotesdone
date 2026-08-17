-- K21 rehearsal. Fire all three triggers for real and prove a run appears for each.
do $k21r$
declare
  v_cust uuid; v_inq uuid; v_quote uuid; v_txn uuid; v_action bigint;
  v_runs_before bigint; v_runs_after bigint;
  v_w14 text; v_w16 text; v_w29 text; v_inbox text; v_fail text; v_goal text;
begin
  select count(*) into v_runs_before from public.phase_c_workflow_run;

  insert into public.customers (email, full_name) values ('zz-k21@example.invalid','ZZ K21 REHEARSAL')
    returning id into v_cust;
  insert into public.inquiries (customer_id, summary, category, emirate, status, scope_type)
    values (v_cust, 'ZZ K21 rehearsal inquiry', 'flooring-suppliers', 'Dubai', 'new', 'single')
    returning id into v_inq;

  -- W14: a new quotation row
  insert into public.quotes (inquiry_id, supplier_id, status, quote_amount)
    values (v_inq, 1, 'draft', 1000) returning id into v_quote;
  select coalesce(string_agg(r.workflow_id || ' run ' || r.run_id, ', '), '(none)')
    into v_w14 from public.phase_c_workflow_run r
   where r.business_object_id = 'quotation:' || v_quote::text;

  -- W16: trg_reveal_receipt_a is AFTER INSERT OR UPDATE and bites when revealed_at first appears.
  insert into public.transactions (inquiry_id, supplier_id, customer_id, reveal_fee, payment_ref)
    values (v_inq, 1, v_cust, 50, 'ZZ-K21-PAY-1') returning id into v_txn;
  update public.transactions set revealed_at = now() where id = v_txn;
  select coalesce(string_agg(r.workflow_id || ' run ' || r.run_id, ', '), '(none)')
    into v_w16 from public.phase_c_workflow_run r
   where r.business_object_id = 'payment_transaction:ZZ-K21-PAY-1';

  -- W29: only a high-risk pending action from one of the three named agents
  insert into public.agent_actions (agent, kind, status, risk, title, recommendation)
    values ('security_ai','zz_k21_probe','pending','high','ZZ K21 rehearsal incident','check it')
    returning id into v_action;
  select coalesce(string_agg(r.workflow_id || ' run ' || r.run_id, ', '), '(none)')
    into v_w29 from public.phase_c_workflow_run r
   where r.business_object_id = 'incident:agent_action:' || v_action::text;

  select status || ' :: ' || left(cutover_action, 80) into v_goal
    from public.phase_c_source_cutover
   where source_component_id = 'dbtrigger:public.company_goals:trg_goal_cascade';

  select coalesce(string_agg(i.source_system || ' -> ' || i.status
           || coalesce(' [' || left(i.refusal_reason, 100) || ']', ''), E'\n                    '), '(none)')
    into v_inbox from public.kernel_trigger_inbox i;
  select coalesce(string_agg(f.source_key || ' ' || f.sqlstate || ' ' || left(f.message, 100), '; '), '(none)')
    into v_fail from public.kernel_adapter_failure f;
  select count(*) into v_runs_after from public.phase_c_workflow_run;

  raise exception E'REHEARSAL K21 (rolled back)\n'
    '  runs before / after % / %\n'
    '  W14 for the quote . %\n'
    '  W16 for the reveal  %\n'
    '  W29 for the action  %\n'
    '  goal_cascade ...... %\n'
    '  inbox:\n                    %\n'
    '  adapter failures .. %',
    v_runs_before, v_runs_after, v_w14, v_w16, v_w29, v_goal, v_inbox, v_fail;
end
$k21r$;
