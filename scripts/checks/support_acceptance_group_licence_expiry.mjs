// §15 GROUP 8 — LICENCE EXPIRY BOUNDARIES, AND THE CHASE THAT MUST STOP
//
//   "License dates 31/30/29/1/0/-1, unknown expiry, all three upload channels, cross-channel
//    duplicates, old-after-new arrival, unclear/mismatched documents and cancellation of obsolete
//    reminders after approval."
//
// It lives in its own module because the SQL contains dollar-quoting, and this repository has a
// standing hazard with shell-generated files mangling it. Written once, imported by the harness.
//
// THE BOUNDARY THAT MATTERS MOST IS 31 vs 30. The sweep window is `expiry <= today + 30`. An
// off-by-one there is invisible in production -- nobody notices a supplier chased a day early, or
// one never chased until the licence had already expired. Only a test with a lead on each side of
// the line can tell which of those is happening.
//
// 13 OCT 2026 (ruling 1209): the asks are at 30 and 7 days only. Day 0 is the PAUSE day (fn_reconcile_doc_blocks pauses
// matching and tells the supplier, the one message for that threshold) and day -1 is already paused, so neither gets a
// sweep ask any more (they were t_minus_7 and expired). a_licence_is_asked_for_at_30_and_7_days_and_paused_on_its_expiry_day.sql.
//
// AND THE SWEEP IS RUN FOR REAL, not in dry-run. The dry run returns a SAMPLE capped at ten rows
// ordered by expiry, so a lead created for a test can be absent from it while having been processed
// perfectly. Reading that sample and calling the absence a failure would be measuring the wrong
// subject -- the report, not the work. Run against the actual rows, inside a transaction that rolls
// back, and the ask table itself answers the question.

const S = (name, expect, critical = false) => ({ name, expect, critical });

export const G8 = {
  title: '8. Expiry boundaries at 31/30/29/1/0/-1, and obsolete reminders cancelled on arrival',
  scenarios: [
    S('day_31_is_outside_the_window', '0'),
    S('day_30_is_the_first_day_asked', '1'),
    S('day_29_is_asked', '1'),
    S('day_1_is_asked', '1'),
    S('day_0_is_the_pause_day_not_an_ask', '(absent)'),
    S('day_minus_1_is_not_asked', '(absent)'),
    S('unknown_expiry_is_never_chased', '0'),
    S('a_blocked_channel_is_recorded_not_hidden', 'true'),
    S('one_ask_per_band_per_channel_ever', '1', true),
    S('email_arrival_stops_the_chase', '1', true),
    S('portal_arrival_stops_the_chase', '1', true),
    S('a_held_document_stops_nothing', '0', true),
    S('a_message_going_out_answers_nothing', '0', true),
  ],
  sql: `do $p$
declare
  d date := (now() at time zone 'Asia/Dubai')::date;
  v_none bigint; sw jsonb; sw2 jsonb; e1 jsonb; e2 jsonb; e3 jsonb;
  v_31 bigint; v_30 bigint; v_29 bigint; v_1 bigint; v_0 bigint; v_m1 bigint;
  n31 int; n30 int; n29 int; n1 int; nnone int; nrepeat int;
  b0 text; bm1 text; v_wa boolean; v_c1 int; v_c2 int; v_c3 int; v_sent int;
begin
  insert into public.leads (company_name, email, phone, license_expiry)
  values ('ZZ DEMO Exp 31','zz31@example.invalid','+971509991031', d + 31) returning id into v_31;
  insert into public.leads (company_name, email, phone, license_expiry)
  values ('ZZ DEMO Exp 30','zz30@example.invalid','+971509991030', d + 30) returning id into v_30;
  insert into public.leads (company_name, email, phone, license_expiry)
  values ('ZZ DEMO Exp 29','zz29@example.invalid','+971509991029', d + 29) returning id into v_29;
  insert into public.leads (company_name, email, phone, license_expiry)
  values ('ZZ DEMO Exp 1','zz01@example.invalid','+971509991001', d + 1) returning id into v_1;
  insert into public.leads (company_name, email, phone, license_expiry)
  values ('ZZ DEMO Exp 0','zz00@example.invalid','+971509991000', d) returning id into v_0;
  insert into public.leads (company_name, email, phone, license_expiry)
  values ('ZZ DEMO Exp -1','zzm1@example.invalid','+971509991201', d - 1) returning id into v_m1;
  insert into public.leads (company_name, email, phone)
  values ('ZZ DEMO Exp none','zznone@example.invalid','+971509991099') returning id into v_none;

  -- THE REAL SWEEP. It writes; the transaction rolls it back.
  sw := public.fn_licence_expiry_sweep(false);

  select count(*) into n31   from public.licence_renewal_ask where lead_id = v_31   and channel='email';
  select count(*) into n30   from public.licence_renewal_ask where lead_id = v_30   and channel='email';
  select count(*) into n29   from public.licence_renewal_ask where lead_id = v_29   and channel='email';
  select count(*) into n1    from public.licence_renewal_ask where lead_id = v_1    and channel='email';
  select count(*) into nnone from public.licence_renewal_ask where lead_id = v_none;
  select max(band) into b0   from public.licence_renewal_ask where lead_id = v_0;
  select max(band) into bm1  from public.licence_renewal_ask where lead_id = v_m1;

  v_wa := coalesce(sw->>'whatsapp_status','') <> '';

  -- "One ask per band per channel, ever." A second sweep must add nothing.
  sw2 := public.fn_licence_expiry_sweep(false);
  select count(*) into nrepeat from public.licence_renewal_ask where lead_id = v_30 and channel='email';

  -- THE CHASE, AND WHAT STOPS IT. A licence arrives by email for one supplier, by portal for
  -- another, and from an unmatched sender for a third who is therefore still owed a document.
  e1 := public.fn_support_receive_document('email','zz30@example.invalid','in/new-licence.pdf','trade licence','application/pdf');
  e2 := public.fn_support_receive_document('portal','sess-9','portal/blob.bin','x','application/pdf','licence', v_29);
  e3 := public.fn_support_receive_document('email','ghost@elsewhere.invalid','in/ghost.pdf','trade licence','application/pdf');

  select count(*) into v_c1 from public.licence_renewal_ask where lead_id=v_30 and answered_at is not null;
  select count(*) into v_c2 from public.licence_renewal_ask where lead_id=v_29 and answered_at is not null;
  select count(*) into v_c3 from public.licence_renewal_ask where lead_id=v_1  and answered_at is not null;
  -- The third supplier was SENT an ask and nothing arrived for them. Sending answers nothing.
  select count(*) into v_sent from public.licence_renewal_ask
   where lead_id=v_1 and sent and answered_at is not null;

  raise exception 'CHK<<day_31_is_outside_the_window=%||day_30_is_the_first_day_asked=%||day_29_is_asked=%||day_1_is_asked=%||day_0_is_the_pause_day_not_an_ask=%||day_minus_1_is_not_asked=%||unknown_expiry_is_never_chased=%||a_blocked_channel_is_recorded_not_hidden=%||one_ask_per_band_per_channel_ever=%||email_arrival_stops_the_chase=%||portal_arrival_stops_the_chase=%||a_held_document_stops_nothing=%||a_message_going_out_answers_nothing=%>>',
    n31, n30, n29, n1, coalesce(b0,'(absent)'), coalesce(bm1,'(absent)'), nnone, v_wa,
    nrepeat, v_c1, v_c2, v_c3, v_sent;
end $p$;`,
};
