// resend_inbound: the expenses mailbox, finance mailbox names and two small helpers the receipt path uses. Moved out of index.ts unchanged (9 Nov 2026).


// The founder confirmed this address on 9 Sep 2026: the accountant "collects expenses from the
// email expenses@mail.quotesdone.com". Same mail. subdomain as docs@mail.quotesdone.com.
export const EXPENSE_MAILBOX = 'expenses@mail.quotesdone.com';
export async function sha256hex(s: string){ const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)); return Array.from(new Uint8Array(d)).map((b)=>b.toString(16).padStart(2,'0')).join(''); }
export const dbxSafe = (s: string) => String(s||'').replace(/[\\/:*?"<>|\r\n\t]+/g,' ').replace(/\s+/g,' ').trim();
// WHICH MAILBOX the sender addressed is structured data, the one fact the sender chose: mail to a finance mailbox
// is expense mail. What any OTHER email is -- a receipt, a statement, or a supplier's document -- is MEANING, and
// is reasoned (_shared/reasoned_books.ts documentKind); the subject/sender regex that decided it (isReceiptish) is
// gone (23 Sep 2026, founder_instruction 886-903, decision point accountant.resend_receiptish).
export const FINANCE_BOXES = new Set(['receipts','receipt','billing','expenses','expense','finance','accounts','accounting','fin','subscriptions','subscription','bills','bill']);
