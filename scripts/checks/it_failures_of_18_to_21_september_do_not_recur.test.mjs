// THE IT FAILURES OF 18–21 SEPTEMBER 2026 DO NOT COME BACK.
//
// The founder received 25 IT emails in four days; docs/it/IT_FAILURES_18_21_SEP_2026.md groups them
// into their causes. Each test here fails if one of the fixed causes re-opens:
//   1. the liveness check reads the SCHEDULER (agent_runs fn:resilience_ping), never the detector's
//      own it_watch_tick — the 20 and 21 Sep "SCHEDULER DOWN" pages were a blind detector read as a
//      dead scheduler;
//   2. fn_it_detect survives one subject flooding agent_runs: 20,000 rows for a throw-away subject
//      are injected inside a rolled-back transaction and the routine must still finish under 6,000 ms
//      — the same bar it_engineer_loop_is_closed.test.mjs holds, on a worse table;
//   3. the CEO answers the two report families that had no decider — a synthetic report of each is
//      decided inside a rolled-back transaction — and an unknown family answers "no decider" and is still
//      answered by the CEO's default decision (#933), never left 'sent';
//   4. send_whatsapp records Twilio's SID as provider_message_id, so no WhatsApp send is
//      'sent_unconfirmed' again (source anchor, not prose);
//   5. resilience_ping calls send_whatsapp on every tick, so the subject has a pulse for the
//      run_silent arm to measure (source anchor: the early return on an empty queue is gone);
//   6. the slow-statement duty leaves out statements stamped by the management API (source anchor).
//
// Against production. Every write is inside a transaction that ends in `raise exception 'CHK<<…>>'`,
// so nothing commits; the result is read out of the error text. No real row is changed.
//
//   node --test scripts/checks/it_failures_of_18_to_21_september_do_not_recur.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

async function probe(body) {
  try {
    await sql(`do $p$ ${body} $p$;`);
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (m) return JSON.parse(m[1].replace(/\\"/g, '"'));
    throw e;
  }
  throw new Error('probe committed instead of rolling back: it must end in raise exception CHK<<...>>');
}

const src = (rel) => readFileSync(join(process.cwd(), rel), 'utf8');

test('the liveness check reads the scheduler from its own rows, not the detector', { skip: SKIP }, async () => {
  const [r] = await sql(`select pg_get_functiondef('public.fn_cron_liveness()'::regprocedure) d,
                                public.fn_cron_liveness() live`);
  assert.ok(r.d.includes(`where agent = 'fn:resilience_ping'`), 'fn_cron_liveness does not read agent_runs fn:resilience_ping');
  assert.ok(!r.d.includes('from public.it_watch_tick'), 'fn_cron_liveness reads it_watch_tick, which is the detector, not the scheduler');
  // 27 Oct 2026: either of the routine's two SCHEDULER sources, never the detector. fn_cron_liveness takes the later
  // of the resilience tick and cron.job_run_details ("taking pg_cron as the later of the two sources if it is ever
  // revived", scripts/sql/the_liveness_check_reads_the_scheduler_not_the_detector.sql). pg_cron was empty when this
  // was written (21 Sep); it was revived with the seat duties' own jobs (one_slow_duty_never_wedges_the_seat_duty_tick.sql,
  // 18 Oct, 42 seat_duty:* jobs) and the schedules moved off GitHub (#1597), so outside the minutes just after a
  // quarter-hour tick a */5 job is newer and the source reads pg_cron by design (27 Oct run: "pg_cron
  // (cron.job_run_details)"). What this test guards - the detector is not read - is the two assertions above.
  assert.match(String(r.live.source || ''), /^(resilience tick|pg_cron \(cron\.job_run_details\))/, `liveness source is ${r.live.source}`);
});

test('fn_it_detect finishes under 6 s even when one subject floods agent_runs', { skip: SKIP }, async () => {
  const r = await probe(`
    declare t0 timestamptz; v_ms numeric; v jsonb;
    begin
      set local statement_timeout = '30s';
      insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
      select 'fn:zz_demo_flood', 'ok', now() - (g || ' seconds')::interval, now() - (g || ' seconds')::interval + interval '1 second',
             '{"http":200,"ms":1000}'::jsonb, 'ZZ DEMO flood probe'
        from generate_series(60, 20059) g;
      t0 := clock_timestamp();
      v := public.fn_it_detect(null, false);
      v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
      raise exception 'CHK<<%>>', json_build_object('detect_ms', round(v_ms),
        'slice_basis', v -> 'notes' -> 'slice' ->> 'basis',
        'capped', (v -> 'notes' -> 'slice' ->> 'subjects_capped')::int,
        -- only ticks THIS transaction could have written: fn_it_detect stamps ran_at with now(), the
        -- transaction's start. The scheduled tick commits rows of its own, and on 22 Sep 2026 one landing
        -- inside the old "last 30 s" window read as 1 and failed a probe that had written none.
        'ticks_written', (select count(*) from public.it_watch_tick where ran_at = now()));
    end`);
  assert.equal(r.slice_basis, 'measured', 'fn_it_detect publishes no notes.slice: the bounded slice is gone');
  assert.ok(r.capped >= 1, 'a 20,000-row subject was not capped');
  assert.ok(r.detect_ms < 6000, `fn_it_detect took ${r.detect_ms} ms under a 20,000-row flood; PostgREST cancels it at 8000`);
  assert.equal(r.ticks_written, 0);
});

test('the CEO decides the delivery_undelivered and dropbox_backup_escalation families; an unknown family says so', { skip: SKIP }, async () => {
  const r = await probe(`
    declare v_nid bigint; v_tid bigint; v_r1 bigint; v_r2 bigint; v_r3 bigint; d1 jsonb; d2 jsonb; d3 jsonb; s1 text; s2 text; s3 text;
    begin
      insert into public.notifications (type, kind, to_email, to_role, channel, subject, body, status, sent_at, requested_by)
      values ('founder_alert', 'platform_down', 'zz-demo-founder@example.invalid', 'founder', 'email', 'ZZ DEMO', 'ZZ DEMO', 'sent', now(), 'platform')
      returning id into v_tid;
      update public.notifications set provider_message_id = 'zz-demo-pmid' where id = v_tid;
      insert into public.notifications (type, kind, to_email, to_role, channel, to_phone, subject, body, status, sent_at, requested_by, created_at)
      select 'founder_alert', 'platform_down', 'zz-demo-founder@example.invalid', 'founder', 'whatsapp', '+971500000099', 'ZZ DEMO', 'ZZ DEMO', 'sent', now(), 'platform', created_at
        from public.notifications where id = v_tid returning id into v_nid;
      insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions, requested_outcome, next_review_at, status, owner_role_id)
      values ('delivery_undelivered:zzprobe' || v_nid, 'it_engineer', 'elevated', 'ZZ DEMO did not arrive',
              jsonb_build_object('rechecked', jsonb_build_object('notification_id', v_nid), 'result', 'sent_unconfirmed'), '[]'::jsonb, 'probe', now() - interval '1 minute', 'sent', 'ceo')
      returning id into v_r1;
      insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions, requested_outcome, next_review_at, status, owner_role_id)
      values ('dropbox_backup_escalation:zzprobe' || v_nid, 'it_engineer', 'serious', 'ZZ DEMO coverage',
              jsonb_build_object('probe', true, 'failing', '[]'::jsonb), '[]'::jsonb, 'probe', now() - interval '1 minute', 'sent', 'ceo')
      returning id into v_r2;
      insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions, requested_outcome, next_review_at, status, owner_role_id)
      values ('zz_probe_family:' || v_nid, 'it_engineer', 'elevated', 'ZZ DEMO unknown', jsonb_build_object('probe', true), '[]'::jsonb, 'probe', now() - interval '1 minute', 'sent', 'ceo')
      returning id into v_r3;
      d1 := public.fn_ceo_decide_report(v_r1); d2 := public.fn_ceo_decide_report(v_r2); d3 := public.fn_ceo_decide_report(v_r3);
      select status into s1 from public.support_ceo_report where id = v_r1;
      select status into s2 from public.support_ceo_report where id = v_r2;
      select status into s3 from public.support_ceo_report where id = v_r3;
      raise exception 'CHK<<%>>', json_build_object('d1', d1->>'ok', 's1', s1, 'd2', d2->>'ok', 's2', s2, 'd3', coalesce(d3->'family_answer'->>'reason', d3->>'reason'), 's3', s3);
    end`);
  assert.equal(r.d1, 'true'); assert.equal(r.s1, 'accepted', 'a sent_unconfirmed WhatsApp with a confirmed email twin was not accepted');
  assert.equal(r.d2, 'true'); assert.equal(r.s2, 'accepted', 'the daily coverage report was not answered');
  // Since #933 (24 Sep 2026, ledger 983) the CEO answers every report the day it arrives: a family with no decider
  // says so in family_answer and is then accepted by fn_ceo_report_default_decide, never left 'sent'.
  assert.equal(r.d3, 'no decider for this family'); assert.equal(r.s3, 'accepted');
});

test('the silence watch lets the CEO answer first and pages a family once a day', { skip: SKIP }, async () => {
  const [r] = await sql(`select pg_get_functiondef('public.fn_it_ceo_silence_watch()'::regprocedure) d`);
  assert.ok(r.d.includes('public.fn_ceo_decide_report(r.id)'), 'the silence watch no longer asks the CEO before paging');
  assert.ok(r.d.includes(`'it_ceo_silent:' || split_part(r.idempotency_key, ':', 1)`), 'the page is deduped per report id, not per family and day');
});

test('send_whatsapp stores the Twilio SID, and resilience_ping calls it every tick', () => {
  const wa = src('supabase/functions/send_whatsapp/index.ts');
  assert.ok(/provider_message_id:\s*res\.ok\s*\?\s*\(res\.sid\s*\|\|\s*null\)/.test(wa), 'send_whatsapp does not store res.sid as provider_message_id');
  const rp = functionSource('resilience_ping');
  const tick = rp.slice(rp.indexOf('async function whatsappTick'), rp.indexOf('async function whatsappTick') + 1500);
  assert.ok(!/if \(!count\) return/.test(tick), 'whatsappTick returns early on an empty queue: the subject beats only under load');
});

test('the slow-statement duty leaves out statements stamped by the management API', { skip: SKIP }, async () => {
  const [r] = await sql(`select pg_get_functiondef('public.fn_it_duties_scheduled(jsonb)'::regprocedure) d`);
  assert.ok(r.d.includes('where not s.operator_session'), 'db_health raises operator-session statements again');
  assert.ok(r.d.includes('db_health_operator_statements_excluded'), 'the excluded count is not published');
});
