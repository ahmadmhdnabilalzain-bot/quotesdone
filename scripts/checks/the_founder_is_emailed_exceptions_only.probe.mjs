// THE FOUNDER IS EMAILED EXCEPTIONS ONLY — proved in ONE aborted transaction inside a declared rehearsal
// window (6 Sep 2026). Nothing survives: the RAISE at the end rolls back every row, and the counts come out
// in the exception message. The founder is never paged by this probe.
//
// For each of the eight subjects that filled his inbox in the 30 days to 6 Sep, the CONDITION is simulated
// and the routine that used to email him is called; the assertion is 0 founder emails queued and exactly 1
// owned org_task opened (or bumped) per condition. For a refund approval and a platform-down signal the
// assertion is 1 email queued. Where a routine's condition cannot be manufactured inside a transaction
// (resilience needs the watchdog's own findings; business health is a view over the whole company) the
// routine's exact call is made instead, and that boundary is stated in the output.
//
//   node scripts/checks/the_founder_is_emailed_exceptions_only.probe.mjs
import { sql } from '../phase_b/lib/db.mjs';

const probe = `
do $probe$
declare
  q0 bigint; t0 bigint; a0 bigint; v_admin text; r jsonb; out jsonb := '{}'::jsonb; n int; k text;
  emails int; tasks int; task_id bigint; task_owner text; task_dept text; seen int; tid2 bigint;
  smoke_before jsonb; smoke_after jsonb; wa_queued int; cron_id bigint; wa_rows int;
  function_count int;
begin
  insert into public.rehearsal_window (run_tag, opened_by, note)
  values ('qd_run:founder_mail_probe', 'the_founder_is_emailed_exceptions_only.probe.mjs', 'aborted transaction; nothing survives');
  select lower(split_part(coalesce(value,''),',',1)) into v_admin from public.app_secrets where key = 'admin_emails';
  select coalesce(max(id),0) into q0 from public.notifications;
  select coalesce(max(id),0) into t0 from public.org_tasks;
  select coalesce(max(id),0) into a0 from public.agent_actions;

  -- ---------------------------------------------------------------- 1. scheduled runs failed
  -- the failed run is stamped BEFORE the rehearsal window opened: the watcher (correctly) does not page on
  -- a failure inside a declared window, and the point here is what it does with a real one
  insert into public.agent_runs (agent, started_at, finished_at, status, note)
  values ('zz_demo_probe_runner', clock_timestamp() - interval '3 seconds', clock_timestamp() - interval '2 seconds', 'error', 'ZZ DEMO probe: a real failure shape');
  update public.rehearsal_window set started_at = clock_timestamp() - interval '1 second' where run_tag = 'qd_run:founder_mail_probe';
  r := public.fn_watch_failed_runs();
  select count(*) into emails from public.notifications where id > q0 and channel in ('email','whatsapp') and (to_role in ('founder','admin') or lower(to_email) = v_admin);
  select count(*), max(id) into tasks, task_id from public.org_tasks where id > t0 and result->'founder_mail'->>'kind' = 'scheduled_runs_failed';
  select assigned_agent, dept_key into task_owner, task_dept from public.org_tasks where id = task_id;
  out := out || jsonb_build_object('1', jsonb_build_object('al', r->'new_conditions_alerted', 'e', emails, 't', tasks, 'o', task_owner, 'd', task_dept));
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);

  -- an UNCHANGED condition on the next pass: a second failure of the same shape (stamped outside the window,
  -- watermark rewound, the watcher's own 24h hold lifted so it reaches the door again): the same task is
  -- bumped, no second task, no email
  update public.rehearsal_window set started_at = clock_timestamp() + interval '2 seconds' where run_tag = 'qd_run:founder_mail_probe';
  insert into public.agent_runs (agent, started_at, finished_at, status, note)
  values ('zz_demo_probe_runner', clock_timestamp(), clock_timestamp(), 'error', 'ZZ DEMO probe: a real failure shape');
  update public.alert_watermark set last_run_at = clock_timestamp() - interval '1 second' where watcher = 'failed_runs';
  update public.alert_signature set last_alerted_at = null where watcher = 'failed_runs' and signature like 'zz_demo_probe_runner:%';
  r := public.fn_watch_failed_runs();
  update public.rehearsal_window set started_at = clock_timestamp() - interval '1 second' where run_tag = 'qd_run:founder_mail_probe';
  select count(*) into emails from public.notifications where id > q0 and channel in ('email','whatsapp') and (to_role in ('founder','admin') or lower(to_email) = v_admin);
  select count(*) into tasks from public.org_tasks where id > t0 and result ? 'founder_mail';
  select (result->'founder_mail'->>'seen_count')::int into seen from public.org_tasks where id = task_id;
  out := out || jsonb_build_object('1b', jsonb_build_object('al', r->'new_conditions_alerted', 'e', emails, 'nt', tasks, 'seen', seen));

  -- ---------------------------------------------------------------- 2. agent silence (a job that never ran)
  select cron.schedule('zz_demo_probe_job', '* * * * *', 'select 1') into cron_id;
  insert into public.cron_job_seen (jobid, jobname, schedule, first_seen) values (cron_id, 'zz_demo_probe_job', '* * * * *', clock_timestamp() - interval '2 days');
  r := public.fn_agent_silence_watch();
  select count(*) into emails from public.notifications where id > q0 and channel in ('email','whatsapp') and (to_role in ('founder','admin') or lower(to_email) = v_admin);
  select count(*), max(id) into tasks, task_id from public.org_tasks where id > t0 and result->'founder_mail'->>'kind' = 'agent_silence' and title like '%zz_demo_probe_job%';
  select assigned_agent, dept_key into task_owner, task_dept from public.org_tasks where id = task_id;
  out := out || jsonb_build_object('2', jsonb_build_object('nr', r->'never_ran_alerts', 'e', emails, 't', tasks, 'o', task_owner, 'd', task_dept));
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);

  -- ---------------------------------------------------------------- 3. resilience (the routine's exact call; its findings cannot be manufactured here)
  r := public.fn_notify_founder('Resilience: the platform needs attention', 'The self-healing watchdog found issues it could not auto-fix:' || E'\\n' || 'ZZ DEMO probe finding', 'critical', p_kind => 'resilience', p_dedupe_key => 'resilience');
  select count(*) into emails from public.notifications where id > q0 and channel in ('email','whatsapp') and (to_role in ('founder','admin') or lower(to_email) = v_admin);
  select count(*), max(id) into tasks, task_id from public.org_tasks where id > t0 and result->'founder_mail'->>'kind' = 'resilience';
  select assigned_agent, dept_key into task_owner, task_dept from public.org_tasks where id = task_id;
  out := out || jsonb_build_object('3', jsonb_build_object('m', r->>'mode', 'e', emails, 't', tasks, 'o', task_owner, 'd', task_dept));
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);

  -- ---------------------------------------------------------------- 4. AI credit low (what alert_founder now forwards from cost_snapshot)
  r := public.fn_notify_founder('AI credit low: $1.00 left', 'ZZ DEMO probe: every AI call runs on one OpenRouter balance', 'critical', p_kind => 'ai_credit_low', p_dedupe_key => 'openrouter_credit_low');
  select count(*) into emails from public.notifications where id > q0 and channel in ('email','whatsapp') and (to_role in ('founder','admin') or lower(to_email) = v_admin);
  select count(*), max(id) into tasks, task_id from public.org_tasks where id > t0 and result->'founder_mail'->>'kind' = 'ai_credit_low';
  select assigned_agent, dept_key into task_owner, task_dept from public.org_tasks where id = task_id;
  out := out || jsonb_build_object('4', jsonb_build_object('m', r->>'mode', 'e', emails, 't', tasks, 'o', task_owner, 'd', task_dept));
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);

  -- ---------------------------------------------------------------- 5. business health (the routine's exact call; the view is the whole company)
  r := public.fn_notify_founder('Business health 61% - department(s) at risk', 'ZZ DEMO probe dept 40% (probe basis)', 'warn', p_kind => 'business_health_at_risk', p_dedupe_key => 'health:' || to_char(now(),'YYYY-MM-DD'));
  select count(*) into emails from public.notifications where id > q0 and channel in ('email','whatsapp') and (to_role in ('founder','admin') or lower(to_email) = v_admin);
  select count(*), max(id) into tasks, task_id from public.org_tasks where id > t0 and result->'founder_mail'->>'kind' = 'business_health_at_risk';
  select assigned_agent, dept_key into task_owner, task_dept from public.org_tasks where id = task_id;
  out := out || jsonb_build_object('5', jsonb_build_object('m', r->>'mode', 'e', emails, 't', tasks, 'o', task_owner, 'd', task_dept));
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);

  -- ---------------------------------------------------------------- 6. data-integrity smoke
  select count(*) into wa_queued from public.notifications where status = 'queued' and channel = 'whatsapp' and created_at < now() - interval '2 hours';
  delete from public.notifications where type = 'smoke_alert' and created_at > now() - interval '24 hours';   -- its own 24h dedupe, cleared LOCALLY (rolled back)
  smoke_before := public.fn_smoke();      -- the WhatsApp rows alone must no longer trip email_backlog_stuck
  insert into public.notifications (type, to_email, to_role, channel, subject, body, status, created_at)
  values ('supplier_invite', 'zz-demo-probe@example.invalid', 'supplier', 'email', 'ZZ DEMO probe', 'stuck for three hours', 'queued', clock_timestamp() - interval '3 hours');
  smoke_after := public.fn_smoke();
  select count(*) into emails from public.notifications where id > q0 and channel in ('email','whatsapp') and (to_role in ('founder','admin') or lower(to_email) = v_admin);
  select count(*), max(id) into tasks, task_id from public.org_tasks where id > t0 and result->'founder_mail'->>'kind' = 'smoke_alert';
  select assigned_agent, dept_key into task_owner, task_dept from public.org_tasks where id = task_id;
  out := out || jsonb_build_object('6', jsonb_build_object('waw', wa_queued,
     'before', jsonb_build_object('f', smoke_before->'failures', 'stuck', (smoke_before->'detail')::text like '%email_backlog_stuck%'),
     'after',  jsonb_build_object('f', smoke_after->'failures',  'stuck', (smoke_after->'detail')::text like '%email_backlog_stuck%'),
     'e', emails, 't', tasks, 'o', task_owner, 'd', task_dept));
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);

  -- ---------------------------------------------------------------- 7. backup: one missed backup (26h) -> ONE task, 0 emails
  update public.agent_runs set started_at = started_at - interval '30 hours', finished_at = finished_at - interval '30 hours' where agent = 'backup';
  update public.agent_actions set status = 'cancelled' where kind = 'backup_alert' and status in ('pending','needs_review');
  r := public.fn_backup_watch();
  select count(*) into emails from public.notifications where id > q0 and channel in ('email','whatsapp') and (to_role in ('founder','admin') or lower(to_email) = v_admin);
  select count(*), max(id) into tasks, task_id from public.org_tasks where id > t0 and result ? 'founder_mail';
  select assigned_agent, dept_key, result->'founder_mail'->>'kind' into task_owner, task_dept, k from public.org_tasks where id = task_id;
  out := out || jsonb_build_object('7', jsonb_build_object('al', r->'alerted', 'aa', (select count(*) from public.agent_actions where id > a0), 'e', emails, 't', tasks, 'kind', k, 'o', task_owner, 'd', task_dept));
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);

  -- 7b. backup still failing after retry (>48h) -> the ONE allowed kind: 1 email, and the task is bumped not doubled
  update public.agent_runs set started_at = started_at - interval '30 hours' where agent = 'backup';
  update public.agent_actions set status = 'cancelled' where kind = 'backup_alert' and status in ('pending','needs_review');
  r := public.fn_backup_watch();
  select count(*), string_agg(distinct kind, ',') into emails, k from public.notifications where id > q0 and channel = 'email' and (to_role in ('founder','admin') or lower(to_email) = v_admin);
  select count(*) into tasks from public.org_tasks where id > t0 and result ? 'founder_mail';
  select (result->'founder_mail'->>'seen_count')::int into seen from public.org_tasks where id = task_id;
  out := out || jsonb_build_object('7b', jsonb_build_object('e', emails, 'k', k, 'nt', tasks, 'seen', seen));
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);

  -- ---------------------------------------------------------------- 8. the real stalled handoff (runs #80/#82, since 17 Aug)
  delete from public.founder_alerts where event like '%run #%' and event ilike '%handoff%' and created_at > now() - interval '24 hours';
  r := public.fn_handoff_watchdog();
  select count(*) into emails from public.notifications where id > q0 and channel in ('email','whatsapp') and (to_role in ('founder','admin') or lower(to_email) = v_admin);
  select count(*), max(id) into tasks, task_id from public.org_tasks where id > t0 and result->'founder_mail'->>'kind' like 'handoff_stalled%';
  select assigned_agent, dept_key, (result->'founder_mail'->>'seen_count')::int into task_owner, task_dept, seen from public.org_tasks where id = task_id;
  out := out || jsonb_build_object('8', jsonb_build_object('ov', r->'escalated', 'rt', r->'routed', 'em', r->'emailed', 'e', emails, 't', tasks, 'seen', seen, 'o', task_owner, 'd', task_dept));
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);

  -- ---------------------------------------------------------------- 9. red view: a failed cron is routed; a page down is platform_down and IS emailed
  update public.rehearsal_window set ended_at = clock_timestamp() - interval '1 second' where ended_at is null or ended_at > clock_timestamp();  -- the alerter holds posts inside a window; closed LOCALLY, rolled back
  r := public.fn_red_view_alert(false);   -- warm-up: whatever stands today is opened and paged on its own
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);
  insert into cron.job_run_details (jobid, runid, job_pid, database, username, command, status, return_message, start_time, end_time)
  values (cron_id, (select coalesce(max(runid),0) + 1 from cron.job_run_details), 0, current_database(), current_user, 'select 1', 'failed', 'ZZ DEMO probe failure', clock_timestamp(), clock_timestamp());
  r := public.fn_red_view_alert(false);
  select count(*) into emails from public.notifications where id > q0 and channel in ('email','whatsapp') and (to_role in ('founder','admin') or lower(to_email) = v_admin);
  select count(*), max(id) into tasks, task_id from public.org_tasks where id > t0 and result->'founder_mail'->>'kind' = 'red_view';
  select assigned_agent, dept_key into task_owner, task_dept from public.org_tasks where id = task_id;
  out := out || jsonb_build_object('9', jsonb_build_object('pg', r->'paged', 'lv', r->'level', 'e', emails, 't', tasks, 'o', task_owner, 'd', task_dept));
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);

  insert into public.health_checks (check_kind, target, ok, status_code, latency_ms, detail, created_at)
  values ('http', 'ZZ DEMO probe page', false, 503, 1, 'founder_mail probe — synthetic outage', clock_timestamp());
  r := public.fn_red_view_alert(false);
  select count(*), string_agg(distinct kind, ',') into emails, k from public.notifications where id > q0 and channel = 'email' and (to_role in ('founder','admin') or lower(to_email) = v_admin);
  select count(*) into wa_rows from public.notifications where id > q0 and channel = 'whatsapp' and (to_role in ('founder','admin'));
  select count(*) into tasks from public.org_tasks where id > t0 and result ? 'founder_mail';
  out := out || jsonb_build_object('10', jsonb_build_object('pg', r->'paged', 'lv', r->'level', 'e', emails, 'k', k, 'wa', wa_rows, 't', tasks));
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);

  -- ---------------------------------------------------------------- 11. a refund approval IS emailed
  r := public.fn_notify_founder('Refund approval needed: AED 250 for ZZ DEMO customer', 'ZZ DEMO probe: a Stripe refund is the one decision that is his', 'high', p_kind => 'refund_approval');
  select count(*), string_agg(distinct kind, ',') into emails, k from public.notifications where id > q0 and channel = 'email' and (to_role in ('founder','admin') or lower(to_email) = v_admin);
  select count(*) into tasks from public.org_tasks where id > t0 and result ? 'founder_mail';
  out := out || jsonb_build_object('11', jsonb_build_object('m', r->>'mode', 'em', r->'emailed', 'e', emails, 'k', k, 't', tasks));
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);

  -- ---------------------------------------------------------------- 12. a caller that names NO kind is routed, never emailed
  r := public.fn_notify_founder('Something the engine invented today', 'ZZ DEMO probe: no kind named', 'high');
  select count(*) into emails from public.notifications where id > q0 and channel in ('email','whatsapp') and (to_role in ('founder','admin') or lower(to_email) = v_admin);
  select count(*), max(id) into tasks, task_id from public.org_tasks where id > t0 and result ? 'founder_mail';
  select assigned_agent, dept_key, result->'founder_mail'->>'registered' into task_owner, task_dept, k from public.org_tasks where id = task_id;
  out := out || jsonb_build_object('12', jsonb_build_object('m', r->>'mode', 'reg', r->'registered', 'e', emails, 't', tasks, 'o', task_owner, 'd', task_dept));
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);

  -- ---------------------------------------------------------------- 13. a legacy producer writing the queue directly, no to_role, his address
  insert into public.notifications (type, to_email, subject, body, status)
  values ('agent_silence', v_admin, 'Scheduled job stopped: zz_demo_probe_legacy', 'ZZ DEMO probe: the pre-policy insert shape', 'pending');
  get diagnostics n = row_count;
  select count(*) into emails from public.notifications where id > q0;
  select count(*), max(id) into tasks, task_id from public.org_tasks where id > t0 and result ? 'founder_mail';
  select assigned_agent, dept_key into task_owner, task_dept from public.org_tasks where id = task_id;
  out := out || jsonb_build_object('13', jsonb_build_object('ins', n, 'q', emails, 't', tasks, 'o', task_owner, 'd', task_dept));
  q0 := (select max(id) from public.notifications); t0 := (select max(id) from public.org_tasks);

  -- ---------------------------------------------------------------- 14. the real queue right now
  select count(*) into n from public.notifications
   where status in ('queued','pending') and channel = 'email'
     and (to_role in ('founder','admin','owner') or lower(to_email) = v_admin)
     and not coalesce((select allowed_to_email from public.founder_mail_policy p where p.kind = coalesce(notifications.kind, notifications.type)), false);
  out := out || jsonb_build_object('14', n,
                                   'rf', (select count(*) from public.founder_alerts where event = 'founder_mail:route_failed'));

  raise exception 'PROBE %', out;
end $probe$;`;

let msg;
try { await sql(probe); }
catch (e) { msg = String(e.message || e); }
if (!msg) { console.error('the probe committed — it must always RAISE'); process.exit(1); }
let text = msg;
try { text = JSON.parse(msg.slice(msg.indexOf('{'))).message; } catch { /* already plain */ }
const m = text.match(/PROBE (\{[\s\S]*\})\s*(?:\nCONTEXT|$)/);
if (!m) { console.error(text); process.exit(1); }
const out = JSON.parse(m[1]);
console.log(JSON.stringify(out, null, 2));
const g = (k) => out[k] || {};
const checks = [
  ['1  scheduled runs failed: 0 founder emails, 1 task for it/product_eng', g('1').e === 0 && g('1').t === 1 && g('1').d === 'product_eng'],
  ['1b same condition again: 0 emails, 0 new tasks, first task bumped',      g('1b').e === 0 && g('1b').nt === 0 && g('1b').seen >= 2],
  ['2  agent silence: 0 founder emails, 1 task for it/product_eng',          g('2').e === 0 && g('2').t === 1 && g('2').d === 'product_eng'],
  ['3  resilience: routed, 0 emails, 1 task for product_eng',               g('3').m === 'routed' && g('3').e === 0 && g('3').t === 1 && g('3').d === 'product_eng'],
  ['4  AI credit low: routed, 0 emails, 1 task for finance',                g('4').m === 'routed' && g('4').e === 0 && g('4').t === 1 && g('4').d === 'finance'],
  ['5  business health: routed, 0 emails, 1 task for exec',                 g('5').m === 'routed' && g('5').e === 0 && g('5').t === 1 && g('5').d === 'exec'],
  ['6  smoke: WhatsApp rows alone no longer trip email_backlog_stuck',      g('6').before && g('6').before.stuck === false],
  ['6b smoke: a stuck EMAIL trips it, 0 founder emails, 1 task for product_eng', g('6').after && g('6').after.stuck === true && g('6').e === 0 && g('6').t === 1 && g('6').d === 'product_eng'],
  ['7  backup missed once: 0 emails, 1 task (backup_alert) for product_eng', g('7').e === 0 && g('7').t === 1 && g('7').kind === 'backup_alert' && g('7').d === 'product_eng'],
  ['7b backup failing after retry: exactly 1 email (backup_failed_after_retry), task bumped not doubled', g('7b').e === 1 && g('7b').k === 'backup_failed_after_retry' && g('7b').nt === 0 && g('7b').seen >= 2],
  ['8  stalled handoff: 0 emails, 1 task for the receiving lead (growth), both runs one condition', g('8').e === 0 && g('8').t === 1 && g('8').d === 'growth' && g('8').seen === 2],
  ['9  red view (cron failed): 0 emails, 1 task for product_eng',           g('9').e === 0 && g('9').t === 1 && g('9').d === 'product_eng'],
  ['10 platform down: exactly 1 email (platform_down), 0 tasks',           g('10').e === 1 && g('10').k === 'platform_down' && g('10').t === 0],
  ['11 refund approval: exactly 1 email (refund_approval), 0 tasks',        g('11').e === 1 && g('11').k === 'refund_approval' && g('11').t === 0],
  ['12 no kind named: routed (unregistered), 0 emails, 1 task',            g('12').m === 'routed' && g('12').reg === false && g('12').e === 0 && g('12').t === 1],
  ['13 legacy direct insert: 0 rows queued, 1 task for product_eng',       g('13').q === 0 && g('13').t === 1 && g('13').d === 'product_eng'],
  ['14 the real queue holds 0 non-policy founder emails',                  out['14'] === 0],
];
let bad = 0;
for (const [name, ok] of checks) { console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}`); if (!ok) bad++; }
process.exit(bad ? 1 : 0);
