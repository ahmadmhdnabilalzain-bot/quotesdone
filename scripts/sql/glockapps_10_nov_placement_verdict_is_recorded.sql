-- GLOCKAPPS 10 NOV 2026: GOOGLE STILL PASSES (24 OF 24 INBOX), MICROSOFT 0 OF 21 AND YAHOO/AOL 0 OF 17 STILL FAIL, AND THE
-- VERDICT THE INVITATION GATE READS IS RENEWED TO 10 DEC 2026 (it_engineer, 10-11 Nov 2026).
--
-- Seat: it_engineer. Assigned: it_engineer. Founder ledger 1617 (10 Nov 2026): "run a new GlockApps inbox-placement test
-- now, so supplier e-mail invitations keep running past 26 Nov". He approved exactly ONE GlockApps credit.
--
-- WHY. fn_invite_placement_class_verdicts reads the latest recorded deliverability_test row for supplier@. Until this file,
-- that was GlockApps 2026-10-27-22:50:26:837t, tested 27 Oct 22:50Z. On a 30-day max_age it goes stale on 26 Nov ~22:50Z,
-- and then every class answers fail:stale_verdict and no invitation is queued. (The brief named 2026-10-27-09:33:53:634t;
-- that test is not in deliverability_test. 22:50:26:837t is the one the gate reads, measured 10 Nov 21:2xZ.)
--
-- MEASURED, the test (GlockApps connector, project 163001, test 2026-11-10-21:29:37:367t, created 21:29:37Z, 1 credit;
-- balance 3 -> 2):
--   * Sent through the SAME path as 5, 19 and 27 Oct: notifications rows with type 'supplier_invite_seed', kind
--     'invite_m365_seed', to_role 'supplier', requested_by 'it_engineer'. The body ends in the marker line
--     "id:2026-11-10-21:29:37:367t", in the no-space form the lane's seedMarker() and this routine's row count accept.
--     send_outbox's Microsoft 365 lane (deployed = repo, verify_deploy_parity MATCH) rebuilds the live variant-A
--     invitation (campaignMail, 0 copy-lint failures) FROM supplier@quotesdone.com, keeps the marker as the last line,
--     and paces 5 a run. Seeds are never open-tracked (open_tracking.ts), so they carry the plain-text form that 80% of
--     real invitations carry. All 129 addresses are GlockApps-owned: 0 in leads, 0 in auth.users, 0 the founder's
--     (a01_notifications_no_test_mail_to_the_founder refused one in an aborted probe).
--   * 129 of 129 addresses reached, 131 sent rows, all 'm365:' message ids, 21:45:47Z -> 05:01:13Z. The send_outbox
--     scheduler slipped from 15 to ~30 min after midnight.
--   * A DUPLICATE BATCH, said rather than hidden. The insert answered HTTP 502 while its transaction was still running.
--     A count read 0, so the guarded retry inserted a second 129 rows (137377-137505, 21:31:39Z). The two transactions
--     overlapped, so the not-exists guard could not see the first. Found at 02:2xZ. 123 queued duplicates, and the 4
--     first-batch rows whose address a duplicate had already reached, were cancelled with a last_error naming why.
--     2 seeds (one Gmail, one Outlook.fr) received two copies; every other seed received one. So "seed_notifications" in
--     stats below counts 258 rows by marker, cancelled included; 131 were sent. Lesson:
--     .claude/memory/a-502-can-commit-after-the-count-that-cleared-the-retry.md.
--   * Result, read 11 Nov 05:13Z, 12 min after the last seed (GlockApps "settled", not "finished"; the 8 not delivered
--     are Interia.pl 3, ukr.net 2, Onet.pl 2, naver.com 1, all class 'other'):
--       microsoft  21 seeds: 0 inbox, 21 spam (Outlook 8, Hotmail 6, Exchange/O365 5, .fr 1, .de 1). EOP SCL 5 on 22,
--                  Forefront SCL 5 on 6 corporate seeds, BCL 0 (not bulk) on all 22: a reputation verdict, not content.
--       google     24 seeds: 24 inbox, 0 tabs, 0 spam (Gmail 16 + 3, Workspace 3 + 2).
--       yahoo_aol  17 seeds: 0 inbox, 17 spam.
--       other      61 seeds: 67.2% inbox, 3.3% tabs, 16.4% spam, 13.1% missing.
--       overall   128 tracked: 68 inbox, 2 tabs, 50 spam, 8 missing (53.1% / 39.1% spam). SPF, DKIM, DMARC pass;
--                  SpamAssassin 0.4; Barracuda 0. Sending IP 40.107.55.86 (Microsoft UAE North).
--   * Against invite_placement_bar (unchanged): google pass; microsoft, yahoo_aol and other (= microsoft) fail. Same
--     classes as 27 Oct, now good until 2026-12-10 21:29Z (tested_at + max_age 30 days).
--
-- WHAT THIS DOES: records that one result through public.fn_record_inbox_placement_verdict, once (keyed on the test id),
-- so the gate reads it. Data only, no DDL. The JSON is scripts/checks/glockapps_10_nov_providers.fixture.json without
-- its _source line; scripts/checks/glockapps_10_nov_verdict_is_recorded_from_its_fixture.test.mjs keeps them equal.
-- WHAT IT DOES NOT CHANGE: invite_enabled and every other campaign switch, invite_placement_bar (every bar, max_age 30
-- days, the sender), invite_daily_cap, any seat, any routine. It sends nothing; the seeds were sent once, by hand.
-- A Microsoft or Yahoo pass would still not reopen those classes: fn_invite_placement_open_providers leaves them out
-- whatever the verdict says (founder_instruction 1537).

select public.fn_record_inbox_placement_verdict(
  $glockapps${"testId":"2026-11-10-21:29:37:367t","projectId":"163001","finished":false,"created":"2026-11-10T21:29:37.363Z","seedAccountsTotal":129,"trackedSeeds":128,"stats":{"inbox":68,"other":2,"spam":50,"notDelivered":8,"inboxRate":53.1,"spamRate":39.1,"otherRate":1.6,"notDeliveredRate":6.2,"inboxAndOtherRates":54.7},"authSummary":{"spf":"pass","dkim":"pass","dmarc":"pass"},"sender":{"senderIp":"40.107.55.86","senderDomain":"quotesdone.com","rdns":"mail-uaenorthazon11022086.outbound.protection.outlook.com","isp":"outlook.com"},"providerRollup":[{"providerGroupId":"4","providerGroupName":"Yahoo","total":9,"inbox":0,"spam":9,"other":0,"notDelivered":0},{"providerGroupId":"2","providerGroupName":"AOL","total":8,"inbox":0,"spam":8,"other":0,"notDelivered":0},{"providerGroupId":"3","providerGroupName":"Outlook","total":8,"inbox":0,"spam":8,"other":0,"notDelivered":0},{"providerGroupId":"6","providerGroupName":"Hotmail","total":6,"inbox":0,"spam":6,"other":0,"notDelivered":0},{"providerGroupId":"17","providerGroupName":"Exchange (Office365)","total":5,"inbox":0,"spam":5,"other":0,"notDelivered":0},{"providerGroupId":"34","providerGroupName":"Interia.pl","total":3,"inbox":0,"spam":0,"other":0,"notDelivered":3},{"providerGroupId":"52","providerGroupName":"mailo.com","total":3,"inbox":0,"spam":3,"other":0,"notDelivered":0},{"providerGroupId":"25","providerGroupName":"Laposte.net (FR)","total":2,"inbox":0,"spam":2,"other":0,"notDelivered":0},{"providerGroupId":"45","providerGroupName":"att.net","total":2,"inbox":0,"spam":2,"other":0,"notDelivered":0},{"providerGroupId":"53","providerGroupName":"ukr.net","total":2,"inbox":0,"spam":0,"other":0,"notDelivered":2},{"providerGroupId":"15","providerGroupName":"Yandex.ru","total":2,"inbox":0,"spam":2,"other":0,"notDelivered":0},{"providerGroupId":"33","providerGroupName":"Onet.pl","total":2,"inbox":0,"spam":0,"other":0,"notDelivered":2},{"providerGroupId":"61","providerGroupName":"Outlook.fr","total":1,"inbox":0,"spam":1,"other":0,"notDelivered":0},{"providerGroupId":"46","providerGroupName":"currently.com","total":1,"inbox":0,"spam":1,"other":0,"notDelivered":0},{"providerGroupId":"48","providerGroupName":"naver.com","total":1,"inbox":0,"spam":0,"other":0,"notDelivered":1},{"providerGroupId":"62","providerGroupName":"Outlook.de","total":1,"inbox":0,"spam":1,"other":0,"notDelivered":0},{"providerGroupId":"11","providerGroupName":"Zoho","total":2,"inbox":1,"spam":0,"other":1,"notDelivered":0,"tabs":["Newsletter"]},{"providerGroupId":"24","providerGroupName":"Seznam.cz","total":2,"inbox":1,"spam":0,"other":1,"notDelivered":0,"tabs":["Newsletter"]},{"providerGroupId":"5","providerGroupName":"Gmail (6 months+)","total":16,"inbox":16,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"56","providerGroupName":"gmx.de","total":6,"inbox":6,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"8","providerGroupName":"Web.de","total":5,"inbox":5,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"7","providerGroupName":"Apple","total":3,"inbox":3,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"42","providerGroupName":"Google Workspace (4 years+)","total":3,"inbox":3,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"59","providerGroupName":"Gmail (4 years+)","total":3,"inbox":3,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"68","providerGroupName":"gmx.at","total":3,"inbox":3,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"58","providerGroupName":"gmx.net","total":3,"inbox":3,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"69","providerGroupName":"gmx.ch","total":3,"inbox":3,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"9","providerGroupName":"Freenet.de","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"63","providerGroupName":"Google Workspace (Up to 6 months)","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"20","providerGroupName":"Virgilio.it","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"57","providerGroupName":"gmx.com","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"30","providerGroupName":"Amazon WorkMail","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"14","providerGroupName":"Mail.ru","total":2,"inbox":2,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"19","providerGroupName":"Libero.it","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"51","providerGroupName":"rambler.ru","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"13","providerGroupName":"Mail.com","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"44","providerGroupName":"T-online.de","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"60","providerGroupName":"Protonmail","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0},{"providerGroupId":"66","providerGroupName":"vodafonemail.de","total":1,"inbox":1,"spam":0,"other":0,"notDelivered":0}]}$glockapps$::jsonb, 'supplier@quotesdone.com', 'it_engineer') as recorded
 where not exists (select 1 from public.deliverability_test d
                    where d.test_id = '2026-11-10-21:29:37:367t' and d.recorded_at is not null);

-- verdict row: the record exists with the measured counts, and the gate reads it with the expected answer per class
select case
  when not exists (select 1 from public.deliverability_test where test_id = '2026-11-10-21:29:37:367t' and recorded_at is not null)
    then 'PROBE FAILED: test 2026-11-10-21:29:37:367t is not recorded'
  when (select class_rates #>> '{microsoft,seeds}' || '/' || (class_rates #>> '{microsoft,inbox}') || ' ' || (class_rates #>> '{google,seeds}')
               || '/' || (class_rates #>> '{google,inbox}') || ' ' || (class_rates #>> '{yahoo_aol,seeds}') || '/' || (class_rates #>> '{yahoo_aol,inbox}')
          from public.deliverability_test where test_id = '2026-11-10-21:29:37:367t') is distinct from '21/0 24/24 17/0'
    then 'PROBE FAILED: the recorded class counts are not the measured 21/0, 24/24, 17/0'
  when (select v ->> 'test_id' from (select public.fn_invite_placement_class_verdicts(timestamptz '2026-11-11 06:00Z') v) x)
       is distinct from '2026-11-10-21:29:37:367t'
    then 'PROBE FAILED: the gate does not read this test'
  when (select concat_ws(',', v ->> 'google', v ->> 'microsoft', v ->> 'yahoo_aol', v ->> 'other')
          from (select public.fn_invite_placement_class_verdicts(timestamptz '2026-11-11 06:00Z') v) x)
       is distinct from 'pass,fail:below_bar:microsoft,fail:below_bar:yahoo_aol,fail:below_bar:microsoft'
    then 'PROBE FAILED: the per-class verdicts are not google pass, microsoft/yahoo_aol/other fail'
  when (select d.tested_at + b.max_age from public.deliverability_test d, public.invite_placement_bar b
         where d.test_id = '2026-11-10-21:29:37:367t' and b.id) is distinct from timestamptz '2026-12-10 21:29:37.363Z'
    then 'PROBE FAILED: this verdict is not good until 2026-12-10 21:29:37Z (has max_age or tested_at moved?)'
  else 'PROBE OK' end as verdict;
