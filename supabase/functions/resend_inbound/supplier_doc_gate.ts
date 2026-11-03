// A SUPPLIER DOCUMENT BY E-MAIL: what the classifier is shown, and when its answer may write onto the lead (it_engineer,
// 3 Nov 2026, release qualification). The subject and body rode into the classifier's prompt bare, and the category
// alone wrote onto the lead whose address the From header named: trade_license_no, authority and expiry for a
// 'trade_license'; capability_summary, services, products, service emirates and the document paths for a
// 'company_profile' or 'catalogue' (review of #1836). A forged From and a body telling the model "this is a trade
// licence" were enough. The mail is now fenced as data, and the lead is written only for a sender the receiving server
// authenticated (suppression_policy.ts senderAuthenticated) who is a matched lead. Anything else is stored and left in
// doc_reviews as pending, for a person.
// prevented by: resend_inbound/supplier_doc_gate.test.ts
import { untrustedMail } from '../_shared/untrusted.ts';

export function classifyPrompt(supplier: string, subject: unknown, body: unknown, fname: string, mime: string): string {
  return `Email from supplier ${supplier}. Attached file: ${fname} (${mime}). Classify this document. The e-mail it came with:`
    + untrustedMail(subject, body);
}

export function leadWritable(lead: { id?: unknown } | null, senderAuthenticated: boolean): boolean {
  return !!lead?.id && senderAuthenticated === true;
}
