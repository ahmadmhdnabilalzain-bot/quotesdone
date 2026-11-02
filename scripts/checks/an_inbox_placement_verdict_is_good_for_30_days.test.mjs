// AN INBOX-PLACEMENT VERDICT IS GOOD FOR 30 DAYS, NOT 7 (sales_engineer, 2 Nov 2026).
//
// public.invite_placement_bar.max_age was 7 days, an it_engineer choice (not a founder ruling; ledger 1312 is only the
// Outlook 80% bar). On it the only open class, Google, went stale at 3 Nov 22:50Z and no invitation could be queued. The
// founder, 2 Nov: focus on the addresses that go to the inbox, ignore Microsoft, resume the invitations. This FAILS if:
//   * offline: the file does anything but set max_age to 30 days and append the reason to the note (another bar column, a
//     routine, a campaign switch, a second statement); the reason is not idempotent; the file is neither pending nor
//     applied, or applies before the gate it updates; the probe could be applied, or stops proving that Google stays open
//     past the old 7-day date while Microsoft, Yahoo/AOL and other stay closed; anything other than the one verdict
//     reader starts to read max_age; the verdict reader gets a literal window back (the bar must stay data).
//   * production, in ONE aborted transaction: the file (while pending) and then the probe, which records a verdict like the
//     real 27 Oct one and judges it one day, 7 days 1 minute, 29 days 23 hours and 30 days 1 minute later.
//
//   node --test scripts/checks/an_inbox_placement_verdict_is_good_for_30_days.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestWithPending, pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const NAME = 'an_inbox_placement_verdict_is_good_for_30_days';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const GATE = 'scripts/sql/the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.sql';
const GATE_PROBE = 'scripts/sql/the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider_probe.sql';
const RETIRED_SEED = 'scripts/sql/no_test_mail_goes_to_the_founders_own_inboxes.sql';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

test('the file sets max_age to 30 days and appends the reason; every other bar and every routine is untouched', () => {
  const src = code(R(FILE));
  const stmts = src.match(/\b(update|insert\s+into|delete\s+from|alter|create|drop|truncate|grant|revoke)\b/gi) || [];
  assert.deepEqual(stmts.map((s) => s.toLowerCase()), ['update'], 'the file does more than one update of the bar');
  const upd = src.match(/update\s+public\.invite_placement_bar\s+set([\s\S]*?)where id;/i);
  assert.ok(upd, 'the file does not update the one bar row (where id)');
  const cols = [...upd[1].matchAll(/^\s*(\w+)\s*=/gm)].map((m) => m[1]);
  assert.deepEqual(cols, ['max_age', 'note', 'updated_at', 'updated_by'], 'a bar column other than max_age and note is written');
  assert.match(upd[1], /max_age\s*=\s*interval '30 days'/);
  assert.match(upd[1], /note\s*=\s*case when position\(.*?in note\) > 0 then note\s+else note \|\|/s, 'the reason is appended without keeping the original note, or not once only');
  assert.match(src, /raise exception 'invite_placement_bar has % rows/, 'the update does not insist on exactly one row');
  for (const k of ['microsoft_min_inbox_pct', 'google_max_spam_pct', 'google_min_delivered_pct', 'yahoo_aol_min_inbox_pct', 'sender']) {
    assert.doesNotMatch(upd[1], new RegExp(`\\b${k}\\s*=`), `${k} is written by the window change`);
  }
  assert.doesNotMatch(src, /app_secrets|invite_enabled|golive|function/i, 'the file touches a campaign switch or a routine');
});

test('nothing but the verdict reader reads max_age, and it reads it from the bar', () => {
  const dirs = ['scripts/sql', 'supabase/functions', 'scripts'];
  const walk = (d) => readdirSync(join(ROOT, d), { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? (e.name === 'node_modules' ? [] : walk(`${d}/${e.name}`)) : (/\.(sql|ts|mjs)$/.test(e.name) ? [`${d}/${e.name}`] : []));
  const readers = dirs.flatMap((d) => (d === 'scripts' ? readdirSync(join(ROOT, d)).filter((n) => n.endsWith('.mjs')).map((n) => `scripts/${n}`) : walk(d)))
    .filter((p) => !/\.test\.mjs$/.test(p) && /(?<![A-Za-z0-9_])max_age(?![A-Za-z0-9_])/.test(code(R(p))));
  assert.deepEqual([...new Set(readers)].sort(), [FILE, PROBE, GATE, GATE_PROBE].sort(),
    'another file reads max_age: check that a 30-day window does not change what it does');
  const gate = code(R(GATE));
  assert.match(gate, /t\.tested_at < p_now - b\.max_age/, 'the verdict reader no longer compares a test with the bar\'s own max_age');
});

test('the file is pending or applied, after the gate it updates; the probe is a probe and proves the three things', () => {
  const notes = pendingNotes();
  const manifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim());
  assert.ok(manifest.includes(FILE) !== notes.has(FILE), 'exactly one of a MANIFEST line and a pending note');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
  assert.ok(!manifest.includes(PROBE), 'the probe is in MANIFEST: it would be applied');
  const order = manifestWithPending();
  assert.ok(order.indexOf(FILE) > order.indexOf(GATE), 'the file must apply after the gate file that creates the bar');
  const p = code(R(PROBE));
  assert.match(p, /interval '7 days 1 minute'/, 'the probe no longer tests one minute past the old 7-day date');
  assert.match(p, /open_old <> '\["google"\]'::jsonb/, 'the probe no longer requires Google to be the only open class past 7 days');
  for (const s of ["'fail:below_bar:microsoft'", "'fail:below_bar:yahoo_aol'", "'fail:stale_verdict'", "interval '30 days'", "interval '30 days 1 minute'"]) {
    assert.ok(p.includes(s), `the probe lost ${s}`);
  }
  assert.match(p, /'PROBE OK'/);
  assert.match(p, /'PROBE FAILED: '/);
  assert.doesNotMatch(p, /(update|insert\s+into|delete\s+from)\s+(public\.)?app_secrets|fn_invite_placement_(judge|gate|open_providers)\(/i,
    'the probe writes a switch or calls a routine that files a finding');
  // the older probe stays strict: a verdict past the bar's own max_age is stale, whatever the value
  const old = code(R(GATE_PROBE));
  assert.match(old, /fn_invite_placement_class_verdicts\(t0 \+ v_max \+ interval '1 minute'\)/);
  assert.match(old, /'fail:stale_verdict' or v ->> 'google' <> 'fail:stale_verdict'/, 'the older probe stopped requiring staleness past max_age');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const pendingText = () => [RETIRED_SEED, GATE, FILE].filter((f) => pendingNotes().has(f)).map(R).join('\n;\n');

test('production, aborted: google stays open past the old date; microsoft, yahoo_aol and other stay closed', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  let verdict, evidence;
  try { await replaySql(pendingText() + '\n;\n' + R(PROBE), { retry: false, label: NAME }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)\|(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    [verdict, evidence] = [m[1], m[2]];
  }
  assert.ok(verdict, 'the probe committed instead of rolling back');
  if (process.env.QD_SHOW_PROBE) console.log(verdict + '\n' + evidence);
  assert.equal(verdict, 'PROBE OK', `${verdict} — ${evidence}`);
});

test('production, aborted: the older gate probe still proves expiry under the new window', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  let verdict, evidence;
  try { await replaySql(pendingText() + '\n;\n' + R(GATE_PROBE), { retry: false, label: `${NAME} older probe` }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)\|(.*?)>>/s);
    assert.ok(m, 'the older probe failed before it could report: ' + String(e.message).slice(0, 800));
    [verdict, evidence] = [m[1], m[2]];
  }
  assert.equal(verdict, 'PROBE OK', `${verdict} — ${evidence}`);
});
