-- every_promise_a_case_records_is_kept_or_its_seat_is_told_before_it_is_due_probe.sql (customer_support, 11 Nov 2026)
-- A pure probe: run AFTER the file, in the SAME transaction, which this probe always aborts (raise 'CHK<<...>>'), so
-- nothing it does survives (scripts/ci/rehearse_sql.mjs: begin; file; probe; rollback). Every subject is created here and
-- is ZZ DEMO with an @example.invalid address; no message is queued to anyone (the handoffs are seat records, and the
-- new_quote notice is inserted as already 'sent'). Run 11 Nov 2026 on a local Postgres 16 stub built from the schema
-- mirror: PROBE OK. It fails if any rule below is removed (each was broken once in a scratch copy and named here).
do $probe$
declare
  v_email constant text := 'zz-promise-probe@example.invalid';
  v_prof bigint; v_ref text; v_cust uuid; v_inq uuid; w jsonb; r1 jsonb; r2 jsonb; m jsonb; o jsonb;
  v_quotes bigint; v_call bigint; v_h bigint; n_rows int; n_after int; v_real int; v_real_after int; v_handoffs int;
  v_line_before int;
  v_summary jsonb;
begin
  perform set_config('qd.duty_fixtures', 'on', true);             -- the duty works fixtures only, in this transaction
  perform set_config('qd.probe_files_demo_handoff', 'on', true);  -- and files their handoffs, which the rollback removes
  select count(*) into v_real from public.support_case_promise where not is_demo;
  select count(*) into v_line_before from public.ceo_brief_line where source = 'customer_support.promise_watch';

  -- a ZZ DEMO customer with one request, known to support by the reserved address
  insert into public.customers (full_name, email) values ('ZZ DEMO promise probe', v_email) returning id into v_cust;
  insert into public.inquiries (customer_id, summary, status) values (v_cust, 'ZZ DEMO promise probe: 4 windows', 'sent') returning id into v_inq;
  v_prof := public.fn_support_profile_resolve('customer', v_cust::text, v_email, null);
  v_ref := public.fn_support_case_route(v_prof, 'new', null, 'email', 'ZZ DEMO promise probe', 'en') ->> 'case_ref';
  if v_ref is null then raise exception 'CHK<<PROBE FAILED: no case was opened>>'; end if;

  -- 1. the summary writer records each stated promise: a dated quotes promise, an undated one; an empty one is not a promise
  v_summary := jsonb_build_object('asked', 'ZZ DEMO a quote for 4 windows', 'said_or_did', 'took the sizes', 'open', '[]'::jsonb,
    'promised', jsonb_build_array(
      jsonb_build_object('what', 'send the quotes', 'by', 'in 2 hours', 'kind', 'quotes', 'due_at', to_char((now() + interval '2 hours') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
      jsonb_build_object('what', 'call them back', 'by', null, 'kind', 'invented'),
      jsonb_build_object('what', '   ', 'by', null)));
  w := public.fn_support_case_summary_write(v_ref, 0, v_summary, 'ASKED: ZZ DEMO a quote', 'ZZ DEMO windows', 'sales_engineer');
  if not coalesce((w ->> 'ok')::boolean, false) then raise exception 'CHK<<PROBE FAILED: the summary was not written: %>>', w; end if;
  select count(*) into n_rows from public.support_case_promise p join public.support_case c on c.case_id = p.case_id where c.case_ref = v_ref;
  select p.id into v_quotes from public.support_case_promise p join public.support_case c on c.case_id = p.case_id where c.case_ref = v_ref and p.what = 'send the quotes';
  select p.id into v_call from public.support_case_promise p join public.support_case c on c.case_id = p.case_id where c.case_ref = v_ref and p.what = 'call them back';
  if n_rows <> 2 or v_quotes is null or v_call is null then raise exception 'CHK<<PROBE FAILED: % promise rows, expected 2>>', n_rows; end if;
  if not exists (select 1 from public.support_case_promise where id = v_quotes and owner_seat = 'sales_engineer' and kind = 'quotes'
                   and due_basis = 'stated' and due_at < now() + interval '3 hours' and is_demo and status = 'open' and stated_in_version = 1)
    then raise exception 'CHK<<PROBE FAILED: the dated promise is not recorded as stated, quotes, sales_engineer, demo>>'; end if;
  if not exists (select 1 from public.support_case_promise where id = v_call and kind = 'other' and due_basis = 'assumed'
                   and due_at between now() + interval '47 hours' and now() + interval '49 hours')
    then raise exception 'CHK<<PROBE FAILED: the undated promise is not assumed due in 48 hours, or an invented kind was kept>>'; end if;

  -- 2. the next version restating the same promises adds no row, and keeps the first due time
  w := public.fn_support_case_summary_write(v_ref, 1, v_summary || jsonb_build_object('said_or_did', 'sent a reminder'), 'ASKED: ZZ DEMO a quote', null, 'customer_support');
  select count(*) into n_after from public.support_case_promise p join public.support_case c on c.case_id = p.case_id where c.case_ref = v_ref;
  if n_after <> 2 or not exists (select 1 from public.support_case_promise where id = v_quotes and owner_seat = 'sales_engineer' and stated_in_version = 1)
    then raise exception 'CHK<<PROBE FAILED: a restated promise became a second row (% rows) or changed owner>>', n_after; end if;

  -- 3. the duty flags the promise due within 24 hours to its seat, once; the one due in 48 hours waits
  r1 := public.fn_support_case_promise_watch();
  r2 := public.fn_support_case_promise_watch();
  select handoff_id into v_h from public.support_case_promise where id = v_quotes;
  if (r1 ->> 'flagged')::int <> 1 or (r2 ->> 'flagged')::int <> 0 or v_h is null
     or exists (select 1 from public.support_case_promise where id = v_call and flagged_at is not null)
    then raise exception 'CHK<<PROBE FAILED: flagging (first %, second %, handoff %)>>', r1, r2, v_h; end if;
  if not exists (select 1 from public.agent_actions where id = v_h and kind = 'handoff' and agent = 'sales_engineer'
                   and detail ->> 'type' = 'support.promise_due' and status <> 'failed')
    then raise exception 'CHK<<PROBE FAILED: the flag is not a live support.promise_due handoff to sales_engineer>>'; end if;
  select count(*) into v_handoffs from public.agent_actions where kind = 'handoff' and target_id = 'support.promise_due:' || v_quotes;
  if v_handoffs <> 1 then raise exception 'CHK<<PROBE FAILED: % handoffs for one promise>>', v_handoffs; end if;

  -- 4. the quotes reach the customer: the promise closes as kept, by the event, and its flag closes with it
  insert into public.notifications (type, to_email, inquiry_id, subject, body, status, sent_at, channel)
  values ('new_quote', v_email, v_inq, 'ZZ DEMO new quote', 'ZZ DEMO', 'sent', now() + interval '1 second', 'email');
  update public.support_case_promise set created_at = now() - interval '1 minute' where id in (v_quotes, v_call);
  o := public.fn_support_case_promise_watch();
  if (o ->> 'kept')::int <> 1 or not exists (select 1 from public.support_case_promise where id = v_quotes and status = 'kept'
       and closed_how like 'quotes delivered: notification %' and closed_at is not null)
    then raise exception 'CHK<<PROBE FAILED: the delivered quotes did not keep the promise: %>>', o; end if;
  if exists (select 1 from public.agent_actions where id = v_h and status not in ('done', 'completed'))
    then raise exception 'CHK<<PROBE FAILED: the kept promise left its flag open (%)>>', (select status from public.agent_actions where id = v_h); end if;
  if exists (select 1 from public.support_case_promise where id = v_call and status <> 'open')
    then raise exception 'CHK<<PROBE FAILED: a notice kept a promise that is not about quotes>>'; end if;

  -- 5. what code cannot see, the owning seat marks: not another seat, not without saying how
  m := public.fn_support_case_promise_mark(v_call, 'kept', 'customer_support', 'called them');
  if coalesce((m ->> 'ok')::boolean, true) then raise exception 'CHK<<PROBE FAILED: a seat that does not own the promise marked it>>'; end if;
  m := public.fn_support_case_promise_mark(v_call, 'kept', 'sales_engineer', '');
  if coalesce((m ->> 'ok')::boolean, true) then raise exception 'CHK<<PROBE FAILED: a promise was marked without saying how>>'; end if;
  m := public.fn_support_case_promise_mark(v_call, 'kept', 'sales_engineer', 'ZZ DEMO called them on 11 Nov');
  if not coalesce((m ->> 'ok')::boolean, false) or not exists (select 1 from public.support_case_promise where id = v_call and status = 'kept' and closed_by = 'sales_engineer')
    then raise exception 'CHK<<PROBE FAILED: the owning seat could not mark its promise: %>>', m; end if;

  -- 6. nothing real moved, and a fixture never reaches the CEO's brief
  select count(*) into v_real_after from public.support_case_promise where not is_demo;
  if v_real_after <> v_real then raise exception 'CHK<<PROBE FAILED: real promises moved (% -> %)>>', v_real, v_real_after; end if;
  if (select count(*) from public.ceo_brief_line where source = 'customer_support.promise_watch') <> v_line_before
    then raise exception 'CHK<<PROBE FAILED: a fixture reached the CEO brief>>'; end if;

  raise exception 'CHK<<PROBE OK %>>', jsonb_build_object('case', v_ref, 'first_watch', r1, 'kept_watch', o);
end $probe$;
