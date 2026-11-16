// A COMPANY BUYER IS BILLED AS HIS COMPANY (sales_engineer and accountant, CUSTOMER_W2, 16 Nov 2026; holes/CUSTOMER.md item 9).
// Before: the reveal invoice and receipt printed "Billed to: name · email · phone", with no company, TRN or PO, so a facility
// manager's buyer could not file it. FAILS IF: the company, its TRN or his PO stop being printed; the person stops being the
// contact; a company added after the reveal is served from the old stored document (same name); the invoice reads no company.
import { assert, assertEquals, assertMatch, assertNotEquals } from 'jsr:@std/assert@1';
import { billToTag, revealInvoiceDocument, revealReceiptDocument, type RevealSale } from '../_shared/reveal_fee_documents.ts';

const SALE: RevealSale = {
  tx_id: 'tx-1', invoice_no: 'ZZDEMO-0001', paid_at: '2026-09-21T09:33:20Z', reveal_fee: 777.6, processing_fee: 38.77, total_charged: 816.37,
  quote_amount: 25920, payment_ref: 'pi_zzdemo', customer: { name: 'ZZ DEMO Buyer', email: 'zz.demo.buyer@example.invalid', phone: null },
  request: { summary: 'ZZ DEMO gypsum ceilings', category: 'gypsum', ref: 'QD-ZZDEMO01' }, card: { brand: 'visa', last4: '4242' }, refund: null,
};
const BILL = { company: 'ZZ DEMO Facilities Management LLC', trn: '100123456789003', po_ref: 'PO-7781' };

Deno.test('the invoice and the receipt are made out to the company, with its TRN, his PO and the person as the contact', () => {
  for (const lang of ['en', 'ar'] as const) for (const make of [revealInvoiceDocument, revealReceiptDocument]) {
    const doc = JSON.stringify(make({ ...SALE, bill_to: BILL }, lang));
    assert(doc.includes(BILL.company) && doc.includes(BILL.trn) && doc.includes(BILL.po_ref), lang);
    assert(doc.includes('ZZ DEMO Buyer · zz.demo.buyer@example.invalid'), 'the person is the contact');
  }
  assertMatch(JSON.stringify(revealInvoiceDocument({ ...SALE, bill_to: BILL }, 'en')), /"Customer TRN","100123456789003"/);
});

Deno.test('without a company nothing changes: billed to the person, the same document name', () => {
  const plain = revealInvoiceDocument(SALE, 'en');
  assertEquals(revealInvoiceDocument({ ...SALE, bill_to: null }, 'en').name, plain.name);
  assert(!JSON.stringify(plain).includes('Customer TRN'));
  assertEquals(billToTag(null), '');
});

Deno.test('a company added or changed is a new document, never the stored one', () => {
  const a = revealInvoiceDocument({ ...SALE, bill_to: BILL }, 'en').name;
  const b = revealInvoiceDocument({ ...SALE, bill_to: { ...BILL, po_ref: 'PO-7790' } }, 'en').name;
  assertNotEquals(a, revealInvoiceDocument(SALE, 'en').name);
  assertNotEquals(a, b);
});

Deno.test('the invoice reads the company the customer saved, and the reveal door saves it through the one writer', async () => {
  const inv = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assertMatch(inv, /from\('reveal_bill_to'\)\.select\('company,trn,po_ref'\)\.eq\('quote_id', tx\.quote_id\)/);
  assertMatch(inv, /bill_to: bt\?\.company \? \{ company: String\(bt\.company\)/);
  const rv = await Deno.readTextFile(new URL('../customer_api/actions/reveal.ts', import.meta.url));
  assertMatch(rv, /if \(action === 'reveal_bill_to'\) \{/);
  assertMatch(rv, /admin\.rpc\('fn_reveal_bill_to_record', \{ p_customer: cust\.id, p_quote: qid,/);
});
