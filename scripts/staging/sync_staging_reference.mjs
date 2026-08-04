// sync_staging_reference.mjs — copy the taxonomy staging needs to route and match.
//
// WHY THIS EXISTS
// route_inquiry reads taxonomy_trade, subcategory_agent_map, lead_trade_map, decision_policy and
// the category tables. All of them were empty in staging, so every inquiry routed to
// {"note":"no_registered_suppliers"} - not because no supplier fitted, but because the taxonomy
// the matcher consults did not exist. An empty reference table produces a confident wrong answer
// rather than an error, which is the worst shape a data gap can take.
//
// WHAT IT DELIBERATELY DOES NOT COPY
// lead_subcategory (25,438 rows) and every other lead-scoped table map REAL scraped supplier
// businesses. Those are production business records, they reference leads staging does not have,
// and the staging policy is explicit that discovered supplier data stays out. Synthetic suppliers
// are created by the journey and acceptance tests instead.
//
// Rows move as JSON through to_jsonb / jsonb_populate_recordset so every column type - arrays,
// jsonb, timestamps, enums - round-trips without hand-built SQL literals.
//
//   node scripts/staging/sync_staging_reference.mjs [--apply]
import { mgmtRead, mgmtWrite, PROD_REF, assertNotProduction } from './qd_guard.mjs';

const REF = assertNotProduction(process.env.QD_STAGING_REF || 'pglpqrhvozwepymcuunn', 'reference sync');
const APPLY = process.argv.includes('--apply');
const BATCH = 500;

// Taxonomy and policy only. Nothing here identifies a real customer or a real supplier.
const TABLES = [
  'catalog_domains',
  'catalog_supplier_categories',   // the 86 categories
  'catalog_subcategories',
  'taxonomy_trade',
  'taxonomy_authority',
  'taxonomy_role',
  'knowledge_domain',
  'category_specs',
  'subcategory_agent_map',
  'lead_trade_map',
  'decision_policy',
  'category_keyword',
  'subcategory_keyword',
  'field_definition',
  'field_definition_source',
  // Without these the AI gateway has no model to route to, so EVERY LLM call fails and
  // inquiry_intake silently drops to its keyword fallback: readiness pinned at 40, the same four
  // questions every turn, and a customer who can never complete an inquiry. The function logs
  // exactly that ("this brief was not written by the model") and the journey still reported the
  // turn as HTTP 200.
  'model_registry',
  'model_policy',
];

const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;
let totalCopied = 0;

// Multi-pass, for the same reason the schema applier is multi-pass: these tables reference each
// other by foreign key, and hand-maintaining a dependency order is a list that goes stale the
// first time someone adds a column. A table that fails because its parent is not loaded yet
// succeeds on the next pass; when a pass loads nothing new, what remains is a real failure.
let pending = TABLES.slice();
for (let pass = 1; pass <= 5 && pending.length; pass++) {
  const failed = [];
  console.log(`\n--- pass ${pass} (${pending.length} table(s)) ---`);
  for (const t of pending) {
    try { await copyTable(t); }
    catch (e) { failed.push(t); console.log(`${t.padEnd(26)} deferred: ${String(e.message).slice(0, 110)}`); }
  }
  const noProgress = failed.length === pending.length;
  pending = failed;
  if (!failed.length || noProgress) break;
}
if (pending.length) console.log(`\nSTILL FAILING: ${pending.join(', ')}`);
console.log(`\ntotal rows now in staging across these tables: ${totalCopied}`);

async function copyTable(t) {
  const [{ n: prodRows }] = await mgmtRead(PROD_REF, `select count(*)::int as n from public.${t}`);
  const [{ n: stageRows }] = await mgmtRead(REF, `select count(*)::int as n from public.${t}`);
  if (!prodRows) { console.log(`${t.padEnd(26)} production is empty - skipped`); return; }
  if (stageRows) { console.log(`${t.padEnd(26)} staging already has ${stageRows} row(s) - skipped`); return; }
  if (!APPLY) { console.log(`${t.padEnd(26)} would copy ${prodRows} row(s)`); return; }

  let copied = 0;
  for (let off = 0; off < prodRows; off += BATCH) {
    const rows = await mgmtRead(PROD_REF,
      `select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)::text as data
       from (select * from public.${t} order by 1 limit ${BATCH} offset ${off}) x`);
    const json = rows[0]?.data ?? '[]';
    if (json === '[]') break;
    await mgmtWrite(REF,
      // OVERRIDING SYSTEM VALUE: several of these tables have GENERATED ALWAYS identity keys, and
      // the ids must survive the copy because the reference tables point at each other by id.
      // Letting Postgres re-issue them would silently rewire the taxonomy.
      `insert into public.${t} overriding system value
       select * from jsonb_populate_recordset(null::public.${t}, ${lit(json)}::jsonb)`,
      `copy ${t}`);
    copied += Math.min(BATCH, prodRows - off);
  }
  const [{ n: after }] = await mgmtRead(REF, `select count(*)::int as n from public.${t}`);
  console.log(`${t.padEnd(26)} copied ${copied}, staging now ${after} (production ${prodRows})`);
  totalCopied += after;
}
