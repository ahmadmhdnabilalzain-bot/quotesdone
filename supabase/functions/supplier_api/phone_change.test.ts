// Finding H1 (9 Nov 2026): a supplier could replace a verified mobile and keep the verified flag.
// Prevented by this file: the rule itself, and that save_profile applies it.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { phoneChanged } from './lib/phone_change.ts';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

Deno.test('a different number is a change; formatting alone is not', () => {
  assertEquals(phoneChanged('+971 50 123 4567', '+971501234567'), false);
  assertEquals(phoneChanged('+971-50-123-4567', '971501234567'), false);
  assertEquals(phoneChanged('+971501234567', '+971559999999'), true);
  assertEquals(phoneChanged(null, '+971501234567'), true);
  assertEquals(phoneChanged('+971501234567', ''), true);
  assertEquals(phoneChanged('+971501234567', undefined), false, 'no phone in the request is no change');
});

Deno.test('save_profile clears owner_phone_verified when the phone changes', () => {
  const src = functionSource('supplier_api');
  const start = src.indexOf("if (action === 'save_profile')");
  assert(start >= 0, 'save_profile handler not found');
  const body = src.slice(start, start + 4000);
  assert(/select\('[^']*\bphone\b[^']*'\)/.test(body.slice(0, 600)), 'save_profile must read the phone on file to compare');
  assert(/phoneChanged\(sup\.phone,\s*upd\.phone\)\)\s*upd\.owner_phone_verified\s*=\s*false/.test(body), 'save_profile must clear owner_phone_verified when phoneChanged(sup.phone, upd.phone)');
});
