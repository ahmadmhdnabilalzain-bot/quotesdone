// edit_summary — what edit_inquiry may write, decided without I/O (13 Nov 2026, sales_engineer; independent review of F2,
// item 7). MEASURED by the review: the edit form always re-sends the summary, so a budget-only edit ran the supplier gate on
// an unchanged summary and answered a permanent 422 "summary_names_you" for "Replace 4 split AC units" (a site seed "unit"
// erased "units"), never saying which word; and an accepted edit stored the REDACTED text over the customer's own words
// ("Repaint villa in █"). Now:
//  * only what changed is checked; an unchanged summary is not re-sent to the database at all;
//  * the customer's own words are stored as he wrote them: every supplier door gates them on the way out;
//  * a summary the gate would withhold from suppliers entirely is refused, naming the parts that cannot be sent and saying
//    that the exact site goes to the supplier whose quotation he opens;
//  * the emirate is one of the seven, whatever the browser sent.
// prevented by: supplier_api/nothing_below_the_emirate_reaches_a_supplier.test.ts ("edit_inquiry ...")
import { oneOfSeven } from '../../_shared/site_location.ts';
import { heldParts, requestSeeds, supplierField, type Buyer } from '../../supplier_api/what_a_supplier_receives.ts';

export type EditDecision = { ok: true; patch: Record<string, unknown> } | { ok: false; status: number; body: Record<string, unknown> };

export function editDecision(patch: Record<string, unknown>, current: { summary?: string | null }, owner: { resolved: boolean; buyer?: Buyer; spec?: unknown }): EditDecision {
  const clean: Record<string, unknown> = {};
  if (patch.budget !== undefined) clean.budget = patch.budget == null ? null : String(patch.budget).slice(0, 80);
  // null or empty is "no change" (second review of F2: the form always sends `emirate: eEmirate || null`, so a request with no
  // emirate was refused on every edit)
  if (patch.emirate != null && String(patch.emirate).trim() !== '') {
    const em = oneOfSeven(patch.emirate);
    if (!em) return { ok: false, status: 400, body: { ok: false, error: 'emirate_unknown', code: 'emirate_unknown', message: 'Choose one of the seven emirates.', message_ar: 'اختر إحدى الإمارات السبع.' } };
    clean.emirate = em;
  }
  const next = patch.summary === undefined ? undefined : String(patch.summary ?? '').slice(0, 500);
  if (next !== undefined && next.trim() !== String(current.summary ?? '').trim()) {
    if (!owner.resolved || !owner.buyer) return { ok: false, status: 503, body: { ok: false, error: 'summary_not_editable', code: 'summary_not_editable', message: 'We could not check this text for your own details just now. Please try again in a moment.', message_ar: 'تعذّر التحقق من خلو النص من بياناتك الآن. يُرجى المحاولة بعد لحظات.' } };
    const seeds = requestSeeds(owner.buyer, owner.spec);
    const g = supplierField<string>(next, owner.buyer, seeds);
    if (g.withheld) {
      const parts = heldParts(next, owner.buyer, seeds);
      const list = parts.length ? parts.map((p) => '"' + p + '"').join(', ') : 'your contact or site details';
      return { ok: false, status: 422, body: { ok: false, error: 'summary_names_you', code: 'summary_names_you', parts,
        message: `This description cannot be sent to the suppliers as written because of ${list}. Take that out and describe the work: the suppliers see the emirate, and your exact site goes to the supplier whose quotation you open.`,
        message_ar: `لا يمكن إرسال هذا الوصف إلى المورّدين كما هو بسبب ${list}. احذف ذلك وصف العمل: يرى المورّدون الإمارة، ويصل موقعك الدقيق إلى المورّد الذي تفتح عرضه.` } };
    }
    clean.summary = next;   // his own words; the doors gate them
  }
  if (!Object.keys(clean).length) return { ok: false, status: 400, body: { ok: false, error: 'nothing_editable', code: 'nothing_editable', message: 'Only the description, the budget and the emirate can be changed. For anything else, please post a new request.', message_ar: 'يمكن تعديل الوصف والميزانية والإمارة فقط. لأي تغيير آخر يُرجى إنشاء طلب جديد.' } };
  return { ok: true, patch: clean };
}
