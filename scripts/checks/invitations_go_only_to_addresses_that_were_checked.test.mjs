// THE INVITATIONS GO ONLY TO ADDRESSES THAT WERE CHECKED (ceo, 19 Nov 2026; rulings 1455, 1486, 1696).
// Text checks over scripts/sql/invitations_go_only_to_addresses_that_were_checked.sql and the last note's copy, each with a
// known-bad control taken from the same text. Measured that day: invitations to 'verified' addresses bounced 1 of 74, to 'true'
// (syntax + MX) 6 of 38, to the unchecked directory rows 8 of 32; brake 51 stopped the company on 2 hard of 6; 37 leads sat
// queued behind a cancelled invitation; the funnel counted 40 nudges as sends; the last note gave UAE suppliers a US number.
// The behaviour itself is the file's probe (its verdict row at apply).
//   node --test scripts/checks/invitations_go_only_to_addresses_that_were_checked.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const SQL = R('scripts/sql/invitations_go_only_to_addresses_that_were_checked.sql');
// the short first file (review of 19 Nov 2026): the index, enqueue's ON CONFLICT and trigger z82, so their locks are brief
const SLOT = R('scripts/sql/a_cancelled_invitation_frees_its_lead_and_its_index_slot.sql');
const code = (s) => s.replace(/--[^\n]*/g, '');
const norm = (s) => s.replace(/\s+/g, ' ').trim().toLowerCase();
/** The body of a routine as one of the two files defines it, comments removed. */
function body(fn, src = SQL.match(new RegExp(`create or replace function public\\.${fn}\\(`, 'i')) ? SQL : SLOT) {
  const m = new RegExp(`create or replace function public\\.${fn}\\(`, 'i').exec(src);
  assert.ok(m, `${fn} is not defined in either file`);
  const rest = src.slice(m.index);
  const tag = /\bas\s+(\$[a-z0-9_]*\$)/i.exec(rest);
  const from = tag.index + tag[0].length;
  return code(rest.slice(from, rest.indexOf(tag[1], from)));
}

const evidenceList = (b) => [...(/in\s*\(([^)]*)\)/.exec(b)?.[1] ?? '').matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).sort();
test('a checked address is verified, maps or social: never syntax + MX (true), never unchecked', () => {
  const b = body('fn_invite_address_has_evidence');
  assert.deepEqual(evidenceList(b), ['maps', 'social', 'verified']);
  assert.notDeepEqual(evidenceList(b.replace("'maps'", "'maps', 'true'")), ['maps', 'social', 'verified'], 'control: true passed');
});

const NEVER_TWICE_IGNORES_CANCELLED = /n\.type = 'supplier_invite' and lower\(btrim\(n\.to_email\)\) = lower\(btrim\(p\.email\)\)\s+and \(n\.status is distinct from 'cancelled' or n\.sent_at is not null\)/;
test('both eligibility rules require the evidence, and their never-twice test ignores an invitation cancelled before it left', () => {
  for (const fn of ['fn_supplier_invite_eligible', 'fn_supplier_invite_eligible_ids']) {
    const b = body(fn);
    assert.match(b, /public\.fn_invite_address_has_evidence\(p\.email_verified\)/, `${fn} does not require the evidence`);
    assert.match(b, NEVER_TWICE_IGNORES_CANCELLED, `${fn} still counts a cancelled, never-sent invitation`);
    // the rules that were there stay: the stored verdict of this address, a measured MX, suppression, the platform domains
    assert.match(b, /verdict = 'verified'[\s\S]{0,40}email_md5 = md5\(lower\(btrim\(p\.email\)\)\)/, `${fn} lost the verdict`);
    assert.match(b, /m\.kind = 'mx'/); assert.match(b, /email_platform_domain/);
    assert.match(b, fn.endsWith('_ids') ? /email_suppressions/ : /fn_email_sendable/);
  }
  assert.doesNotMatch("where n.type = 'supplier_invite' and lower(btrim(n.to_email)) = lower(btrim(p.email)))", NEVER_TWICE_IGNORES_CANCELLED, 'control');
});

const PRED = "type = 'supplier_invite' and (status is distinct from 'cancelled' or sent_at is not null)";
test('the once-only index and the batch\'s ON CONFLICT name the same predicate (a mismatch fails every batch)', () => {
  const idx = /create unique index notifications_supplier_invite_once_uidx on public\.notifications \(lower\(btrim\(to_email\)\)\)\s+where ([^;]*);/.exec(code(SLOT));
  assert.doesNotMatch(code(SQL), /create unique index|drop index|create or replace trigger|enqueue_supplier_invites\(p_cap/,
    'the second file takes a strong lock on notifications again');
  assert.ok(idx, 'the index is not rebuilt');
  assert.equal(norm(idx[1]), PRED);
  const conflicts = [...code(SLOT).matchAll(/on conflict \(lower\(btrim\(to_email\)\)\) where ([^\n]*?) do nothing/g)].map((m) => norm(m[1]));
  assert.ok(conflicts.length >= 2, 'the batch and the zero-row proof both name the conflict target');
  for (const c of conflicts) assert.equal(c, PRED, 'an ON CONFLICT names another predicate than the index');
  assert.notEqual(norm("type = 'supplier_invite'"), PRED, 'control: the old predicate passed');
  assert.match(body('enqueue_supplier_invites'), /on conflict \(lower\(btrim\(to_email\)\)\) where type = 'supplier_invite' and \(status is distinct from 'cancelled' or sent_at is not null\) do nothing/);
});

test('every insert into the outbox in either file inserts nothing (WHERE false): neither file queues a message', () => {
  const inserts = [...code(SQL + SLOT).matchAll(/insert into public\.notifications\b[\s\S]*?;/g)].map((m) => m[0]);
  assert.ok(inserts.length >= 1);
  for (const s of inserts) assert.match(s, /\swhere false\s/, 'an insert into notifications that can write a row');
  assert.match(SLOT, /zz-demo-never-sent@example\.invalid/, 'the proof row is not a fixture address');
});

// The WHEN clause of z82, evaluated as Postgres would on last_error (LIKE on null is null: the trigger does not fire)
const whenPrefixes = (src) => [...(/when \(new\.type = 'supplier_invite'[\s\S]*?execute function/.exec(code(src))?.[0] ?? '')
  .matchAll(/new\.last_error like '((?:[^']|'')*)%'/g)].map((m) => m[1].replace(/''/g, "'"));
const frees = (prefixes, lastError) => lastError != null && prefixes.some((p) => lastError.startsWith(p));
test('z82 frees a lead only when the campaign itself stopped the invitation: never a cancel with no last_error', () => {
  const pre = whenPrefixes(SLOT);
  assert.deepEqual(pre.sort(), ["cancelled at send time:", "cancelled: the restart's probation failed", 'cancelled: the supplier campaign was paused'].sort());
  // the writers' own words (read from the live routines and send_outbox on 19 Nov 2026)
  for (const w of ['cancelled: the supplier campaign was paused by invite_bounce_judge: 2 hard bounce(s)',
                   "cancelled: the restart's probation failed: 2 hard bounce(s)", 'cancelled at send time: the company is stopped']) {
    assert.ok(frees(pre, w), `a campaign stop does not free its lead: ${w}`);
  }
  assert.ok(!frees(pre, null), 'a cancel with no last_error (fn_sales_engineer_records_email_checks) frees the lead');
  assert.ok(!frees(pre, ''), 'an empty last_error frees the lead');
  assert.ok(!frees(pre, 'cancelled by hand'), 'a cancel by hand frees the lead');
  assert.ok(!frees(pre, 'duplicate: the same message to the same person'), 'a duplicate frees the lead');
  // the writers still write those words, so the trigger is not silently dead
  const lane = R('supabase/functions/send_outbox/invite_lane.ts');
  assert.match(lane, /'cancelled at send time: ' \+ v\.why/, 'send_outbox no longer writes the send-time prefix');
  assert.ok(frees(['x'], 'xy') && !frees([], 'x'), 'control');
});

test('a queued invitation cancelled before it left frees its lead, unless another invitation to it is live', () => {
  const t = body('trg_notifications_a_cancelled_invitation_frees_its_lead');
  assert.match(t, /set invite_status = null, invited_at = null/);
  assert.match(t, /l\.invite_status = 'queued'/, 'it would reset a bounced, unsubscribed or registered lead');
  assert.match(t, /n\.id <> new\.id/); assert.match(t, /n\.status is distinct from 'cancelled' or n\.sent_at is not null/);
  assert.match(code(SLOT), /after update of status on public\.notifications\s+for each row when \(new\.type = 'supplier_invite' and new\.status = 'cancelled' and old\.status is distinct from 'cancelled'\s+and new\.sent_at is null/);
});

test('the brake judges a hard-bounce rate only on a sample of 20, and a burst of 3 in a day still stops it', () => {
  const cell = body('fn_invite_judge_cell');
  const hard = /when p_hard >= [^\n]*\n[^\n]*then 'hard'/.exec(cell)?.[0] ?? '';
  assert.match(hard, /p_sent >= coalesce\(\(p_cfg->>'hard_min_sent'\)::int, 20\)/, 'the hard breach has no minimum sample');
  assert.match(hard, /fn_invite_wilson_lower|hl >/, 'the hard breach no longer reads the lower bound');
  assert.match(cell, /fn_invite_wilson_lower/);
  assert.match(cell, /when p_complaint >= /, 'the complaint rule is gone from the cell');
  assert.match(SQL, /'hard_min_sent', 20, 'hard_burst', 3/, 'the limits are not data');
  const j = body('fn_invite_bounce_judgement');
  assert.match(j, /coalesce\(\(v_today_all->>'hard'\)::int, 0\) >= coalesce\(\(v_cfg->>'hard_burst'\)::int, 3\)/, 'no burst rule below the sample');
  assert.match(j, /if coalesce\(\(v_all->>'complaint'\)::int, 0\) > 0 then\s+v_company := 'complaint'/, 'any complaint no longer stops the company');
  assert.match(j, /public\.fn_invite_address_has_evidence\(l\.email_verified\) or n\.type <> 'supplier_invite' then 'checked' else 'unchecked'/,
    'the checked segment is not the population the company sends');
  assert.doesNotMatch(j, /'verified', 'true', 'maps', 'social'/, 'the judgement still counts syntax + MX as checked');
  assert.doesNotMatch("when p_hard >= coalesce((p_cfg->>'hard_min')::int, 2) and hl > 0.03 then 'hard'", /p_sent >= /, 'control');
});

test('the CEO restarts only on a projection under 3% on 20 sends, through his own restart routine, and records the decision', () => {
  const p = body('fn_invite_restart_projection');
  assert.match(p, /fn_invite_address_has_evidence\(l\.email_verified\)/);
  assert.match(p, /n\.type = 'supplier_invite' and n\.sent_at is not null/);
  assert.match(p, /'ok', coalesce\(t\.sent >= k\.min_sent and t\.bounced::numeric \/ nullif\(t\.sent, 0\) < k\.max_rate, false\)/);
  assert.match(SQL, /'restart_max_rate', 0\.03, 'restart_min_sent', 20/);
  const r = body('fn_ceo_restarts_invites');
  assert.match(r, /when not coalesce\(\(v_proj->>'ok'\)::boolean, false\) then/, 'the CEO restarts without the projection');
  for (const kept of [/v_used >= v_limit/, /never restarted over a complaint/, /interval '24 hours'/, /insert into public\.email_suppressions/,
                      /insert into public\.invite_brake_decision/]) assert.match(r, kept, `the CEO restart lost ${kept}`);
  const block = code(SQL.slice(SQL.indexOf('do $ceo$'), SQL.indexOf('end $ceo$;')));
  assert.match(block, /public\.fn_ceo_restarts_invites\(v_reason\)/, 'the file restarts around the CEO routine');
  // every safety fact raises BEFORE the restart, so a failure rolls the file back with the lane off (review of 19 Nov 2026)
  const restartAt = block.indexOf('public.fn_ceo_restarts_invites(v_reason)');
  for (const fact of ['an eligible lead has no evidence', 'the google ready pool (fn_supplier_invite_candidates) is empty',
                      'address(es) in the ready pool have no evidence', 'the once-only index still counts a cancelled invitation',
                      'trigger z82_notifications_a_cancelled_invitation_frees_its_lead is missing']) {
    const at = SQL.indexOf(fact, SQL.indexOf('do $ceo$'));
    assert.ok(at > 0, `no raise for: ${fact}`);
    assert.match(SQL.slice(at - 40, at), /raise exception '/, `${fact} is not raised`);
    assert.ok(at < SQL.indexOf('public.fn_ceo_restarts_invites(v_reason)'), `${fact} is checked after the restart`);
  }
  assert.ok(restartAt > 0);
  // ... and the file refuses to run at all without the first one
  const needs = code(SQL.slice(SQL.indexOf('do $needs$'), SQL.indexOf('end $needs$;')));
  assert.match(needs, /raise exception 'apply a_cancelled_invitation_frees_its_lead_and_its_index_slot\.sql first/);
  assert.ok(SQL.indexOf('do $needs$') < SQL.indexOf('create or replace function'), 'the prerequisite is checked after the file has changed things');
  assert.doesNotMatch(block, /key = 'invite_enabled'/, 'the file writes invite_enabled itself instead of through the CEO routine');
  const capWrite = block.indexOf("update public.app_secrets set value = v_cap::text where key = 'invite_daily_cap'");
  assert.ok(capWrite > 0 && block.indexOf('if v_ok then') < capWrite && capWrite < block.indexOf("v_choice := 'hold'"), 'the cap moves without a restart');
  assert.match(block, /least\(coalesce\(\(select \(nullif\(value, ''\)::jsonb->>'base_cap'\)::int/, 'the cap is not the ramp start');
  assert.match(block, /public\.fn_invite_founder_cap\(/, 'the cap ignores the founder cap (ruling 1231)');
  assert.match(block, /insert into public\.ceo_own_decision/);
});

test('the funnel counts first invitations as sent and delivered; nudges are their own column', () => {
  const f = body('fn_ceo_supplier_funnel_refresh');
  assert.match(f, /case when n\.type = 'supplier_invite_nudge' then 0 else 1 end as sent/);
  assert.match(f, /case when n\.type = 'supplier_invite_nudge' or r\.invite_status = 'bounced' then 0 else 1 end as delivered/);
  assert.match(f, /insert into public\.ceo_supplier_funnel_daily \([^)]*nudges_sent\)/);
  assert.doesNotMatch(f, /\b1 as sent\b/, 'a nudge is a send again');
  assert.match(SQL, /add column if not exists nudges_sent integer not null default 0/);
});

test('the file ends with one verdict row; the stranded leads are released and their old stamps kept', () => {
  const c = code(SQL).trimEnd();
  const last = c.slice(c.lastIndexOf('\nwith cfg as') + 1);
  assert.ok(last.endsWith(';') && !/\ninsert |\nupdate |\ndelete |\ndo \$/i.test(last), 'a statement follows the probe'); assert.match(last, /'PROBE OK: '/); assert.match(last, /'PROBE FAILED: '/);
  for (const w of ['cell 2/6', 'brake 51 replayed', 'released', 'funnel', 'notifications queued by this file']) assert.ok(last.includes(w) || SQL.includes(w), w);
  assert.match(SQL, /'invite_stranded_release'/); assert.match(SQL, /'was_invited_at'/);
  for (const src of [SQL, SLOT]) assert.match(src, /set local lock_timeout = '1500ms';/);
  const slotLast = code(SLOT).trimEnd();
  assert.match(slotLast.slice(slotLast.lastIndexOf('\nwith t as')), /'PROBE OK: '[\s\S]*'PROBE FAILED: '|'PROBE FAILED: '[\s\S]*'PROBE OK: '|PROBE OK[\s\S]*PROBE FAILED/, 'the first file has no verdict row');
});

test('the last note to a parked lead carries no telephone number; the copy rules refuse a foreign one', () => {
  const lane = R('supabase/functions/send_outbox/m365_lane.ts');
  const ft = lane.slice(lane.indexOf('export function m365FinalTouchText'), lane.indexOf('export function companyFromBody'));
  assert.ok(ft.length > 100, 'm365FinalTouchText not found');
  assert.doesNotMatch(ft, /FINAL_TOUCH_PHONE|our number is|\+1 218/, 'the last note writes a number out');
  assert.doesNotMatch(lane, /export const FINAL_TOUCH_PHONE/);
  assert.match(lane, /rule: 'no telephone number outside the UAE \(\+971\) in a supplier campaign e-mail'/);
  assert.match("`If you would rather talk on WhatsApp, our number is ${FINAL_TOUCH_PHONE}.`", /FINAL_TOUCH_PHONE|our number is/, 'control');
});
