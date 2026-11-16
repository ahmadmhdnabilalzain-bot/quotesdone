// THE SUPPLIER IS KNOWN ON EVERY CHANNEL (customer_support, 16 Nov 2026; founder ledgers 1711-1713, who-knows-what items 5-7).
// "Why am I getting no jobs?", "why is my account not approved?", "is my quotation ready to submit?": every supplier door now reads
// one reading (fn_wa_context's supplier branch, scripts/sql/the_supplier_is_known_on_every_channel.sql) and words it once
// (_shared/supplier_known.ts). The scenarios are a bank, not rules (scripts/eval/supplier_known_bank.mjs, 16 messages, EN and AR,
// on WhatsApp, the widget, e-mail and the quotation chat).
//
// What fails if it breaks:
//   offline — the bank shrinks or loses a language or a door, points at a key the SQL no longer gives, a door stops reading or
//     wording the one reading, the code grader stops catching another supplier or the customer, or the SQL file has both or
//     neither of a MANIFEST line and a pending note.
//   local database (QD_LOCAL_DB_URL, built by scripts/db/local_pg16.mjs; NEVER production) — the bank's fixture is written and
//     rolled back; every key each scenario needs is in the supplier's reading, the words his door builds carry every `must`
//     group and none of `must_not`, and no reading carries another supplier's company or the customer. Without a local database
//     that part is reported NOT RUN.
//   env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL QD_LOCAL_DB_URL=<url> node --test scripts/checks/the_supplier_is_known_on_every_channel.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SCENARIOS, SUPPLIERS, CUSTOMER, fixtureSql, has, codeGrade } from '../eval/supplier_known_bank.mjs';
import { supplierStanding } from '../../supabase/functions/_shared/supplier_known.ts';
import { registeredSupplierFacts } from '../../supabase/functions/email_triage/account_facts.ts';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const NAME = 'the_supplier_is_known_on_every_channel';
const SQL = `scripts/sql/${NAME}.sql`;
const LOCAL = process.env.QD_LOCAL_DB_URL || '';
const DOORS = ['whatsapp', 'widget', 'email', 'quote_chat'];

/** The words a door gives the model from a reading: the e-mail reply adds his jobs; the others word the standing. */
const wordsFor = (door, sup, reading) => (door === 'email' ? registeredSupplierFacts(SUPPLIERS[sup].company, reading) : supplierStanding(reading));

test('the bank holds at least 12 supplier scenarios, in English and Arabic, on every supplier door', () => {
  assert.ok(SCENARIOS.length >= 12, `${SCENARIOS.length} scenarios`);
  assert.equal(new Set(SCENARIOS.map((s) => s.id)).size, SCENARIOS.length, 'duplicate scenario id');
  for (const l of ['en', 'ar']) assert.ok(SCENARIOS.filter((s) => s.lang === l).length >= 5, `fewer than 5 scenarios in ${l}`);
  for (const d of DOORS) assert.ok(SCENARIOS.filter((s) => s.door === d).length >= 2, `fewer than 2 scenarios on ${d}`);
  for (const s of SCENARIOS) {
    assert.ok(SUPPLIERS[s.sup] && DOORS.includes(s.door), `${s.id}: unknown supplier or door`);
    assert.ok(s.msg && s.judge && s.needs.length && s.must.length && Array.isArray(s.must_not), `${s.id}: incomplete`);
  }
  const src = R(SQL);
  for (const s of SCENARIOS) for (const p of s.needs) for (const seg of p.split('.').filter((x) => x !== '*')) {
    assert.ok(src.includes(`'${seg}'`), `${s.id}: needs ${p}, and the SQL gives no key '${seg}'`);
  }
});

test('the code grader catches a missing fact, another supplier and the customer', () => {
  const sc = SCENARIOS.find((s) => s.id === 'en_missed_request');
  assert.equal(codeGrade(sc, '1 request(s) in his trades were posted; Plumbing; sharjah').pass, true);
  assert.equal(codeGrade(sc, 'Plumbing in sharjah').pass, false);
  assert.equal(codeGrade(sc, `1 request(s) in his trades were posted; Plumbing; sharjah; it went to ${SUPPLIERS.ACTIVE.company}`).pass, false);
  assert.equal(codeGrade(sc, `1 request(s) in his trades were posted; Plumbing; sharjah; for ${CUSTOMER.name}`).pass, false);
});

test('every supplier door reads the one reading and words it once', () => {
  assert.match(R('supabase/functions/email_triage/account_facts.ts'), /registeredSupplierFacts\(String\(sup\.company_name \|\| ''\), await readSupplier\(admin, e\)\)/,
    'the e-mail reply does not read fn_wa_context');
  assert.doesNotMatch(R('supabase/functions/email_triage/account_facts.ts'), /from\('inquiry_matches'\)/, 'the e-mail reply reads jobs itself again');
  assert.match(R('supabase/functions/supplier_api/actions/quote_review_chat.ts'), /facts: withSupplierKnown\(v\.situation, known\)/, 'the quotation chat is blind to the supplier');
  assert.match(R('supabase/functions/wa_inbound/compose.ts'), /supplierStanding\(\(await prefetch\.mine\)/, 'WhatsApp does not word the standing');
  assert.match(R('supabase/functions/site_assistant/turn_facts.ts'), /supplierStanding\(o\.live\)/, 'the widget does not word the standing');
  assert.match(R('supabase/functions/_shared/supplier_known.ts'), /rpc\('fn_wa_context', \{ p_audience: 'supplier'/, 'the shared reading is not fn_wa_context');
  const manifest = R('scripts/sql/MANIFEST.txt').split('\n').includes(SQL);
  assert.ok(manifest !== existsSync(join(ROOT, `scripts/sql/pending/${NAME}.txt`)), 'the file needs exactly one of a MANIFEST line or a pending note');
});

test('local database: every scenario\'s facts are in the supplier\'s reading and his door\'s words, and nobody else is', { skip: LOCAL ? false : 'NOT RUN: no local database (QD_LOCAL_DB_URL); never run against production' }, () => {
  assert.doesNotMatch(LOCAL, /supabase\.(co|com)|pooler/i, 'QD_LOCAL_DB_URL must be a LOCAL database');
  const input = ['begin;', R(SQL), fixtureSql(), 'rollback;'].join('\n');
  const r = spawnSync('psql', [LOCAL, '-q', '-tA', '-v', 'ON_ERROR_STOP=1'], { input, encoding: 'utf8', maxBuffer: 64 << 20, timeout: 120_000 });
  assert.equal(r.status, 0, 'the fixture did not run: ' + String(r.stderr).slice(0, 800));
  const line = String(r.stdout).trim().split('\n').filter((l) => l.startsWith('{')).pop();
  const out = JSON.parse(line);
  const problems = [];
  for (const s of SCENARIOS) {
    const reading = out[s.sup];
    if (!reading || reading.known !== true) { problems.push(`${s.id}: ${s.sup} is not known`); continue; }
    for (const p of s.needs) if (!has(reading, p)) problems.push(`${s.id}: ${p} missing in the reading`);
    const g = codeGrade(s, wordsFor(s.door, s.sup, reading));
    for (const x of g.problems) problems.push(`${s.id} (${s.door}): ${x}`);
    const raw = JSON.stringify(reading);
    for (const [k, v] of Object.entries(SUPPLIERS)) if (k !== s.sup && raw.includes(v.company)) problems.push(`${s.id}: the reading names ${v.company}`);
    for (const c of [CUSTOMER.name, CUSTOMER.email, '500000093', 'kitchen sink leak']) if (raw.includes(c)) problems.push(`${s.id}: the reading carries the customer (${c})`);
  }
  assert.deepEqual(problems, [], problems.slice(0, 20).join('\n'));
  // the states the bank stands on, read back
  assert.deepEqual(out.ACTIVE.matching.why_no_jobs, [], 'an active supplier is given a reason he gets no jobs');
  assert.equal(out.HELD.matching.receives_requests_now, false);
  assert.equal(out.IDLE.matching.receives_requests_now, true);
});
