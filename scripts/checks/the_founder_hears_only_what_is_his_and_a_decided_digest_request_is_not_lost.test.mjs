// THE FOUNDER HEARS ONLY WHAT IS HIS, AND A REQUEST THE IT DIGEST HOLDS OR DECIDED IS NOT A LOST DELIVERY
// (built by it_engineer, agent L3_IT, 16 Nov 2026, founder ledger 1557; rulings 9, 1696, 1710).
// Measured before (SELECT, 7 days to 16 Nov 2026): 171 of 197 founder_alerts rows were the masking log line
// 'inquiry_contact_masked'; 213 of the 1,025 "no confirmed outcome" delivery incidents were it_new_bug requests the IT digest
// had already decided ('fixed' 130, 'internal' 83); the VAT threshold asked the founder to decide registration although
// ruling 9 sends it to the CEO. Three files, each with its probe:
//   scripts/sql/a_masked_contact_is_logged_as_a_company_event_not_a_founder_alert.sql            (sales_engineer)
//   scripts/sql/a_request_the_it_digest_holds_or_has_decided_is_never_an_unconfirmed_delivery.sql  (it_engineer)
//   scripts/sql/the_ceo_decides_vat_registration_and_the_founder_is_not_asked.sql                  (accountant)
// Left with the founder on purpose: refund_ceo_summary (ruling 183: "sends the founder a short WhatsApp summary") and the
// finance_alert of fn_accountant_escalates_payment_exception (a payment that did not reconcile, the same money-mismatch
// summary); founder_mail_policy is unchanged.
// LOCAL (QD_LOCAL_DB_URL = a LOCAL Postgres 16 with production's bodies; never production): each file applies twice to a copy
// and its probe answers PROBE OK twice.
//   env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL QD_LOCAL_DB_URL=postgresql://postgres@%2Fdev%2Fshm%2Fpg-L3IT:55440/l3base \
//     node --test scripts/checks/the_founder_hears_only_what_is_his_and_a_decided_digest_request_is_not_lost.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const MASK = 'a_masked_contact_is_logged_as_a_company_event_not_a_founder_alert';
const DIGEST = 'a_request_the_it_digest_holds_or_has_decided_is_never_an_unconfirmed_delivery';
const VAT = 'the_ceo_decides_vat_registration_and_the_founder_is_not_asked';
const code = (name) => read(`scripts/sql/${name}.sql`).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

test('1. the masking is logged once per inquiry as a company event, never in the founder\'s alert ledger', () => {
  const c = code(MASK);
  assert.doesNotMatch(c, /insert into public\.founder_alerts/, 'no founder_alerts row');
  assert.match(c, /insert into public\.company_event \(event_type, entity_type, entity_id, actor, payload, dedupe_key\)\s*select 'inquiry\.contact_masked', 'inquiry', new\.id::text, 'sales_engineer'/);
  assert.match(c, /'inquiry\.contact_masked:' \|\| new\.id\s*where new\.id is not null\s*and not exists/, 'once per inquiry');
  assert.doesNotMatch(c.slice(c.indexOf('company_event')), /new\.(summary|raw_input|budget|spec|boq)\b/, 'the event carries ids, never the text');
  assert.match(c, /new\.summary_masked\s*:= public\.mask_project_identity\(public\.mask_contacts\(new\.summary\)\)/, 'the masking is unchanged');
});

test('2. a request the IT digest decided, or still holds before it has run, is not an unconfirmed delivery', () => {
  const c = code(DIGEST);
  assert.match(c, /and not \(a\.status = 'done' and coalesce\(a\.evidence->>'digest', ''\) in \('fixed', 'internal', 'sent'\)\)/,
    'a decided request is finished work (coalesce: a request with no digest is still judged)');
  assert.match(c, /or not exists \(select 1 from public\.founder_alerts d\s*where d\.dedupe_key like 'it\\_daily\\_digest:%'/,
    'a waiting request is late only once a digest has run since its hold');
  assert.match(c, /'title', 'Delivery request ' \|\| x\.id/, 'the detector itself still raises a lost delivery');
});

test('3. the VAT registration decision goes to the CEO, never to the founder', () => {
  const c = code(VAT);
  assert.doesNotMatch(c, /fn_seat_handoff\('accountant', 'customer_support', 'delivery\.request', 'founder'/, 'no founder delivery request');
  assert.doesNotMatch(c, /your decision is needed/);
  assert.match(c, /public\.fn_support_report_to_ceo\(/, 'the CEO is still told');
  assert.match(c, /when v_frac >= coalesce\(v_dec, 1\)\s*then 'Decide whether QuotesDone registers for UAE VAT now or at the threshold/, 'and asked to decide');
});

test('4. each file is pending with its probe, and the founder kinds his rulings keep are untouched', () => {
  const manifest = read('scripts/sql/MANIFEST.txt');
  for (const n of [MASK, DIGEST, VAT]) {
    assert.ok(existsSync(join(REPO, `scripts/sql/pending/${n}.txt`)) !== manifest.includes(`${n}.sql`), `${n}: a pending note or a MANIFEST line`);
    assert.ok(existsSync(join(REPO, `scripts/sql/pending/${n}_probe.txt`)) && !manifest.includes(`${n}_probe.sql`), `${n}: the probe is never applied`);
    assert.doesNotMatch(code(n), /founder_mail_policy/, `${n}: founder_mail_policy unchanged (rulings 183 keep refund_ceo_summary and the payment summary with him)`);
  }
});

const URL_ = process.env.QD_LOCAL_DB_URL ?? '';
const isLocal = /^postgres(ql)?:\/\/[^@]*@(%2F|localhost|127\.0\.0\.1)/i.test(URL_);
const LOCAL_SKIP = !URL_ ? 'QD_LOCAL_DB_URL not set (a local Postgres 16 built from the mirror)' : !isLocal ? 'QD_LOCAL_DB_URL is not a local database: refused' : false;

test('5. (local Postgres) each file applies twice and its probe answers PROBE OK twice', { skip: LOCAL_SKIP, timeout: 300000 }, () => {
  const db = 'founder_check_' + process.pid;
  const admin = (args) => spawnSync('psql', [URL_, '-v', 'ON_ERROR_STOP=1', '-q', ...args], { encoding: 'utf8' });
  const at = (args) => spawnSync('psql', [URL_.replace(/\/[^/?]+(\?|$)/, `/${db}$1`), '-q', ...args], { encoding: 'utf8' });
  const tpl = URL_.match(/\/([^/?]+)(\?|$)/)[1];
  assert.equal(admin(['-c', `create database ${db} template ${tpl}`]).status, 0, 'the copy of the local database');
  try {
    for (const n of [MASK, DIGEST, VAT]) {
      for (let i = 0; i < 2; i++) {
        const r = at(['-v', 'ON_ERROR_STOP=1', '-1', '-f', join(REPO, `scripts/sql/${n}.sql`)]);
        assert.equal(r.status, 0, `${n} does not apply: ${r.stderr.slice(0, 600)}`);
      }
      for (let i = 0; i < 2; i++) {
        const out = at(['-f', join(REPO, `scripts/sql/${n}_probe.sql`)]).stderr;
        assert.match(out, /CHK<<PROBE OK/, `${n} probe: ${out.slice(0, 1200)}`);
      }
    }
  } finally { admin(['-c', `drop database if exists ${db}`]); }
});
