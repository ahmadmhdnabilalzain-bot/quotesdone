// inquiry_intake/required_documents.ts — §3 "Required Documents" on the summary card of a ready request. Moved verbatim from
// handle.ts (19 Nov 2026, it_engineer; ledgers 1714/1715/1556: handle.ts was 1,418 lines), which runs it beside the supplier
// count on the turn's clock.
// deno-lint-ignore-file no-explicit-any
import { utilityText } from './classify.ts';
import { admin } from './shared.ts';

// REQUIRED DOCUMENTS come from category_specs.compliance_checklist — the same list
// create_inquiry now copies onto the RFQ, so the customer is shown exactly what the supplier
// will be held to. A category with no checklist emits an EMPTY ARRAY, never a placeholder:
// 21 of 56 categories carry one, and inventing three lines for the other 35 would be telling
// the customer we require things we do not.
export async function readRequiredDocuments(brief: any, category: string, emirate: string | null): Promise<void> { try {
  const { data: cs } = await admin.from('category_specs').select('compliance_checklist').eq('category', category).maybeSingle();
  const cl = (cs as any)?.compliance_checklist;
  const list = Array.isArray(cl?.list) ? cl.list : (Array.isArray(cl) ? cl : []);
  // The checklist names "DEWA / the relevant emirate authority"; once the emirate is known the
  // one utility that serves it is named (classify.ts UTILITY_BY_EMIRATE).
  const em = brief.al_ain ? 'Al Ain' : (brief.emirate || emirate || null);   // AADC for Al Ain, ADDC for the rest of Abu Dhabi
  brief.required_documents = list.slice(0, 8).map((x: any) => ({
    item: utilityText(String(x?.item ?? x ?? '').slice(0, 160), em),
    item_ar: x?.item_ar ? utilityText(String(x.item_ar).slice(0, 160), em, 'ar') : null,
    authority: x?.authority ? utilityText(String(x.authority).slice(0, 80), em) : null,
    authority_ar: x?.authority_ar ? utilityText(String(x.authority_ar).slice(0, 80), em, 'ar') : null,
    notes: x?.notes ? String(x.notes).slice(0, 160) : null,
  })).filter((x: any) => x.item);
  brief.required_documents_source = brief.required_documents.length ? 'category_specs.compliance_checklist' : 'no checklist published for this category';
} catch (_e) { brief.required_documents = []; brief.required_documents_source = 'checklist lookup failed'; } }
