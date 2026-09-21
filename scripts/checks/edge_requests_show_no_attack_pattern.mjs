// ATTACK PATTERNS IN THE EDGE LOGS — 9 September 2026.  Agent: ceo.
//
// The founder, 9 Sep 2026: "he should be able to monitor cyber attacks or hackers ... he monitor
// literally everything in the app and the website."
//
// The 64 edge functions are the public surface of this company. Every request to any of them lands
// in Supabase's `edge_logs`, with the caller's IP, the path and the status — and nothing read it.
// The two attacks that actually reach a marketplace's API before it has customers are CREDENTIAL
// STUFFING (a burst of 401/403 from one address) and ENDPOINT ENUMERATION (one address walking many
// paths that do not exist). Both are visible in that log and neither needs a model to spot.
//
// ── THE THRESHOLDS ARE MEASURED, NOT GUESSED ───────────────────────────────────────────────────
// Measured on production over the 24 hours to 09 Sep 2026 07:00 UTC: 6,630 requests, of which 26
// were 403, 24 were 400 and 4 were 404 — and the WORST single IP produced exactly ONE error
// response. The busiest address made 1,038 requests in the whole day.
//
// So the bars below sit an order of magnitude above anything this estate has ever produced:
//   * 10 responses in {401,403} from one IP in one hour   (observed peak: 1)
//   * 10 distinct 404 paths from one IP in one hour       (observed peak: 1)
//
// DELIBERATELY ABSENT, and said rather than implied: a raw REQUEST-VOLUME rule. The busiest address
// in the estate is the operator's own, and a rule that fires when the company works is worse than
// no rule — it is the failure this repository already has a name for. Rate limiting belongs at the
// edge (see public.security_gap 'edge_waf_has_no_rules'), not in a detector that would page on us.
//
// ── WHY THIS IS A SCRIPT AND NOT AN EDGE FUNCTION ──────────────────────────────────────────────
// edge_logs is reachable only through the management analytics API, which needs the management
// token. No edge function has one, and copying one into app_secrets would widen a service-role leak
// to the whole Supabase account. Same trade, same reasoning and same record as the advisor
// baseline: public.security_gap, 'advisors_unreadable_from_the_runtime'.
//
// Findings are written to public.security_events through the SAME fingerprinted pipeline as every
// other detection, so they are deduplicated across runs and read by fn_security_watch().
//
//   node scripts/checks/edge_requests_show_no_attack_pattern.mjs             # last 24h, report
//   node scripts/checks/edge_requests_show_no_attack_pattern.mjs --record    # and write the events
//   node scripts/checks/edge_requests_show_no_attack_pattern.mjs --hours=6
//
// Exit 0 when no pattern is present, 1 when one is, 2 when the LOG ITSELF could not be read — a
// log that cannot be queried is not a quiet estate, and must never be reported as one.
import { readFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { sql, PROJECT_REF } from '../lib/db.mjs';
import { withRetry } from '../lib/retry.mjs';

const arg = (n, d) => { const a = process.argv.find((x) => x.startsWith(`--${n}=`)); return a ? a.slice(n.length + 3) : d; };
const HOURS = Math.max(1, Math.min(24, Number(arg('hours', 24)) || 24));
const RECORD = process.argv.includes('--record');
const AUTH_FAILURES_PER_HOUR = 10;   // observed peak 1
const MISSING_PATHS_PER_HOUR = 10;   // observed peak 1

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  if (existsSync(p)) return readFileSync(p, 'utf8').trim();
  throw new Error('No Supabase access token (SUPABASE_ACCESS_TOKEN or ~/.supabase/access-token).');
}

// THREE ATTEMPTS BEFORE "UNREADABLE" (21 Sep 2026). One request to the analytics endpoint was the
// whole verdict: a single transient miss (a 5xx, a dropped socket) reported the log unreadable, turned
// the parity job red and emailed the founder. A miss is now retried twice, 2 s then 4 s apart. A log
// that is STILL unreadable after the third attempt exits 2 exactly as before: the gate is not
// weakened, a blip just stops counting as an outage. withRetry is tested in scripts/lib/retry.test.mjs.
// FIVE ATTEMPTS, 5 s DOUBLING (21 Sep 2026, run 35637779273): five PRs' CI read the logs at once and the
// management API answered HTTP 429 three times inside 7 s — its throttle window is about a minute, so
// 2 s + 4 s could never outlast it. 5+10+20+40 s = 75 s now spans the window; the gate itself is unchanged.
const logs = (query) => withRetry(() => logsOnce(query), 5, 5000);

async function logsOnce(query) {
  // The window MUST be explicit. Without iso_timestamp_start the endpoint answers over a very short
  // default window and returns [] — which reads exactly like "no attacks" and is not.
  const end = new Date().toISOString();
  const start = new Date(Date.now() - HOURS * 3600e3).toISOString();
  const u = `https://api.supabase.com/v1/projects/${PROJECT_REF}/analytics/endpoints/logs.all`
          + `?sql=${encodeURIComponent(query)}`
          + `&iso_timestamp_start=${encodeURIComponent(start)}&iso_timestamp_end=${encodeURIComponent(end)}`;
  const r = await fetch(u, { headers: { Authorization: `Bearer ${token()}` } });
  const text = await r.text();
  let j; try { j = JSON.parse(text); } catch { j = null; }
  if (!r.ok || !j || j.error || !Array.isArray(j.result)) {
    throw new Error(`edge_logs unreadable: HTTP ${r.status} ${text.slice(0, 200)}`);
  }
  return j.result;
}

const FROM = `from edge_logs t
  cross join unnest(t.metadata) m
  cross join unnest(m.response) r
  cross join unnest(m.request) req
  cross join unnest(req.headers) h`;

let total, authBursts, sweeps;
try {
  // POSITIVE CONTROL FIRST. A detector that reports "no attack" against a log it is not actually
  // reading is indistinguishable from one that is switched off, so the run asserts the log has
  // traffic in it before it is allowed to report a clean window.
  const t = await logs(`select count(*) as n ${FROM}`);
  total = Number(t?.[0]?.n || 0);
  if (total === 0) {
    console.error(`edge_logs returned 0 requests over the last ${HOURS}h. This project serves `
                + 'traffic continuously, so that is an instrument failure, not a quiet estate.');
    process.exit(2);
  }
  authBursts = await logs(
    `select h.cf_connecting_ip as ip, timestamp_trunc(t.timestamp, HOUR) as hr, count(*) as n
     ${FROM} where r.status_code in (401, 403)
     group by ip, hr having count(*) >= ${AUTH_FAILURES_PER_HOUR} order by n desc limit 50`);
  sweeps = await logs(
    `select h.cf_connecting_ip as ip, timestamp_trunc(t.timestamp, HOUR) as hr,
            count(distinct req.path) as paths, count(*) as n
     ${FROM} where r.status_code = 404
     group by ip, hr having count(distinct req.path) >= ${MISSING_PATHS_PER_HOUR}
     order by paths desc limit 50`);
} catch (e) {
  console.error(String(e.message || e));
  process.exit(2);
}

const q = (s) => `'${String(s ?? '').replace(/'/g, "''")}'`;
const hourKey = (hr) => new Date(typeof hr === 'number' ? hr / 1000 : hr).toISOString().slice(0, 13).replace(/[-T:]/g, '');

const findings = [
  ...authBursts.map((r) => ({
    kind: 'auth_failure_burst', severity: 'high', ip: r.ip,
    fp: `edge_auth:${r.ip}:${hourKey(r.hr)}`,
    detail: { failures: Number(r.n), hour: r.hr, threshold: AUTH_FAILURES_PER_HOUR, observed_peak_before_this_rule: 1 },
    line: `${r.ip} produced ${r.n} 401/403 responses in one hour (bar ${AUTH_FAILURES_PER_HOUR})`,
  })),
  ...sweeps.map((r) => ({
    kind: 'endpoint_enumeration', severity: 'medium', ip: r.ip,
    fp: `edge_sweep:${r.ip}:${hourKey(r.hr)}`,
    detail: { distinct_missing_paths: Number(r.paths), requests: Number(r.n), hour: r.hr,
              threshold: MISSING_PATHS_PER_HOUR, observed_peak_before_this_rule: 1 },
    line: `${r.ip} asked for ${r.paths} distinct paths that do not exist in one hour (bar ${MISSING_PATHS_PER_HOUR})`,
  })),
];

if (RECORD && findings.length) {
  const vals = findings.map((f) =>
    `(${q(f.kind)}, ${q(f.severity)}, 'supabase_edge_logs', ${q(f.ip)}, ${q(JSON.stringify(f.detail))}::jsonb, ${q(f.fp)})`);
  await sql(`insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
             values ${vals.join(',')} on conflict (fingerprint) do nothing`);
}

console.log(`edge_logs on ${PROJECT_REF}: ${total} requests over the last ${HOURS}h`);
console.log(`  auth-failure bursts   ${authBursts.length}`);
console.log(`  endpoint enumeration  ${sweeps.length}`);
for (const f of findings) console.log(`  ${f.severity.toUpperCase().padEnd(6)} ${f.kind} — ${f.line}`);
if (findings.length && !RECORD) console.log('re-run with --record to write these to security_events.');
process.exit(findings.length ? 1 : 0);
