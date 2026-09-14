// WHICH inbound_messages ROWS ARE A CUSTOMER'S OWN CORRESPONDENCE.
//
// Seen live 14 Sep 2026, customer portal /me -> Messages, signed in as the founder: the e-mail
// channel showed "Fw: Renewal receipt for order #4161152146 — [expense subscription] GoDaddy 40.95
// AED ... accountant historical sweep, Resend inbound id ...". messages_api joins inbound_messages
// on the signed-in address alone, and the founder's address is both a customer and the permitted
// receipt forwarder, so every receipt he forwarded to the accountant read as his customer mail.
//
// A row is back-office mail, never a customer thread, when ANY of these holds:
//   1. it was addressed to one of our internal mailboxes (expenses@ is the accountant's intake —
//      the same address resend_inbound and accountant each hold as EXPENSE_MAILBOX; docs@ and
//      supplier@ are supplier intake; management@ is the company's own). info@ is NOT internal:
//      it is where customers write to us.
//   2. owner_role is set — fn_receipt_hand_to_bookkeeper stamps it on rows a seat owns (6 Sep 2026).
//   3. its body carries the tag the accountant / receipt path writes: "[expense ...]",
//      "[REFUSED — ...]", "[HELD — ...]", "[receipt received but NOT booked ...]".
export const EXPENSE_MAILBOX = 'expenses@mail.quotesdone.com';
const INTERNAL_LOCALS = new Set(['expenses', 'docs', 'supplier', 'management']);
const OUR_DOMAIN = /^(?:mail\.)?quotesdone\.com$/;
const BACK_OFFICE_TAG = /^\[(?:expense|receipt|refused|held)\b/i;

export function isInternalMailbox(addr: unknown): boolean {
  return String(addr ?? '').toLowerCase().split(/[,;]/).some((a) => {
    const m = a.trim().match(/<?([^<>\s]+)@([^<>\s]+?)>?$/);
    if (!m) return false;
    return (m[1] + '@' + m[2]) === EXPENSE_MAILBOX || (OUR_DOMAIN.test(m[2]) && INTERNAL_LOCALS.has(m[1]));
  });
}

export function isCustomerCorrespondence(row: { to_email?: unknown; owner_role?: unknown; body?: unknown }): boolean {
  if (row.owner_role) return false;
  if (BACK_OFFICE_TAG.test(String(row.body ?? '').trim())) return false;
  return !isInternalMailbox(row.to_email);
}
