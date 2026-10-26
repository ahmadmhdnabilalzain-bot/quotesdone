// public.it_watch_subject IS WHERE THE IT ENGINEER'S SEVERITIES COME FROM, AND IT IS A SNAPSHOT.
//
// fn_it_detect derives severity from two things and nothing else: the STATE it computed, and
// whether the failing subject is reachable from outside our own backend. That second fact lives in
// public.it_watch_subject.public_surface, and it is a transcription of two properties of the
// deployed code:
//
//     verify_jwt      supabase/config.toml, [functions.<name>]
//     secret_gated    the function's index.ts checks an internal shared secret in the request body
//                     (requireInternal, or a literal comparison of __secret / __deploy_secret)
//     public_surface  = NOT secret_gated
//
// WHY THIS CHECK EXISTS. The registry drifted inside the session that created it: it was seeded at
// 06:5x on 9 Sep 2026, and by 07:0x a sibling build had added secret gates to eight edge functions,
// so eight rows described a deployment that no longer existed. Drift here does not hide a fault —
// the fault is still detected — it MIS-RANKS it, which is the quieter and more corrosive failure:
// the founder is paged as CRITICAL for an internal cron, or not paged loudly enough when a customer
// cannot register. A monitor that cries wolf is switched off, and then nothing is monitored.
//
// This check re-derives the entire table from the repository and fails on any disagreement,
// including a deployed function that has no row at all. It reads production; it writes nothing.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';

const CONFIG = 'supabase/config.toml';
const FNDIR = 'supabase/functions';

// The same expression the seed was generated with. A gate is a PRESENTED credential being checked,
// not one being sent: `__secret: x` in an outbound body is not a gate, `body.__secret !== x` is.
const GATE = /requireInternal|__deploy_secret|__secret\s*(?:!==|===)|!\s*[A-Za-z_$][A-Za-z0-9_$]*\??\.__secret/;

function fromRepo() {
  const toml = readFileSync(CONFIG, 'utf8');
  const out = new Map();
  let cur = null;
  for (const line of toml.split(/\r?\n/)) {
    const m = line.match(/^\[functions\.([a-z0-9_]+)\]/i);
    if (m) { cur = m[1]; continue; }
    const v = line.match(/^\s*verify_jwt\s*=\s*(true|false)/);
    if (v && cur) { out.set(cur, { verify_jwt: v[1] === 'true' }); cur = null; }
  }
  // A directory with no [functions.<name>] block still deploys, and Supabase defaults verify_jwt
  // to true. Counting it is the difference between "classified" and "silently absent".
  for (const d of readdirSync(FNDIR, { withFileTypes: true })) {
    if (!d.isDirectory() || d.name.startsWith('_')) continue;
    if (!out.has(d.name)) out.set(d.name, { verify_jwt: true });
  }
  for (const [name, row] of out) {
    const p = `${FNDIR}/${name}/index.ts`;
    const src = existsSync(p) ? readFileSync(p, 'utf8') : '';
    row.secret_gated = GATE.test(src);
    row.public_surface = !row.secret_gated;
  }
  return out;
}

const repo = fromRepo();
const live = await mgmtRead(PROD_REF,
  `select subject, public_surface, verify_jwt, secret_gated
     from public.it_watch_subject where kind = 'edge_function' order by subject`);
const liveMap = new Map(live.map((r) => [r.subject, r]));

const problems = [];
for (const [name, want] of repo) {
  const got = liveMap.get(name);
  if (!got) { problems.push(`MISSING     ${name} is deployed and has no row in it_watch_subject`); continue; }
  if (got.public_surface !== want.public_surface)
    problems.push(`PUBLIC      ${name}: registry says public_surface=${got.public_surface}, the deployed function says ${want.public_surface}`);
  if (got.secret_gated !== want.secret_gated)
    problems.push(`GATE        ${name}: registry says secret_gated=${got.secret_gated}, index.ts says ${want.secret_gated}`);
  if (got.verify_jwt !== want.verify_jwt)
    problems.push(`VERIFY_JWT  ${name}: registry says ${got.verify_jwt}, config.toml says ${want.verify_jwt}`);
}
for (const name of liveMap.keys()) {
  if (!repo.has(name)) problems.push(`ORPHAN      ${name} has a registry row and is not a deployed function`);
}

const pub = [...repo.values()].filter((r) => r.public_surface).length;
console.log(`it_watch_subject vs the deployment: ${repo.size} function(s), ${pub} reachable from outside the backend, ${repo.size - pub} backend-only`);
if (!problems.length) {
  console.log('OK — every deployed function has a row, and every row matches config.toml and its index.ts');
  process.exit(0);
}
console.log(`\n${problems.length} disagreement(s):`);
for (const p of problems) console.log('  ' + p);
console.log('\nRe-seed by editing the values block in');
console.log('  scripts/sql/the_it_engineer_detection_engine_answers_whether_anything_is_wrong.sql');
console.log('and re-applying it; the insert is ON CONFLICT DO UPDATE, so it corrects in place.');
process.exit(1);
