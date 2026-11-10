// every_admin_door_requires_a_two_step_session.test.mjs
// node --test scripts/checks/every_admin_door_requires_a_two_step_session.test.mjs
//
// Security checklist audit 10 Nov 2026, open item 1 (it_engineer). Measured that day: ten edge functions turned a JWT
// into admin power by asking one question — is the account's e-mail in app_secrets.admin_emails — so whoever read
// the founder's mailbox was the admin of refunds_api and nine others. They now go through ONE door,
// supabase/functions/_shared/admin_session.ts, which also requires the session's `aal` claim to be 'aal2' (a TOTP
// authenticator-app code was passed) and answers an aal1 admin 403 `two_step_required` naming the step.
//
// This check fails if:
//   1. any runtime file in supabase/functions reads admin_emails outside the door, unless it is registered below as
//      an ADDRESS LIST (a recipient or a sender allow-list, never a caller's identity) with the exact number of reads;
//   2. a registered address-list file reads admin_emails more often than registered (a new read must be looked at), or
//      no longer reads it at all (the register must not point at nothing);
//   3. one of the ten admin doors stops importing the door, stops calling adminCaller, stops answering
//      two_step_required, or loses its two_step.test.ts (the test that drives its real handler);
//   4. the door stops requiring aal2, or the test harness is imported by a runtime file;
//   5. anything in src/ or supabase/functions enrols a phone factor (phone MFA is a paid Supabase add-on; the founder
//      ruled 10 Nov 2026, ledger 1606, that nothing that costs money is added). The authenticator app is free.
// Comments are stripped before matching, so the prose that explains a read never counts as one.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';

const REPO = join(import.meta.dirname, '..', '..');
const FUNCTIONS = join(REPO, 'supabase', 'functions');
const DOOR = 'supabase/functions/_shared/admin_session.ts';
const HARNESS = 'supabase/functions/_shared/admin_two_step_harness.ts';

// The functions that grant admin power from a JWT, enumerated with `grep -rn admin_emails supabase/functions` on
// 10 Nov 2026 and read one by one. (The audit table also named email_triage and wa_templates_watch: both read
// admin_emails only as a recipient list and accept no JWT; they are in ADDRESS_LISTS. It did not name ceo_agent,
// marketing or sales_engineer, which did grant founder power from a JWT.)
const ADMIN_DOORS = ['accountant', 'ceo_agent', 'compliance_archive', 'extract_text', 'it_engineer', 'marketing',
  'pdf_native', 'quote_compare', 'refunds_api', 'sales_engineer'];

// Files that read admin_emails as an ADDRESS, never to decide who the caller is. reads = quoted reads in code.
const ADDRESS_LISTS = {
  'supabase/functions/login_otp/index.ts': { reads: 1, why: 'resolveAdminEmailByPhone: the FIRST factor (SMS to admin_mfa_phone) names the account to sign in; the session it mints is aal1, which no admin door accepts' },
  'supabase/functions/email_triage/index.ts': { reads: 1, why: "the founder's own addresses, so triage never answers him as a customer; the function accepts only the internal credential" },
  'supabase/functions/wa_templates_watch/index.ts': { reads: 1, why: 'the recipient of the template-approval notice; internal credential only' },
  'supabase/functions/resend_inbound/steps/read_mail.ts': { reads: 1, why: 'the SENDER allow-list for forwarded expense mail (the From header of an inbound e-mail), not a JWT' },
  'supabase/functions/accountant/actions/expenses.ts': { reads: 1, why: "expense_sweep reuses resend_inbound's sender allow-list over the mailbox history; the caller was already admitted by accountant's whoami, through the door" },
  'supabase/functions/supplier_api/actions/profile.ts': { reads: 1, why: "the management address a supplier's first-submission notice is sent to" },
};

const NOT_RUNTIME = (name) => /\.(test|check)\.ts$/.test(name) || name === 'fixtures' || name.startsWith('test_') || name.startsWith('_test') || name === 'vendor';
function runtimeFiles(dir = FUNCTIONS) {
  const out = [];
  for (const name of readdirSync(dir).sort()) {
    if (NOT_RUNTIME(name)) continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...runtimeFiles(p));
    else if (/\.(ts|tsx|mjs|js)$/.test(name)) out.push(relative(REPO, p).split('\\').join('/'));
  }
  return out;
}

// A `//` starts a comment only when every quote before it on the line is closed (so 'https://…' is not a comment).
const stripComments = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').split('\n').map((l) => {
  for (let i = l.indexOf('//'); i >= 0; i = l.indexOf('//', i + 2)) {
    const before = l.slice(0, i);
    if ([`'`, '"', '`'].every((q) => (before.split(q).length - 1) % 2 === 0)) return before;
  }
  return l;
}).join('\n');
const code = (rel) => stripComments(readFileSync(join(REPO, rel), 'utf8'));
const READ = /['"`]admin_emails['"`]/g;
const reads = (rel) => (code(rel).match(READ) || []).length;

const FILES = runtimeFiles();

test('the walk found the functions and the door', () => {
  assert.ok(FILES.length > 300, `walked ${FILES.length} runtime files`);
  assert.ok(FILES.includes(DOOR), `${DOOR} is missing`);
});

test('no runtime file reads admin_emails outside the door unless it is a registered address list', () => {
  const stray = FILES.filter((f) => f !== DOOR && !ADDRESS_LISTS[f] && reads(f) > 0);
  assert.deepEqual(stray, [], `these read admin_emails without _shared/admin_session.ts — a JWT must become an admin only through adminCaller() (aal2 required): ${stray.join(', ')}`);
});

test('every registered address list still reads admin_emails, and no more often than registered', () => {
  for (const [f, { reads: n, why }] of Object.entries(ADDRESS_LISTS)) {
    assert.ok(existsSync(join(REPO, f)), `${f} is registered but does not exist`);
    assert.ok(why.length > 20, `${f} needs a reason`);
    const got = reads(f);
    assert.ok(got > 0, `${f} no longer reads admin_emails: remove it from ADDRESS_LISTS`);
    assert.ok(got <= n, `${f} reads admin_emails ${got} times, registered ${n}: a new read decides something — route it through adminCaller() if it is about the caller, or register it with its reason`);
  }
});

test('each of the ten admin doors goes through adminCaller, answers two_step_required, and has its handler test', () => {
  for (const fn of ADMIN_DOORS) {
    const files = FILES.filter((f) => f.startsWith(`supabase/functions/${fn}/`));
    assert.ok(files.length, `${fn} has no runtime files`);
    const src = files.map(code).join('\n');
    assert.match(src, /from\s+['"](?:\.\.\/)+_shared\/admin_session\.ts['"]/, `${fn} must import _shared/admin_session.ts`);
    assert.match(src, /\badminCaller\(/, `${fn} must call adminCaller()`);
    assert.match(src, /two_step_required/, `${fn} must answer an aal1 admin with two_step_required`);
    assert.doesNotMatch(src, /\.auth\.getUser\(/, `${fn} resolves a JWT itself; the door (via signedInUser) does that`);
    assert.ok(existsSync(join(FUNCTIONS, fn, 'two_step.test.ts')), `${fn}/two_step.test.ts (aal1 admin 403, aal2 admin allowed, non-admin unchanged) is missing`);
  }
});

test('the door requires aal2, and the test harness is never imported by a runtime file', () => {
  const door = code(DOOR);
  assert.match(door, /claims\.aal !== 'aal2'/, 'adminCaller must refuse any session whose aal claim is not aal2');
  assert.match(door, /signedInUser\(/, 'adminCaller must resolve the user through signedInUser (bounded, local refusal first)');
  const importers = FILES.filter((f) => f !== HARNESS && /admin_two_step_harness/.test(code(f)));
  assert.deepEqual(importers, [], 'the harness stubs fetch and Deno.serve: tests only');
});

test('nothing enrols a phone factor (paid add-on): the authenticator app is the only second factor', () => {
  const roots = [join(REPO, 'src'), FUNCTIONS];
  const walk = (dir) => readdirSync(dir).flatMap((n) => { const p = join(dir, n); return statSync(p).isDirectory() ? (n === 'node_modules' ? [] : walk(p)) : /\.(ts|tsx|mjs|js)$/.test(n) ? [p] : []; });
  const hits = roots.flatMap(walk).filter((p) => /factorType\s*:\s*['"`]phone['"`]/.test(stripComments(readFileSync(p, 'utf8'))));
  assert.deepEqual(hits.map((p) => relative(REPO, p)), []);
});
