// A SUPPLIER'S REPLY NAMES CONFIRMING THE SERVICES AND IS SIGNED (sales_engineer, 2 Nov 2026, founder ledger 1469).
// Prevented by this file: a reply that lists what a supplier needs without the services step (a company with all six is still held until it
// confirms them), and a reply that ends with no QuotesDone sign-off (fn_inbox_send adds none).
//   node --test scripts/checks/a_supplier_reply_names_confirming_services_and_is_signed.test.mjs
// Two halves:
//   1. OFFLINE (always runs): the three answer texts are read out of the SQL file and judged by one predicate. KNOWN-BAD CONTROLS: the real text
//      that went out on 2 Nov and the body of a_supplier_reply_gets_the_action_it_asked_for.sql both FAIL the same predicate.
//   2. PRODUCTION, one aborted transaction (needs a Supabase management token): the definition and the probe are replayed through safe_replay.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const NEW = 'scripts/sql/a_supplier_reply_names_confirming_services_and_is_signed.sql';
const PROBE = 'scripts/sql/a_supplier_reply_names_confirming_services_and_is_signed_probe.sql';
const OLD = 'scripts/sql/a_supplier_reply_gets_the_action_it_asked_for.sql';
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SIGN = '\n\nKind regards,\nThe QuotesDone Team';

// every E'...' literal piece of a branch of fn_supplier_reply_answer joined around the link (p_link becomes <LINK>), unescaped
function branch(sql, when) {
  const start = sql.indexOf(`when '${when}' then`);
  const stop = [`when 'later' then`, `when 'subsidiary' then`, 'else', 'end)', 'end\n$fn$'].map((k) => sql.indexOf(k, start + 10)).filter((i) => i > 0).sort((a, b) => a - b)[0];
  const seg = sql.slice(start, stop);
  const parts = [...seg.matchAll(/E'((?:[^']|'')*)'|p_link/g)].map((m) => (m[0] === 'p_link' ? '<LINK>' : m[1]));
  return parts.join('').replace(/''/g, "'").replace(/\\n/g, '\n');
}
function elseBranch(sql) {
  const start = sql.indexOf('    else\n', sql.indexOf('fn_supplier_reply_answer'));
  const seg = sql.slice(start, sql.indexOf('    end', start));
  const parts = [...seg.matchAll(/E'((?:[^']|'')*)'|p_link/g)].map((m) => (m[0] === 'p_link' ? '<LINK>' : m[1]));
  return parts.join('').replace(/''/g, "'").replace(/\\n/g, '\n');
}

// the predicate: English only, the link, and when it lists requirements the services step with the hold; signed once the routine appends it
const problems = (t, { lists }) => {
  const p = [];
  if (/[؀-ۿ]/.test(t)) p.push('not English');
  if (!t.includes('<LINK>')) p.push('no link');
  if (lists && !/confirms? the services[^.]*Services tab[^.]*held until/.test(t)) p.push('no services step');
  return p;
};

test('known-bad control: the subsidiary text that went out on 2 Nov lists the six and stops', () => {
  const sent = 'Thank you for your message.\n\nA separately licensed company registers on its own, with its own trade licence and a different e-mail address: one e-mail address manages one company.\n\nTo register it, open <LINK> , choose "Create account" and use that company\'s work e-mail. It needs its licensed name, a UAE mobile number verified with a code, the verified work e-mail, the trade licence, the company profile and acceptance of the supplier terms.\n\nAnything you have already started for your first company stays as it is. We will check in with you in a week.';
  assert.deepEqual(problems(sent, { lists: true }), ['no services step']);
});

test('known-bad control: the body live before this change (a_supplier_reply_gets_the_action_it_asked_for.sql) fails for both listing answers', () => {
  const old = read(OLD);
  const sub = branch(old, 'subsidiary'), ent = elseBranch(old);
  assert.ok(sub.includes('<LINK>') && ent.includes('<LINK>'), 'the reader found the old branches');
  assert.deepEqual(problems(sub, { lists: true }), ['no services step']);
  assert.deepEqual(problems(ent, { lists: true }), ['no services step']);
  assert.ok(!old.includes('Kind regards'), 'the old body has no sign-off');
});

test('the new body: subsidiary and interested name confirming the services and the hold; later is untouched; all three are signed', () => {
  const sql = read(NEW);
  const sub = branch(sql, 'subsidiary'), later = branch(sql, 'later'), ent = elseBranch(sql);
  assert.deepEqual(problems(sub, { lists: true }), []);
  assert.deepEqual(problems(ent, { lists: true }), []);
  assert.deepEqual(problems(later, { lists: false }), []);
  assert.match(sub, /different e-mail address: one e-mail address manages one company/, 'the separate-company rule is kept');
  assert.match(ent, /Only you can verify, accept and confirm these, so we cannot do it for you/, 'it still never offers to do a step for them');
  assert.ok(sql.includes("end) || E'\\n\\nKind regards,\\nThe QuotesDone Team'"), 'one sign-off after the case, on every answer');
  assert.equal(SIGN.trim().split('\n')[1], 'The QuotesDone Team');
  // the sign-off is the one composeMailReply uses
  assert.match(read('supabase/functions/_shared/customer_mail.ts'), /Kind regards,\\nThe QuotesDone Team/);
});

test('the file is a seated, restated-ACL replacement, the probe says PROBE OK or PROBE FAILED, and the MANIFEST lists the file once, not the probe', () => {
  const sql = read(NEW);
  assert.match(sql, /^-- .*\n-- Seat: sales_engineer\./m);
  assert.match(sql, /revoke execute on function public\.fn_supplier_reply_answer\(text, text\) from public, anon, authenticated;/);
  const probe = read(PROBE);
  assert.match(probe, /PROBE OK/); assert.match(probe, /PROBE FAILED/);
  const manifest = read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim());
  assert.equal(manifest.filter((l) => l === NEW).length, 1);
  assert.equal(manifest.filter((l) => l === PROBE).length, 0);
});

test('production, rolled back: the three answers are signed, name the services and the known-bad texts fail',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { replaySql } = await import('../lib/safe_replay.mjs');
  let msg = '';
  try { await replaySql(read(NEW) + '\n' + read(PROBE), { retry: false }); } catch (e) { msg = String(e?.body ?? e?.message ?? e); }
  assert.ok(msg.includes('PROBE OK') && !msg.includes('PROBE FAILED'), msg.slice(0, 800));
});
