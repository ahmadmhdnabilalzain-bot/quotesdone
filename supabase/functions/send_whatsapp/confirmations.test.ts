// deno test supabase/functions/send_whatsapp/confirmations.test.ts
// 3 Nov 2026 (customer_support): the three confirmations the founder asked for go on WhatsApp as well as email.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { CONFIRMATION_TYPES, invoiceLink, isConfirmation } from './confirmations.ts';

const SIGNED = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/sign/agent-docs/reveal_invoice/zzdemo01/1730000000000_invoice-ZZDEMO-0001-en-t2.pdf?token=eyJhbGciOiJIUzI1NiJ9.zz.demo';

Deno.test('the three confirmation types, and nothing else, are confirmations', () => {
  assertEquals([...CONFIRMATION_TYPES].sort(), ['customer_account_active', 'reveal_receipt', 'supplier_approved']);
  for (const t of ['supplier_invite_wa', 'new_quote', 'registration_received', 'founder_alert', '', null]) assert(!isConfirmation(t), String(t));
});

Deno.test('the invoice link is read only as a signed storage URL', () => {
  assertEquals(invoiceLink('You have unlocked ZZ DEMO.\n\nYour invoice: ' + SIGNED), SIGNED);
  assertEquals(invoiceLink('فاتورتكم: ' + SIGNED + '\n'), SIGNED);
});

Deno.test('KNOWN-BAD control: a portal link, a supplier site or an over-long link is never "your invoice"', () => {
  assertEquals(invoiceLink('Open https://quotesdone.com/me to see it.'), null);
  assertEquals(invoiceLink('See https://zz-demo.example.invalid/storage/v1/object/public/x.pdf'), null);
  assertEquals(invoiceLink('Your invoice: ' + SIGNED + 'x'.repeat(1000)), null);
  assertEquals(invoiceLink(null), null);
});

Deno.test('send_whatsapp maps each confirmation to a template and exempts only them from the per-recipient cap', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assertMatch(src, /if\(t==='customer_account_active'\) return 'customer_account_active';/);
  assertMatch(src, /if\(t==='registration_received'\) return 'supplier_account_notice';/);
  assertMatch(src, /if\(t==='supplier_approved'\) return 'supplier_account_notice';/);
  assertMatch(src, /'reveal_receipt'[^\n]*return 'customer_supplier_unlocked';/);
  // the invoice template only with the link and only once approved
  assertMatch(src, /key === 'customer_supplier_unlocked' && invoiceLink\(n\.body\) && ready && tmpl\.customer_reveal_invoice\?\.\[wlang\]/);
  assertMatch(src, /if \(inv\.status === 'approved'\) key = 'customer_reveal_invoice';/);
  assertMatch(src, /key==='customer_reveal_invoice'\) return \{'1': shortSummary\(n\.subject\|\|''\), '2': invoiceLink\(n\.body\) \|\| linkFor\(key\)\}/);
  assertMatch(src, /if \(!isFounderRow\(n\) && !isConfirmation\(n\.type\)\) \{\n\s+const \{ count: toThisNumber \}/);
  // the daily cap still applies to them
  assertMatch(src, /if \(budget <= 0 && !isFounderRow\(n\)\) \{ capped\+\+; continue; \}/);
});

Deno.test('wa_template_setup can submit both customer templates in English and Arabic, literal-bounded', () => {
  const setup = Deno.readTextFileSync(new URL('../wa_template_setup/index.ts', import.meta.url));
  for (const k of ['customer_account_active', 'customer_reveal_invoice']) {
    const at = setup.indexOf('  ' + k + ': {');
    assert(at > 0, k + ' is not in the catalogue');
    const entry = setup.slice(at, setup.indexOf('  },', at));
    assert(!/english_only/.test(entry), k + ' is written to customers, who are written to in their own language');
    for (const lang of ['en', 'ar']) {
      const body = entry.match(new RegExp('\\n    ' + lang + ": '([^']+)'"))![1];
      assert(body.includes('{{1}}') && body.includes('{{2}}'), k + ' ' + lang + ' must carry both variables');
      // Meta refuses a body that opens or closes with a variable
      assert(!body.startsWith('{{') && !body.endsWith('}}'), k + ' ' + lang + ': ' + body);
    }
  }
});
