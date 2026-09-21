// cert_rows.ts - who the signed-terms certificate names (pure; tested by cert_rows.test.ts).
//
// THE CERTIFICATE NAMED THE WRONG SIGNATORY (21 Sep 2026, campaign registration walk). The row
// "Authorised signatory" printed fields.full_name, which for a supplier is the CONTACT person
// (full_name || contact_name || signatory_name). A supplier who entered contact "ZZ DEMO Contact" and
// signatory "ZZ DEMO Signatory" received a legal record saying the contact signed. The signatory is
// now the signatory the supplier entered, falling back to the contact only when none was given.
export type CertFields = Record<string, string>;

export function certFields(rec: Record<string, unknown>, kind: string): Pick<CertFields, 'full_name' | 'signatory'> {
  const s = (v: unknown) => (v == null ? '' : String(v)).trim();
  const full = s(rec.full_name) || s(rec.contact_name) || s(rec.signatory_name);
  return { full_name: full, signatory: kind === 'supplier' ? (s(rec.signatory_name) || s(rec.contact_name) || full) : '' };
}

export function identityRows(fields: CertFields, kind: string): [string, string][] {
  const rows: [string, string][] = [['Full name', fields.full_name]];
  if (kind === 'supplier') rows.push(['Company', fields.company], ['Authorised signatory', fields.signatory || fields.full_name]);
  return rows;
}
