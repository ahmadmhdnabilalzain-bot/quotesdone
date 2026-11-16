// A MEMBER ASKS TO TAKE OVER THE COMPANY: ONLY THE OWNER'S NOTICE RIDES A TEMPLATE (REVIEW2 W3PEOPLE, 16 Nov 2026).
// fn_wa_fanout twins every supplier e-mail of a company to the company's ONE confirmed number (fn_whatsapp_destination reads
// leads.whatsapp_phone by lead_id, never by the addressee), and that number is the owner's. So the owner's notice
// (scripts/sql/a_company_whose_owner_left_gets_a_new_owner_the_sales_engineer_decides.sql: at the claim, and again when a transfer
// is approved) is mapped to the approved supplier_account_notice template, and every notice written to the MEMBER stays unmapped:
// send_whatsapp marks its twin skipped, so the member's own correspondence never reaches the owner's phone.
//   deno test supabase/functions/send_whatsapp/ownership_claim_owner_notice_template.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { linkFor, tmplKey, varsFor } from './templates.ts';

Deno.test('the owner\'s claim notice rides supplier_account_notice: its subject and the portal, where "Keep ownership" is', () => {
  assertEquals(tmplKey('supplier_ownership_claim_owner_notice'), 'supplier_account_notice');
  const v = varsFor('supplier_account_notice', { subject: 'A member asks to take over ZZ DEMO Co on QuotesDone', body: 'ZZ DEMO M (zz-demo-m@example.invalid) tells us that you have left.' });
  assertEquals(v, { '1': 'A member asks to take over ZZ DEMO Co on QuotesDone', '2': linkFor('supplier_account_notice') });
});

Deno.test('no notice written to the member (or to the former owner after the hand-over) has a template', () => {
  for (const t of ['supplier_ownership_claim_received', 'supplier_ownership_claim_approved', 'supplier_ownership_claim_question',
                   'supplier_ownership_claim_refused', 'supplier_ownership_claim_kept', 'supplier_ownership_claim_done']) {
    assertEquals(tmplKey(t), null, t);
  }
});
