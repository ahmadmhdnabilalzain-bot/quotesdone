#!/usr/bin/env node
// it_engineer — 100 concurrent website chats with the model STUBBED (founder ruling 1622; ruling 1606: no model money).
// Opens a LOAD window, runs ramp_driver's chat mix inside it, then tears everything down and proves it. Report:
// docs/reports/2026-11-11-load-test.md.
//
// NEEDS DEPLOYED FIRST: ai_gateway and site_assistant from the branch that added _shared/load_stub.ts. The driver's
// preflight refuses to start otherwise (a gateway without the stub answers the preflight with the no-cost
// fixture_no_spend, measured 11 Nov 2026), so running this early costs nothing and sends no chat turn.
//
// THE WINDOW. rehearsal_window (run_tag 'qd_run:<tag>', opened_by 'load_test', models_allowed FALSE, cap_usd 0.01, 45 min,
// note 'delay_ms=6000-10000'). models_allowed=false means fn_e2e_run_tag_open is false for it, so nothing in the estate
// that lets a TEST reach a model can ever treat this window as one; only _shared/load_stub.ts reads it, and only to stub.
// TEARDOWN, in a finally (and on SIGINT/SIGTERM): demo_factory.teardown(run) for the tag, the run's own widget
// conversations by id (assistant_logs.conv_id), its limiter rows (rl_hits 'load:<tag>:%'), then the window is closed.
// PROOF: no notification created since the run started names the run or carries the canned reply (nothing queued or
// dispatched), and every table the teardown touched is counted again and must be 0 for the run.
//   QD_FIXTURES=1 NODE_USE_ENV_PROXY=1 QD_LOAD_ANON_KEY=... QD_LOAD_RUN_SECRET=<cred_db_internal> \
//   QD_LOAD_GATEWAY_SECRET=<cred_fn_ai> node scripts/load/chat_load_run.mjs --stages=10,50,100 --stage-seconds=90 --out=<scratch>/chat.json
import { loadLimiterKeys } from '../../supabase/functions/_shared/load_stub.ts';
import { randomBytes } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { closeOnExit, closeRehearsalWindow, newRun, teardown } from '../lib/demo_factory.mjs';
import { mgmtFixture } from '../lib/qd_guard.mjs';
import { mgmtQuery, run as runMix } from './ramp_driver.mjs';

const REF = 'htdblwldjkcgjvmqkbeh';
const uuidList = (ids) => ids.filter((x) => /^[0-9a-f-]{36}$/.test(x)).map((x) => `'${x}'`).join(',') || `''`;
export const openWindowSql = (tag, minutes = 45) => {
  if (!/^zzload[a-z0-9]{2,10}$/.test(tag)) throw new Error('prevented by: a load window tag starts zzload: ' + tag);
  return `insert into public.rehearsal_window (run_tag, opened_by, models_allowed, cap_usd, expires_at, note)
    values ('qd_run:${tag}', 'load_test', false, 0.01, now() + make_interval(mins => ${Math.min(120, minutes | 0)}), 'delay_ms=6000-10000 | ruling 1622 load test, model stubbed')`;
};
// The real outbox keeps moving rows between statuses during a run (measured 11 Nov 2026: queued 204 -> 200, sent
// 1158 -> 1163 in 30 minutes, none of it ours), so the proof is "no notification CREATED since the run started that names
// the run", not "the status counts are equal".
const census = async (env, tag, convs, since = new Date().toISOString()) => (await mgmtQuery(env, `select
  (select count(*) from public.notifications n where n.created_at >= '${since}'::timestamptz and (to_jsonb(n)::text ilike '%${tag}%' or to_jsonb(n)::text ilike '%sandbox load-test reply%')) notifications,
  (select count(*) from public.assistant_logs where conv_id in (${uuidList(convs)}) or e2e_run_tag = 'qd_run:${tag}' or e2e_run_tag = '${tag}') assistant_logs,
  (select count(*) from public.rl_hits where k like '${loadLimiterKeys(tag)}') rl_hits`))[0];

async function main(argv, env) {
  if (env.QD_FIXTURES !== '1') throw new Error('prevented by: QD_FIXTURES is not 1 (this opens a window and writes demo rows)');
  const arg = (k, d) => (argv.find((a) => a.startsWith(`--${k}=`)) || '').split('=')[1] || d;
  const r = newRun({ tag: 'zzload' + randomBytes(3).toString('hex') });
  const tag = r.tag;
  const runEnv = { ...env, QD_LOAD_RUN_TAG: tag };
  let convs = [];
  const startedAt = new Date().toISOString();
  const before = await census(runEnv, tag, [], startedAt);
  console.log(`chat load run ${tag}; before: ${JSON.stringify(before)}`);
  const close = async () => {
    try { await teardown(r); } catch (e) { console.error('teardown: ' + e.message); }
    if (convs.length) await mgmtFixture(REF, `delete from public.assistant_logs where conv_id in (${uuidList(convs)})`, 'load chat turns');
    // the bucket name comes first in a key ('site_assistant_ipconv:load:<tag>:...'): 'load:<tag>:%' left every run's rows behind
    await mgmtFixture(REF, `delete from public.rl_hits where k like '${loadLimiterKeys(tag)}'`, 'load limiter rows');
    await closeRehearsalWindow(tag);
  };
  const disarm = closeOnExit(close);
  let result;
  try {
    await mgmtFixture(REF, openWindowSql(tag), 'load window');
    result = await runMix({ mixName: 'chat', stages: arg('stages', '10,50,100').split(',').map(Number),
      stageSeconds: Number(arg('stage-seconds', '90')), env: runEnv, out: arg('out', '') });
    convs = result.convs ?? [];
  } finally {
    disarm();
    await close();
  }
  const after = await census(runEnv, tag, convs, startedAt);
  console.log(`after: ${JSON.stringify(after)}`);
  if (Number(after.notifications)) throw new Error('prevented by: the run queued ' + after.notifications + ' notification(s)');
  if (Number(after.assistant_logs) || Number(after.rl_hits)) throw new Error('prevented by: the run left rows behind: ' + JSON.stringify(after));
  return result?.aborted ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2), process.env).then((c) => process.exit(c), (e) => { console.error(e.message); process.exit(2); });
}
