-- K22b rehearsal. Two quotations, on purpose: one keeps its live W14 run so a revision can attach
-- to it, the other has its run cancelled so an item change happens with NO live run. The second is
-- the case that matters — it is the ordinary state of the world, and it used to raise and take the
-- insert down with it.
do $k22r$
declare
  v_cust uuid; v_inq uuid; v_qa uuid; v_qb uuid; v_item_a bigint; v_item_b bigint; v_txn uuid;
  v_run_a bigint; v_run_b bigint;
  v_live text; v_dead text; v_refund text; v_class text;
  v_err_a text := 'no error'; v_err_b text := 'no error';
  v_runs_before bigint; v_runs_after bigint;
begin
  select count(*) into v_runs_before from public.phase_c_workflow_run;
  update public.kernel_signal_type set activation_state = 'active'
   where signal_type in ('supplier.quote_revision','provider.callback');

  insert into public.customers (email, full_name) values ('zz-k22@example.invalid','ZZ K22')
    returning id into v_cust;
  insert into public.inquiries (customer_id, summary, category, emirate, status, scope_type)
    values (v_cust, 'ZZ K22 rehearsal', 'flooring-suppliers', 'Dubai', 'new', 'single')
    returning id into v_inq;

  -- QUOTE A — keeps its run. Inserting the quote fires trg_new_quote_sms (K21) and opens W14.
  insert into public.quotes (inquiry_id, supplier_id, status, quote_amount)
    values (v_inq, 1, 'draft', 1000) returning id into v_qa;
  select public.fn_kernel_run_for('quotation:' || v_qa::text) into v_run_a;
  begin
    insert into public.quote_items (quote_id, description, qty, unit_price)
      values (v_qa::text, 'ZZ K22 line A', 1, 100) returning id into v_item_a;
  exception when others then v_err_a := 'INSERT RAISED: ' || left(sqlerrm, 140); end;
  select coalesce(string_agg(s.status || coalesce(' run ' || s.workflow_run_id::text, ' run -')
           || coalesce(' [' || left(s.refusal_reason, 70) || ']', ''), '; ' order by s.signal_id), '(none)')
    into v_live from public.kernel_signal_inbox s
   where s.source_type = 'dbtrigger:public.quote_items:quote_items_roll'
     and s.source_id = v_qa::text;

  -- QUOTE B — run cancelled first, so the item change finds nothing live to attach to.
  insert into public.quotes (inquiry_id, supplier_id, status, quote_amount)
    values (v_inq, 2, 'draft', 2000) returning id into v_qb;
  select public.fn_kernel_run_for('quotation:' || v_qb::text) into v_run_b;
  if v_run_b is not null then
    perform public.fn_kernel_cancel(jsonb_build_object('subject_kind','workflow_run',
      'subject_ref', v_run_b::text, 'op','cancel',
      'reason','K22b rehearsal: so the next item change has no live run to attach to',
      'actor','kernel:rehearsal'));
  end if;
  begin
    insert into public.quote_items (quote_id, description, qty, unit_price)
      values (v_qb::text, 'ZZ K22 line B', 1, 100) returning id into v_item_b;
  exception when others then v_err_b := 'INSERT RAISED: ' || left(sqlerrm, 140); end;
  select coalesce(string_agg(s.status || coalesce(' [' || left(s.refusal_reason, 90) || ']', ''), '; '), '(none)')
    into v_dead from public.kernel_signal_inbox s
   where s.source_type = 'dbtrigger:public.quote_items:quote_items_roll'
     and s.source_id = v_qb::text;

  -- the refund resolution path, which needs a live W17 run first
  insert into public.transactions (inquiry_id, supplier_id, customer_id, reveal_fee)
    values (v_inq, 1, v_cust, 50) returning id into v_txn;
  update public.transactions set refund_status = 'requested', refund_requested_at = now() where id = v_txn;
  update public.transactions set refund_status = 'refunded' where id = v_txn;
  select coalesce(string_agg(s.status || coalesce(' run ' || s.workflow_run_id::text, ''), '; '), '(none)')
    into v_refund from public.kernel_signal_inbox s
   where s.source_type = 'dbtrigger:public.transactions:trg_refund_resolved';

  select string_agg(replace(source_component_id, 'dbtrigger:public.quote_items:', '') || '=' || left(source_class,1),
           ', ' order by source_component_id)
    into v_class from public.phase_c_source_cutover
   where source_component_id like 'dbtrigger:public.quote_items:%';

  select count(*) into v_runs_after from public.phase_c_workflow_run;

  raise exception E'REHEARSAL K22B (rolled back)\n'
    '  QUOTE A, live W14 run %\n'
    '      item insert: %\n'
    '      signal ledger: %\n'
    '  QUOTE B, run cancelled first\n'
    '      item insert: %   <- must NOT raise; that was the defect\n'
    '      signal ledger: %\n'
    '  refund resolved:\n'
    '      signal ledger: %\n'
    '  quote_items classes: %\n'
    '  runs before / after: % / %',
    coalesce(v_run_a::text,'(none)'), v_err_a, v_live,
    v_err_b, v_dead, v_refund, v_class, v_runs_before, v_runs_after;
end
$k22r$;
