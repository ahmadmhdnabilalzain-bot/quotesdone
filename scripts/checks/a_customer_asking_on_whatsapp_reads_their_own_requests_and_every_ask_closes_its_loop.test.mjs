// A CUSTOMER ASKING ON WHATSAPP READS THEIR OWN REQUESTS, AND EVERY ASK CLOSES ITS LOOP (customer_support, 3 Nov 2026).
// Founder: "confirm that things are linked properly" and "not a single thing in our app is one-way communication".
//
// MEASURED 3 Nov 2026 on production (rolled back, ZZ DEMO): the fact pack told the model no job status could be given for
// any id, named an UNCONFIRMED number's customer and missed a confirmed other number; fn_wa_answer told a confirmed
// customer "I do not recognise this number"; a reveal of one quote exposed the exact low/high of all; a late request,
// a change and a cancel on WhatsApp reached no seat; a cancel told no supplier; a person request whose WhatsApp window
// had closed got no follow-up. The fix: scripts/sql/a_customer_asking_on_whatsapp_reads_their_own_requests_and_every_ask_closes_its_loop.sql.
//
// What fails if that breaks: the newest body of each routine loses its rule (static), or production does (the probe,
// in one rolled-back request with the file first). Mutated once: the probe against the pre-fix routines reports the
// failures above.
//   node --test scripts/checks/a_customer_asking_on_whatsapp_reads_their_own_requests_and_every_ask_closes_its_loop.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { manifestWithPending } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const NAME = 'a_customer_asking_on_whatsapp_reads_their_own_requests_and_every_ask_closes_its_loop';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN;

// The canonical body: the last file, in apply order (pending after), that defines it. Comments removed.
function canonical(fn) {
  const re = new RegExp(`create or replace function public\\.${fn}\\(`, 'i');
  const owner = [...manifestWithPending()].reverse().find((f) => existsSync(join(ROOT, f)) && re.test(R(f)));
  assert.ok(owner, `no applied or pending file defines ${fn}`);
  const src = R(owner);
  const from = src.search(re);
  const tag = src.slice(from).match(/\bas\s+(\$[a-z_]*\$)/i)[1];
  return { owner, body: code(src.slice(from).split(tag)[1] || '') };
}

test('the fact pack names only the confirmed customer and never says no request exists', () => {
  const { owner, body } = canonical('fn_wa_fact_pack');
  assert.doesNotMatch(body, /no job status can be given/i, `${owner}: the false "no live requests" line is back`);
  assert.match(body, /fn_whatsapp_owner\(p_phone\)[\s\S]*party_kind = 'customer'/, `${owner}: the customer is not the confirmed one`);
  assert.doesNotMatch(body, /from public\.customers\s+where regexp_replace\(coalesce\(phone/, `${owner}: customers.phone selects the customer again`);
  assert.match(body, /fn_customer_inquiry_facts\(c\.id/, `${owner}: the customer's own requests are not in the pack`);
});

test('a reveal unlocks that quote only: the band is of the unrevealed quotes', () => {
  const { owner, body } = canonical('fn_customer_inquiry_facts');
  assert.match(body, /avg\(q\.quote_amount\) filter \(where q\.revealed_at is null\)/, `${owner}: the band includes revealed quotes`);
  assert.doesNotMatch(body, /'low',\s*min\(q\.quote_amount\)/, `${owner}: the exact low/high of every quote is back`);
  assert.match(canonical('fn_wa_context').body, /fn_customer_inquiry_facts\(v_cust\.id/, 'fn_wa_context does not read the one reading');
});

test('a confirmed customer is a known party, and every ask acts', () => {
  const a = canonical('fn_wa_answer').body;
  assert.match(a, /fn_whatsapp_owner\(p_from\)[\s\S]*party_kind = 'customer'/, 'fn_wa_answer does not know a confirmed customer');
  assert.match(a, /fn_wa_customer_request_answer\(/, 'fn_wa_answer does not answer a customer from their requests');
  const w = canonical('fn_wa_customer_request_answer').body;
  assert.match(w, /fn_seat_handoff\('customer_support', 'sales_engineer', 'inquiry\.status_chase'/, 'a late request is not chased');
  assert.match(w, /fn_inquiry_change_from_customer\(/, 'a change reaches no supplier');
  assert.match(w, /fn_cancel_inquiry\(/, 'a cancel is not carried out');
  const c = canonical('fn_cancel_inquiry').body;
  assert.match(c, /'rfq_cancelled'/, 'a cancel tells no matched supplier');
  assert.match(c, /'inquiry_cancelled'/, 'a cancel is not confirmed to the customer');
  assert.match(canonical('fn_customer_support_closes_status_chases').body, /set_config\('qd\.handoff_closer', 'customer_support'/, 'the originator does not close the chase');
});

test('production, rolled back: every case and every loop answers PROBE OK', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  let msg = '';
  try { await replaySql(R(FILE) + '\n' + R(PROBE), { label: NAME, rows: false }); }
  catch (e) { msg = String(e?.body ?? e?.message ?? e); }
  assert.match(msg, /CHK<<PROBE OK/, msg.slice(0, 3000));
});
