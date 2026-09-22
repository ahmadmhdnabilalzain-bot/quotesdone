// verify_constraints.mjs — the parity dimension nothing measured.
//
// §9: "apply_missing_objects.mjs — catalogue diff: enums, sequences, columns, tables, views,
// routines. Does NOT diff constraints — which is why staging's org_action_executor lost
// production's NOT NULLs and CHECKs."
//
// verify_phase1 asserts 403 tables / 161 views / 739 routines / 5,237 columns and passes, so the
// gap is invisible to every gate in the repo: a COLUMN can exist in both projects while being
// nullable in one and NOT NULL in the other, and a CHECK can be absent entirely. Staging then
// accepts rows production would reject, and a fixture that passes here proves nothing about there.
// That is the same class as §5's "silent failure at two layers": the schema looks identical by
// every measure anyone was taking.
//
// Measured 5 Aug 2026: CHECK 145 vs 143, NOT NULL columns 1,812 vs 1,807. Foreign keys (169),
// primary keys (402) and uniques (82) match exactly — so the drift is narrow and worth naming
// precisely rather than rebuilding anything.
//
// Report-only by default. `--apply` fixes STAGING through qd_guard's mgmtWrite, which refuses
// production by construction.
//
//     node scripts/staging/verify_constraints.mjs
//     node scripts/staging/verify_constraints.mjs --apply
import { mgmtRead, mgmtWrite, PROD_REF } from '../lib/qd_guard.mjs';
import { REF } from '../lib/demo_factory.mjs';

const APPLY = process.argv.includes('--apply');

const NN = `select table_name||'.'||column_name as k from information_schema.columns
             where table_schema='public' and is_nullable='NO' order by 1`;
// conname is included because two different CHECKs on one table are two different facts.
const CK = `select t.relname||'|'||c.conname||'|'||pg_get_constraintdef(c.oid) as k
              from pg_constraint c join pg_class t on t.oid=c.conrelid
              join pg_namespace n on n.oid=t.relnamespace
             where n.nspname='public' and c.contype='c' order by 1`;

const set = async (ref, sql) => new Set((await mgmtRead(ref, sql)).map((r) => r.k));
const [pNN, sNN, pCK, sCK] = await Promise.all([
  set(PROD_REF, NN), set(REF, NN), set(PROD_REF, CK), set(REF, CK),
]);

const only = (a, b) => [...a].filter((x) => !b.has(x));
const missNN = only(pNN, sNN), extraNN = only(sNN, pNN);
const missCK = only(pCK, sCK), extraCK = only(sCK, pCK);

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ ok });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(50)} ${detail}`);
};

step('NOT NULL columns match production', missNN.length === 0 && extraNN.length === 0,
  `production ${pNN.size}, staging ${sNN.size}` +
  (missNN.length ? ` — missing in staging: ${missNN.join(', ')}` : '') +
  (extraNN.length ? ` — extra in staging: ${extraNN.join(', ')}` : ''));

step('CHECK constraints match production', missCK.length === 0 && extraCK.length === 0,
  `production ${pCK.size}, staging ${sCK.size}` +
  (missCK.length ? ` — missing in staging: ${missCK.map((k) => k.split('|').slice(0, 2).join('.')).join(', ')}` : '') +
  (extraCK.length ? ` — extra in staging: ${extraCK.map((k) => k.split('|').slice(0, 2).join('.')).join(', ')}` : ''));

// The statements, printed whether or not --apply is passed, so the diff is reviewable first.
const stmts = [
  ...missNN.map((k) => {
    const [t, c] = k.split('.');
    return `alter table public.${t} alter column ${c} set not null;`;
  }),
  ...missCK.map((k) => {
    const [t, name, def] = k.split('|');
    return `alter table public.${t} add constraint ${name} ${def};`;
  }),
];

if (stmts.length) {
  console.log(`\n${stmts.length} statement(s) to bring staging up to production:\n`);
  for (const s of stmts) console.log(`  ${s}`);
  if (APPLY) {
    console.log('');
    for (const s of stmts) {
      // A NOT NULL that existing staging rows violate must fail loudly rather than be skipped:
      // silently leaving it off is exactly how this drift went unnoticed for three sessions.
      try { await mgmtWrite(REF, s, 'constraint parity'); console.log(`  applied: ${s}`); }
      catch (e) { console.log(`  FAILED : ${s}\n           ${String(e.message).slice(0, 220)}`); }
    }
    console.log('\nRe-run without --apply to confirm.');
  } else {
    console.log('\nRun with --apply to apply them to staging (production is refused by qd_guard).');
  }
}

const bad = checks.filter((c) => !c.ok).length;
console.log(`\nCONSTRAINT PARITY ${checks.length - bad}/${checks.length} on ${REF}`);
process.exit(bad ? 1 : 0);
