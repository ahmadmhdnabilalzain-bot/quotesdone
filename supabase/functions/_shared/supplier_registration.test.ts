// The mandatory six as the portal shows them — see supplier_registration.ts.
// Run: deno test supabase/functions/_shared/supplier_registration.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { MANDATORY_SIX, mandatorySixMissing, registrationChecklist, sixInWords } from './supplier_registration.ts';

Deno.test('the checklist ticks exactly what the database did not name as missing', () => {
  const items = registrationChecklist(['reg_licence', 'reg_terms']);
  assertEquals(items.map((i) => i.code), MANDATORY_SIX.map((i) => i.code));
  assertEquals(items.filter((i) => !i.done).map((i) => i.code), ['reg_licence', 'reg_terms']);
  assertEquals(items.find((i) => i.code === 'reg_licence')?.fix, 'documents');
});

Deno.test('missing items read in the supplier\'s language', () => {
  assertEquals(sixInWords(['reg_profile', 'reg_terms'], 'en'), 'company profile, the signed supplier terms');
  assertEquals(sixInWords(['reg_profile'], 'ar'), 'الملف التعريفي للشركة');
});

Deno.test('an unreadable answer is an error, never an empty list', async () => {
  const admin = { rpc: () => Promise.resolve({ data: null, error: { message: 'down' } }) };
  let threw = false;
  try { await mandatorySixMissing(admin, 1); } catch (_e) { threw = true; }
  assertEquals(threw, true);
  const ok = { rpc: () => Promise.resolve({ data: ['reg_email'], error: null }) };
  assertEquals(await mandatorySixMissing(ok, 1), ['reg_email']);
});
