// THE UNANSWERED-REQUESTS WARNING AND THE STOP REACH WHATSAPP (sales_engineer, 16 Nov 2026; agent W3_PEOPLE; wave-3 item 6).
// fn_supplier_strike_notice writes the warning (one short of the stop) and the stop as e-mail; fn_wa_fanout queues the WhatsApp
// twin to a confirmed number, and fn_supplier_strike_warning_redeliver (scripts/sql/an_undelivered_strike_warning_is_sent_again_
// another_way.sql) queues a WhatsApp copy when the e-mail bounced. With no template mapped, neither could ever be sent outside
// the 24-hour window. They ride the approved supplier_account_notice template: its subject and the portal, nothing else.
//   deno test supabase/functions/send_whatsapp/strike_notice_template.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { linkFor, tmplKey, varsFor } from './templates.ts';

Deno.test('the strike warning and the stop ride the supplier_account_notice template', () => {
  assertEquals(tmplKey('supplier_strike_warning'), 'supplier_account_notice');
  assertEquals(tmplKey('supplier_strike_stopped'), 'supplier_account_notice');
});

Deno.test('the WhatsApp copy says its subject and points to the portal, where "Not for me" and "I\'m available" are', () => {
  const v = varsFor('supplier_account_notice', { subject: 'Please answer your QuotesDone job requests', body: 'You did not answer 2 job requests (RFQ-1, RFQ-2).' });
  assertEquals(v, { '1': 'Please answer your QuotesDone job requests', '2': linkFor('supplier_account_notice') });
});
