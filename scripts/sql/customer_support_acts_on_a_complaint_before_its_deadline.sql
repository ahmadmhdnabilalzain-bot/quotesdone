-- CUSTOMER SUPPORT ACTS ON A COMPLAINT BEFORE ITS DEADLINE (19 Oct 2026). Assigned: customer_support (the CEO decides
-- the final response). Founder ledger 1003 stage 2, contribution CS-C10: "Run complaints to the published service
-- levels (acknowledge, update, final response) with a reference number".
--
-- MEASURED 19 Oct 2026 (repo, read-only): fn_complaint_open acknowledges at once (status 'acknowledged',
-- acknowledged_at = now, acknowledge_due +2 working days, respond_due +10 working days: the Complaints Policy).
-- fn_complaint_clock_tick (seatClocks, every 30 min) opens a complaint.due item in the seat's own queue from 2 working
-- days before respond_due and reports to the CEO only AFTER it has passed. The weekly case review counts tickets past
-- respond_due after the fact. Nothing told the customer anything between acknowledgement and final response, and the
-- one person who decides the final response heard of it only once it was late.
--
-- WHAT THIS ADDS: customer_support.complaint_deadlines, hourly, fn_customer_support_complaint_deadline_tick().
-- For every ticket without its final response:
--   update   from halfway to respond_due: the ticket moves to in_review (fn_complaint_set_status) and the customer is
--            owed ONE written update with the ticket reference and the date the final response is due, in English or
--            Arabic. 27 Oct 2026 (founder_instruction 1339): the duty records what is owed
--            (fn_customer_support_voice_owe, customer_support_writes_its_duty_updates_through_the_model.sql) and the
--            MODEL writes it (_shared/duty_voice.ts); the text below is the draft, sent only on an OpenRouter outage.
--            Still once per ticket through the seat's one sending path (fn_customer_support_duty_send);
--   decide   from complaint_seat_warning_working_days (2) before respond_due: the CEO gets the decision request NOW,
--            while it can still be met (fn_support_report_to_ceo 'complaint_due_soon:<ticket>', once), with the
--            ticket, the complaint and the due date;
--   then     fn_complaint_clock_tick runs as before (the complaint.due item, and the overdue report if it still lapses).
-- qd.duty_fixtures = 'on' acts only on example.invalid tickets, and a fixture never writes to the CEO.
--
-- Prevented by: scripts/checks/customer_support_senior_contributions_are_working_duties.test.mjs.
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/customer_support_acts_on_a_complaint_before_its_deadline.sql --apply --ddl

create or replace function public.fn_customer_support_complaint_deadline_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_warn int := public.fn_seat_clock_policy('complaint_seat_warning_working_days', 2)::int;
  t public.complaint_tickets; v_due text; v_ar boolean; v_r jsonb; v_clock jsonb;
  n_update int := 0; n_ceo int := 0;
begin
  for t in select * from public.complaint_tickets
            where status <> 'final_response' and public.fn_is_demo_email(email) = v_fx order by id loop
    v_due := to_char(t.respond_due at time zone 'Asia/Dubai', 'YYYY-MM-DD');
    v_ar := coalesce(t.message, '') ~ '[؀-ۿ]';

    if now() >= t.created_at + (t.respond_due - t.created_at) / 2 then
      if t.status = 'acknowledged' then perform public.fn_complaint_set_status(t.ticket_no, 'in_review'); end if;
      if public.fn_customer_support_voice_owe('complaint.update', t.ticket_no, 'complaint.update:' || t.ticket_no, 'customer', t.email,
        case when v_ar then 'ar' else 'en' end,
        case when v_ar then 'شكواكم ' || t.ticket_no || ': قيد المراجعة' else 'Your complaint ' || t.ticket_no || ': in review' end,
        case when v_ar then
          'عزيزنا ' || coalesce(nullif(btrim(t.name), ''), 'العميل') || '،' || chr(10) || chr(10)
          || 'نودّ إعلامكم بأن شكواكم ذات المرجع ' || t.ticket_no || ' قيد المراجعة الآن. ستصلكم إجابتنا النهائية في موعد أقصاه ' || v_due
          || '. إن كانت لديكم أي معلومات إضافية، يُرجى الرد على هذه الرسالة مع ذكر المرجع.' || chr(10) || chr(10) || 'فريق QuotesDone'
        else
          'Dear ' || coalesce(nullif(btrim(t.name), ''), 'customer') || ',' || chr(10) || chr(10)
          || 'Your complaint, reference ' || t.ticket_no || ', is now in review. You will have our final response by ' || v_due
          || '. If you have anything to add, reply to this email and quote the reference.' || chr(10) || chr(10) || 'The QuotesDone team' end,
        -- what the model writes, from these facts only (nothing internal: ledger 1338)
        'Write the customer an update on their complaint: it is now in review, and our final response will reach them by the date in the facts. Address them by name when the facts give one. Invite them to reply to this e-mail with anything they want to add, quoting the reference.',
        'COMPLAINT REFERENCE: ' || t.ticket_no || chr(10) || 'CUSTOMER NAME: ' || coalesce(nullif(btrim(t.name), ''), '(not given)')
          || chr(10) || 'STATUS: in review' || chr(10) || 'FINAL RESPONSE DUE BY: ' || v_due,
        array[t.ticket_no, v_due]) then n_update := n_update + 1; end if;
    end if;

    if not v_fx and public.fn_working_days_between(now(), t.respond_due) <= v_warn and now() <= t.respond_due then
      v_r := public.fn_support_report_to_ceo(
        'complaint_due_soon:' || t.ticket_no, 'elevated',
        'Complaint ' || t.ticket_no || ' needs its final response by ' || v_due || ' Dubai',
        jsonb_build_object('ticket', t.ticket_no, 'created_at', t.created_at, 'respond_due', t.respond_due, 'status', t.status,
                           'complaint', left(coalesce(t.message, ''), 1500),
                           'policy', 'Complaints Policy: acknowledgement within 2 working days, substantive response within 10'),
        jsonb_build_array('acknowledged on ' || coalesce(t.acknowledged_at::text, '?'), 'the customer was told the due date'),
        'Decide the final response on ' || t.ticket_no || ' before ' || v_due || ' and have customer_support give it (fn_complaint_set_status).',
        p_case_ref => t.ticket_no, p_source_agent => 'customer_support');
      if coalesce((v_r->>'ok')::boolean, false) and not coalesce((v_r->>'duplicate')::boolean, false) then n_ceo := n_ceo + 1; end if;
    end if;
  end loop;

  v_clock := public.fn_complaint_clock_tick(v_fx);
  return jsonb_build_object('ok', true, 'fixture', v_fx, 'updates_owed', n_update, 'decisions_asked_before_lapse', n_ceo, 'clock', v_clock);
end $fn$;
revoke execute on function public.fn_customer_support_complaint_deadline_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_complaint_deadline_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.complaint_deadlines', 'customer_support', interval '1 hour', 'fn_customer_support_complaint_deadline_tick',
   'CS-C10: every open complaint gets its written update from halfway to the due date, the CEO''s decision is asked for before the deadline lapses, then the complaint clock runs',
   'scripts/sql/customer_support_acts_on_a_complaint_before_its_deadline.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
