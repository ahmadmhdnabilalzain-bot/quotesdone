// A MODEL CHOOSES A SUPPLIER'S TRADES FROM OUR OWN CODES, AND PROVES EACH ONE WITH THE DOCUMENT'S OWN LINE.
// Seat: sales_engineer (the reading); it_engineer (the build). 13 Oct 2026, decided by the coordinator on the founder's
// rulings 1175 (OpenRouter is always on), 1177 (every attachment is read) and 890 (no word matching).
//
// WHY. Measured on 29 real UAE company profiles and catalogues (ACCURACY_real_profiles.md, PR #1404): code that maps a
// company's words onto 213 trade codes - exact code, or gte-small meaning confirmed by the trade's own words - got 7/29
// files exact with 37 wrong trades. Aliases deciding by themselves: 227 wrong. A model choosing from the codes on the
// offer text code had found: 15/24 exact, 8 wrong, at a fraction of a cent a profile. A profile is read once per
// supplier, so the strongest sensible model is used (model_policy 'supplier_trade_choice').
//
// WHAT CODE STILL DOES, AND WHAT IT CHECKS. Code finds the text (the PDF's words, the offer sections of a long profile,
// a catalogue's headings and statements, or the services a vision model read off a picture). The model is given every
// active trade with its DEFINITION - its name and the services it covers - and must answer with codes from that list
// only, each with the exact line of the document that justifies it and a reason. Code then refuses:
//   * a code that is not an active trade (exact or none - never a "nearest" code);
//   * a code without a quoted line, or whose quote is not in the text it was given (word for word, case and spacing
//     aside) - a trade the document does not say is a trade the model made up.
// The model never sees, and so can never act on, anything but the document's words and our codes.
// If the model cannot be reached the document proposes NOTHING and says why (choice: 'unavailable'): a supplier is
// never given a trade the model did not prove, and the next upload or re-read tries again.

export type TradeDef = { code: string; label: string; services: string[] };
/** `quotes`: every proven line for the code, strongest first, never more than three lines. The first is `quote`. */
export type TradeChoice = { code: string; quote: string; reason: string; quotes?: string[] };
export type ChoiceResult =
  | { ok: true; trades: TradeChoice[]; rejected: { code: string; why: string }[] }
  | { ok: false; error: string; held?: { readings: { code: string; quote: string }[][] } };
/** The text in, the proven choices out. Injected for tests; liveTradeChooser is the edge function's. */
/** `company`: the name the supplier registered - whose work counts (a group's own brochure vs one company's profile). */
export type TradeChooser = (text: string, kind: 'profile' | 'catalogue', company?: string | null) => Promise<ChoiceResult>;
const companyLine = (company?: string | null) => company ? `The company registered as: ${String(company).slice(0, 160)}\n\n` : '';

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

/** The stable part of the prompt (cacheable): the rules and every trade's definition. */
export function choiceSystem(defs: TradeDef[]): string {
  const list = defs.map((d) => `${d.code} = ${d.label}${d.services.length ? ' (covers: ' + d.services.join('; ') + ')' : ''}`).join('\n');
  return `You read the text of a UAE company's profile or product catalogue and name the trades the company ITSELF offers as its business - the work it does or the goods it supplies.

Use ONLY these trade codes. Each line is: code = name (covers: the services of that trade).
${list}

RULES
1. A code is named only when the text says the company does that work or supplies those goods. Exact trade or none: if the company's work is not one of these trades, name nothing for it - never the nearest code.
2. Never from: the company's or another company's NAME, a client or project owner, another contractor on a project, a certificate or standard it holds (ISO, LEED), a policy, its staff, its equipment or vehicles, its offices, a sentence about quality, safety or values, a vision, mission or goal statement (what it hopes to offer), or a tool or method it uses in its own work (survey drones, design software) - only what it sells as a service or product. Work it does INSIDE a project of another trade names its own trade (plumbing done inside a hotel construction project is plumbing, not general contracting).
3. A line that lists the company's own works as its title or tagline (for example under or beside its name: "Tiling, Gypsum Partitions & Ceiling Works") states what it does: name every trade it lists.
4. Whose work it is. The company is the one the profile is about. Its own factory, workshop or division counts (an in-house "steel fabrication yard" is steel fabrication). Work done by a SISTER, partner or associated company ("our sister company", "by M/s ...", "a group company") is that other company's, not this one's - unless the whole document is the group's own brochure, the group itself being the company, and then each group company's described work counts.
5. For EVERY code give "quotes": one to three objects {"text": a line copied EXACTLY, word for word, from the text, "form": what that line IS in the document - "list_item" (an item of a list of the company's services, activities or products), "heading" (a heading or section title the company gives a service), "title" (the company's name line, tagline or stated line of business), "capability_claim" (a sentence about what the company or its staff are able to do, their skills, experience or expertise, in any language), or "list_intro" (a line that only introduces a list)}. Give the lines - the lines that most directly name that service or product itself (for example "supply and installation of glass shopfronts", not a general sentence about the company), strongest first; when the company lists the service in a list of its own services, a title line or a services heading, include that line - and "reason": one short sentence. A code you cannot quote is not named.
6. Prefer the specific trade the text names (fire fighting, HVAC, plumbing, electrical) and add mep_general only when the text offers combined MEP / electromechanical contracting.
7. MAIN LINES OF BUSINESS ONLY. Read the whole text and name every trade the document presents as a line of business of the company's own: in its title or tagline, in its list of services, activities, divisions or products, or as a section or heading of its own. Do NOT name a trade from an item mentioned in passing, a sub-item or component of another service, a material or product it uses in its own work, a project description, or one word inside a long sentence. When you are not sure a trade is a main line of business, leave it out: a trade offered only in passing is not required.
8. What a line IS before what it says: a contact mailbox or department name ("leasing@...", "Procurement Department"), a word in the company's name or in its logo artwork (a slogan such as "Build Smart" printed under a logo), a caption, or a heading of the brochure's own layout names no trade. A METHOD of delivering a service (working at height from cradles, night shifts, prefabrication off site) is not a trade of its own: the trade is the work done with it (cleaning done from a cradle is cleaning). The exception is a company whose business IS the access itself - it presents itself as a rope-access, BMU or gondola provider: facade_access_maintenance covers that access service, named beside the work it carries out. A product feature or a material used in its main work (the light fittings installed as part of a shop fit-out) is that main work's trade.

9. A list's HEADING says whose work its items are. Items printed under a heading that names a trade (under "PLUMBING WORKS": water heaters, booster pumps) are that heading trade's work: name another trade for such an item only when the company also offers it as a service of its own elsewhere in the text. A heading or label that is itself a trade's name ("Civil:", "Joinery -") names THAT trade for the items listed after it when those items fall within that trade's definition (buildings and structures under "Civil"); when the items under it are other trades' works (tiling, painting and partitions under a "CIVIL" label), name the items' own trades, not the heading's. An MEP or electromechanical heading is the exception: the specific trades it lists ("MEP: HVAC, electrical and plumbing services") are each named, with mep_general.
11. GOODS ARE NOT WORKS. In a CATALOGUE every trade named is a goods or supply trade. A product is named by what it IS, never by a word in its name: "thermal insulation blocks" are concrete blocks (building_materials), "cable trays" and trunking are cable containment (electrical), not cables. A company that sells or trades goods (a catalogue, a trading or building-materials company) is named by the goods trades whose definitions cover what it sells (for example building_materials, electrical_wholesale, plastics_pipes, hand_power_tools), never by an installation or contracting trade (plumbing, electrical, hvac, painting) unless the text says it installs or carries out that work.
14. A MAIN TRADE'S OWN SCOPE. Items a company lists as the scope of its main trade - ordinary parts of that work, such as landscape lighting, pergolas or plant nurseries in a landscaping company's list, or ceilings and partitions in a fit-out company's list - are that main trade's work, not trades of their own, unless the company gives the item its own heading or section as a separate business.
12. ONE ITEM, ONE TRADE. When the definitions of two trades both cover the same item (shade structures, kitchen cabinets), name only the trade whose own listed services name it most closely, and only once.
13. A quote names the service itself, from a services or products list, a heading or a title. A line that only introduces a list ("Our main activities are on:", "We offer the following") names nothing: quote the list item. A sentence about what the company or its staff are able to do ("our skilled team is competent to carry out civil and structural jobs") is not an offer and names no trade.
10. Design is named by what is designed. design_consultancy is architectural or interior design (its definition). Design or engineering of the company's own trade's works (a pool builder designing pools, an MEP contractor designing its MEP installations, a contractor's "contracting, engineering and design services") is part of that trade, not design_consultancy or engineering_consultancy - unless the company sells architectural, interior or engineering design as a consultancy service in its own right.

Return STRICT JSON only: {"trades":[{"code":"...","quotes":[{"text":"...","form":"list_item"}],"reason":"..."}]}`;
}

export function choiceRequest(text: string, kind: 'profile' | 'catalogue', defs: TradeDef[], subject: unknown, company?: string | null) {
  return { fn: 'supplier_doc_trades', task_class: choiceTaskClass(), subject: subject ?? null, temperature: 0,
    sys_stable: choiceSystem(defs), sys: '',
    input: [{ role: 'user', content: [{ type: 'text', text: `${companyLine(company)}The company's ${kind === 'catalogue' ? 'catalogue' : 'profile'} text:\n\n${text.slice(0, CHOICE_TEXT_MAX)}` }] }] };
}

/** The forms of line a trade may be quoted from (the model labels each quote; review of #1483). */
export const QUOTE_FORMS = new Set(['list_item', 'heading', 'title']);
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
/** The parts of a document's text the chooser hands the model, one per request. One definition, read by liveTradeChooser and by
 *  scripts/e2e/document_reading_qualification.ts, so what the qualification says reached the model is what reaches it. */
export const modelParts = (text: string): string[] => textChunks(String(text ?? '').slice(0, CHOICE_TEXT_MAX));
export const modelText = (text: string): string => modelParts(text).join('\n');
/** Codes a reading NAMED: proposed, or proposed with a quote code could not find. */
const namedBy = (r: Extract<ChoiceResult, { ok: true }>) => new Set([...r.trades.map((t) => t.code), ...r.rejected.filter((x) => x.why.startsWith('the quote is not in the document')).map((x) => x.code)]);
/** A third reading is needed when one of two readings is empty or they named different codes. */
export function needsThird(a: Extract<ChoiceResult, { ok: true }>, b: Extract<ChoiceResult, { ok: true }>): boolean {
  const x = namedBy(a), y = namedBy(b);
  return !a.trades.length || !b.trades.length || x.size !== y.size || [...x].some((c) => !y.has(c));
}
/** The codes at least two readings named, each proven by a quote one of them gave. One reading alone never passes a code:
 *  fewer than two non-empty readings, or no code with two votes, is null - the document is held (review of #1483). */
export function majority(rs: Extract<ChoiceResult, { ok: true }>[]): Extract<ChoiceResult, { ok: true }> | null {
  const full = rs.filter((r) => r.trades.length);
  if (full.length < 2) return null;
  const count = new Map<string, number>();
  for (const r of full) for (const c of namedBy(r)) count.set(c, (count.get(c) ?? 0) + 1);
  const keep = new Set([...count].filter(([, n]) => n >= 2).map(([c]) => c));
  if (!keep.size) return null;
  const merged = mergeChoices(full.map((r) => ({ trades: r.trades.filter((t) => keep.has(t.code)), rejected: [] })));
  // two votes for a code whose every quote code refused prove nothing: held, never ok and empty (review of #1483)
  if (!merged.trades.length) return null;
  const once = [...new Set(full.flatMap((r) => r.trades.map((t) => t.code)))].filter((c) => !keep.has(c));
  return { ok: true, trades: merged.trades, rejected: [...full.flatMap((r) => r.rejected), ...once.map((c) => ({ code: c, why: 'named by one reading only' }))] };
}
/** Proven choices of several chunks as one: a code once, its quotes (up to 3) gathered; refusals kept. */
export function mergeChoices(rs: { trades: TradeChoice[]; rejected: { code: string; why: string }[] }[]): Extract<ChoiceResult, { ok: true }> {
  const by = new Map<string, TradeChoice>();
  for (const r of rs) for (const t of r.trades) {
    const was = by.get(t.code);
    if (!was) { by.set(t.code, { ...t, quotes: [...(t.quotes ?? [t.quote])] }); continue; }
    for (const q of t.quotes ?? [t.quote]) if (was.quotes!.length < 3 && !was.quotes!.includes(q)) was.quotes!.push(q);
  }
  const trades = [...by.values()].sort((a, b) => a.code.localeCompare(b.code));
  return { ok: true, trades, rejected: rs.flatMap((r) => r.rejected).filter((x) => !by.has(x.code)) };
}

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
const answerHead = (c: string) => JSON.stringify(String(c ?? '').slice(0, 120));

/** The model's answer, checked by code: active codes only, each with a quote that is in the text. */
export function checkChoice(content: string, text: string, defs: TradeDef[]): ChoiceResult {
  const parsed = answerJson(content, 'trades') as { trades?: unknown } | null;
  if (!parsed || !Array.isArray(parsed.trades)) return { ok: false, error: 'the answer was not the JSON asked for: ' + answerHead(content) };
  const codes = new Set(defs.map((d) => d.code));
  // a word hyphenated across a line break in the source ("Compa-" then "ny", common in OCR) is read whole, in the text
  // and in the quote (N07, 19 Oct 2026)
  const dehyph = (x: string) => String(x ?? '').replace(/(\p{L})-\s*\r?\n\s*(\p{L})/gu, '$1$2');
  const hay = ' ' + quoteKey(dehyph(text)) + ' ';
  const trades: TradeChoice[] = [], rejected: { code: string; why: string }[] = [];
  for (const t of parsed.trades as Record<string, unknown>[]) {
    const code = String(t?.code ?? '').trim(), reason = String(t?.reason ?? '').trim().slice(0, 300);
    // "quotes" (a list of proven lines since 19 Oct 2026, never more than three lines. Or the older single "quote"): every line is proven on its own, and the code stands
    // when at least one is in the text. One quote only was the H08 miss: the model quoted its weakest line ("complimentary
    // 3D design") and the second look, seeing only that line, dropped a service the profile prints as its own heading.
    // Each quote is {text, form}: the MODEL says what the line is in the document (review of #1483 - no word list decides it).
    const items = (Array.isArray(t?.quotes) ? t.quotes as unknown[] : [t?.quote]).map((x) => (x && typeof x === 'object'
      ? { text: String((x as Record<string, unknown>).text ?? '').trim(), form: String((x as Record<string, unknown>).form ?? '').trim() }
      : { text: String(x ?? '').trim(), form: '' })).filter((x) => x.text).slice(0, 3);
    const given = items.map((x) => x.text);
    if (!codes.has(code)) { rejected.push({ code, why: 'not an active trade code' }); continue; }
    if (!given.some((x) => quoteKey(x).length >= 3)) { rejected.push({ code, why: 'no quoted line' }); continue; }
    // A PDF breaks a sentence across lines, and the model may quote across the break: every line of the quote must
    // then be in the text, each word for word (a line of fewer than 3 letters is not evidence and is skipped).
    const inText = (quote: string) => {
      const q = quoteKey(dehyph(quote)), parts = dehyph(quote).split(/\r?\n/).map(quoteKey).filter((x) => x.length >= 3);
      return q.length >= 3 && (hay.includes(' ' + q + ' ') || (parts.length > 1 && parts.every((x) => hay.includes(' ' + x + ' '))));
    };
    // A trade is quoted from a services or products list, a heading or a title (QUOTE_FORMS), as the model labels the line,
    // never from a capability claim (M04: "... skilled workers competent to carry out technical jobs & civil, structural ...")
    // or a line that only introduces a list (N04: "Our main activities are on :"). The line must also be in the document.
    const inDoc = items.filter((x) => inText(x.text));
    const proven = inDoc.filter((x) => QUOTE_FORMS.has(x.form) && !/:\s*$/.test(x.text)).map((x) => x.text);
    if (!inDoc.length) { rejected.push({ code, why: `the quote is not in the document: "${given[0].slice(0, 80)}"` }); continue; }
    if (!proven.length) { rejected.push({ code, why: `the quote's form is not a services list, heading or title (${inDoc.map((x) => x.form || 'no form given').join(', ')}): "${inDoc[0].text.slice(0, 80)}"` }); continue; }
    if (trades.some((x) => x.code === code)) continue;
    trades.push({ code, quote: proven[0].slice(0, 240), quotes: proven.map((x) => x.slice(0, 240)), reason });
  }
  return { ok: true, trades: trades.sort((a, b) => a.code.localeCompare(b.code)), rejected };
}

/** Every active trade with its services, read once per request. */
// deno-lint-ignore no-explicit-any
export async function tradeDefs(admin: any): Promise<TradeDef[] | null> {
  const [{ data: t, error: e1 }, { data: s, error: e2 }] = await Promise.all([
    admin.from('taxonomy_trade').select('code,label').eq('active', true).order('code'),
    admin.from('taxonomy_trade_service').select('trade_code,label_en,active,sort').order('sort'),
  ]);
  if (e1 || e2 || !t?.length) return null;
  const by = new Map<string, string[]>();
  for (const r of (s || []) as { trade_code: string; label_en: string; active: boolean | null }[]) {
    if (r.active === false) continue;
    if (!by.has(r.trade_code)) by.set(r.trade_code, []);
    by.get(r.trade_code)!.push(r.label_en);
  }
  return (t as { code: string; label: string }[]).map((r) => ({ code: r.code, label: r.label, services: by.get(r.code) ?? [] }));
}

/** The chooser an edge function uses: ai_gateway with the cred_fn_ai credential. `headers` carries a rehearsal tag. */
// deno-lint-ignore no-explicit-any
export function liveTradeChooser(admin: any, opts: { subject?: unknown; headers?: Record<string, string> } = {}): TradeChooser {
  let defs: TradeDef[] | null = null, cred: string | null = null;
  // One retry of each step: measured on the 29 real files, 1 of 28 answers came back as prose instead of JSON.
  const twice = async <T extends { ok: boolean }>(f: () => Promise<T>) => { const a = await f(); return a.ok ? a : await f(); };
  return async (text, kind, company) => {
    try {
      defs ??= await tradeDefs(admin);
      if (!defs) return { ok: false, error: 'the trade list could not be read' };
      if (!cred) { const { data } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_ai').maybeSingle(); cred = data?.value ?? null; }
      if (!cred) return { ok: false, error: 'no model credential' };
      const d = defs;
      // CHUNKED (19 Oct 2026): one request over a long document hit the gateway's CPU cap (N05, HTTP 546) and its 55 s
      // wall deadline (H02, gateway_deadline). Each chunk is chosen on its own, in parallel, and the proven choices merged;
      // one second look then judges the merged list against the whole text.
      const parts = modelParts(text);
      // A later chunk is read with the document's opening (title, about, services) as context, so a list item is judged
      // as part of the company it belongs to; only the chunk itself may be quoted.
      const head = parts.length > 1 ? parts[0].slice(0, 2500) : '';
      // one reading of the whole document: every chunk read once, merged; an error only when a chunk could not be read twice
      const readOnce = async (): Promise<ChoiceResult> => {
        // A CHUNK THE GATEWAY COULD NOT ANSWER IN TIME IS READ IN HALVES (3 Nov 2026, sales_engineer; document_reading_qualification on
        // the real set: an 85 MB group brochure's 14,000-character chunks hit the gateway's deadline, HTTP 502 gateway_deadline, on 3 of 5
        // runs, and the whole document proposed nothing). Twice at most, so a chunk is never cut below a quarter.
        const readPart = async (p: string, i: number, depth = 0): Promise<ChoiceResult> => {
          const r = await twice(async () => { const g = await gateway(choiceRequest(i && head ? `[The document opens with this, for context only - do not quote it:]\n${head}\n[The part to read and quote from:]\n${p}` : p, kind, d, opts.subject, company)); if (g.ok && (globalThis as any).Deno?.env?.get('QD_CHOICE_DEBUG')) console.error('CHOICE_RAW', i, String(g.content).slice(0, 1500)); return g.ok ? checkChoice(g.content, p, d) : g; });
          if (r.ok || depth >= 2 || p.length < 4000 || !/gateway_deadline|546|cut off|timed? ?out/i.test(r.error)) return r;
          const halves = await Promise.all(textChunks(p, Math.ceil(p.length / 2) + 200).map((h) => readPart(h, i || 1, depth + 1)));
          return halves.find((x) => !x.ok) ?? mergeChoices(halves as Extract<ChoiceResult, { ok: true }>[]);
        };
        const each = await inPool(parts, CHOICE_CONCURRENCY, (p, i) => readPart(p, i));
        const bad = each.find((x) => !x.ok);
        return bad ?? mergeChoices(each as Extract<ChoiceResult, { ok: true }>[]);
      };
      // AGREEMENT BY MAJORITY (stability runs on the fresh blind set, 19 Oct 2026). Two readings had to agree, so a core trade
      // one reading missed was dropped (M08 prefab_buildings, M09 electrical_wholesale), and a scan both readings answered
      // with nothing lost every trade (M12). Now a third reading is taken whenever the two disagree or one came back empty,
      // and a code goes forward when at least two of the readings named it; three empty readings hold the document.
      const [ra, rb] = await Promise.all([readOnce(), readOnce()]);
      let readings = [ra, rb].filter((x) => x.ok) as Extract<ChoiceResult, { ok: true }>[];
      if (!readings.length) return ra;
      if (readings.length < 2 || needsThird(readings[0], readings[1])) {
        const rc = await readOnce();
        if (rc.ok) readings = [...readings, rc];
      }
      const chosen = majority(readings);
      if (!chosen) return { ok: false, error: 'the readings did not agree on any trade: held for the sales engineer',
        held: { readings: readings.map((r) => r.trades.map((t) => ({ code: t.code, quote: t.quote }))) } };
      if (!chosen.ok || !chosen.trades.length) return chosen;
      const kept = await twice(async () => { const g = await gateway(verifyRequest(chosen.trades, d, opts.subject, text, company)); return g.ok ? checkVerify(g.content, chosen) : g; });
      return kept;
    } catch (e) { return { ok: false, error: String((e as Error)?.message || e).slice(0, 200) }; }
  };
  // A NETWORK failure (no HTTP answer at all: "fetch failed") is tried twice more after a pause - measured on the
  // real set, 2 of 29 profiles lost both of their tries to it in one run. An HTTP error is not retried here.
  async function gateway(req: Record<string, unknown>): Promise<{ ok: true; content: string } | { ok: false; error: string }> {
    let last = '';
    for (const pause of [0, 2_000, 6_000]) {
      if (pause) await new Promise((res) => setTimeout(res, pause));
      try { return await gatewayOnce(req); } catch (e) { last = String((e as Error)?.message || e).slice(0, 160); }
    }
    return { ok: false, error: 'model unreachable: ' + last };
  }
  async function gatewayOnce(req: Record<string, unknown>): Promise<{ ok: true; content: string } | { ok: false; error: string }> {
    const r = await fetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/ai_gateway', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...(opts.headers ?? {}) }, signal: AbortSignal.timeout(120_000),
      body: JSON.stringify({ __secret: cred, client_timeout_ms: 115_000, ...req }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok || j?.ok === false) return { ok: false, error: `model unavailable (${r.status}): ${String(j?.error || j?.detail || '').slice(0, 160)}` };
    if (j?.truncated === true || j?.finish_reason === 'length') return { ok: false, error: 'the answer was cut off' };
    return { ok: true, content: String(j?.content ?? '') };
  }
}

// THE SECOND LOOK (13 Oct 2026). On the 29 real files the chooser named every core trade, but each run also named one
// or two the company does not sell, a different one each time, with its own reason saying why not ("IT department
// installs and maintains network systems (internal)", "began as a wooden doors trading company ... only as history").
// So each proposed code, with its quote and reason, is put to the model again on its own, as a check: keep only a trade
// the quote shows the company SELLS NOW under that trade's definition. Code then keeps only what the check kept, so a
// trade is proposed only when the document quotes it and two separate readings agree. If the check cannot be read the
// document proposes nothing (held), never the unchecked list.
export function verifySystem(defs: TradeDef[]): string {
  const list = defs.map((d) => `${d.code} = ${d.label}${d.services.length ? ' (covers: ' + d.services.join('; ') + ')' : ''}`).join('\n');
  return `You check trades proposed for a UAE company from its own profile. Each proposal is a trade code, one or more lines quoted from the profile each with the lines around it in the profile (context, with the list heading it sits under when there is one), and a reason. Judge the quote together with its context. Trade definitions (code = name (covers: services)):
${list}

KEEP a proposal only when the quoted lines show that the company ITSELF sells this now, as one of its MAIN lines of business - in its title or tagline, its list of services, activities, divisions or products, or a section or heading of its own - and it falls under that trade's definition. An item mentioned in passing, a sub-item or component of another service, or one word in a long sentence is not a main line: DROP it. A product is named by what it IS, not by a word in its name (insulation blocks are blocks; cable trays are containment, not cables). A company that sells goods is not an installation or contracting trade (plumbing, electrical, flooring works) unless the text says it does that work; but each product category a trading company or catalogue lists under its own goods (tools, pipes, safety products) is a line of business of that company, even when printed under a general heading such as "BUILDING MATERIALS". Items a company lists as ordinary parts of its main trade's scope (landscape lighting or pergolas in a landscaper's list, ceilings in a fit-out list) are that main trade: DROP their own trades unless they have a heading or section of their own. When two proposals cover the same item, KEEP only the one whose definition names it most closely.
DROP it when the line is: history the company has left behind ("began as", "formerly" - but a capability its history says it ADDED and still runs, such as "in 2015 we added a precast concrete plant", is current), an internal function of the company (its own IT, HR, fleet), a tool or method it uses for its own work or to deliver a service (working from a cradle is how the cleaning is delivered, not a trade of its own), an accessory sold alongside its main goods rather than a line of business, work that is only a part of another trade's work and is not offered on its own (light fittings installed inside a shop fit-out are fit-out; but a service the company lists on its own in its list of services is offered on its own), a client, a project, or work of a sister, partner or group company when the profile is one company's (when the registered company IS the group and the document is the group's own brochure, each group company's described work is the group's and is kept), a contact mailbox or department name, a word of the company's own name or logo, or a certificate, policy or value, or a vision, mission or goal statement (N09: "envisions providing ... Pipeline work"). A COMPONENT printed under a list heading that names ANOTHER trade (under "ELECTRICAL WORKS": an item such as intercoms or access control) is that heading trade's work: DROP the component's own trade unless another quoted line shows the company offers it on its own. But an item that is itself the name of a service ("Joinery solutions", "HVAC services", "Plumbing") is a line of business wherever it is listed: a section label such as "HOME INTERIORS" or a combined "MEP" heading does not swallow it - HVAC, electrical and plumbing listed under MEP are each KEPT. Design of the company's own trade's works (landscape design by a landscaper, MEP design by an MEP contractor) is that trade's work, not design_consultancy, which is architectural or interior design. Judge every quote a proposal gives: KEEP it when any one of them shows the trade is sold now.

Return STRICT JSON only: {"keep":["code",...],"drop":[{"code":"...","why":"..."}]}`;
}
/** The quoted line with the lines around it in the document (code, not the model): a quote cut short ("supply and
 *  installation, modernization,") is checked with what it belongs to (measured on Al Nas Elevators, run 7). */
export function quoteContext(text: string, quote: string, around = 2): string {
  const lines = String(text ?? '').split(/\r?\n/);
  const first = quoteKey(String(quote ?? '').split(/\r?\n/)[0] ?? '');
  const i = first ? lines.findIndex((l) => (' ' + quoteKey(l) + ' ').includes(' ' + first + ' ') || (first.includes(quoteKey(l)) && quoteKey(l).length >= 12)) : -1;
  if (i < 0) return quote;
  const ctx = lines.slice(Math.max(0, i - around), i + around + 1).join('\n').slice(0, 600);
  // The list heading the quote sits under (H05: "Access Control" is an item of "ELECTRICAL WORKS", three lines up),
  // found by code: the nearest heading-shaped line above the context, within 12 lines.
  const h = headingAbove(lines, i - around, 12);
  return h ? `[under the heading: ${h}]\n${ctx}` : ctx;
}
/** A heading-shaped line: letters, at most 60 characters, and either upper case or ending in ":". */
export function isHeading(line: string): boolean {
  const t = String(line ?? '').replace(/\s+/g, ' ').trim();
  if (t.length < 3 || t.length > 60 || !/\p{L}{3}/u.test(t)) return false;
  const letters = t.replace(/[^\p{L}]/gu, '');
  return /:\s*$/.test(t) || (letters.length >= 4 && letters === letters.toUpperCase() && letters !== letters.toLowerCase());
}
export function headingAbove(lines: string[], from: number, span: number): string | null {
  for (let j = from - 1; j >= Math.max(0, from - span); j--) if (isHeading(lines[j])) return lines[j].replace(/\s+/g, ' ').trim();
  return null;
}
export function verifyRequest(trades: TradeChoice[], defs: TradeDef[], subject: unknown, text = '', company?: string | null) {
  return { fn: 'supplier_doc_trades', task_class: choiceTaskClass(), subject: subject ?? null, temperature: 0,
    sys_stable: verifySystem(defs), sys: '',
    input: [{ role: 'user', content: [{ type: 'text', text: companyLine(company) + 'Proposals:\n' + JSON.stringify(trades.map((t) => ({ code: t.code, quotes: (t.quotes?.length ? t.quotes : [t.quote]).map((q) => ({ quote: q, context: text ? quoteContext(text, q) : q })), reason: t.reason })), null, 1) }] }] };
}
/** The check's answer applied by code: only codes it kept stay; the rest are rejected with its reason. */
export function checkVerify(content: string, chosen: { trades: TradeChoice[]; rejected: { code: string; why: string }[] }): ChoiceResult {
  const parsed = answerJson(content, 'keep') as { keep?: unknown; drop?: unknown } | null;
  if (!parsed || !Array.isArray(parsed.keep)) return { ok: false, error: 'the check was not the JSON asked for: ' + answerHead(content) };
  const keep = new Set((parsed.keep as unknown[]).map((c) => String(c).trim()));
  const why = new Map((Array.isArray(parsed.drop) ? parsed.drop as Record<string, unknown>[] : []).map((d) => [String(d?.code ?? ''), String(d?.why ?? '')]));
  return { ok: true, trades: chosen.trades.filter((t) => keep.has(t.code)),
    rejected: [...chosen.rejected, ...chosen.trades.filter((t) => !keep.has(t.code)).map((t) => ({ code: t.code, why: 'the second look dropped it: ' + (why.get(t.code) || 'not kept').slice(0, 160) }))] };
}
