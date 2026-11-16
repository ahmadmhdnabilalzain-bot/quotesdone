-- PROBE: AN UNFINISHED REQUEST CHAT IS KEPT, AND HE IS NUDGED AT A DAY AND AT THREE DAYS.
-- Seat: sales_engineer. Agent: CUSTOMER_W2, 16 Nov 2026. Pure probe: no DDL, never applied. Run after
-- an_unfinished_request_chat_is_kept_and_he_is_nudged_at_a_day_and_three_days.sql on a LOCAL Postgres 16. It always raises, so
-- every row it writes is rolled back. Every party is a ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if
--   1. a draft left 30 hours with 2 questions open gets one English nudge saying "2 questions"; a second run sends nothing;
--   2. a complete draft left 80 hours gets one Arabic nudge saying it is complete (his registered language);
--   3. a draft touched 2 hours ago, one left 10 days ago and one with no message of his get nothing;
--   4. when he comes back and leaves again, the clock starts again: a new nudge;
--   5. a non-demo customer's draft (an unroutable .local address, rolled back) is never nudged by a fixture run.
do $probe$
declare
  fails text := ''; cE uuid := gen_random_uuid(); cA uuid := gen_random_uuid(); cR uuid := gen_random_uuid();
  dA uuid := gen_random_uuid(); dB uuid := gen_random_uuid(); dC uuid := gen_random_uuid(); dD uuid := gen_random_uuid();
  dE uuid := gen_random_uuid(); dR uuid := gen_random_uuid(); v jsonb; n int; t jsonb := '[{"role":"user","text":"ZZ DEMO paint my villa"},{"role":"assistant","text":"Which emirate?"}]';
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  perform set_config('qd.duty_fixtures', 'on', true);
  insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
  values ('delivery.request', 'sales_engineer', 'customer_support', 'probe copy of the production row', 'fn_customer_support_acts_on_handoff', null, false,
          'scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql')
  on conflict (type, from_seat, to_seat) do nothing;
  insert into public.customers (id, full_name, email, locale) values
    (cE, 'ZZ DEMO Nudge English', 'zz-demo-nudge-en@example.invalid', 'en'),
    (cA, 'ZZ DEMO Nudge Arabic', 'zz-demo-nudge-ar@example.invalid', 'ar'),
    (cR, 'Probe Real Person', 'probe-not-demo-cw2@quotesdone-probe.local', 'en');
  insert into public.inquiry_intake (id, customer_id, email, category, status, turns, missing, created_at, updated_at) values
    (dA, cE, 'zz-demo-nudge-en@example.invalid', 'painting', 'needs_info', t, '["emirate","area"]', now() - interval '31 hours', now() - interval '30 hours'),
    (dB, cA, 'zz-demo-nudge-ar@example.invalid', 'plumbing', 'ready', t, '[]', now() - interval '81 hours', now() - interval '80 hours'),
    -- (a draft of his own started later would make dA one he set aside: never nudged; this not-yet-due draft is another fixture's)
    (dC, null, 'zz-demo-nudge-c@example.invalid', 'painting', 'needs_info', t, '["emirate"]', now() - interval '3 hours', now() - interval '2 hours'),
    (dD, cE, 'zz-demo-nudge-en@example.invalid', 'painting', 'needs_info', t, '["emirate"]', now() - interval '11 days', now() - interval '10 days'),
    (dE, cE, 'zz-demo-nudge-en@example.invalid', 'painting', 'needs_info', '[{"role":"assistant","text":"Hi"}]', '["emirate"]', now() - interval '31 hours', now() - interval '30 hours'),
    (dR, cR, 'probe-not-demo-cw2@quotesdone-probe.local', 'painting', 'needs_info', t, '["emirate"]', now() - interval '31 hours', now() - interval '30 hours');

  v := public.fn_sales_engineer_nudges_unfinished_requests(now());
  if (v->>'nudged_24h')::int <> 1 or (v->>'nudged_72h')::int <> 1 then fails := fails || ' [run 1: ' || v::text || ']'; end if;
  select count(*) into n from public.notifications where to_email = 'zz-demo-nudge-en@example.invalid' and type = 'intake_nudge' and body like '%2 questions from going to the right suppliers%';
  if n <> 1 then fails := fails || ' [1: ' || n || ' English nudges with the count]'; end if;
  select count(*) into n from public.notifications where to_email = 'zz-demo-nudge-ar@example.invalid' and type = 'intake_nudge' and lang = 'ar' and body like '%مكتمل وجاهز للإرسال%';
  if n <> 1 then fails := fails || ' [2: ' || n || ' Arabic nudges]'; end if;
  if (select nudged_72h_at from public.inquiry_intake where id = dB) is null then fails := fails || ' [2: not marked]'; end if;
  if exists (select 1 from public.inquiry_intake where id in (dC, dD, dE, dR) and (nudged_24h_at is not null or nudged_72h_at is not null)) then fails := fails || ' [3/5: a draft that is not due was nudged]'; end if;
  if exists (select 1 from public.notifications where to_email = 'probe-not-demo-cw2@quotesdone-probe.local') then fails := fails || ' [5: a real person was written by a fixture run]'; end if;

  v := public.fn_sales_engineer_nudges_unfinished_requests(now());
  if (v->>'nudged_24h')::int <> 0 or (v->>'nudged_72h')::int <> 0 then fails := fails || ' [1: a second run nudged again: ' || v::text || ']'; end if;

  -- 4. the first nudge went 29 hours ago; he came back (a turn) and left again 26 hours ago
  update public.inquiry_intake set nudged_24h_at = now() - interval '29 hours', updated_at = now() - interval '26 hours' where id = dA;
  v := public.fn_sales_engineer_nudges_unfinished_requests(now());
  if (v->>'nudged_24h')::int <> 1 then fails := fails || ' [4: no new nudge after he came back: ' || v::text || ']'; end if;
  -- and 72 hours on from his last word, the second nudge
  v := public.fn_sales_engineer_nudges_unfinished_requests(now() + interval '47 hours');
  if (v->>'nudged_72h')::int <> 1 then fails := fails || ' [4: no 72-hour nudge: ' || v::text || ']'; end if;
  -- 6. he set dA aside and started a new request chat: dA, the draft "Start a new request" left behind, is never nudged again
  update public.inquiry_intake set nudged_24h_at = null, nudged_72h_at = null, updated_at = now() - interval '30 hours' where id = dA;
  insert into public.inquiry_intake (id, customer_id, email, category, status, turns, missing, created_at, updated_at)
  values (gen_random_uuid(), cE, 'zz-demo-nudge-en@example.invalid', 'tiling', 'needs_info', t, '["area"]', now() - interval '1 hour', now() - interval '1 hour');
  v := public.fn_sales_engineer_nudges_unfinished_requests(now());
  if v->'ids' ? dA::text then fails := fails || ' [6: the draft he set aside was nudged: ' || v::text || ']'; end if;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK>>';
end $probe$;
