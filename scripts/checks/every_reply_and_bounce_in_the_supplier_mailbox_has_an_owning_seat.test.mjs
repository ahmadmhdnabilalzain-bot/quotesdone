// EVERY REPLY AND BOUNCE IN THE SUPPLIER MAILBOX HAS AN OWNING SEAT (1 Nov 2026; sales_engineer, customer_support,
// it_engineer).
//
// On 1 Nov 2026 receipts_never_wait_on_the_founder failed on five messages to supplier@quotesdone.com that no seat
// owned: three founder replies to his own seed test, one reply to a hand-sent mail, and a Gmail bounce of an
// invitation. The invite-reply filer hands over only an invited lead's reply and every other exit left the row
// unowned; a bounce that arrives as mail was read by nobody, so the bounced lead stayed on the nudge list.
//
// WHAT FAILS IF THE CAUSE RETURNS:
//   * offline: the owner is written at insert (email_triage reads only owner_role-null rows, so it would never answer an
//     invited supplier's "yes"; independent review of this PR), or not after triage declines, or an exit loses its owner
//     (bounce -> customer_support, founder -> it_engineer, a person -> sales_engineer), or a bounce suppresses without
//     an authenticated sender;
//   * production, in ONE aborted transaction (the pending file replayed first; ZZ DEMO and example.invalid only, every
//     row rolls back): the _probe file must answer PROBE OK. On the definition before this fix it answers PROBE FAILED.
//
//   node --test scripts/checks/every_reply_and_bounce_in_the_supplier_mailbox_has_an_owning_seat.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const NAME = 'every_reply_and_bounce_in_the_supplier_mailbox_has_an_owning_seat';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const src = readFileSync(join(REPO, FILE), 'utf8');
const pending = existsSync(join(REPO, 'scripts/sql/pending', `${NAME}.txt`));
const manifest = readFileSync(join(REPO, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).map((l) => l.trim())
  .filter((l) => l && !l.startsWith('#')).map((l) => l.replace(/^scripts\/sql\//, ''));

/** One routine's dollar-quoted body, with -- comments removed, so a comment cannot satisfy the check. */
export function bodyOf(text, fn) {
  const open = text.search(new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${fn}\\s*\\(`, 'i'));
  if (open < 0) return null;
  const m = /\bas\s+(\$[a-z_]*\$)/i.exec(text.slice(open));
  if (!m) return null;
  const start = open + m.index + m[0].length;
  return text.slice(start, text.indexOf(m[1], start)).replace(/--[^\n]*/g, '');
}

/** The file that defines a routine LAST: a pending file is applied after everything in MANIFEST, so it wins. */
function winning(fn) {
  const defines = (f) => existsSync(join(REPO, 'scripts/sql', f)) && bodyOf(readFileSync(join(REPO, 'scripts/sql', f), 'utf8'), fn) !== null;
  if (pending && defines(`${NAME}.sql`)) return `${NAME}.sql`;
  const listed = manifest.filter(defines);
  assert.ok(listed.length > 0, `no applied file defines ${fn}`);
  return listed[listed.length - 1];
}

/** The problems with the fix, [] when every declined message gets its owner and none is owned before triage reads it. */
export function problems(fileText, z52Body) {
  const out = [];
  const t = fileText.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');
  // the owner is written only AFTER email_triage declined: email_triage reads owner_role-null rows only
  const trg = /create trigger z53_supplier_mailbox_mail_gets_its_owner after update of triaged_at on public\.inbound_messages for each row when \(([^;]*)\) execute function public\.trg_supplier_mailbox_mail_gets_its_owner\(\)/i.exec(t);
  if (!trg) out.push('no z53 trigger on UPDATE OF triaged_at: the owner is not given when triage declines');
  else {
    if (!/new\.ai_category = 'no_auto_reply'/.test(trg[1])) out.push('z53 does not wait for triage to decline (ai_category no_auto_reply)');
    if (!/new\.ai_summary like 'Not answered automatically:%'/.test(trg[1])) out.push('z53 can fire on a model\'s category string, not only on triage\'s own decline');
    if (!/new\.owner_role is null/.test(trg[1]) || !/new\.replied_at is null/.test(trg[1])) out.push('z53 can take an owned or answered message');
  }
  if (/after insert[^;]*trg_supplier_mailbox_mail_gets_its_owner/i.test(t)) out.push('the owner is written at insert: email_triage would never answer the message');
  if (z52Body && /fn_supplier_mailbox_mail_gets_its_owner/.test(z52Body)) out.push('z52 (at insert) writes the owner: email_triage would never answer the message');
  const owner = bodyOf(fileText, 'fn_supplier_mailbox_mail_gets_its_owner');
  if (!owner) { out.push('fn_supplier_mailbox_mail_gets_its_owner is not defined'); return out; }
  const o = owner.replace(/\s+/g, ' ');
  if (!/fn_inbound_is_bounce\(/.test(o) || !/v_owner := 'customer_support'/.test(o)) out.push('a bounce is not customer_support\'s');
  if (!/insert into public\.email_suppressions/.test(o) || !/set invite_status = 'bounced'/.test(o)) out.push('a permanent bounce no longer suppresses the address and marks its lead');
  const auth = o.indexOf("sender_authenticated"), sup = o.indexOf('insert into public.email_suppressions');
  if (auth < 0 || auth > sup) out.push('a bounce suppresses without its sender being authenticated');
  if (!/fn_is_founder_own_inbox\(v_from\)[^;]*then update public\.inbound_messages set owner_role = 'it_engineer'/.test(o)) out.push('the founder\'s own inbox is not the it_engineer\'s');
  if (!/v_owner := 'sales_engineer'/.test(o) || !/'mailbox\.supplier_reply'/.test(o)) out.push('a person who is no invited lead is not handed to the sales engineer');
  if (/set (needs_review|replied_at)/.test(o)) out.push('the routine closes a message instead of handing it over');
  return out;
}

function z52() {
  const f = winning('trg_invite_reply_reaches_sales_engineer');
  return bodyOf(readFileSync(join(REPO, 'scripts/sql', f), 'utf8'), 'trg_invite_reply_reaches_sales_engineer');
}

test('the owner is given after email_triage declines, never before it reads the message', () => {
  const p = problems(src, z52());
  assert.deepEqual(p, [], p.join('; '));
});

test('known-bad controls: an owner at insert, and a bounce that suppresses unauthenticated, are caught', () => {
  const atInsert = src.replace('after update of triaged_at', 'after insert');
  assert.ok(problems(atInsert, z52()).some((x) => /at insert|UPDATE OF triaged_at/.test(x)), 'an owner written at insert passes');
  const z52Stamping = 'begin perform public.fn_marketing_files_invite_reply(new.id); perform public.fn_supplier_mailbox_mail_gets_its_owner(new.id); return null; end';
  assert.ok(problems(src, z52Stamping).some((x) => /z52/.test(x)), 'z52 writing the owner at insert passes');
  const noAuth = src.replace(/elsif coalesce\(m\.raw->>'sender_authenticated'[\s\S]*?v_why := 'the bounce''s sender is not authenticated';/, '');
  assert.notEqual(noAuth, src, 'the control could not remove the authentication gate');
  assert.ok(problems(noAuth, z52()).some((x) => /authenticated/.test(x)), 'a bounce without the authentication gate passes');
});

test('the file is pending XOR in MANIFEST, and its probe is never applied', () => {
  assert.ok(pending !== manifest.includes(`${NAME}.sql`), 'exactly one of a pending note and a MANIFEST line');
  assert.ok(existsSync(join(REPO, 'scripts/sql/pending', `${NAME}_probe.txt`)), 'the probe has no pending note');
  assert.ok(!manifest.includes(`${NAME}_probe.sql`), 'the probe is in MANIFEST');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: every reply and bounce in the supplier mailbox gets its owner', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  // While pending, the fix is replayed first in the same transaction. Its five-row backfill and verdict are left out:
  // the probe is about the routing, and the verdict reads the real rows the apply hands over.
  const fix = src.slice(0, src.indexOf('-- the five rows of 1 Nov 2026'));
  assert.ok(fix.length > 1000, 'the fix could not be cut before its backfill');
  const block = (pending ? fix + '\n' : '') + readFileSync(join(REPO, PROBE), 'utf8');
  let msg = '';
  try { await replaySql(block, { retry: false }); msg = 'the probe committed instead of rolling back'; } catch (e) { msg = String(e.message); }
  const m = msg.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(m, 'the probe failed before it could report: ' + msg.slice(0, 1500));
  const out = JSON.parse(m[1].replace(/\\"/g, '"'));
  assert.equal(out.verdict, 'PROBE OK', JSON.stringify(out).slice(0, 3000));
});
