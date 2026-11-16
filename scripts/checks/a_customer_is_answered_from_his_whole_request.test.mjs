// A CUSTOMER IS ANSWERED FROM HIS WHOLE REQUEST, ON EVERY CHANNEL (customer_support, 16 Nov 2026; founder ledger 1711).
// "What happened with my inquiry? Did you find anyone below 5,000?" — the facts every customer channel reads now carry what he
// asked and what his portal shows him (scripts/sql/a_customer_is_answered_from_his_whole_request_on_every_channel.sql), and the
// model reasons over them (_shared/own_request_facts.ts OWN_REQUEST_RULE). The scenarios are a bank, not rules
// (scripts/eval/customer_follow_up_bank.mjs, 45 follow-ups in English, Arabic, Gulf dialect, Arabizi and a mix).
//
// What fails if it breaks:
//   offline — the bank shrinks, loses a group the founder named or points at a fact the SQL no longer gives; a consumer stops
//     giving the rule; the code grader stops catching a leaked supplier or a missing figure.
//   local database (QD_LOCAL_DB_URL, built by scripts/db/local_pg16.mjs or scripts/db/local_from_mirror.mjs; NEVER production)
//     — the bank's fixture is written and rolled back, and every fact each scenario needs is read from the WhatsApp fact pack
//     AND the own record (fn_wa_context, which the widget reads too); no unrevealed supplier, planted phone or planted brand is
//     in either. Without a local database that part is reported NOT RUN.
//   QD_CASEFACTS_OUT=<file outside the repository> also writes the facts the paid eval (scripts/eval/customer_follow_up/run.ts)
//   answers from.
//   env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL QD_LOCAL_DB_URL=<url> node --test scripts/checks/a_customer_is_answered_from_his_whole_request.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SCENARIOS, REQUESTS, COVERAGE, SUPPLIERS, PLANTED, TIMELINE, fixtureSql, has, codeGrade } from '../eval/customer_follow_up_bank.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const NAME = 'a_customer_is_answered_from_his_whole_request_on_every_channel';
const SQL = `scripts/sql/${NAME}.sql`;
const LOCAL = process.env.QD_LOCAL_DB_URL || '';

test('the bank holds at least 40 scenarios across languages and every group the founder named', () => {
  assert.ok(SCENARIOS.length >= 40, `${SCENARIOS.length} scenarios`);
  assert.equal(new Set(SCENARIOS.map((s) => s.id)).size, SCENARIOS.length, 'duplicate scenario id');
  for (const l of ['en', 'ar', 'mixed']) assert.ok(SCENARIOS.filter((s) => s.lang === l).length >= 4, `fewer than 4 scenarios in ${l}`);
  for (const s of SCENARIOS) {
    assert.ok(REQUESTS[s.req], `${s.id}: no request ${s.req}`);
    assert.ok(s.msg && s.judge && s.needs.length && ['answer', 'change', 'cancel', 'identity'].includes(s.action), `${s.id}: incomplete`);
  }
  for (const [g, ids] of Object.entries(COVERAGE)) for (const id of ids) assert.ok(SCENARIOS.some((s) => s.id === id), `${g}: ${id} missing`);
  const src = R(SQL);
  for (const s of SCENARIOS) for (const p of s.needs) for (const seg of p.split('.').filter((x) => x !== '*')) {
    assert.ok(src.includes(`'${seg}'`), `${s.id}: needs ${p}, and the SQL gives no key '${seg}'`);
  }
});

test('the code grader catches a missing figure, a sealed supplier and the planted phone', () => {
  const sc = SCENARIOS.find((s) => s.id === 'en_below_5k');
  assert.equal(codeGrade(sc, 'Two of your three quotes are below AED 5,000 before VAT: Supplier A AED 4,600 and Supplier B AED 4,900.').pass, true);
  assert.equal(codeGrade(sc, 'Supplier A is AED 4,600.').pass, false);
  assert.equal(codeGrade(sc, 'Cool Breeze Trading quoted AED 4,600 and B AED 4,900.').pass, false);
  assert.equal(codeGrade(sc, 'A AED 4,600, B AED 4,900; call 050 000 0111.').pass, false);
  assert.equal(codeGrade(SCENARIOS.find((s) => s.id === 'gulf_below_5k'), 'عرضان أقل من ٥٠٠٠: المورد A بـ ٤٬٦٠٠ درهم').pass, true);
});

test('every customer channel gives the model the one rule and the facts pass the code generaliser', () => {
  for (const f of ['supabase/functions/wa_inbound/compose.ts', 'supabase/functions/site_assistant/turn_facts.ts',
    'supabase/functions/sales_engineer/actions/portal.ts', 'supabase/functions/email_triage/account_facts.ts']) {
    assert.match(R(f), /OWN_REQUEST_RULE/, `${f} does not give OWN_REQUEST_RULE`);
  }
  for (const f of ['supabase/functions/wa_inbound/compose.ts', 'supabase/functions/site_assistant/turn_facts.ts', 'supabase/functions/email_triage/account_facts.ts']) {
    assert.match(R(f), /generaliseOwnRequestFacts\(/, `${f} hands sealed quote words to a model without the generaliser`);
  }
  assert.match(R('supabase/functions/email_triage/account_facts.ts'), /rpc\('fn_customer_inquiry_facts'/, 'e-mail does not read the one reading');
  assert.match(R('supabase/functions/sales_engineer/lib/own_quotes.ts'), /rpc\('fn_customer_inquiry_facts'/, 'the portal chat does not carry what he asked');
  assert.match(R('supabase/functions/_shared/support_case_memory.ts'), /REQUEST_IS_THE_RECORD \+/, 'the case block does not point at the request facts');
  // who-knows-what gaps 3 and 4: the portal chat reads his account and timeline; the e-mail reply gets the timeline it read
  assert.match(R('supabase/functions/sales_engineer/actions/portal.ts'), /customerRecordFacts\(live, events\)/, 'the portal chat is blind to his account and timeline');
  assert.match(R('supabase/functions/email_triage/index.ts'), /timelineReplyFacts\(tlText, relation/, 'the e-mail reply never sees the timeline');
  for (const s of SCENARIOS.filter((x) => x.timeline)) assert.ok(TIMELINE.length && ['portal', 'email'].includes(s.channel), `${s.id}: a timeline scenario names its door`);
  const manifest = R('scripts/sql/MANIFEST.txt').split('\n').includes(SQL);
  assert.ok(manifest !== existsSync(join(ROOT, `scripts/sql/pending/${NAME}.txt`)), 'the file needs exactly one of a MANIFEST line or a pending note');
});

test('local database: every fact each scenario needs is in the WhatsApp pack and the own record, and nothing sealed is', { skip: LOCAL ? false : 'NOT RUN: no local database (QD_LOCAL_DB_URL); never run against production' }, () => {
  assert.doesNotMatch(LOCAL, /supabase\.(co|com)|pooler/i, 'QD_LOCAL_DB_URL must be a LOCAL database');
  const input = ['begin;', R(SQL), fixtureSql(), 'rollback;'].join('\n');
  const r = spawnSync('psql', [LOCAL, '-q', '-tA', '-v', 'ON_ERROR_STOP=1'], { input, encoding: 'utf8', maxBuffer: 64 << 20, timeout: 120_000 });
  assert.equal(r.status, 0, 'the fixture did not run: ' + String(r.stderr).slice(0, 800));
  const line = String(r.stdout).trim().split('\n').filter((l) => l.startsWith('{')).pop();
  const out = JSON.parse(line);
  if (process.env.QD_CASEFACTS_OUT) writeFileSync(process.env.QD_CASEFACTS_OUT, JSON.stringify(out));
  const packReqs = out.pack?.identity?.requests ?? [];
  const mineReqs = out.mine?.inquiries ?? [];
  assert.equal(out.pack?.identity?.kind, 'customer', 'the fixture customer is not identified by the pack');
  const missing = [];
  for (const s of SCENARIOS) {
    const ref = out.refs[s.req];
    for (const [where, list] of [['pack', packReqs], ['own record', mineReqs]]) {
      const req = list.find((x) => x.ref === ref);
      if (!req) { missing.push(`${s.id}: request ${s.req} not in the ${where}`); continue; }
      for (const p of s.needs) if (!has(req, p)) missing.push(`${s.id}: ${p} missing in the ${where}`);
    }
  }
  assert.deepEqual(missing, [], missing.slice(0, 20).join('\n'));
  const text = JSON.stringify(out.pack) + JSON.stringify(out.mine);
  const sealed = Object.entries(SUPPLIERS).filter(([k]) => k !== 's5').map(([, n]) => n);
  for (const n of [...sealed, PLANTED.phone, PLANTED.ownBrand, PLANTED.ownBrand2]) assert.ok(!text.includes(n), `the facts carry "${n}" before a reveal`);
  assert.ok(text.includes(SUPPLIERS.s5), 'the revealed supplier is not named');
  const ac = packReqs.find((x) => x.ref === out.refs.AC);
  assert.deepEqual(ac.quotes.map((q) => [q.letter, q.price_ex_vat_aed, q.total_with_vat_aed]), [['A', 4600, 4830], ['B', 4900, 5145], ['C', 6200, 6510]]);
  assert.equal(ac.asked.budget_as_he_stated_it, 'AED 5,000 excluding VAT');
  assert.equal(packReqs.find((x) => x.ref === out.refs.FLOOR).quotes.length, 0);
  // REVIEW 16 Nov: no comparison in the facts; every quote the portal showed has its stored letter, so none is merely counted
  for (const req of [...packReqs, ...mineReqs]) assert.ok(!('comparison' in req), `request ${req.ref} carries a comparison`);
  assert.equal(ac.quotes_not_yet_on_his_portal, 0);
  // the paid eval composes on each scenario's route, as production does: a change or a cancel carries the database's answer
  for (const s of SCENARIOS) assert.ok(out.routes?.[s.id], `${s.id}: no route`);
  for (const s of SCENARIOS.filter((x) => ['change', 'cancel'].includes(x.action))) {
    assert.ok(String(out.routes[s.id].deterministic_reply || '').trim(), `${s.id}: the ${s.action} route gives no database answer`);
  }
});
