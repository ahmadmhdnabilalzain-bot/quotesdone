// THE MANDATORY SIX — what a supplier must have before the sales engineer may verify them.
//
// Founder decision (memory: supplier-verification-mandatory-six): name, mobile, email, trade licence,
// company profile, signed T&C. Everything else is extra. "A supplier whose mandatory fields are
// incomplete cannot be verified by the sales engineer."
//
// 15 Sep 2026 (sales_engineer): THE DEFINITION MOVED INTO THE DATABASE. This file used to decide the six
// from row values, and a second, different decision lived in SQL (fn_supplier_mandatory_check): one took
// a licence NUMBER without a document and ticked the terms on the acceptance timestamp, the other took a
// landline-shaped regex for the mobile and ignored the owner's verified e-mail. The one definition is now
// public.fn_supplier_mandatory_six (scripts/sql/the_mandatory_six_have_one_definition_and_the_sales_engineer_verifies.sql):
// a document counts only when storage holds it, the terms item is the signed certificate, and a
// database trigger refuses approval while anything is missing. This file keeps only the presentation —
// the order, which tab fixes each item, and the words — and asks the database which items are missing.
// scripts/checks/the_mandatory_six_have_one_definition.test.mjs fails if the codes here and in the SQL
// ever differ, or if the portal's EN/AR copy lacks one.

// deno-lint-ignore no-explicit-any
type Admin = any;

export const MANDATORY_SIX = [
  // ruling 1672 (12 Nov 2026): the name is read from the trade licence, so it is fixed where the licence is
  { code: 'reg_name',    fix: 'documents', en: 'company name (read from your trade licence)', ar: 'اسم الشركة' },
  { code: 'reg_mobile',  fix: 'profile',   en: 'a verified UAE mobile number', ar: 'رقم جوال إماراتي موثَّق' },
  { code: 'reg_email',   fix: 'profile',   en: 'a verified e-mail address',    ar: 'بريد إلكتروني موثَّق' },
  { code: 'reg_licence', fix: 'documents', en: 'trade licence',                ar: 'الرخصة التجارية' },
  { code: 'reg_profile', fix: 'documents', en: 'company profile',              ar: 'الملف التعريفي للشركة' },
  { code: 'reg_terms',   fix: 'profile',   en: 'the signed supplier terms',    ar: 'الموافقة الموقّعة على شروط المورّد' },
] as const;

// Documents-tab keys that are part of the six. Catalogues are optional.
export const REQUIRED_DOC_KEYS = ['license', 'profile'];

export type RegItem = { code: string; done: boolean; fix: 'profile' | 'documents' };

/** The six, in order, ticked from the database's list of what is missing. */
export function registrationChecklist(missing: readonly string[]): RegItem[] {
  return MANDATORY_SIX.map(({ code, fix }) => ({ code, done: !missing.includes(code), fix }));
}

/** The six items still missing for this supplier, as the database decides them. Throws on a read error:
 *  an unreadable answer must never be shown as "complete". */
export async function mandatorySixMissing(admin: Admin, leadId: number): Promise<string[]> {
  const { data, error } = await admin.rpc('fn_supplier_mandatory_six_for', { p_lead_id: leadId });
  if (error) throw new Error('fn_supplier_mandatory_six_for: ' + error.message);
  return Array.isArray(data) ? (data as string[]) : [];
}

/** Missing codes in words, for a notice in the supplier's language. Unknown codes pass through. */
export function sixInWords(codes: readonly string[], lang: 'en' | 'ar'): string {
  return codes.map((c) => MANDATORY_SIX.find((i) => i.code === c)?.[lang] ?? c).join(lang === 'ar' ? '، ' : ', ');
}
