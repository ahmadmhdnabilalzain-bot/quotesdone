// node --test src/components/portal/supplier/revealedContact.test.mjs
// Walk of 12 Nov 2026, S8 (sales_engineer, built by it_engineer): after a reveal the customer's phone and e-mail, the two things the
// supplier paid for, were 21 px tall tap targets at 390 and 360 px (Projects.tsx). This fails if either link drops below 44 px.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('./core/Projects.tsx', import.meta.url), 'utf8');

test('the revealed phone and e-mail are 44 px tall to a finger', () => {
  for (const k of ["href={'tel:'", "href={'mailto:'"]) {
    const a = new RegExp('<a className="([^"]*)" ' + k.replace(/[{}()'.:]/g, '\\$&')).exec(src);
    assert.ok(a, k + ' link not found');
    assert.match(a[1], /\binline-flex\b/, k); assert.match(a[1], /\bmin-h-11\b/, k);
  }
});
