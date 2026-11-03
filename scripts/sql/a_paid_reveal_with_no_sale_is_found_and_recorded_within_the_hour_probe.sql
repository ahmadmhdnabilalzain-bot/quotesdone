-- PROBE for a_paid_reveal_with_no_sale_is_found_and_recorded_within_the_hour.sql (accountant, 3 Nov 2026).
-- Never applied: it always raises CHK<<...>>, so every row it writes is rolled back, the pg_net request included (pg_net
-- sends only after a commit). Run after the file, or concatenated after it in one transaction (the PR rehearsal and
-- apply-on-merge do exactly that): node scripts/ci/rehearse_sql.mjs <file> <this probe>.
--
-- It drives the duty through the real runner (fn_seat_duty_run) and the real record routine with ZZ-probe Stripe ids
-- (in_zzprobe*, pi_zzprobe*) that no real payment carries, and random quote ids no quote has. It proves:
--   1 the duty dispatches one sweep to the accountant runtime, and sends no second one while that is in flight;
--   2 a sweep silent for over 2 hours is a finding, closed by the next report (only when production has no report in
--     the last 3 hours, so a real run is never needed or disturbed);
--   3 a live payment that could not be recorded is a finding; a second payment is a finding for the CEO; a recovered
--     sale, a test-mode payment and an example.invalid payment file NONE;
--   4 the same report again writes no new item and no new finding (attempts count up); a malformed outcome is refused;
--   5 a payment refunded in full resolves its item and closes its finding; a second payment already raised by
--     recordRevealSale (reveal:second_payment:<pi>, #1835) is not filed twice; a live Stripe that could not be read is
--     a finding;
--   6 nothing reached the founder (notifications to admin/founder, founder_alerts).
do $probe$
declare
  n0 bigint := (select count(*) from public.notifications where to_role in ('admin', 'founder'));
  fa0 bigint := (select count(*) from public.founder_alerts);
  items0 bigint := (select count(*) from public.accountant_reveal_reconcile_item);
  q1 uuid := gen_random_uuid(); q2 uuid := gen_random_uuid(); q3 uuid := gen_random_uuid(); q4 uuid := gen_random_uuid(); q5 uuid := gen_random_uuid();
  v_live jsonb := '{"live":{"basis":"measured","invoices":5,"payment_intents":0,"truncated":false},"test":{"basis":"measured","invoices":1,"payment_intents":0,"truncated":false}}';
  v_out jsonb; v_r jsonb := '{}'::jsonb; v_fail text := ''; v_tick jsonb; v_tick2 jsonb; v_run bigint; v_silent_tested boolean;
  open_f bigint;
  k text := 'acct:reveal_reconcile:';
begin
  -- 2 (set-up): a dispatch 150 minutes old that never reported, when production has no recent report of its own.
  v_silent_tested := not exists (select 1 from public.accountant_reveal_reconcile_run where reported_at > now() - interval '3 hours');
  if v_silent_tested then
    insert into public.accountant_reveal_reconcile_run (requested_at, window_days) values (now() - interval '150 minutes', 30);
  end if;

  -- 1. The duty, through the runner.
  v_r := v_r || jsonb_build_object('run', public.fn_seat_duty_run('accountant.reveal_reconcile'));
  v_tick := (select last_result from public.seat_duty where duty = 'accountant.reveal_reconcile');
  if coalesce((v_r->'run'->>'ok')::boolean, false) is not true then v_fail := v_fail || '1:runner_not_ok ' || coalesce(v_r->'run'->>'error', '') || '; '; end if;
  if coalesce((v_tick->>'dispatched')::boolean, false) is not true then v_fail := v_fail || '1:not_dispatched; '; end if;
  v_run := (v_tick->>'run')::bigint;
  if not exists (select 1 from net.http_request_queue q where q.id = (v_tick->>'request')::bigint and q.url like '%/functions/v1/accountant') then
    v_fail := v_fail || '1:no_request_to_accountant; ';
  end if;
  v_tick2 := public.fn_accountant_reveal_reconcile_tick();
  if coalesce((v_tick2->>'dispatched')::boolean, true) then v_fail := v_fail || '1:second_dispatch_in_flight; '; end if;
  if v_silent_tested and not exists (select 1 from public.it_engineer_finding where issue_key = k || 'sweep_silent' and closed_at is null) then
    v_fail := v_fail || '2:silent_not_filed; ';
  end if;

  -- 3. The runtime's report for that dispatch.
  v_out := public.fn_accountant_reveal_reconcile_record(v_run, jsonb_build_object('days', 30, 'modes', v_live, 'checked', 6, 'too_recent', 0,
    'outcomes', jsonb_build_array(
      jsonb_build_object('key', 'in_zzprobefail1', 'mode', 'live', 'livemode', true, 'source', 'invoice', 'quote_id', q1, 'invoice_id', 'in_zzprobefail1',
        'payment_intent', 'pi_zzprobefail1', 'customer_email', 'zz.reconcile.probe@quotesdone.com', 'amount_fils', 30000, 'currency', 'aed',
        'paid_at', extract(epoch from now() - interval '2 hours')::bigint, 'outcome', 'failed', 'error', 'quote not found: probe'),
      jsonb_build_object('key', 'in_zzprobe2nd', 'mode', 'live', 'livemode', true, 'source', 'invoice', 'quote_id', q2, 'invoice_id', 'in_zzprobe2nd',
        'payment_intent', 'pi_zzprobe2nd', 'customer_email', 'zz.reconcile.probe@quotesdone.com', 'amount_fils', 30000, 'currency', 'aed', 'outcome', 'second_payment'),
      jsonb_build_object('key', 'in_zzproberec', 'mode', 'live', 'livemode', true, 'source', 'invoice', 'quote_id', q3, 'invoice_id', 'in_zzproberec',
        'payment_intent', 'pi_zzproberec', 'customer_email', 'zz.reconcile.probe@quotesdone.com', 'amount_fils', 30000, 'outcome', 'recovered'),
      jsonb_build_object('key', 'in_zzprobedemo1', 'mode', 'test', 'livemode', false, 'source', 'invoice', 'quote_id', q4, 'invoice_id', 'in_zzprobedemo1',
        'payment_intent', 'pi_zzprobedemo1', 'customer_email', 'zz.reconcile.probe@quotesdone.com', 'amount_fils', 30000, 'outcome', 'failed', 'error', 'probe'),
      jsonb_build_object('key', 'pi_zzprobedemo2', 'mode', 'live', 'livemode', true, 'source', 'payment_intent', 'quote_id', q5, 'payment_intent', 'pi_zzprobedemo2',
        'customer_email', 'zz-demo-buyer@example.invalid', 'amount_fils', 30000, 'outcome', 'failed', 'error', 'probe'),
      jsonb_build_object('key', 'not a stripe id', 'source', 'invoice', 'quote_id', q1, 'outcome', 'failed'),
      jsonb_build_object('key', 'in_zzprobematch', 'source', 'invoice', 'quote_id', q1, 'outcome', 'recorded'))));
  v_r := v_r || jsonb_build_object('first', v_out - 'findings');
  if (v_out->>'kept')::int <> 5 or (v_out->>'refused')::int <> 2 then v_fail := v_fail || '3:kept_or_refused ' || (v_out - 'findings')::text || '; '; end if;
  if not exists (select 1 from public.it_engineer_finding where issue_key = k || 'failed:in_zzprobefail1' and closed_at is null) then v_fail := v_fail || '3:failed_not_filed; '; end if;
  if not exists (select 1 from public.it_engineer_finding where issue_key = k || 'second_payment:in_zzprobe2nd' and closed_at is null
                   and evidence->>'owner_seat' = 'ceo') then v_fail := v_fail || '3:second_payment_not_filed_for_ceo; '; end if;
  if exists (select 1 from public.it_engineer_finding where issue_key like k || '%zzprobe%' and closed_at is null
               and issue_key in (k || 'failed:in_zzprobedemo1', k || 'failed:pi_zzprobedemo2', k || 'recovered:in_zzproberec')) then
    v_fail := v_fail || '3:demo_or_recovered_filed; ';
  end if;
  if not (select demo from public.accountant_reveal_reconcile_item where key = 'in_zzprobedemo1')
     or not (select demo from public.accountant_reveal_reconcile_item where key = 'pi_zzprobedemo2')
     or (select demo from public.accountant_reveal_reconcile_item where key = 'in_zzprobefail1') then v_fail := v_fail || '3:demo_flag; '; end if;
  if (select resolved_at is null from public.accountant_reveal_reconcile_item where key = 'in_zzproberec') then v_fail := v_fail || '3:recovered_not_resolved; '; end if;
  if v_silent_tested and exists (select 1 from public.it_engineer_finding where issue_key = k || 'sweep_silent' and closed_at is null) then
    v_fail := v_fail || '2:silent_not_closed_by_report; ';
  end if;
  if (select reported_at is null from public.accountant_reveal_reconcile_run where id = v_run) then v_fail := v_fail || '3:run_not_reported; '; end if;

  -- 4. The same report again (as a by-hand call: no run id).
  open_f := (select count(*) from public.it_engineer_finding where issue_key like k || '%' and closed_at is null);
  v_out := public.fn_accountant_reveal_reconcile_record(null, jsonb_build_object('days', 30, 'modes', v_live, 'outcomes', jsonb_build_array(
      jsonb_build_object('key', 'in_zzprobefail1', 'livemode', true, 'source', 'invoice', 'quote_id', q1, 'invoice_id', 'in_zzprobefail1',
        'payment_intent', 'pi_zzprobefail1', 'customer_email', 'zz.reconcile.probe@quotesdone.com', 'amount_fils', 30000, 'outcome', 'failed', 'error', 'quote not found: probe'))));
  if (select count(*) from public.accountant_reveal_reconcile_item) <> items0 + 5 then v_fail := v_fail || '4:item_count; '; end if;
  if (select attempts from public.accountant_reveal_reconcile_item where key = 'in_zzprobefail1') <> 2 then v_fail := v_fail || '4:attempts; '; end if;
  if (select count(*) from public.it_engineer_finding where issue_key like k || '%' and closed_at is null) <> open_f then v_fail := v_fail || '4:findings_changed; '; end if;

  -- 5a. Refunded in full: resolved and closed.
  perform public.fn_accountant_reveal_reconcile_record(null, jsonb_build_object('days', 30, 'modes', v_live, 'outcomes', jsonb_build_array(
      jsonb_build_object('key', 'in_zzprobefail1', 'livemode', true, 'source', 'invoice', 'quote_id', q1, 'invoice_id', 'in_zzprobefail1',
        'payment_intent', 'pi_zzprobefail1', 'outcome', 'refunded'))));
  if (select resolved_at is null from public.accountant_reveal_reconcile_item where key = 'in_zzprobefail1') then v_fail := v_fail || '5:refund_not_resolved; '; end if;
  if exists (select 1 from public.it_engineer_finding where issue_key = k || 'failed:in_zzprobefail1' and closed_at is null) then v_fail := v_fail || '5:refund_finding_open; '; end if;
  -- 5b. recordRevealSale already raised the second payment: not filed twice.
  perform public.fn_it_engineer_finding_upsert('reveal:second_payment:pi_zzprobe2nd', 'ZZ probe: second payment raised by recordRevealSale',
    'probe', 'customer_facing', 1, '{"owner_seat":"ceo"}'::jsonb, '{}'::text[], '{}'::text[], 'accountant');
  perform public.fn_accountant_reveal_reconcile_findings();
  if exists (select 1 from public.it_engineer_finding where issue_key = k || 'second_payment:in_zzprobe2nd' and closed_at is null) then
    v_fail := v_fail || '5:second_payment_filed_twice; ';
  end if;
  -- 5c. Live Stripe unreadable.
  perform public.fn_accountant_reveal_reconcile_record(null, jsonb_build_object('days', 30,
    'modes', '{"live":{"basis":"unreadable","reason":"a Stripe list could not be read"},"test":{"basis":"measured"}}'::jsonb, 'outcomes', '[]'::jsonb));
  if not exists (select 1 from public.it_engineer_finding where issue_key = k || 'stripe_live_unread' and closed_at is null) then v_fail := v_fail || '5:live_unread_not_filed; '; end if;

  -- 6. Nobody was told anything.
  v_r := v_r || jsonb_build_object('silent_tested', v_silent_tested,
    'founder_notifications_added', (select count(*) from public.notifications where to_role in ('admin', 'founder')) - n0,
    'founder_alerts_added', (select count(*) from public.founder_alerts) - fa0);
  if (v_r->>'founder_notifications_added')::int <> 0 or (v_r->>'founder_alerts_added')::int <> 0 then v_fail := v_fail || '6:reached_the_founder; '; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK ' else 'PROBE FAILED: ' || v_fail end || v_r::text;
end $probe$;
