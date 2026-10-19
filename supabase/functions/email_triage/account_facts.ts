// THE SENDER'S OWN ACCOUNT, ON E-MAIL TOO (customer_support, 19 Oct 2026). A registered customer e-mailed about their
// request and was told we cannot see its status, while the portal and WhatsApp read it. The sender is matched on the
// EXACT address (fn_mail_sender_known's rule), and only that account's rows are read: its own inquiries, each one's
// status and quotes count (fn_customer_stats, the portal's own overview read), or for a supplier the jobs sent to it and
// its OWN quote on each. Never another party's name, contact, price or case text (#1441). Unknown sender: nothing.
// deno-lint-ignore no-explicit-any
type Db = any;

export interface CustomerInq { id: unknown; category?: string | null; emirate?: string | null; status?: string | null; quotes_count?: number | null; created_at?: string | null }
export interface SupplierJob { inquiry_id: unknown; category?: string | null; emirate?: string | null; status?: string | null; my_quote_status?: string | null; sent_at?: string | null }

const day = (s?: string | null) => (s ? String(s).slice(0, 10) : '');

export function customerFacts(inqs: CustomerInq[]): string {
  if (!inqs.length) return 'THE SENDER IS A REGISTERED CUSTOMER (matched on their exact e-mail address). They have no requests yet.';
  return 'THE SENDER IS A REGISTERED CUSTOMER (matched on their exact e-mail address). Their own requests, newest first '
    + '(answer about their requests from this; never say you cannot see their status):\n'
    + inqs.slice(0, 15).map((i) => `- Request #${i.id}: ${i.category || 'request'}${i.emirate ? ' in ' + i.emirate : ''}${i.created_at ? ', posted ' + day(i.created_at) : ''}, status ${i.status || 'unknown'}, ${Number(i.quotes_count || 0)} quote(s) received`).join('\n');
}

export function supplierFacts(company: string, jobs: SupplierJob[]): string {
  const head = `THE SENDER IS A REGISTERED SUPPLIER${company ? ' (' + company + ')' : ''}, matched on their exact e-mail address.`;
  if (!jobs.length) return head + ' No jobs have been sent to them yet.';
  return head + ' Jobs sent to them, newest first, with THEIR OWN quote only (never another supplier\'s quote or the customer\'s identity):\n'
    + jobs.slice(0, 15).map((j) => `- Job #${j.inquiry_id}: ${j.category || 'job'}${j.emirate ? ' in ' + j.emirate : ''}${j.sent_at ? ', sent ' + day(j.sent_at) : ''}, job status ${j.status || 'unknown'}, their quote: ${j.my_quote_status || 'not submitted'}`).join('\n');
}

/** The verified sender's own records as reply facts, or '' for anyone else (or when a read fails). */
export async function accountFacts(admin: Db, email: string, relation: unknown): Promise<string> {
  const e = String(email || '').trim().toLowerCase();
  if (!e) return '';
  try {
    if (relation === 'customer') {
      const { data: custs } = await admin.from('customers').select('id').ilike('email', e.replace(/[\\%_]/g, (c) => '\\' + c)).limit(2);
      if (!custs || custs.length !== 1) return '';   // exactly one account, or nothing
      const { data: stats, error } = await admin.rpc('fn_customer_stats', { p_customer: custs[0].id });
      if (error) return '';
      return customerFacts(((stats as { inquiries?: CustomerInq[] } | null)?.inquiries) || []);
    }
    if (relation === 'supplier') {
      const { data: leads } = await admin.from('leads').select('id,company_name').ilike('email', e.replace(/[\\%_]/g, (c) => '\\' + c)).limit(2);
      if (!leads || leads.length !== 1) return '';
      const sup = leads[0];
      const { data: m } = await admin.from('inquiry_matches').select('inquiry_id,sent_at,inquiries(category,emirate,status)')
        .eq('supplier_id', sup.id).order('sent_at', { ascending: false }).limit(15);
      const ids = (m || []).map((r: { inquiry_id: unknown }) => r.inquiry_id);
      const { data: q } = ids.length ? await admin.from('quotes').select('inquiry_id,status').eq('supplier_id', sup.id).in('inquiry_id', ids) : { data: [] };
      const mine = new Map((q || []).map((r: { inquiry_id: unknown; status: string }) => [String(r.inquiry_id), r.status]));
      return supplierFacts(String(sup.company_name || ''), (m || []).map((r: Db) => ({ inquiry_id: r.inquiry_id, sent_at: r.sent_at,
        category: r.inquiries?.category, emirate: r.inquiries?.emirate, status: r.inquiries?.status, my_quote_status: mine.get(String(r.inquiry_id)) ?? null })));
    }
  } catch (_e) { /* an unread account leaves the reply ungrounded, never the mail unanswered */ }
  return '';
}

// SPOOF-PROOF (review of #1498): a From header is free text. The account is read only when resend_inbound recorded
// that the receiving server authenticated the From domain (raw.sender_authenticated, an aligned DMARC/DKIM/SPF pass).
// Missing or false: no account data, and the reply invites them to sign in to see their requests.
export const SIGN_IN_FACT = 'THE SENDER\'S E-MAIL COULD NOT BE VERIFIED AS COMING FROM THEIR ADDRESS, so no account details may be given. '
  + 'If they ask about their requests, quotes or account, say that for their security they can see the status by signing in to their account on quotesdone.ae.';
export function senderVerified(raw: unknown): boolean {
  return !!raw && typeof raw === 'object' && (raw as { sender_authenticated?: unknown }).sender_authenticated === true;
}
/** The facts for this mail: the account when the sender is verified, the sign-in line when a known sender is not. */
export async function mailFacts(admin: Db, email: string, relation: unknown, raw: unknown): Promise<string> {
  if (relation !== 'customer' && relation !== 'supplier') return '';
  return senderVerified(raw) ? await accountFacts(admin, email, relation) : SIGN_IN_FACT;
}
