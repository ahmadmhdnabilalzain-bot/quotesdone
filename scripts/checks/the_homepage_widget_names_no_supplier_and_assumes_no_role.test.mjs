// Founder ruling 1249 (18 Oct 2026). Seat: customer_support. The homepage widget recommended a supplier
// ("aluminium windows in Dubai") and told a visitor they were a supplier ("who told you i am a supplier?").
// This pins the prompt rules and the message limit that answer that; the scored replies are
// widget_no_supplier_named / widget_no_role_assumed in scripts/eval/support_reply_suite.mjs (EN + AR).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const src = readFileSync(new URL('../../supabase/functions/site_assistant/index.ts', import.meta.url), 'utf8');
test('the widget never names a supplier and points to sign-up', () => {
  assert.match(src, /Never recommend, name or rank any supplier/);
  assert.match(src, /founder ruling 1249/);
  assert.match(src, /sign up free at quotesdone\.com\/me/);
  assert.match(src, /Never collect or ask for job details/);
});
test('the widget assumes no role', () => {
  assert.match(src, /Never assume, state or hint at their role/);
  assert.doesNotMatch(src, /Read from their words whether they buy/);
});
test('a visitor conversation has a limited number of messages', () => {
  const m = src.match(/site_assistant_conv_hour: (\d+),/);
  assert.ok(m && Number(m[1]) <= 15, 'conversation cap ' + (m && m[1]));
});
