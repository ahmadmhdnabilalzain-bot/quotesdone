// THE ACCOUNTANT'S DUTIES NEVER END IN A ONE-WAY MESSAGE.
//
// Founder, 14 Sep 2026: "yea add them all", "yea add them", and "always make sure things are in loop.
// nothing literally should ever be a one way communication". The duties are the scripts/sql files named
// in FILES; scripts/checks/accountant_duties_fixtures.sql proves each loop on ZZ DEMO fixtures.
//
// Statically (runs in CI without a token):
//   * Stripe's dispute events are in HANDLED_STRIPE_EVENTS and stripe_webhook branches on them
//   * every duty the hourly routine names is defined in the files, and every finding goes through
//     fn_accountant_duty_settle (the IT loop's ledger), never straight to the outbox or the founder
//   * no reminder or final-demand wording is typed into a routine: it is read from decision_policy
// Against production (skipped without a management token):
//   * the files and the fixtures run as ONE batch that always rolls back; every duty's loop closes
//
//   node --test scripts/checks/the_accountant_closes_every_loop_it_opens.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const SQL = join(REPO, 'scripts', 'sql');
// In apply order: the loop core first, the hourly routine last.
export const FILES = [
  'the_accountant_raises_its_findings_into_the_loop_the_it_engineer_runs.sql',
  'the_accountant_matches_every_stripe_payout_to_the_bank.sql',
  'the_accountant_bills_every_supplier_after_the_thousandth.sql',
  'the_money_a_refund_could_still_take_back_is_held_not_earned.sql',
  'every_reveal_charge_is_audited_against_what_stripe_took.sql',
  'the_companys_own_bank_and_stripe_costs_book_themselves.sql',
  'the_accountant_answers_every_card_dispute_before_stripe_closes_it.sql',
  'the_accountant_watches_the_vat_threshold_and_tells_the_ceo.sql',
  'the_accountant_closes_every_month_and_the_ceo_signs_for_it.sql',
  'the_accountant_chases_what_a_silent_supplier_owes.sql',
  'every_expense_has_its_receipt_and_every_subscription_its_renewal.sql',
  'the_accountant_runs_its_duties_every_hour.sql',
  // The five further duties (14 Sep 2026) in their MANIFEST order, and the backup registry after them: it
  // owns fn_it_backup_expected, whose SQL body reads the year-end table. The batch applies these in the real
  // final order, so a second, older definition winning would fail the year-end fixture (review of #659).
  'every_meta_invoice_is_matched_to_the_spend_meta_reported.sql',
  'every_supplier_charge_claim_is_tracked_to_payment_or_court_on_the_uae_clock.sql',
  'the_accountant_budgets_every_renewal_the_it_engineer_sees_coming.sql',
  'the_accountant_tells_the_ceo_every_month_what_is_in_the_bank_and_how_long_it_lasts.sql',
  'the_accountant_files_the_year_end_pack_in_dropbox_and_the_backups_bucket.sql',
  'every_stored_document_source_is_registered_for_backup.sql',
];

// Every routine is defined in exactly ONE of the files: a second body is a second answer, and the file
// applied last would silently decide which one runs.
test('no routine is defined in two of the accountant\'s files', () => {
  const owner = new Map();
  for (const f of FILES) {
    for (const m of read(join(SQL, f)).matchAll(/create or replace function public\.([a-z0-9_]+)\(/g)) {
      const prev = owner.get(m[1]);
      assert.ok(!prev || prev === f, `${m[1]} is defined in both ${prev} and ${f}`);
      owner.set(m[1], f);
    }
  }
});
const read = (p) => readFileSync(p, 'utf8');
const sqlText = FILES.map((f) => read(join(SQL, f))).join('\n');
const fnBody = (name) => {
  const at = sqlText.lastIndexOf(`create or replace function public.${name}(`);
  assert.ok(at >= 0, `${name} is not defined in the accountant's files`);
  return sqlText.slice(at, sqlText.indexOf('$fn$;', at));
};

test('Stripe disputes are handled events and the webhook records them', () => {
  const ev = read(join(REPO, 'supabase', 'functions', '_shared', 'stripe_events.ts'));
  for (const e of ['charge.dispute.created', 'charge.dispute.updated', 'charge.dispute.closed']) assert.match(ev, new RegExp(`'${e.replace(/\./g, '\\.')}'`));
  assert.match(ev, /HANDLED_STRIPE_EVENTS[^;]*\.\.\.DISPUTE_EVENTS/);
  const wh = read(join(REPO, 'supabase', 'functions', 'stripe_webhook', 'index.ts'));
  assert.match(wh, /DISPUTE_EVENTS as readonly string\[\]\)\.includes/);
  assert.match(wh, /fn_accountant_dispute_record/);
});

test('every duty the hour runs is defined, and every one settles through the loop', () => {
  const duties = fnBody('fn_accountant_duties');
  const called = [...duties.matchAll(/public\.(fn_[a-z_]+)\(/g)].map((m) => m[1]);
  for (const f of new Set(called)) if (f !== 'fn_accountant_duty_stage') fnBody(f);
  for (const d of ['fn_accountant_bank_reconcile', 'fn_accountant_collections_tick', 'fn_accountant_subscription_tick',
    'fn_accountant_expense_duty', 'fn_accountant_charge_audit_record', 'fn_accountant_disputes_tick']) {
    assert.match(fnBody(d), /fn_accountant_duty_settle\(/, `${d} does not raise its findings through fn_accountant_duty_settle`);
  }
  // Findings reach people only through the IT loop and customer_support.
  for (const f of FILES.filter((x) => !x.startsWith('the_it_engineer_'))) assert.doesNotMatch(read(join(SQL, f)), /insert\s+into\s+public\.notifications/i, `${f} writes the outbox itself`);
});

test('no supplier-charge reminder or demand wording is typed into a routine', () => {
  const w = fnBody('fn_sales_engineer_writes_money_notice');
  assert.match(w, /supplier_charge_reminder_template/);
  assert.match(w, /supplier_charge_final_demand_template/);
  assert.match(fnBody('fn_accountant_collections_tick'), /supplier_charge_recovery_basis/);
});

// Since #648 every conversation is a row of public.seat_handoff_kind naming its handler, and no file but
// the IT engineer's loop file defines fn_seat_handoff_act or fn_seat_handoff_types. The accountant's five
// notices are rows it inserts, answered by fn_sales_engineer_writes_money_notice.
export const NOTICE_KINDS = ['nonresponse.charge_reminder', 'nonresponse.final_demand', 'subscription.renewal_reminder',
  'subscription.dunning', 'subscription.payment_failed'];

test('the accountant adds its notices as handoff kinds, and never redefines the loop core', () => {
  for (const f of FILES) {
    assert.doesNotMatch(read(join(SQL, f)), /create or replace function public\.fn_seat_handoff_(act|types)\(/, `${f} redefines the loop core`);
  }
  const ins = sqlText.slice(sqlText.indexOf('insert into public.seat_handoff_kind'));
  for (const k of NOTICE_KINDS) {
    assert.match(ins, new RegExp(`\\('${k.replace('.', '\\.')}', 'accountant', 'sales_engineer',[\\s\\S]*?'fn_sales_engineer_writes_money_notice'`), `${k} is not a kind answered by the notice writer`);
    assert.match(fnBody('fn_sales_engineer_writes_money_notice'), new RegExp(`'${k.replace('.', '\\.')}'`), `the notice writer has no words for ${k}`);
  }
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('production: the accountant\'s notice kinds are live and their handler exists', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select type from public.seat_handoff_kind
                           where from_seat = 'accountant' and to_seat = 'sales_engineer' and handler = 'fn_sales_engineer_writes_money_notice'
                             and to_regprocedure('public.fn_sales_engineer_writes_money_notice(bigint)') is not null`);
  assert.deepEqual(rows.map((r) => r.type).sort(), [...NOTICE_KINDS].sort(), 'a notice kind is missing from public.seat_handoff_kind');
});

test('production: every duty\'s loop closes on ZZ DEMO fixtures, rolled back', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const batch = sqlText + '\n;\n' + read(join(REPO, 'scripts', 'checks', 'accountant_duties_fixtures.sql'));
  let r;
  try { await sql(batch); } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    r = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(r, 'the fixture batch committed instead of rolling back');
  for (const k of ['1_bank', '2_collections', '3_subscriptions', '4_vat', '6_expenses', '7_disputes', '8_close', '9_reserve', '10_charge_audit', '11_costs',
                   'x1_cash', 'x2_ad_spend', 'x3_recovery', 'x4_year_end', 'x5_renewals', 'duties_hour']) {
    assert.ok(r[k], `duty ${k} did not report`);
  }
});
