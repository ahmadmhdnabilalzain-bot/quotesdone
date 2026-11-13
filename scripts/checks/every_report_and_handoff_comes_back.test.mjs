// EVERY REPORT AND EVERY HANDOFF COMES BACK TO WHOEVER SENT IT.
//
// The founder: "nothing literally should ever be a one way communication" (14 Sep 2026). Measured
// 15 Sep 2026: 680 sales engineer reports to the CEO that nothing read, and 33 of 40 handoff kinds that
// closed the moment the receiver answered, with nobody who sent them checking the outcome.
// scripts/sql/the_ceo_decides_every_sales_engineer_report_and_every_sender_closes_its_handoff.sql
// built the reader and the re-verification. This fails when:
//   1. the fn_it_loop_tick that wins in MANIFEST order stops calling the CEO's and the originators' steps;
//   2. (production) a kind marked originator_closes has no routine that closes it as its originator
//      (one that names the kind and sets qd.handoff_closer or qd.backup_closer) -- such a kind would
//      leave every handoff pending forever;
//   3. (production) one of the 18 kinds (17 flipped, plus delivery.remediate) decided in that file lost its reply window or its flag, which is
//      what re-applying an older file that inserts the rows would do;
//   4. (production) an approval kind can email the founder, or an owner or authority names no seat.
//
//   node --test scripts/checks/every_report_and_handoff_comes_back.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SEATS = ['ceo', 'customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing'];
const FLIPPED = [
  ['refund.requested', 'sales_engineer', 'accountant'], ['billing.question', 'sales_engineer', 'accountant'],
  ['charge.disputed', 'sales_engineer', 'accountant'],
  ...['reveal.paid', 'payment.failed', 'payment.received', 'refund.request_checked', 'refund.declined', 'refund.in_progress',
    'subscription.due', 'billing.answer', 'charge.dispute_answer', 'nonresponse.charge_reminder',
    'nonresponse.final_demand', 'subscription.dunning', 'subscription.payment_failed', 'subscription.renewal_reminder']
    .map((t) => [t, 'accountant', 'sales_engineer']),
  ['delivery.remediate', 'ceo', 'sales_engineer'],
];

test('the winning fn_it_loop_tick runs the CEO and originator steps', () => {
  const order = readFileSync(join(REPO, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).filter((l) => l.endsWith('.sql'));
  const defines = /create\s+or\s+replace\s+function\s+public\.fn_it_loop_tick\s*\(\s*\)([\s\S]*?)\$fn\$;/i;
  const winner = order.filter((f) => existsSync(join(REPO, f)) && defines.test(readFileSync(join(REPO, f), 'utf8'))).pop();
  assert.ok(winner, 'no MANIFEST file defines fn_it_loop_tick');
  const body = readFileSync(join(REPO, winner), 'utf8').match(defines)[1];
  for (const step of ['fn_originators_reverify_handoffs', 'fn_ceo_sales_engineer_reports_sweep', 'fn_sales_engineer_reports_complete',
                      'fn_ceo_accountant_reports_sweep', 'fn_ceo_it_reports_sweep']) {
    assert.ok(body.includes(`public.${step}(`), `${winner}: fn_it_loop_tick no longer calls ${step}`);
  }
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

// Since #1194 (the_originator_closes_what_was_answered_and_the_digest_carries_only_his_decisions.sql, 5 Oct 2026)
// fn_originators_reverify_handoffs section 4 closes EVERY originator_closes kind it does not name (it names only the
// kinds it leaves to their own closers) once the kind's handler has answered without 'waiting'. A kind registered after
// it -- ceo.lesson_reapproval_overdue (#1496) and review.requested (#1566, closed by fn_review_request_decide through
// the stored handoff id) -- names no literal closer and is still closed, so the generic closer counts here, but only
// for a kind whose handler is a live routine: with no handler nothing ever answers, and nothing generic closes it.
test('every originator-closed kind has a routine that closes it as its originator', { skip: SKIP }, async () => {
  const orphans = await sql(`
    select k.type, k.from_seat, k.to_seat from public.seat_handoff_kind k
     where k.originator_closes
       and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                        where n.nspname = 'public' and p.prosrc like '%''' || k.type || '''%'
                          and (p.prosrc like '%qd.handoff_closer%' or p.prosrc like '%qd.backup_closer%'))
       and not (to_regproc('public.' || k.handler) is not null
                and exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                             where n.nspname = 'public' and p.prosrc like '%sk.originator_closes%'
                               and p.prosrc like '%qd.handoff_closer%' and p.prosrc not like '%''' || k.type || '''%'))`);
  assert.deepEqual(orphans, [], 'these kinds wait for an originator that never closes them');
});

test('the decided kinds keep their reply window and their closer', { skip: SKIP }, async () => {
  const rows = await sql(`select type, from_seat, to_seat, reply_within is not null as has_window, originator_closes from public.seat_handoff_kind`);
  const at = new Map(rows.map((r) => [`${r.type}|${r.from_seat}|${r.to_seat}`, r]));
  const lost = FLIPPED.filter(([t, f, to]) => { const r = at.get(`${t}|${f}|${to}`); return !r || !r.has_window || !r.originator_closes; })
    .map((x) => x.join(' '));
  assert.deepEqual(lost, [], 'reset by a re-applied insert? re-apply the_ceo_decides_every_sales_engineer_report_and_every_sender_closes_its_handoff.sql');
});

test('no approval emails the founder, and every owner is a seat', { skip: SKIP }, async () => {
  const seats = SEATS.map((s) => `'${s}'`).join(',');
  const [r] = await sql(`select
      (select coalesce(json_agg(kind), '[]') from public.founder_mail_policy
        where allowed_to_email and kind in ('refund_approval', 'refund_decision', 'spend_approval_needed')) approvals,
      (select coalesce(json_agg(kind), '[]') from public.founder_mail_policy where owner_role not in (${seats})) mail_owners,
      (select coalesce(json_agg(function_slug), '[]') from public.function_owner where owner not in (${seats})) function_owners,
      (select coalesce(json_agg(kind), '[]') from public.agent_action_kind_policy
        where authority_role is null or authority_role not in (${seats})) authorities`);
  assert.deepEqual(r.approvals, [], 'these approval kinds can still email the founder');
  assert.deepEqual(r.mail_owners, [], 'founder_mail_policy names an owner that is not a seat');
  assert.deepEqual(r.function_owners, [], 'function_owner names an owner that is not a seat');
  assert.deepEqual(r.authorities, [], 'agent_action_kind_policy names no seat');
});

// ── 13 Nov 2026 (ceo, founder ledger 1688: "It's never like this agent is done with this task, he just sends an output and he
// doesn't know what happens after that"). Measured that day: 196 hand-overs open past their window, every one answered by its
// receiver; the open move was the sender's or the CEO's, and nothing told anyone. 15,110 closed within 2 s by the receiving SQL
// carried their outcome in evidence, but the sender had no reader of it. every_seat_reads_one_pool_and_every_hand_over_comes_back.sql
// escalates once and gives the sender the line; these fail when that rule loses a leg.
const POOL_FILE = 'scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql';
const fnBody = (text, name) => {
  const at = text.indexOf(`create or replace function public.${name}(`);
  return at < 0 ? '' : text.slice(at, text.indexOf('$fn$;', at));
};

// Review of 13 Nov evening (items 2 and 4): the escalation goes to the SILENT seat's superior (not the sender's), the founder
// only when the CEO himself is silent; the silent seat is the one "awaiting" names, case-insensitively, else the receiver.
test('an overdue hand-over is escalated once, to the silent seat\'s superior, by its due date, and the sender is told', () => {
  const text = readFileSync(join(REPO, POOL_FILE), 'utf8');
  const esc = fnBody(text, 'fn_handoff_overdue_escalate');
  assert.ok(esc, 'fn_handoff_overdue_escalate is gone');
  assert.match(esc, /not coalesce\(a\.escalated, false\)/, 'ONCE: an escalated row is never escalated again');
  assert.match(esc, /not \(a\.detail \? 'escalated_report_id'\) and not \(a\.detail \? 'silence'\)/, 'ONCE: rows another loop escalated are left alone');
  assert.match(esc, /a\.detail->>'due_at'/, 'a month directive is late at its month end, not at its reply window');
  assert.match(esc, /from public\.org_reporting_edge e/, 'the superior is read from the reporting line, never assumed');
  assert.match(esc, /if v_silent = 'ceo' then\s+v_sup := 'founder';/, 'the CEO\'s own overdue hand-overs go to the founder\'s brief');
  assert.match(esc, /where e\.child_role_id = v_silent/, 'the superior asked is the SILENT seat\'s, not the sender\'s');
  assert.match(esc, /v_silent := public\.fn_handoff_owing_seat\(h\.detail->>'awaiting', h\.agent\)/, 'the silent seat is the one that owes the move');
  assert.match(fnBody(text, 'fn_handoff_owing_seat'), /~\* \('\(\^\|\[\^a-z_\]\)' \|\| r\.role_id/, 'the seat named in awaiting is read case-insensitively');
  assert.match(esc, /'silent_seat', v_silent/, 'the silence is recorded');
  assert.ok(fnBody(text, 'fn_founder_brief_overdue_handoffs'), 'the founder\'s lines are gone');
  assert.match(esc, /where x\.due < now\(\)\s+order by x\.due limit 100/, 'the due check is in the WHERE: no starvation behind the first 100 ids');
  assert.match(fnBody(text, 'fn_seat_pool_waiting'), /'NO ANSWER YET: ' \|\| string_agg\(m\.owes \|\| ' owes '/, 'the sender is never blind, and reads who owes it');
  assert.match(fnBody(text, 'fn_seat_pool_waiting'), /'YOU ARE LATE: '/, 'the silent seat is told it is late');
  const tl = fnBody(text, 'fn_seat_pool_timeline');
  assert.match(tl, /'answered: ' \|\| left\(coalesce\(case when a\.evidence \? 'ceo_decision' then a\.evidence->>'reply' end,\s+a\.evidence->'ceo_decision'->>'choice', a\.evidence->>'verdict'/, 'the sender reads the outcome, not only "done"');
  assert.match(tl, /then 'answered: ' \|\| left\(coalesce\(a\.evidence->>'reply'/, 'a pending row the sender waits on prints the answer itself');
  // an escalation is work somebody decides: the CEO's held question, or the founder's daily note
  assert.match(fnBody(text, 'fn_ceo_files_judgements'), /a\.detail->'silence'->>'escalated_to' = 'ceo'/, 'an escalation to the CEO is filed for his decision');
  assert.match(fnBody(text, 'fn_ceo_tells_the_founder_daily'), /public\.fn_notify_founder\(/, 'the founder is told once a day');
  const dl = fnBody(text, 'fn_authors_close_reviewed_deliberations');
  assert.match(dl, /in \('agree', 'agreed', 'approve', 'approved'\) and r\.state = 'done'/, 'only an agreeing review is closed by reading it');
  assert.match(dl, /'deliberation\.rework'/, 'a revise or reject goes back to its author as work');
});

test('(production) a hand-over closed in the last two days carries an outcome the sender can read', { skip: SKIP }, async () => {
  const [r] = await sql(`select count(*)::int as bare from public.agent_actions a
     where a.status = 'done' and a.created_at > now() - interval '2 days' and a.kind = 'handoff'
       and (a.evidence is null or (a.evidence - 'cites_note') = '{}'::jsonb)`);
  assert.equal(r.bare, 0, 'closed with no outcome: the sender knows only "done"');
});
