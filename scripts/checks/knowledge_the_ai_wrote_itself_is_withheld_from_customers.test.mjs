// KNOWLEDGE THE AI WROTE ITSELF IS WITHHELD FROM CUSTOMERS (customer_support, 27 Oct 2026). Founder ruling 1338:
// "Withhold from customers." Measured: fn_reason_retrieve and fn_reason_retrieve_ml gave kb_chunks rows of source_kind
// 'generated' (1,317 model-written rows, incl. "Typical Cost Ranges (AED)" per trade) and 'memory' (53 agent notes) to
// a customer, supplier, visitor or NULL audience exactly as to an internal seat (probe, live routines: PROBE FAILED).
//
// This check reads the NEWEST file defining each routine: the last MANIFEST entry, or a pending file (a .sql with a note
// in scripts/sql/pending/) defining it, which is newer than every MANIFEST entry. It fails if that body's kb_chunks
// branch lets an outside audience read those rows, or if the edge's list (_shared/customer_facing_knowledge.ts) and the
// SQL list differ. Mutated once: removing either predicate fails it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const root = new URL('../../', import.meta.url);
const read = (p) => readFileSync(new URL(p, root), 'utf8');
const LIST = "('generated', 'memory')";

function newestDefiner(fn) {
  const re = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\(`, 'i');
  const listed = read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim()).filter((l) => l.endsWith('.sql'));
  const pending = readdirSync(new URL('scripts/sql/pending/', root)).filter((n) => n.endsWith('.txt'))
    .map((n) => 'scripts/sql/' + n.replace(/\.txt$/, '.sql')).filter((p) => existsSync(new URL(p, root)) && !listed.includes(p));
  const definers = [...listed, ...pending].filter((p) => existsSync(new URL(p, root)) && re.test(read(p)));
  assert.ok(definers.length, fn + ': no file defines it');
  const file = definers[definers.length - 1];
  const src = read(file);
  const i = src.search(re);
  return { file, body: src.slice(i, src.indexOf('end $fn$;', i)) };
}

test('fn_reason_retrieve: the kb_chunks branch withholds generated and memory rows from an outside audience', () => {
  const { file, body } = newestDefiner('fn_reason_retrieve');
  const kb = body.slice(body.indexOf("(select 'kb_chunks' src"), body.indexOf("union all", body.indexOf("(select 'kb_chunks' src")));
  assert.ok(kb.length > 0, file + ': no kb_chunks branch found');
  assert.ok(kb.includes(`and (v_internal or coalesce(c.source_kind not in ${LIST}, false))`), file + ': kb_chunks reaches a customer unfiltered');
  assert.match(body, /v_internal constant boolean := lower\(btrim\(coalesce\(p_audience, ''\)\)\) in \('internal', 'founder'\);/, file);
});

test('fn_reason_retrieve_ml: the final kb_chunks hits withhold generated and memory rows from an outside audience', () => {
  const { file, body } = newestDefiner('fn_reason_retrieve_ml');
  const at = body.indexOf("(select 'kb_chunks' src, c.id::text id");
  assert.ok(at > 0, file + ': no kb_chunks hits found');
  const kb = body.slice(at, body.indexOf('union all', at));
  assert.ok(kb.includes(`where v_internal or coalesce(c.source_kind not in ${LIST}, false)`), file + ': kb_chunks reaches a customer unfiltered');
  assert.match(body, /v_internal constant boolean := lower\(btrim\(coalesce\(p_audience, ''\)\)\) in \('internal', 'founder'\);/, file);
});

test('the edge rule and the SQL rule withhold the same source kinds', () => {
  const ts = read('supabase/functions/_shared/customer_facing_knowledge.ts');
  const m = ts.match(/KB_CHUNKS_NOT_CUSTOMER_FACING: ReadonlySet<string> = new Set\(\[([^\]]*)\]\)/);
  assert.ok(m, 'the edge list moved');
  const edge = m[1].split(',').map((s) => s.trim().replace(/'/g, '')).filter(Boolean).sort();
  const sql = LIST.replace(/[()' ]/g, '').split(',').sort();
  assert.deepEqual(edge, sql);
});
