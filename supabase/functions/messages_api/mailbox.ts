// THE SUPPLIER'S MAILBOX, WITH ITS GATE AS DATA (15 Sep 2026, sales_engineer).
//
// The founder's spec for the supplier portal's Messages tab: a mailbox between the supplier and the
// CUSTOMER, opened only after the customer paid the reveal fee for that job; until then the tab says so.
// And, the same day: "later this will be a mobile app as well" — so the gate is decided HERE and returned
// as `gate`, not inferred by a client from an empty list.
//
// THE GATE IS THE REVEAL, AND IT IS ENFORCED IN THREE PLACES, NONE OF THEM A CLIENT:
//   1. this list is built only from the supplier's own transactions rows with revealed_at set — the
//      reveal itself — so a thread for an unrevealed job cannot appear;
//   2. messages_api `thread` and `send` re-check revealed(inquiry, supplier) on every call and answer
//      locked / 403 without one (index.ts);
//   3. public.messages and public.chat_threads have RLS on with no policy and no grant to anon or
//      authenticated (measured 15 Sep 2026), so a browser holding a supplier's JWT cannot read or write
//      either table directly; only this service-role function can.
// NO CUSTOMER IDENTITY IS IN THIS PAYLOAD, even after the reveal. The counterpart is 'customer'; the name,
// e-mail and phone the reveal paid for are served by supplier_api `projects`, keyed the same way.
//
// respond_by is the Supplier Agreement's 5-working-day rule (cl. 11 and 33): transactions.refund_deadline
// when refund_flow has stamped it, else fn_add_working_days(revealed_at, 5) — the same calendar
// supplier_api `projects` and the nudges use.

// deno-lint-ignore no-explicit-any
type Admin = any;
// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

export type MailboxGate = { open: boolean; reason: 'revealed' | 'no_revealed_job'; revealed_jobs: number };
export type MailboxThread = {
  inquiry_id: string; supplier_id: number; counterpart: 'customer';
  subject: string | null; category: string | null; emirate: string | null;
  revealed_at: string; respond_by: string | null; acknowledged_at: string | null;
  chat_status: string; last: string | null; last_at: string | null; unread: number;
};
export type Mailbox = { ok: true; role: 'supplier'; gate: MailboxGate; threads: MailboxThread[]; unread_total: number };

export function gateOf(revealedJobs: number): MailboxGate {
  return revealedJobs > 0 ? { open: true, reason: 'revealed', revealed_jobs: revealedJobs } : { open: false, reason: 'no_revealed_job', revealed_jobs: 0 };
}

export async function buildSupplierMailbox(admin: Admin, supId: number): Promise<Mailbox> {
  const { data: tx } = await admin.from('transactions')
    .select('inquiry_id,revealed_at,refund_deadline,supplier_ack_at,inquiries(category,emirate,summary)')
    .eq('supplier_id', supId).not('revealed_at', 'is', null).order('revealed_at', { ascending: false }).limit(100);
  // One job per inquiry: a second transactions row for the same job is the same conversation.
  const seen = new Set<string>();
  const jobs = ((tx || []) as Row[]).filter((t) => t.inquiry_id && !seen.has(String(t.inquiry_id)) && seen.add(String(t.inquiry_id)));
  const threads = await Promise.all(jobs.map(async (t): Promise<MailboxThread> => {
    const iq = String(t.inquiry_id);
    const [{ data: th }, { data: last }, { count }, respondBy] = await Promise.all([
      admin.from('chat_threads').select('status').eq('inquiry_id', iq).eq('supplier_id', supId).maybeSingle(),
      admin.from('messages').select('body,created_at').eq('inquiry_id', iq).eq('supplier_id', supId).eq('blocked', false).order('created_at', { ascending: false }).limit(1).maybeSingle(),
      admin.from('messages').select('id', { count: 'exact', head: true }).eq('inquiry_id', iq).eq('supplier_id', supId).eq('sender', 'customer').eq('read_by_supplier', false).eq('blocked', false),
      t.refund_deadline ? Promise.resolve(String(t.refund_deadline))
        : Promise.resolve(admin.rpc('fn_add_working_days', { p_from: t.revealed_at, p_days: 5 })).then((r: Row) => (r?.data as string) || null).catch(() => null),
    ]);
    const i = (t.inquiries || {}) as Row;
    return { inquiry_id: iq, supplier_id: supId, counterpart: 'customer', subject: i.summary || i.category || null, category: i.category || null, emirate: i.emirate || null,
      revealed_at: String(t.revealed_at), respond_by: respondBy, acknowledged_at: t.supplier_ack_at || null,
      // A revealed job's chat opens on first touch (index.ts), so 'none' here means "not opened yet", not closed.
      chat_status: th?.status || 'none', last: last?.body || null, last_at: last?.created_at || null, unread: count || 0 };
  }));
  threads.sort((a, b) => String(b.last_at || b.revealed_at).localeCompare(String(a.last_at || a.revealed_at)));
  return { ok: true, role: 'supplier', gate: gateOf(threads.length), threads, unread_total: threads.reduce((n, x) => n + x.unread, 0) };
}
