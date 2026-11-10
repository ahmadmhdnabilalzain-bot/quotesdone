// WHO MAY CHANGE SOMETHING BY WHATSAPP (it_engineer, 3 Nov 2026, release qualification).
// A founder setting change and a supplier's re-price are WRITES driven by a message, so the message must be proven:
//  - founder_directive: only a webhook whose X-Twilio-Signature verified, from the founder's number. The internal JSON
//    path sets trusted=true with a caller-chosen From (replay tooling), and the provenance lookup proves only that a
//    MessageSid came from that number, not that the body is the one he sent; neither may change a setting.
//  - supplier_directive: only a webhook Twilio vouched for (signature or provenance, never the internal JSON path), from
//    the number's confirmed supplier (fn_supplier_apply_change scopes the quotation to that supplier in SQL), and only an
//    amount the supplier wrote: the classifier's reading of the message is not enough, since the message can instruct it.
// prevented by: wa_inbound/directive_gate.test.ts

export function founderDirectiveAllowed(o: { audience: string; signatureVerified: boolean }): boolean {
  return o.audience === 'founder' && o.signatureVerified === true;
}

export function supplierDirectiveAllowed(o: { audience: string; internalCaller: boolean }): boolean {
  return o.audience === 'supplier' && o.internalCaller === false;
}

// Arabic-Indic and Persian digits, and the Arabic thousands sign U+066C, written as escapes: code, not Arabic copy.
const western = (s: string) => s.replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x660)).replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x6f0));
const toNumber = (s: string): number | null => {
  let t = western(s).replace(/[,\u066C\s]/g, '');
  if (/^\d{1,3}(?:\.\d{3})+$/.test(t)) t = t.replace(/\./g, '');   // 12.500 is a thousands dot, as written in the Gulf
  const m = t.match(/^(\d+(?:\.\d+)?)(k)?$/i);
  return m ? Number(m[1]) * (m[2] ? 1000 : 1) : null;
};

/** The classifier's amount, only when the supplier's own message states that amount (thousands commas, spaces, dots and
 *  the Arabic thousands sign, a "k" and Arabic-Indic digits allowed); null otherwise. The SQL routine scopes it to their own
 *  quotation; which of two numbers they wrote is the price is the classifier's reading of their own words. */
export function amountInOwnWords(amount: unknown, body: string): string | null {
  const want = toNumber(String(amount ?? '').replace(/aed|dhs?|dirhams?|\s/gi, ''));
  if (want == null || want <= 0) return null;
  const said = western(String(body || '')).match(/\d(?:[\d,\u066C.]|\s(?=\d{3}\b))*k?/gi) ?? [];
  return said.some((s) => toNumber(s.replace(/[.,\u066C]+$/, '')) === want) ? String(want) : null;
}

/** Every amount the supplier's own message states, as the bare number amountInOwnWords would accept (largest first). The
 *  replay of a re-price the model could not read chooses among THESE only (reprice_outage.ts): no amount is invented. */
export function amountsInOwnWords(body: string): string[] {
  const said = western(String(body || '')).match(/\d(?:[\d,\u066C.]|\s(?=\d{3}\b))*k?/gi) ?? [];
  const out = new Set<number>();
  for (const s of said) { const n = toNumber(s.replace(/[.,\u066C]+$/, '')); if (n != null && n > 0) out.add(n); }
  return [...out].sort((a, b) => b - a).slice(0, 8).map(String);
}
