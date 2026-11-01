-- PROBE for the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.sql (it_engineer, 27 Oct 2026).
-- Pure: no DDL. Run after no_test_mail_goes_to_the_founders_own_inboxes.sql and the file above in the SAME request
-- (scripts/checks/the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.test.mjs does), inside one
-- transaction that ends in raise exception 'CHK<<verdict|evidence>>', so nothing commits. The verdict is the first
-- thing in the exception.
--
-- It CANNOT reach a person: it writes no notification, calls no sender, and every row it writes (two verdict tables)
-- is uncommitted. It NEVER writes app_secrets: invite_enabled, supplier_outreach_golive and wa_supplier_invite_golive
-- are READ before and after and must be equal. Every gate question is asked on a UAE weekend (t1 below), where the judge
-- files and closes nothing whether the campaign is held or open, so the open-day branch (one finding a day) is proved
-- from the code by the check, not by switching anything on here.
--
-- It asserts: a recipient's class from its MX host; no verdict before any test; the REAL 27 Oct GlockApps numbers
-- (scripts/checks/glockapps_27_oct_providers.fixture.json, inlined below) give Microsoft 0/18, Google 5 inbox + 20 tabs
-- of 25, Yahoo/AOL 0/17, overall 44/111 (GlockApps' own figure; its provider rows cover 106, so 5 are unclassified), so Google passes and Microsoft, Yahoo/AOL and other are skipped; the verdict
-- goes stale after 7 days; the bar holds exactly at 80% / 20% on counts; lost Gmail mail cannot pass on a low spam
-- figure; a bad result is refused; the candidate filter returns only the asked class and the one-argument picker is
-- unchanged; the held campaign files no finding; the new routines and tables are closed to anon and authenticated.
do $$ declare
  o jsonb := '{}'; v_fail text[] := '{}';
  v_real jsonb := $glockapps${"testId":"2026-10-27-09:33:53:634t","projectId":"163001","finished":false,"created":"2026-10-27T09:33:53.632Z","seedAccountsTotal":112,"trackedSeeds":111,"stats":{"inbox":44,"other":21,"spam":41,"notDelivered":5,"inboxRate":39.6,"spamRate":36.9,"otherRate":18.9,"notDeliveredRate":4.6,"inboxAndOtherRates":58.6},"authSummary":{"spf":"pass","dkim":"pass","dmarc":"pass"},"sender":{"senderIp":"40.107.54.87","senderDomain":"quotesdone.com","rdns":"mail-uaenorthazon11021087.outbound.protection.outlook.com","isp":"outlook.com"},"providerRollup":[{"providerGroupId":"5","providerGroupName":"Gmail (6 months+)","total":17,"inbox":0,"spam":0,"other":17,"notDelivered":0,"tabs":["Promotions"]},{"providerGroupId":"4","providerGroupName":"Yahoo","total":9,"inbox":0,"spam":9,"other":0,"notDelivered":0},{"providerGroupId":"2","providerGroupName":"AOL","total":8,"inbox":0,"spam":8,"other":0,"notDelivered":0},{"providerGroupId":"3","providerGroupName":"Outlook","total":8,"inbox":0,"spam":8,"other":0,"notDelivered":0},{"providerGroupId":"6","providerGroupName":"Hotmail","total":6,"inbox":0,"spam":6,"other":0,"notDelivered":0},{"providerGroupId":"59","providerGroupName":"Gmail (4 years+)","total":3,"inbox":0,"spam":0,"other":3,"notDelivered":0,"tabs":["Promotions"]},{"providerGroupId":"34","providerGroupName":"Interia.pl","total":3,"inbox":0,"spam":0,"other":0,"notDelivered":3},{"providerGroupId":"45","providerGroupName":"att.net","total":2,"inbox":0,"spam":2,"other":0,"notDelivered":0},{"providerGroupId":"17","providerGroupName":"Exchange (Office365)","total":2,"inbox":0,"spam":2,"other":0,"notDelivered":0},{"providerGroupId":"33","providerGroupName":"Onet.pl","total":2,"inbox":0,"spam":0,"other":0,"notDelivered":2},{"providerGroupId":"15","providerGroupName":"Yandex.ru","total":2,"inbox":0,"spam":2,"other":0,"notDelivered":0},{"providerGroupId":"61","providerGroupName":"Outlook.fr","total":1,"inbox":0,"spam":1,"other":0,"notDelivered":0},{"providerGroupId":"62","providerGroupName":"Outlook.de","total":1,"inbox":0,"spam":1,"other":0,"notDelivered":0},{"providerGroupId":"11","providerGroupName":"Zoho","total":2,"inbox":1,"spam":0,"other":1,"notDelivered":0,"tabs":["Newsletter"]},{"providerGroupId":"8","providerGroupName":"Web.de","total":5,"inbox":5,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"52","providerGroupName":"mailo.com","total":3,"inbox":3,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"42","providerGroupName":"Google Workspace (4 years+)","total":3,"inbox":3,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"56","providerGroupName":"gmx.de","total":3,"inbox":3,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"9","providerGroupName":"Freenet.de","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"24","providerGroupName":"Seznam.cz","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"63","providerGroupName":"Google Workspace (Up to 6 months)","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"57","providerGroupName":"gmx.com","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"53","providerGroupName":"ukr.net","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"14","providerGroupName":"Mail.ru","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"20","providerGroupName":"Virgilio.it","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"30","providerGroupName":"Amazon WorkMail","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"25","providerGroupName":"Laposte.net (FR)","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"19","providerGroupName":"Libero.it","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"7","providerGroupName":"Apple","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"51","providerGroupName":"rambler.ru","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"66","providerGroupName":"vodafonemail.de","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"44","providerGroupName":"T-online.de","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"48","providerGroupName":"naver.com","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"13","providerGroupName":"Mail.com","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"60","providerGroupName":"Protonmail","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0}]}$glockapps$::jsonb;
  -- 28 Oct 2026 (it_engineer, ledger 1406): the clock starts just after the newest test production holds, and the
  -- real 27 Oct numbers are recorded at that moment (step 3), so every question below is answered by this probe's own
  -- tests. It used to start at that test's own time, 27 Oct 09:33Z; once the 22:50Z test was recorded (28 Oct 03:51Z)
  -- the newer real verdict answered for the fixture: "stale after 7 days" read a 6-day-old real test and failed, and
  -- "judged per class" judged the 22:50 test, not these numbers.
  t0 timestamptz := greatest(timestamptz '2026-10-27T09:33:53.632Z', (select max(d.tested_at) from public.deliverability_test d)) + interval '1 minute';
  v_sw_before jsonb; v_sw_after jsonb; n_mail_before bigint; n_mail_after bigint; n_find_before bigint; n_find_after bigint;
  r jsonb; v jsonb; a text[]; v_ok boolean; n bigint; m bigint; v_ids1 bigint[]; v_ids2 bigint[];
  t1 timestamptz; v_plan json;
  fx text := '{"projectId":"163001","finished":true,"sender":{"senderDomain":"quotesdone.com"},"providerRollup":[';
begin
  -- The gate's own forms run through the judge, which on an OPEN day files the day's one finding: asked on 29 Oct, a day
  -- the live judge had not filed yet, the probe wrote two notification rows inside its rolled-back transaction (28 Oct
  -- 2026). So every question through the judge is asked at t1, the first Saturday 12:00 Dubai after t0:
  -- fn_invite_placement_day_closed answers 'the UAE weekend', the judge files and closes nothing, and the fixture is
  -- under 7 days old there.
  t1 := (date_trunc('week', t0 at time zone 'Asia/Dubai') + interval '5 days 12 hours') at time zone 'Asia/Dubai';
  if t1 <= t0 then t1 := t1 + interval '7 days'; end if;

  -- 0. what must not move (read only)
  select coalesce(jsonb_object_agg(key, value), '{}') into v_sw_before from app_secrets
   where key in ('invite_enabled', 'supplier_outreach_golive', 'wa_supplier_invite_golive');
  -- 1 Nov 2026 (it_engineer): only rows THIS transaction writes. A whole-table count read another session's live
  -- inserts as the probe's (two suppressed supplier_approved rows every ~20 s): now() is this transaction's start,
  -- the column's default, and xmin catches a writer that sets created_at itself.
  select count(*) into n_mail_before from notifications where created_at = now() or xmin::text = (pg_current_xact_id()::text::bigint % 4294967296)::text;
  select count(*) into n_find_before from it_engineer_finding where issue_key = 'deliverability:inbox_placement' and closed_at is null;

  -- 1. a recipient's mailbox class
  o := o || jsonb_build_object('classes', jsonb_build_object(
    'm365_corporate', fn_mail_provider_class('adpf.ae', array['adpf-ae.mail.protection.outlook.com']),
    'hotmail_mx', fn_mail_provider_class('hotmail.com', array['hotmail-com.olc.protection.outlook.com']),
    'google_workspace', fn_mail_provider_class('acme.ae', array['aspmx.l.google.com', 'alt1.aspmx.l.google.com']),
    'gmail', fn_mail_provider_class('gmail.com', array['gmail-smtp-in.l.google.com']),
    'yahoo', fn_mail_provider_class('yahoo.com', array['mta5.am0.yahoodns.net']),
    'aol', fn_mail_provider_class('aol.com', array['mx-aol.mail.gm0.yahoodns.net']),
    'etisalat', fn_mail_provider_class('emirates.net.ae', array['imailv.emirates.net.ae']),
    'gateway_first', fn_mail_provider_class('adcustoms.gov.ae', array['seg.in.tmes-uae.trendmicro.com', 'adcustoms-gov-ae.mail.protection.outlook.com']),
    'outlook_no_mx', fn_mail_provider_class('outlook.com', null),
    'live_lookalike', fn_mail_provider_class('livestock.ae', null)));
  if o #>> '{classes,m365_corporate}' <> 'microsoft' or o #>> '{classes,hotmail_mx}' <> 'microsoft'
     or o #>> '{classes,google_workspace}' <> 'google' or o #>> '{classes,gmail}' <> 'google'
     or o #>> '{classes,yahoo}' <> 'yahoo_aol' or o #>> '{classes,aol}' <> 'yahoo_aol'
     or o #>> '{classes,etisalat}' <> 'other' or o #>> '{classes,gateway_first}' <> 'other'
     or o #>> '{classes,outlook_no_mx}' <> 'microsoft' or o #>> '{classes,live_lookalike}' <> 'other' then
    v_fail := v_fail || text 'a mailbox class is wrong'; end if;

  -- 2. no verdict before any test (a moment before every recorded test)
  v := fn_invite_placement_class_verdicts('2026-01-05 08:00+00');
  o := o || jsonb_build_object('before_any_test', v ->> 'strict');
  if v ->> 'strict' <> 'fail:no_verdict' or v ->> 'google' <> 'fail:no_verdict' then v_fail := v_fail || text 'no verdict is not fail:no_verdict'; end if;

  -- 3. the REAL 27 Oct result
  r := fn_record_inbox_placement_verdict(v_real || jsonb_build_object('created', t0), 'supplier@quotesdone.com', 'it_engineer');
  o := o || jsonb_build_object('real_rates', r -> 'class_rates', 'real_against_bar', r -> 'against_the_bar',
                               'real_seed_notifications', r -> 'seed_notifications');
  if r #>> '{class_rates,microsoft,seeds}' <> '18' or r #>> '{class_rates,microsoft,inbox}' <> '0'
     or r #>> '{class_rates,google,seeds}' <> '25' or r #>> '{class_rates,google,inbox}' <> '5' or r #>> '{class_rates,google,tabs}' <> '20'
     or r #>> '{class_rates,yahoo_aol,seeds}' <> '17' or r #>> '{class_rates,yahoo_aol,spam}' <> '17'
     or r #>> '{class_rates,overall,seeds}' <> '111' or r #>> '{class_rates,overall,inbox}' <> '44'
     or r #>> '{class_rates,overall,unclassified}' <> '5' then
    v_fail := v_fail || text 'the real 27 Oct numbers were not recorded as measured'; end if;
  v := fn_invite_placement_class_verdicts(t1);
  -- a one-literal call takes now(), an open weekday's judge: its overload is read from the plan, which runs nothing
  execute 'explain (verbose, costs off, format json) select public.fn_invite_placement_gate(''google'')' into v_plan;
  o := o || jsonb_build_object('real_day_after', v - 'bar_sender' - 'effective_sender' - 'max_age' - 'checked_at',
    'gate_strict', fn_invite_placement_gate(null::date, t1),
    'gate_google', fn_invite_placement_gate('google', null, t1),
    'gate_microsoft', fn_invite_placement_gate('microsoft', null, t1),
    'gate_unknown_is_other', fn_invite_placement_gate('zz-unknown', null, t1),
    'open_real', to_jsonb(fn_invite_placement_open_providers(null, t1)),
    'one_literal_resolves_to_the_class_form', strpos(v_plan::text, 'fn_invite_placement_gate(''google''::text, NULL::date, now())') > 0);
  if v ->> 'microsoft' <> 'fail:below_bar:microsoft' or v ->> 'google' <> 'pass' or v ->> 'yahoo_aol' <> 'fail:below_bar:yahoo_aol'
     or v ->> 'other' <> 'fail:below_bar:microsoft' or v ->> 'strict' <> 'fail:below_bar:microsoft'
     or o ->> 'gate_strict' <> 'fail:below_bar:microsoft' or o ->> 'gate_google' <> 'pass'
     or o ->> 'gate_unknown_is_other' <> 'fail:below_bar:microsoft' or o -> 'open_real' <> '["google"]'::jsonb then
    v_fail := v_fail || text 'the real result is not judged per class (Google pass, the rest skipped)'; end if;
  if not coalesce((o ->> 'one_literal_resolves_to_the_class_form')::boolean, false) then
    v_fail := v_fail || text 'fn_invite_placement_gate(<literal>) does not resolve to the class form'; end if;

  -- 4. stale after 7 days
  v := fn_invite_placement_class_verdicts(t0 + interval '7 days 1 minute');
  o := o || jsonb_build_object('real_after_7_days', v ->> 'strict', 'google_after_7_days', v ->> 'google');
  if v ->> 'strict' <> 'fail:stale_verdict' or v ->> 'google' <> 'fail:stale_verdict' then v_fail := v_fail || text 'a 7-day-old verdict is not stale'; end if;

  -- 5. the bar on counts, with ZZ DEMO tests recorded after the real one
  r := fn_record_inbox_placement_verdict((fx || '{"providerGroupName":"Outlook","total":20,"inbox":16,"spam":4,"other":0,"notDelivered":0},'
       || '{"providerGroupName":"Gmail (6 months+)","total":20,"inbox":10,"spam":4,"other":6,"notDelivered":0},'
       || '{"providerGroupName":"Yahoo","total":10,"inbox":8,"spam":2,"other":0,"notDelivered":0}]}')::jsonb
       || jsonb_build_object('testId', 'zz-demo-probe-at-the-bar', 'created', t1 + interval '1 hour'), 'supplier@quotesdone.com', 'it_engineer');
  o := o || jsonb_build_object('at_the_bar', fn_invite_placement_class_verdicts(t1 + interval '1 hour 30 minutes') ->> 'strict',
                               'at_the_bar_open', to_jsonb(fn_invite_placement_open_providers(null, t1 + interval '1 hour 30 minutes')));
  if o ->> 'at_the_bar' <> 'pass' or o -> 'at_the_bar_open' <> '["google", "microsoft", "other", "yahoo_aol"]'::jsonb then
    v_fail := v_fail || text 'exactly 80% inbox / 20% spam does not pass'; end if;
  r := fn_record_inbox_placement_verdict((fx || '{"providerGroupName":"Hotmail","total":19,"inbox":15,"spam":4,"other":0,"notDelivered":0},'
       || '{"providerGroupName":"Gmail (4 years+)","total":20,"inbox":15,"spam":5,"other":0,"notDelivered":0},'
       || '{"providerGroupName":"AOL","total":10,"inbox":8,"spam":2,"other":0,"notDelivered":0}]}')::jsonb
       || jsonb_build_object('testId', 'zz-demo-probe-below-the-bar', 'created', t1 + interval '2 hours'), 'supplier@quotesdone.com', 'it_engineer');
  v := fn_invite_placement_class_verdicts(t1 + interval '2 hours 30 minutes');
  o := o || jsonb_build_object('below_the_bar', v - 'bar_sender' - 'effective_sender' - 'max_age' - 'checked_at' - 'tested_at');
  if v ->> 'microsoft' <> 'fail:below_bar:microsoft' or v ->> 'google' <> 'fail:below_bar:google' or v ->> 'yahoo_aol' <> 'pass'
     or v ->> 'other' <> 'fail:below_bar:microsoft' then
    v_fail := v_fail || text '78.9% inbox or 25% spam passed'; end if;
  r := fn_record_inbox_placement_verdict((fx || '{"providerGroupName":"Outlook","total":10,"inbox":10,"spam":0,"other":0,"notDelivered":0},'
       || '{"providerGroupName":"Gmail (6 months+)","total":20,"inbox":10,"spam":0,"other":0,"notDelivered":10},'
       || '{"providerGroupName":"Yahoo","total":10,"inbox":10,"spam":0,"other":0,"notDelivered":0}]}')::jsonb
       || jsonb_build_object('testId', 'zz-demo-probe-gmail-lost', 'created', t1 + interval '3 hours'), 'supplier@quotesdone.com', 'it_engineer');
  o := o || jsonb_build_object('gmail_lost_half', fn_invite_placement_class_verdicts(t1 + interval '3 hours 30 minutes') ->> 'google');
  if o ->> 'gmail_lost_half' <> 'fail:below_bar:google' then v_fail := v_fail || text 'Gmail with half the mail lost and 0% spam passed'; end if;
  -- a count missing from the rates is a fail, and the strict answer says so (review of #1701: it answered 'pass')
  v := fn_invite_placement_rates_verdict('{"microsoft":{"seeds":10,"inbox":10},"google":{"seeds":10,"spam":0,"inbox":10},"yahoo_aol":{"seeds":10}}'::jsonb);
  o := o || jsonb_build_object('missing_count_strict', v ->> 'strict');
  if v ->> 'strict' = 'pass' or v ->> 'google' = 'pass' or v ->> 'yahoo_aol' = 'pass' then
    v_fail := v_fail || text 'a missing count passed, or left the strict answer at pass'; end if;

  -- 6. a bad result is refused
  foreach a slice 1 in array array[
      array['bad_sum', (fx || '{"providerGroupName":"Outlook","total":9,"inbox":1,"spam":1,"other":0,"notDelivered":0}]}')::jsonb || jsonb_build_object('testId','zz-demo-probe-bad','created',t0) #>> '{}', 'supplier@quotesdone.com', 'it_engineer'],
      array['not_a_seat', (fx || '{"providerGroupName":"Outlook","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0}]}')::jsonb || jsonb_build_object('testId','zz-demo-probe-bad','created',t0) #>> '{}', 'supplier@quotesdone.com', 'zz_not_a_seat'],
      array['wrong_domain', (fx || '{"providerGroupName":"Outlook","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0}]}')::jsonb || jsonb_build_object('testId','zz-demo-probe-bad','created',t0) #>> '{}', 'zz@example.invalid', 'it_engineer'],
      array['no_rollup', jsonb_build_object('testId','zz-demo-probe-bad','created',t0,'stats','{}'::jsonb) #>> '{}', 'supplier@quotesdone.com', 'it_engineer'],
      array['no_created', (fx || '{"providerGroupName":"Outlook","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0}]}')::jsonb || jsonb_build_object('testId','zz-demo-probe-bad') #>> '{}', 'supplier@quotesdone.com', 'it_engineer']] loop
    v_ok := false;
    begin
      perform fn_record_inbox_placement_verdict(a[2]::jsonb, a[3], a[4]);
    exception when check_violation then v_ok := sqlerrm like 'fn_record_inbox_placement_verdict:%';
    end;
    if not v_ok then v_fail := v_fail || ('a bad result was accepted: ' || a[1]); end if;
  end loop;

  -- 7. the candidate picker: the filter returns only the asked class; the one-argument form is unchanged
  select count(*), count(*) filter (where fn_mail_provider_of_email(c.to_email) <> 'google') into n, m
    from fn_supplier_invite_candidates(25, array['google']) c;
  select array_agg(c.lead_id order by c.lead_id) into v_ids1 from fn_supplier_invite_candidates(25) c;
  select array_agg(c.lead_id order by c.lead_id) into v_ids2 from fn_supplier_invite_candidates(25, null::text[]) c;
  o := o || jsonb_build_object('google_candidates', n, 'google_candidates_not_google', m,
                               'one_arg_unchanged', v_ids1 is not distinct from v_ids2, 'one_arg_rows', coalesce(cardinality(v_ids1), 0));
  if m <> 0 then v_fail := v_fail || text 'the class filter let another class through'; end if;
  if v_ids1 is distinct from v_ids2 then v_fail := v_fail || text 'the one-argument picker changed'; end if;
  o := o || jsonb_build_object('eligible_pool_by_class', (select jsonb_object_agg(k, c) from (
          select fn_mail_provider_of_email(l.email) k, count(*) c from leads l
           where l.id in (select e.id from fn_supplier_invite_eligible_ids() e(id)) group by 1) x));

  -- 8. nothing moved: no switch, no mail, and the held campaign filed no finding
  select coalesce(jsonb_object_agg(key, value), '{}') into v_sw_after from app_secrets
   where key in ('invite_enabled', 'supplier_outreach_golive', 'wa_supplier_invite_golive');
  select count(*) into n_mail_after from notifications where created_at = now() or xmin::text = (pg_current_xact_id()::text::bigint % 4294967296)::text;
  select count(*) into n_find_after from it_engineer_finding where issue_key = 'deliverability:inbox_placement' and closed_at is null;
  o := o || jsonb_build_object('switches', v_sw_after, 'held_because', fn_invite_placement_day_closed(t1),
                               'mail_rows_added', n_mail_after - n_mail_before, 'findings_added', n_find_after - n_find_before);
  if v_sw_after is distinct from v_sw_before then v_fail := v_fail || text 'a campaign switch changed'; end if;
  if n_mail_after <> n_mail_before then v_fail := v_fail || text 'a notification was written'; end if;
  -- the weekend moment must really be closed, or the judge could have filed and the check below would be skipped
  if fn_invite_placement_day_closed(t1) is null then v_fail := v_fail || text 'the probe''s weekend moment t1 is an open day'; end if;
  if fn_invite_placement_day_closed(t1) is not null and n_find_after <> n_find_before then
    v_fail := v_fail || text 'a finding was filed while the campaign is held'; end if;

  -- 9. closed doors
  o := o || jsonb_build_object('closed', jsonb_build_object(
    'routines', not exists (select 1 from unnest(array[
        'public.fn_record_inbox_placement_verdict(jsonb,text,text)', 'public.fn_invite_placement_class_verdicts(timestamptz)',
        'public.fn_invite_placement_judge(date,timestamptz)', 'public.fn_invite_placement_gate(text,date,timestamptz)',
        'public.fn_invite_placement_gate(date,timestamptz)', 'public.fn_invite_placement_open_providers(date,timestamptz)',
        'public.fn_invite_placement_rates_verdict(jsonb)', 'public.fn_mail_provider_class(text,text[])',
        'public.fn_mail_provider_of_email(text)', 'public.fn_glockapps_provider_class(text)',
        'public.fn_supplier_invite_candidates(integer,text[])', 'public.fn_supplier_invite_candidates(integer)']) f, unnest(array['anon', 'authenticated']) g
       where has_function_privilege(g, f, 'execute')),
    'tables', not exists (select 1 from unnest(array['public.deliverability_test', 'public.deliverability_test_provider', 'public.invite_placement_bar']) t,
                                 unnest(array['anon', 'authenticated']) g where has_table_privilege(g, t, 'select')),
    'rls', (select bool_and(c.relrowsecurity) from pg_class c where c.oid in ('public.deliverability_test'::regclass,
              'public.deliverability_test_provider'::regclass, 'public.invite_placement_bar'::regclass)),
    'policies', (select count(*) from pg_policies where schemaname = 'public' and policyname in
              ('deliverability_test_service_role_only', 'deliverability_test_provider_service_role_only', 'invite_placement_bar_service_role_only')),
    'service_role_records', has_function_privilege('service_role', 'public.fn_record_inbox_placement_verdict(jsonb,text,text)', 'execute'),
    'one_bar_row', (select count(*) from invite_placement_bar)));
  if not (o #>> '{closed,routines}')::boolean or not (o #>> '{closed,tables}')::boolean or not (o #>> '{closed,rls}')::boolean
     or (o #>> '{closed,policies}')::int <> 3 or not (o #>> '{closed,service_role_records}')::boolean or (o #>> '{closed,one_bar_row}')::int <> 1 then
    v_fail := v_fail || text 'a door is open, or the bar is not one row'; end if;

  -- The management API returns about 2,000 characters of an error, so a passing run raises the short form; a failing
  -- run raises everything it measured, the verdict first.
  raise exception 'CHK<<%|%>>',
    case when cardinality(v_fail) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_fail, '; ') end,
    case when cardinality(v_fail) > 0 then o::text else (o - 'classes' - 'closed' - 'real_rates' - 'real_against_bar' - 'real_day_after' - 'below_the_bar'
      || jsonb_build_object('real_27_oct', format('microsoft %s/%s inbox; google %s inbox + %s tabs of %s, %s spam; yahoo_aol %s/%s inbox; other %s/%s; overall %s/%s inbox, %s unclassified',
           o #>> '{real_rates,microsoft,inbox}', o #>> '{real_rates,microsoft,seeds}', o #>> '{real_rates,google,inbox}', o #>> '{real_rates,google,tabs}',
           o #>> '{real_rates,google,seeds}', o #>> '{real_rates,google,spam}', o #>> '{real_rates,yahoo_aol,inbox}', o #>> '{real_rates,yahoo_aol,seeds}',
           o #>> '{real_rates,other,inbox}', o #>> '{real_rates,other,seeds}', o #>> '{real_rates,overall,inbox}', o #>> '{real_rates,overall,seeds}',
           o #>> '{real_rates,overall,unclassified}'),
         'below_the_bar', (o -> 'below_the_bar') - 'test_id', 'checks_passed', 'classes 10/10, doors closed (12 routines, 3 tables, RLS, 3 policies, 1 bar row)'))::text end;
end $$;
