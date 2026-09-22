-- PROBE: EVERY WHATSAPP SAYS WHETHER IT ARRIVED, AND A FAILURE GOES BACK TO WHOEVER ASKED.
--
-- Assigned: customer_support. 22 Sep 2026. Pure probe: no DDL, nothing survives it. Run AFTER
-- every_whatsapp_says_whether_it_arrived.sql, as ONE query through the Management API; never applied.
--
-- WHAT IT RUNS, inside a block that always raises so every write is rolled back: three ZZ DEMO WhatsApp
-- rows already 'sent' to the fixture number +971500000099 with fixture SIDs (SMZZDEMOPROBE…), each
-- adopted by support's z90 trigger as a delivery.request, and mocked Twilio reports fed to
-- fn_twilio_status_arrived exactly as wa_status would.
-- VERDICT: PROBE OK only if
--   1. a sent row with no report is NOT returned as delivered (the watch keeps waiting);
--   2. sent -> delivered applies; a late 'sent' and a repeated 'delivered' are ignored (order, idempotency);
--      the watch then returns 'delivered' and the asking seat closes it 'confirmed';
--   3. 'undelivered' 63016 turns the row 'failed' with the plain-words reason; a later 'delivered' is
--      ignored; the watch returns 'failed' as a delivery.result carrying code 63016 and its meaning;
--   4. a row sent 25 hours ago with no report comes back 'sent_unconfirmed';
--   5. the backstop claims that row once and not again in the same half hour, and never the delivered one;
--   6. an unknown SID matches nothing, an unknown status is refused;
--   7. the IT duty raises no_final_status:whatsapp for the 25-hour row;
--   8. the CEO's decider, on a founder WhatsApp with a SID but no delivery report, does not write "the
--      provider confirmed" — it accepts on the confirmed email twin and says Twilio has not reported delivery.
-- Nothing reaches a person: the number is the reserved fixture range, the rows are already past the
-- queue (nothing drains 'sent'), and the whole block rolls back before any dispatcher could read it.
create temp table zz_probe_verdict (verdict text, detail text) on commit drop;
do $probe$
declare
  n1 bigint; n2 bigint; n3 bigint; q1 bigint; q2 bigint; q3 bigint;
  w0 jsonb; a_sent jsonb; a_del jsonb; a_late jsonb; a_dup jsonb; a_fail jsonb; a_after jsonb; a_unknown jsonb; a_bogus jsonb;
  r1 text; loop1 text; r2 text; r3 text; st2 text; err2 text; res2 jsonb; c1 int; c2 int; c_del int; it jsonb; it_open boolean;
  t_email bigint; t_wa bigint; t_rep bigint; ceo jsonb;
  v_err text;
begin
  begin
    insert into public.notifications (type, kind, to_role, to_phone, channel, subject, body, status, sent_at, provider_message_id, requested_by)
    values ('zz_demo_probe', 'zz_demo_probe', null, '+971500000099', 'whatsapp', 'ZZ DEMO probe 1', 'ZZ DEMO', 'sent', now(), 'SMZZDEMOPROBE000000000000000000001', 'customer_support')
    returning id into n1;
    insert into public.notifications (type, kind, to_role, to_phone, channel, subject, body, status, sent_at, provider_message_id, requested_by)
    values ('zz_demo_probe', 'zz_demo_probe', null, '+971500000099', 'whatsapp', 'ZZ DEMO probe 2', 'ZZ DEMO', 'sent', now(), 'SMZZDEMOPROBE000000000000000000002', 'customer_support')
    returning id into n2;
    insert into public.notifications (type, kind, to_role, to_phone, channel, subject, body, status, sent_at, provider_message_id, requested_by, created_at)
    values ('zz_demo_probe', 'zz_demo_probe', null, '+971500000099', 'whatsapp', 'ZZ DEMO probe 3', 'ZZ DEMO', 'sent', now() - interval '25 hours',
            'SMZZDEMOPROBE000000000000000000003', 'customer_support', now() - interval '25 hours')
    returning id into n3;
    select id into q1 from public.agent_actions where target_id = 'delivery.request:notification:' || n1;
    select id into q2 from public.agent_actions where target_id = 'delivery.request:notification:' || n2;
    select id into q3 from public.agent_actions where target_id = 'delivery.request:notification:' || n3;

    -- 1. accepted is not arrived
    w0 := public.fn_customer_support_delivery_watch(q1);
    -- 2. order and idempotency
    a_sent := public.fn_twilio_status_arrived('SMZZDEMOPROBE000000000000000000001', 'sent', null, 'probe');
    a_del  := public.fn_twilio_status_arrived('SMZZDEMOPROBE000000000000000000001', 'delivered', null, 'probe');
    a_late := public.fn_twilio_status_arrived('SMZZDEMOPROBE000000000000000000001', 'sent', null, 'probe');
    a_dup  := public.fn_twilio_status_arrived('SMZZDEMOPROBE000000000000000000001', 'delivered', null, 'probe');
    perform public.fn_customer_support_delivery_watch(q1);
    select detail->>'result', detail->>'loop' into r1, loop1 from public.agent_actions where id = q1;
    -- 3. failure, in plain words, back to the seat that asked
    a_fail  := public.fn_twilio_status_arrived('SMZZDEMOPROBE000000000000000000002', 'undelivered', '63016', 'probe');
    a_after := public.fn_twilio_status_arrived('SMZZDEMOPROBE000000000000000000002', 'delivered', null, 'probe');
    select status, last_error into st2, err2 from public.notifications where id = n2;
    perform public.fn_customer_support_delivery_watch(q2);
    select detail->>'result' into r2 from public.agent_actions where id = q2;
    select detail->'evidence' into res2 from public.agent_actions
     where kind = 'handoff' and detail->>'type' = 'delivery.result' and detail->>'request_id' = q2::text;
    -- 4. no report in 24 hours
    perform public.fn_customer_support_delivery_watch(q3);
    select detail->>'result' into r3 from public.agent_actions where id = q3;
    -- 5. the backstop
    select count(*) filter (where notification_id = n3), count(*) filter (where notification_id = n1)
      into c1, c_del from public.fn_twilio_status_poll_claim(50);
    select count(*) into c2 from public.fn_twilio_status_poll_claim(50) where notification_id = n3;
    -- 6. what matches nothing
    a_unknown := public.fn_twilio_status_arrived('SMZZDEMOPROBE000000000000000000999', 'delivered', null, 'probe');
    a_bogus   := public.fn_twilio_status_arrived('SMZZDEMOPROBE000000000000000000001', 'exploded', null, 'probe');
    -- 7. the IT duty
    it := public.fn_it_whatsapp_delivery_health();
    select exists (select 1 from public.it_engineer_finding where issue_key = 'duty:whatsapp_delivery:no_final_status:whatsapp' and closed_at is null)
      into it_open;
    -- 8. the CEO does not call a Twilio acceptance "the provider confirmed"
    insert into public.notifications (type, kind, to_email, to_role, channel, subject, body, status, sent_at, requested_by, provider_message_id)
    values ('founder_alert', 'platform_down', 'zz-demo-founder@example.invalid', 'founder', 'email', 'ZZ DEMO', 'ZZ DEMO', 'sent', now(), 'platform', 'zz-demo-pmid')
    returning id into t_email;
    insert into public.notifications (type, kind, to_email, to_role, channel, to_phone, subject, body, status, sent_at, requested_by, created_at, provider_message_id)
    select 'founder_alert', 'platform_down', 'zz-demo-founder@example.invalid', 'founder', 'whatsapp', '+971500000099', 'ZZ DEMO', 'ZZ DEMO', 'sent', now(),
           'platform', created_at, 'SMZZDEMOPROBE000000000000000000004'
      from public.notifications where id = t_email returning id into t_wa;
    insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions, requested_outcome, next_review_at, status, owner_role_id)
    values ('delivery_undelivered:zzprobe' || t_wa, 'customer_support', 'elevated', 'ZZ DEMO did not arrive',
            jsonb_build_object('rechecked', jsonb_build_object('notification_id', t_wa), 'result', 'sent_unconfirmed'), '[]'::jsonb, 'probe', now() - interval '1 minute', 'sent', 'ceo')
    returning id into t_rep;
    ceo := public.fn_ceo_delivery_undelivered_decide(t_rep);
    raise exception 'ZZPROBE rollback';
  exception when others then
    v_err := sqlerrm;
  end;
  insert into zz_probe_verdict
  select case when v_err = 'ZZPROBE rollback' and q1 is not null and q2 is not null and q3 is not null
                   and (w0->>'still_watching')::int = 1 and (w0->>'results_returned')::int = 0
                   and (a_sent->>'applied')::boolean and (a_del->>'applied')::boolean
                   and not (a_late->>'applied')::boolean and not (a_dup->>'applied')::boolean
                   and r1 = 'delivered' and loop1 = 'confirmed'
                   and (a_fail->>'applied')::boolean and not (a_after->>'applied')::boolean
                   and st2 = 'failed' and err2 like 'Twilio reported undelivered (error 63016): outside the 24-hour window%'
                   and r2 = 'failed' and res2->'notification'->>'provider_error_code' = '63016'
                   and res2->'notification'->>'provider_error_explained' like 'outside the 24-hour window%'
                   and r3 = 'sent_unconfirmed' and c1 = 1 and c2 = 0 and c_del = 0
                   and a_unknown->>'matched' = 'false' and not (a_bogus->>'applied')::boolean
                   and it_open
                   and (ceo->>'ok')::boolean and ceo->>'receipt' not like '%the provider confirmed%'
                   and ceo->>'receipt' like '%Twilio has not reported it delivered%'
              then 'PROBE OK' else 'PROBE FAILED' end,
         format('requests %s/%s/%s; watch before any report=%s; sent=%s delivered=%s late sent=%s repeat=%s; result 1=%s loop=%s; '
                || 'undelivered=%s then delivered=%s; row 2 status=%s error=%s; result 2=%s evidence=%s; result 3=%s; '
                || 'backstop first=%s second=%s delivered-row=%s; unknown sid=%s; bogus status=%s; IT duty=%s open=%s; CEO=%s; block ended with: %s',
                q1, q2, q3, w0, a_sent->'applied', a_del->'applied', a_late->'applied', a_dup->'applied', r1, loop1,
                a_fail->'applied', a_after->'applied', st2, err2, r2, res2->'notification', r3, c1, c2, c_del,
                a_unknown, a_bogus->'applied', it->'settled', it_open, ceo, v_err);
end $probe$;
select * from zz_probe_verdict;
