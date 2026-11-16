-- Probe for an_inbound_burst_is_accepted_at_once_and_read_in_turn.sql (pure probe: it raises its verdict, so everything it wrote
-- is rolled back). It touches only rows it creates in public.inbound_mail_queue (provider ids 'zz-demo-probe-*', addresses on
-- example.invalid, the reserved test identity), the IT finding its own dead letter files and that finding's handoff. Inside one
-- transaction now() does not move, so a lease that ran out, a backoff that passed and an hour between two deaths of one message
-- are written onto its own rows rather than waited for. It runs fn_it_loop_reverify, which walks every pending it.finding
-- handoff, so it refuses a database that has any it did not file. The kick's
-- net.http_post is queued inside the rolled-back transaction and never sent. Run on the LOCAL database only (13 Nov 2026).
--   QD_LOCAL_DB_URL=... node scripts/ci/rehearse_sql.mjs scripts/sql/an_inbound_burst_is_accepted_at_once_and_read_in_turn.sql \
--     scripts/sql/an_inbound_burst_is_accepted_at_once_and_read_in_turn_probe.sql
do $probe$
declare
  v jsonb; v_n int; v_ids bigint[]; v_reads int := 0; v_rounds int := 0; r record; v_q1 bigint; v_q2 bigint; v_q3 bigint;
  v_c bigint; v_p bigint; v_h bigint; v_h2 bigint; v_detail jsonb; v_claim text[]; v_j1 bigint; v_j2 bigint; f record;
  v_key text; v_a timestamptz; v_b timestamptz;
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  if exists (select 1 from public.inbound_mail_queue where status = 'reading') then
    raise exception 'CHK<<PROBE FAILED: a real message is being read; run the probe on the local database>>';
  end if;
  if exists (select 1 from public.agent_actions where kind = 'handoff' and detail->>'type' = 'it.finding' and status in ('pending', 'failed')) then
    raise exception 'CHK<<PROBE FAILED: real it.finding handoffs are open and fn_it_loop_reverify would act on them; run the probe on the local database>>';
  end if;

  -- 1. A burst of 20 receipts is recorded once each; a redelivery is a duplicate and records nothing.
  for i in 1..20 loop
    v := public.fn_inbound_mail_accept('zz-demo-probe-r' || i, 'msg_zz_probe_r' || i, '{"type":"email.received"}',
           'zz-demo-founder@example.invalid', 'expenses@mail.quotesdone.com', 'ZZ DEMO receipt ' || i, null, 'accountant');
    if (v->>'queued')::boolean is not true then raise exception 'CHK<<PROBE FAILED: receipt % not queued: %>>', i, v; end if;
  end loop;
  v := public.fn_inbound_mail_accept('zz-demo-probe-r7', 'msg_zz_probe_r7', '{}', 'x@example.invalid', 'expenses@mail.quotesdone.com', '', null, 'accountant');
  if (v->>'duplicate')::boolean is not true or (v->>'status') <> 'queued' then raise exception 'CHK<<PROBE FAILED: a redelivery was not a duplicate: %>>', v; end if;
  select count(*) into v_n from public.inbound_mail_queue where provider_email_id like 'zz-demo-probe-r%';
  if v_n <> 20 then raise exception 'CHK<<PROBE FAILED: % rows for 20 receipts>>', v_n; end if;
  -- the RFC Message-ID is kept on the row: the Microsoft 365 readers hand one Message-ID once across every mailbox, and a copy
  -- that is only queued (not yet in inbound_messages) must still count as handed
  v := public.fn_inbound_mail_accept('zz-demo-probe-m1', null, '{}', 'zz-tiles@example.invalid', 'supplier@quotesdone.com', 'ZZ DEMO quote',
         null, 'customer_support', '<zz-demo-probe-1@example.invalid>');
  if (select message_id from public.inbound_mail_queue where id = (v->>'id')::bigint) is distinct from '<zz-demo-probe-1@example.invalid>' then
    raise exception 'CHK<<PROBE FAILED: the Message-ID was not kept on the queue row>>';
  end if;
  delete from public.inbound_mail_queue where id = (v->>'id')::bigint;

  -- 2. At most two are read at once: a reader asking for five gets two, a second reader gets none.
  select array_agg(id) into v_ids from public.fn_inbound_mail_claim('zz-probe-w1', 5);
  if coalesce(array_length(v_ids, 1), 0) <> 2 then raise exception 'CHK<<PROBE FAILED: the first claim took % (want 2)>>', coalesce(array_length(v_ids, 1), 0); end if;
  select count(*) into v_n from public.fn_inbound_mail_claim('zz-probe-w2', 5);
  if v_n <> 0 then raise exception 'CHK<<PROBE FAILED: a third message was claimed while two were read>>'; end if;
  for r in select unnest(v_ids) id loop perform public.fn_inbound_mail_finish(r.id, 'zz-probe-w1', true, '{"status":200}'::jsonb, null); v_reads := v_reads + 1; end loop;

  -- 3. Two readers drain the rest: each message is claimed exactly once and ends done.
  loop
    v_rounds := v_rounds + 1; exit when v_rounds > 40;
    select array_agg(id) into v_ids from public.fn_inbound_mail_claim('zz-probe-w' || (v_rounds % 2), 1);
    exit when v_ids is null;
    perform public.fn_inbound_mail_finish(v_ids[1], 'zz-probe-w' || (v_rounds % 2), true, '{"status":200}'::jsonb, null);
    v_reads := v_reads + 1;
  end loop;
  select count(*) into v_n from public.inbound_mail_queue where provider_email_id like 'zz-demo-probe-r%' and status = 'done' and attempts = 1;
  if v_n <> 20 or v_reads <> 20 then raise exception 'CHK<<PROBE FAILED: % done at one attempt, % reads, for 20 receipts>>', v_n, v_reads; end if;

  -- 4. One sender's mail to one mailbox is read in order; another sender is not held behind it.
  v_q1 := (public.fn_inbound_mail_accept('zz-demo-probe-q1', null, '{}', 'zz-tiles@example.invalid', 'supplier@quotesdone.com', 'quote', 'zz-tiles@example.invalid>supplier@quotesdone.com', 'customer_support')->>'id')::bigint;
  v_q2 := (public.fn_inbound_mail_accept('zz-demo-probe-q2', null, '{}', 'zz-tiles@example.invalid', 'supplier@quotesdone.com', 'correction', 'zz-tiles@example.invalid>supplier@quotesdone.com', 'customer_support')->>'id')::bigint;
  v_q3 := (public.fn_inbound_mail_accept('zz-demo-probe-q3', null, '{}', 'zz-paint@example.invalid', 'supplier@quotesdone.com', 'quote', 'zz-paint@example.invalid>supplier@quotesdone.com', 'customer_support')->>'id')::bigint;
  select array_agg(provider_email_id order by id) into v_claim from public.fn_inbound_mail_claim('zz-probe-t', 5);
  if v_claim is distinct from array['zz-demo-probe-q1', 'zz-demo-probe-q3'] then raise exception 'CHK<<PROBE FAILED: thread order: claimed %>>', v_claim; end if;
  perform public.fn_inbound_mail_finish(v_q1, 'zz-probe-t', true, null, null);
  perform public.fn_inbound_mail_finish(v_q3, 'zz-probe-t', true, null, null);
  select array_agg(provider_email_id) into v_claim from public.fn_inbound_mail_claim('zz-probe-t', 5);
  if v_claim is distinct from array['zz-demo-probe-q2'] then raise exception 'CHK<<PROBE FAILED: the correction after the quotation: claimed %>>', v_claim; end if;
  perform public.fn_inbound_mail_finish(v_q2, 'zz-probe-t', true, null, null);

  -- 5. A reader killed mid-message: its lease runs out, the message waits its backoff, is read once more, and the dead reader's
  --    late verdict is refused.
  v_c := (public.fn_inbound_mail_accept('zz-demo-probe-c', 'msg_zz_probe_c', '{}', 'zz-demo-founder@example.invalid', 'expenses@mail.quotesdone.com', 'crash', null, 'accountant')->>'id')::bigint;
  perform public.fn_inbound_mail_claim('zz-probe-killed', 1);
  update public.inbound_mail_queue set lease_until = now() - interval '1 second' where id = v_c;
  select count(*) into v_n from public.fn_inbound_mail_claim('zz-probe-live', 1);
  select * into r from public.inbound_mail_queue where id = v_c;
  if v_n <> 0 or r.status <> 'queued' or r.next_attempt_at not between now() + interval '1 minute' and now() + interval '90 seconds'
     or r.last_error not like '%lease ran out%' then
    raise exception 'CHK<<PROBE FAILED: a dead reader''s message: claimed %, status %, next %, error %>>', v_n, r.status, r.next_attempt_at, r.last_error;
  end if;
  update public.inbound_mail_queue set next_attempt_at = now() - interval '1 second' where id = v_c;
  select count(*) into v_n from public.fn_inbound_mail_claim('zz-probe-live', 1);
  v := public.fn_inbound_mail_finish(v_c, 'zz-probe-killed', false, null, 'late');
  if v_n <> 1 or (v->>'finished')::boolean is not false then raise exception 'CHK<<PROBE FAILED: resume: claimed %, late verdict %>>', v_n, v; end if;
  if public.fn_inbound_mail_touch(v_c, 'zz-probe-killed') or not public.fn_inbound_mail_touch(v_c, 'zz-probe-live') then
    raise exception 'CHK<<PROBE FAILED: only the live reader may renew the lease>>';
  end if;
  v := public.fn_inbound_mail_finish(v_c, 'zz-probe-live', true, '{"status":200}'::jsonb, null);
  select * into r from public.inbound_mail_queue where id = v_c;
  if r.status <> 'done' or r.attempts <> 2 then raise exception 'CHK<<PROBE FAILED: after resume: status %, attempts %>>', r.status, r.attempts; end if;

  -- 5b. Two messages that failed together (one worker the edge killed takes both its readers) do not come back together: each
  --     retry is the backoff stretched by up to half again at random.
  v_j1 := (public.fn_inbound_mail_accept('zz-demo-probe-j1', null, '{}', 'zz-demo-founder@example.invalid', 'expenses@mail.quotesdone.com', 'ZZ DEMO j1', null, 'accountant')->>'id')::bigint;
  v_j2 := (public.fn_inbound_mail_accept('zz-demo-probe-j2', null, '{}', 'zz-demo-founder@example.invalid', 'expenses@mail.quotesdone.com', 'ZZ DEMO j2', null, 'accountant')->>'id')::bigint;
  select count(*) into v_n from public.fn_inbound_mail_claim('zz-probe-j', 2);
  if v_n <> 2 then raise exception 'CHK<<PROBE FAILED: the pair: claimed %>>', v_n; end if;
  perform public.fn_inbound_mail_finish(v_j1, 'zz-probe-j', false, null, 'ZZ DEMO worker killed');
  perform public.fn_inbound_mail_finish(v_j2, 'zz-probe-j', false, null, 'ZZ DEMO worker killed');
  select next_attempt_at into v_a from public.inbound_mail_queue where id = v_j1;
  select next_attempt_at into v_b from public.inbound_mail_queue where id = v_j2;
  if v_a = v_b or v_a not between now() + interval '1 minute' and now() + interval '90 seconds'
     or v_b not between now() + interval '1 minute' and now() + interval '90 seconds' then
    raise exception 'CHK<<PROBE FAILED: two messages that failed together come back at % and % (want two different times in 1-1.5 min)>>', v_a, v_b;
  end if;
  update public.inbound_mail_queue set next_attempt_at = now() - interval '1 second' where id in (v_j1, v_j2);
  for r in select id from public.fn_inbound_mail_claim('zz-probe-j', 2) loop perform public.fn_inbound_mail_finish(r.id, 'zz-probe-j', true, null, null); end loop;
  if (select count(*) from public.inbound_mail_queue where id in (v_j1, v_j2) and status = 'done') <> 2 then
    raise exception 'CHK<<PROBE FAILED: the pair was not read on its second attempt>>';
  end if;

  -- 6. A failure is read again after 1, 5, 15, 60 minutes (each stretched by up to half); the fifth makes the message a dead
  --    letter: an IT finding naming it, and that finding's handoff to the seat that owns the mail.
  v_p := (public.fn_inbound_mail_accept('zz-demo-probe-p', 'msg_zz_probe_p', '{}', 'zz-buyer@example.invalid', 'supplier@quotesdone.com', 'ZZ DEMO poison', 'zz-buyer@example.invalid>supplier@quotesdone.com', 'customer_support')->>'id')::bigint;
  for i in 1..5 loop
    update public.inbound_mail_queue set next_attempt_at = now() - interval '1 second' where id = v_p and status = 'queued';
    select count(*) into v_n from public.fn_inbound_mail_claim('zz-probe-p', 1);
    if v_n <> 1 then raise exception 'CHK<<PROBE FAILED: poison attempt % not claimed>>', i; end if;
    v := public.fn_inbound_mail_finish(v_p, 'zz-probe-p', false, null, 'ZZ DEMO the reader failed');
    if i < 5 and ((v->>'status') <> 'queued' or (select next_attempt_at from public.inbound_mail_queue where id = v_p)
                   not between now() + (array[interval '1 minute', interval '5 minutes', interval '15 minutes', interval '60 minutes'])[i]
                           and now() + 1.5 * (array[interval '1 minute', interval '5 minutes', interval '15 minutes', interval '60 minutes'])[i]) then
      raise exception 'CHK<<PROBE FAILED: attempt % backoff: %>>', i, v;
    end if;
  end loop;
  select * into r from public.inbound_mail_queue where id = v_p;
  if (v->>'status') <> 'dead' or r.status <> 'dead' or r.handoff_id is null or r.last_error not like 'attempt 5: ZZ DEMO the reader failed%' then
    raise exception 'CHK<<PROBE FAILED: poison: %, status %, handoff %, error %>>', v, r.status, r.handoff_id, r.last_error;
  end if;
  v_key := 'inbound_mail_queue:' || v_p; v_h := r.handoff_id;
  select * into f from public.it_engineer_finding where issue_key = v_key;
  if f.issue_key is null or f.closed_at is not null or f.evidence->>'owner_seat' <> 'customer_support'
     or f.evidence->>'provider_email_id' <> 'zz-demo-probe-p' or f.evidence->>'reason' not like '%ZZ DEMO the reader failed%'
     or f.evidence->>'ask' not like '%fn_inbound_mail_requeue(' || v_p || ')%'
     or f.title not like 'An e-mail to supplier@quotesdone.com from example.invalid ("ZZ DEMO poison", received % UTC) could not be read after 5 attempt(s)'
     or f.title like '%zz-buyer%' or f.evidence::text like '%zz-buyer@%' then
    raise exception 'CHK<<PROBE FAILED: the dead letter''s finding (it must name the mailbox, the sender''s domain only, the subject and when it came): %>>', to_jsonb(f);
  end if;
  select detail into v_detail from public.agent_actions where id = v_h and kind = 'handoff' and agent = 'customer_support'
     and detail->>'type' = 'it.finding' and detail->>'from' = 'it_engineer' and detail->>'issue_key' = v_key
     and (detail->>'occurrence_started_at')::timestamptz = f.started_at;
  if v_detail is null then raise exception 'CHK<<PROBE FAILED: the dead letter''s handoff is not the IT loop''s handoff of its finding>>'; end if;
  -- THE IT LOOP KEEPS IT. fn_it_loop_reverify closes an it.finding handoff whose finding is gone or closed; this one's is open.
  -- (Review of 15 Nov 2026: filed as a bare handoff with no finding, it was closed as "the finding is no longer open".)
  -- The first death is moved an hour back first, as an hour would pass before the seat requeues it.
  update public.it_engineer_finding set started_at = started_at - interval '1 hour' where issue_key = v_key;
  update public.agent_actions
     set target_id = 'it.finding:' || v_key || '@' || floor(extract(epoch from f.started_at - interval '1 hour'))::bigint,
         detail = detail || jsonb_build_object('occurrence_started_at', f.started_at - interval '1 hour'),
         created_at = created_at - interval '1 hour'
   where id = v_h;
  select status into r from public.agent_actions where id = v_h;
  perform public.fn_it_loop_reverify();
  if (select status from public.agent_actions where id = v_h) <> r.status
     or (select evidence->>'verified_by' from public.agent_actions where id = v_h) is not null
     or (select closed_at from public.it_engineer_finding where issue_key = v_key) is not null then
    raise exception 'CHK<<PROBE FAILED: the IT loop closed the dead letter''s handoff while the e-mail is still unread: %>>',
      (select to_jsonb(a) from public.agent_actions a where id = v_h);
  end if;
  update public.inbound_mail_queue set next_attempt_at = now() - interval '1 second' where id = v_p;
  select count(*) into v_n from public.fn_inbound_mail_claim('zz-probe-p', 1);
  if v_n <> 0 then raise exception 'CHK<<PROBE FAILED: a dead message was claimed again>>'; end if;

  -- 6b. A requeue reads it again, clears the old handoff and error off the row, and closes the finding, so the IT loop closes the
  --     handoff; a second death files anew (a new occurrence of the finding, a new handoff), and the loop keeps that one too.
  v := public.fn_inbound_mail_requeue(v_p);
  select * into r from public.inbound_mail_queue where id = v_p;
  if (v->>'requeued')::boolean is not true or r.status <> 'queued' or r.handoff_id is not null or r.last_error is not null or r.attempts <> 0 then
    raise exception 'CHK<<PROBE FAILED: requeue: %, status %, handoff %, error %>>', v, r.status, r.handoff_id, r.last_error;
  end if;
  if (select closed_at from public.it_engineer_finding where issue_key = v_key) is null then
    raise exception 'CHK<<PROBE FAILED: the requeue left the dead letter''s finding open>>';
  end if;
  perform public.fn_it_loop_reverify();
  if not exists (select 1 from public.agent_actions where id = v_h and (status = 'done' or detail ? 'awaiting_learning')) then
    raise exception 'CHK<<PROBE FAILED: after the requeue the IT loop did not treat the handoff as cleared: %>>',
      (select to_jsonb(a) from public.agent_actions a where id = v_h);
  end if;
  for i in 1..5 loop
    update public.inbound_mail_queue set next_attempt_at = now() - interval '1 second' where id = v_p and status = 'queued';
    select count(*) into v_n from public.fn_inbound_mail_claim('zz-probe-p', 1);
    if v_n <> 1 then raise exception 'CHK<<PROBE FAILED: second round, attempt % not claimed>>', i; end if;
    v := public.fn_inbound_mail_finish(v_p, 'zz-probe-p', false, null, 'ZZ DEMO it failed again');
  end loop;
  select * into r from public.inbound_mail_queue where id = v_p;
  v_h2 := r.handoff_id;
  if r.status <> 'dead' or v_h2 is null or v_h2 = v_h or r.last_error not like 'attempt 5: ZZ DEMO it failed again%'
     or (select closed_at from public.it_engineer_finding where issue_key = v_key) is not null
     or not exists (select 1 from public.agent_actions where id = v_h2 and agent = 'customer_support' and status in ('pending', 'failed')
                     and detail->>'issue_key' = v_key) then
    raise exception 'CHK<<PROBE FAILED: a second death after a requeue: status %, handoff % (first %), error %>>', r.status, v_h2, v_h, r.last_error;
  end if;
  perform public.fn_it_loop_reverify();
  if (select status from public.agent_actions where id = v_h2) not in ('pending', 'failed')
     or (select evidence->>'verified_by' from public.agent_actions where id = v_h2) is not null then
    raise exception 'CHK<<PROBE FAILED: the IT loop closed the second dead letter''s handoff>>';
  end if;
  -- a successful read closes it as well
  perform public.fn_inbound_mail_requeue(v_p);
  perform public.fn_it_engineer_finding_upsert(v_key, 'ZZ DEMO reopened by hand', 'probe', 'agent_facing', 1, '{"owner_seat":"customer_support"}'::jsonb);
  select count(*) into v_n from public.fn_inbound_mail_claim('zz-probe-p', 1);
  v := public.fn_inbound_mail_finish(v_p, 'zz-probe-p', true, '{"status":200}'::jsonb, null);
  if v_n <> 1 or (v->>'status') <> 'done' or (select closed_at from public.it_engineer_finding where issue_key = v_key) is null then
    raise exception 'CHK<<PROBE FAILED: a successful read left the finding open: %>>', v;
  end if;
  -- the requeue in 7 below has a dead message to read again
  perform public.fn_inbound_mail_dead_letter(v_p, 'ZZ DEMO dead once more');
  v := public.fn_inbound_mail_requeue(v_p);
  if (v->>'requeued')::boolean is not true then raise exception 'CHK<<PROBE FAILED: requeue: %>>', v; end if;

  -- 7. The kick starts one reader per due message a free slot can take (the requeued one: one request).
  v := public.fn_inbound_mail_kick();
  if (v->>'due')::int < 1 or (v->>'kicked')::int not between 1 and public.fn_inbound_mail_readers() then
    raise exception 'CHK<<PROBE FAILED: the kick: %>>', v;
  end if;

  raise exception 'CHK<<PROBE OK: 20 of a burst recorded once and read once two at a time, a thread kept its order, a killed reader''s message resumed, two that failed together came back apart, a poison message went to customer_support after 5 attempts as an IT finding the loop kept open until a requeue, a second death filed anew, the kick started %>>', v->>'kicked';
end $probe$;
