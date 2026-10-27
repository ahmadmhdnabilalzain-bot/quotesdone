// A SANCTIONED PARTY IS UNREACHABLE ON EVERY SURFACE, AND THE RECORD SURVIVES.
//
// Founder instruction 516, 18 Sep 2026. He said "if any of them is in the sanctions delete that
// record totally", and when it was put to him that deleting destroys the proof we screened and
// frees the name to sign up again: "better banned i believe".
//
// WHY THIS CHECK EXISTS. Before 18 Sep the whole of "banned" was one boolean column, and exactly
// one surface read it: fn_is_matchable. A confirmed sanctions hit therefore stopped the RFQ
// matcher and NOTHING else — the party was still invited (the invite enqueuer counted a pool that
// excluded the banned and then selected recipients from a CTE that did not), still e-mailed, still
// listed in the supplier-facing company search, still able to sign in and edit its profile, and
// still able to register again the next morning under a new mailbox. That is the estate's "a status
// column is not a delivery record" lesson wearing an access-control hat, and it is the exact shape
// that comes back quietly when somebody adds a forty-first action to supplier_api.
//
// TWO HALVES, both required:
//
//   A. THE SURFACES, asserted against source. Each assertion is anchored on a CODE shape — a call
//      with its arguments, a return with its status — and never on a phrase, because a check that
//      greps for a sentence matches the comment that explains the fix (this has cost this repo two
//      false reds).
//   B. THE DATABASE, asserted by EXECUTION against production. It runs
//      scripts/sql/probe_a_sanctioned_party_is_unreachable.sql, which builds a ZZ DEMO party,
//      drives it to a confirmed hit and then tries, one at a time, to match it, invite it, message
//      it, re-register its name / licence / account e-mail, delete its lead, its hit, its register
//      row and the screening entry it cites, and un-ban it. The probe raises its verdict — the
//      Supabase management API discards `raise notice`, so a probe that reports with a notice
//      reports to nobody — and the raise rolls the whole transaction back, which is the only way to
//      run this against production: a sanctions_ban row cannot be deleted afterwards by design.
//
// If half B fails with "relation public.sanctions_ban does not exist", the PR carrying
// scripts/sql/a_sanctioned_party_is_banned_for_good_not_deleted.sql has not been applied yet:
//   node scripts/apply_sql.mjs scripts/sql/a_sanctioned_party_is_banned_for_good_not_deleted.sql --apply --ddl
// That is a real red, not a nuisance: until it is applied, nothing below is true in production.
//
//   node --test scripts/checks/a_sanctioned_party_is_unreachable.test.mjs
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { sql } from '../lib/db.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const PROJECT = 'htdblwldjkcgjvmqkbeh';
const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

const src = (p) => readFileSync(p, 'utf8');

// Each entry: the file, and the code shape that must be in it. The shapes are calls and returns.
const SURFACES = [
  ['supabase/functions/_shared/sanctioned.ts',
   "from('sanctions_ban')",
   'the shared helper must ask public.sanctions_ban, not leads.banned — a dues ban is reversible and must not lock a supplier out of paying'],

  // SIGN IN — mintSession is the only function in the estate that issues a supplier or customer
  // session, so the refusal lives inside it and both call sites map it to a 403.
  ['supabase/functions/login_otp/index.ts',
   'if (await sanctionedEmail(admin, email)) return \'sanctioned\';',
   'login_otp must refuse to mint a session for a sanctioned party'],
  ['supabase/functions/login_otp/index.ts',
   "if (s === 'sanctioned') return J(SANCTIONED_REFUSAL, 403);",
   'both sign-in branches must answer the refusal with 403, not a generic 500'],

  // ACT — one gate above the action switch in each of the two portal APIs.
  ['supabase/functions/supplier_api/index.ts',
   'if (await sanctionedEmail(admin, email)) return J(SANCTIONED_REFUSAL, 403);',
   'supplier_api must refuse every action for a sanctioned account'],
  ['supabase/functions/supplier_portal/index.ts',
   'sanctionedLead(admin, sup.id) || await sanctionedEmail(admin, email)) return J(SANCTIONED_REFUSAL, 403);',
   'supplier_portal must refuse every action for a sanctioned account'],

  // SHOWN — the supplier-facing company search, the invitation landing page, the reveal and the
  // supplier history a customer can open.
  ['supabase/functions/supplier_api/index.ts',
   'barred.has(String(r.id))',
   'the company-name search must drop sanctioned parties from its results'],
  ['supabase/functions/claim_lookup/index.ts',
   'l.banned === true',
   'the invitation landing endpoint must answer a banned lead the way it answers a closed one'],
  ['supabase/functions/customer_api/index.ts',
   'if (await sanctionedLead(admin, q.supplier_id)) return J(SANCTIONED_REFUSAL, 403);',
   'supplier_history must refuse to show a sanctioned party\'s profile'],
  // 22 Sep 2026 (customer-portal audit CP-09). These three lines used to be pinned one per
  // function, and stripe_checkout — the door that TAKES THE MONEY — was not pinned at all, because
  // it had no sanctions check to pin. The three reveal doors now go through one guard, so the
  // check follows the code: the guard must hold the refusal, and each door must call it. Pinning
  // the old per-file text would have meant keeping three copies of the check to keep the test
  // green, which is the defect this fix removed.
  ['supabase/functions/_shared/reveal_guard.ts',
   "if (await sanctionedLead(admin, q.supplier_id)) return refuse('account_sanctioned');",
   'the one reveal guard must refuse a sanctioned supplier'],
  ['supabase/functions/customer_api/index.ts',
   'const gate = await canReveal(admin, { quoteId: qid, customerId: String(cust.id) });',
   'the reveal must go through the guard BEFORE the customer is charged'],
  ['supabase/functions/stripe_checkout/index.ts',
   'const gate = await canReveal(admin, { quoteId: qid, customerId: String(cust.id) });',
   'checkout must go through the guard before a card is charged'],
  ['supabase/functions/stripe_confirm/index.ts',
   'const g = await canReveal(admin, { quoteId: qid, customerId: String(cust.id) });',
   'the post-payment identity release must hand back nothing for a sanctioned party'],

  // MESSAGED — the counterparty, not only the caller.
  ['supabase/functions/messages_api/index.ts',
   "if (await sanctionedLead(admin, supplier_id)) return J({ error: 'This conversation is closed.', code: 'account_sanctioned' }, 403);",
   'a customer must not be able to open a thread with, or message, a sanctioned party'],
  ['supabase/functions/customer_api/index.ts',
   'barredLosers.has(String(l.id))',
   'the losing-bidder notice must not be addressed to a sanctioned party'],

  // ACT, THE REST OF IT. The five functions above were the ones a session would think of; these
  // four authenticate a supplier by leads.claimed_by just as completely and were found by the
  // 18 Sep security review, not by the session that wrote the first five. Verification, payment,
  // catalogue upload and the assistant are all "acting".
  // kyc reads the ban in the same round trip as its other reads (28 Sep 2026, latency), then refuses before acting.
  ['supabase/functions/kyc/index.ts',
   'const [sanctioned, bodyIn, leadR, custR, leadWaR, custWaR] = await Promise.all([\n      sanctionedEmail(admin, email),',
   'kyc must read the ban for the signed-in email'],
  ['supabase/functions/kyc/index.ts',
   'if (sanctioned) return J(SANCTIONED_REFUSAL, 403);',
   'kyc must refuse a sanctioned party (it verifies identity and accepts terms)'],
  ['supabase/functions/supplier_pay/index.ts',
   'if (await sanctionedEmail(admin, email)) return J(SANCTIONED_REFUSAL, 403);',
   'supplier_pay must refuse a sanctioned party — a sanctions ban is not a debt to be cleared'],
  ['supabase/functions/supplier_catalog_ingest/index.ts',
   'if (await sanctionedEmail(admin, user.email.toLowerCase())) return J(SANCTIONED_REFUSAL, 403);',
   'catalogue upload must refuse a sanctioned party'],
  ['supabase/functions/site_assistant/index.ts',
   // #1036 (customer_support): identify() also returns the verified party id, so a signed-in widget chat is
   // logged as 'supplier:<lead id>' and lands on that supplier's support case. The refusal is unchanged.
   "if (sup) return (await sanctionedEmail(admin, email)) ? null : { email, audience: 'supplier', id: String(sup.id) };",
   'the site assistant must not recognise a sanctioned party as a supplier'],

  // FAIL CLOSED. A PostgREST error resolves as { data: null, error } rather than throwing, so a
  // helper that reads only `data` answers "not sanctioned" for every transient database failure —
  // and opens every gate above at the same moment.
  ['supabase/functions/_shared/sanctioned.ts',
   "if (r.error) throw new Error('sanctions_ban lookup failed",
   'the shared helper must fail closed on a lookup error, not answer "not sanctioned"'],

  // THE REFUSAL SAYS WHAT IS TRUE. The re-registration guard matches a NORMALISED name, so two
  // unrelated companies can collide; telling that applicant their account is closed is false twice.
  ['supabase/functions/supplier_api/index.ts',
   'return J(SANCTIONED_REGISTRATION_REFUSAL, 403);',
   'a refused registration must get its own wording, not the account-closed sentence'],

  // THE CHANNEL WITH NO SESSION TO REFUSE.
  ['scripts/sql/a_sanctioned_party_is_banned_for_good_not_deleted.sql',
   'and not exists (select 1 from public.sanctions_ban b where b.lead_id = l.id)',
   'fn_whatsapp_owner must stop resolving a handset to a sanctioned party — it is the root of fn_wa_lead_id, fn_conversation_party and fn_identify_contact'],
  ['scripts/sql/a_sanctioned_party_is_banned_for_good_not_deleted.sql',
   "set banned_until = 'infinity'::timestamptz",
   'the ban must reach the identity provider, so a session minted before it cannot be refreshed'],
];

test('A. every surface carries its refusal', () => {
  const missing = [];
  for (const [file, shape, why] of SURFACES) {
    // The shape is counted, not merely found: the point of anchoring on code is that a comment
    // cannot contain a call with its arguments, so a count of 0 is the only failure mode.
    if (!src(file).includes(shape)) missing.push(`${file}: ${why}\n    expected to contain: ${shape}`);
  }
  assert.equal(missing.length, 0, 'a sanctioned party is reachable again:\n  ' + missing.join('\n  '));
});

// THE INVITE ENQUEUER'S TWO POPULATIONS. The pool count and the recipient CTE must apply the same
// clause; they did not, for as long as the function has existed.
test('A2. the invitation enqueuer selects from the pool it counts', () => {
  const sql = src('scripts/sql/a_sanctioned_party_is_banned_for_good_not_deleted.sql');
  const cte = sql.slice(sql.indexOf('  cand as ('), sql.indexOf('  prio as ('));
  assert.ok(cte.includes('coalesce(l.banned,false) = false'),
    'the `cand` CTE in enqueue_supplier_invites must exclude banned leads, the way the pool count above it does');
});

test('B. production refuses a confirmed sanctions hit on every surface, and keeps the record', async (t) => {
  if (!mgmtToken) return t.skip('no Supabase management token in this environment');
  const query = src('scripts/sql/probe_a_sanctioned_party_is_unreachable.sql');
  // The probe ALWAYS ends in a raise, so the management API answers 400 carrying the verdict and
  // scripts/lib/db.mjs throws it. A 200 — sql() returning — means the probe did NOT reach its own
  // verdict, which is a failure, not a pass.
  //
  // This POSTed its own fetch with no backoff until 22 Sep 2026, and asserted `notEqual(429)` when
  // it was throttled. That turns a rate limit into a red test whose only remedy is a human re-run;
  // db.mjs retries seven times with jitter first and only then throws, and its message names the
  // throttle as infrastructure. The assertion on the verdict is unchanged.
  let text;
  try { text = JSON.stringify(await replaySql(query, { ref: PROJECT })); }
  catch (e) { if (e.throttled) throw e; text = String(e.message); }
  assert.ok(text.includes('CHK<<sanctioned party unreachable:'),
    'the production probe did not return its verdict. Raw answer:\n' + text.slice(0, 4000));
});

// THE RECORD IS STILL THERE AFTERWARDS. The probe rolls back, so this asserts the check itself
// left nothing behind — the demo party must not exist outside the aborted transaction.
test('C. the probe leaves nothing behind', async (t) => {
  if (!mgmtToken) return t.skip('no Supabase management token in this environment');
  // THE COUNT MUST BE A COUNT. Until 22 Sep 2026 this parsed the raw body without checking the
  // status, so a throttled run parsed `{"message":"ThrottlerException"}`, read `rows[0].n` as
  // undefined, and failed with "the probe left a ZZ DEMO party behind" — the residue this check
  // exists to catch, asserted from a request that never reached the database. Going through
  // db.mjs makes an unmeasured run throw as infrastructure instead of reporting a false residue.
  const rows = await sql(
    "select count(*)::int as n from public.leads"
    + " where company_name like 'ZZ DEMO Sanctioned%' or email like 'zz.demo.sanctioned%';",
    { ref: PROJECT, readOnly: true });
  assert.equal(typeof rows?.[0]?.n, 'number', `the residue count did not come back: ${JSON.stringify(rows).slice(0, 500)}`);
  assert.equal(rows[0].n, 0, 'the probe left a ZZ DEMO party behind — it must abort its own transaction');
});
