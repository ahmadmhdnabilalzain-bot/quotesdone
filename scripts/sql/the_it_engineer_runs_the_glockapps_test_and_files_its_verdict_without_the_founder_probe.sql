-- PROBE for the_it_engineer_runs_the_glockapps_test_and_files_its_verdict_without_the_founder.sql (27 Oct 2026).
-- Assigned: it_engineer
--
-- A pure probe: it always ends in raise exception 'CHK<<...>>', so every row it writes rolls back, the net.http_post
-- the tick queues included (pg_net reads only committed requests). Run in the SAME transaction after the change file
-- while that file is pending (scripts/checks/the_glockapps_test_runs_and_files_its_verdict_without_the_founder.test.mjs
-- does this through scripts/lib/safe_replay.mjs).
--
-- It cannot reach a person: app.qd_stub_founder_notify = 'on' makes fn_deliverability_test_file skip the founder
-- email; its own test rows are 'ZZPROBE-…' ids that GlockApps never issues; it queues no notification. It names the
-- real rows it must not disturb (the adopted 27 Oct test and the two invitation switches) and reads them before and
-- after.
set local app.qd_stub_founder_notify = 'on';
create temp table zz_probe_glockapps (step text primary key, v boolean, detail text) on commit drop;
create temp table zz_probe_before on commit drop as
  select key, value from public.app_secrets where key in ('invite_enabled', 'wa_supplier_invite_golive', 'supplier_outreach_golive');
create temp table zz_probe_adopted on commit drop as
  select test_id, status, verdict, reported_at from public.deliverability_test where test_id = '2026-10-27-09:33:53:634t';

-- 1. the tick collects the oldest open test, and its result carries no credential
insert into zz_probe_glockapps
select 'tick_collects_oldest_open',
       (r ->> 'action') = 'collect' and (r ->> 'test_id') = (select test_id from public.deliverability_test where status in ('seeds_queued', 'collecting') order by created_at limit 1)
       and (r ->> 'kicked')::boolean and not (r ? '__secret'), r::text
  from (select public.fn_deliverability_test_tick() r) x
 where exists (select 1 from public.deliverability_test where status in ('seeds_queued', 'collecting'));
insert into zz_probe_glockapps select 'tick_collects_oldest_open', true, 'no open test to collect'
 where not exists (select 1 from zz_probe_glockapps where step = 'tick_collects_oldest_open');

-- 2. with no open test, a request makes it create; without one and with the weekly switch off it does nothing
create temp table zz_probe_open on commit drop as
  select test_id, status from public.deliverability_test where status in ('seeds_queued', 'collecting');
update public.deliverability_test set status = 'failed' where test_id in (select test_id from zz_probe_open);
delete from public.app_secrets where key = 'deliverability_test_request';
update public.app_secrets set value = 'false' where key = 'deliverability_retest_weekly';
insert into zz_probe_glockapps select 'idle_without_intent', (public.fn_deliverability_test_tick() ->> 'action') = 'none', null;
select public.fn_deliverability_test_request('ZZ PROBE');
insert into zz_probe_glockapps select 'request_creates', (r ->> 'action') = 'create' and (r ->> 'reason') = 'ZZ PROBE', r::text
  from (select public.fn_deliverability_test_tick() r) x;
delete from public.app_secrets where key = 'deliverability_test_request';
update public.app_secrets set value = 'true' where key = 'deliverability_retest_weekly';
insert into zz_probe_glockapps select 'weekly_creates_when_due',
  (public.fn_deliverability_test_tick() ->> 'action') = case when (select max(created_at) from public.deliverability_test) < now() - interval '7 days'
                                                            or not exists (select 1 from public.deliverability_test) then 'create' else 'none' end, null;

-- 3. filing: a pending test is refused; a failed one raises the finding once; a passing one closes it
insert into public.deliverability_test (test_id, reason, requested_by, marker, status, verdict, outlook, outlook_inbox_pct, decided_at, summary)
values ('ZZPROBE-0001t', 'ZZ PROBE', 'it_engineer', 'id:ZZPROBE-0001t', 'collecting', 'pending', null, null, null, null),
       ('ZZPROBE-0002t', 'ZZ PROBE', 'it_engineer', 'id:ZZPROBE-0002t', 'complete', 'fail', '{"seeds":18,"inbox":0}'::jsonb, 0, now(), 'ZZ PROBE summary'),
       ('ZZPROBE-0003t', 'ZZ PROBE', 'it_engineer', 'id:ZZPROBE-0003t', 'complete', 'pass', '{"seeds":18,"inbox":16}'::jsonb, 88.9, now(), 'ZZ PROBE summary');
insert into public.deliverability_test_provider (test_id, provider, is_outlook, seeds, inbox, spam, tabs, missing, inbox_pct)
values ('ZZPROBE-0002t', 'Outlook', true, 18, 0, 18, 0, 0, 0);
insert into zz_probe_glockapps select 'pending_not_filed', not (public.fn_deliverability_test_file('ZZPROBE-0001t') ->> 'filed')::boolean, null;
insert into zz_probe_glockapps select 'fail_filed_stubbed',
  (r ->> 'filed')::boolean and (r -> 'founder' ->> 'stubbed')::boolean, r::text
  from (select public.fn_deliverability_test_file('ZZPROBE-0002t') r) x;
insert into zz_probe_glockapps select 'finding_raised',
  exists (select 1 from public.it_engineer_finding where issue_key = 'deliverability_outlook_not_proven' and closed_at is null), null;
insert into zz_probe_glockapps select 'filed_once', (public.fn_deliverability_test_file('ZZPROBE-0002t') ->> 'reason') = 'already filed', null;
-- two statements: a statement's own subquery does not see what a function it calls wrote
insert into zz_probe_glockapps select 'pass_filed', (public.fn_deliverability_test_file('ZZPROBE-0003t') ->> 'filed')::boolean, null;
insert into zz_probe_glockapps select 'pass_closes',
  not exists (select 1 from public.it_engineer_finding where issue_key = 'deliverability_outlook_not_proven' and closed_at is null), null;
insert into zz_probe_glockapps select 'no_email_queued',
  not exists (select 1 from public.notifications where created_at >= now() and (subject like '%GlockApps%' or kind = 'deliverability_verdict')), null;
do $c$ begin
  begin
    insert into public.deliverability_test (test_id, reason, requested_by, marker, status, verdict, outlook_inbox_pct, decided_at)
    values ('ZZPROBE-0004t', 'ZZ PROBE', 'it_engineer', 'id:ZZPROBE-0004t', 'complete', 'pass', 79.9, now());
    insert into zz_probe_glockapps values ('pass_needs_80', false, 'a 79.9% pass was accepted');
  exception when check_violation then insert into zz_probe_glockapps values ('pass_needs_80', true, null);
  end;
end $c$;

-- 4. a real lead's address is a known party; a GlockApps-style address that no party holds is not
insert into zz_probe_glockapps
select 'known_parties',
       (select lower(btrim(email)) from public.leads where btrim(coalesce(email, '')) <> '' order by id limit 1) = any(
         public.fn_deliverability_known_parties(array[(select lower(btrim(email)) from public.leads where btrim(coalesce(email, '')) <> '' order by id limit 1),
                                                    'zz-probe-not-a-party@example.invalid']))
       and not ('zz-probe-not-a-party@example.invalid' = any(public.fn_deliverability_known_parties(array['zz-probe-not-a-party@example.invalid']))), null;

-- 5. nothing real moved: the invitation switches and the adopted test are as they were before the probe's own edits
insert into zz_probe_glockapps select 'switches_untouched',
  not exists (select key, value from zz_probe_before except select key, value from public.app_secrets where key in (select key from zz_probe_before)), null;
update public.deliverability_test d set status = o.status from zz_probe_open o where d.test_id = o.test_id;
insert into zz_probe_glockapps select 'adopted_untouched',
  not exists (select * from zz_probe_adopted except select test_id, status, verdict, reported_at from public.deliverability_test where test_id = '2026-10-27-09:33:53:634t'), null;

do $v$ begin
  -- step -> true/false only: a detail text carries quotes that the transport escapes twice
  raise exception 'CHK<<%>>', (select jsonb_object_agg(step, coalesce(v, false)) from zz_probe_glockapps)::text;
end $v$;
