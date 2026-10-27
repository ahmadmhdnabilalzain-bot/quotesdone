// CUSTOMERS AND SUPPLIERS ARE NEVER GIVEN INTERNAL KNOWLEDGE (customer_support, 27 Oct 2026). Founder ruling 1338:
// "Withhold from customers." Internal seats keep access.
//
// MEASURED 27 Oct 2026 on production: all 9,143 ops_knowledge rows are confidentiality 'internal', and four routines
// handed them to outside callers without reading that column. The probe against the live routines reported LEAK:
// fn_reason_retrieve gave 6 of 6 ops rows to a customer, a supplier and a NULL audience; fn_reason_retrieve_ml 6 to a
// visitor; fn_support_corpus_search(p_public false), the signed-in portal's corpus, 25 ops rows and 2 internal support
// rows; fn_sales_assist, the portal chat's retrieval, 8 ops rows. The fix is
// scripts/sql/customers_and_suppliers_are_never_given_internal_knowledge.sql.
//
// What fails if that breaks:
//   * the newest body (MANIFEST order, then pending) of any of the four routines loses its predicate      -> static
//   * a routine starts reading ops_knowledge and nobody decided whether an outside caller reaches it        -> inventory
//   * the supplier English (e-mailed to suppliers) is reasoned with an internal audience again               -> static
//   * any of it on production, in one rolled-back request (the fix first while pending)                      -> live probe
// Mutated once each: deleting a predicate from the fix file fails its static test; the probe alone reports LEAK.
//
//   node --test scripts/checks/customers_and_suppliers_are_never_given_internal_knowledge.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestWithPending, pendingNotes } from '../lib/pending_sql.mjs';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const NAME = 'customers_and_suppliers_are_never_given_internal_knowledge';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const INTERNAL_SUPPORT = "(s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))";

// The canonical body: the last file, in the order files are (or will be) applied, that defines it. Comments removed.
function canonical(fn) {
  const re = new RegExp(`create or replace function public\\.${fn}\\(`, 'i');
  const owner = [...manifestWithPending()].reverse().find((f) => existsSync(join(ROOT, f)) && re.test(R(f)));
  assert.ok(owner, `no applied or pending file defines ${fn}`);
  const src = R(owner);
  const from = src.search(re);
  const tag = src.slice(from).match(/\bas\s+(\$[a-z_]*\$)/i)[1];
  return { owner, body: code(src.slice(from).split(tag)[1] || '') };
}
const between = (s, a, b) => { const i = s.indexOf(a); assert.ok(i >= 0, `not found: ${a}`); const j = s.indexOf(b, i + a.length); return s.slice(i, j < 0 ? undefined : j); };

test('fn_support_corpus_search: the signed-in portal (p_public false) gets only public ops rows and no internal support row', () => {
  const { owner, body } = canonical('fn_support_corpus_search');
  const w = between(body, 'case when p_public then c.is_public', 'end)');
  assert.doesNotMatch(w, /else\s+true\b/, `${owner}: p_public false reads every row again`);
  assert.match(w, /c\.src <> 'ops' or exists \(select 1 from public\.ops_knowledge k\s+where k\.record_id = c\.src_id and k\.confidentiality = 'public'\)/, `${owner}: internal ops rows reach the portal`);
  assert.ok(w.replace(/\s+/g, ' ').includes(INTERNAL_SUPPORT.replace(/\s+/g, ' ')), `${owner}: internal support rows reach the portal`);
  assert.match(w, /c\.src <> 'supportkb' or not exists/, `${owner}: the support exclusion is not a NOT EXISTS`);
});

test('fn_sales_assist (the portal chat): ops rows only when public, support rows never when internal', () => {
  const { owner, body } = canonical('fn_sales_assist');
  const ops = between(body, "select 'ops_knowledge', o.record_id", 'limit v_wide');
  assert.match(ops, /and o\.confidentiality = 'public'/, `${owner}: internal ops rows reach the portal chat`);
  const sup = between(body, "select 'support_knowledge', s.record_id", 'limit v_wide');
  assert.ok(sup.replace(/\s+/g, ' ').includes('and not ' + INTERNAL_SUPPORT), `${owner}: internal support rows reach the portal chat`);
});

test('fn_reason_retrieve: the ops branch gives an outside audience only public rows', () => {
  const { owner, body } = canonical('fn_reason_retrieve');
  assert.match(body, /v_internal constant boolean := lower\(btrim\(coalesce\(p_audience, ''\)\)\) in \('internal', 'founder'\);/, owner);
  const ops = between(body, "(select 'ops_knowledge', o.record_id", 'limit k)');
  assert.match(ops, /and \(v_internal or o\.confidentiality = 'public'\)/, `${owner}: internal ops rows reach a customer, supplier or visitor`);
});

test('fn_reason_retrieve_ml: the final ops hits give an outside audience only public rows', () => {
  const { owner, body } = canonical('fn_reason_retrieve_ml');
  assert.match(body, /v_internal constant boolean := lower\(btrim\(coalesce\(p_audience, ''\)\)\) in \('internal', 'founder'\);/, owner);
  const ops = between(body, "(select 'ops_knowledge', o.record_id, o.title", 'limit k)');
  assert.match(ops, /where v_internal or o\.confidentiality = 'public'/, `${owner}: internal ops rows reach a customer, supplier or visitor`);
});

// Every routine production runs that reads ops_knowledge, and the decision about outside callers. A new reader fails
// here until someone decides: it filters confidentiality for an outside audience (and gets a test above), or it has no
// customer or supplier caller (said here, with the reason). Read from the schema mirror (production as exported).
const READERS = {
  // filtered for an outside audience (tests above)
  fn_reason_retrieve: 'filtered', fn_reason_retrieve_ml: 'filtered', fn_sales_assist: 'filtered',
  // reads ops_knowledge itself once this PR's filter is live (its confidentiality EXISTS for p_public = false; tested above)
  fn_support_corpus_search: 'filtered',
  // no customer or supplier caller (27 Oct 2026: their SQL callers and every rpc() in supabase/functions)
  fn_accountant_assist: 'accountant edge, seat credential or founder only',
  fn_it_engineer_assist: 'it_engineer edge, seat credential or founder only',
  fn_marketing_assist: 'marketing edge, seat credential or founder only (the social inbox replies through aiReply)',
  fn_agent_context: 'internal agent context (fn_decide); no edge caller', fn_agent_context_v3: 'internal agent context; no edge caller',
  fn_apply_playbook: 'internal task machinery', fn_ops_knowledge_search: 'internal (tools.ts, which nothing imports)',
  fn_ops_knowledge_match: 'internal; no edge caller', fn_org_task_consume_tick: 'internal task machinery',
  fn_org_task_deterministic_done: 'internal task machinery', fn_org_task_lane_knowledge: 'internal task machinery',
  fn_workflow_step_deterministic_done: 'internal task machinery',
  fn_reason_retrieve_library: 'no caller at all; takes no audience - must be filtered before anything outside reads it',
  fn_reason_retrieve_ml_library: 'no caller at all; takes no audience - must be filtered before anything outside reads it',
  fn_support_knowledge_gap: 'names the table only in the task text it files',
  fn_backup_source_registry: 'backup', fn_ml_embed_claim: 'embedding pipeline', fn_ops_knowledge_embedding_status: 'embedding status',
  fn_company_knowledge_upsert: 'writer', fn_company_org_directory_sync: 'writer', fn_company_self_knowledge_sync: 'writer',
  fn_marketing_platform_spec_knowledge_sync: 'writer',
  fn_knowledge_library_fill_page: 'library build', fn_knowledge_library_recompute: 'library build',
  fn_knowledge_library_reconcile: 'library build', fn_knowledge_library_source_sql: 'library build', fn_knowledge_library_sync: 'library build',
};
test('every routine that reads ops_knowledge has a decision about outside callers', () => {
  const t = readSchemaMirror();
  const re = /CREATE OR REPLACE FUNCTION public\.([a-z0-9_]+)\(/gi;
  const at = []; let m;
  while ((m = re.exec(t))) at.push([m.index, m[1]]);
  const readers = new Set();
  for (let i = 0; i < at.length; i++) {
    let b = t.slice(at[i][0], i + 1 < at.length ? at[i + 1][0] : undefined);
    const stop = b.indexOf('\n-- ====='); if (stop > 0) b = b.slice(0, stop);
    if (/\bops_knowledge\b/.test(code(b))) readers.add(at[i][1]);
  }
  assert.ok(readers.has('fn_reason_retrieve') && readers.has('fn_sales_assist'), 'the mirror scan found none of the known readers');
  const undecided = [...readers].filter((r) => !READERS[r]).sort();
  assert.deepEqual(undecided, [], 'a routine reads ops_knowledge (all confidentiality internal) and nobody decided whether a customer or supplier reaches it: ' + undecided.join(', '));
  // the one routine that reads the corpus view must carry the filter (tested above), and the view has no other reader
  const viewReaders = at.filter(([i, n], k) => n !== 'fn_support_corpus_search'
    && /\b(from|join)\s+(public\.)?v_support_corpus\b/i.test(code(t.slice(i, k + 1 < at.length ? at[k + 1][0] : undefined).split('\n-- =====')[0])));
  assert.deepEqual(viewReaders.map(([, n]) => n), [], 'v_support_corpus (every ops row) has a reader other than fn_support_corpus_search');
});

test('the supplier English (e-mailed to every matched supplier) is reasoned for a supplier, never an internal audience', () => {
  const s = R('supabase/functions/_shared/supplier_english.ts');
  const hold = between(s, 'export async function holdForEnglish', '\n}');
  assert.match(hold, /context: \{ audience: 'supplier', language: 'en' \}/, 'the supplier copy is reasoned with the internal brief and internal knowledge');
});

// REVIEW OF #1660, 27 Oct 2026: the first version of this file redefined fn_sales_assist from a body that predated
// #1644 (a_harness_chat_turn_carries_its_run_tag_and_files_no_gap_or_task.sql), so applying it would have dropped
// #1644's v_test branch: sandbox and ZZ DEMO traffic would have filed knowledge gaps and opened org_tasks again. The
// static tests above only asked that the new predicates be present; nothing asked that everything else survive.
//   1. each body THIS file defines keeps every code line of the body it replaces (the newest definition before it in
//      apply order), except the one line the fix deliberately rewrites;
//   2. whatever file defines fn_sales_assist last keeps #1644's test-traffic branch.
// Mutated once each: this file rebuilt from the pre-#1644 body fails both.
function definitions(fn) {   // [{ file, body }] in apply order (MANIFEST, then pending), comments removed
  const re = new RegExp(`create or replace function public\\.${fn}\\(`, 'i');
  return [...manifestWithPending()].filter((f) => existsSync(join(ROOT, f)) && re.test(R(f))).map((file) => {
    const src = R(file); const from = src.search(re);
    const tag = src.slice(from).match(/\bas\s+(\$[a-z_]*\$)/i)[1];
    return { file, body: code(src.slice(from).split(tag)[1] || '') };
  });
}
const codeLines = (body) => body.split('\n').map((l) => l.trim()).filter(Boolean);
// the lines the ruling-1338 fix rewrites on purpose (everything else in a replaced body must survive)
const REWRITTEN = new Set(['where (case when p_public then c.is_public else true end)']);
test('every body this file defines keeps every code line of the body it replaces (review of #1660)', () => {
  for (const fn of ['fn_support_corpus_search', 'fn_sales_assist', 'fn_reason_retrieve', 'fn_reason_retrieve_ml']) {
    const defs = definitions(fn);
    const at = defs.findIndex((d) => d.file === FILE);
    assert.ok(at > 0, `${fn}: ${FILE} is not a later definition of an existing routine`);
    const mine = new Set(codeLines(defs[at].body));
    const lost = codeLines(defs[at - 1].body).filter((l) => !mine.has(l) && !REWRITTEN.has(l));
    assert.deepEqual(lost, [], `${fn}: ${FILE} drops lines of ${defs[at - 1].file}, the body it replaces`);
  }
});
test('the canonical fn_sales_assist keeps #1644: test traffic files no gap and opens no task', () => {
  const { owner, body } = canonical('fn_sales_assist');
  assert.match(body, /v_test\s+boolean := public\.fn_e2e_run_tag_current\(\) is not null or public\.fn_seat_work_is_demo\(p_text, null\);/, `${owner}: the v_test declaration is gone`);
  assert.match(body, /\bif v_test then\b/, `${owner}: the test-traffic branch is gone`);
  assert.match(body, /'gap_recorded', cardinality\(v_cited\) = 0 and not v_test,/, `${owner}: gap_recorded counts test traffic`);
  assert.match(body, /'test_traffic', v_test,/, `${owner}: test_traffic is no longer reported`);
});

test('the change is pending until the release applies it, and the probe is never applied', () => {
  const notes = pendingNotes();
  const inManifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).includes(FILE);
  assert.ok(inManifest || notes.has(FILE), 'the change is neither applied (MANIFEST) nor pending');
  assert.ok(!(inManifest && notes.has(FILE)), 'the change has a MANIFEST line AND a pending note');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('production, rolled back: no outside audience gets an internal ops row; internal still does; a public row reaches all four', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  // While the change is pending, its file runs first in the same request; the probe's raise rolls both back.
  const pre = pendingNotes().has(FILE) ? R(FILE) + '\n;\n' : '';
  let verdict = null; let out = null;
  try { await replaySql(pre + R(PROBE), { label: NAME, retry: false }); } catch (e) {
    const m = String(e.message || e).replace(/\\"/g, '"').match(/CHK<<(PROBE OK|LEAK|PROBE FAILED[^{]*) ?(\{[\s\S]*\})?>>/);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message || e).slice(0, 800));
    verdict = m[1].trim(); out = m[2] ? JSON.parse(m[2]) : null;
  }
  console.log('  ' + verdict + ' ' + JSON.stringify(out));
  assert.equal(verdict, 'PROBE OK', JSON.stringify(out?.fails ?? out));
  // the positive control flipped one row to 'public' inside the request; it must be internal again
  const left = await sql(`select confidentiality from public.ops_knowledge where record_id = '${String(out.subject).replace(/'/g, "''")}'`);
  assert.equal(left[0]?.confidentiality, 'internal', 'the probe left its subject row public');
});
