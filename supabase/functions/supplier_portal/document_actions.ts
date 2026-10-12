// document_actions — the rules behind Replace and Remove on a supplier's fixed documents
// (founder instruction 524, 21 Sep 2026): every document offers View / Download / Replace / Remove;
// Replace keeps the previous version; Remove hides, never destroys, and is REFUSED on a sealed record.
//
// Pure functions, so supplier_portal/index.ts stays the door and this file is what
// document_actions.test.ts drives.
//
// WHERE A VERSION LIVES. public.doc_versions (entity_type, entity_id, version, snapshot) already
// exists with public._next_docver() as its counter — the estate's own document-history table, whose
// readers were retired on 4 Sep 2026 for having no surface. This gives it one: entity_type
// 'supplier_document', entity_id '<lead id>:<kind>', snapshot = the row the column held before the
// change plus the event. The stored file is never deleted (Dropbox backup keeps it too:
// fn_backup_source_registry lists every leads.*_doc_path column).
//
// WHAT IS SEALED, for the fixed kinds a supplier holds:
//   * a mandatory-six document (trade licence, company profile — REQUIRED_DOC_KEYS) of an APPROVED
//     supplier. Removing it would demote them on the spot (trg_leads_e0_mandatory_six_gate), so the
//     honest answer is to refuse and say why; a supplier who is pending / action_required may remove
//     and re-upload. Replace is always allowed: the new file lands before the old one goes.
//   * a sanctioned party never reaches here — supplier_portal's one gate above the action switch
//     refuses every action with SANCTIONED_REFUSAL (instruction 516).
//   * the signed terms and paid invoices are not documents in DOC_KINDS at all: the terms are
//     leads.signed_terms_path written by compliance_archive, receipts are rendered per due. Neither
//     has a Remove door on the server; the portal shows the four actions and refuses the two by name.

export type RemoveRefusal = { code: 'mandatory_of_approved' | 'unknown_kind' | 'nothing_on_file'; message: string; message_ar: string };

export function removeRefusal(a: { kind: string; known: boolean; onFile: boolean; required: boolean; approval_status: string | null | undefined }): RemoveRefusal | null {
  if (!a.known) return { code: 'unknown_kind', message: 'That document type does not exist.', message_ar: 'لا يوجد نوع مستند بهذا الاسم.' };
  if (!a.onFile) return { code: 'nothing_on_file', message: 'There is no file on record to remove.', message_ar: 'لا يوجد ملف محفوظ يمكن إزالته.' };
  if (a.required && a.approval_status === 'approved') {
    return { code: 'mandatory_of_approved',
      message: 'This document is one of the six your approval rests on. It cannot be removed while your company is approved — upload a replacement instead. If it must come off, contact support and your approval will be paused first.',
      message_ar: 'هذا المستند أحد المستندات الستة التي يقوم عليها اعتماد شركتكم، ولا يمكن إزالته ما دامت الشركة معتمدة؛ ويمكنكم رفع مستند بديل عوضًا عنه. وإن تعيّنت إزالته، فيُرجى التواصل مع فريق الدعم، وسيُعلَّق الاعتماد أولًا.' };
  }
  return null;
}

export type VersionSnapshot = { event: 'replaced' | 'removed'; kind: string; path: string; name: string | null; expiry: string | null; at: string };

/** The doc_versions row for what a column held before a replace or a remove. */
export function versionRow(leadId: number, snap: VersionSnapshot, version: number) {
  return { entity_type: 'supplier_document', entity_id: `${leadId}:${snap.kind}`, version, snapshot: snap,
           checksum: null, changed_fields: [snap.event === 'removed' ? 'removed' : 'path'] };
}

/** What the upload answer says about an expiry, so the portal can show the read date for confirmation. */
export type ExpiryNote =
  | { kind: string; expiry: string; source: 'text' | 'ai'; needs_confirm: boolean; typed: string | null }
  | { kind: string; expiry: null; source: null; needs_confirm: false; typed: string | null; unread: true; message?: string };
