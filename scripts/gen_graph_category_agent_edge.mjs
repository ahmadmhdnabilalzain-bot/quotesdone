// ROW #6 §12 — mech-graph-edge. Generates the fn_graph_rebuild fix WITHOUT retyping its body.
//
// ── WHY THIS IS A GENERATOR AND NOT A HAND-WRITTEN .sql FILE ────────────────────────────────────
// fn_graph_rebuild is long, it owns every edge in the graph, and the repo's promotion rule is that a
// routine reaches production by reading a VERIFIED definition back out — never by retyping a body.
// The defect is one `exists` clause. Retyping the other ~90 lines to change it would put every one
// of them at risk of a transcription error that no diff would catch, to fix a bug in one of them.
//
// So the current definition is read from STAGING, exactly one clause is replaced, and the result is
// written to scripts/sql/. If the clause is not found EXACTLY once the script exits non-zero and
// writes nothing: a silent no-op here would produce a file that looks like a fix, applies cleanly,
// and changes nothing — which is the failure mode that let this edge sit dead since it was written.
//
// ── WHAT THE CLAUSE IS AND WHY ROW #5's REASONING FOR LEAVING IT NO LONGER HOLDS ─────────────────
// Row #5 found the edge dead and deliberately did not repair it. Its stated reason:
//
//     "It is left in place and not repaired here, because repairing it would connect a category to
//      an internal AI agent — and that is org structure, which is the thing a supplier must not be
//      shown."
//
// That objection was correct about the edge AS WRITTEN — `dst_kind='employee'`, joined to
// `org_agents`, which is QuotesDone's own 67-person org chart. It was wrong about what
// `category_agent_map.agent_slug` holds. Row #5 read it as "the CATEGORY slug, not an agent key".
// Measured on production 2026-08-09:
//
//     category_agent_map rows                                    84
//     … joined to category_agents.slug   on the bare slug        84   <- it IS an agent key
//     … joined to org_agents.agent_key   on the bare slug         0
//     … joined to org_agents.agent_key   on 'cat:'||slug          0
//
// `category_agents` is a 132-row registry of CATEGORY agents (slug, name, persona, agent_class) —
// a product surface, not a person. 84 of its rows are exactly the spec's realistic categories. So
// the relationship is category -> category_agent, and it is not org structure at all; nothing about
// QuotesDone's departments or reporting lines is expressed by it.
//
// The edge therefore changes target, not just predicate: dst_kind becomes 'category_agent'. Leaving
// dst_kind='employee' while joining category_agents would be worse than the bug — it would file 84
// product surfaces as staff in the same table the org chart lives in, and every consumer that reads
// dst_kind='employee' would start returning them.
//
// The supplier-facing reader (fn_graph_supplier_market) selects rel='adjacent_to' only, so this
// adds nothing to what a supplier sees. It is the internal graph that gains the relationship.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from './lib/qd_guard.mjs';
import { REF as STAGE } from './lib/demo_factory.mjs';

const OUT = 'scripts/sql/fn_graph_rebuild_category_agent_edge.sql';

const rows = await mgmtRead(STAGE, `select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.proname='fn_graph_rebuild' limit 1`);
const def = rows[0] && rows[0].def;
if (!def) { console.error('fn_graph_rebuild not found on staging'); process.exit(1); }

// The clause as it stands. Matched on its distinguishing parts rather than on exact whitespace, so
// a reformat does not silently turn this into a no-op — but still anchored tightly enough that it
// cannot match anything else in the function.
const CLAUSE = /select distinct 'category',\s*c\.slug,\s*'served_by',\s*'employee',\s*m\.agent_slug\s*\n\s*from category_agent_map m join catalog_supplier_categories c on c\.slug=m\.catalog_slug\s*\n\s*where exists \(select 1 from org_agents a where a\.agent_key=m\.agent_slug and a\.active\)/;

const hits = def.match(new RegExp(CLAUSE.source, 'g'));
if (!hits || hits.length !== 1) {
  console.error(`REFUSING: the org_agents clause was found ${hits ? hits.length : 0} time(s), expected exactly 1.`);
  console.error('fn_graph_rebuild has changed shape since this generator was written. Re-read it before editing.');
  process.exit(1);
}

const FIXED =
  `select distinct 'category', c.slug, 'served_by', 'category_agent', m.agent_slug\n` +
  `    from category_agent_map m join catalog_supplier_categories c on c.slug=m.catalog_slug\n` +
  `   where exists (select 1 from category_agents a where a.slug=m.agent_slug and coalesce(a.active,true))`;

const patched = def.replace(CLAUSE, FIXED);
if (patched === def) { console.error('replacement produced no change'); process.exit(1); }

// Take the leading comment block and stop at the first line that is not one. A fixed slice length
// silently swallowed the import statements into the .sql on the first run, and Postgres reported it
// as a syntax error 43 lines into a file whose first 42 lines were fine.
const selfLines = readFileSync(new URL(import.meta.url).pathname.replace(/^\//, ''), 'utf8').split('\n');
const end = selfLines.findIndex((l) => !l.startsWith('//'));
const HEADER = selfLines.slice(0, end < 0 ? selfLines.length : end)
  .map(l => l.replace(/^\/\/ ?/, '-- ').replace(/^\/\//, '--')).join('\n');

writeFileSync(OUT, `${HEADER}\n\n${patched};\n`);
console.log(`wrote ${OUT}`);
console.log(`  clause replaced: org_agents/'employee'  ->  category_agents/'category_agent'`);
