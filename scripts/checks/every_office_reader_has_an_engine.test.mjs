// EVERY FUNCTION THAT READS OFFICE FILES HAS A WORKBOOK ENGINE, AND SUPPLIER_API STAYS UNDER ITS UPLOAD BUDGET.
// Assigned: it_engineer (16 Nov 2026).
//
// MEASURED 16 Nov 2026. `supabase functions deploy supplier_api --use-api` failed 413: the local files in its module
// graph (deno info --json supplier_api/index.ts, every file under supabase/functions/) came to 4,695,339 bytes,
// where 4.54 MB had deployed on 15 Nov. 503,237 of them were the vendored SheetJS, reached only through
// _shared/vendor/xlsx_lazy.ts from doc_read/office.ts (workbooks) and doc_read/ole.ts (.doc/.msg). Since then those
// two files take their reads from a REGISTERED engine (_shared/doc_read/workbook_engine.ts): SheetJS in the
// isolate (workbook_local.ts, registered by importing it) or in doc_extract (workbook_remote.ts, supplier_api).
//
// WHAT THIS ASSERTS, from the source alone (no deno, no database):
//   1. every function whose graph reaches office.ts or ole.ts registers an engine: its graph reaches
//      workbook_local.ts, or its own folder calls registerWorkbookEngine(remoteWorkbookEngine(...)). One without
//      either refuses every workbook, .doc and .msg as 'this function has no workbook reader'.
//   2. workbook_local.ts is imported by no _shared module (only by function folders and tests), or SheetJS would
//      ride back into every function that imports that module.
//   3. no function in REMOTE_READERS (supplier_api, and wa_inbound since 16 Nov 2026) has SheetJS, xlsx_lazy.ts or
//      workbook_local.ts in its graph; each registers the remote engine and stays under its upload budget.
//
// THE GRAPH WALK is a text scan of relative import specifiers (static import / export-from, side-effect import, literal
// dynamic import(), @deno-types), the same edges deno follows for files under supabase/functions/. Remote (https:, jsr:, npm:)
// modules are not counted, as they were not in the 4,695,339 measurement. Checked on 16 Nov 2026 against
// `deno info --json` for all 79 function entries: the same file set for every one.
//
//   node --test scripts/checks/every_office_reader_has_an_engine.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const FN = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'supabase', 'functions');

// 4,400,000: 4.54 MB deployed on 15 Nov and 4.70 MB did not, so the ceiling sits below the last size known to work,
// with 227,342 bytes of room above the 4,172,658 measured after this change (248 files). Raising it needs a deploy that proves the new
// size is accepted, not a guess.
export const SUPPLIER_API_BUDGET = 4_400_000;
// The functions that read workbooks through doc_extract, and the upload budget of each. wa_inbound joined on 16 Nov 2026
// (simplification wave A, DUP item 1): its graph was 4,345,532 bytes in 214 files by `deno info --json`, 503,237 of them
// SheetJS, the second-largest upload after supplier_api; the same 4.4 MB ceiling holds for the same reason.
// Its credential is cred_fn_wa_inbound, whose scope names doc_extract (scripts/sql/whatsapp_reads_workbooks_through_doc_extract.sql).
export const REMOTE_READERS = { supplier_api: SUPPLIER_API_BUDGET, wa_inbound: 4_400_000 };

const OFFICE = ['_shared/doc_read/office.ts', '_shared/doc_read/ole.ts'];
const LOCAL = '_shared/doc_read/workbook_local.ts';
const SHEETJS = ['_shared/vendor/sheetjs-0.20.3/xlsx.mjs', '_shared/vendor/xlsx_lazy.ts', LOCAL];
const REMOTE_REGISTRATION = /registerWorkbookEngine\s*\(\s*remoteWorkbookEngine\s*\(/;

const SPEC = [
  /(?:^|[\n;])\s*(?:import|export)\s+(?:type\s+)?[\w*${}\s,]*?\s*from\s*['"](\.{1,2}\/[^'"]+)['"]/g,
  /(?:^|[\n;])\s*import\s*['"](\.{1,2}\/[^'"]+)['"]/g,
  /\bimport\(\s*['"](\.{1,2}\/[^'"]+)['"]\s*\)/g,
  /@deno-types\s*=\s*["'](\.{1,2}\/[^'"]+)["'][^\n]*\n\s*(?:import|export)\s/g, // deno honours it on a static import only
];
const edges = new Map();
function importsOf(abs) {
  if (!edges.has(abs)) {
    const src = readFileSync(abs, 'utf8');
    const out = new Set();
    for (const re of SPEC) for (const m of src.matchAll(re)) out.add(resolve(dirname(abs), m[1]));
    edges.set(abs, [...out].filter((p) => existsSync(p)));
  }
  return edges.get(abs);
}

/** Every local file reachable from a function's index.ts, as paths relative to supabase/functions. */
export function localGraph(fn) {
  const seen = new Set();
  const stack = [join(FN, fn, 'index.ts')];
  while (stack.length) {
    const f = stack.pop();
    if (seen.has(f)) continue;
    seen.add(f);
    stack.push(...importsOf(f));
  }
  return [...seen].map((f) => relative(FN, f).split('\\').join('/'));
}

export const functions = () => readdirSync(FN).filter((d) => !d.startsWith('_') && existsSync(join(FN, d, 'index.ts'))).sort();
const graphBytes = (files) => files.reduce((n, f) => n + statSync(join(FN, f)).size, 0);

function ownSource(fn) {
  const out = [];
  const walk = (d) => { for (const e of readdirSync(d, { withFileTypes: true })) { const p = join(d, e.name); if (e.isDirectory()) walk(p); else if (/\.ts$/.test(e.name) && !/\.(test|check|fixtures)\.ts$/.test(e.name)) out.push(readFileSync(p, 'utf8')); } };
  walk(join(FN, fn));
  return out.join('\n');
}

const readers = () => functions().map((fn) => ({ fn, graph: new Set(localGraph(fn)) })).filter((r) => OFFICE.some((o) => r.graph.has(o)));

test('the scan is not empty: supplier_api and the other office readers are found', () => {
  const names = readers().map((r) => r.fn);
  assert.ok(names.includes('supplier_api') && names.includes('doc_extract') && names.length >= 9, 'expected supplier_api, doc_extract and at least nine office readers, found: ' + names.join(', '));
});

test('every function whose graph reaches office.ts or ole.ts registers a workbook engine', () => {
  const none = readers().filter((r) => !r.graph.has(LOCAL) && !REMOTE_REGISTRATION.test(ownSource(r.fn))).map((r) => r.fn);
  assert.deepEqual(none, [], 'these functions read office files but register no workbook engine, so every workbook, .doc and .msg they '
    + 'read is refused as "this function has no workbook reader". Add `import \'../_shared/doc_read/workbook_local.ts\';` to their '
    + 'index.ts (see that file\'s header):\n' + none.join('\n'));
});

test('workbook_local.ts is imported by no _shared module (it would carry SheetJS into every importer)', () => {
  const shared = [];
  const walk = (d) => { for (const e of readdirSync(d, { withFileTypes: true })) { const p = join(d, e.name); if (e.isDirectory()) walk(p); else if (/\.ts$/.test(e.name) && !/\.(test|check|fixtures)\.ts$/.test(e.name)) shared.push(p); } };
  walk(join(FN, '_shared'));
  const importers = shared.filter((p) => importsOf(p).includes(join(FN, LOCAL))).map((p) => relative(FN, p));
  assert.deepEqual(importers, []);
});

for (const [fn, budget] of Object.entries(REMOTE_READERS)) {
  test(`${fn} reads workbooks through doc_extract: SheetJS is not in its graph, and its upload stays under budget`, () => {
    const graph = localGraph(fn);
    const back = SHEETJS.filter((f) => graph.includes(f));
    assert.deepEqual(back, [], `SheetJS is back in ${fn}'s module graph (supplier_api's deploy failed 413 at 4,695,339 bytes with it). `
      + `Something ${fn} imports now reaches: ` + back.join(', '));
    assert.ok(REMOTE_REGISTRATION.test(ownSource(fn)), `${fn} no longer registers the remote workbook engine`);
    const bytes = graphBytes(graph);
    assert.ok(bytes < budget, `${fn}'s local module graph is ${bytes.toLocaleString('en')} bytes in ${graph.length} files, over the `
      + `${budget.toLocaleString('en')} budget. Supabase refused supplier_api's 4,695,339-byte upload with 413 on 16 Nov 2026 (4.54 MB was `
      + `accepted on 15 Nov). Find what grew: deno info --json supabase/functions/${fn}/index.ts.`);
  });
}
