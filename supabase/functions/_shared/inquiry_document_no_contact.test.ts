// inquiry_document_no_contact.test.ts — the request (BOQ) PDF a matched supplier downloads carries no contact detail
// of any shape, QuotesDone's own included (3 Nov 2026, sales_engineer).
// deno test --no-lock -A supabase/functions/_shared/inquiry_document_no_contact.test.ts
//
// THE FAILURE IT REPLAYS: nightly journey run 41598217377, drawings step (scripts/e2e/drawing_reaches_suppliers.mjs):
// "FAIL no contact detail of any shape in the English BOQ PDF — management@quotesdone.com | +971 56 791 8605", and the
// same for the Arabic PDF. The footer printed our mailbox and both numbers on a document whose reader is a supplier;
// supplier questions go through the portal (doc_template.SUPPLIER_ASK). The same three contact shapes the journey
// searches for are searched here, on the real renderer's output, in both languages.
import { assert } from 'jsr:@std/assert@1';
import { inquiryDocument } from './quote_documents.ts';
import { FALLBACK, SUPPLIER_ASK } from './doc_template.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { pdfPages } from './pdf_text_positions.ts';
import * as F from './quote_documents.fixture.ts';

const CONTACT_RE = [/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i, /\+?971[\s-]?\d{1,2}[\s-]?\d{3}[\s-]?\d{4}/, /\(\d{3}\)\s?\d{3}-\d{4}/];
for (const lang of ['en', 'ar'] as const) {
  Deno.test(`the ${lang} request PDF a supplier receives prints no e-mail and no phone, and says where questions go`, async () => {
    const { body } = F.reasoned((arTexts) => inquiryDocument({ inquiry: F.REQUEST, lang, portalUrl: 'https://quotesdone.com/supplier', ...(lang === 'ar' ? { date_ar: '3 نوفمبر 2026' } : { date: '3 November 2026' }), arTexts }));
    const out = await renderPdf(body, { fetchBytes: async () => null });
    assert(out.ok, 'rendered');
    const text = (await pdfPages(out.bytes)).flatMap((p) => p.runs.map((r) => r.text)).join(' ');
    const hits = CONTACT_RE.flatMap((re) => text.match(new RegExp(re.source, 'gi')) || []);
    assert(!hits.length, `contact shapes on the supplier's PDF: ${hits.join(' | ')}`);
    for (const c of [FALLBACK.email, FALLBACK.callPhone, FALLBACK.phone]) assert(!text.includes(c), c);
    // The legal line stays: who issues it and under which licence.
    assert(text.includes('1633275'), 'licence number printed');
    if (lang === 'en') assert(text.replace(/\s+/g, ' ').includes(SUPPLIER_ASK.en), 'portal pointer printed');
  });
}
