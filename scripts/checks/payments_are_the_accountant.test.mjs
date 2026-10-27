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
//   * THE WHOLE LADDER on ZZ DEMO fixtures -- the canonical routines and scripts/checks/refund_ladder_fixtures.sql
//     run as ONE batch that always rolls back -- eleven scenarios, from the happy path through every
//     mismatch the CEO's playbook fixes. Nothing it writes survives and nothing it queues is sent.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { canonicalReplay, definitions } from '../lib/canonical_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';
import { seatWorkFixtures } from '../lib/seat_work_fixtures.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FNS = join(REPO, 'supabase', 'functions');
const SQL = join(REPO, 'scripts', 'sql');
// The files that own the refund ladder and the handoff loop. The check does NOT replay them whole: it
// replays the CANONICAL definition of every routine they define -- the last one in MANIFEST order,
// wherever it now lives (scripts/lib/canonical_sql.mjs). Replaying the files whole re-ran bodies later
// files had replaced; on 21 Sep 2026 that failed on main with "column l.iban_doc_path does not exist"
// (#777 dropped the column and redefined the routines that read it), red on code production no longer
// runs, and the file order here had to be hand-tuned for every such case before.
const FILES = ['payments_are_the_accountant_and_the_seats_close_every_refund_together.sql',
  'the_it_engineer_knows_what_should_be_backed_up_and_closes_the_loop.sql',
  'the_it_engineer_closes_every_loop_it_opens.sql',
  'every_send_comes_back_to_whoever_asked.sql'];

// Every payment function, as function_owner lists them. quote_pdf left this list on 22 Sep 2026: it is not
// deployed and has no directory here, and every_deployed_function_has_exactly_one_right_owner.sql (PR #811)
// removed its stale owner row; the quotation PDF is served by customer_api / supplier_api.
export const PAYMENT_SLUGS = ['stripe_checkout', 'stripe_confirm', 'stripe_webhook', 'stripe_setup', 'stripe_setup_page',
  'supplier_pay', 'reveal_invoice', 'refunds_api', 'refund_flow', 'accountant'];

const read = (p) => readFileSync(p, 'utf8');
const walk = (d) => readdirSync(d).flatMap((f) => {
  const p = join(d, f);
  return statSync(p).isDirectory() ? walk(p) : /\.tsx?$/.test(f) && !/\.test\./.test(f) ? [p] : [];
});
const slugs = readdirSync(FNS).filter((s) => !s.startsWith('_') && statSync(join(FNS, s)).isDirectory());
const fnSource = (s) => walk(join(FNS, s)).map(read).join('\n');
const sqlText = canonicalReplay(FILES);

function tsRegistry() {
  const src = read(join(FNS, '_shared', 'payment_handoffs.ts'));
  return [...src.matchAll(/\{ type: '([a-z_.]+)', from: '([a-z_]+)', to: '([a-z_]+)' \}/g)].map((m) => `${m[1]}|${m[2]}|${m[3]}`).sort();
}
// The conversations are rows of public.seat_handoff_kind, inserted by whichever file owns them. A row
// that names its handler ('fn_…' after the meaning) keeps it; a row that does not gets the handler the
// owner file's INSERT derives: fn_seat_answers_it_finding, fn_delivery_result_acts, else the seat's own.
const allSql = readdirSync(SQL).filter((f) => f.endsWith('.sql')).map((f) => read(join(SQL, f))).join('\n');
function kindRows() {
  const rows = [];
  for (const m of allSql.matchAll(/insert into public\.seat_handoff_kind\b[\s\S]*?;\s*$/gm)) {
    for (const t of m[0].matchAll(/\('([a-z_.]+)',\s*'([a-z_]+)',\s*'([a-z_]+)',\s*'(?:[^']|'')*'(?:,\s*'(fn_[a-z0-9_]+)')?/g)) {
      const [, type, from, to, named] = t;
      const handler = named ?? (type === 'it.finding' ? 'fn_seat_answers_it_finding'
        : type === 'delivery.result' ? 'fn_delivery_result_acts' : `fn_${to}_acts_on_handoff`);
      rows.push({ type, from, to, handler });
    }
    // 22 Sep 2026: the INSERT ... SELECT 'type', 'from', s, '<meaning>', 'fn_handler' ... FROM unnest(array[...]) s
    // shape (one kind to several seats) was invisible to the tuple parser above, so the four ceo.directive rows
    // were live in production and absent from payment_handoffs.ts with this static test green. Read it too.
    for (const t of m[0].matchAll(/select\s+'([a-z_.]+)',\s*'([a-z_]+)',\s*s,\s*'(?:[^']|'')*'(?:,\s*'(fn_[a-z0-9_]+)')?[\s\S]*?from\s+unnest\(array\[([^\]]*)\]\)\s+s\b/g)) {
      const [, type, from, named, seats] = t;
      for (const [, to] of seats.matchAll(/'([a-z_]+)'/g)) {
        rows.push({ type, from, to, handler: named ?? `fn_${to}_acts_on_handoff` });
      }
    }
    // 24 Sep 2026 (#913): the mirror shape, several seats to one — SELECT 'type', s, 'to', '<meaning>', 'fn_handler'
    // ... FROM unnest(array[...]) s — registers the root-cause reviews each seat sends the CEO.
    for (const t of m[0].matchAll(/select\s+'([a-z_.]+)',\s*s,\s*'([a-z_]+)',\s*'(?:[^']|'')*'(?:,\s*'(fn_[a-z0-9_]+)')?[\s\S]*?from\s+unnest\(array\[([^\]]*)\]\)\s+s\b/g)) {
      const [, type, to, named, seats] = t;
      for (const [, from] of seats.matchAll(/'([a-z_]+)'/g)) {
        rows.push({ type, from, to, handler: named ?? `fn_${to}_acts_on_handoff` });
      }
    }
    // 6 Oct 2026: the aliased union shape — SELECT 'type' [as type], 'from' | s.seat, s.seat | 'to', '<meaning>',
    // 'fn_handler' ... FROM unnest(array[...]) s(seat) [UNION ALL ...] — was invisible to both parsers above, so the
    // fifteen ceo.revise / ceo.decision_closed / ceo.decision_owed rows (MANIFEST 1894, founder_instruction 1059) were
    // live in production and absent from payment_handoffs.ts with this static test green. Read it too.
    for (const t of m[0].matchAll(/select\s+'([a-z_.]+)'(?:\s+as\s+\w+)?,\s*(?:'([a-z_]+)'|s\.seat)(?:\s+as\s+\w+)?,\s*(?:'([a-z_]+)'|s\.seat)(?:\s+as\s+\w+)?,\s*'(?:[^']|'')*'(?:\s+as\s+\w+)?(?:,\s*'(fn_[a-z0-9_]+)')?[\s\S]*?from\s+unnest\(array\[([^\]]*)\]\)\s+s\(seat\)/g)) {
      const [, type, fixedFrom, fixedTo, named, seats] = t;
      if (!!fixedFrom === !!fixedTo) continue; // exactly one side is the unnested seat
      for (const [, s] of seats.matchAll(/'([a-z_]+)'/g)) {
        const from = fixedFrom ?? s, to = fixedTo ?? s;
        rows.push({ type, from, to, handler: named ?? `fn_${to}_acts_on_handoff` });
      }
    }
    // 27 Oct 2026: two more shapes were invisible, so ceo.lesson_reapproval_overdue (#1496) and the five
    // review.requested rows (#1566) were live in production and absent from payment_handoffs.ts with this test green.
    // (a) one literal row: SELECT 'type', 'from', 'to', '<meaning>', 'fn_handler' ... WHERE NOT EXISTS (...)
    for (const t of m[0].matchAll(/select\s+'([a-z_.]+)',\s*'([a-z_]+)',\s*'([a-z_]+)',\s*'(?:[^']|'')*',\s*'(fn_[a-z0-9_]+)'/g)) {
      const [, type, from, to, named] = t;
      rows.push({ type, from, to, handler: named });
    }
    // (b) one kind to every seat review_route names: SELECT 'type', 'from', s.seat, '<meaning>', 'fn_handler' ...
    //     FROM (select distinct owner_seat as seat from public.review_route where decision_type <> 'person') s.
    //     The seats are the review_route rows the files insert, read the same way.
    for (const t of m[0].matchAll(/select\s+'([a-z_.]+)',\s*'([a-z_]+)',\s*s\.seat,\s*'(?:[^']|'')*',\s*'(fn_[a-z0-9_]+)'[\s\S]*?from\s+\(select distinct owner_seat as seat from public\.review_route where decision_type <> 'person'\)\s+s\b/g)) {
      const [, type, from, named] = t;
      for (const to of reviewRouteSeats()) rows.push({ type, from, to, handler: named });
    }
  }
  return rows;
}
// The owning seats of review_route (ledger 1152), from the (decision_type, owner_seat, meaning) rows its inserts write.
function reviewRouteSeats() {
  const seats = new Set();
  for (const m of allSql.matchAll(/insert into public\.review_route\b[\s\S]*?;\s*$/gm)) {
    for (const [, kind, seat] of m[0].matchAll(/\('([a-z_]+)',\s*'([a-z_]+)',\s*'(?:[^']|'')*'\)/g)) if (kind !== 'person') seats.add(seat);
  }
  return [...seats].sort();
}
// A pair two files register (the second insert is on conflict do nothing) is one conversation.
const sqlRegistry = () => [...new Set(kindRows().map((r) => `${r.type}|${r.from}|${r.to}`))].sort();
function fnBody(name) {
  const d = definitions(sqlText).filter((x) => x.name === name).pop();
  assert.ok(d, `${name} has no canonical definition`);
  return d.stmt;
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
  // A seat's generic handler (fn_<seat>_acts_on_handoff) branches on the type, so it must name it; a
  // routine written for the conversation (fn_delivery_result_acts, an accountant money notice) only has
  // to exist.
  const handlerOk = ({ type, to, handler }) => (handler === `fn_${to}_acts_on_handoff`
    ? fnBody(handler).includes(`'${type}'`)
    : allSql.includes(`create or replace function public.${handler}(`));
  const handlers = new Map(kindRows().map((r) => [`${r.type}|${r.from}|${r.to}`, r]));
  const ts = slugs.map(fnSource).join('\n');
  const missing = [];
  for (const k of tsRegistry()) {
    const [type, from, to] = k.split('|');
    const row = handlers.get(k);
    if (!row || !handlerOk(row)) missing.push(`${k}: ${to} has no handler${row ? ` (${row.handler})` : ''}`);
    // A conversation's producer lives in the file that owns the kind (since #648 kinds are data a build
    // adds), so it is looked for across every routine file, not only the FILES above.
    const produced = allSql.includes(`fn_seat_handoff('${from}', '${to}', '${type}'`)
      || (type === 'delivery.request' && from === 'sales_engineer' && sqlText.includes('fn_seat_handoff(\'sales_engineer\', \'customer_support\', \'delivery.request\''))
      // the edge door opens a request from the seat that owns the type; the watch answers whoever asked
      || (type === 'delivery.request' && sqlText.includes("fn_seat_handoff(v_seat, 'customer_support', 'delivery.request'"))
      || (type === 'delivery.result' && sqlText.includes("fn_seat_handoff('customer_support', q.detail->>'from', 'delivery.result'"))
      // the IT engineer addresses a finding to the seat that owns the faulty component
      || (type === 'it.finding' && sqlText.includes("fn_seat_handoff('it_engineer', v_owner, 'it.finding'"))
      || new RegExp(`p_from: '${from}', p_to: '${to}', p_type: '${type.replace('.', '\\.')}'`).test(ts)
      || (type === 'refund.remediate' && sqlText.includes("fn_seat_handoff('ceo', x.owner, 'refund.remediate'"))
      || (type === 'incident.fix' && sqlText.includes("fn_seat_handoff('ceo', 'accountant', 'incident.fix'"))
      // the reveal invoice is filed directly, not through fn_seat_handoff, so a ZZ DEMO sale still proves the notice
      // (ruling 1199 files nothing for demo work); the accountant's trigger writes the typed row itself
      || (type === 'invoice.issued' && allSql.includes("jsonb_build_object('type', 'invoice.issued', 'from', 'accountant', 'from_name', 'Accountant', 'to', 'sales_engineer'"))
      // the CEO's daily plan addresses each directive to the seat the plan names
      || (type === 'ceo.directive' && allSql.includes("fn_seat_handoff('ceo', dr->>'seat', 'ceo.directive'"))
      // a target miss asks the metric's owning seat (#913); the month directive and an improvement go to the seat
      // the year-one plan names (#923)
      || (type === 'ceo.root_cause' && allSql.includes("fn_seat_handoff('ceo', p.owner_seat, 'ceo.root_cause'"))
      || (type === 'ceo.month_directive' && allSql.includes("fn_seat_handoff('ceo', s, 'ceo.month_directive'"))
      // a rejection never ends the cycle (founder_instruction 1059): the CEO answers the seat that submitted the item
      || (type === 'ceo.revise' && from === 'ceo' && allSql.includes("fn_seat_handoff('ceo', p_originator, 'ceo.revise'"))
      || (type === 'ceo.decision_closed' && from === 'ceo' && allSql.includes("fn_seat_handoff('ceo', new.originator_seat, 'ceo.decision_closed'"))
      || (type === 'ceo.decision_owed' && to === 'ceo' && allSql.includes("fn_seat_handoff(p_originator, 'ceo', 'ceo.decision_owed'"))
      || (type === 'ceo.improvement' && allSql.includes("fn_seat_handoff('ceo', p_seat, 'ceo.improvement'"))
      // a recurring support cause goes to the seat support_category names as its owner (instruction 1009)
      || (type === 'support.root_cause' && from === 'customer_support'
          && allSql.includes("fn_seat_handoff('customer_support', r.owner_seat, 'support.root_cause'"))
      // an unanswerable question goes to the seat that owns the knowledge: kb/sales to sales_engineer, the rest to ceo (#1549)
      || (type === 'knowledge.request' && from === 'customer_support' && ['sales_engineer', 'ceo'].includes(to)
          && allSql.includes("fn_seat_handoff('customer_support', v_seat, 'knowledge.request'"))
      // a contested decision goes to the seat review_route names as its owner (ledger 1152, #1566)
      || (type === 'review.requested' && from === 'customer_support'
          && allSql.includes("fn_seat_handoff('customer_support', v_route.owner_seat, 'review.requested'"))
      // a review is started only by a real call site for THIS pair (founder_instruction 873): the generic opener
      // proves nothing about which pairs anything opens
      || (type === 'deliberation.review' && (new RegExp(`fn_seat_deliberation_open\\(\\s*'[a-z_.]+',\\s*'${from}',\\s*'${to}'`).test(allSql)
          || new RegExp(`p_author_seat: '${from}',\\s*p_reviewer_seat: '${to}'`).test(ts)
          // a seat duty opens its review through fn_seat_duty_cross_review, whose call names the pair the same way (#901)
          // (the kind may be built, e.g. 'ceo.' || v_kind; the author and reviewer must still be written literally)
          || new RegExp(`fn_seat_duty_cross_review\\(\\s*[^,]+,\\s*'${from}',\\s*'${to}'`).test(allSql)
          // the CEO's root-cause challenge (#913): the author is the seat that owns the metric, the reviewer the CEO
          // (the accountant when the CEO is the author). Only for the non-CEO seats that registration names.
          || (to === 'ceo' && from !== 'ceo'
              && allSql.includes("fn_seat_duty_cross_review(r.seat || '.root_cause', r.seat, case when r.seat = 'ceo' then 'accountant' else 'ceo' end"))));
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
  const live = (await sql('select type, from_seat, to_seat from public.seat_handoff_kind')).map((r) => `${r.type}|${r.from_seat}|${r.to_seat}`).sort();
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
  // The CEO's refund decisions are rounds in public.ceo_decision_round (founder_instruction 1059). While that file
  // waits for its apply it is replayed first, so the ladder is proved against the code that will run, not the code
  // it replaces; once it is in MANIFEST it is production's own and nothing is added. It goes AFTER the canonical
  // replay, which reads MANIFEST only and would otherwise put the older bodies back over it.
  const LEDGER = 'scripts/sql/a_rejection_never_ends_the_cycle_the_ceo_gives_reasons_and_the_seat_revises.sql';
  const ledgerPending = existsSync(join(REPO, LEDGER))
    && !read(join(REPO, 'scripts', 'sql', 'MANIFEST.txt')).split(/\r?\n/).map((l) => l.trim()).includes(LEDGER);
  // Ruling 1199 (demo_activity_files_no_seat_task_or_handoff.sql, #1479) files no handoff for a ZZ DEMO subject, so
  // the ladder stopped at "s1 reveal.paid handoff not done" (27 Oct 2026). The fixtures prove the loop, so they switch
  // that guard off for their own rolled-back transaction (a_rolled_back_probe_may_file_demo_seat_work_under_its_own_switch.sql).
  const batch = [sqlText, ...(ledgerPending ? [read(join(REPO, LEDGER))] : []), seatWorkFixtures(),
    read(join(REPO, 'scripts', 'checks', 'refund_ladder_fixtures.sql'))].join('\n;\n');
  let message = '';
  try { await replaySql(batch); message = 'the fixture batch returned without raising, so it did not roll back'; } catch (e) { message = String(e.message); }
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
