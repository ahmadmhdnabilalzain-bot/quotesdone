// receipt_parse — DETERMINISTIC extraction of a forwarded vendor receipt (6 Sep 2026).
//
// Why this exists: resend_inbound booked a forwarded SaaS receipt only after an ai_gateway extraction
// call. Since the paid hold began on 15 Aug that call returns nothing, so every receipt the founder
// forwarded fell through to the supplier-document path and landed on HIS screen as "Inbox — awaiting
// your reply" and "Reviews pending" — four of them by 6 Sep, expense_entries at 0 since 15 Aug.
// A Stripe/Orb/Apify receipt is a fixed-shape document: the vendor is the original sender's domain,
// the amount is next to "Amount paid" / "Total" / "payment of", the date is on the "Paid" or "Sent:"
// line. Plain parsing reads all four real receipts; the model is the fallback, not the path.
//
// Pure: no I/O, no Deno APIs, so scripts/backfill_unbooked_receipts.ts runs the same code the edge
// function runs. The only company data it consults is passed in (knownCadence from `expenses`).

export type ParsedReceipt = {
  vendor: string;
  amount: number;
  currency: string;
  date: string;            // YYYY-MM-DD
  period: 'monthly' | 'annual' | 'one_off';
  recurring: boolean;
  basis: string;           // which patterns decided it — written into the expense note
  vat: number | null;      // VAT the receipt STATES; null when it states none. Never computed.
  trn: string | null;      // the vendor's 15-digit UAE TRN when the receipt prints one
};

// The vendor is DERIVED from the original sender's domain (billing@apify.com -> Apify). This map only
// exists for names whose casing or wording the domain label cannot produce; it is a constant rather
// than a table because it carries no company decision — it is spelling — and the same six names
// already sit as literals in expense_entries.vendor, which dedup matches on. Add a line when a new
// vendor's domain label is not its name.
const VENDOR_NAMES: Record<string, string> = {
  openrouter: 'OpenRouter', godaddy: 'GoDaddy', openai: 'OpenAI', cloudconvert: 'CloudConvert',
  dubaipay: 'DubaiPay', withorb: 'Orb', stripe: 'Stripe',
};
const CURRENCIES = 'USD|AED|EUR|GBP|SGD|SAR';
const MONTHS: Record<string, number> = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, sept: 9, oct: 10, nov: 11, dec: 12 };

/**
 * FORMATTING IS NOT CONTENT (9 Sep 2026).
 *
 * The Google Play receipt the founder forwarded on 13 Aug 2026 prints its total as
 *   `Total: <RLM>26.99 د.إ.<RLM>/month`   and   `(Includes VAT of <RLM>1.29 د.إ.<RLM>)`
 * — a real, stated, AED figure. Every pattern below missed it twice over: U+200F RIGHT-TO-LEFT MARK
 * is not \s, so `Total:\s*<figure>` never reached the digits, and the dirham is written in the
 * Arabic abbreviation `د.إ.` rather than the three ASCII letters CURRENCIES knows. So the receipt
 * was held as unreadable, and so would EVERY UAE-issued invoice printing the same symbol — which is
 * most of them. That is not a receipt we cannot read; it is one we were not looking at properly.
 *
 * This function only removes bidi control characters (which carry no meaning to a parser) and
 * rewrites the printed dirham symbol as the ISO code for the same currency. It supplies nothing the
 * document does not state: a receipt with no currency mark still yields no currency, and the amount
 * patterns still refuse a bare number.
 */
export function normalizeReceiptText(s: string): string {
  return String(s == null ? '' : s)
    .replace(/\u00a0/g, ' ')                                          // nbsp
    .replace(/[\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, '')   // bidi marks and embeddings
    .replace(/د\s*\.?\s*إ\s*\.?/g, 'AED ');                    // the dirham as UAE documents print it
}

function num(s: string): number { return Number(String(s).replace(/,/g, '')); }
function ymd(y: number, m: number, d: number): string | null {
  if (!(y >= 2000 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31)) return null;
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

/** The ORIGINAL sender of a forwarded email: the first "From: ... <addr>" line in the body, else the forwarder. */
export function originalSender(body: string, from: string): string {
  const m = body.match(/^\s*(?:>?\s*)?From:\s*([^\n]+)$/im);
  if (m) {
    const addrs = m[1].match(/[\w.+-]+@[\w.-]+\.\w+/g);
    if (addrs && addrs.length) return addrs[addrs.length - 1].toLowerCase(); // "x on behalf of Y <y>": Y is the vendor
  }
  return String(from || '').toLowerCase();
}

export function vendorFromAddress(addr: string): string | null {
  const dom = (addr.split('@')[1] || '').toLowerCase();
  if (!dom) return null;
  const labels = dom.split('.').filter(Boolean);
  if (labels.length < 2) return null;
  // registrable label: the one before the public suffix (co.uk / com.au style handled by length)
  const last = labels[labels.length - 1]; const prev = labels[labels.length - 2];
  const label = (['co', 'com', 'org', 'net'].includes(prev) && last.length === 2 && labels.length >= 3) ? labels[labels.length - 3] : prev;
  if (['gmail', 'outlook', 'hotmail', 'yahoo', 'icloud', 'live', 'quotesdone'].includes(label)) return null;
  return VENDOR_NAMES[label] || (label.charAt(0).toUpperCase() + label.slice(1));
}

export function parseAmount(text: string): { amount: number; currency: string; basis: string } | null {
  const t = normalizeReceiptText(text);
  // a figure with its currency before it ("$20.00", "USD 21.10", "AED 77.50") or after it ("29 USD")
  const money = `(?:(${CURRENCIES})\\s?\\$?|\\$|US\\$)?\\s?([\\d,]+(?:\\.\\d{1,2})?)(?:\\s?(${CURRENCIES}))?`;
  // 1. a labelled total wins: "Amount paid $20.00", "Total $30.00", "payment of 29 USD", "$35.63 has been charged"
  const labelled: [string, RegExp][] = [
    // 9 SEP 2026 — the \b on `total` and `paid` is load-bearing, not tidiness. Without it "total"
    // matched inside SUBTOTAL, so a UAE tax invoice printing "Subtotal AED 100 / VAT 5 / Total AED
    // 105" booked the PRE-VAT figure as the amount charged: every VAT-bearing invoice understated,
    // silently, with a confident basis string saying labelled:total. Caught by pdf_text.test.ts.
    ['amount_paid', new RegExp(`\\bamount\\s+paid\\s*:?\\s*${money}`, 'i')],
    ['total', new RegExp(`\\btotal\\s*(?:amount|due|paid)?\\s*:?\\s*${money}`, 'i')],
    ['payment_of', new RegExp(`\\b(?:payment|charge)\\s+of\\s+${money}`, 'i')],
    ['charged', new RegExp(`${money}\\s+(?:has been|was)\\s+charged`, 'i')],
    ['paid', new RegExp(`\\b(?:paid|charged)\\s*:?\\s*${money}`, 'i')],
  ];
  for (const [name, re] of labelled) {
    const m = t.match(re);
    // the currency must be stated (prefix, suffix or a $ sign): "Total 3" is not money
    if (m && num(m[2]) > 0 && (m[1] || m[3] || /\$/.test(m[0]))) return { amount: num(m[2]), currency: (m[1] || m[3] || 'USD').toUpperCase(), basis: 'labelled:' + name };
  }
  // 2. the first currency-marked figure ("$20.00", "USD 21.10", "AED 77.50") — a Stripe receipt's headline
  const bare = new RegExp(`(?:(${CURRENCIES})\\s?|\\$|US\\$)([\\d,]+\\.\\d{2})\\b(?:\\s?(${CURRENCIES}))?`, 'i');
  const m = t.match(bare);
  if (m && num(m[2]) > 0) return { amount: num(m[2]), currency: (m[1] || m[3] || 'USD').toUpperCase(), basis: 'first_currency_figure' };
  return null;
}

export function parseDate(text: string): { date: string; basis: string } | null {
  const t = normalizeReceiptText(text);
  const monthNum = (s: string) => MONTHS[s.slice(0, 4).toLowerCase()] ?? MONTHS[s.slice(0, 3).toLowerCase()];
  // 1. "Paid August 15, 2026" / "Paid on Aug 27, 2026"
  let m = t.match(/\bpaid(?:\s+on)?\s+([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})/i);
  if (m) { const d = ymd(+m[3], monthNum(m[1]), +m[2]); if (d) return { date: d, basis: 'paid_line' }; }
  // 2. the forwarded "Sent: Sunday, 16 August 2026 02:02:09" (Outlook) / "Date: Sun, 16 Aug 2026" (Gmail)
  m = t.match(/^\s*(?:Sent|Date):\s*(?:[A-Za-z]+,\s*)?(\d{1,2})\s+([A-Za-z]{3,9})\.?\s+(\d{4})/im);
  if (m) { const d = ymd(+m[3], monthNum(m[2]), +m[1]); if (d) return { date: d, basis: 'sent_line' }; }
  m = t.match(/^\s*(?:Sent|Date):\s*(?:[A-Za-z]+,\s*)?([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})/im);
  if (m) { const d = ymd(+m[3], monthNum(m[1]), +m[2]); if (d) return { date: d, basis: 'sent_line' }; }
  // 3. any ISO date in the body
  m = t.match(/\b(20\d{2})-(\d{2})-(\d{2})\b/);
  if (m) { const d = ymd(+m[1], +m[2], +m[3]); if (d) return { date: d, basis: 'iso_in_body' }; }
  return null;
}

// UAE SPECIFICS (9 Sep 2026). A UAE tax invoice prints the supplier's 15-digit TRN and a 5% VAT
// line. Both are READ, never derived: VAT is not total/21 and a TRN is not any 15-digit run in the
// document. A receipt that states neither has neither, and the ledger books the whole amount to the
// expense account — which is correct, because we cannot reclaim input VAT we have no evidence of.
/** The vendor's Tax Registration Number, only when the document labels it. */
export function parseTrn(text: string): string | null {
  const m = normalizeReceiptText(text).match(/\b(?:TRN|Tax\s+Registration\s+(?:No\.?|Number)|VAT\s+Reg(?:istration)?\.?\s*(?:No\.?|Number)?)\s*[:#]?\s*([\d][\d\s-]{13,22})/i);
  if (!m) return null;
  const d = m[1].replace(/\D/g, '');
  return d.length === 15 ? d : null;
}

/** The VAT the receipt STATES, in the same currency as the total. null when it states none. */
export function parseVat(text: string, total: number): { amount: number; basis: string } | null {
  const t = normalizeReceiptText(text);
  const money = `(?:(?:${CURRENCIES})\\s?\\$?|\\$|US\\$)?\\s?([\\d,]+(?:\\.\\d{1,2})?)`;
  // `of` (9 Sep 2026): a Google Play receipt writes "(Includes VAT of AED 1.29)". Without it the
  // stated tax was invisible and the whole gross went to the expense account, so input VAT the
  // company IS entitled to reclaim was never debited to 1150. Still READ, never derived.
  const pats: [string, RegExp][] = [
    ['vat_5pct', new RegExp(`\\bVAT\\s*\\(?\\s*5\\s*%\\s*\\)?\\s*:?\\s*${money}`, 'i')],
    ['vat_amount', new RegExp(`\\bVAT(?:\\s+amount)?(?:\\s+of)?\\s*:?\\s*${money}`, 'i')],
    ['tax_5pct', new RegExp(`\\btax\\s*\\(?\\s*5\\s*%\\s*\\)?\\s*:?\\s*${money}`, 'i')],
    ['tax_amount', new RegExp(`\\btax(?:\\s+amount)?(?:\\s+of)?\\s*:?\\s*${money}`, 'i')],
  ];
  for (const [name, re] of pats) {
    const m = t.match(re);
    if (!m) continue;
    const v = num(m[1]);
    // it must be a plausible tax on THIS total: positive, below it, and not the total restated
    if (v > 0 && v < total) return { amount: v, basis: name };
  }
  return null;
}

export function parsePeriod(text: string, knownCadence?: string | null): { period: ParsedReceipt['period']; basis: string } {
  if (/\b(annual|yearly|per year|\/\s?yr|12 months)\b/i.test(text)) return { period: 'annual', basis: 'text:annual' };
  if (/\b(subscription|monthly|per month|\/\s?mo\b|renew(al|ed|s)?|your plan)\b/i.test(text)) return { period: 'monthly', basis: 'text:monthly' };
  // a Stripe line-item period "Aug 29–Sep 28, 2026" is a one-month billing cycle
  if (/\b[A-Za-z]{3,9}\s+\d{1,2}\s?[–-]\s?[A-Za-z]{3,9}\s+\d{1,2},\s+\d{4}\b/.test(text)) return { period: 'monthly', basis: 'text:month_range' };
  if (knownCadence === 'annual' || knownCadence === 'monthly') return { period: knownCadence, basis: 'expenses.cadence' };
  return { period: 'one_off', basis: 'default' };
}

/**
 * Returns null when no amount can be read — the caller then falls back to the model (which under the
 * paid hold returns nothing) and hands the email to the bookkeeper. Never guesses an amount.
 */
export function parseReceipt(input: { from: string; subject: string; body: string; knownCadence?: string | null; today?: string }): ParsedReceipt | null {
  const body = String(input.body || ''); const subject = String(input.subject || '');
  const text = subject + '\n' + body;
  const amt = parseAmount(body) || parseAmount(subject);
  if (!amt) return null;
  const sender = originalSender(body, input.from);
  const vendor = vendorFromAddress(sender) || vendorFromAddress(input.from);
  if (!vendor) return null;
  const dt = parseDate(text);
  const date = dt?.date || input.today || new Date().toISOString().slice(0, 10);
  const per = parsePeriod(text, input.knownCadence);
  const vat = parseVat(text, amt.amount);
  const trn = parseTrn(text);
  return {
    vendor, amount: amt.amount, currency: amt.currency, date, period: per.period,
    recurring: per.period !== 'one_off',
    basis: `vendor=${sender} amount=${amt.basis} date=${dt?.basis || 'today'} period=${per.basis}`
      + (vat ? ` vat=${vat.basis}` : '') + (trn ? ' trn=read' : ''),
    vat: vat?.amount ?? null,
    trn,
  };
}
