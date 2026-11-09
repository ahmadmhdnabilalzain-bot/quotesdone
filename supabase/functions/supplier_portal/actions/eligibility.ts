// supplier_portal — eligibility, insights_summary and the supporting-document actions.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here from index.ts on 9 Nov 2026 (sales_engineer: the 791-line index.ts split into modules, a pure move).
import { safeFilename, SAFE_UPLOAD } from '../../_shared/attachment.ts';
import { sanitizeAndScan } from '../../_shared/malware.ts';
import { buildEligibility } from '../overview.ts';
import { buildInsightsSummary } from '../insights_summary.ts';
import { deleteSupporting, listSupporting, saveSupporting, urlSupporting } from '../supporting_documents.ts';
import { type ActionCtx, J, admin, sign } from '../context.ts';

export async function eligibilityActions(c: ActionCtx): Promise<Response | undefined> {
  const { b, action, supId } = c;
    // Why am I not being matched? The builder and the reasoning behind every item: ./overview.ts.
    if (action === 'eligibility') return J(await buildEligibility(admin, supId));

    // THE INSIGHTS TAB AS DATA (15 Sep 2026): totals, price position, funnel, 12-month series and
    // coded hints. ./insights_summary.ts; the contract is docs/api/supplier_portal_messages_documents_insights.md.
    if (action === 'insights_summary') {
      const r = await buildInsightsSummary(admin, supId, buildEligibility(admin, supId).then((e) => !!e.eligible));
      return J(r.body, r.status);
    }

    // SUPPORTING COMPANY DOCUMENTS (15 Sep 2026): any document besides the fixed kinds above.
    // ./supporting_documents.ts says where each file goes and why it reaches Dropbox.
    if (action === 'supporting_documents' || action === 'supporting_document_save' || action === 'supporting_document_delete' || action === 'supporting_document_url') {
      const signOne = (p: string) => sign('supplier-docs', p);
      let r;
      if (action === 'supporting_documents') r = await listSupporting(admin, supId, signOne);
      else if (action === 'supporting_document_delete') r = await deleteSupporting(admin, supId, b.id);
      else if (action === 'supporting_document_url') r = await urlSupporting(admin, supId, b.id, signOne);
      else r = await saveSupporting(admin, supId, b, {
        sign: signOne, safeFilename,
        scan: async ({ b64, mime, filename }) => {
          const sc = await sanitizeAndScan({ input: b64, declaredMime: mime, filename, allow: SAFE_UPLOAD,
                                             scan: { source: 'supplier_portal.supporting', subject: String(supId), filename, bucket: 'supplier-docs' } });
          return sc.ok ? { ok: true, bytes: sc.result.bytes, mime: sc.result.mime } : { ok: false, reason: String(sc.body.detail || sc.body.error) };
        },
        upload: async (path, bytes, mime) => {
          const { error } = await admin.storage.from('supplier-docs').upload(path, bytes, { contentType: mime, upsert: false });
          return { error: error ? error.message : null };
        },
      });
      return J(r.body, r.status);
    }
}
