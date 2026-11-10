// supplier_api — the regenerated quotation's renderer and the replay that finishes a held Arabic one.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
import { SUPPLIER_LOCALE } from '../../_shared/registered_locale.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { nativeArabic } from '../../_shared/reasoned_governance.ts';
import { finishArabic, pdfDoc, supabaseRepo, type Render } from '../../_shared/line_specs/workflow.ts';
import { requirementsOf } from '../../_shared/line_specs/assess.ts';
import { jobAlias } from '../../_shared/quote_labels.ts';
import { jobNo } from '../quote_review.ts';
import { J, SUPA_URL, admin, secretVal } from '../context.ts';
import { UUID_RE } from './fields.ts';
import { kickDelivery, supplierOf } from './quote_acceptance.ts';

/** The regenerated quotation's renderer: the standard quotation (quoteDocument via workflow.ts pdfDoc) in the
 * supplier's language, under the one alias this supplier carries on this job. An Arabic quotation whose lines are
 * not all translated by reasoning yet is not rendered: 'arabic_pending' (decision point trade_glossary_ar). */
// deno-lint-ignore no-explicit-any
export function regenRender(q: any, sup: any, inqRow: any): Render {
  return async (rec) => {
    const secret = await secretVal('cred_fn_supplier_api'); if (!secret) return null;
    const [{ data: safeInq }, { data: matches }] = await Promise.all([
      admin.from('inquiries_supplier_safe').select('emirate').eq('id', q.inquiry_id).maybeSingle(),
      admin.from('inquiry_matches').select('id,supplier_id').eq('inquiry_id', q.inquiry_id).order('id', { ascending: true }),
    ]);
    const order = [...new Set((matches || []).map((m: { supplier_id: number }) => Number(m.supplier_id)))];
    const letter = jobAlias(order, Number(sup.id)).replace(/^Supplier /, '');
    const lang: 'en' | 'ar' = SUPPLIER_LOCALE;
    const d = await nativeArabic(defaultDeps(admin, 'supplier_api'), (arTexts) => pdfDoc(rec, { inquiry: { id: String(q.inquiry_id), rfq_no: inqRow?.rfq_no ?? null, category: inqRow?.category ?? null, emirate: safeInq?.emirate ?? null }, letter, lang, arTexts }), { subject: { quote_id: rec.quote_id, kind: 'regenerated_quotation' } });
    if (!d.doc) {
      // The quote waits by its own id, whoever filed the lines first; the replay renders it when they are all in.
      if (d.missing.length) await admin.rpc('fn_arabic_document_wait', { p_quote: String(rec.quote_id), p_texts: d.missing });
      return 'arabic_pending';
    }
    const r = await fetch(`${SUPA_URL}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, ...d.doc.body, bucket: 'quote-files', folder: `quotes/${sup.id}/${q.inquiry_id}/regenerated`, name: `quotation_${String(rec.quote_id).slice(0, 8)}_option${rec.option_no}_${lang}` }) });
    const j = await r.json().catch(() => null);
    return j?.ok ? { bucket: String(j.bucket), path: String(j.path) } : null;
  };
}

/** THE REPLAY'S EFFECT (internal credential only, from _shared/reasoned_delivery.ts): a regenerated Arabic quotation
 * that waited for its reasoned translation is rendered now and its approval request sent (workflow.ts finishArabic). */
export async function arabicFinish(quoteId: string): Promise<Response> {
  if (!UUID_RE.test(quoteId)) return J({ ok: false, code: 'not_found' }, 404);
  const repo = supabaseRepo(admin, { dispatch: kickDelivery });
  const q = await repo.quote(quoteId);
  if (!q) return J({ ok: false, code: 'not_found' }, 404);
  const { data: sup } = await admin.from('leads').select('id,locale,whatsapp,phone,claimed_by').eq('id', q.supplier_id).maybeSingle();
  if (!sup) return J({ ok: false, code: 'not_found' }, 404);
  const { data: inqRow } = await admin.from('inquiries').select('category,spec,rfq_no').eq('id', q.inquiry_id).maybeSingle();
  const { count: optCount } = await admin.from('quotes').select('id', { count: 'exact', head: true }).eq('inquiry_id', q.inquiry_id).eq('supplier_id', sup.id);
  const ctx = { category: inqRow?.category ?? null, requirements: requirementsOf(inqRow?.spec), ref: jobNo({ id: String(q.inquiry_id), rfq_no: inqRow?.rfq_no }), multiOption: (optCount || 0) > 1 };
  const out = await finishArabic(repo, quoteId, supplierOf(sup, String(sup.claimed_by || '')), ctx, regenRender(q, sup, inqRow));
  // Done, or nothing waits any more: the waiter row goes. still_pending keeps it for the next replay.
  if (out.ok || out.code === 'not_pending' || out.code === 'not_found') await admin.from('arabic_document_waiter').delete().eq('quote_id', quoteId);
  else {
    // A render that fails is counted; after 5 it stops being replayed (fn_arabic_waiters_ready) and the sales engineer is told.
    const { data: w } = await admin.from('arabic_document_waiter').select('attempts').eq('quote_id', quoteId).maybeSingle();
    const attempts = Number(w?.attempts ?? 0) + 1;
    await admin.from('arabic_document_waiter').update({ attempts, last_tried_at: new Date().toISOString() }).eq('quote_id', quoteId);
    if (attempts >= 5) await admin.from('agent_actions').insert({ agent: 'sales_engineer', kind: 'arabic_quotation_render_failed', status: 'pending', risk: 'medium',
      title: 'The Arabic regenerated quotation could not be rendered after 5 tries', detail: { quote_id: quoteId, last: out }, target_table: 'quotes', target_id: quoteId });
  }
  return J(out, out.ok ? 200 : 409);
}
