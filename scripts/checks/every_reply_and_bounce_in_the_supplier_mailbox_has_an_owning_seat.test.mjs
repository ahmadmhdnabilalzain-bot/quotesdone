// EVERY REPLY AND BOUNCE IN THE SUPPLIER MAILBOX HAS AN OWNING SEAT (1 Nov 2026; sales_engineer, customer_support,
// it_engineer).
//
// On 1 Nov 2026 receipts_never_wait_on_the_founder failed on five messages to supplier@quotesdone.com that no seat
// owned: three founder replies to his own seed test, one reply to a hand-sent mail, and a Gmail bounce of an
// invitation. The invite-reply filer hands over only an invited lead's reply and every other exit left the row
// unowned; a bounce that arrives as mail was read by nobody, so the bounced lead stayed on the nudge list.
//
// WHAT FAILS IF THE CAUSE RETURNS:
//   * offline: the definition that wins the apply order of trg_invite_reply_reaches_sales_engineer stops calling
//     fn_supplier_mailbox_mail_gets_its_owner, or that routine loses an exit's owner (bounce -> customer_support,
//     founder -> it_engineer, a person -> sales_engineer), or the bounce stops suppressing the address;
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

/** The problems with the trigger body and the owner routine, [] when every exit has its owner. */
export function problems(trg, owner) {
  const out = [];
  if (!trg || !/public\.fn_supplier_mailbox_mail_gets_its_owner\(\s*new\.id/i.test(trg)) out.push('the z52 trigger no longer gives the message an owner');
  if (!owner) { out.push('fn_supplier_mailbox_mail_gets_its_owner is not defined'); return out; }
  const b = owner.replace(/\s+/g, ' ');
  if (!/fn_inbound_is_bounce\(/.test(b) || !/v_owner := 'customer_support'/.test(b)) out.push('a bounce is not customer_support\'s');
  if (!/insert into public\.email_suppressions/.test(b) || !/set invite_status = 'bounced'/.test(b)) out.push('a permanent bounce no longer suppresses the address and marks its lead');
  if (!/fn_is_founder_own_inbox\(v_from\)[^;]*then update public\.inbound_messages set owner_role = 'it_engineer'/.test(b)) out.push('the founder\'s own inbox is not the it_engineer\'s');
  if (!/v_owner := 'sales_engineer'/.test(b) || !/'mailbox\.supplier_reply'/.test(b)) out.push('a person who is no invited lead is not handed to the sales engineer');
  if (/set (needs_review|replied_at)/.test(b)) out.push('the routine closes a message instead of handing it over');
  return out;
}

test('the definitions that win the apply order give every supplier-mailbox message an owning seat', () => {
  const t = winning('trg_invite_reply_reaches_sales_engineer');
  const o = winning('fn_supplier_mailbox_mail_gets_its_owner');
  const read = (f) => readFileSync(join(REPO, 'scripts/sql', f), 'utf8');
  const p = problems(bodyOf(read(t), 'trg_invite_reply_reaches_sales_engineer'), bodyOf(read(o), 'fn_supplier_mailbox_mail_gets_its_owner'));
  assert.deepEqual(p, [], `${t} / ${o}: ${p.join('; ')}`);
});

test('known-bad control: the trigger as it was on 1 Nov 2026 is caught', () => {
  const before = `
declare
begin
  begin
    perform public.fn_marketing_files_invite_reply(new.id);
  exception when others then
    raise warning 'x';
  end;
  return null;
end `;
  assert.ok(problems(before, bodyOf(src, 'fn_supplier_mailbox_mail_gets_its_owner')).length > 0, 'the trigger before the fix passes');
  const noBounce = bodyOf(src, 'fn_supplier_mailbox_mail_gets_its_owner').replace(/insert into public\.email_suppressions/g, 'select 1 from public.email_suppressions');
  assert.ok(problems(bodyOf(src, 'trg_invite_reply_reaches_sales_engineer'), noBounce).some((x) => /suppresses/.test(x)), 'a bounce that suppresses nothing passes');
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
