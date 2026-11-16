// deno test --no-lock --node-modules-dir=none supabase/functions/wa_inbound/member_phone.test.ts
//
// A COMPANY MEMBER CONFIRMS HIS WHATSAPP NUMBER WITH THE CODE FROM HIS PORTAL (16 Nov 2026, SUPPLIER hole 4; agent SUPPLIER_W2).
// Before: WhatsApp knew one owner number per company. Only a six-digit code in a short message is a code; a conversation is not.
import { assertEquals } from 'jsr:@std/assert@1';
Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
const { codeIn } = await import('./member_phone.ts');

Deno.test('the code is six digits in a short message, Arabic-Indic digits included; anything longer is a conversation', () => {
  assertEquals(codeIn('482913'), '482913');
  assertEquals(codeIn('my code is 482913'), '482913');
  assertEquals(codeIn('الرمز ٤٨٢٩١٣'), '482913');
  assertEquals(codeIn('call me on 0501234567'), null, 'a phone number is not a code');
  assertEquals(codeIn('12345'), null);
  assertEquals(codeIn('We need a quotation for 482913 square feet of tiling in the new tower near the marina please'), null);
});

Deno.test('the step runs only for a number we do not know and answers through the model (no fixed sentence is sent)', async () => {
  const src = await Deno.readTextFile(new URL('./member_phone.ts', import.meta.url));
  assertEquals(/if \(audience !== 'unknown'\) return undefined;/.test(src), true);
  assertEquals(/const out = await sayFor\('supplier'\)\(situation, 'en'\);/.test(src), true);
  const index = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assertEquals(index.indexOf('await identify(t);') < index.indexOf('await memberPhone(t)'), true);
});
