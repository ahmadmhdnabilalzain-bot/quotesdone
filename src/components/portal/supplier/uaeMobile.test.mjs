// node --test src/components/portal/supplier/uaeMobile.test.mjs
// Browser perfection walk, 12 Nov 2026 (customer_support), M9: "+971 050 123 4567" and a number typed on an Arabic keyboard
// (٠٥٠١٢٣٤٥٦٧) were refused with only the general hint, so the button did nothing he could see. Fails on main 0b612866e.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { uaeMobile } from './uaeMobile.ts';

test('a UAE mobile written with the trunk 0 after the country code is accepted', () => {
  for (const v of ['+971 050 123 4567', '+9710501234567', '00971 050 123 4567', '971-050-123-4567']) assert.equal(uaeMobile(v), '+971501234567', v);
});

test('a UAE mobile typed in Arabic-Indic or Persian digits is accepted', () => {
  for (const v of ['٠٥٠١٢٣٤٥٦٧', '٠٥٠ ١٢٣ ٤٥٦٧', '+٩٧١ ٥٠ ١٢٣ ٤٥٦٧', '۰۵۰۱۲۳۴۵۶۷', '‎+971 50 123 4567']) assert.equal(uaeMobile(v), '+971501234567', v);
});

test('everything the old rule accepted still is, and everything it refused still is', () => {
  for (const v of ['0501234567', '050 123 4567', '+971 50 123 4567', '00971501234567', '971-50-123-4567', '501234567']) assert.equal(uaeMobile(v), '+971501234567', v);
  for (const v of ['', '0401234567', '+44 7700 900123', '05012345', '050123456789', 'abc', '+971 00 501234567', '+9710401234567']) assert.equal(uaeMobile(v), null, v);
});
