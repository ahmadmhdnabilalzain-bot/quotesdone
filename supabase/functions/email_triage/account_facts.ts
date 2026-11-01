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
  if (!jobs.length) return head + ' No jobs have been sent to them yet. ' + SEPARATE_COMPANY_FACT;
  return SEPARATE_COMPANY_FACT + '\n' + head + ' Jobs sent to them, newest first, with THEIR OWN quote only (never another supplier\'s quote or the customer\'s identity):\n'
    + jobs.slice(0, 15).map((j) => `- Job #${j.inquiry_id}: ${j.category || 'job'}${j.emirate ? ' in ' + j.emirate : ''}${j.sent_at ? ', sent ' + day(j.sent_at) : ''}, job status ${j.status || 'unknown'}, their quote: ${j.my_quote_status || 'not submitted'}`).join('\n');
}

// AN INVITED SUPPLIER WHO SAYS "YES" IS NOT YET A REGISTERED SUPPLIER (sales_engineer, 28 Oct 2026, ledger 1375:
// "tomorrow morning i need suppliers receiving invitations and registering"). Traced that night: the invitation (variant
// A, no link) asks "Would your company like to receive ... requests?"; the reply reaches resend_inbound through the
// Microsoft 365 reader, and email_triage answers it. fn_mail_sender_known calls ANY lead 'supplier' (20k directory rows,
// claimed or not), and the facts below then said "THE SENDER IS A REGISTERED SUPPLIER ... No jobs have been sent to
// them yet" -- to a company with no account, with no word of how to register. The yes was answered with a falsehood
// and a dead end. A lead that has not claimed its listing now gets the truth and its own registration link: the same
// /portal?t=<claim_token> link the old invitation carried, which names the company and opens on "Create account".
// The reply goes only to the address the mail came from (fn_inbox_send), which is the lead's own address, so the link
// reaches nobody the invitation itself would not have reached.
export const SITE = 'https://quotesdone.com';
// WHAT REGISTRATION NEEDS IS THE SIX, AND NOBODY REGISTERS FOR THEM (it_engineer audit of the supplier journey, 28 Oct
// 2026, founder ledger 1401). Replayed through the real reply path that day, eight supplier replies: every answer listed
// the steps without the company profile and without accepting the supplier terms (two of the founder's six, ruling of
// 7 Sep 2026; fn_supplier_mandatory_six refuses approval without them), and every answer that explained registration
// ended "reply with the trades you cover and our team will set up the page for you". Nothing performs that: the
// invite.reply handoff it files is answered by fn_sales_engineer_takes_invite_reply with 'waiting' and nothing more,
// and the six need the supplier's own verified e-mail and mobile, uploads and acceptance in any case. So the facts name
// the six and forbid the offer. The live invitation (variant A) makes no such offer; the WhatsApp draft still does.
export const SIX_ITEMS = 'the company\'s licensed name, a UAE mobile number verified with a code, the verified work e-mail, '
  + 'the trade licence (uploaded), the company profile (uploaded) and their acceptance of the supplier terms';
export const NO_SETUP_FOR_THEM = 'Never offer to register them, to set up their company page or to do any step for them, and never say '
  + 'our team will: only they can verify their e-mail and mobile, upload their documents and accept the terms.';
// A SECOND COMPANY (2 Nov 2026, customer_support; a supplier asked to register its subsidiary). Read from
// supplier_api/create_company.ts and the indexes on leads, measured on production: an account manages one company
// (company_exists), an address holding a claimed lead is refused (email_already_registered; uq_leads_email_lower,
// leads_claimed_by_lower_uidx), and a claimed licence or name cannot repeat. Nothing links two companies to one login.
export const SEPARATE_COMPANY_FACT = 'IF THEY ASK TO REGISTER ANOTHER COMPANY (a subsidiary or sister company with its own trade licence): it registers as its own '
  + 'separate company at quotesdone.com/portal with "Create account", with its own trade licence and details and a different work e-mail that has no '
  + 'account with us, because one e-mail manages exactly one company and it cannot be added under their existing account. '
  + `It needs all six of: ${SIX_ITEMS}. Any registration link given above is for the company named above only, never for the other company. ` + NO_SETUP_FOR_THEM;
export function unregisteredSupplierFacts(company: string, link: string): string {
  return `THE SENDER IS A SUPPLIER COMPANY WE INVITED${company ? ' (' + company + ')' : ''}, matched on their exact e-mail address. `
    + 'THEY HAVE NOT REGISTERED YET: never call them registered and never mention jobs or quotes sent to them. '
    + 'If they say yes, want to join or ask how, tell them registration is free for our first 1,000 suppliers and takes a few minutes: '
    + `open their company's own registration link ${link} , choose "Create account" with their work e-mail and type the 6-digit code we e-mail them. `
    + `To be verified they need all six of: ${SIX_ITEMS}. The trades they cover are confirmed in the Services tab of their portal. `
    + 'Give the link exactly as written, on its own line. ' + NO_SETUP_FOR_THEM + ' ' + SEPARATE_COMPANY_FACT;
}
// An UNVERIFIED sender who is a lead: no account is read (the spoof rule below), and the sign-in line alone would send
// a supplier with no account to a sign-in box. Both routes are named, without a personal link.
export const SUPPLIER_SIGN_IN_FACT = 'THE SENDER\'S E-MAIL COULD NOT BE VERIFIED AS COMING FROM THEIR ADDRESS, so no account details may be given. '
  + 'If they ask about their jobs, quotes or account, say that for their security they can see them by signing in at quotesdone.com/portal. '
  + 'If they are not registered yet and want to join, they can register at quotesdone.com/portal with "Create account" and their work e-mail; '
  + `to be verified they need all six of: ${SIX_ITEMS}. ` + NO_SETUP_FOR_THEM + ' ' + SEPARATE_COMPANY_FACT;

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
      const { data: leads } = await admin.from('leads').select('id,company_name,claimed,claim_token').ilike('email', e.replace(/[\\%_]/g, (c) => '\\' + c)).limit(2);
      if (!leads || leads.length !== 1) return '';
      const sup = leads[0];
      if (!sup.claimed) return unregisteredSupplierFacts(String(sup.company_name || ''), sup.claim_token ? `${SITE}/portal?t=${sup.claim_token}` : `${SITE}/portal`);
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
  return senderVerified(raw) ? await accountFacts(admin, email, relation) : (relation === 'supplier' ? SUPPLIER_SIGN_IN_FACT : SIGN_IN_FACT);
}
