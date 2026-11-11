#!/usr/bin/env node
// it_engineer — concurrent inquiry writes against production that COMMIT NOTHING (founder ruling 1622; report
// docs/reports/2026-11-11-load-test.md). Each probe is one DO block, run over the management API, that inserts a
// ZZ DEMO customer at @example.invalid and a 'sent' inquiry for it (every BEFORE/AFTER trigger on both tables fires),
// runs the matcher's own SQL (fn_match_capability, what sales_engineer 'match' calls), and then RAISES with its timings,
// so the whole transaction rolls back: no row, no queued notification, no pg_net request survives (the queue tables are
// written in the same transaction). Bursts of N probes start together; the driver reports the per-step p50/p95/max.
//
// Proof it left nothing: before and after, it counts the run's customers and inquiries and every notification created
// since the start that names a load probe; the two must match (assertNothingLeft) or the script exits 1.
//   NODE_USE_ENV_PROXY=1 node scripts/load/db_write_burst.mjs --run --bursts=1,10,25,50 --rounds=3 --out=<scratch>/db.json
import { randomBytes } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export const RUN = 'zzload' + randomBytes(3).toString('hex');
/** The probe. `k` makes each address unique; nothing in it can commit, because every path ends in a raise. */
export function probeSql(k, run = RUN) {
  const email = `qd-${run}-c${k}@example.invalid`;
  if (!/^qd-zzload[0-9a-f]{6}-c\d+@example\.invalid$/.test(email)) throw new Error('prevented by: the probe address is not a load fixture: ' + email);
  return `do $probe$
declare c uuid; i uuid; mt int; t0 timestamptz := clock_timestamp(); t1 timestamptz; t2 timestamptz; t3 timestamptz;
begin
  set local statement_timeout = '25s';
  insert into public.customers(full_name, email, locale) values ('ZZ DEMO — load probe ${k}', '${email}', 'en') returning id into c;
  t1 := clock_timestamp();
  insert into public.inquiries(customer_id, category, emirate, role_needed, raw_input, summary, status, scope_type, lang)
  values (c, 'plumbing', 'Dubai', 'supplier', 'ZZ DEMO — load probe: a leaking pipe under the kitchen sink', 'ZZ DEMO leaking pipe', 'sent', 'single', 'en')
  returning id into i;
  t2 := clock_timestamp();
  select count(*) into mt from public.fn_match_capability(array['plumbing'], 'executes', '{}'::text[], '{}'::text[], null, null, 'Dubai', 500, '{}'::text[]);
  t3 := clock_timestamp();
  raise exception 'CHK<<%>>', json_build_object('customer_ms', round(extract(epoch from t1 - t0) * 1000), 'inquiry_ms', round(extract(epoch from t2 - t1) * 1000),
    'match_ms', round(extract(epoch from t3 - t2) * 1000), 'total_ms', round(extract(epoch from t3 - t0) * 1000), 'matches', mt);
end $probe$;`;
}
export function parseProbe(text) {
  let msg = String(text);
  try { const j = JSON.parse(msg); msg = String(j?.message ?? j?.error ?? msg); } catch { /* a plain-text body */ }
  const m = /CHK<<(\{.*?\})>>/.exec(msg);
  return m ? JSON.parse(m[1]) : null;
}
export function assertNothingLeft(before, after) {
  const a = JSON.stringify(before), b = JSON.stringify(after);
  if (a !== b) throw new Error('prevented by: the burst left something behind: before ' + a + ' after ' + b);
  return true;
}

const env = process.env;
async function q(sql, readOnly = false) {
  const t0 = performance.now();
  const r = await fetch(`https://api.supabase.com/v1/projects/${env.SUPABASE_PROJECT_REF || 'htdblwldjkcgjvmqkbeh'}/database/query`, {
    method: 'POST', headers: { authorization: 'Bearer ' + env.SUPABASE_ACCESS_TOKEN, 'content-type': 'application/json' },
    body: JSON.stringify({ query: sql, read_only: readOnly }), signal: AbortSignal.timeout(60000),
  });
  return { status: r.status, text: await r.text(), ms: Math.round(performance.now() - t0) };
}
// Not the notification status counts: the real outbox moves rows between statuses while a burst runs (measured 11 Nov
// 2026). What must not move is any row this run could have made: its customers, its inquiries, and a notification
// created since the start that names a load probe.
const STARTED = new Date().toISOString();
const census = async () => rowsOf(await q(`select
  (select count(*) from public.notifications n where n.created_at >= '${STARTED}'::timestamptz and to_jsonb(n)::text ilike '%load probe%') as notifications,
  (select count(*) from public.customers where email like 'qd-zzload%@example.invalid') as load_customers,
  (select count(*) from public.inquiries where raw_input like 'ZZ DEMO — load probe%') as load_inquiries`, true))[0];
function rowsOf(r) {
  try { const j = JSON.parse(r.text); if (Array.isArray(j)) return j; } catch { /* below */ }
  throw new Error('census query failed: HTTP ' + r.status + ' ' + r.text.slice(0, 200));
}
const pct = (a, p) => { const s = [...a].sort((x, y) => x - y); return s.length ? s[Math.min(s.length - 1, Math.ceil(p * s.length) - 1)] : null; };

async function main(argv) {
  const arg = (k, d) => (argv.find((a) => a.startsWith(`--${k}=`)) || '').split('=')[1] || d;
  const bursts = arg('bursts', '1,10,25,50').split(',').map(Number);
  const rounds = Number(arg('rounds', '3'));
  console.log(`db write burst ${RUN}: bursts ${bursts.join(',')} x ${rounds} rounds; sample probe:\n` + probeSql(0).split('\n').slice(0, 4).join('\n'));
  if (!argv.includes('--run')) { console.log('dry run — nothing sent. Add --run.'); return 0; }
  const before = await census();
  const out = { run: RUN, before, stages: [] };
  let k = 0;
  for (const n of bursts) {
    const res = [];
    for (let r = 0; r < rounds; r++) {
      const got = await Promise.all(Array.from({ length: n }, () => q(probeSql(k++))));
      res.push(...got);
      await new Promise((s) => setTimeout(s, 2000));
    }
    const ok = res.map((x) => ({ ...x, p: parseProbe(x.text) }));
    const good = ok.filter((x) => x.p);
    const col = (f) => good.map((x) => x.p[f]);
    const st = {
      concurrent: n, probes: res.length, rolled_back_with_timings: good.length,
      other: ok.filter((x) => !x.p).map((x) => x.status + ' ' + x.text.slice(0, 160)).slice(0, 5),
      round_trip_ms: { p50: pct(res.map((x) => x.ms), 0.5), p95: pct(res.map((x) => x.ms), 0.95), max: Math.max(...res.map((x) => x.ms)) },
    };
    for (const f of ['customer_ms', 'inquiry_ms', 'match_ms', 'total_ms']) st[f] = { p50: pct(col(f), 0.5), p95: pct(col(f), 0.95), p99: pct(col(f), 0.99), max: Math.max(...col(f)) };
    st.matches = [...new Set(col('matches'))];
    out.stages.push(st);
    console.log(JSON.stringify(st));
  }
  out.after = await census();
  const arg2 = arg('out', '');
  if (arg2) writeFileSync(arg2, JSON.stringify(out, null, 1));
  assertNothingLeft(before, out.after);
  console.log('nothing left behind: ' + JSON.stringify(out.after));
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).then((c) => process.exit(c), (e) => { console.error(e.message); process.exit(1); });
}
