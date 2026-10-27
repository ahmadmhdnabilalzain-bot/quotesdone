// WHICH QUOTE THE CUSTOMER HAS (19 Oct 2026, with supplier withdraw_quote). A draft was never the
// customer's; a quotation its supplier WITHDREW before the reveal is no longer theirs either, so it leaves
// the portal list, the comparison, the supplier letters and the reveal door together. One list, one place:
// every read that used to say `status <> 'draft'` says this.
export const NOT_LIVE_QUOTE = ['draft', 'withdrawn'] as const;
/** For PostgREST: `.not('status', 'in', NOT_LIVE_QUOTE_IN)`. */
export const NOT_LIVE_QUOTE_IN = '(' + NOT_LIVE_QUOTE.map((s) => '"' + s + '"').join(',') + ')';
export const isLiveQuote = (status: unknown): boolean => !(NOT_LIVE_QUOTE as readonly string[]).includes(String(status ?? ''));
