// ONE RECORD OF A SUPPLIER'S TERMS ACCEPTANCE (sales_engineer, 15 Sep 2026).
//
// Measured on origin/main: three writers recorded the acceptance three ways. supplier_api save_profile
// and supplier_api accept_terms read app_secrets('terms_version') and stored the SHA-256 of the exact
// agreement text; kyc accept_terms, called by the portal straight afterwards, read
// supplier_terms_version and rewrote the version with NO hash, so the stored record was always the one
// without the evidence. Both keys hold 'v12' today; nothing guaranteed they would stay equal.
//
// Every writer now builds the row here. The version is read server-side (supplier_terms_version, then
// terms_version), never from the browser; the hash is of the text this module was exported for, and is
// null — never the hash of the wrong agreement — when the live version is a different one.
import { SUPPLIER_AGREEMENT_AR, SUPPLIER_AGREEMENT_EN, SUPPLIER_AGREEMENT_VERSION } from './supplier_agreement.ts';

export type TermsRecord = {
  accepted_terms_at: string;
  accepted_terms_version: string;
  accepted_terms_ip: string | null;
  accepted_terms_sha256: string | null;
};

export async function agreementSha256(): Promise<string> {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(SUPPLIER_AGREEMENT_EN + '\n' + SUPPLIER_AGREEMENT_AR));
  return Array.from(new Uint8Array(bytes)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function currentSupplierTermsVersion(sec: (k: string) => Promise<string | null>): Promise<string> {
  return String((await sec('supplier_terms_version')) || (await sec('terms_version')) || '').trim().slice(0, 20);
}

/** The acceptance row for now, or null when no version is configured (refuse rather than invent one). */
export async function supplierTermsRecord(sec: (k: string) => Promise<string | null>, ip: string): Promise<TermsRecord | null> {
  const v = await currentSupplierTermsVersion(sec);
  if (!v) return null;
  if (v !== SUPPLIER_AGREEMENT_VERSION) console.error(`supplier terms ${v} have no exported agreement text (module is ${SUPPLIER_AGREEMENT_VERSION}); hash not stored`);
  return {
    accepted_terms_at: new Date().toISOString(),
    accepted_terms_version: v,
    accepted_terms_ip: ip || null,
    accepted_terms_sha256: v === SUPPLIER_AGREEMENT_VERSION ? await agreementSha256() : null,
  };
}
