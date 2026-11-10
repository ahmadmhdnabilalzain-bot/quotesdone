// deno test supabase/functions/send_whatsapp/confirmations.test.ts
// 3 Nov 2026 (customer_support): the confirmations the founder asked for go on WhatsApp as well as email.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { functionSource } from './test_source.ts';
import { CONFIRMATION_TYPES, invoiceAttachment, isConfirmation } from './confirmations.ts';

const REF = { bucket: 'agent-docs', path: 'reveal_invoice/0b9b1c7e/1730000000000_invoice-ZZDEMO-0001-en-t2.pdf', filename: 'QuotesDone-invoice-ZZDEMO-0001.pdf' };

Deno.test('the confirmation types, and nothing else, are confirmations', () => {
  assertEquals([...CONFIRMATION_TYPES].sort(), ['customer_account_active', 'invoice_ready', 'reveal_receipt', 'supplier_approved']);
  for (const t of ['supplier_invite_wa', 'new_quote', 'registration_received', 'founder_alert', '', null]) assert(!isConfirmation(t), String(t));
});

Deno.test('the invoice is read only from the row\'s attachments, as a QuotesDone invoice in agent-docs', () => {
  assertEquals(invoiceAttachment([REF]), { bucket: REF.bucket, path: REF.path });
});

Deno.test('KNOWN-BAD control: another bucket, another folder, a traversal, a non-PDF or a body is never "your invoice"', () => {
  assertEquals(invoiceAttachment([{ ...REF, bucket: 'finance-docs' }]), null);
  assertEquals(invoiceAttachment([{ ...REF, path: 'invoices/zz/stripe.pdf' }]), null);
  assertEquals(invoiceAttachment([{ ...REF, path: 'reveal_invoice/../finance/x.pdf' }]), null);
  assertEquals(invoiceAttachment([{ ...REF, path: 'reveal_invoice/0b9b1c7e/x.html' }]), null);
  assertEquals(invoiceAttachment('Your invoice: https://evil.example.invalid/storage/v1/object/sign/x'), null);
  assertEquals(invoiceAttachment(null), null);
});

Deno.test('send_whatsapp maps each confirmation to a template and exempts only them from the per-recipient cap', () => {
  const src = functionSource();
  assertMatch(src, /if\(t==='customer_account_active'\) return 'customer_account_active';/);
  assertMatch(src, /if\(t==='invoice_ready'\) return 'customer_reveal_invoice';/);
  assertMatch(src, /if\(t==='registration_received'\) return 'supplier_account_notice';/);
  assertMatch(src, /if\(t==='supplier_approved'\) return 'supplier_account_notice';/);
  assertMatch(src, /'reveal_receipt'[^\n]*return 'customer_supplier_unlocked';/);
  // the link is signed from the row's attachment as it leaves, never parsed out of the body
  assertMatch(src, /const inv = key === 'customer_reveal_invoice' \? invoiceAttachment\(n\.attachments\) : null;/);
  assertMatch(src, /createSignedUrl\(inv\.path, INVOICE_LINK_TTL\)/);
  assertMatch(src, /key==='customer_reveal_invoice'\) return \{'1': shortSummary\(n\.subject\|\|''\), '2': n\.invoice_url \|\| linkFor\(key\)\}/);
  assert(!/invoiceLink\(/.test(src), 'no link may be read out of a body');
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
