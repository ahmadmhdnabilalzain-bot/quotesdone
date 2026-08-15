// PHASE A — STEP 6: apply the COMMITTED migration directly to production.
//
// Three refusals before a byte is sent, because this is the only remote environment there is:
//   1. the project must be the declared QuotesDone production project;
//   2. the migration file must be committed AND unmodified since — the protocol forbids applying
//      an uncommitted migration, and "committed" has to mean the bytes being sent, not the path;
//   3. the rehearsal artefact must exist, so this cannot be the first time these bytes have met
//      the database.
//
// The migration carries its own preconditions and postconditions and is one implicit transaction,
// so this script does not need to be clever: it sends the file and reports what came back.
//
//   node scripts/phase_a/deploy.mjs
import { readFileSync, existsSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { PROD_REF } from '../staging/qd_guard.mjs';

const DECLARED_PROD = 'htdblwldjkcgjvmqkbeh';
const FWD = 'supabase/migrations/20260815050000_phase_a_organization_closure.sql';
const BACK = 'scripts/sql/phase_a_rollback.sql';
const sha = (b) => createHash('sha256').update(b).digest('hex');

if (PROD_REF !== DECLARED_PROD) {
  console.error(`REFUSED: resolved project ${PROD_REF}, declared ${DECLARED_PROD}.`); process.exit(3);
}
for (const f of [FWD, BACK]) {
  if (!existsSync(f)) { console.error(`REFUSED: ${f} does not exist.`); process.exit(3); }
  const dirty = execSync(`git status --porcelain -- ${f}`).toString().trim();
  if (dirty) { console.error(`REFUSED: ${f} has uncommitted changes:\n${dirty}`); process.exit(3); }
}
if (!existsSync('docs/phase-a/phase_a_fingerprint_pre.json')) {
  console.error('REFUSED: no pre-change fingerprint. Run baseline.mjs first.'); process.exit(3);
}

const sql = readFileSync(FWD);
const back = readFileSync(BACK);
const commit = execSync('git rev-parse HEAD').toString().trim();
console.log(`project        ${PROD_REF}`);
console.log(`commit         ${commit}`);
console.log(`migration      ${FWD}`);
console.log(`               sha256 ${sha(sql)}  (${sql.length} bytes)`);
console.log(`rollback       ${BACK}`);
console.log(`               sha256 ${sha(back)}  (${back.length} bytes)`);

const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const started = new Date().toISOString();
console.log(`\napplying at ${started} …`);

const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
  method: 'POST',
  headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query: sql.toString('utf8') }),
});
const body = await r.text();
const finished = new Date().toISOString();

console.log(`HTTP ${r.status} at ${finished}`);
if (!r.ok) {
  let msg = body; try { msg = JSON.parse(body).message || body; } catch { /* raw */ }
  console.error('\nMIGRATION REFUSED — nothing was applied, the whole file is one transaction:\n');
  console.error(String(msg).replace(/\\n/g, '\n').slice(0, 3000));
  process.exitCode = 1;
} else {
  console.log('\nMIGRATION APPLIED. Its own postconditions passed inside the transaction, or this');
  console.log('would have been a 400. Run the production invariant suite now — the migration');
  console.log('asserting its own success is not the same as an independent check saying so.');
}
