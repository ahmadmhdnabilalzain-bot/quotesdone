// WHAT ACTUALLY DIFFERS between staging and production, character by character.
//
// verify_prod_parity reports WHICH objects drifted; it cannot tell you WHY, and a normalising diff
// can lie in both directions. Measured here: my first normalisation reported fn_schema_export as
// "staging 3890 vs production 1241 — a third the size", which was an artefact of stripping `--`
// comments with a regex, because that function BUILDS a schema dump and contains string literals
// like '-- ===== EXTENSIONS ====='. The comment-stripper ate the data. Raw, the two differ by 11
// characters.
//
// So this prints the first differing region of the RAW definitions, with the project ref masked
// (staging routines must reference staging — that is isolation, not drift).
//
//   node scripts/diff_drifted_objects.mjs
import { mgmtRead, PROD_REF } from './staging/qd_guard.mjs';
import { REF as STAGE } from './staging/demo_factory.mjs';

const ROUTINES = ['enqueue_supplier_invites', 'fn_control_mode_open', 'fn_invite_ramp',
                  'fn_schema_export', 'run_health_check'];
const VIEWS = ['v_audit_coverage', 'v_department_health'];

const defs = (ref) => mgmtRead(ref, `
  select p.proname n, 'routine' kind, pg_get_functiondef(p.oid) d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname='public' and p.proname in (${ROUTINES.map(r => `'${r}'`).join(',')})
  union all
  select viewname, 'view', definition from pg_views
   where schemaname='public' and viewname in (${VIEWS.map(v => `'${v}'`).join(',')})`);

const [S, P] = [await defs(STAGE), await defs(PROD_REF)];
const mask = (s) => s.replace(new RegExp(`${STAGE}|${PROD_REF}`, 'g'), '<REF>');

for (const p of P) {
  const s = S.find(x => x.n === p.n);
  if (!s) { console.log(`\n### ${p.n} — ABSENT FROM STAGING`); continue; }
  const a = mask(s.d), b = mask(p.d);

  if (a === b) {
    console.log(`\n### ${p.n} (${p.kind}) — IDENTICAL once the project ref is masked. NOT DRIFT.`);
    continue;
  }

  // First and last differing offsets, so the changed region is bounded rather than guessed at.
  let i = 0; while (i < a.length && i < b.length && a[i] === b[i]) i++;
  let ja = a.length - 1, jb = b.length - 1;
  while (ja > i && jb > i && a[ja] === b[jb]) { ja--; jb--; }

  console.log(`\n### ${p.n} (${p.kind}) — staging ${a.length} chars, production ${b.length}`);
  console.log(`  common prefix ends at ${i}; differing region: staging ${ja - i + 1} chars, production ${jb - i + 1} chars`);
  console.log(`  ...context: ${JSON.stringify(a.slice(Math.max(0, i - 70), i))}`);
  console.log(`  STAGING   : ${JSON.stringify(a.slice(i, Math.min(ja + 1, i + 320)))}`);
  console.log(`  PRODUCTION: ${JSON.stringify(b.slice(i, Math.min(jb + 1, i + 320)))}`);
}
