// THE JSON OBJECT A MODEL WROTE: the one reader (it_engineer, 17 Nov 2026; founder ledgers 1714 and 1715, simplification
// audit of 16 Nov 2026 item 11).
//
// Measured 17 Nov 2026 on origin/main 09e43394c (READ): 43 readers in supabase/functions took the JSON object out of a
// model's reply by hand, in six shapes: the whole reply, else the first '{' to the last '}' (`/\{[\s\S]*\}/` or
// indexOf/lastIndexOf, the same span); a ```json fence stripped first, at the ends or anywhere; the whole reply parsed
// first and handed on whatever it was (an array, a number) or only when it was an object; a raw line break inside a string
// escaped as a last try (ai_reply, 3 Nov 2026); and the whole reply or a fence around all of it, nothing else. No copy
// tolerated a trailing comma, so this reader does not either. Every variant and what became of it is in
// docs/engineering/duplicated-helpers.md, "The JSON object in a model's reply".
//
// What every caller gets: a plain object (never an array, a number, a string or null), or null. The empty answer a caller
// used to return ({} for some, a thrown error for one) stays at the call site as `?? {}`.
//
// Deliberately NOT here: a search of every '{' candidate for the one holding a key (supplier_trade_choice.answerJson),
// the nearest '{' before the last '}' (ai_gateway/confidence.ts reads a JSON tail after prose, where the first '{' is a
// quoted schema), and a first-fenced-block-anywhere rule (quote_compare keeps its one line). No model, no network, no env.
// Prevented by: model_json.test.ts.

export type JsonObject = Record<string, unknown>;

export type ReadJson = {
  /** The whole reply, or a ```json fence around all of it, and nothing else: no sentence before or after the object.
   *  For callers whose comment says "tolerates a fence; nothing else" (escalation_clock, review_decide, seat_deliberation,
   *  provider_signals). */
  exact?: boolean;
  /** When the reply as written parses as JSON, that value is the answer: a bare array or number is no object, and the
   *  object inside it is not looked for. For callers that parsed the whole reply first and passed its value on (the
   *  drawing redaction gates fail closed on anything but one object). */
  wholeDecides?: boolean;
  /** As a last try, a control character typed raw inside a string (a real line break) is escaped (ai_reply, 3 Nov 2026). */
  escapeControls?: boolean;
};

const FENCE = /^```(?:json)?\s*([\s\S]*?)\s*```$/;

function plainObject<T>(s: string): T | null {
  try { const v = JSON.parse(s); return v && typeof v === 'object' && !Array.isArray(v) ? v as T : null; } catch (_e) { return null; }
}

/** The first '{' to the last '}', or '' when there is no such span. */
export function outermostBraces(t: string): string {
  const a = t.indexOf('{'), b = t.lastIndexOf('}');
  return a >= 0 && b > a ? t.slice(a, b + 1) : '';
}

// A LINE BREAK TYPED INSIDE THE ANSWER STRING (customer_support, 3 Nov 2026; moved here from ai_reply.ts 17 Nov 2026). The reply
// rules ask for each phone number, e-mail and link on its own line; a model that writes that break as a real newline inside the
// JSON string (not \n) makes JSON.parse throw. Control characters INSIDE a string are escaped; outside strings they are
// whitespace and left alone.
export function controlsEscaped(t: string): string {
  let out = '', inStr = false, esc = false;
  for (const ch of t) {
    if (inStr && !esc && ch < ' ') { out += JSON.stringify(ch).slice(1, -1); continue; }   // "\n" -> the two characters \ and n
    if (inStr) { if (esc) esc = false; else if (ch === '\\') esc = true; else if (ch === '"') inStr = false; }
    else if (ch === '"') inStr = true;
    out += ch;
  }
  return out;
}

/**
 * The JSON object in a model's reply, or null. In order: the whole reply (inside a ```json fence around all of it, when
 * there is one) when it is an object; else the first '{' to the last '}' (a sentence or a fence around the object); else,
 * with escapeControls, that span with raw control characters inside strings escaped. A truncated object never parses and
 * is never repaired: a half answer is no answer.
 */
export function parseJson<T = JsonObject>(text: unknown, o: ReadJson = {}): T | null {
  const t = String(text ?? '').trim();
  if (!t) return null;
  const fenced = t.match(FENCE), body = fenced ? fenced[1] : t;
  if (o.exact) return plainObject<T>(body);
  if (o.wholeDecides) {
    let whole: unknown, parsed = false;
    try { whole = JSON.parse(t); parsed = true; } catch (_e) { /* not JSON as written */ }
    if (parsed) return whole && typeof whole === 'object' && !Array.isArray(whole) ? whole as T : null;
  }
  const span = outermostBraces(body);
  return plainObject<T>(body) ?? (span ? plainObject<T>(span) ?? (o.escapeControls ? plainObject<T>(controlsEscaped(span)) : null) : null);
}
