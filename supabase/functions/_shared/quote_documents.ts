// quote_documents.ts — what goes ON the customer's quotation PDF and comparison report.
//
// 14 Sep 2026, agent: ceo. Two founder notes on the documents #600/#601 produced:
//   "the format can be more professional and advanced (very simple now)"
//   "what is arabic is not fully in arabic, many english words here and there"
// and a third on the comparison report: it must be technically detailed — the exact material spec
// (type of wood, thickness …) side by side, not only delivery time and installation.
//
// WHAT IT IS NOW. Each document is a cover (title, reference, date, request summary, a key-figures
// strip) and numbered sections, laid out by pdf_native/render.ts. The builders here are pure:
//   • Everything the platform knows the meaning of is written from our own keys (labels, trade codes,
//     emirates, durations, units).
//   • Everything a person wrote — item descriptions, specification values, scope, exclusions, payment
//     terms — is translated natively by reasoning (_shared/reasoned_governance.ts nativeArabic, decision
//     point trade_glossary_ar, 23 Sep 2026) and handed in as `arTexts`. A line without its Arabic is
//     returned in `untranslated` and the caller HOLDS the Arabic document: never printed half-translated,
//     and never a glossary's word-by-word substitution (founder_instruction 890).
//   • The comparison report carries a TECHNICAL COMPARISON: each scope line × each supplier's stated
//     value per attribute, marked matches / differs / not stated against the request (see
//     TechnicalComparison below — the renderer input the spec agent's contract fills).
//   • The founder's four completeness checks (14 Sep 2026) are shown side by side for every quote:
//     material specs per line, delivery / lead time, installation (where it applies: included, scope,
//     timeline) and warranty (where it applies: period and coverage). "N/A" where it does not apply.
//   • Who prepared it: "the QuotesDone sales engineer" (founder rule, 14 Sep 2026: "its always the
//     sales agent. no other agent is involved in customer or supplier portal"). Never an AI, never
//     an assistant, never another agent.
//
// ANONYMITY. The customer pays a reveal fee to learn who quoted. Supplier free text can carry a
// name, a number or an email ("call Ahmed on 050…"), so every string in both documents passes
// maskContacts, which also blanks the supplier names the caller hands in. Links are ids only.
// The documents are split by subject under ./quote_documents/; this file keeps every public name importers already use.
export { DOC_VERSION, docName, isCurrentDoc, supplierLabel, maskContacts } from './quote_documents/base.ts';
export type { Lang } from './quote_documents/base.ts';
export { arCount, arUnit, arEmirate, enCategory, arCategory, arDuration } from './quote_documents/arabic.ts';
export { jobNoOf, itemsOfRows, completenessOf, quoteRef, clipCell, arLabelWords, labelFor, VAT_LINE, VAT_RE, stripVat } from './quote_documents/rows.ts';
export type { QuoteRow, InquiryRow, Item, SpecFlag, SpecCell, TechAttribute, TechLine, TechTerm, TechnicalComparison } from './quote_documents/rows.ts';
export type { ArTexts } from './quote_documents/kit.ts';
export { quoteDocument } from './quote_documents/quote_document.ts';
export { comparedQuotes, compareTable, toCsv } from './quote_documents/compare_rows.ts';
export { compareDocument } from './quote_documents/compare_document.ts';
export { qtyBasis, inquiryDocument } from './quote_documents/inquiry_document.ts';
export type { RequestLine, InquiryDocRow } from './quote_documents/inquiry_document.ts';
