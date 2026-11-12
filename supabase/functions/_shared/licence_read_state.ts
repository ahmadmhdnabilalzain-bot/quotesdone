// WHOSE FAILURE AN UNREAD LICENCE IS (10 Nov 2026, customer_support; supplier-journey follow-up, item 6 of #1901's report).
//
// MEASURED BEFORE THIS FILE. supplier_api process_docs answered `license_error: 'extract_failed'` to the browser when OUR
// reader failed (license_extract timed out, the gateway answered 5xx or was out of credit, the reply did not parse) and
// stored nothing about it. The row then looked exactly like a licence the supplier had made unreadable: the licence number
// (or name, expiry, authority) empty, so fn_sales_engineer_verifies_supplier held it licence_number_unread and
// fn_sales_engineer_decides_held_registrations asked the supplier three times (day 0, 3, 7) for "a clearer copy of the whole
// page" and closed the registration at day 14, for a file that may have been perfectly legible. The OpenRouter account
// was out of credit on 10 Nov (checkpoint-10-nov), so every scanned licence was on that path.
//
// THE RULE, one function every licence reader calls (supplier_api process_docs, supplier_portal save_documents):
//   * 'read'            our reader finished. Whatever is still blank is what the document itself did not show, and the gate
//                       may ask the supplier for a clearer copy;
//   * 'file_unreadable' the model was asked and answered that the document cannot be read (licence_extract's
//                       normaliseLicence: no name, or 'low' confidence). The file is the problem; asking is right;
//   * 'ours_failed'     a field is still blank and our model was NOT able to answer: it failed, it is switched off
//                       (app_secrets.document_expiry_ai), or the stored bytes could not be fetched to send it. The supplier is
//                       never asked for this: the gate holds the registration as 'licence_being_read', the sweep reads the
//                       licence again (supplier_api docs_reread, fn_supplier_licence_reread_claim), and a licence we still
//                       cannot read after three days goes to the ceo seat, never to the 14-day close.
// Prevented by: _shared/licence_read_state.test.ts.
import { licenceNeedsModel } from './document_expiry.ts';

/** What happened when the model was (or was not) asked to read the licence. */
export type LicenceModelOutcome =
  | 'not_needed'   // code read every field the gate stands on, so the model was not asked
  | 'not_sent'     // a field was blank but there was nothing to send (no bytes, no images)
  | 'off'          // a field was blank and the document model is switched off
  | 'pending'      // the model is asked after the row is written and has not answered yet (supplier_api/lib/licence_store_first.ts)
  | 'failed'       // the model was asked and did not answer usably (5xx, timeout, out of credit, unparseable)
  | 'unreadable'   // the model answered: this document cannot be read
  | 'read';        // the model answered with a reading

export type LicenceReadState = 'read' | 'ours_failed' | 'file_unreadable';

/** The four fields the verification gate stands on, as they will be written to the row. */
export type LicenceRowFields = { licence_legal_name?: unknown; trade_license_no?: unknown; license_expiry?: unknown; license_authority?: unknown };

const filled = (v: unknown) => v != null && String(v).trim() !== '';

/** True when one of the four fields the gate stands on is still blank after every reader ran. */
export function licenceLeftUnread(f: LicenceRowFields): boolean {
  return licenceNeedsModel({
    legal_name_en: filled(f.licence_legal_name) ? String(f.licence_legal_name) : null,
    licence_no: filled(f.trade_license_no) ? String(f.trade_license_no) : null,
    expiry_date: filled(f.license_expiry) ? String(f.license_expiry) : null,
    authority: filled(f.license_authority) ? String(f.license_authority) : null,
  });
}

/** Whose failure a licence read is. See the header: only 'ours_failed' keeps the supplier from being asked. */
export function licenceReadState(leftUnread: boolean, model: LicenceModelOutcome): LicenceReadState {
  if (!leftUnread) return 'read';
  if (model === 'read') return 'read';
  if (model === 'unreadable') return 'file_unreadable';
  return 'ours_failed';
}

/** The outcome of one license_extract answer (supplier_api's extract(), supplier_portal's direct call). */
// deno-lint-ignore no-explicit-any
export function modelOutcomeOf(jd: any): LicenceModelOutcome {
  if (jd?.ok && jd.doc && !jd.doc.unreadable) return 'read';
  if (jd?.ok && jd.doc?.unreadable) return 'unreadable';
  return 'failed';
}

/**
 * THE LONGEST A MODEL'S READING OF A LICENCE (OR A CERTIFICATE) MAY HOLD A SUPPLIER'S ANSWER (11 Nov 2026, customer_support;
 * certification run 2, J5: an inline read held process_docs 56 s, the browser was cut off at ~30 s and told the stored file was
 * not stored). supplier_api process_docs lets a slower read finish after the answer (lib/licence_store_first.ts); supplier_portal
 * save_documents stops waiting, keeps the file and the read state 'ours_failed', and the sweep reads it again.
 */
export const MODEL_ANSWER_BUDGET_MS = 10_000;

/** What the supplier reads while our reader has not finished. English only (suppliers are always written in English). */
export const LICENCE_BEING_READ_NOTE =
  'Our document reader has not finished reading your trade licence yet. That is on our side, not yours: we read it again automatically and tell you if anything is needed. Nothing was guessed.';

/**
 * WHERE CODE AND THE MODEL READ A LICENCE DIFFERENTLY, IT IS RECORDED, NOT ACTED ON (12 Nov 2026, sales_engineer; founder rulings
 * 1663, 1664). The model's reading is the reading; code's own reading and license_extract's text-layer notes (a date or number the
 * PDF's text layer does not print, `check.notes`) are evidence for our own reviewer only, never shown to the supplier and never a
 * hold. One agent_actions row per read that has something to say (kind 'licence_read_disagreement', auto_done: nothing to do on it
 * one by one; the session counts them, e.g. select detail->'fields' from agent_actions where kind = 'licence_read_disagreement').
 * No table of its own: agent_actions already holds supplier_api's evidence rows (services cross-check). A failed write is logged.
 */
export async function recordLicenceReadNote(
  // deno-lint-ignore no-explicit-any
  admin: any, supplierId: unknown, where: string,
  note: { disagreements?: { field: string; code: unknown; model: unknown }[]; check?: { failed?: string[]; notes?: string[]; asked?: number } | null; path?: unknown },
): Promise<void> {
  const fields = note.disagreements ?? [];
  const checks = [...(note.check?.failed ?? []), ...(note.check?.notes ?? [])];
  if (!fields.length && !checks.length) return;
  try {
    const { error } = await admin.from('agent_actions').insert({
      agent: 'sales_engineer', kind: 'licence_read_disagreement', status: 'auto_done', risk: 'low',
      title: `Licence read: ${[...fields.map((f) => f.field), ...checks].join(', ')}`.slice(0, 200),
      recommendation: "The model's reading was kept. Nothing to do on this row alone; it is counted to see where code and the model differ.",
      detail: { supplier_id: supplierId, where, fields, checks, asked: note.check?.asked ?? 1, path: note.path ?? null, at: new Date().toISOString() },
      target_table: 'leads', target_id: String(supplierId),
    });
    if (error) console.error(JSON.stringify({ at: `${where}.licence_read_note`, supplier: supplierId, error: error.message }));
  } catch (e) { console.error(JSON.stringify({ at: `${where}.licence_read_note`, supplier: supplierId, error: String(e) })); }
}

/**
 * AN APPROVED SUPPLIER KEEPS THE READING WE ACCEPTED UNTIL HIS NEW LICENCE'S READING LANDS (12 Nov 2026, sales_engineer; second
 * review of #1978, defect A). Since rulings 1663/1664 only the model's reading is written, and a new file cleared the old readings
 * at once with the state 'ours_failed'. For an APPROVED supplier the re-verification trigger (z20, source 'licence_changed') then
 * found his name, number, expiry and authority blank and made him pending / licence_being_read, verified false, out of matching;
 * with the provider down that lasted until a re-read succeeded (10 minutes to about 42 hours). And the nightly
 * fn_reconcile_doc_blocks lifts a 'licence_expired' block when the expiry is NULL, so a blocked supplier who attached any file while
 * the provider was down would have been unblocked and e-mailed "active again" before anything was read.
 * Now, for an approved supplier only, the new file is recorded with the state 'ours_failed' (our reader has not finished: the sweep
 * reads it again) and the accepted reading stays on the row; the gate keeps him approved on it, and an expiry block stays on the
 * date that set it. When the model's reading of the new file lands it replaces all four fields, read or not (an unread field is
 * then unread, never the old value), and the usual re-verification runs on it. A model answer that the file is unreadable is a
 * reading too: the old fields are cleared and the file is held. Every other supplier is cleared at once, as before. What he is
 * shown meanwhile is the new licence being read, never the old values as its reading (src/.../licenceReceived.ts).
 * Prevented by: supplier_api/an_approved_supplier_keeps_standing_while_a_new_licence_is_read.test.ts.
 */
export const keepsAcceptedReading = (approvalStatus: unknown): boolean => String(approvalStatus ?? '') === 'approved';
/** The four readings the gate stands on, cleared: what a new licence's reading replaces whole. */
export const LICENCE_READINGS_CLEARED = { licence_legal_name: null, license_expiry: null, trade_license_no: null, license_authority: null } as const;
