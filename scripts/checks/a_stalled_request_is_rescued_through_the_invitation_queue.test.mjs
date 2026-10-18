// A STALLED REQUEST IS RESCUED THROUGH THE INVITATION QUEUE (sales_engineer, 29 Sep 2026, founder ledger 1018 item 1).
//
// WHAT FAILS IF THE CAUSE RETURNS:
//   * offline: the rescued trade and area are not the FIRST tier of fn_supplier_invite_candidates, a fixture rescue can
//     move the real queue, the rescue writes an invitation itself (around the go switch, the caps and the brakes that
//     live in enqueue_supplier_invites), the customer's update is not in both languages, or the duty has no clock;
//   * production, in ONE aborted transaction (the pending file replayed first; ZZ DEMO and example.invalid only, every
//     row rolls back): scripts/sql/a_stalled_request_puts_its_trade_and_area_first_in_recruitment_and_tells_the_customer_probe.sql
//     must answer PROBE OK.
//
//   node --test scripts/checks/a_stalled_request_is_rescued_through_the_invitation_queue.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const NAME = 'a_stalled_request_puts_its_trade_and_area_first_in_recruitment_and_tells_the_customer';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
// DEPENDS-ON #1105: its file creates public.stalled_inquiry_rescue and fn_stalled_inquiry_flag; while pending it runs first.
const COMPANION = 'scripts/sql/a_busy_or_paused_supplier_is_skipped_and_an_unreachable_inquiry_goes_to_the_rescue.sql';
const companionPending = existsSync(join(REPO, 'scripts/sql/pending', COMPANION.split('/').pop().replace(/\.sql$/, '.txt')));
const companionSrc = companionPending ? readFileSync(join(REPO, COMPANION), 'utf8') : '';
const QUEUE = 'scripts/sql/a_stalled_request_puts_its_trade_and_area_first_in_the_invitation_queue.sql';
const queueSrc = readFileSync(join(REPO, QUEUE), 'utf8');
const queuePending = existsSync(join(REPO, 'scripts/sql/pending', QUEUE.split('/').pop().replace(/\.sql$/, '.txt')));
const src = readFileSync(join(REPO, FILE), 'utf8');
const pending = existsSync(join(REPO, 'scripts/sql/pending', `${NAME}.txt`));
// one routine's body, from its head to the next routine or the end
const bodyIn = (text, file, fn) => { const i = text.indexOf(`function public.${fn}(`); assert.ok(i > 0, `${fn} is not defined in ${file}`); const j = text.indexOf('create or replace function', i + 10); return text.slice(i, j < 0 ? undefined : j); };
const body = (fn) => bodyIn(src, FILE, fn);

test('the rescued trade and area are the first tier of the invitation queue, and only a real rescue counts', () => {
  const c = bodyIn(queueSrc, QUEUE, 'fn_supplier_invite_candidates');
  assert.match(c, /rescue as materialized \(select x\.trades, x\.emirate from public\.stalled_inquiry_rescue x where x\.cleared_at is null and not x\.fixture and cardinality\(x\.trades\) > 0\)/,
    'the queue does not read the open, real rescues');
  const tiers = c.slice(c.indexOf('case when exists (select 1 from rescue x'));
  assert.ok(tiers.indexOf('then -1') > 0 && tiers.indexOf('then -1') < tiers.indexOf("g.status = 'recruit'"), 'the rescue tier is not ahead of the recruit tier');
  assert.match(c, /order by r\.target_rank, r\.plan_rank/, 'inside a tier the queue no longer follows marketing\'s gap ranking');
  assert.match(c, /'en'::text as lang/, 'an invitation is no longer always English');
});

test('the rescue never writes an invitation itself: every brake stays in enqueue_supplier_invites', () => {
  const r = body('fn_sales_engineer_stalled_inquiry_rescue');
  assert.match(r, /public\.enqueue_supplier_invites\(\)/, 'the rescue does not offer the queue through enqueue_supplier_invites');
  assert.doesNotMatch(r, /insert into public\.notifications|'supplier_invite'|app_secrets/, 'the rescue writes around the one invitation door');
  assert.match(r, /'to_role', 'customer'/, 'the rescue writes to someone other than the customer');
});

test('the customer is told in both languages, in the formal register', () => {
  const n = body('fn_sales_engineer_stalled_inquiry_notice');
  assert.match(n, /if v_ar then[\s\S]*تحية طيبة وبعد[\s\S]*وتفضلوا بقبول فائق الاحترام والتقدير[\s\S]*else[\s\S]*Dear /, 'the update is not written in Arabic and English');
  assert.match(src, /public\.fn_sales_engineer_stalled_inquiry_notice\(r\.lang,/, 'the update does not take the language of the request');
});

test('the duty has a clock, the table is exported daily, and the file is pending XOR in MANIFEST', () => {
  assert.match(src, /\('sales_engineer\.stalled_inquiry_rescue',[\s\S]*?'30 minutes', true, 'fn_sales_engineer_stalled_inquiry_rescue'/);
  assert.match(body('fn_table_export_list'), /\('stalled_inquiry_rescue','inquiry'\)/, 'stalled_inquiry_rescue is not in the daily export');
});

// ONE SUBJECT, ONE HOME (review of #1106, 29 Sep 2026): #1105's public.stalled_inquiry_rescue is the rescue's only table,
// one routine acts on it, and #1105's intake clears only its own reason.
test('one rescue table, extended not duplicated; #1105\'s intake clears only its own reason', () => {
  assert.doesNotMatch(src, /create\s+table[^;]*\binquiry_rescue\b/i, 'a second rescue table is created');
  assert.match(src, /alter table public\.stalled_inquiry_rescue\s+add column if not exists trades/, 'the rescue does not extend #1105\'s table');
  assert.match(src, /check \(reason in \('no_reachable_supplier', 'no_quote_48h'\)\)/, 'the no-quote reason is not admitted');
  const flag = body('fn_stalled_inquiry_flag');
  const clears = [...flag.matchAll(/update public\.stalled_inquiry_rescue set cleared_at = now\(\)[\s\S]*?;/g)].map((m) => m[0]);
  assert.equal(clears.length, 2, 'fn_stalled_inquiry_flag no longer has its two clears');
  for (const u of clears) assert.match(u, /reason = 'no_reachable_supplier'/, 'fn_stalled_inquiry_flag clears a rescue it did not flag');
  // review of #1106 at 3d1bbb8: the WRITE is filtered too, a reopen starts the rescue's record over, and only a row
  // actually inserted or reopened is counted new
  assert.match(flag, /where stalled_inquiry_rescue\.reason = 'no_reachable_supplier' or stalled_inquiry_rescue\.cleared_at is not null;/,
    'fn_stalled_inquiry_flag can overwrite an open no-quote rescue');
  for (const col of ['reason = excluded.reason', 'acted_at', 'customer_notice', 'trades', 'uninvited_pool', 'finding_key'])
    assert.ok(flag.includes(col), `a reopened rescue does not reset ${col}`);
  assert.match(flag, /get diagnostics v_written = row_count;\s*if v_written = 0 then/, 'a row the flag did not write is still counted');
  const r = body('fn_sales_engineer_stalled_inquiry_rescue');
  assert.match(r, /where x\.cleared_at is null and x\.acted_at is null/, 'the rescue does not act on every open row, whichever way it came in');
  const manifest = readFileSync(join(REPO, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).map((l) => l.trim());
  assert.ok(pending !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
  assert.ok(queuePending !== manifest.includes(QUEUE), `${QUEUE}: exactly one of a pending note and a MANIFEST line`);
  if (pending && queuePending) assert.ok(FILE < QUEUE, 'the queue file would apply before the table it reads exists');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: a stalled ZZ DEMO request is rescued, told, ranked first and closed', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const block = (companionPending ? companionSrc + '\n' : '') + (pending ? src + '\n' : '') + (queuePending ? queueSrc + '\n' : '')
    + readFileSync(join(REPO, PROBE), 'utf8');
  let msg = '';
  try { await replaySql(block, { retry: false }); msg = 'the probe committed instead of rolling back'; } catch (e) { msg = String(e.message); }
  const m = msg.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(m, 'the probe failed before it could report: ' + msg.slice(0, 1500));
  const out = JSON.parse(m[1].replace(/\\"/g, '"'));
  assert.equal(out.verdict, 'PROBE OK', JSON.stringify(out).slice(0, 3000));
});
