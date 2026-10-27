// NO TEST MAIL GOES TO THE FOUNDER'S OWN INBOXES (it_engineer, 27 Oct 2026).
//
// The founder, 27 Oct 2026: "stop doing tests on my email. thats extremely useless". Three paths mailed him tests: the
// morning seed (fn_invite_placement_due, every sending day, to his Gmail and management@), the warm-up / seed rows a
// session wrote by hand (type supplier_invite_seed, kind invite_m365_seed, to his five mailboxes), and
// scripts/invitation_inbox_check.mjs --send-seed, whose allowlist named his inboxes. This FAILS if any comes back:
//   * offline: the seed script accepts one of his addresses; the canonical fn_invite_placement_due (MANIFEST then
//     pending) writes anything; the canonical gate can pass, or stops failing closed by name; the refusing trigger,
//     its WHEN clause or a revoke goes; the file is neither applied nor pending, or the probe could be applied.
//   * production, in ONE aborted transaction (the file replayed while pending, then the probe): nothing is queued in
//     the old seed window with the campaign switched on; the gate answers fail:seed_retired and files one finding; a
//     seed to each of his mailboxes, a +tag, a dotted Gmail, a cc or a re-address is refused; a non-founder seed and
//     a founder_brief still go in; the ledger row is standing.
//
//   node --test scripts/checks/no_test_mail_goes_to_the_founders_own_inboxes.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestWithPending, pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const NAME = 'no_test_mail_goes_to_the_founders_own_inboxes';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const HIS = ['management@quotesdone.com', 'ahmadmhdnabilalzain@gmail.com', 'management@doratajewelries.com',
  'djzaino@outlook.com', 'bookings@djzaino.com', 'fati.labib@icloud.com'];

// The file that defines a routine last, in apply order (MANIFEST, then pending files): that body is what production runs.
function canonical(fn) {
  const re = new RegExp(`create or replace function public\\.${fn}\\(`, 'i');
  const path = manifestWithPending().filter((p) => { try { return re.test(code(R(p))); } catch { return false; } }).pop();
  assert.ok(path, `${fn} is defined nowhere`);
  const src = code(R(path));
  const open = src.search(re);
  return { path, body: src.slice(open, src.indexOf('$fn$;', src.indexOf('$fn$', open) + 4)) };
}

test('the seed script refuses every one of his mailboxes', async () => {
  const mod = await import('../invitation_inbox_check.mjs');
  for (const a of [...HIS, 'Ahmadmhdnabilalzain+x@gmail.com']) assert.equal(mod.seedAddressAllowed(a), false, `${a} is accepted as a seed`);
  assert.equal(mod.seedAddressAllowed('test-abc@srv1.mail-tester.com'), true, 'a test service is no longer accepted');
  assert.equal('FOUNDER_INBOXES' in mod, false, 'a founder allowlist came back');
});

test('the canonical morning seed writes nothing, and the gate cannot pass', () => {
  const due = canonical('fn_invite_placement_due');
  assert.equal(due.path, FILE, `${due.path} redefines fn_invite_placement_due after the retirement`);
  assert.doesNotMatch(due.body, /\binsert\b|\bupdate\b|notifications/i, 'the morning seed writes again');
  assert.match(due.body, /'action', 'idle'/);
  const gate = canonical('fn_invite_placement_gate');
  assert.equal(gate.path, FILE, `${gate.path} redefines fn_invite_placement_gate`);
  assert.doesNotMatch(gate.body, /'pass'/, 'the retired gate can pass without the GlockApps verdict');
  // THE OPEN-DAY BRANCH, PROVED FROM THE CODE (review of #1696): the probe never switches the campaign on, so the branch
  // that runs on an open day is read here. Its only statement is the finding relay inside an if, and the body's one
  // return, after that if, is unconditional: no day, open or held, can answer anything but fail:seed_retired.
  assert.equal((gate.body.match(/\breturn\b/g) || []).length, 1, 'the retired gate has a second way out');
  assert.match(gate.body, /end if;\s+return 'fail:seed_retired';\s+end\s*$/, 'the gate does not end in an unconditional fail:seed_retired');
  const branch = gate.body.slice(gate.body.indexOf('if public.fn_invite_placement_day_closed'), gate.body.lastIndexOf('end if;'));
  assert.equal((branch.replace(/'(?:[^']|'')*'/g, "''").match(/;/g) || []).length, 1, 'the open-day branch does more than file the one finding');
  assert.match(gate.body, /fn_invite_placement_day_closed\(p_now\) is null then\s+perform public\.fn_invite_placement_finding\(v_day, 'seed_retired',/, 'the finding is filed while the campaign is held, or not through the registered relay');
});

test('the refusal is a trigger on every seed row, before the founder-mail policy; new routines are closed', () => {
  const src = code(R(FILE));
  assert.match(src, /create trigger a01_notifications_no_test_mail_to_the_founder\s+before insert or update of to_email, cc_emails, type, kind on public\.notifications/);
  assert.ok('a01_notifications_no_test_mail_to_the_founder' < 'a10_notifications_founder_mail_policy', 'the policy would run first');
  assert.match(src, /when \(new\.type = 'supplier_invite_seed' or new\.kind in \('invite_m365_seed', 'supplier_invite_seed'\)\)/);
  assert.match(src, /raise exception 'no_test_mail_to_the_founder:/);
  for (const a of HIS) assert.ok(src.includes(`'${a}'`), `${a} is not one of his mailboxes in the guard`);
  for (const sig of ['fn_is_founder_own_inbox(text)', 'fn_mailbox_fold(text)', 'fn_notifications_no_test_mail_to_the_founder()']) {
    assert.ok(src.includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), `${sig} keeps the PUBLIC grant CREATE gives it`);
  }
  for (const fn of ['fn_is_founder_own_inbox', 'fn_mailbox_fold', 'fn_notifications_no_test_mail_to_the_founder', 'fn_invite_placement_due', 'fn_invite_placement_gate']) {
    const b = src.slice(src.indexOf(`create or replace function public.${fn}(`));
    assert.match(b.slice(0, 400), /set search_path to 'public', 'pg_temp'/, `${fn}: search_path not pinned`);
  }
  assert.doesNotMatch(src, /key = 'invite_enabled'[^;]*set|set value = 'true'|wa_supplier_invite_golive/, 'this file touches a campaign switch');
});

test('the change is applied or pending, and the probe is never applied', () => {
  // Neither the probe nor this check may write a campaign switch, even inside a rolled-back transaction (review of #1696).
  for (const f of [PROBE, 'scripts/checks/no_test_mail_goes_to_the_founders_own_inboxes.test.mjs']) {
    assert.doesNotMatch(code(R(f)).replace(/doesNotMatch\([^\n]*/g, ''), /(update|insert into|delete from)\s+(public\.)?app_secrets/i, `${f} writes app_secrets`);
  }
  const notes = pendingNotes();
  const inManifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).includes(FILE);
  assert.ok(inManifest !== notes.has(FILE), 'exactly one of a MANIFEST line and a pending note');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: no seed is queued, the gate fails by name, every seed to him is refused, business mail is not', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const replay = pendingNotes().has(FILE) ? R(FILE) : '';
  let verdict, evidence;
  try { await replaySql(replay + '\n' + R(PROBE), { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)\|(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    [verdict, evidence] = [m[1], m[2]];
  }
  assert.ok(verdict, 'the probe committed instead of rolling back');
  assert.equal(verdict, 'PROBE OK', `${verdict} — ${evidence}`);
});
