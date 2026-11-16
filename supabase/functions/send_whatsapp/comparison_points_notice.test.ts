// The sales engineer's question about a submitted quotation (the comparison's open points) reaches WhatsApp on the
// supplier_account_notice template, as his other notices about the supplier's own quote do, and carries only its subject
// and the portal. scripts/sql/the_comparison_hands_its_open_points_to_the_sales_engineer.sql queues it (COMPARE4).
//   deno test supabase/functions/send_whatsapp/comparison_points_notice.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { linkFor, tmplKey, varsFor } from './templates.ts';

Deno.test('quote_comparison_points rides the supplier_account_notice template, like the hold notice', () => {
  assertEquals(tmplKey('quote_comparison_points'), 'supplier_account_notice');
  assertEquals(tmplKey('quote_comparison_points'), tmplKey('quote_spec_hold'));
});

Deno.test('its variables are the subject and the supplier portal: nothing of the body, nothing of the customer', () => {
  const subject = 'The sales engineer has a question about your quotation for QD-1234 — Joinery in Dubai';
  const v = varsFor('supplier_account_notice', { subject, body: 'Dear Sir or Madam,\n\nThe customer Jane Doe ...' });
  assertEquals(Object.keys(v).sort(), ['1', '2']);
  assertEquals(v['1'], subject.slice(0, 90));
  assertEquals(v['2'], linkFor('supplier_account_notice'));
  assertEquals(v['2'], 'https://quotesdone.com/portal');
});
