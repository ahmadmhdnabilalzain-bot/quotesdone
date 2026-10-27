// IS ANYTHING STILL SENDING A LEGACY (HS256) KEY? (it_engineer, 27 Oct 2026). Assigned: it_engineer.
//
// Step B of closing the leaked legacy JWT secret (docs/reports/security/SECURITY_HARDENING_27_OCT.md item 3). After
// the PR that moved every consumer to the publishable and secret keys is deployed, the release operator runs this
// until it reports ZERO for a full 24 to 48 h. Only then: disable the legacy keys (step C1), then revoke the HS256
// signing key (step C2). It reads the API gateway's edge_logs through the Management API; it writes nothing and
// prints no key (the logs hold only the decoded JWT header and claims, never the token).
//
//   node scripts/it/hs256_traffic_since_the_key_move.mjs              # the last 24 h
//   node scripts/it/hs256_traffic_since_the_key_move.mjs --hours=48   # the last 48 h (read in 24 h windows)
//   node scripts/it/hs256_traffic_since_the_key_move.mjs --since=2026-10-28T09:00:00Z
//
// Exit 0: zero HS256 requests in the window (outside Supabase's own /admin/* paths), so the window counts.
// Exit 1: some remain; the table names who (network, user agent, role) and where (path), so the consumer can be
//         found. Exit 2: the logs could not be read; that is not a zero.
//
// The query is the report's (SECURITY_HARDENING_27_OCT.md, step B), grouped further by role and user agent. The
// endpoint is GET /v1/projects/{ref}/analytics/endpoints/logs (logs.all was removed by Supabase; measured 27 Oct
// 2026: HTTP 410 on the old path). Measured 27 Oct 2026, 24 h before the move: ~11,000 service_role from
// "Anthropic, PBC" Deno/2.9.4 (cloud-session scripts), ~5,100 from a UAE node client (silent since 05:00 UTC),
// ~1,000 from "Google LLC" node, ~150 from the Vercel cron and the edge runtime relaying it.
import { supabaseAccessToken } from '../lib/supabase_token.mjs';
import { PROJECT_REF } from '../lib/db.mjs';

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3);
const end = new Date();
const start = arg('since') ? new Date(arg('since')) : new Date(end.getTime() - Number(arg('hours') || 24) * 3600e3);
if (Number.isNaN(start.getTime()) || start >= end) { console.error('--since/--hours must name a moment in the past'); process.exit(2); }

const HS256 = `(log_attributes['request.sb.jwt.apikey.payload.algorithm'] = 'HS256'
      or log_attributes['request.sb.jwt.authorization.payload.algorithm'] = 'HS256')
  and log_attributes['request.path'] not like '/admin/%'`;
// The total is its own count(): grouping by path first and summing would lose the tail, because every storage
// object is its own path (measured 27 Oct 2026: a 200-group cut read 13,034 of 19,150).
const ROLE = `coalesce(nullif(log_attributes['request.sb.jwt.apikey.payload.role'], ''), log_attributes['request.sb.jwt.authorization.payload.role'])`;
export const QUERIES = {
  total: `select count() n from logs where source = 'edge_logs' and ${HS256}`,
  who: `select ${ROLE} role, log_attributes['request.cf.asOrganization'] org, log_attributes['request.headers.user_agent'] ua, count() n
    from logs where source = 'edge_logs' and ${HS256} group by role, org, ua order by n desc limit 100`,
  where: `select ${ROLE} role, log_attributes['request.path'] p, count() n
    from logs where source = 'edge_logs' and ${HS256} group by role, p order by n desc limit 40`,
};

async function window(query, from, to) {
  const u = new URL(`https://api.supabase.com/v1/projects/${PROJECT_REF}/analytics/endpoints/logs`);
  u.searchParams.set('sql', query);
  u.searchParams.set('iso_timestamp_start', from.toISOString());
  u.searchParams.set('iso_timestamp_end', to.toISOString());
  for (let attempt = 0; ; attempt++) {
    const r = await fetch(u, { headers: { Authorization: 'Bearer ' + supabaseAccessToken() } });
    const text = await r.text();
    if ((r.status === 429 || r.status >= 500) && attempt < 5) { await new Promise((res) => setTimeout(res, 2000 * 2 ** attempt)); continue; }
    let j; try { j = JSON.parse(text); } catch { j = null; }
    if (!r.ok || !j || j.error || !Array.isArray(j.result)) throw new Error(`logs ${r.status}: ${text.slice(0, 300)}`);
    return j.result;
  }
}

try {
  let total = 0; const who = new Map(); const where = new Map();
  const add = (m, k, n) => m.set(k, (m.get(k) || 0) + Number(n || 0));
  // The endpoint answers one window of at most a day; a longer span is read a day at a time and summed. The
  // gateway logs keep about a day on this plan, so a window older than that reads as empty, not as zero traffic:
  // run this at least once a day through the watch rather than once at the end of it.
  for (let to = end; to > start; to = new Date(to.getTime() - 24 * 3600e3)) {
    const from = new Date(Math.max(start.getTime(), to.getTime() - 24 * 3600e3));
    const [t] = await window(QUERIES.total, from, to);
    total += Number(t?.n || 0);
    if (!Number(t?.n || 0)) continue;
    for (const r of await window(QUERIES.who, from, to)) add(who, [r.role || '(none)', r.org || '(unknown)', r.ua || '(none)'].join('\t'), r.n);
    for (const r of await window(QUERIES.where, from, to)) add(where, [r.role || '(none)', r.p || ''].join('\t'), r.n);
  }
  console.log(`HS256 requests through the gateway, ${start.toISOString()} to ${end.toISOString()} (excluding /admin/*): ${total}`);
  if (!total) { console.log('ZERO: this window counts toward the 24-48 h before the legacy keys are disabled.'); process.exit(0); }
  const show = (title, m) => {
    console.log(`\n${title}`);
    for (const [k, n] of [...m].sort((a, b) => b[1] - a[1]).slice(0, 40)) {
      const [role, ...rest] = k.split('\t');
      console.log(`${String(n).padStart(7)}  ${role.padEnd(12)}  ${rest.map((x) => x.slice(0, 70)).join(' / ')}`);
    }
  };
  show('      n  role          network / user agent', who);
  show('      n  role          path (top 40)', where);
  console.log('\nNOT ZERO: a consumer still sends a legacy key. Do not disable the legacy keys yet.');
  process.exit(1);
} catch (e) {
  console.error('could not read the gateway logs (this is NOT a zero): ' + String(e?.message || e));
  process.exit(2);
}
