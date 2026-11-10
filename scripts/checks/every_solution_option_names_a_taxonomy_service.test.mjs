// EVERY SOLUTION OPTION NAMES A TAXONOMY SERVICE, AND EVERY SURFACE ADVISES AS AN EXPERT (10 Nov 2026). Seat: sales_engineer,
// with customer_support for WhatsApp. Subject: supabase/functions/_shared/solution_catalogue.json (.ts), _shared/inquiry_trades.ts,
// _shared/inquiry_reading.ts, the phase-2 columns of scripts/sql/every_inquiry_conversation_keeps_one_state_every_surface_reads.sql
// and scripts/sql/the_expert_inquiry_turns_on_the_portal_and_whatsapp_are_listed_model_consumers.sql. Founder ledger 1572,
// 1579 ("every trade, product and service"), 1586 (every trade in the UAE but food and beverage, location rules).
//
// FILES (always, offline). It fails when:
//   * an option names a service key that no scripts/sql taxonomy seed defines (a key no supplier can ever tick matches
//     nobody), or a family names a trade slug no conversation playbook carries;
//   * the request chat's prompt carries the old ban ("Do not pitch", "your only job is to collect") or loses the ADVISE rule,
//     the reference options, the trade pack or the whole taxonomy;
//   * the portal or WhatsApp stops giving the model the ADVISE rule, stops answering a job on the interview class, or stops
//     reading the state back (the reader);
//   * a model class the portal or WhatsApp names in code is not in the consumers file, or that file is neither listed nor
//     waiting with a note;
//   * the state's phase-2 columns are not written by fn_inquiry_state_merge or not carried by fn_inquiry_state_carry.
// PRODUCTION (when a management token exists; read-only): every option's service key is an ACTIVE taxonomy_trade_service row.
//   node --test scripts/checks/every_solution_option_names_a_taxonomy_service.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const read = (f) => fs.readFileSync(path.join(ROOT, f), 'utf8');
const FN = 'supabase/functions/';
const code = (f) => read(f).split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n');
const CAT = JSON.parse(read(FN + '_shared/solution_catalogue.json'));
const KEYS = [...new Set(CAT.families.flatMap((f) => f.problems.flatMap((p) => p.options.flatMap((o) => o.services))))].sort();

// ('trade','code','Label EN','Label AR', n): the shape the taxonomy seeds use (as every_demo_service_sentence_names_exact_taxonomy_labels)
const seeded = new Set();
for (const f of fs.readdirSync(path.join(ROOT, 'scripts/sql')).filter((x) => x.endsWith('.sql'))) {
  for (const m of read('scripts/sql/' + f).matchAll(/\(\s*'([a-z0-9_]+)'\s*,\s*'([a-z0-9_]+)'\s*,\s*'(?:[^']|'')+'\s*,\s*'[^']*'\s*,\s*\d+\s*\)/g)) seeded.add(m[1] + '.' + m[2]);
}

test('the seeds were read, and every option names a seeded taxonomy service', () => {
  assert.ok(seeded.has('wallpaper.wall_panels') && seeded.size > 500, `taxonomy seed tuples not found (${seeded.size})`);
  const missing = KEYS.filter((k) => !seeded.has(k));
  assert.deepEqual(missing, [], 'an option names a service no seed defines: ' + missing.join(', '));
});

test('every family names trades the conversation playbooks carry, and the catalogue covers at least 20 families', () => {
  const cats = new Set(fs.readdirSync(path.join(ROOT, 'knowledge/brief/conversation')).flatMap((f) =>
    (read('knowledge/brief/conversation/' + f).match(/^\*\*Categories:\*\*\s*(.+)$/m)?.[1] ?? '').split(',').map((s) => s.trim()).filter(Boolean)));
  assert.ok(cats.size >= 50, 'playbook categories not read');
  const bad = CAT.families.flatMap((f) => f.trades.filter((t) => !cats.has(t)).map((t) => `${f.code}: ${t}`));
  assert.deepEqual(bad, []);
  assert.ok(CAT.families.length >= 20, CAT.families.length + ' families');
});

test('the request chat advises: the old ban is gone, the rule, the options, the pack and the taxonomy are in its prompt', () => {
  const h = read(FN + 'inquiry_intake/handle.ts');
  assert.doesNotMatch(h, /Do not pitch, quote prices/, 'the old ban is back in the identity');
  assert.doesNotMatch(h, /your only job is to collect a complete, accurate brief/);
  for (const x of ['${ADVISE_RULE}', 'solutionsBlock(refProblems', 'problemIndex()', 'tradeBlock(tradeCtx', 'taxonomyBlock(taxonomy)', 'solutionStateText(st',
    'withPack(checklist, tradeCtx', 'validCodes(out.trade_codes', 'readSolution(out)', 'solutionPatch(', 'brief.trade_codes = codesNow', 'brief.service_keys']) assert.ok(h.includes(x), 'handle.ts: ' + x);
  const c = code(FN + 'customer_api/actions/inquiry_create.ts');
  assert.ok(c.includes('service_keys: intakeServiceKeys') && c.includes('...intakeTradeCodes'), 'the inquiry does not carry the settled services and trades');
});

test('the portal and WhatsApp advise on the interview class and read the state back', () => {
  const p = code(FN + 'sales_engineer/actions/portal.ts');
  for (const x of ['ADVISE_RULE', "jobTalk ? 'inquiry_qualification_conversation' : 'customer_portal_assistant'", 'readInquiry(gatewayAsk(', 'readingPatch(reading)', 'tradeBlock(ce.ctx', 'solutionsBlock(refProblems']) assert.ok(p.includes(x), 'portal.ts: ' + x);
  const s = code(FN + 'wa_inbound/say.ts');
  for (const x of ['ADVISE_RULE', "taskClass: 'inquiry_qualification_conversation'", 'readInquiry(ask', 'readingPatch(r)', "aud === 'customer' || aud === 'visitor'"]) assert.ok(s.includes(x), 'say.ts: ' + x);
  assert.match(code(FN + 'wa_inbound/model_says.ts'), /r\.expert && r\.audience !== 'supplier'/, 'a supplier must never get the expert block');
  assert.match(code(FN + '_shared/ai_reply.ts'), /taskClass: r\.taskClass \?\? REPLY_CLASS/);
});

test('each class those surfaces name is a listed consumer, and the consumers file is pending or listed', () => {
  const NAME = 'the_expert_inquiry_turns_on_the_portal_and_whatsapp_are_listed_model_consumers';
  const sql = read(`scripts/sql/${NAME}.sql`);
  assert.match(sql, /^-- .*\n-- Seat: sales_engineer/m);
  for (const c of ['sales_engineer:inquiry_qualification_conversation', 'wa_inbound:inquiry_qualification_conversation', 'sales_engineer:json_extraction', 'wa_inbound:json_extraction']) assert.ok(sql.includes(`'${c}'`), c);
  assert.match(sql, /'PROBE OK: [^']+' *\n?\s*else 'PROBE FAILED/);
  const listed = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(`scripts/sql/${NAME}.sql`);
  const pending = fs.existsSync(path.join(ROOT, `scripts/sql/pending/${NAME}.txt`));
  assert.ok(listed !== pending, 'exactly one of: a MANIFEST line or a pending note');
});

test('the phase-2 columns are written by the merge and carried by the carry', () => {
  const sql = read('scripts/sql/every_inquiry_conversation_keeps_one_state_every_surface_reads.sql');
  for (const c of ['condition', 'options_offered', 'chosen_option', 'budget']) {
    assert.match(sql, new RegExp(`alter table public\\.inquiry_state add column if not exists ${c} jsonb`), c + ' column');
    assert.ok(sql.includes(`${c} = s.${c}`), c + ' not written by the merge');
    assert.ok(sql.includes(`f.${c}`), c + ' not carried');
  }
  assert.match(read('scripts/sql/every_inquiry_conversation_keeps_one_state_every_surface_reads_probe.sql'), /the phase-2 state was not carried/);
});

test('PRODUCTION: every option names an active taxonomy service (read-only; skipped without a token)', async (t) => {
  if (!process.env.SUPABASE_ACCESS_TOKEN || process.env.QD_OFFLINE === '1') { t.skip('no management token (offline)'); return; }
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select trade_code || '.' || code as k from public.taxonomy_trade_service where active`, { readOnly: true });
  const live = new Set(rows.map((x) => x.k));
  assert.ok(live.size > 500, 'the live vocabulary was not read');
  assert.deepEqual(KEYS.filter((k) => !live.has(k)), [], 'an option names a service that is not active in production');
});
