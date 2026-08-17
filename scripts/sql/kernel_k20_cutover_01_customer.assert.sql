-- K20 rehearsal. Insert a real inquiry and a real refund complaint and prove a workflow run
-- appears, in the aborted transaction. Reading the trigger body proves it was edited; only firing
-- it proves the kernel was reached.
do $k20r$
declare
  v_cust uuid; v_inq uuid; v_child uuid; v_txn uuid;
  v_runs_before bigint; v_runs_after bigint;
  v_w05 text; v_w17 text; v_w18 text; v_inbox text; v_fail text; v_notif bigint;
  v_ab uuid; i int;
begin
  select count(*) into v_runs_before from public.phase_c_workflow_run;

  -- a customer and a NEW parent inquiry: the class-A path
  insert into public.customers (email, full_name) values ('zz-k20@example.invalid','ZZ K20 REHEARSAL')
    returning id into v_cust;
  insert into public.inquiries (customer_id, summary, category, emirate, status, scope_type)
    values (v_cust, 'ZZ K20 rehearsal inquiry', 'flooring-suppliers', 'Dubai', 'new', 'single')
    returning id into v_inq;

  -- a CHILD sub-RFQ of a combined project: must NOT get its own run
  insert into public.inquiries (customer_id, summary, category, emirate, status, scope_type, parent_inquiry_id)
    values (v_cust, 'ZZ K20 rehearsal child', 'flooring-suppliers', 'Dubai', 'new', 'single', v_inq)
    returning id into v_child;

  select coalesce(string_agg(r.workflow_id || ' run ' || r.run_id || ' obj ' || r.business_object_id, ', '), '(none)')
    into v_w05 from public.phase_c_workflow_run r where r.business_object_id like 'inquiry:%';

  select count(*) into v_notif from public.notifications where inquiry_id = v_inq;

  -- a refund complaint: the other class-A path on this increment
  -- trg_notify_refund is AFTER UPDATE with WHEN (new.refund_status = 'requested' AND it changed),
  -- so the row is inserted without a refund and then the refund is REQUESTED. Inserting it
  -- already-requested fires nothing, and a rehearsal that never fires the trigger proves nothing.
  insert into public.transactions (inquiry_id, supplier_id, customer_id, reveal_fee)
    values (v_inq, 1, v_cust, 50)
    returning id into v_txn;
  update public.transactions set refund_status = 'requested', refund_requested_at = now()
   where id = v_txn;
  select coalesce(string_agg(r.workflow_id || ' run ' || r.run_id, ', '), '(none)')
    into v_w17 from public.phase_c_workflow_run r
   where r.business_object_id = 'refund_dispute_case:' || v_txn::text;

  -- customer_abandon_ban is AFTER UPDATE and only bites at the FOURTH cancellation. Four
  -- inquiries are cancelled so the branch the emit sits in actually runs; cancelling one would
  -- prove only that the trigger stayed quiet.
  for i in 1..4 loop
    insert into public.inquiries (customer_id, summary, category, emirate, status, scope_type)
      values (v_cust, 'ZZ K20 abandon ' || i, 'flooring-suppliers', 'Dubai', 'new', 'single')
      returning id into v_ab;
    update public.inquiries set status = 'cancelled' where id = v_ab;
  end loop;
  select coalesce(string_agg(r.workflow_id || ' run ' || r.run_id, ', '), '(none)')
    into v_w18 from public.phase_c_workflow_run r
   where r.business_object_id = 'customer_case:abandon:' || v_cust::text;

  select coalesce(string_agg(i.source_system || ' -> ' || i.status
           || coalesce(' [' || left(i.refusal_reason, 90) || ']', ''), E'\n                         '), '(none)')
    into v_inbox from public.kernel_trigger_inbox i;
  select coalesce(string_agg(f.source_key || ' ' || f.sqlstate || ' ' || left(f.message, 90), '; '), '(none)')
    into v_fail from public.kernel_adapter_failure f;

  select count(*) into v_runs_after from public.phase_c_workflow_run;

  raise exception E'REHEARSAL K20 (rolled back)\n'
    '  runs before / after .... % / %\n'
    '  W05 runs by object ..... %\n'
    '  child sub-RFQ id ....... %   (must NOT appear above)\n'
    '  W17 run for txn % ...... %\n'
    '  W18 run, 4th abandon ... %\n'
    '  confirmation notifications for the inquiry: %  (must still be 1 — nothing was removed)\n'
    '  trigger inbox:\n                         %\n'
    '  adapter failures ....... %',
    v_runs_before, v_runs_after, v_w05, v_child, v_txn, v_w17, v_w18, v_notif, v_inbox, v_fail;
end
$k20r$;
