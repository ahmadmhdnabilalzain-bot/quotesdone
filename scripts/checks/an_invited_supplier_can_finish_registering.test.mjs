// AN INVITED SUPPLIER CAN FINISH REGISTERING (21 Sep 2026, sales_engineer) — the campaign registration
// walk found two defects on the path every campaign email leads to, and this is what fails if either
// cause comes back. The behaviour itself is walked by scripts/e2e/supplier_registration_walk.mjs.
//
// 1. THE CLAIM RACE. The dashboard mounted in the same tick the invitation claim was sent (the claim
//    takes up to ~5.8 s, measured on production), answered no_company, and showed the supplier who had
//    just been told "this listing is reserved for your company" an empty "Register your company" form.
// 2. THE WHATSAPP DEAD END. An invited supplier claims a listing that already exists, so Onboarding
//    never runs and registration is finished on the Profile tab (ProfileForm mode="edit"). save()
//    demands the WhatsApp answer from every supplier not yet approved, and the question rendered only
//    when !isEdit: "Still needed to register: Your answer on your WhatsApp number" with nothing to answer.
//
// It reads source only (no network, no secret), so it runs in the checks job.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SRC = readFileSync(new URL('../../src/components/portal/SupplierPortal.tsx', import.meta.url), 'utf8');
const code = SRC.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, ' ');   // a comment naming the old shape must not satisfy the check

test('the dashboard is not mounted while the invitation claim is in flight', () => {
  assert.match(code, /phase === 'app' && \(claiming\s*\?/, 'the Dashboard must be gated on `claiming`');
  assert.match(code, /setClaiming\(true\)/, 'claimIfInvited must raise `claiming` before it calls claim');
  assert.match(code, /drop\(\);\s*warmSupplier\(access\)/, 'the dashboard warmed before the claim must be discarded and re-warmed');
  assert.match(code, /if \(claimRun\.current\) return claimRun\.current/, 'the claim is sent once per page, not once per mount path');
});

test('the WhatsApp question shows whenever save() will demand it', () => {
  const guard = code.match(/if \(me\.approval_status !== 'approved'\) \{[\s\S]*?reg_whatsapp/);
  assert.ok(guard, 'save() no longer requires reg_whatsapp for an unapproved supplier — update this check with it');
  assert.match(code, /\{me\.approval_status !== 'approved' && phoneVerified && !waSignupSettled\(wa\) && <div/, 'the question must render on the same condition save() demands it');
  assert.doesNotMatch(code, /\{!isEdit && phoneVerified && !waSignupSettled\(wa\)/, 'the edit-mode dead end is back');
});

test('a supplier whose first certificate failed can still finish (reg_terms asks for the certificate)', () => {
  // 3. Measured 21 Sep 2026: compliance_archive timed out once under load, and every later save answered
  //    missing_required [reg_terms] and returned before the kyc call that issues the certificate.
  const save = code.slice(code.indexOf('const save = async () =>'));
  const heal = save.search(/includes\('reg_terms'\)\)\s*\{\s*const \w+ = await call\('kyc', \{ action: 'accept_terms' \}/);
  const bail = save.search(/if \(!\(j && j\.ok\)\) \{ setBusy\(false\); setMsg\(srvMsg\(lang, j, t\(lang, 'could_not_save'\)\)\); return; \}/);
  assert.ok(heal > 0, 'save() must request the certificate when save_profile says reg_terms is what is missing');
  assert.ok(bail > heal, 'the certificate must be requested BEFORE save() gives up on a missing_required answer');
});

test('a supplier who owes nothing does not trigger the whole-book interest recompute on Billing', () => {
  const pay = readFileSync(new URL('../../supabase/functions/supplier_pay/index.ts', import.meta.url), 'utf8')
    .replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, ' ');
  const call = pay.indexOf("admin.rpc('fn_supplier_dues_accrue_interest'");
  assert.ok(call > 0, 'the accrual call moved — update this check with it');
  assert.match(pay.slice(Math.max(0, call - 120), call), /if \(openDues !== 0\)/, 'the accrual must be gated on this supplier having open dues');
});

test('the establishment card is not called a green-building certificate', () => {
  assert.doesNotMatch(SRC, /Emirates Green Building|المباني الخضراء/);
});
