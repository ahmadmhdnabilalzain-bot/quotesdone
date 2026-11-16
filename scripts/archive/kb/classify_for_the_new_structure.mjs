// WHAT BELONGS TO THE NEW STRUCTURE, AND WHAT DOES NOT
//
// Founder, 7 September 2026: "anything that doesnt belong to the current new structure need to be
// deleted. by new structure i mean today from the time i told you to remove all previous agents".
//
// 648 tables and 1,256 routines is far too many to sort by my judgement of their names, so this
// classifies by EVIDENCE instead, and only then by name:
//
//   KEEP 1 — anything the live product actually calls. Every edge function under supabase/functions
//            and every source file under src/ and app/ is scanned for each object's name. If the
//            running website or an edge function references it, it stays, whatever it is called.
//            Deleting something the site calls would break the product to tidy the schema.
//   KEEP 2 — the new structure itself: the two seats, the CEO's tables and functions built today,
//            the WhatsApp/customer-support path, the knowledge, the terms, and the founder's own
//            decisions. These are what he named.
//   DROP   — everything else: the Phase A-D scaffolding, the kernel, the org and workflow machinery,
//            the agent machinery and their satellites. The structure he removed.
//
// It writes nothing. It prints the three lists so the deletion that follows is reviewable first.
//
//   node scripts/archive/kb/classify_for_the_new_structure.mjs [--verbose]

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { sql } from '../../lib/db.mjs';

const VERBOSE = process.argv.includes('--verbose');

// ---- every file the running product is made of --------------------------------------------------
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
console.log('scanned ' + (code.length / 1024 / 1024).toFixed(1) + ' MB of product code');

// ---- the new structure, by name -----------------------------------------------------------------
const KEEP_NAME = [
  /^ceo_/, /^company_charter/, /^target_(contract|driver|verdict)/,          // the CEO, built today
  /^wa_/, /^sms_/, /^twilio/,                                                // customer support
  /^kb_/, /^ops_knowledge/, /^company_faq/, /^knowledge_/,                   // knowledge
  /^founder_/,                                                              // his decisions
  /^org_role$/, /^org_agents$/, /^org_role_alias$/,                          // the two seats
  /^leads/, /^customers?/, /^inquir/, /^quotation/, /^quotes?/, /^supplier/, // the product
  /^transaction/, /^stripe/, /^reveal/, /^match/, /^rfq/, /^portal/,
  /^terms/, /^company_registration/, /^legal_/, /^documents?$/, /^doc_/,
  /^app_secrets$/, /^app_settings$/, /^notifications$/, /^internal_/,        // platform plumbing
  /^gl_/, /^expense/, /^ap_/, /^ar_/, /^budget/, /^company_financial/, /^ad_spend/,
];
const keptByName = (n) => KEEP_NAME.some((r) => r.test(n));

// A name is "used" only when it appears as a whole word, so `leads` does not match `leadsheet`.
const usedByProduct = (n) => new RegExp('\\b' + n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b').test(code);

const tables = (await sql(`select c.relname, coalesce(s.n_live_tup,0) rows from pg_class c
  join pg_namespace n on n.oid=c.relnamespace left join pg_stat_user_tables s on s.relid=c.oid
 where n.nspname='public' and c.relkind='r' order by 1`));
const routines = (await sql(`select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')
 group by 1 order by 1`));

const bucket = (name) => {
  if (keptByName(name)) return 'new_structure';
  if (usedByProduct(name)) return 'used_by_product';
  return 'drop';
};

const out = { tables: { new_structure: [], used_by_product: [], drop: [] },
              routines: { new_structure: [], used_by_product: [], drop: [] } };
for (const t of tables) out.tables[bucket(t.relname)].push(t.relname);
for (const r of routines) out.routines[bucket(r.proname)].push(r.proname);

const show = (label, o, total) => {
  console.log('\n' + label + ' (' + total + ')');
  console.log('  new structure, keep      ' + String(o.new_structure.length).padStart(5));
  console.log('  used by the product, keep' + String(o.used_by_product.length).padStart(5));
  console.log('  DROP                     ' + String(o.drop.length).padStart(5));
};
show('TABLES', out.tables, tables.length);
show('ROUTINES', out.routines, routines.length);

if (VERBOSE) {
  console.log('\n--- tables to drop ---\n' + out.tables.drop.join(', '));
  console.log('\n--- routines to drop (first 120) ---\n' + out.routines.drop.slice(0, 120).join(', '));
}
console.log('\nNothing was deleted. This only classifies.');
process.exit(0);
