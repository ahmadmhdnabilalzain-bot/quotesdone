// PAYMENTS ARE THE ACCOUNTANT'S, AND THE SEATS TALK ABOUT MONEY THROUGH HANDOFFS.
//
// Founder, 14 Sep 2026: "anything related to payment is under the accountant agent. and the accountant
// need to be in communication back and forth with the sales agent. its one company eventually." And:
// "the only agent who uses the whatsapp and email is the customer support agent."
//
// Statically (runs in CI without a token):
//   * only accountant-owned functions call Stripe, and none of them writes the outbox itself
//   * the list of conversations in supabase/functions/_shared/payment_handoffs.ts is the list in
//     fn_seat_handoff_types (scripts/sql/payments_are_the_accountant_and_the_seats_close_every_refund_together.sql)
//   * every conversation has a producer (something that starts it) and the receiving seat has a handler
// Against production (skipped without a management token):
//   * function_owner and llm_seat_binding for every payment slug say 'accountant'
//   * the live fn_seat_handoff_types() is the same list, and every trigger that starts a conversation exists
//   * THE WHOLE LADDER on ZZ DEMO fixtures -- the routine file and scripts/checks/refund_ladder_fixtures.sql
//     run as ONE batch that always rolls back -- eleven scenarios, from the happy path through every
//     mismatch the CEO's playbook fixes. Nothing it writes survives and nothing it queues is sent.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FNS = join(REPO, 'supabase', 'functions');
const SQL = join(REPO, 'scripts', 'sql');
const FILES = ['payments_are_the_accountant_and_the_seats_close_every_refund_together.sql'];

// Every payment function, as function_owner lists them. quote_pdf has an owner row and no directory
// in this repository (it is not deployed from here); it is checked against production only.
export const PAYMENT_SLUGS = ['stripe_checkout', 'stripe_confirm', 'stripe_webhook', 'stripe_setup', 'stripe_setup_page',
  'supplier_pay', 'reveal_invoice', 'quote_pdf', 'refunds_api', 'refund_flow', 'accountant'];

const read = (p) => readFileSync(p, 'utf8');
const walk = (d) => readdirSync(d).flatMap((f) => {
  const p = join(d, f);
  return statSync(p).isDirectory() ? walk(p) : /\.tsx?$/.test(f) && !/\.test\./.test(f) ? [p] : [];
});
const slugs = readdirSync(FNS).filter((s) => !s.startsWith('_') && statSync(join(FNS, s)).isDirectory());
const fnSource = (s) => walk(join(FNS, s)).map(read).join('\n');
const sqlText = FILES.map((f) => read(join(SQL, f))).join('\n');

function tsRegistry() {
  const src = read(join(FNS, '_shared', 'payment_handoffs.ts'));
  return [...src.matchAll(/\{ type: '([a-z_.]+)', from: '([a-z_]+)', to: '([a-z_]+)' \}/g)].map((m) => `${m[1]}|${m[2]}|${m[3]}`).sort();
}
function sqlRegistry() {
  const body = sqlText.slice(sqlText.indexOf('create or replace function public.fn_seat_handoff_types()'));
  const values = body.slice(0, body.indexOf('$fn$;'));
  return [...values.matchAll(/\('([a-z_.]+)',\s*'([a-z_]+)',\s*'([a-z_]+)',/g)].map((m) => `${m[1]}|${m[2]}|${m[3]}`).sort();
}
function fnBody(name) {
  const at = sqlText.indexOf(`create or replace function public.${name}(`);
  assert.ok(at >= 0, `${name} is not defined in the routine file`);
  return sqlText.slice(at, sqlText.indexOf('$fn$;', at));
}

test('only accountant-owned functions call Stripe', () => {
  const bad = slugs.filter((s) => !PAYMENT_SLUGS.includes(s) && /api\.stripe\.com/.test(fnSource(s)));
  assert.deepEqual(bad, [], 'a Stripe call outside the accountant\'s functions');
});

test('no payment function writes the outbox itself: customer_support delivers', () => {
  const bad = PAYMENT_SLUGS.filter((s) => existsSync(join(FNS, s)) && /from\('notifications'\)\s*\.insert/.test(fnSource(s)));
  assert.deepEqual(bad, [], 'a payment function queues email or WhatsApp directly');
});

test('the list of conversations is the same in TypeScript and in the database file', () => {
  const ts = tsRegistry(); const sql = sqlRegistry();
  assert.ok(ts.length >= 20, `only ${ts.length} conversations parsed from payment_handoffs.ts`);
  assert.deepEqual(ts, sql);
});

test('every conversation has a producer and a handler in the receiving seat', () => {
  const handlers = {
    sales_engineer: fnBody('fn_sales_engineer_acts_on_handoff'),
    accountant: fnBody('fn_accountant_acts_on_handoff'),
    customer_support: fnBody('fn_customer_support_acts_on_handoff'),
  };
  const ts = slugs.map(fnSource).join('\n');
  const missing = [];
  for (const k of tsRegistry()) {
    const [type, from, to] = k.split('|');
    if (!handlers[to].includes(`'${type}'`)) missing.push(`${k}: ${to} has no handler`);
    const produced = sqlText.includes(`fn_seat_handoff('${from}', '${to}', '${type}'`)
      || (type === 'delivery.request' && from === 'sales_engineer' && sqlText.includes('fn_seat_handoff(\'sales_engineer\', \'customer_support\', \'delivery.request\''))
      || new RegExp(`p_from: '${from}', p_to: '${to}', p_type: '${type.replace('.', '\\.')}'`).test(ts)
      || (type === 'refund.remediate' && sqlText.includes("fn_seat_handoff('ceo', x.owner, 'refund.remediate'"))
      || (type === 'incident.fix' && sqlText.includes("fn_seat_handoff('ceo', 'accountant', 'incident.fix'"));
    if (!produced) missing.push(`${k}: nothing starts it`);
  }
  assert.deepEqual(missing, []);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('production: every payment function and model binding is the accountant\'s', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const owners = new Map((await sql('select function_slug, owner from public.function_owner')).map((r) => [r.function_slug, r.owner]));
  const binds = new Map((await sql('select fn, seat from public.llm_seat_binding')).map((r) => [r.fn, r.seat]));
  const bad = [];
  for (const s of PAYMENT_SLUGS) {
    if (owners.get(s) !== 'accountant') bad.push(`${s}: owner=${owners.get(s) ?? '(none)'}`);
    if (binds.has(s) && binds.get(s) !== 'accountant') bad.push(`${s}: llm_seat_binding=${binds.get(s)}`);
  }
  assert.deepEqual(bad, []);
});

test('production: the live conversations and the triggers that start them', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const live = (await sql('select type, from_seat, to_seat from public.fn_seat_handoff_types()')).map((r) => `${r.type}|${r.from_seat}|${r.to_seat}`).sort();
  assert.deepEqual(live, tsRegistry(), 'production fn_seat_handoff_types() is not the repository\'s list (is the file applied?)');
  const trg = (await sql(`select c.relname || '.' || t.tgname as t from pg_trigger t join pg_class c on c.oid = t.tgrelid
                           where not t.tgisinternal and t.tgname in ('z20_reveal_receipt','z30_refund_request_hands_to_accountant',
                             'z40_refund_outcome_follows_through','a05_ceo_refund_approval_checks_the_process',
                             'z20_refund_case_approval_checks_the_process','z50_external_refund_is_verified')`)).map((r) => r.t).sort();
  assert.deepEqual(trg, ['ceo_approval.a05_ceo_refund_approval_checks_the_process', 'refund_case.z20_refund_case_approval_checks_the_process',
    'refunds.z30_refund_request_hands_to_accountant', 'refunds.z50_external_refund_is_verified',
    'transactions.z20_reveal_receipt', 'transactions.z40_refund_outcome_follows_through']);
  const [{ n }] = await sql("select count(*)::int n from pg_proc where proname = 'trg_reveal_receipt' and prosrc like '%fn_seat_handoff%'");
  assert.equal(n, 1, 'trg_reveal_receipt still writes the reveal messages itself');
});

test('production: the whole refund ladder on ZZ DEMO fixtures, rolled back', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const batch = [...FILES.map((f) => read(join(SQL, f))), read(join(REPO, 'scripts', 'checks', 'refund_ladder_fixtures.sql'))].join('\n;\n');
  let message = '';
  try { await sql(batch); message = 'the fixture batch returned without raising, so it did not roll back'; } catch (e) { message = String(e.message); }
  const chk = message.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(chk, message.slice(0, 2000));
  const res = JSON.parse(chk[1].replace(/\\"/g, '"'));
  for (const k of ['1_happy_ladder', '2_accountant_fix', '3_sales_engineer_fix', '4_failed_delivery_and_escalation', '5_whatsapp_proof',
    '6_under_refund', '7_stripe_failed', '8_duplicate_refund', '9_wrong_charge_sent', '10_missed_handoff', '11_over_refund']) {
    assert.ok(res[k], `scenario ${k} did not report`);
  }
  assert.equal(res['1_interest_30_days_aed'], 2.61);
  assert.equal(res['1_accrual_second_run_changed'], 0);
});
