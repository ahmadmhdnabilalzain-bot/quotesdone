-- every_escalation_carries_a_clock_and_the_ceo_decides_it_not_the_founder_probe.sql — a PURE probe: it always raises CHK<<...>>,
-- so everything it does rolls back. Assigned: customer_support (agent FOUNDER_CLOCK). Run after the DDL file, or with it in one
-- rolled-back transaction, on the LOCAL database (scripts/db/local_pg16.mjs). Expect: CHK<<PROBE OK ...>>.
-- IT CANNOT REACH A PERSON: every requester is a reserved fixture (+971 50 000 00xx, @example.invalid) or a site visitor named only by
-- a documentation address (203.0.113.0/24, RFC 5737) with no e-mail or phone, so no delivery has anywhere to go; it never writes
-- stripe_live_hold; real rows of the tables it touches are counted before and after.
do $probe$
declare
  v_mail text := 'zz-clock-probe@example.invalid';
  v_wa text := 'whatsapp:+971500000097';
  v_wa_open text := '+971500000096';
  v_visitor text := 'site visitor 203.0.113.77';
  v_real_clocks bigint := (select count(*) from public.escalation_clock);
  v_real_reviews bigint := (select count(*) from public.decision_review_request where requester not in ('zz-clock-probe@example.invalid', 'site visitor 203.0.113.77', 'whatsapp:+971500000097'));
  v_founder_before bigint := (select count(*) from public.founder_alerts);
  v jsonb; v_due jsonb; v_id bigint; v_id2 bigint; v_rr bigint; c public.escalation_clock; r public.decision_review_request;
  v_routes_added boolean := false;
begin
  -- 0. the shape: RLS with its policy, nothing granted to anon or authenticated
  if not exists (select 1 from pg_policies where tablename = 'escalation_clock' and policyname = 'escalation_clock_service_role_only') then
    raise exception 'CHK<<PROBE FAILED: escalation_clock has no service-role-only policy>>';
  end if;
  if has_function_privilege('anon', 'public.fn_escalation_clock_open(text, text, text, text, text, text, text, text, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_escalation_case_facts(text, text)', 'execute')
     or has_function_privilege('anon', 'public.fn_review_request_open(text, text, text, text, text, text, text, text, bigint, text)', 'execute') then
    raise exception 'CHK<<PROBE FAILED: a clock routine is executable by anon or authenticated>>';
  end if;
  perform set_config('qd.duty_fixtures', 'on', true);
  if not exists (select 1 from public.review_route where decision_type = 'person') then
    insert into public.review_route (decision_type, owner_seat, meaning) values ('person', 'customer_support', 'speaking to a person');
    v_routes_added := true;
  end if;

  -- 1. an explicit person request by e-mail goes to the CEO with a clock; the founder is not paged; the row reads 'with_ceo'
  v := public.fn_review_request_open('person', 'email', v_mail, 'ZZ DEMO I want to speak to a real person about my request',
         'inbound_messages', '-9001', null, null, null, 'email:zz-clock-probe');
  v_rr := (v->>'id')::bigint;
  select * into r from public.decision_review_request where id = v_rr;
  if r.status <> 'with_ceo' or r.founder_notified is not null or v->>'owner_seat' <> 'ceo' then
    raise exception 'CHK<<PROBE FAILED: the person request reads % (founder_notified %, owner %), not with_ceo and unpaged>>', r.status, r.founder_notified, v->>'owner_seat';
  end if;
  if (select count(*) from public.founder_alerts) <> v_founder_before then
    raise exception 'CHK<<PROBE FAILED: a person request paged the founder>>';
  end if;
  v_id := (v->'escalation_clock'->>'id')::bigint;
  select * into c from public.escalation_clock where id = v_id;
  if c.id is null or c.kind <> 'person' or c.source_table <> 'inbound_messages' or not c.fixture or c.owner_seat <> 'customer_support' or c.decider_seat <> 'ceo'
     or not coalesce((c.detail->>'promise_generic')::boolean, false) or c.status_due_at <= now() then
    raise exception 'CHK<<PROBE FAILED: the clock is not the e-mail''s generic person clock owned by support and decided by the CEO: %>>', row_to_json(c);
  end if;

  -- 2. the channel's own call after its reply lands on the same clock: the exact words replace the generic promise, legal sharpens the kind
  v := public.fn_escalation_clock_open('inbound_messages', '-9001', 'legal', 'email', v_mail,
         'ZZ DEMO We have your letter; it is with the person accountable for legal matters, who will reply in this thread.', null, 'Re: ZZ DEMO', '{}'::jsonb);
  select * into c from public.escalation_clock where id = v_id;
  if (v->>'id')::bigint <> v_id or not (v->>'existing')::boolean or c.kind <> 'legal' or c.promised not like 'ZZ DEMO We have your letter%' or c.detail ? 'promise_generic' then
    raise exception 'CHK<<PROBE FAILED: the second open did not land on the same clock with the exact promise and the legal kind: %>>', row_to_json(c);
  end if;

  -- 3. the CEO's queue: the new clock is due for a decision, with the founder facts beside it
  v_due := public.fn_escalation_clocks_due(10);
  if not exists (select 1 from jsonb_array_elements(v_due) x where (x->>'id')::bigint = v_id and x->>'due_for' = 'decide' and x->'founder' ? 'founder_last_answered_at') then
    raise exception 'CHK<<PROBE FAILED: the clock is not due for the CEO''s decision: %>>', v_due;
  end if;

  -- 4. a "founder" answer that names no law stays the CEO's; one that names the law reaches him through founder_mail_policy (fixture: not sent)
  v := public.fn_escalation_clock_ceo_decided(v_id, 'founder_by_law', 'Send it to the founder', 'ZZ DEMO the founder should look', 'probe/model', null, 'legal');
  select * into c from public.escalation_clock where id = v_id;
  if c.state <> 'open' or c.ceo_reason not like '%without naming the law%' or c.ceo_attempts <> 1 then
    raise exception 'CHK<<PROBE FAILED: a founder answer with no law was not kept as the CEO''s: %>>', row_to_json(c);
  end if;
  if exists (select 1 from jsonb_array_elements(public.fn_escalation_clocks_due(10)) x where (x->>'id')::bigint = v_id and x->>'due_for' = 'decide') then
    raise exception 'CHK<<PROBE FAILED: the CEO is asked again within 6 hours>>';
  end if;

  -- 5. decided within its authority: due to be told; told on e-mail (fixture capture under the duty switch) closes the case
  update public.escalation_clock set ceo_tried_at = now() - interval '7 hours' where id = v_id;
  v := public.fn_escalation_clock_ceo_decided(v_id, 'decided', 'ZZ DEMO The request is closed with no charge; customer_support explains why.', 'ZZ DEMO within the CEO''s authority', 'probe/model');
  if not exists (select 1 from jsonb_array_elements(public.fn_escalation_clocks_due(10)) x where (x->>'id')::bigint = v_id and x->>'due_for' = 'tell') then
    raise exception 'CHK<<PROBE FAILED: a decided clock is not due to be told>>';
  end if;
  v := public.fn_escalation_clock_deliver(v_id, 'decision', 'Re: ZZ DEMO', 'ZZ DEMO the decision, written by the model');
  if not coalesce((v->>'sent')::boolean, false) or v->>'via' <> 'email' then
    raise exception 'CHK<<PROBE FAILED: the fixture decision was not captured by e-mail: %>>', v;
  end if;
  if not exists (select 1 from public.customer_support_duty_message where stage = 'escalation.decision' and subject_key = v_id::text) then
    raise exception 'CHK<<PROBE FAILED: the e-mail did not go through customer_support''s duty send>>';
  end if;
  v := public.fn_escalation_clock_told(v_id, 'decision', v, 'ZZ DEMO the decision, written by the model');
  select * into c from public.escalation_clock where id = v_id;
  if c.state <> 'closed' or c.statuses_sent <> 1 or c.closed_reason not like 'decided and told%' then
    raise exception 'CHK<<PROBE FAILED: telling the decision did not close the case: %>>', row_to_json(c);
  end if;
  -- a second delivery of the same stage is refused by the duty send (once per clock and stage)
  v := public.fn_escalation_clock_deliver(v_id, 'decision', 'Re: ZZ DEMO', 'again');
  if coalesce((v->>'sent')::boolean, false) then raise exception 'CHK<<PROBE FAILED: the same stage was sent twice>>'; end if;
  -- a closed clock does not stop the next escalation from the same subject
  v := public.fn_escalation_clock_open('inbound_messages', '-9001', 'person', 'email', v_mail, null, 'ZZ DEMO again', null, '{}'::jsonb);
  if (v->>'existing')::boolean or (v->>'id')::bigint = v_id then raise exception 'CHK<<PROBE FAILED: a closed clock blocked a new one>>'; end if;

  -- 6. WhatsApp: a closed window and no owner is no open channel; an open window sends through send_whatsapp (local net stand-in)
  v := public.fn_escalation_clock_open('wa_conversation', v_wa, 'escalation', 'whatsapp', v_wa, 'ZZ DEMO the WhatsApp reply that went', 'ZZ DEMO you took my money', null, '{}'::jsonb);
  v_id2 := (v->>'id')::bigint;
  v := public.fn_escalation_clock_deliver(v_id2, 'status_1', null, 'ZZ DEMO status');
  if coalesce((v->>'sent')::boolean, false) or v->>'reason' not like 'no open channel%' then
    raise exception 'CHK<<PROBE FAILED: a closed WhatsApp window with no e-mail was not "no open channel": %>>', v;
  end if;
  v := public.fn_escalation_clock_told(v_id2, 'status_1', v, 'ZZ DEMO status');
  select * into c from public.escalation_clock where id = v_id2;
  if c.attempts <> 1 or c.status_due_at > now() + interval '61 minutes' or c.statuses_sent <> 0 then
    raise exception 'CHK<<PROBE FAILED: an unsent status is not retried in an hour: %>>', row_to_json(c);
  end if;
  insert into public.wa_conversation (phone_e164, party_kind, window_opened_at, window_expires_at) values ('971500000096', 'unknown', now(), now() + interval '20 hours');
  v := public.fn_escalation_clock_open('wa_conversation', v_wa_open, 'escalation', 'whatsapp', v_wa_open, 'ZZ DEMO reply', 'ZZ DEMO complaint', null, '{}'::jsonb);
  insert into public.app_secrets (key, value) values ('cred_fn_resilience_ping', 'zz-probe-not-a-secret') on conflict (key) do nothing;
  v := public.fn_escalation_clock_deliver((v->>'id')::bigint, 'status_1', null, 'ZZ DEMO status in the window');
  if not coalesce((v->>'sent')::boolean, false) or v->>'via' <> 'whatsapp' then
    raise exception 'CHK<<PROBE FAILED: an open WhatsApp window did not carry the status: %>>', v;
  end if;

  -- 7. the case facts of every channel: the person's own open escalation and the founder facts
  v := public.fn_escalation_case_facts(null, '+971 50 000 0097');
  if jsonb_array_length(v->'open_escalations') <> 1 or v->'open_escalations'->0->>'kind' <> 'escalation'
     or not (v ? 'founder_last_answered_at') or not (v ? 'channels_down_founder_credential') then
    raise exception 'CHK<<PROBE FAILED: the case facts by phone are wrong: %>>', v;
  end if;
  insert into public.it_engineer_finding (issue_key, title, where_it_is, blast, evidence)
  values ('duty:zz_probe:zz_meta_probe', 'ZZ DEMO a credential only the founder can renew', 'probe', 'agent_facing', '{"founder_required_credential": true}');
  if not exists (select 1 from jsonb_array_elements(public.fn_founder_availability()->'channels_down_founder_credential') x where x->>'integration' = 'zz_meta_probe') then
    raise exception 'CHK<<PROBE FAILED: a founder-credential finding is not read as a channel down>>';
  end if;

  -- 8. a held payer is on a clock with what he was promised; while the switch does not read off, he is owed a status, never "tell"
  if not public.fn_stripe_live_hold_reads_off() then
    insert into public.agent_actions (agent, kind, status, recommendation, detail, target_table, target_id, created_at)
    values ('ceo', 'handoff', 'pending', 'ZZ DEMO tell the held payer when payment opens', jsonb_build_object('type', 'review.requested', 'held_by', 'stripe_live_hold', 'from', 'customer_support', 'decision', 'ZZ DEMO held by the live hold', 'supplier_id', -9002, 'kind', 'registration',
                              'ask', 'ZZ DEMO A real account tried to pay while live Stripe payments are held. Nothing was charged. Tell the person when payment opens.'),
            'leads', 'review.requested:-9002', now() - interval '5 hours')
    returning id into v_id2;
    v := public.fn_held_payers_sync();
    -- no lead -9002 exists, so there is no e-mail: counted, not clocked
    if coalesce((v->>'no_email')::int, 0) < 1 or exists (select 1 from public.escalation_clock where source_table = 'agent_actions' and source_id = v_id2::text) then
      raise exception 'CHK<<PROBE FAILED: a held payer with no e-mail was clocked or not counted: %>>', v;
    end if;
    v := public.fn_escalation_clock_open('agent_actions', v_id2::text, 'held_payment', 'email', v_mail, 'Card payment opens shortly.', null, null,
           jsonb_build_object('audience', 'supplier', 'promised_at', now() - interval '5 hours'));
    if not exists (select 1 from jsonb_array_elements(public.fn_escalation_clocks_due(10)) x where (x->>'id')::bigint = (v->>'id')::bigint and x->>'due_for' = 'status' and x->>'switch_reads_off' = 'false') then
      raise exception 'CHK<<PROBE FAILED: a held payer past his clock is not owed an honest status while the hold is on>>';
    end if;
  end if;

  -- 9. the one-off (run as the main session runs it: the duty-fixture switch off): fixtures left alone; a request with no contact
  --    is adopted onto a clock, moved to the CEO, unreached and recorded
  perform set_config('qd.duty_fixtures', '', true);

  insert into public.decision_review_request (decision_type, owner_seat, channel, requester, request_text, status, founder_notified, created_at)
  values ('person', 'customer_support', 'whatsapp', v_wa, 'ZZ DEMO person please', 'with_founder', '{}'::jsonb, now() - interval '13 days'),
         ('person', 'customer_support', 'site_chat', v_visitor, 'ZZ DEMO a human please', 'with_founder', '{"probe": true}'::jsonb, now() - interval '5 days');
  v := public.fn_escalation_clock_adopts_stale_person_requests(true);
  if (v->>'adopted')::int <> 0 or exists (select 1 from public.decision_review_request where requester = v_visitor and status <> 'with_founder') then
    raise exception 'CHK<<PROBE FAILED: the dry run changed something: %>>', v;
  end if;
  v := public.fn_escalation_clock_adopts_stale_person_requests(false);
  select * into r from public.decision_review_request where requester = v_visitor;
  select * into c from public.escalation_clock where (detail->>'review_request_id')::bigint = r.id;
  if (v->>'fixtures_left_alone')::int < 1 or (v->>'adopted')::int < 1 or r.status <> 'with_ceo' or r.founder_notified is not null
     or r.evidence->'founder_notified_then'->>'probe' <> 'true' or c.id is null or c.attempts <> 1 or c.last_error not like 'no open channel%'
     or c.promised_at > now() - interval '4 days' or c.state <> 'open' then
    raise exception 'CHK<<PROBE FAILED: the one-off did not adopt the stale request as expected: % / % / %>>', v, row_to_json(r), row_to_json(c);
  end if;
  if exists (select 1 from public.decision_review_request where requester = v_wa and status <> 'with_founder') then
    raise exception 'CHK<<PROBE FAILED: the one-off touched a fixture row>>';
  end if;
  if public.fn_escalation_stale_apology('whatsapp', '2026-11-03 10:00+04', '2026-11-17 10:00+04', false) not like 'We are sorry. On 03 Nov 2026 you asked on WhatsApp%by 17 Nov 2026%' then
    raise exception 'CHK<<PROBE FAILED: the apology text is not the reviewed wording: %>>', public.fn_escalation_stale_apology('whatsapp', '2026-11-03 10:00+04', '2026-11-17 10:00+04', false);
  end if;

  -- nothing real moved
  if (select count(*) from public.escalation_clock where requester not in (v_mail, v_wa, v_wa_open, v_visitor)) <> v_real_clocks then
    raise exception 'CHK<<PROBE FAILED: a real clock changed>>';
  end if;
  if (select count(*) from public.decision_review_request where requester not in (v_mail, v_visitor, v_wa)) <> v_real_reviews
     or (select count(*) from public.founder_alerts) <> v_founder_before then
    raise exception 'CHK<<PROBE FAILED: a real review request or a founder alert changed>>';
  end if;
  raise exception 'CHK<<PROBE OK: a person request goes to the CEO with a clock and never pages the founder; the exact promise and a legal reading land on the same clock; the CEO is asked, a founder answer without a law stays the CEO''s, a decision told closes the case once; WhatsApp only in the window, e-mail through the duty send; the case facts carry the open escalation, the founder''s last word and a founder-credential channel down; a held payer is owed a status while the hold is on; the one-off adopts only real requests and leaves fixtures alone>>';
end
$probe$;
