// scripts/e2e/journey_proof/sample_documents.ts — the documents of a STUBBED journey A, drawn OFFLINE by the platform's
// own builders on invented ZZ DEMO inputs, so the founder can see the dossier's form before any money is spent.
// Seat: customer_support. No network, no database, no model: what a model would have written is a committed test
// fixture of the product (supabase/functions/_shared/quote_documents.fixture.ts), and is said to be so in the dossier.
//
//   deno run --no-lock --node-modules-dir=none --allow-read --allow-write scripts/e2e/journey_proof/sample_documents.ts <dir> <customer.json>
// Writes the PDFs under <dir> and prints what it made (JSON) for sample.mjs.
import { renderPdf } from '../../../supabase/functions/pdf_native/render.ts';
import * as QD from '../../../supabase/functions/_shared/quote_documents.ts';
import * as F from '../../../supabase/functions/_shared/quote_documents.fixture.ts';
import { deterministicCompare, rosterOf } from '../../../supabase/functions/quote_compare/deterministic.ts';
import { portalLink } from '../../../supabase/functions/_shared/site_origins.ts';
import { revealInvoiceDocument, type RevealSale } from '../../../supabase/functions/_shared/reveal_fee_documents.ts';
import { certFields, certificate } from '../../../supabase/functions/compliance_archive/certificate.ts';
import { inboxField } from '../../../supabase/functions/supplier_api/identity_scrub.ts';
import { seedTerms } from '../../../supabase/functions/_shared/anonymise.ts';
import { fetchBytes } from './dossier.ts';
import { revealCharge, stripeCostFor } from '../../../supabase/functions/_shared/reveal_fee.ts';

const [dir, custFile] = Deno.args;
const cust = JSON.parse(await Deno.readTextFile(custFile));
for (const d of ['customer_files', 'shared', 'quotations']) await Deno.mkdir(`${dir}/${d}`, { recursive: true });
const on = { date: '13 November 2026', date_ar: '13 نوفمبر 2026' };
const out: Record<string, unknown> = {};
const draw = async (body: unknown, f: string) => { const r = await renderPdf(body, { fetchBytes }); if (!r.ok) throw new Error(`${f}: ${JSON.stringify(r.body)}`); await Deno.writeFile(`${dir}/${f}`, r.bytes); return { file: f, pages: r.meta.pages, bytes: r.bytes.length, dropped: r.meta.glyphs_dropped }; };

// 1 the signed-terms certificate (compliance_archive's builder)
const rec = { full_name: cust.name, locale: 'en' };
const fields = { ...certFields(rec, 'customer'), company: '', phone: cust.phone, email: cust.email, terms_label: 'Terms of Service — Version 9', accepted_utc: '2026-11-13 06:02:11 UTC', accepted_iso: '2026-11-13T06:02:11Z', ip: '' };
const c = certificate(fields, 'customer', '0'.repeat(64), 'https://quotesdone.ae/terms', 'en');
out.certificate = await draw({ title: c.title, lang: 'en', body_html: c.body_html, options: { letterhead: true } }, 'customer_files/signed_terms_certificate.pdf');

// 3 the inquiry a supplier receives: the product's own request fixture, its summary through the supplier inbox's own scrub
const seeds = seedTerms({ name: cust.name, email: cust.email, phone: cust.phone, project: '', extra: [] });
const summary = inboxField<string>(F.REQUEST.summary, cust.name, seeds, []);
const row = { ...F.REQUEST, summary: summary.boq ?? '' };
out.inquiry = await draw(F.reasoned((ar) => QD.inquiryDocument({ inquiry: row, lang: 'en', portalUrl: 'https://quotesdone.ae/portal', ...on, arTexts: ar })).body, 'shared/inquiry_as_the_supplier_receives_it.pdf');
out.summary_scrub = { in: F.REQUEST.summary, out: summary.boq, withheld: summary.withheld };

// 5 three quotations as the customer sees them (quote_documents' builder, names masked as production masks them)
const live = F.liveQuotes().slice(0, 3);
out.quotes = [];
for (const [i, qt] of live.entries()) {
  const f = `quotations/Supplier ${QD.supplierLabel(i)} - as the customer sees it.pdf`;
  const d = await draw(F.reasoned((ar) => QD.quoteDocument({ quote: qt, inquiry: F.INQUIRY, items: qt.items, letter: QD.supplierLabel(i), lang: 'en', maskNames: F.identities(), requestUrl: portalLink('en', F.INQUIRY.id, qt.id), ...on, arTexts: ar })).body, f);
  (out.quotes as unknown[]).push({ ...d, letter: QD.supplierLabel(i), quote_id: qt.id, amount: qt.quote_amount, supplier: (qt as unknown as { supplier: Record<string, string> }).supplier, lead_time: qt.lead_time, warranty: qt.warranty, items: qt.items });
}
// 7 the comparison report (quote_compare's deterministic ranking, the report builder)
const lab = F.labelled();
// deno-lint-ignore no-explicit-any
const a: any = deterministicCompare(lab, 'en'); a.all_quotes = rosterOf(lab, a.top3); a.total_quotes = lab.length; a.technical = F.HVAC_TECHNICAL;
out.comparison = await draw(F.reasoned((ar) => QD.compareDocument({ analysis: a, inquiry: F.INQUIRY, lang: 'en', maskNames: F.identities(), portalUrl: portalLink('en', F.INQUIRY.id), linkFor: (x: string) => portalLink('en', F.INQUIRY.id, x), ...on, arTexts: ar })).body, 'shared/comparison_report.pdf');
out.top3 = (a.top3 || []).map((x: Record<string, unknown>, i: number) => ({ rank: i + 1, label: x.label, price: x.price, why: x.why || x.reason || x.summary || null, quote_id: x.quote_id }));
// 8 the reveal fee invoice
const first = live[0];
// the money by the product's own rule (_shared/reveal_fee.ts): the customer pays the 3% fee and nothing else; Stripe's cost is
// ours (expense 6100), estimated here for a UAE card. 3% is the founder's hard rule (the only hard rules, memory).
const charge = revealCharge(Number(first.quote_amount), 0.03);
const fee = charge.base_fee, proc = charge.processing_fee;
out.charge = charge; out.stripe_cost = stripeCostFor(charge.total_charged, 'domestic');
const SALE: RevealSale = { tx_id: 'tx-zzdemo-sample', invoice_no: 'ZZDEMO-SAMPLE-0001', paid_at: '2026-11-13T07:40:00Z', reveal_fee: fee, processing_fee: proc, total_charged: charge.total_charged,
  quote_amount: Number(first.quote_amount), payment_ref: 'pi_zzdemo_sample', customer: { name: cust.name, email: cust.email, phone: null },
  request: { summary: 'Villa AC: replace four split units, service three ducted units', category: 'hvac', ref: 'QD-ZZSAMPLE' }, card: { brand: 'visa', last4: '4242' }, refund: null };
out.invoice = await draw(revealInvoiceDocument(SALE, 'en'), 'shared/invoice.pdf');
out.sale = SALE;
console.log(JSON.stringify(out));
