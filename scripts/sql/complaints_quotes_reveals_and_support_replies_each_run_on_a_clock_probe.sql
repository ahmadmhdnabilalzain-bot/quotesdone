-- PROBE: complaints, short quotes, reveals and support replies each run on a clock (22 Sep 2026, ceo).
--
-- No DDL. Run AFTER complaints_quotes_reveals_and_support_replies_each_run_on_a_clock.sql is applied.
-- Returns ONE verdict row: 'PROBE OK …' or 'PROBE FAILED: <reasons>'. Also run on every pull request by
-- scripts/checks/every_duty_has_an_owner_and_a_clock.test.mjs (parity job, management token).
--
-- The rehearsal writes ONLY inside a block its own raise rolls back (zero residue, asserted after), on
-- ZZ DEMO / @example.invalid fixtures, so nothing it queues is ever committed and the outbox never sees
-- it. It proves, per clock: the behaviour, that it happens exactly once, that nothing is written to a real
-- address, and that nothing is addressed to the founder.
create temp table if not exists zz_seat_clock_probe (verdict text) on commit drop;
do $probe$
declare
  f text[] := '{}';
  v_fn text; v_n int; v_n2 int; v_before bigint; v_ticket text; v jsonb; v_inq uuid; v_tx uuid; v_q uuid;
  v_window numeric; v_left int; v_log bigint; v_lead bigint; v_chat0 int;
begin
  -- ── structure ──
  foreach v_fn in array array['public.fn_seat_clocks_tick()', 'public.fn_complaint_clock_tick(boolean)',
      'public.fn_rfq_short_of_quotes_tick(boolean)', 'public.fn_reveal_outcome_check_tick(boolean)',
      'public.fn_support_reply_watch_tick()', 'public.fn_seat_clock_refusal(boolean,text,text)',
      'public.fn_suppression_stops(text,text)', 'public.fn_opt_out_types()',
      'public.fn_seat_clock_deliver(text,text,text,text,boolean,text,text,jsonb,text,uuid,uuid,bigint)',
      'public.fn_seat_clock_compose(text,text,jsonb)', 'public.fn_complaint_due_waits_for_the_response(bigint)'] loop
    if to_regprocedure(v_fn) is null then f := f || (v_fn || ' does not exist'); continue; end if;
    if has_function_privilege('anon', to_regprocedure(v_fn), 'execute')
       or has_function_privilege('authenticated', to_regprocedure(v_fn), 'execute')
       or not exists (select 1 from pg_proc p where p.oid = to_regprocedure(v_fn)
                       and array_to_string(p.proconfig, ',') like '%search_path%') then
      f := f || (v_fn || ' is callable by anon/authenticated or has no pinned search_path');
    end if;
  end loop;
  if cardinality(f) > 0 then
    insert into zz_seat_clock_probe values ('PROBE FAILED: ' || array_to_string(f, '; '));
    return;
  end if;
  if not exists (select 1 from public.resilience_step where step = 'seatClocks' and every <= interval '1 hour') then
    f := f || text 'the heartbeat does not schedule seatClocks'; end if;
  select count(*) into v_n from public.decision_policy where key in ('complaint_seat_warning_working_days',
    'rfq_short_sweep_hours_before_deadline', 'reveal_outcome_check_days', 'support_first_reply_sla_hours');
  if v_n <> 4 then f := f || ('decision_policy carries ' || v_n || ' of the 4 clock settings'); end if;
  if not exists (select 1 from public.seat_handoff_kind where type = 'complaint.due' and to_seat = 'customer_support') then
    f := f || text 'complaint.due is not a registered conversation'; end if;

  begin
    -- ── the gate ──
    if public.fn_seat_clock_refusal(true, 'someone@quotesdone.com', 'rfq_quote_reminder') is null then f := f || text 'a fixture subject may write to a real address'; end if;
    if public.fn_seat_clock_refusal(false, 'zz.clock@example.invalid', 'rfq_quote_reminder') is null then f := f || text 'a real subject may write to a fixture address'; end if;
    if public.fn_seat_clock_refusal(true, 'zz.clock@example.invalid', 'rfq_quote_reminder') is not null then f := f || text 'a fixture subject cannot reach its own fixture'; end if;

    -- ── the suppression policy (instruction 632, PR #804): an opt-out stops only cold outreach ──
    -- The address is only READ by the gate below; nothing is ever queued to it (the row is rolled back).
    insert into public.email_suppressions (email, reason, source) values ('zz.optout.clockprobe@probe-never-sent.com', 'unsubscribe', 'probe');
    foreach v_fn in array array['rfq_quote_reminder', 'rfq_short_of_quotes', 'reveal_outcome_check'] loop
      if public.fn_seat_clock_refusal(false, 'zz.optout.clockprobe@probe-never-sent.com', v_fn) is not null then
        f := f || (v_fn || ' was stopped by an opt-out (it is not cold outreach): '
                   || public.fn_seat_clock_refusal(false, 'zz.optout.clockprobe@probe-never-sent.com', v_fn)); end if;
    end loop;
    if coalesce(public.fn_seat_clock_refusal(false, 'zz.optout.clockprobe@probe-never-sent.com', 'supplier_rfq_widened_invite'), '') not like 'opted out%' then
      f := f || text 'the cold widened invitation ignored an opt-out'; end if;
    update public.email_suppressions set reason = 'hard_bounce:permanent' where email = 'zz.optout.clockprobe@probe-never-sent.com';
    if public.fn_seat_clock_refusal(false, 'zz.optout.clockprobe@probe-never-sent.com', 'rfq_short_of_quotes') is null then
      f := f || text 'a hard bounce did not stop a customer notice'; end if;
    -- a skip is recorded: open for a real fault, recorded-and-closed for an opt-out
    v := public.fn_seat_clock_deliver('sales_engineer', 'rfq_quote_reminder', 'supplier', 'zz.optout.clockprobe@probe-never-sent.com',
           false, 'en', 'rfq_quote_reminder', '{}'::jsonb, 'zz_clock_probe_bounce');
    if coalesce((v->>'ok')::boolean, true) or not exists (select 1 from public.it_engineer_finding
         where issue_key = 'seat_clock_not_written:zz_clock_probe_bounce' and closed_at is null) then
      f := f || text 'a send refused for a bounce was not recorded as an open finding'; end if;
    update public.email_suppressions set reason = 'unsubscribe' where email = 'zz.optout.clockprobe@probe-never-sent.com';
    v := public.fn_seat_clock_deliver('sales_engineer', 'supplier_rfq_widened_invite', 'supplier', 'zz.optout.clockprobe@probe-never-sent.com',
           false, 'en', 'rfq_invite', '{}'::jsonb, 'zz_clock_probe_optout');
    if coalesce((v->>'ok')::boolean, true) or not exists (select 1 from public.it_engineer_finding
         where issue_key = 'seat_clock_not_written:zz_clock_probe_optout' and closed_at is not null) then
      f := f || text 'an opted-out invitation was not recorded (and closed) on the ledger'; end if;
    if exists (select 1 from public.notifications where lower(to_email) = 'zz.optout.clockprobe@probe-never-sent.com') then
      f := f || text 'a refused address was queued a message'; end if;

    -- ── the words, EN and AR, for every kind ──
    foreach v_fn in array array['rfq_invite', 'rfq_quote_reminder', 'rfq_short_of_quotes', 'reveal_outcome_check'] loop
      v := public.fn_seat_clock_compose(v_fn, 'ar', jsonb_build_object('name', 'ZZ DEMO', 'category', 'aluminium',
             'emirate', 'Dubai', 'quotes', 1, 'deadline', now(), 'supplier', 'ZZ DEMO supplier'));
      if v->>'lang' <> 'ar' or v->>'body' !~ '[؀-ۿ]' or v->>'subject' !~ '[؀-ۿ]' or v->>'body' !~ '/ar/portal'
         or v->>'body' ~ '(Dear|Please|quotation)' then f := f || (v_fn || ': the Arabic text is not Arabic or has no Arabic portal link'); end if;
      v := public.fn_seat_clock_compose(v_fn, 'en', jsonb_build_object('category', 'aluminium', 'emirate', 'Dubai',
             'quotes', 0, 'deadline', now()));
      if v->>'lang' <> 'en' or v->>'body' ~ '[؀-ۿ]' or v->>'body' !~ '/en/portal' then
        f := f || (v_fn || ': the English text carries Arabic or no English portal link'); end if;
    end loop;

    select coalesce(max(id), 0) into v_before from public.notifications;

    -- ── complaints: seat first, then the CEO, once; closed by the final response ──
    v_ticket := public.fn_complaint_open('zz.clock@example.invalid', 'ZZ DEMO clock probe', 'probe', null)->>'ticket';
    perform public.fn_complaint_clock_tick(true);
    if exists (select 1 from public.agent_actions where target_id = 'complaint.due:' || v_ticket) then
      f := f || text 'a fresh complaint (10 working days left) was already put on the seat''s clock'; end if;
    update public.complaint_tickets set respond_due = now() - interval '1 hour' where ticket_no = v_ticket;
    perform public.fn_complaint_clock_tick(true);
    perform public.fn_complaint_clock_tick(true);
    select count(*) into v_n from public.agent_actions
     where kind = 'handoff' and agent = 'customer_support' and target_id = 'complaint.due:' || v_ticket and status not in ('done', 'failed');
    select count(*) into v_n2 from public.support_ceo_report where idempotency_key = 'complaint_overdue:' || v_ticket || ':final_response';
    if v_n <> 1 then f := f || ('an overdue complaint left ' || v_n || ' open seat item(s), expected 1'); end if;
    if v_n2 <> 1 then f := f || ('an overdue complaint reached the CEO ' || v_n2 || ' time(s), expected once'); end if;
    perform public.fn_complaint_set_status(v_ticket, 'final_response', 'ZZ DEMO probe final response');
    perform public.fn_complaint_clock_tick(true);
    if exists (select 1 from public.agent_actions where target_id = 'complaint.due:' || v_ticket and status <> 'done') then
      f := f || text 'the seat''s complaint item stayed open after the final response'; end if;

    -- ── a request short of quotes: widen once, remind once, tell the customer once ──
    -- THE PROBE OWNS ITS REQUEST (2 Nov 2026, customer_support). It used to borrow the newest open fixture request,
    -- which on a night with a walk running is the WALK's live request: a message the walk (or a live tick) committed
    -- for it counted as a second notice, and a notice already asked for it made the probe see none -- "the customer
    -- was not told exactly once" on two PRs, green on a rerun. Nothing else can touch a row born in this block,
    -- which its own raise rolls back. It borrows only a fixture customer and that customer's request shape.
    insert into public.inquiries (customer_id, status, category, emirate)
    select i.customer_id, 'sent', i.category, i.emirate
      from public.inquiries i join public.customers c on c.id = i.customer_id
     where public.fn_seat_clock_customer_is_fixture(c) and i.category is not null
     order by i.created_at desc limit 1
    returning id into v_inq;
    if v_inq is not null then
      insert into public.leads (company_name, email) values ('ZZ DEMO clock probe supplier', 'zz.clock.supplier@example.invalid')
      returning id into v_lead;
      insert into public.inquiry_matches (inquiry_id, supplier_id, match_reason) values (v_inq, v_lead, 'ZZ DEMO clock probe: invited, not quoted');
    end if;
    if v_inq is null then
      f := f || text 'no open ZZ DEMO request exists to rehearse on';
    else
      select nullif(regexp_replace(coalesce(value, ''), '[^0-9.]', '', 'g'), '')::numeric into v_window
        from public.app_secrets where key = 'sla_quote_hours';
      update public.inquiry_matches set sent_at = now() - make_interval(secs => ((coalesce(v_window, 24) + 1) * 3600)::double precision)
       where inquiry_id = v_inq;
      update public.inquiries set routing = coalesce(routing, '{}'::jsonb) - 'short_sweep' where id = v_inq;
      perform public.fn_rfq_short_of_quotes_tick(true);
      select count(*) into v_n from public.notifications where id > v_before and inquiry_id = v_inq;
      perform public.fn_rfq_short_of_quotes_tick(true);
      select count(*) into v_n2 from public.notifications where id > v_before and inquiry_id = v_inq;
      if v_n2 <> v_n then f := f || ('a second sweep wrote ' || (v_n2 - v_n) || ' more message(s) about the same request'); end if;
      if not exists (select 1 from public.inquiries where id = v_inq and routing ? 'short_sweep') then
        f := f || text 'the widening round was not recorded on the request'; end if;
      if (select count(*) from public.notifications where id > v_before and inquiry_id = v_inq and type = 'rfq_quote_reminder') < 1 then
        f := f || text 'no invited supplier was reminded'; end if;
      if (select count(*) from public.notifications where id > v_before and inquiry_id = v_inq and type = 'rfq_short_of_quotes'
            and to_role = 'customer' and coalesce(channel, 'email') = 'email') <> 1 then
        f := f || text 'the customer was not told exactly once at the deadline'; end if;
    end if;

    -- ── seven days after a reveal: once, only inside the window before the rating ask ──
    select t.id, t.quote_id into v_tx, v_q from public.transactions t join public.customers c on c.id = t.customer_id
     where t.quote_id is not null and public.fn_seat_clock_customer_is_fixture(c) order by t.revealed_at desc limit 1;
    if v_tx is null then
      f := f || text 'no ZZ DEMO reveal exists to rehearse on';
    else
      update public.transactions set revealed_at = now() - interval '25 days', refund_status = 'window_open' where id = v_tx;
      update public.inquiries set outcome = null, status = 'revealed' where id = (select inquiry_id from public.transactions where id = v_tx);
      perform public.fn_reveal_outcome_check_tick(true);
      if exists (select 1 from public.notifications where id > v_before and quote_id = v_q and type = 'reveal_outcome_check') then
        f := f || text 'the outcome check was sent after the rating ask was due'; end if;
      update public.transactions set revealed_at = now() - interval '8 days' where id = v_tx;
      perform public.fn_reveal_outcome_check_tick(true);
      perform public.fn_reveal_outcome_check_tick(true);
      if (select count(*) from public.notifications where id > v_before and quote_id = v_q and type = 'reveal_outcome_check'
            and coalesce(channel, 'email') = 'email') <> 1 then
        f := f || text 'the 7-day outcome check was not asked exactly once'; end if;
    end if;

    -- ── time to first reply: a finding while waiting, closed when answered ──
    -- Measured by the tick's own over_sla count, never by the evidence ids: those keep only the 20 oldest,
    -- so with 21 real questions waiting (11 Oct) the probe's newest id was dropped and this read as no finding.
    v := public.fn_support_reply_watch_tick();
    v_chat0 := coalesce((v->'chat'->>'over_sla')::int, 0);
    insert into public.assistant_logs (message, reply, answered, created_at, audience, path, seat)
    values ('ZZ DEMO clock probe question', null, false, now() - interval '30 hours', 'probe', '/probe', 'customer_support')
    returning id into v_log;
    v := public.fn_support_reply_watch_tick();
    if coalesce((v->'chat'->>'over_sla')::int, 0) <> v_chat0 + 1
       or not exists (select 1 from public.it_engineer_finding where issue_key = 'support_reply_sla:chat' and closed_at is null
                        and (evidence->>'waiting')::int = v_chat0 + 1) then
      f := f || text 'an unanswered chat question past the SLA raised no finding'; end if;
    delete from public.assistant_logs where id = v_log;
    v := public.fn_support_reply_watch_tick();
    if coalesce((v->'chat'->>'over_sla')::int, 0) <> v_chat0
       or (v_chat0 = 0 and exists (select 1 from public.it_engineer_finding where issue_key = 'support_reply_sla:chat' and closed_at is null)) then
      f := f || text 'the reply finding did not close once the channel was clear'; end if;

    -- ── nothing to a real address, nothing to the founder, and the whole step runs ──
    select count(*) into v_n from public.notifications
     where id > v_before and (not public.fn_is_demo_email(to_email) or to_role in ('founder', 'admin') or type = 'founder_alert');
    if v_n <> 0 then f := f || (v_n || ' message(s) went to a real address or to the founder'); end if;
    v := public.fn_seat_clocks_tick();
    if not coalesce((v->>'ok')::boolean, false) then f := f || ('fn_seat_clocks_tick did not run clean: ' || left(v::text, 300)); end if;

    raise exception 'zz_seat_clock_probe_done';
  exception when others then
    if sqlerrm <> 'zz_seat_clock_probe_done' then f := f || ('the rehearsal raised: ' || sqlerrm); end if;
  end;

  select count(*) into v_left from public.complaint_tickets where email = 'zz.clock@example.invalid';
  if v_left <> 0 then f := f || (v_left || ' probe ticket(s) survived the rollback'); end if;
  insert into zz_seat_clock_probe values (case when cardinality(f) = 0
    then 'PROBE OK: complaints go to the seat then the CEO once and close on the final response; a short request is widened, reminded and its customer told once; the 7-day reveal check is asked once and never after the rating ask; a late first reply is a finding that closes; an opt-out stops only cold outreach and every skip is recorded; EN and AR text; nothing to a real address or the founder'
    else 'PROBE FAILED: ' || array_to_string(f, '; ') end);
end $probe$;
select verdict from zz_seat_clock_probe;
