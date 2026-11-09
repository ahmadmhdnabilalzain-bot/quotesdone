// THE CODE STEP NAMES THE ADDRESS IT WAS SENT TO (28 Oct 2026, sales_engineer, ledger 1375). The production browser
// walk of an invited supplier (scripts/e2e/supplier_registration_walk.mjs --real-otp, 1366 and 390 px) found:
//
// 1. After "Create my account" the card's subtitle still read "Enter your work email and we'll create your account",
//    and nothing on the screen named the address the code went to. A supplier who mistyped the address could only
//    find out by waiting for a code that would never arrive.
// 2. "Claim my listing" on the invitation card scrolled to the sign-up card but left the focus where it was, so on a
//    phone the supplier still had to find and tap the e-mail box.
//
// It reads source only (no network, no secret), so it runs in the checks job. The behaviour is walked by the e2e.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readSupplierPortal } from '../lib/portal_sources.mjs';

const SRC = readSupplierPortal();
const code = SRC.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, ' ');   // a comment naming the shape must not satisfy the check

test('the code step shows "code sent to <address>" instead of the e-mail step subtitle', () => {
  assert.match(code, /step === 'code' && ident\s*\?\s*t\(lang, 'code_sent_to'\)/, 'the code step must render code_sent_to with the address');
  assert.match(code, /<bdi dir="ltr"[^>]*>\{ident\}<\/bdi>/, 'the address must be shown, left-to-right');
});

// Suppliers are always English (ruling 1008, nothing_a_supplier_reads_can_be_arabic): one English sentence, which t()
// also serves for lang 'ar'.
test('the English dictionary carries the sentence with the {id} slot', () => {
  const lines = SRC.match(/code_sent_to:'[^']*'/g) || [];
  assert.equal(lines.length, 1, 'code_sent_to must exist once, in English');
  for (const l of lines) assert.match(l, /\{id\}/, 'code_sent_to must name the address: ' + l);
});

test('"Claim my listing" and the hero button put the cursor in the e-mail box', () => {
  const starts = code.match(/onStart=\{\(\) => \{[^}]*scrollIntoView[^}]*\}\)?;[^}]*\.focus\(\{ preventScroll: true \}\)/g) || [];
  assert.equal(starts.length, 2, 'both onStart handlers must scroll AND focus the sign-up input');
});

// 3. THE 390 PX OVERFLOW (same walk). A document row holding Attach file + an expiry date + Upload was a shrink-0 flex
//    item with no width bound, so on a phone it kept its one-line width, pushed Upload past the card and made the page
//    scroll sideways. Every upload row in the Documents card is bounded by the card.
test('a document upload row is bounded by its card, so it wraps on a phone', () => {
  const rows = code.match(/<div className="flex gap-2 items-center flex-wrap shrink-0[^"]*">/g) || [];
  assert.ok(rows.length >= 2, 'the Documents upload rows were not found — update this check with them');
  for (const r of rows) assert.match(r, /max-w-full/, 'an upload row can overflow its card on a phone: ' + r);
});
