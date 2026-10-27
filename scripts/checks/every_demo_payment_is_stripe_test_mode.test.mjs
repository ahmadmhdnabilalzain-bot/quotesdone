// Every function that opens a Stripe Checkout for a signed-in account picks the key by the account:
// an @example.invalid (demo) account is served only the TEST key, a real one only the LIVE key.
// QA 19 Oct 2026: supplier_pay read stripe_secret_key directly, so a ZZ DEMO supplier's due opened a
// LIVE checkout and the supplier-fee path could never be exercised with a Stripe test card.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const code = (fn) => fs.readFileSync(path.join(ROOT, 'supabase', 'functions', fn, 'index.ts'), 'utf8')
  .split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');

for (const fn of ['stripe_checkout', 'supplier_pay']) {
  test(`${fn} chooses the Stripe key from the signed-in account`, () => {
    const src = code(fn);
    assert.match(src, /stripeKeyNames\(isDemoEmail\(/, `${fn} must derive the key from isDemoEmail`);
    assert.doesNotMatch(src, /secret\(\s*'stripe_secret_key'\s*\)/, `${fn} must not read the live key unconditionally`);
  });
}
