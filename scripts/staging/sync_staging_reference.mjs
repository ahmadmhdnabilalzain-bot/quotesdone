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
  // Parents the children below FK to. field_definition and field_definition_source were listed for
  // two sessions and silently deferred on every run because mep_trade was never in the list; the
  // multi-pass loop reported them as "deferred" and the summary line reported a total that looked
  // fine. A table that is in the allowlist but never loads is worse than one that is absent.
  'mep_trade',                     // 5 rows, parent of field_definition.trade_key
  'kb_operational_route',          // 86 rows, parent of both kb_operational_* tables below
  'field_definition',
  'field_definition_source',
  // Without these the AI gateway has no model to route to, so EVERY LLM call fails and
  // inquiry_intake silently drops to its keyword fallback: readiness pinned at 40, the same four
  // questions every turn, and a customer who can never complete an inquiry. The function logs
  // exactly that ("this brief was not written by the model") and the journey still reported the
  // turn as HTTP 200.
  'model_registry',
  'model_policy',
  // ai_gateway maps a calling function to its task_class through this table. With it empty EVERY
  // function falls through to the default tier, so the routing policy above is loaded and then
  // never consulted. quote_compare - the customer's decision step - was answered by the cheapest
  // model at 1500 output tokens, truncated its JSON, failed to parse twice, and returned HTTP 200
  // with nothing to compare.
  'fn_task_class',
  // fn_kb_route_decide's own inputs. Without them it returns top_score 0 for every string in
  // staging, so the operational router is not merely unwired - it has nothing to route against.
  // kb_operational_alias is 4,212 rows and its first column (catalog_num) is massively non-unique,
  // which is precisely the case the `order by 1` pagination above used to corrupt.
  'kb_operational_alias',
  'kb_operational_route_map',
  // ---- the org / autonomy layer (added 5 Aug 2026) ---------------------------------------------
  // DEFINITIONS, not business records: which action classes exist, which executor runs each, which
  // RPCs are allowed, the workflow shapes and the org chart they hang off. No customer, supplier,
  // inquiry or quote data is copied, so this script's own no-real-data rule is not breached.
  //
  // Staging held 0 rows in all eight against production's 55 / 16 / 14 / 117 / 10 / 15 / 67 / 196,
  // which made every Phase 7 measurement meaningless: v_executor_registry_gaps returning 0 in
  // staging meant "the registry is empty", not "there are no gaps".
  //
  // NOTE what this deliberately does NOT do. The orchestrator that would LEASE a workflow_run, walk
  // workflow_step into workflow_step_run, dispatch through org_action_executor into
  // action_execution and write decision_trace still does not exist, and this does not build one.
  // All four of those tables already EXIST in both projects and are empty - measured 5 Aug 2026, so
  // "build the four missing tables" is stale too; they were never missing. Loading the config is
  // what makes building an orchestrator possible for whoever does it; writing rows into those four
  // by hand would only manufacture the appearance of a working autonomy layer.
  'operating_system',              // parent of workflow / org_departments
  'org_departments',
  'org_agents',
  'org_authority',
  'workflow',                      // parent of workflow_step
  'workflow_step',
  'org_action_executor',           // parent of org_action_executor_rpc_allowed
  'org_action_executor_rpc_allowed',
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

// A function declaration, not a const: copyTable runs inside the pass loop ABOVE this point, and a
// const here would still be in its temporal dead zone when the first table is copied.
function qi(c) { return `"${String(c).replace(/"/g, '""')}"`; }

// LIMIT/OFFSET pagination is only meaningful over a TOTAL order. `order by 1` orders by the first
// column, which for most of these tables is not unique - kb_operational_alias's is catalog_num,
// whose primary key is (catalog_num, language, alias) across 4,212 rows. Postgres is free to return
// tied rows in any order per query, so batches both duplicate and drop rows: the duplicate violates
// the primary key and the INSERT throws, leaving the table half-loaded. Order by the whole primary
// key instead, and where there is no primary key, by every column.
async function orderCols(t) {
  const pk = await mgmtRead(PROD_REF, `
    select a.attname
      from pg_index i
      join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
     where i.indrelid = 'public.${t}'::regclass and i.indisprimary
     order by array_position(i.indkey, a.attnum)`);
  if (pk.length) return { cols: pk.map((r) => r.attname), hasPk: true };
  const all = await mgmtRead(PROD_REF, `
    select column_name from information_schema.columns
     where table_schema='public' and table_name=${lit(t)} order by ordinal_position`);
  return { cols: all.map((r) => r.column_name), hasPk: false };
}

async function copyTable(t) {
  const [{ n: prodRows }] = await mgmtRead(PROD_REF, `select count(*)::int as n from public.${t}`);
  const [{ n: stageRows }] = await mgmtRead(REF, `select count(*)::int as n from public.${t}`);
  if (!prodRows) { console.log(`${t.padEnd(26)} production is empty - skipped`); return; }
  // The old guard was `if (stageRows) skip`, which made a HALF-LOADED table skip forever: the
  // pagination bug above would abort a large copy partway through and every later run would then
  // report "staging already has N rows - skipped" and never finish it. Skip only when the table is
  // actually complete; otherwise resume.
  if (stageRows >= prodRows) {
    console.log(`${t.padEnd(26)} staging already has ${stageRows} of ${prodRows} - skipped`);
    totalCopied += stageRows; return;
  }
  if (!APPLY) {
    console.log(`${t.padEnd(26)} would copy ${prodRows} row(s)` +
      (stageRows ? ` (resuming: staging has ${stageRows})` : ''));
    return;
  }

  const { cols, hasPk } = await orderCols(t);
  const order = cols.map(qi).join(', ');
  // ON CONFLICT DO NOTHING makes a resume idempotent: rows already present are skipped instead of
  // aborting the batch. It needs a unique constraint to conflict on, so a table without a primary
  // key still has to be all-or-nothing.
  const onConflict = hasPk ? ' on conflict do nothing' : '';
  if (stageRows) {
    console.log(`${t.padEnd(26)} resuming: staging has ${stageRows} of ${prodRows}` +
      (hasPk ? '' : ' (NO PRIMARY KEY - cannot resume safely, reloading from empty)'));
    if (!hasPk) await mgmtWrite(REF, `delete from public.${t}`, `reset ${t}`);
  }

  let fetched = 0;
  for (let off = 0; off < prodRows; off += BATCH) {
    const rows = await mgmtRead(PROD_REF,
      `select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)::text as data
       from (select * from public.${t} order by ${order} limit ${BATCH} offset ${off}) x`);
    const json = rows[0]?.data ?? '[]';
    if (json === '[]') break;
    // org_authority is protected by trg_org_authority_guard, which REFUSES any insert or update
    // that widens authority - a higher max_tier or a higher threshold_aed - unless
    // app.change_reason is set. Loading 196 rows into an empty table is a widening by definition,
    // so the copy failed with SQLSTATE 23514 until a reason was supplied.
    //
    // That guard is correct and must not be worked around: it exists so nobody can quietly grant an
    // agent more autonomy without recording why. The right response is to STATE the reason, which
    // is what this does. It is set transaction-locally (set_config third argument true) so it
    // cannot leak into any later statement on the same connection.
    const reason = t === 'org_authority'
      ? `select set_config('app.change_reason', ` +
        lit('Reference sync: copying production org_authority verbatim into an empty staging table '
          + 'so Phase 7 measurements mean something. No tier or threshold is raised ABOVE production '
          + '- staging is being brought up to it. sync_staging_reference.mjs, 5 Aug 2026.') +
        `, true);\n`
      : '';
    await mgmtWrite(REF,
      // OVERRIDING SYSTEM VALUE: several of these tables have GENERATED ALWAYS identity keys, and
      // the ids must survive the copy because the reference tables point at each other by id.
      // Letting Postgres re-issue them would silently rewire the taxonomy.
      `${reason}insert into public.${t} overriding system value
       select * from jsonb_populate_recordset(null::public.${t}, ${lit(json)}::jsonb)${onConflict}`,
      `copy ${t}`);
    fetched += JSON.parse(json).length;
  }
  const [{ n: after }] = await mgmtRead(REF, `select count(*)::int as n from public.${t}`);
  // A count that does not match production means pagination lost or duplicated rows. Say so rather
  // than reporting a number that looks like a success.
  const verdict = after === prodRows ? '' : `  *** MISMATCH: staging ${after} vs production ${prodRows} ***`;
  console.log(`${t.padEnd(26)} fetched ${fetched}, staging now ${after} (production ${prodRows})${verdict}`);
  totalCopied += after;
}
