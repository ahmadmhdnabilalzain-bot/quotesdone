// A PAID REVEAL ASKS THE CUSTOMER WHETHER THE SUPPLIER CALLED, AND EVERY MONEY PROBLEM AFTER IT REACHES A CASE.
// customer_support (agent AFTER_REVEAL), 16 Nov 2026; holes SP/holes/CUSTOMER.md items 1, 2, 3, 4 and 12. Offline: reads the SQL file
// and the edge functions; no database, no network.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * the ladder decides "the supplier responded" without the customer's word (fn_refund_state stops reading fn_reveal_contact_word);
//   * a denial after the supplier's click stops reaching the CEO with both statements;
//   * the follow-up writes a review from "never contacted", or the refund door's rating refusal stops asking whether it shows dealing;
//   * the supplier's acknowledgement goes back to role admin, or is written to the table without telling the customer;
//   * a door (portal, WhatsApp, widget) stops reaching fn_customer_after_reveal_message, or the intake loses an option or the
//     quotation on record; or code starts reading the customer's words with a pattern (founder ruling 1664: the model reads);
//   * a remedy or a supplier action can follow a decision for the supplier;
//   * a routine loses its pinned search_path or its revoke, the table its RLS or policy; dynamic SQL appears; a customer link
//     leaves quotesdone.ae; the file carries both, or neither, of a pending note and a MANIFEST line.
//   node --test scripts/checks/a_paid_reveal_asks_the_customer_and_every_money_problem_reaches_a_case.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyState } from '../lib/pending_sql.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const NAME = 'a_paid_reveal_asks_the_customer_and_every_money_problem_reaches_a_case';
const SQL = readFileSync(join(REPO, 'scripts/sql', NAME + '.sql'), 'utf8');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const body = (fn) => {
  const i = SQL.indexOf(`function public.${fn}(`);
  assert.ok(i >= 0, `${fn} is not defined in the file`);
  return SQL.slice(i, SQL.indexOf('$fn$;', i));
};

test('the ladder reads the customer\'s word beside the supplier\'s claim', () => {
  const st = body('fn_refund_state');
  assert.match(st, /v_word := public\.fn_reveal_contact_word\(t\.id\);\s*v_responded := coalesce\(\(v_word->>'responded'\)::boolean, false\);/,
    'fn_refund_state decides "responded" without the customer\'s word');
  assert.doesNotMatch(st, /v_responded := t\.supplier_ack_at is not null/, 'the one-click acknowledgement alone decides again');
  const w = body('fn_reveal_contact_word');
  assert.match(w, /'responded', w\.yes_at is not null or \(w\.claim_at is not null and not w\.denied_after_claim\)/, 'the rule for "responded" changed');
  assert.match(w, /coalesce\(w0\.yes_at is null and w0\.def_said = 'no' and w0\.claim_at is not null and w0\.def_at >= w0\.claim_at, false\)/,
    'a denial is no longer compared, null-safely, with the time of the supplier\'s claim');
});

test('a denial after the click goes to the CEO with both statements, through the existing conversation', () => {
  const r = body('fn_reveal_contact_record');
  assert.match(r, /fn_seat_handoff\('sales_engineer', 'ceo', 'sales\.escalation'/);
  assert.match(r, /'escalation', 'disputed_reveal'/);
  assert.match(r, /'customer_statement'/); assert.match(r, /'supplier_statement'/);
});

test('our own survey never turns "never contacted" into a refund bar', () => {
  const a = body('fn_customer_followup_answer');
  assert.match(a, /if p_stars is not null and not v_no_contact and not exists \(select 1 from public\.reviews/, 'a "never contacted" answer can write a review');
  assert.match(a, /fn_customer_support_dispute_consider\(t\.id, 'customer', v_statement, 'followup_page'\)/, 'a complaint after contact does not reach the intake');
  const o = body('fn_refund_open_from_customer');
  assert.match(o, /elsif public\.fn_refund_rating_shows_dealing\(t\.id\) then\s*v_code := 'supplier_rated'/, 'the rating refusal does not ask whether it shows dealing');
  assert.doesNotMatch(o, /elsif exists \(select 1 from public\.reviews v where v\.transaction_id = t\.id\)/, 'the bare "any review" refusal is back');
});

test('the supplier\'s acknowledgement reaches the customer, not role admin', () => {
  const src = read('supabase/functions/supplier_ack/index.ts');
  assert.match(src, /admin\.rpc\('fn_supplier_ack_record', \{ p_transaction: tx \}\)/);
  assert.doesNotMatch(src, /to_role\s*:\s*'admin'/);
  assert.doesNotMatch(src, /from\('transactions'\)\.update\(/, 'the handler writes the table itself again');
  assert.match(body('fn_supplier_ack_record'), /fn_customer_support_duty_send\('supplier_ack\.customer'/);
});

test('working day 2 asks, once, in his language, through the one door', () => {
  const t = body('fn_customer_support_contact_check_tick');
  assert.match(t, /fn_customer_message_lang\(/); assert.match(t, /fn_customer_support_duty_send\('followup\.day_two_contact'/);
  assert.match(t, /now\(\) >= public\.fn_add_working_days\(t\.revealed_at, 2\)/); assert.match(t, /qd\.duty_fixtures/);
  assert.match(t, /not coalesce\(c\.banned, false\)/); assert.doesNotMatch(t, /insert into public\.notifications/);
  assert.match(SQL, /\('sales_engineer\.contact_check', 'sales_engineer', interval '2 hours', 'fn_customer_support_contact_check_tick'/);
});

test('every door reaches the one routine, and the model reads the words: four readings with the quotation on record', () => {
  const c = body('fn_customer_support_dispute_consider');
  for (const id of ['supplier_contacted', 'supplier_not_contacted', 'dispute', 'not_dispute']) assert.match(c, new RegExp(`'id', '${id}'`), `the intake lost ${id}`);
  assert.match(c, /'job_on_record', public\.fn_reveal_job_facts\(t\.id\)/);
  const door = body('fn_customer_after_reveal_message');
  assert.match(door, /fn_customer_support_dispute_consider\(t\.id, 'customer', p_message, p_channel\)/);
  // the only pattern the door runs on his text is the request NUMBER (format), never a word
  assert.doesNotMatch(door, /p_message\s*~\*?|p_message\s+ilike|p_message\s+like/, 'the door reads his words with a pattern');
  assert.match(body('fn_wa_answer'), /if v_cust is not null and v_intent\.intent_key = 'after_reveal' then\s*v_ans := public\.fn_customer_after_reveal_message\(v_cust, p_body, 'whatsapp', null\)/);
  assert.match(SQL, /insert into public\.wa_reply_intent[\s\S]*'after_reveal'/);
  assert.match(read('supabase/functions/customer_api/actions/reveal.ts'), /admin\.rpc\('fn_customer_after_reveal_message', args\)/);
  assert.match(read('supabase/functions/site_assistant/after_reveal_door.ts'), /rpc\('fn_customer_after_reveal_message'/);
  const apply = body('fn_reason_apply_customer_support__dispute_intake');
  assert.match(apply, /fn_refund_open_from_customer\(v_tx, 'customer'/); assert.match(apply, /fn_customer_support_dispute_open\(v_tx/);
});

test('the CEO\'s decision acts, and a remedy follows only an upheld or shared complaint', () => {
  const d = body('fn_ceo_decides_post_reveal_dispute');
  assert.match(d, /if not v_upheld and \(coalesce\(p_remedy, 'none'\) <> 'none' or coalesce\(p_supplier_action, 'none'\) <> 'none'\) then\s*raise exception/);
  assert.match(d, /insert into public\.supplier_strike_event/); assert.match(d, /fn_refund_request\(/);
  assert.match(d, /matching_block_reason = 'dispute_upheld'/);
  assert.match(body('fn_accountant_dispute_remedy_tick'), /fn_refund_request\([\s\S]*'goodwill', 'ceo_dispute_decision'/);
});

test('every routine is pinned and revoked; the table is closed; no dynamic SQL; links on quotesdone.ae', () => {
  const fns = [...SQL.matchAll(/create or replace function public\.([a-z0-9_]+)\(/g)].map((m) => m[1]);
  assert.ok(fns.length >= 20, `only ${fns.length} routines found`);
  for (const fn of new Set(fns)) {
    assert.match(body(fn), /set search_path to 'public', 'pg_temp'/, `${fn} has no pinned search_path`);
    assert.match(SQL, new RegExp(`revoke execute on function public\\.${fn}\\([^)]*\\) from public, anon, authenticated;`), `${fn} is not revoked`);
  }
  assert.match(SQL, /alter table public\.reveal_contact_statement enable row level security;/);
  assert.match(SQL, /create policy reveal_contact_statement_service_role_only on public\.reveal_contact_statement\s+as permissive for all to public using \(false\) with check \(false\);/);
  assert.match(SQL, /revoke all on public\.reveal_contact_statement from anon, authenticated;/);
  assert.doesNotMatch(SQL, /execute format\(/i);
  for (const l of [...SQL.matchAll(/https:\/\/[a-z.]+\/[^\s']*/g)].map((m) => m[0])) assert.match(l, /^https:\/\/quotesdone\.ae\//, `${l} is not on quotesdone.ae`);
});

test('pending note or MANIFEST line, exactly one; the probe is never applied', () => {
  const note = existsSync(join(REPO, 'scripts/sql/pending', NAME + '.txt'));
  const listed = read('scripts/sql/MANIFEST.txt').split('\n').some((l) => l.trim() === `scripts/sql/${NAME}.sql`);
  assert.ok(note !== listed, 'the file needs exactly one of a pending note and a MANIFEST line');
  assert.ok(existsSync(join(REPO, 'scripts/sql/pending', NAME + '_probe.txt')), 'the probe has no pending note');
  assert.ok(!read('scripts/sql/MANIFEST.txt').includes(NAME + '_probe.sql'), 'the probe is in MANIFEST');
});

// ── REVIEW AFTERREVEAL (16 Nov 2026, customer_support builder: after-reveal review fixes) ─────────────────────────────────────────
test('R1: the two live money routines keep what production added after the mirror', () => {
  const st = body('fn_refund_state');
  assert.match(st, /v_start := public\.fn_reveal_clock_start\(t\.id\);/, 'fn_refund_state lost the 13 Nov R6 clock (rebuilt from the mirror again?)');
  for (const k of ['partly_refunded', 'refunded_aed', 'clock_starts_at']) assert.match(st, new RegExp(`'${k}'`), `fn_refund_state lost ${k}`);
  const o = body('fn_refund_open_from_customer');
  assert.match(o, /and reason_code is distinct from 'overcharge_return'\s+-- the accountant's return of an overcharge is not the customer's case/,
    'fn_refund_open_from_customer lost the 15 Nov overcharge_return handling');
  assert.match(o, /round\(coalesce\(t\.total_charged, t\.reveal_fee, 0\) \* 100\)::bigint - v_over/, 'the case no longer files what remains after an overcharge return');
});

test('R2: an overcharge return is not an open refund for the CEO\'s dispute remedy', () => {
  const d = body('fn_ceo_decides_post_reveal_dispute');
  assert.match(d, /r\.status not in \('rejected', 'failed', 'cancelled'\)\s+and r\.reason_code is distinct from 'overcharge_return'\) then\s+(?:--[^\n]*\n\s+)?v_effect := v_effect \|\| jsonb_build_object\('refund', 'already_open'\)/);
  assert.match(d, /fn_refund_request\(round\(coalesce\(t\.total_charged, t\.reveal_fee, 0\) \* 100\)::bigint - v_over,/);
  assert.match(body('fn_accountant_dispute_remedy_tick'), /r\.reason_code is distinct from 'overcharge_return'\) then/);
});

test('R4: a denial after the supplier\'s claim is never swallowed by the duplicate rule', () => {
  const r = body('fn_reveal_contact_record');
  assert.match(r, /and coalesce\(t\.supplier_ack_at, '-infinity'::timestamptz\) <= v_prev\.said_at/);
  assert.match(r, /and not exists \(select 1 from public\.messages m where[\s\S]*m\.created_at > v_prev\.said_at\) then/);
});

test('R5: every reading of the intake answers the customer with a ticket and a reply written by the model', () => {
  const a = body('fn_reason_apply_customer_support__dispute_intake');
  assert.match(a, /v_tk := public\.fn_complaint_open\(v_c\.email/, 'not_dispute / supplier_contacted open no ticket');
  assert.match(a, /fn_customer_support_voice_owe\('dispute_intake\.answer'/, 'not_dispute / supplier_contacted owe him no reply');
  assert.doesNotMatch(a, /if v_choice = 'not_dispute' then return/, 'not_dispute returns before answering him again');
});

test('R6: the widget names no job itself, a widget reading records no "yes", the CEO\'s reasoning decides, a pause ends', () => {
  const a = body('fn_reason_apply_customer_support__dispute_intake');
  const widget = a.slice(a.indexOf("if v_choice = 'supplier_contacted' and v_ch = 'widget' then"), a.indexOf("elsif v_choice = 'supplier_contacted' then"));
  assert.ok(widget.length > 0, 'the widget reading has no branch of its own');
  assert.doesNotMatch(widget, /fn_reveal_contact_record/, 'a widget reading writes the customer\'s word on contact');
  assert.match(widget, /https:\/\/quotesdone\.ae\/u\/followup\?t=/, 'the widget reading does not ask him to confirm with one tap');
  assert.match(body('fn_customer_after_reveal_message'), /if p_transaction is null and p_channel = 'widget' then[\s\S]*'customer_support\.after_reveal_job'/);
  const j = body('fn_reason_apply_customer_support__after_reveal_job');
  assert.match(j, /x\.customer_id = \(h\.subject->>'customer_id'\)::uuid/, 'the named job is not checked to be his');
  assert.match(j, /fn_customer_support_voice_owe\('after_reveal\.widget_filed'/, 'he is not told what was filed');
  const ap = body('fn_reason_apply_ceo__post_reveal_dispute');
  assert.match(ap, /fn_ceo_reasons_problem\(p_result->>'answer'\)/); assert.match(ap, /public\.fn_ceo_decides_post_reveal_dispute\(d\.id, split_part\(v_choice, '\|', 1\)/);
  assert.match(body('fn_ceo_post_reveal_dispute_tick'), /fn_seat_duty_reason\('ceo', 'ceo\.post_reveal_dispute'/);
  assert.match(SQL, /\('ceo\.post_reveal_dispute', 'ceo', interval '1 hour', 'fn_ceo_post_reveal_dispute_tick'/);
  const d = body('fn_ceo_decides_post_reveal_dispute');
  assert.match(d, /'pause_skipped', 'already blocked', 'blocked_for'/, 'a pause skipped because the supplier was already blocked is not recorded');
  assert.match(d, /set pause_until = public\.fn_add_working_days\(now\(\)/);
  assert.match(body('fn_ceo_lifts_dispute_pause'), /where id = d\.supplier_id and matching_block_reason = 'dispute_upheld'/, 'a lift can clear another block');
  assert.match(SQL, /\('ceo\.dispute_pause', 'ceo', interval '1 hour', 'fn_ceo_dispute_pause_tick'/);
});

test('the CEO refund checklist file: built on production, reads the word and the dispute, applied after both branch files', () => {
  const CN = 'the_ceo_refund_checklist_reads_the_customers_word_the_dispute_and_every_channel';
  const C = read('scripts/sql/' + CN + '.sql');
  assert.match(C, /md5\(prosrc\) 027da5f6bf69ba10ab4a648c1028b307/);
  assert.match(C, /v_basis := public\.fn_refund_dispute_basis\(t\.id\);/); assert.match(C, /v_word := public\.fn_reveal_contact_word\(t\.id\);/);
  assert.match(C, /and \(not v_conflict or v_conf_choice is not distinct from 'refund_review'\)\)/, 'a contested word can pass item 4 unanswered');
  assert.match(C, /'remediable', v_proofs = 0 and not v_live and v_conf_choice is distinct from 'uphold_reveal'/);
  assert.match(C, /v_rated := public\.fn_refund_rating_shows_dealing\(t\.id\);/);
  assert.match(C, /v_tl := public\.fn_contact_timeline\(v_cust, 60\);/, 'item 1b (every_door) is missing');
  assert.match(C, /exception when others then\s+v_seen := '\[\]'::jsonb; v_prom := '\[\]'::jsonb;/, 'item 1b is not guarded');
  assert.match(C, /revoke execute on function public\.fn_ceo_refund_checklist\(uuid, text, boolean\) from public, anon, authenticated;/);
  assert.doesNotMatch(C, /execute format\(/i);
  // Waiting, its note orders it after the every-door file; applied (16 Nov 05:39 UTC, 14ac60ac2), its MANIFEST line follows
  // BOTH branch files, so it is the canonical fn_ceo_refund_checklist and file 2 was not re-applied over it.
  const st = applyState('scripts/sql/' + CN + '.sql');
  assert.ok(st.applied !== (st.note !== null), 'the checklist file is both pending and in MANIFEST, or neither');
  if (st.note !== null) assert.match(st.note, /every_door_and_the_ceo_read_the_same_case\.sql[\s\S]*THIS FILE/, 'the pending note does not order it after the every-door file');
  else for (const before of ['a_paid_reveal_asks_the_customer_and_every_money_problem_reaches_a_case', 'every_door_and_the_ceo_read_the_same_case']) {
    const b = applyState(`scripts/sql/${before}.sql`).index;
    assert.ok(b >= 0 && b < st.index, `the checklist file is applied before ${before}.sql, or that file was re-applied over it`);
  }
  const probe = applyState('scripts/sql/' + CN + '_probe.sql');
  assert.ok(existsSync(join(REPO, 'scripts/sql', CN + '_probe.sql')) && /^A PROBE/.test(probe.note || '') && !probe.applied, 'the probe is missing, or is applied');
});
