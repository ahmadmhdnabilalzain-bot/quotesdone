// WHAT MUST SURVIVE, INCLUDING WHAT THE SURVIVORS DEPEND ON
//
// Classifying by evidence gives a first answer: keep what the product calls, keep the new structure,
// drop the rest. That answer is not safe on its own. A routine that survives because an edge function
// calls it may itself call a routine that nothing in the product mentions -- drop that one and the
// survivor breaks. So this computes the CLOSURE: whatever a kept routine references is kept too,
// repeated until the set stops growing.
//
// Writes the drop list to a file. Deletes nothing.
//
//   node scripts/kb/new_structure_closure.mjs [--out <path>]

import { readFileSync, readdirSync, statSync, existsSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { sql } from '../lib/db.mjs';

const argOut = process.argv.indexOf('--out');
const OUT = argOut >= 0 ? process.argv[argOut + 1] : 'drop_list.json';

const CODE_DIRS = ['supabase/functions', 'src', 'app', 'pages', 'components', 'lib'];
let code = '';
const walk = (d) => {
  if (!existsSync(d)) return;
  for (const e of readdirSync(d)) {
    const p = join(d, e);
    let st; try { st = statSync(p); } catch { continue; }
    if (st.isDirectory()) { if (e !== 'node_modules' && e !== '.next') walk(p); }
    else if (/\.(ts|tsx|js|jsx|mjs|sql)$/.test(e)) { try { code += readFileSync(p, 'utf8'); } catch { /* unreadable */ } }
  }
};
for (const d of CODE_DIRS) walk(d);
console.log('product code scanned: ' + (code.length / 1048576).toFixed(1) + ' MB');

// The new structure, named. Everything here is something the founder explicitly kept.
const KEEP_NAME = [
  /^ceo_/, /^company_charter/, /^target_(contract|driver|verdict)/,
  /^wa_/, /^sms_/, /^twilio/,
  /^kb_/, /^ops_knowledge/, /^company_faq/, /^knowledge_/,
  /^founder_/,
  /^org_role$/, /^org_agents$/, /^org_role_alias$/,
  /^leads/, /^customers?/, /^inquir/, /^quotation/, /^quotes?/, /^supplier/,
  /^transaction/, /^stripe/, /^reveal/, /^match/, /^rfq/, /^portal/,
  /^terms/, /^company_registration/, /^legal_/, /^documents?$/, /^doc_/,
  /^app_secrets$/, /^app_settings$/, /^notifications$/, /^internal_/,
  /^gl_/, /^expense/, /^ap_/, /^ar_/, /^budget/, /^company_financial/, /^ad_spend/,
];
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const word = (n) => new RegExp('\\b' + esc(n) + '\\b');
const byName = (n) => KEEP_NAME.some((r) => r.test(n));
const usedByProduct = (n) => word(n).test(code);

const tables = (await sql(`select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind in ('r','v','m')`)).map((x) => x.relname);
const procs = await sql(`select p.proname, p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')`);
const srcOf = {};
for (const p of procs) srcOf[p.proname] = (srcOf[p.proname] || '') + '\n' + (p.prosrc || '');
const allProcs = Object.keys(srcOf);
const names = [...tables, ...allProcs];

const keep = new Set(names.filter((n) => byName(n) || usedByProduct(n)));
console.log('seed (new structure + called by the product): ' + keep.size + ' of ' + names.length);

for (let pass = 1; pass <= 10; pass++) {
  const before = keep.size;
  let body = '';
  for (const p of allProcs) if (keep.has(p)) body += '\n' + srcOf[p];
  for (const n of names) {
    if (keep.has(n)) continue;
    if (word(n).test(body)) keep.add(n);
  }
  console.log('  closure pass ' + pass + ': ' + keep.size + ' (+' + (keep.size - before) + ')');
  if (keep.size === before) break;
}

const dropTables = tables.filter((n) => !keep.has(n));
const dropRoutines = allProcs.filter((n) => !keep.has(n));
console.log('\nKEEP  tables ' + (tables.length - dropTables.length) + '  routines ' + (allProcs.length - dropRoutines.length));
console.log('DROP  tables ' + dropTables.length + '  routines ' + dropRoutines.length);
writeFileSync(OUT, JSON.stringify({ tables: dropTables, routines: dropRoutines }, null, 1));
console.log('drop list written to ' + OUT + '. Nothing was deleted.');
process.exit(0);
