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

// ── A WRONG DOCUMENT IN THE LICENCE SLOT (12 Nov 2026, sales_engineer; founder ruling 1668) ──────────────────────────────────────
// The rule for saying it is _shared/licence_extract.ts wrongDocumentOf. Here: where it is kept and how the supplier is told. A file the
// model is sure is not a licence never becomes his licence file (review of #1985, D3): the row is put back as it was before the upload
// (the previous licence file and readings, or none), so no new state, no column and no SQL. What it was is kept on one agent_actions
// row per upload (kind 'licence_wrong_document'; detail.path the wrong file, detail.restored_to the licence file the row names again),
// which `me`, the late-read poll and the Documents tab read back for three days while the row still names restored_to
// (wrongDocumentOnFile). When the answer could not reach the
// form (it came after the answer, or by the re-read sweep), the supplier is written to through the sales engineer's notice writer,
// once per file (fn_sales_engineer_writes, subject id licence_wrong_document:<lead>:<path>).
// NO SUPPLIER IS TRAPPED (13 Nov 2026, founder ruling 1681): every refusal sentence names a way to a person (licence_extract.ts
// NOT_A_LICENCE_WAY_TO_A_PERSON), and the SAME file (detail.file_sha, the SHA-256 license_extract computed) refused a second time for the
// same supplier opens ONE ceo task, once per supplier (an agent_actions row of kind 'licence_refused_twice' is the marker), not per upload.
type WrongDoc = { kind: string; why?: string; message: string; file_sha?: string };
/** Records which kind of wrong file the licence slot holds. Awaited before the row's own write, so a reader of the row finds it. */
export async function recordWrongDocument(
  // deno-lint-ignore no-explicit-any
  admin: any, supplierId: unknown, where: string, path: unknown, wrong: WrongDoc, restoredTo: unknown = null,
): Promise<void> {
  try {
    const { error } = await admin.from('agent_actions').insert({
      agent: 'sales_engineer', kind: 'licence_wrong_document', status: 'auto_done', risk: 'low',
      title: `Not a trade licence in the licence slot (${wrong.kind}) — supplier #${supplierId}`,
      recommendation: 'No action required. The supplier is told which file it is and asked for the trade licence; nothing of it was stored as a licence reading.',
      // blocks_submit: nothing was put back (no licence before it), so Submit stops on it (second review of #1985, W3)
      detail: { supplier_id: supplierId, where, path: path ?? null, restored_to: restoredTo ?? null, kind: wrong.kind, why: wrong.why ?? null, message: wrong.message,
        blocks_submit: (restoredTo ?? null) === null, file_sha: wrong.file_sha ?? null, at: new Date().toISOString() },
      target_table: 'leads', target_id: String(supplierId),
    });
    if (error) console.error(JSON.stringify({ at: `${where}.wrong_document`, supplier: supplierId, error: error.message }));
  } catch (e) { console.error(JSON.stringify({ at: `${where}.wrong_document`, supplier: supplierId, error: String(e) })); }
  if (wrong.file_sha) await refusedTwice(admin, supplierId, where, path, wrong);
}
/** The same file refused twice for one supplier: one ceo task, once per supplier. Never fails the caller. */
async function refusedTwice(
  // deno-lint-ignore no-explicit-any
  admin: any, supplierId: unknown, where: string, path: unknown, wrong: WrongDoc,
): Promise<void> {
  try {
    const { data: same } = await admin.from('agent_actions').select('id').eq('kind', 'licence_wrong_document').eq('target_id', String(supplierId))
      .eq('detail->>file_sha', String(wrong.file_sha)).limit(2);
    if (!Array.isArray(same) || same.length < 2) return;   // this upload's own row is one of them
    const { data: told } = await admin.from('agent_actions').select('id').eq('kind', 'licence_refused_twice').eq('target_id', String(supplierId)).limit(1);
    if (Array.isArray(told) && told.length) return;
    await admin.from('agent_actions').insert({ agent: 'sales_engineer', kind: 'licence_refused_twice', status: 'needs_review', risk: 'medium',
      title: `The same file was refused twice as his trade licence — supplier #${supplierId}`.slice(0, 200),
      recommendation: `The reader said the file is not a trade licence (${wrong.kind}: ${wrong.why || 'no reason given'}) and he attached the same file again. Open it (${String(path ?? '')}). If it is his licence, record its fields on his row with licence_read_state 'read'; if not, tell him what to attach.`,
      detail: { supplier_id: supplierId, where, path: path ?? null, kind: wrong.kind, why: wrong.why ?? null, file_sha: wrong.file_sha, at: new Date().toISOString() },
      target_table: 'leads', target_id: String(supplierId) });
    await admin.rpc('fn_ceo_task_open', { p_title: `A supplier attached the same file twice as his licence: #${supplierId}`,
      p_detail: `Supplier ${supplierId} attached the same file (${String(path ?? '')}) twice in the licence slot and the reader refused it both times (${wrong.kind}). Open it: if it is his licence, record its fields with licence_read_state 'read'; if not, tell him what to attach.` });
  } catch (e) { console.error(JSON.stringify({ at: `${where}.refused_twice`, supplier: supplierId, error: String(e) })); }
}
/** The last file put in the licence slot that was not read as a licence (a wrong document, or one held for a person), while the row
 *  still names the file it was left at (restored_to; three days at most), or null. `blocks_submit`: the form stops Submit on it. */
export const WRONG_DOCUMENT_SHOWN_MS = 3 * 24 * 3600_000;
export async function wrongDocumentOnFile(
  // deno-lint-ignore no-explicit-any
  admin: any, supplierId: unknown, row: { license_doc_path?: unknown } | null | undefined, now = Date.now(),
): Promise<{ kind: string; message: string; path: string; held: boolean; blocks_submit: boolean } | null> {
  if (!row || supplierId == null) return null;
  try {
    const { data } = await admin.from('agent_actions').select('kind,detail,created_at').in('kind', ['licence_wrong_document', 'licence_held_for_person'])
      .eq('target_id', String(supplierId)).gte('created_at', new Date(now - WRONG_DOCUMENT_SHOWN_MS).toISOString()).order('created_at', { ascending: false }).limit(1);
    const r = (Array.isArray(data) && data[0]) || null, d = r?.detail || null;
    if (!d || (d.restored_to ?? null) !== (row.license_doc_path ?? null)) return null;
    const held = r.kind === 'licence_held_for_person';
    return { kind: String(d.kind ?? 'other'), message: String(d.message ?? ''), path: String(d.path ?? ''), held, blocks_submit: !held && d.blocks_submit !== false };
  } catch (_e) { return null; }
}

/**
 * A FILE THE MODEL DOUBTS IS A LICENCE IS PUT TO A PERSON AT ONCE (12 Nov 2026, sales_engineer; second review of #1985, W1; rule (iii)
 * of licence_extract.ts licenceJudgementOf). Three rows, written before the row's own write so every reader finds them:
 *   1. agent_actions 'licence_held_for_person', needs_review: what the model said the file is and what licence-like fields it read (kept
 *      here for the person, never on the row), the path, the file the row is left at (restored_to) and the sentence he was shown;
 *   2. a ceo task (fn_ceo_task_open, as the held-registration hand-over opens one), now and not after three days of "being read";
 *   3. the hand-over's own once-mark (agent_actions held_registration_for_ceo, clock licence_being_read:<path>), so the daily decider does
 *      not open a second task for the same file three days on.
 * The person accepts it the way a held licence is accepted today: record the fields on the supplier's row with licence_read_state 'read';
 * the re-verification trigger (z20) then runs the gate on them. Never fails the caller.
 */
export async function holdLicenceForPerson(
  // deno-lint-ignore no-explicit-any
  admin: any, supplierId: unknown, companyName: unknown, where: string, path: unknown, held: { kind: string; why?: string; message: string; read?: Record<string, unknown> }, restoredTo: unknown,
): Promise<void> {
  const name = String(companyName ?? `supplier #${supplierId}`).slice(0, 120);
  const r = held.read ?? {};
  // once per file: a second answer about the same file (a retry, the sweep) opens nothing new
  try {
    const { data: seen } = await admin.from('agent_actions').select('id').eq('kind', 'licence_held_for_person').eq('target_id', String(supplierId)).eq('detail->>path', String(path ?? '')).limit(1);
    if (Array.isArray(seen) && seen.length) return;
  } catch (_e) { /* the check is a courtesy; a duplicate task is the worse failure only by a little */ }
  const readLine = Object.entries(r).filter(([, v]) => String(v ?? '').trim()).map(([k, v]) => `${k} ${v}`).join(', ') || 'nothing';
  try {
    await admin.from('agent_actions').insert({
      agent: 'sales_engineer', kind: 'licence_held_for_person', status: 'needs_review', risk: 'medium',
      title: `Check a licence the reader doubts: called ${held.kind} — ${name}`.slice(0, 200),
      recommendation: `The model read licence-like fields (${readLine}) but called the file ${held.kind}: ${held.why || 'no reason given'}. Open the file. If it is his trade licence, record its fields on the supplier's row with licence_read_state 'read' (the gate then runs on them). If it is another document, ask him for his licence. Nothing of it was stored as a licence and he cannot be approved on it.`,
      detail: { supplier_id: supplierId, where, path: path ?? null, restored_to: restoredTo ?? null, kind: held.kind, why: held.why ?? null, read: r, message: held.message,
        blocks_submit: false, at: new Date().toISOString() },
      target_table: 'leads', target_id: String(supplierId),
    });
    await admin.rpc('fn_ceo_task_open', { p_title: `Check a supplier licence our reader doubts: ${name}`,
      p_detail: `Supplier ${supplierId} attached a file as his trade licence (${String(path ?? '')}). The model read licence-like fields (${readLine}) but said it is ${held.kind}. Open it: if it is his licence, record its fields with licence_read_state 'read'; if not, ask him for his licence. He was told a person will check it.` });
    await admin.from('agent_actions').insert({ agent: 'sales_engineer', kind: 'held_registration_for_ceo', status: 'auto_done', risk: 'low',
      title: `Held registration put to the ceo seat — ${name}`.slice(0, 200), recommendation: 'No action required here. The ceo task decides it.',
      detail: { supplier_id: supplierId, clock: `licence_being_read:${String(path ?? '')}`, why: `the model doubts the file is a licence (${held.kind})` }, target_table: 'leads', target_id: String(supplierId) });
  } catch (e) { console.error(JSON.stringify({ at: `${where}.held_for_person`, supplier: supplierId, error: String(e) })); }
}
/** The e-mail when the form could not say it: the same finding, worded for a letter, once per file. Never fails the caller. */
export async function tellWrongDocument(
  // deno-lint-ignore no-explicit-any
  admin: any, supplierId: unknown, email: string | null | undefined, path: unknown, wrong: WrongDoc,
): Promise<void> {
  if (!email) return;
  const what = wrong.message.replace(/^This (looks like|does not look like)/, (_m, v) => `The file you attached as your trade licence ${v === 'looks like' ? 'looks like' : 'does not look like'}`)
    .replace(/ Please attach your (company's )?trade licence here\..*$/, '');
  const body = `${what} Please attach your current UAE trade licence in the Trade licence step of your registration at https://quotesdone.com/portal; we read it as soon as it arrives. Nothing from the other file was recorded as your licence.`;
  try {
    const { error } = await admin.rpc('fn_sales_engineer_writes', { p_msg_type: 'licence_wrong_document', p_role: 'supplier', p_email: email, p_lead: Number(supplierId),
      p_customer: null, p_inquiry: null, p_quote: null, p_subject_en: 'Your QuotesDone registration: please attach your trade licence', p_body_en: body,
      p_subject_id: `licence_wrong_document:${supplierId}:${String(path ?? '')}` });
    if (error) console.error(JSON.stringify({ at: 'licence_wrong_document.tell', supplier: supplierId, error: error.message }));
  } catch (e) { console.error(JSON.stringify({ at: 'licence_wrong_document.tell', supplier: supplierId, error: String(e) })); }
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

/**
 * THE MARK FOR STAFF WHILE AN APPROVED SUPPLIER'S NEW LICENCE IS READ (12 Nov 2026, sales_engineer; review of #1982, L3-2). While
 * keepsAcceptedReading holds, the stored FILE is the new one and the number, authority, name and expiry on the row are the previous
 * licence's; no staff surface reads licence_read_state, so a reviewer opening the file would take those values for its reading. One
 * agent_actions row per new file says so (kind 'licence_new_file_being_read', auto_done). Never awaited by the supplier's answer; a
 * failed write is only logged. A staff view that shows the marker beside the file is a follow-up (admin supplier view).
 */
export async function recordAcceptedReadingKept(
  // deno-lint-ignore no-explicit-any
  admin: any, supplierId: unknown, where: string, path: unknown,
): Promise<void> {
  try {
    const { error } = await admin.from('agent_actions').insert({
      agent: 'sales_engineer', kind: 'licence_new_file_being_read', status: 'auto_done', risk: 'low',
      title: `New licence file attached, being read — supplier #${supplierId}`,
      recommendation: 'New licence file attached and being read. The licence number, authority, name and expiry on file are the previously accepted reading, not this file\'s, until its reading lands. If it is not read within three days the ceo seat is asked to read it.',
      detail: { supplier_id: supplierId, where, path: path ?? null, fields_are: 'previously_accepted_reading', at: new Date().toISOString() },
      target_table: 'leads', target_id: String(supplierId),
    });
    if (error) console.error(JSON.stringify({ at: `${where}.accepted_reading_kept`, supplier: supplierId, error: error.message }));
  } catch (e) { console.error(JSON.stringify({ at: `${where}.accepted_reading_kept`, supplier: supplierId, error: String(e) })); }
}
