-- PROBE for a_request_the_it_digest_holds_or_has_decided_is_never_an_unconfirmed_delivery.sql (it_engineer L3_IT, 16 Nov 2026,
-- ledger 1557). Pure probe: always raises CHK<<...>>, rolling back its three founder-bound ZZ DEMO delivery requests, the digest
-- marker and every finding fn_it_duties settles. Nothing is sent: the requests are rows only and fn_it_duties sends nothing.
-- LOCAL Postgres 16 only. Before the file: "a request the digest decided is called unconfirmed".
do $p$
declare v_fail text := ''; h_dec bigint; h_wait bigint; h_lost bigint; h_sent bigint; h_old bigint; v_at timestamptz; v_open text[];
  c constant jsonb := '{"type": "delivery.request", "from": "ceo", "recipient_role": "founder", "kind": "it_new_bug"}';
begin
  insert into public.agent_actions (agent, kind, title, status, detail, evidence, created_at, decided_at, target_table, target_id)
  values ('customer_support', 'handoff', 'ZZ DEMO probe decided', 'done', c || '{"dedupe_key": "it_new_bug:duty:zzprobe:a"}',
          '{"digest": "fixed", "not_cited": {"reason": "probe", "by": "probe"}}', now() - interval '5 hours', now() - interval '4 hours',
          'founder', 'zzprobe-a') returning id into h_dec;
  -- a request whose hold ended less than a day ago while no digest has run (the hold depends on the Dubai clock: found, not assumed)
  select now() - make_interval(hours => h) into v_at from generate_series(24, 96) h
   where now() > public.fn_it_digest_hold_ends(now() - make_interval(hours => h))
     and now() < public.fn_it_digest_hold_ends(now() - make_interval(hours => h)) + interval '1 day' - interval '5 minutes'
   order by h limit 1;
  insert into public.agent_actions (agent, kind, title, status, detail, evidence, created_at, target_table, target_id)
  values ('customer_support', 'handoff', 'ZZ DEMO probe waiting', 'pending', c || '{"dedupe_key": "it_new_bug:duty:zzprobe:b"}',
          '{"digest": "pending"}', v_at, 'founder', 'zzprobe-b') returning id into h_wait;
  -- (review 16 Nov) the two losses production flags must stay flagged: a request the digest SENT whose delivery never confirmed,
  -- and one still waiting 6 days on, when no digest ever ran
  insert into public.agent_actions (agent, kind, title, status, detail, evidence, created_at, decided_at, target_table, target_id)
  values ('customer_support', 'handoff', 'ZZ DEMO probe sent', 'done', c || '{"dedupe_key": "it_new_bug:duty:zzprobe:d"}',
          '{"digest": "sent", "not_cited": {"reason": "probe", "by": "probe"}}', now() - interval '5 hours', now() - interval '4 hours',
          'founder', 'zzprobe-d') returning id into h_sent;
  insert into public.agent_actions (agent, kind, title, status, detail, evidence, created_at, target_table, target_id)
  values ('customer_support', 'handoff', 'ZZ DEMO probe six days', 'pending', c || '{"dedupe_key": "it_new_bug:duty:zzprobe:e"}',
          '{"digest": "pending"}', now() - interval '6 days', 'founder', 'zzprobe-e') returning id into h_old;
  -- the control: a request with no loop, no result and no digest decision is still a lost delivery (a true alarm kept)
  insert into public.agent_actions (agent, kind, title, status, detail, evidence, created_at, decided_at, target_table, target_id)
  values ('customer_support', 'handoff', 'ZZ DEMO probe lost', 'done', c || '{"dedupe_key": "it_new_bug:duty:zzprobe:c"}',
          '{"not_cited": {"reason": "probe", "by": "probe"}}', now() - interval '5 hours', now() - interval '4 hours',
          'founder', 'zzprobe-c') returning id into h_lost;
  -- the title filter skips 'ZZ DEMO' titles; the detector reads the title, so the probe's rows carry a plain one
  update public.agent_actions set title = 'probe delivery request' where id in (h_dec, h_wait, h_lost, h_sent, h_old);
  delete from public.founder_alerts where dedupe_key like 'it\_daily\_digest:%';
  perform public.fn_it_duties('{}'::jsonb);
  select array_agg(issue_key) into v_open from public.it_engineer_finding where closed_at is null and issue_key like 'duty:delivery:request:%';
  if 'duty:delivery:request:' || h_dec = any(coalesce(v_open, '{}')) then v_fail := v_fail || 'a request the digest decided is called unconfirmed; '; end if;
  if 'duty:delivery:request:' || h_wait = any(coalesce(v_open, '{}')) then v_fail := v_fail || 'a request waiting for a digest that has not run is called unconfirmed; '; end if;
  if not ('duty:delivery:request:' || h_lost = any(coalesce(v_open, '{}'))) then v_fail := v_fail || 'a really unconfirmed request is no longer flagged; '; end if;
  if v_at is null then v_fail := v_fail || 'no creation time puts a hold less than a day in the past; '; end if;
  if not ('duty:delivery:request:' || h_sent = any(coalesce(v_open, '{}'))) then v_fail := v_fail || 'a digest-sent request that never confirmed is not flagged; '; end if;
  if not ('duty:delivery:request:' || h_old = any(coalesce(v_open, '{}'))) then v_fail := v_fail || 'a request waiting 6 days with no digest is not flagged; '; end if;
  -- the digest has run since the hold ended and did not take it: now it is late
  insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
  values ('info', 'ZZ DEMO probe digest', 'probe', 'os', 'it_daily_digest:' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD'));
  perform public.fn_it_duties('{}'::jsonb);
  if not exists (select 1 from public.it_engineer_finding where closed_at is null and issue_key = 'duty:delivery:request:' || h_wait) then
    v_fail := v_fail || 'a request the digest ran past is not flagged; '; end if;
  if v_fail <> '' then raise exception 'CHK<<PROBE FAILED: %>>', v_fail; end if;
  raise exception 'CHK<<PROBE OK: decided and waiting requests not flagged; lost, digest-sent-unconfirmed, 6-days-waiting and digest-ran-past ones are>>';
end $p$;
