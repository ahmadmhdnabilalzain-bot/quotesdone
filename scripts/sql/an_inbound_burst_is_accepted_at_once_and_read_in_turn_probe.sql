-- Probe for an_inbound_burst_is_accepted_at_once_and_read_in_turn.sql (pure probe: it raises its verdict, so everything it wrote
-- is rolled back). It touches only rows it creates in public.inbound_mail_queue (provider ids 'zz-demo-probe-*', addresses on
-- example.invalid, the reserved test identity) and the handoff its own dead letter files. Inside one transaction now() does not
-- move, so a lease that ran out and a backoff that passed are written onto its own rows rather than waited for. The kick's
-- net.http_post is queued inside the rolled-back transaction and never sent. Run on the LOCAL database only (13 Nov 2026).
--   QD_LOCAL_DB_URL=... node scripts/ci/rehearse_sql.mjs scripts/sql/an_inbound_burst_is_accepted_at_once_and_read_in_turn.sql \
--     scripts/sql/an_inbound_burst_is_accepted_at_once_and_read_in_turn_probe.sql
do $probe$
declare
  v jsonb; v_n int; v_ids bigint[]; v_reads int := 0; v_rounds int := 0; r record; v_q1 bigint; v_q2 bigint; v_q3 bigint;
  v_c bigint; v_p bigint; v_h bigint; v_detail jsonb; v_claim text[];
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  if exists (select 1 from public.inbound_mail_queue where status = 'reading') then
    raise exception 'CHK<<PROBE FAILED: a real message is being read; run the probe on the local database>>';
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
  if v_n <> 0 or r.status <> 'queued' or r.next_attempt_at <> now() + interval '1 minute' or r.last_error not like '%lease ran out%' then
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

  -- 6. A failure is read again after 1, 5, 15, 60 minutes; the fifth hands the message to its seat with the reason.
  v_p := (public.fn_inbound_mail_accept('zz-demo-probe-p', 'msg_zz_probe_p', '{}', 'zz-buyer@example.invalid', 'supplier@quotesdone.com', 'ZZ DEMO poison', 'zz-buyer@example.invalid>supplier@quotesdone.com', 'customer_support')->>'id')::bigint;
  for i in 1..5 loop
    update public.inbound_mail_queue set next_attempt_at = now() - interval '1 second' where id = v_p and status = 'queued';
    select count(*) into v_n from public.fn_inbound_mail_claim('zz-probe-p', 1);
    if v_n <> 1 then raise exception 'CHK<<PROBE FAILED: poison attempt % not claimed>>', i; end if;
    v := public.fn_inbound_mail_finish(v_p, 'zz-probe-p', false, null, 'ZZ DEMO the reader failed');
    if i < 5 and ((v->>'status') <> 'queued' or (select next_attempt_at from public.inbound_mail_queue where id = v_p)
                   <> now() + (array[interval '1 minute', interval '5 minutes', interval '15 minutes', interval '60 minutes'])[i]) then
      raise exception 'CHK<<PROBE FAILED: attempt % backoff: %>>', i, v;
    end if;
  end loop;
  select * into r from public.inbound_mail_queue where id = v_p;
  if (v->>'status') <> 'dead' or r.status <> 'dead' or r.handoff_id is null or r.last_error not like 'attempt 5: ZZ DEMO the reader failed%' then
    raise exception 'CHK<<PROBE FAILED: poison: %, status %, handoff %, error %>>', v, r.status, r.handoff_id, r.last_error;
  end if;
  select detail into v_detail from public.agent_actions where id = r.handoff_id and kind = 'handoff' and agent = 'customer_support'
     and target_id = 'it.finding:' || v_p;
  if v_detail is null or v_detail->>'duty' <> 'inbound_mail_dead_letter' or v_detail->>'provider_email_id' <> 'zz-demo-probe-p'
     or v_detail->>'reason' not like '%ZZ DEMO the reader failed%' or v_detail->>'ask' not like '%fn_inbound_mail_requeue(' || v_p || ')%' then
    raise exception 'CHK<<PROBE FAILED: the dead letter''s handoff: %>>', v_detail;
  end if;
  update public.inbound_mail_queue set next_attempt_at = now() - interval '1 second' where id = v_p;
  select count(*) into v_n from public.fn_inbound_mail_claim('zz-probe-p', 1);
  if v_n <> 0 then raise exception 'CHK<<PROBE FAILED: a dead message was claimed again>>'; end if;
  v := public.fn_inbound_mail_requeue(v_p);
  if (v->>'requeued')::boolean is not true or (select status from public.inbound_mail_queue where id = v_p) <> 'queued' then
    raise exception 'CHK<<PROBE FAILED: requeue: %>>', v;
  end if;

  -- 7. The kick starts one reader per due message a free slot can take (the requeued one: one request).
  v := public.fn_inbound_mail_kick();
  if (v->>'due')::int < 1 or (v->>'kicked')::int not between 1 and public.fn_inbound_mail_readers() then
    raise exception 'CHK<<PROBE FAILED: the kick: %>>', v;
  end if;

  raise exception 'CHK<<PROBE OK: 20 of a burst recorded once and read once two at a time, a thread kept its order, a killed reader''s message resumed, a poison message went to customer_support after 5 attempts, the kick started %>>', v->>'kicked';
end $probe$;
