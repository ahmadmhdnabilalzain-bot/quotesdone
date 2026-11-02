-- PROBE for an_inbox_placement_verdict_is_good_for_30_days.sql (sales_engineer, 2 Nov 2026).
-- Pure: no DDL. Run after the file above (or after it in the SAME request through scripts/lib/safe_replay.mjs replaySql, which
-- scripts/checks/an_inbox_placement_verdict_is_good_for_30_days.test.mjs does), inside one transaction that ends in
-- raise exception 'CHK<<verdict|evidence>>', so nothing commits and the verdict is the first thing in the exception.
--
-- It CANNOT reach a person: it writes no notification and calls no sender. It reads the verdicts through
-- fn_invite_placement_class_verdicts (side-effect free) and never through the judge, the gate or open_providers, which file
-- a finding on an open day; "open" below is the set of classes whose verdict is 'pass', as the judge computes it. The only rows it writes are one GlockApps
-- verdict (ZZ DEMO test id, tested in 2031 so no real test can sit after it) and its provider rows, all uncommitted. It
-- never writes app_secrets: the three campaign switches are READ before and after and must be equal.
--
-- It records a verdict shaped like the real 27 Oct one (Outlook 0/18 inbox, Gmail 5 inbox + 20 Promotions of 25 and
-- 0 spam, Yahoo 0/17 inbox) and asserts: the bar row is one row with max_age 30 days and the other bars as they were;
-- one day after the test Google passes and Microsoft, Yahoo/AOL and other are below the bar; ONE MINUTE PAST THE OLD
-- 7-DAY DATE Google is still open and the others are still below the bar (not merely stale); Google is still open
-- 29 days 23 hours after; 30 days 1 minute after every class is stale and nothing is open.
do $$ declare
  o jsonb := '{}'; v_fail text[] := '{}';
  t1 timestamptz := '2031-01-06T09:00:00Z';
  fx text := '{"projectId":"163001","finished":true,"sender":{"senderDomain":"quotesdone.com"},"providerRollup":['
          || '{"providerGroupName":"Outlook","total":18,"inbox":0,"spam":18,"other":0,"notDelivered":0},'
          || '{"providerGroupName":"Gmail (6 months+)","total":25,"inbox":5,"spam":0,"other":20,"notDelivered":0},'
          || '{"providerGroupName":"Yahoo","total":17,"inbox":0,"spam":17,"other":0,"notDelivered":0}]}';
  b public.invite_placement_bar; v jsonb; r jsonb; open_old jsonb; open_edge jsonb; open_end jsonb;
  v_sw_before jsonb; v_sw_after jsonb; n_mail_before bigint; n_mail_after bigint;
begin
  select coalesce(jsonb_object_agg(key, value), '{}') into v_sw_before from app_secrets
   where key in ('invite_enabled', 'supplier_outreach_golive', 'wa_supplier_invite_golive');
  select count(*) into n_mail_before from notifications;

  -- 1. the bar: one row, 30 days, the reason written, every other bar as it was
  select * into b from public.invite_placement_bar where id;
  o := o || jsonb_build_object('bar_rows', (select count(*) from public.invite_placement_bar), 'max_age', b.max_age::text,
    'bars', jsonb_build_array(b.sender, b.microsoft_min_inbox_pct, b.google_max_spam_pct, b.google_min_delivered_pct, b.yahoo_aol_min_inbox_pct));
  if (select count(*) from public.invite_placement_bar) <> 1 then v_fail := v_fail || text 'the bar is not one row'; end if;
  if b.max_age is distinct from interval '30 days' then v_fail := v_fail || text 'max_age is not 30 days'; end if;
  if position('2 Nov 2026, sales_engineer: a verdict is good for 30 days' in b.note) = 0
     or position('Microsoft >= 80% inbox: the founder, ledger 1312' in b.note) = 0 then
    v_fail := v_fail || text 'the reason is not appended to the original note'; end if;
  if (select count(*) from regexp_matches(b.note, '2 Nov 2026, sales_engineer: a verdict is good for 30 days', 'g')) <> 1 then
    v_fail := v_fail || text 'the reason is in the note more than once'; end if;
  if b.sender <> 'supplier@quotesdone.com' or b.microsoft_min_inbox_pct <> 80 or b.google_max_spam_pct <> 20
     or b.google_min_delivered_pct <> 80 or b.yahoo_aol_min_inbox_pct <> 80 then
    v_fail := v_fail || text 'another bar moved'; end if;

  -- 2. a verdict shaped like the real 27 Oct one, tested later than any real test
  r := public.fn_record_inbox_placement_verdict((fx)::jsonb || jsonb_build_object('testId', 'zz-demo-probe-30-day-window', 'created', t1),
                                                'supplier@quotesdone.com', 'it_engineer');
  if r ->> 'recorded' is distinct from 'true' then v_fail := v_fail || text 'the probe verdict was not recorded'; end if;

  -- 3. one day after: Google open, the rest below the bar
  v := public.fn_invite_placement_class_verdicts(t1 + interval '1 day');
  o := o || jsonb_build_object('day_1', v - 'bar_sender' - 'effective_sender' - 'max_age' - 'checked_at' - 'tested_at' - 'test_id');
  if v ->> 'google' <> 'pass' or v ->> 'microsoft' <> 'fail:below_bar:microsoft' or v ->> 'yahoo_aol' <> 'fail:below_bar:yahoo_aol'
     or v ->> 'other' <> 'fail:below_bar:microsoft' or v ->> 'strict' <> 'fail:below_bar:microsoft' then
    v_fail := v_fail || text 'day 1: google is not open, or another class is'; end if;

  -- 4. one minute past the OLD 7-day date: Google still open; the others closed on the bar, not on age
  v := public.fn_invite_placement_class_verdicts(t1 + interval '7 days 1 minute');
  open_old := (select coalesce(jsonb_agg(c order by c), '[]'::jsonb) from unnest(array['google', 'microsoft', 'other', 'yahoo_aol']) c where v ->> c = 'pass');
  o := o || jsonb_build_object('past_7_days', v - 'bar_sender' - 'effective_sender' - 'max_age' - 'checked_at' - 'tested_at' - 'test_id',
                               'past_7_days_open', open_old);
  if v ->> 'google' <> 'pass' or v ->> 'microsoft' <> 'fail:below_bar:microsoft' or v ->> 'yahoo_aol' <> 'fail:below_bar:yahoo_aol'
     or v ->> 'other' <> 'fail:below_bar:microsoft' or open_old <> '["google"]'::jsonb then
    v_fail := v_fail || text 'past the old 7-day date google is not open, or microsoft, yahoo_aol or other opened'; end if;

  -- 5. 29 days 23 hours: still open
  v := public.fn_invite_placement_class_verdicts(t1 + interval '29 days 23 hours');
  open_edge := (select coalesce(jsonb_agg(c order by c), '[]'::jsonb) from unnest(array['google', 'microsoft', 'other', 'yahoo_aol']) c where v ->> c = 'pass');
  o := o || jsonb_build_object('day_29_23h', v ->> 'google', 'day_29_23h_open', open_edge);
  if v ->> 'google' <> 'pass' or v ->> 'microsoft' <> 'fail:below_bar:microsoft' or v ->> 'yahoo_aol' <> 'fail:below_bar:yahoo_aol'
     or v ->> 'other' <> 'fail:below_bar:microsoft' or open_edge <> '["google"]'::jsonb then
    v_fail := v_fail || text 'inside the 30 days google closed, or another class opened'; end if;

  -- 6. past 30 days: every class stale, nothing open
  v := public.fn_invite_placement_class_verdicts(t1 + interval '30 days 1 minute');
  open_end := (select coalesce(jsonb_agg(c order by c), '[]'::jsonb) from unnest(array['google', 'microsoft', 'other', 'yahoo_aol']) c where v ->> c = 'pass');
  o := o || jsonb_build_object('day_30_1m', v - 'bar_sender' - 'effective_sender' - 'max_age' - 'checked_at' - 'tested_at' - 'test_id',
                               'day_30_1m_open', open_end);
  if v ->> 'google' <> 'fail:stale_verdict' or v ->> 'microsoft' <> 'fail:stale_verdict' or v ->> 'yahoo_aol' <> 'fail:stale_verdict'
     or v ->> 'other' <> 'fail:stale_verdict' or v ->> 'strict' <> 'fail:stale_verdict' or open_end <> '[]'::jsonb then
    v_fail := v_fail || text 'a 30-day-old verdict is not stale for every class'; end if;

  -- 7. nothing moved: no switch, no mail
  select coalesce(jsonb_object_agg(key, value), '{}') into v_sw_after from app_secrets
   where key in ('invite_enabled', 'supplier_outreach_golive', 'wa_supplier_invite_golive');
  select count(*) into n_mail_after from notifications;
  o := o || jsonb_build_object('switches', v_sw_after, 'mail_written', n_mail_after - n_mail_before);
  if v_sw_before is distinct from v_sw_after then v_fail := v_fail || text 'a campaign switch moved'; end if;
  if n_mail_after <> n_mail_before then v_fail := v_fail || text 'the probe wrote mail'; end if;

  -- The management API returns about 2,000 characters of an error, so a passing run raises the short form; a failing
  -- run raises everything it measured, the verdict first.
  raise exception 'CHK<<%|%>>',
    case when cardinality(v_fail) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_fail, '; ') end,
    case when cardinality(v_fail) > 0 then o::text
      else format('max_age %s, one bar row, bars %s; google open at day 1, past day 7, at day 29 23h; microsoft, yahoo_aol, other below the bar throughout; every class stale at day 30 1 min; no switch or mail moved',
                  o ->> 'max_age', o ->> 'bars') end;
end $$;
