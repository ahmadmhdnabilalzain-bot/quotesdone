// A CUSTOMER'S TERMS ACCEPTANCE, WRITTEN THE SAME WAY EVERYWHERE (it_engineer, 6 Oct 2026; release review of #1240).
//
// Suppliers record version, time, IP and the SHA-256 of the text they accepted (_shared/supplier_terms.ts).
// Customers recorded version, time and IP only, and nothing ever asked a customer to accept a NEWER version:
// a contract change applied silently. This file is the one place that answers "which version is current" and
// "what does an acceptance record hold", for kyc accept_terms (sign-up) and customer_api (re-acceptance).
//
// The SHA is the pinned hash of the signed customer body (app_secrets terms_sha256_customer), recorded only when
// the pin is for the version being accepted, so a stale pin can never be written against a new version.
// A customer who accepted an older version is NOT locked out (5 live customers on 6 Oct 2026: v6, v8, v9 and
// one with none). Their acceptance stands until their NEXT request, where they re-accept inline.

export type Sec = (k: string) => Promise<string | null | undefined>;

export async function currentCustomerTermsVersion(sec: Sec): Promise<string | null> {
  return ((await sec('customer_terms_version')) || '').trim() || null;
}

/** True when the customer has accepted some version, but not the current one. */
export function needsReacceptance(c: { tos_accepted_at?: string | null; tos_version?: string | null } | null | undefined, current: string | null): boolean {
  return !!(c && c.tos_accepted_at && current && String(c.tos_version || '') !== current);
}

export async function customerTermsRecord(sec: Sec, ip: string): Promise<{ tos_accepted_at: string; tos_version: string; tos_ip: string; tos_sha256: string | null } | null> {
  const v = await currentCustomerTermsVersion(sec);
  if (!v) return null;
  const pinV = ((await sec('terms_sha256_customer_version')) || '').trim();
  const sha = pinV === v ? (((await sec('terms_sha256_customer')) || '').trim() || null) : null;
  return { tos_accepted_at: new Date().toISOString(), tos_version: v, tos_ip: ip, tos_sha256: sha };
}

// The words a customer sees when a newer version waits (customer_api create_inquiry / accept_terms).
export const REACCEPT_MESSAGE = {
  en: 'Our Terms of Service have been updated. Please read and accept the current version to send this request.',
  ar: 'حُدِّثت شروط الخدمة لدينا. يُرجى الاطلاع على الإصدار الحالي والموافقة عليه لإرسال هذا الطلب.',
};
