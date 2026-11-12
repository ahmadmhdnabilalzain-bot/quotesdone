// THE READER'S SHARED PIECES: how the model is called, how a document is cut into parts, how a quote is found in the text it came from,
// and how a JSON answer is read. Seat: sales_engineer (the reading); it_engineer (the build). Since 13 Oct 2026 (rulings 1175, 1177, 890).
//
// THE ONE-CALL CHOOSER IS GONE (12 Nov 2026, ruling 1647; docs/reports/2026-11-12-supplier-service-profiling.md). It read every document
// with the whole catalogue (55,000-69,000 prompt tokens) and 16 precision rules in one prompt, took up to three readings and a majority
// vote, then a second look that kept or dropped each TRADE. Measured on the 12 hard profiles that day: 85 of 114 stated services found
// (47% on the broad, vague or glossy ones), 22 of 22 partner services dropped, 4 of 12 companies "held" for ever, no question asked.
// It is replaced by the reading in two steps, supplier_profile_reading.ts (reader supplier_doc_trades@5), which uses what is left here.
// Its tests went with it; the hard-profile set (scripts/e2e/services_hard_profiles/) is the measurement that replaced it.

// THE MODEL READS EVERYTHING CODE READ (3 Nov 2026, sales_engineer; founder: "a supplier attaches a company profile of 300 pages
// and the sales agent must go through it properly"). This was 40,000 characters: measured by scripts/e2e/document_reading_qualification.ts,
// a 300-page text profile (270,000 characters) whose services are stated on page 160 as division pages, with no offer heading or
// offer sentence for offerText to bring forward, was cut at about page 45 and its three trades never reached the model. The cap is
// now the reader's own text cap, so nothing code read is withheld; a document is cut into CHUNK_CHARS requests, CHOICE_CONCURRENCY
// at a time. What it costs (ai_cost_log, 30 days to 3 Nov 2026: 1,254 supplier_trade_choice calls, AED 0.0027 each on average):
// a 270,000-character profile is 20 chunks x 2-3 readings + one check, about AED 0.15, once per supplier.
export const CHOICE_TEXT_MAX = 400_000;   // = doc_read/types.ts LIMITS.maxTextChars (asserted in long_document_reading.test.ts)
export const CHOICE_CONCURRENCY = 5;
/** fn over items, at most n at a time, results in order. */
export async function inPool<T, R>(items: T[], n: number, fn: (x: T, i: number) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => { while (next < items.length) { const i = next++; out[i] = await fn(items[i], i); } }));
  return out;
}
// The route (model_policy). QD_CHOICE_TASK_CLASS lets the accuracy harness measure on another class's model before the
// new row is applied at merge; production never sets it.
export function choiceTaskClass(): string {
  // read when a request is built, never at import: a test or a caller without env access still loads this module
  // deno-lint-ignore no-explicit-any
  try { return (globalThis as any).Deno?.env?.get('QD_CHOICE_TASK_CLASS') || 'supplier_trade_choice'; } catch { return 'supplier_trade_choice'; }
}

export const CHUNK_CHARS = 14_000;
/** The text cut into chunks of at most CHUNK_CHARS, on line breaks. */
export function textChunks(text: string, max = CHUNK_CHARS): string[] {
  const out: string[] = []; let cur = '';
  for (const line of String(text ?? '').split('\n')) {
    if (cur && cur.length + line.length + 1 > max) { out.push(cur); cur = ''; }
    cur += (cur ? '\n' : '') + line.slice(0, max);
  }
  if (cur.trim() || !out.length) out.push(cur);
  return out;
}
/** The parts of a document's text, one per request. One definition, read by
 *  scripts/e2e/document_reading_qualification.ts, so what the qualification says reached the model is what reaches it. */
export const modelParts = (text: string): string[] => textChunks(String(text ?? '').slice(0, CHOICE_TEXT_MAX));
export const modelText = (text: string): string => modelParts(text).join('\n');
/** Letters and digits only, lower case, one space: how a quote is found in the text it came from.
 *  THE LAM-ALEF ORDER IS NOT EVIDENCE (3 Nov 2026, sales_engineer; document_reading_qualification, real profile C05): pdf.js gives the
 *  ligature back swapped inside a word ("مقاوال" for "مقاولا"), the model quotes the word as written, and the quote was refused as
 *  "not in the document" on 3 of 3 runs. The key reads both orders as one, on both sides; the stored quote is unchanged. */
export const quoteKey = (s: string) => String(s ?? '').toLowerCase().normalize('NFKC').replace(/[^\p{L}\p{N}]+/gu, ' ').replace(/لا/g, 'ال').trim();

/** The JSON object of a model answer that holds `key`: code fences stripped, every {...} candidate tried from the last. */
export function answerJson(content: string, key: string): Record<string, unknown> | null {
  const s = String(content ?? '').replace(/```(?:json)?/gi, '');
  const starts: number[] = []; for (let i = s.indexOf('{'); i >= 0; i = s.indexOf('{', i + 1)) starts.push(i);
  for (const a of starts) {
    for (let b = s.lastIndexOf('}'); b > a; b = s.lastIndexOf('}', b - 1)) {
      try { const o = JSON.parse(s.slice(a, b + 1)); if (o && typeof o === 'object' && key in o) return o; } catch { /* next */ }
      if (b - a > 200_000) break;
    }
  }
  return null;
}

/** Whether a quote is in a text, word for word, by quoteKey. A word hyphenated across a line break in the source ("Compa-" then
 *  "ny", common in OCR) is read whole, in the text and in the quote (N07, 19 Oct 2026). A PDF breaks a sentence across lines, and
 *  the model may quote across the break: every line of the quote must then be in the text, each word for word (a line of fewer
 *  than 3 letters is not evidence and is skipped). Also how supplier_doc_trades.readTogether finds which document a quote is in. */
export function quoteFinder(text: string): (quote: string) => boolean {
  const dehyph = (x: string) => String(x ?? '').replace(/(\p{L})-\s*\r?\n\s*(\p{L})/gu, '$1$2');
  const hay = ' ' + quoteKey(dehyph(text)) + ' ';
  return (quote: string) => {
    const q = quoteKey(dehyph(quote)), parts = dehyph(quote).split(/\r?\n/).map(quoteKey).filter((x) => x.length >= 3);
    return q.length >= 3 && (hay.includes(' ' + q + ' ') || (parts.length > 1 && parts.every((x) => hay.includes(' ' + x + ' '))));
  };
}

/** One request to ai_gateway with the cred_fn_ai credential (115 s a call; the gateway keeps 3 s back). A NETWORK failure (no HTTP
 *  answer at all: "fetch failed") is tried twice more after a pause - measured on the real set, 2 of 29 profiles lost both of their
 *  tries to it in one run. An HTTP error is not retried here. Shared by both readers (supplier_profile_reading.liveProfileReader). */
export async function gatewayCall(cred: string, req: Record<string, unknown>, headers?: Record<string, string>): Promise<{ ok: true; content: string } | { ok: false; error: string }> {
  let last = '';
  for (const pause of [0, 2_000, 6_000]) {
    if (pause) await new Promise((res) => setTimeout(res, pause));
    try {
      const r = await fetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/ai_gateway', {
        method: 'POST', headers: { 'Content-Type': 'application/json', ...(headers ?? {}) }, signal: AbortSignal.timeout(120_000),
        body: JSON.stringify({ __secret: cred, client_timeout_ms: 115_000, ...req }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok || j?.ok === false) return { ok: false, error: `model unavailable (${r.status}): ${String(j?.error || j?.detail || '').slice(0, 160)}` };
      if (j?.truncated === true || j?.finish_reason === 'length') return { ok: false, error: 'the answer was cut off' };
      return { ok: true, content: String(j?.content ?? '') };
    } catch (e) { last = String((e as Error)?.message || e).slice(0, 160); }
  }
  return { ok: false, error: 'model unreachable: ' + last };
}
