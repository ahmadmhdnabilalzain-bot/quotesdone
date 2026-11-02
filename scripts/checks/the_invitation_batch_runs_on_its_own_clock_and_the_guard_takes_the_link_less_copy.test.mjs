// THE INVITATION BATCH RUNS ON ITS OWN CLOCK, AND THE GUARD TAKES THE LINK-LESS COPY (28 Oct 2026, sales_engineer).
//
// The first open day after the resume (28 Oct) queued 0 invitations, for two reasons, both hidden while invitations
// were held. This fails if either returns:
//   1. fn_sales_engineer_supplier_outreach_tick is run by resilience_ping again, through PostgREST, under the
//      authenticator's 8 s statement_timeout. An open day measured 13.4 s, so every beat was cancelled.
//   2. a07_notifications_supplier_invite_is_whole demands a portal link again, while the approved copy has none
//      (#1614): every row of the batch was refused, "carries no portal link".
// For 2, the test does not grep for one pattern: it takes the guard's body from the file that wins the apply order,
// pulls out every regex the guard requires the body to match (`body ... !~ '<re>'` raises), and runs each against the
// approved copy in the no-link file. A new requirement the approved copy cannot meet fails it, whatever it is.
// The behaviour is proved against production by the probe file of the same name (rolled back, never writes app_secrets).
//   node --test scripts/checks/the_invitation_batch_runs_on_its_own_clock_and_the_guard_takes_the_link_less_copy.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const SQL = 'scripts/sql/';
const FIX = 'the_invitation_batch_runs_on_its_own_clock_and_the_guard_takes_the_link_less_copy.sql';
const NOLINK = 'the_supplier_invitation_carries_no_link_and_a_reply_with_trades_reaches_the_sales_engineer.sql';
const ping = readFileSync('supabase/functions/resilience_ping/index.ts', 'utf8');
const manifest = readFileSync(SQL + 'MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
  .map((l) => l.replace(/^scripts\/sql\//, ''));
const pending = (f) => existsSync(SQL + 'pending/' + f.replace(/\.sql$/, '.txt'));

// The file that defines the guard LAST: a pending file is applied after everything in MANIFEST, so it wins.
function guardFile() {
  const defines = (f) => existsSync(SQL + f) && /create or replace function public\.fn_notifications_supplier_invite_is_whole\(\)/i.test(readFileSync(SQL + f, 'utf8'));
  if (pending(FIX) && defines(FIX)) return FIX;
  const listed = manifest.filter(defines);
  assert.ok(listed.length > 0, 'no applied file defines fn_notifications_supplier_invite_is_whole');
  return listed[listed.length - 1];
}

function guardBody() {
  const src = readFileSync(SQL + guardFile(), 'utf8');
  const open = src.search(/create or replace function public\.fn_notifications_supplier_invite_is_whole\(\)/i);
  // whatever dollar tag the file uses ($fn$, $function$, ...): from `as $tag$` to the same tag closing it
  const m = /\bas\s+(\$[a-z_]*\$)/i.exec(src.slice(open));
  assert.ok(m, `${guardFile()}: the guard has no dollar-quoted body`);
  const start = open + m.index + m[0].length;
  const end = src.indexOf(m[1], start);
  assert.ok(end > start, `${guardFile()}: the guard's body is not closed`);
  return src.slice(start, end);
}

function approvedBody() {
  const src = readFileSync(SQL + NOLINK, 'utf8');
  const m = src.match(/update public\.app_secrets set value = \$body\$([\s\S]*?)\$body\$/);
  assert.ok(m, 'the approved invitation copy is no longer in ' + NOLINK);
  return m[1].replaceAll('{{company}}', 'Example Trading LLC');   // as the composer fills it
}

test('the approved link-less copy passes every body requirement of the live guard', () => {
  const g = guardBody();
  const body = approvedBody();
  // Every `... body ... !~ '<re>' then raise` is a requirement on an English invitation; Arabic-only checks are
  // guarded by `lang = 'ar'` on the same line and do not apply to the approved English copy.
  const reqs = [...g.matchAll(/^.*new\.body[^\n]*!~\s*'([^']+)'[^\n]*$/gm)].filter((m) => !/lang/.test(m[0])).map((m) => m[1]);
  for (const re of reqs) {
    const js = new RegExp(re.replace(/\[\?\]/g, '\\?'));
    assert.match(body, js, `the guard in ${guardFile()} requires /${re}/, which the approved copy (no link, #1614) does not carry: every invitation would be refused`);
  }
  assert.ok(!/portal\[\?\]t=/.test(g), `the guard in ${guardFile()} still demands a portal link`);
});

// Relaxing the link must not relax the opt-out (review of #1705, 28 Oct 2026): the guard refuses a body without the
// reply-"stop" line, the approved copy carries it, and the same copy with that line cut is refused.
test('the guard still requires the reply-"stop" opt-out line, and the approved copy carries it', () => {
  const g = guardBody();
  const m = g.match(/new\.body[^\n]*!~\*\s*'((?:[^']|'')+)'[^\n]*\n[^\n]*no reply-"stop" opt-out line/);
  assert.ok(m, `the guard in ${guardFile()} no longer refuses an invitation without the reply-"stop" opt-out line`);
  const re = new RegExp(m[1].replaceAll("''", "'").replaceAll('[[:space:]]', '\\s'), 'i');
  const body = approvedBody();
  assert.match(body, re, 'the approved copy has no reply-"stop" line: every invitation would be refused');
  assert.doesNotMatch(body.split('\n').filter((l) => !/stop/i.test(l)).join('\n'), re, 'a body without the stop line would pass the guard');
});

test('the outreach tick is not run under the 8 s heartbeat RPC', () => {
  const open = ping.indexOf("const STEP_RUN: Record<string, Omit<Step, 'name'>> = {");
  const close = ping.indexOf('\n};', open);
  assert.ok(open > 0 && close > open, 'STEP_RUN not found in resilience_ping');
  assert.doesNotMatch(ping.slice(open, close), /^\s*supplierOutreach\s*:/m, 'resilience_ping runs supplierOutreach again, under the 8 s RPC limit');
  assert.doesNotMatch(ping, /rpc\(\s*'fn_sales_engineer_supplier_outreach_tick'/, 'resilience_ping calls the outreach tick again, under the 8 s RPC limit');
});

test('the tick has its own 60 s job and the heartbeat row is gone', () => {
  const src = readFileSync(SQL + FIX, 'utf8');
  assert.match(src, /'sales_engineer\.supplier_outreach', 'sales_engineer', interval '15 minutes', 'fn_sales_engineer_supplier_outreach_tick'/);
  assert.match(src, /select public\.fn_seat_duty_isolate\('sales_engineer\.supplier_outreach'\)/, 'the duty is not on its own job');
  assert.match(src, /delete from public\.resilience_step where step = 'supplierOutreach';/, 'the heartbeat would still plan the step');
  assert.ok(pending(FIX) !== manifest.includes(FIX), `${FIX}: exactly one of a pending note and a MANIFEST line`);
});
