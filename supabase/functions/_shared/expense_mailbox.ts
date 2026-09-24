// The expenses mailbox, as the accountant reads it. Assigned: accountant (ledger 983, 24 Sep 2026).
//
// Two identity tests, and deliberately nothing looser (founder_instruction 890: no word matching):
//   * a message belongs to the mailbox when one of its recipients IS the mailbox address, or its local part is
//     'expenses' (Resend delivers to the address the forwarder typed, in any case);
//   * a subscription-register row belongs to a vendor when its vendor IS the vendor the receipt was booked
//     under, compared after trim and case-fold. The vendor itself was reasoned (reasoned_books.receiptVendor),
//     so this is the same company, not a similar word. Until 24 Sep this was a case-insensitive LIKE, in
//     which '_' and '%' in a vendor name matched any character.

export type InboundItem = { id?: unknown; to?: unknown; from?: unknown; created_at?: unknown };
export type MailboxMessage = { id: string; created_at: string; from: string };

const toList = (v: unknown): string[] =>
  (Array.isArray(v) ? v : [v]).map((x) => String(x || '').toLowerCase().trim()).filter(Boolean);

/** The messages addressed to the expenses mailbox and received at or after sinceMs. */
export function mailboxMessages(items: InboundItem[], mailbox: string, sinceMs: number): MailboxMessage[] {
  const box = mailbox.toLowerCase().trim();
  const out: MailboxMessage[] = [];
  for (const m of items) {
    const id = String(m.id || '');
    const at = Date.parse(String(m.created_at || ''));
    if (!id || !Number.isFinite(at) || at < sinceMs) continue;
    if (!toList(m.to).some((a) => a === box || a.split('@')[0] === 'expenses')) continue;
    out.push({ id, created_at: new Date(at).toISOString(), from: String(m.from || '').toLowerCase().trim() });
  }
  return out;
}

/** The register row for a vendor, by identity of the booked vendor name. */
export function sameVendor(a: string, b: string): boolean {
  return a.trim().toLowerCase() === b.trim().toLowerCase();
}

// deno-lint-ignore no-explicit-any
type Admin = { from: (t: string) => any };

/** The active subscription-register rows for this vendor (the register is small; read, then compare). */
export async function registerRowsFor(admin: Admin, vendor: string): Promise<{ id: number; expense_date: string | null }[]> {
  const { data } = await admin.from('expenses').select('id,vendor,expense_date').eq('active', true);
  return ((data || []) as { id: number; vendor: string; expense_date: string | null }[])
    .filter((r) => sameVendor(String(r.vendor || ''), vendor))
    .map((r) => ({ id: r.id, expense_date: r.expense_date }));
}
