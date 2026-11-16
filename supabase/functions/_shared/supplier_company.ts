// supplier_company.ts - WHO IN A SUPPLIER COMPANY IS WRITING, AND WHAT HE MAY DO (customer_support + sales_engineer, 16 Nov 2026;
// agent SUPPLIER_W2; SUPPLIER hole 4).
//
// A company was ONE e-mail (leads.claimed_by): the estimator's quotation from his own address was "unverified", the owner's
// WhatsApp was the only number known, and the invitation screen promised "ask them to add you" with no way to do it. Now the owner
// adds members (public.supplier_member: estimator = may quote; viewer = reads only), each signs in with his OWN e-mail code and is
// screened like the owner, and every door resolves him to the company through ONE reading, fn_supplier_company_of:
//   * the portal (supplier_api's door): a member acts for the company's address, so every action that scopes by claimed_by keeps
//     scoping by the company, and the role decides which actions he may take (memberMay below);
//   * an e-mail he sends (resend_inbound, email_triage): his address names the company;
//   * a WhatsApp number he confirmed with a code (fn_whatsapp_owner's member branch; fn_supplier_member_by_phone for his role).
// The rules here are permissions over FIXED action names, i.e. code deciding who may do what (rulings 1663/1664 keep that with code).
// prevented by: _shared/supplier_company.test.ts, supplier_api/team.test.ts
// deno-lint-ignore no-explicit-any
type Admin = any;

export type Role = 'owner' | 'estimator' | 'viewer';
export type Company = {
  role: Role; lead_id: number; company_email: string; member_email: string;
  member_name?: string | null; member_id?: number | null; company_name?: string | null; phone_confirmed?: boolean;
};
export type Invitation = { member_id: number; lead_id: number; company_name: string | null; role: Role; invited_by: string; invited_at: string };
export type CompanyReading = { company: Company | null; invitation: Invitation | null; held: { company_name: string | null; why: string } | null };

const NONE: CompanyReading = { company: null, invitation: null, held: null };

/** The company this address acts for (owner or member), its pending invitation, or a member held by the sanctions screen. */
export async function companyOf(admin: Admin, email: string | null | undefined): Promise<CompanyReading> {
  const e = String(email ?? '').trim().toLowerCase();
  if (!e) return NONE;
  const { data, error } = await admin.rpc('fn_supplier_company_of', { p_email: e });
  // the routine missing (before the apply) or failing: the address is read as it always was, as itself
  if (error || !data) return NONE;
  const j = data as Record<string, unknown>;
  if (j.role && j.lead_id) return { company: j as unknown as Company, invitation: null, held: null };
  if (j.invitation) return { company: null, invitation: j.invitation as Invitation, held: null };
  if (j.held) return { company: null, invitation: null, held: j.held as CompanyReading['held'] };
  return NONE;
}

// What only the owner does: the company's record, its papers, its money, its team and its account.
export const OWNER_ONLY = new Set([
  'accept_terms', 'claim', 'create_company', 'save_profile', 'save_settings', 'capability_confirm', 'services_answer', 'services_resolve',
  // upload_url signs a path for the licence, profile or catalogue, so it is the owner's as process_docs is (review supplierw2).
  'services_rewrite', 'services_save_rewrite', 'transcribe_service_note', 'upload_url', 'process_docs', 'pay_registration', 'dispute_charge',
  'set_availability', 'leave_quotes', 'remove_work', 'correction_decide',
  'member_invite', 'transfer_start', 'transfer_confirm', 'close_account', 'reopen_account',
]);
// What a viewer may do: read.
export const VIEWER_MAY = new Set([
  'me', 'search', 'inbox', 'inquiries_list', 'inquiry_detail', 'inquiry_documents', 'inquiry_pdf', 'quote_pdf', 'receipt_pdf', 'receipts',
  'projects', 'settings', 'services_state', 'services_questions', 'capability_state', 'standing', 'template_list', 'review_thread',
  'support_rating_due', 'team', 'member_remove', 'member_phone_code', 'account_closure', 'warm',
]);

export type May = { ok: true } | { ok: false; code: 'owner_only' | 'read_only'; error: string };

/** May a person in this role take this portal action? The owner may take every action. */
export function memberMay(role: Role, action: string): May {
  if (role === 'owner') return { ok: true };
  if (role === 'viewer' && !VIEWER_MAY.has(action)) {
    return { ok: false, code: 'read_only', error: 'Your access to this company is read only. Ask the owner to make you an estimator to quote.' };
  }
  if (OWNER_ONLY.has(action)) {
    return { ok: false, code: 'owner_only', error: 'Only the company\'s owner can do this. Ask the owner, or ask him to hand you the company (Settings, Team).' };
  }
  return { ok: true };
}

// What a member may ask for by e-mail or WhatsApp (the kinds _shared/supplier_instruction.ts reads).
const OWNER_KINDS = new Set(['remove_work', 'answer_yes', 'answer_no', 'close_account', 'close_confirm', 'close_cancel']);
const ESTIMATOR_KINDS = new Set(['not_for_me', 'available', 'confirm_figure', 'job_question', 'customer_silent', 'paid_leads']);
/** May this role give this instruction? A viewer gives none; a paid-leads offer is only recorded, so anyone's is kept. */
export function memberMayInstruct(role: Role, kind: string): boolean {
  if (role === 'owner') return true;
  if (kind === 'paid_leads') return true;
  if (role === 'viewer') return false;
  return ESTIMATOR_KINDS.has(kind) && !OWNER_KINDS.has(kind);
}

/** The sender of an e-mail, resolved to a company: its claimed address, or an active member's own address. */
export async function mailSenderCompany(admin: Admin, from: string): Promise<Company | null> {
  return (await companyOf(admin, from)).company;
}

/** The person behind a WhatsApp number: a member (his role) or, when none, the owner of the company the number names. */
export async function waSenderRole(admin: Admin, phone: string): Promise<{ role: Role; email: string | null; name: string | null } > {
  try {
    const { data } = await admin.rpc('fn_supplier_member_by_phone', { p_phone: phone });
    const m = data as { role?: Role; email?: string; name?: string } | null;
    if (m?.role) return { role: m.role, email: m.email ?? null, name: m.name ?? null };
  } catch (_e) { /* the routine missing: the number is the owner's, as before */ }
  return { role: 'owner', email: null, name: null };
}
