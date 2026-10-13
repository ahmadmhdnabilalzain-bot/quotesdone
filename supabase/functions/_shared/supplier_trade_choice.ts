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
export type TradeChoice = { code: string; quote: string; reason: string };
export type ChoiceResult =
  | { ok: true; trades: TradeChoice[]; rejected: { code: string; why: string }[] }
  | { ok: false; error: string };
/** The text in, the proven choices out. Injected for tests; liveTradeChooser is the edge function's. */
export type TradeChooser = (text: string, kind: 'profile' | 'catalogue') => Promise<ChoiceResult>;

export const CHOICE_TEXT_MAX = 40_000;
// The route (model_policy). QD_CHOICE_TASK_CLASS lets the accuracy harness measure on another class's model before the
// new row is applied at merge; production never sets it.
// deno-lint-ignore no-explicit-any
export const CHOICE_TASK_CLASS: string = (globalThis as any).Deno?.env?.get('QD_CHOICE_TASK_CLASS') || 'supplier_trade_choice';

/** The stable part of the prompt (cacheable): the rules and every trade's definition. */
export function choiceSystem(defs: TradeDef[]): string {
  const list = defs.map((d) => `${d.code} = ${d.label}${d.services.length ? ' (covers: ' + d.services.join('; ') + ')' : ''}`).join('\n');
  return `You read the text of a UAE company's profile or product catalogue and name the trades the company ITSELF offers as its business - the work it does or the goods it supplies.

Use ONLY these trade codes. Each line is: code = name (covers: the services of that trade).
${list}

RULES
1. A code is named only when the text says the company does that work or supplies those goods. Exact trade or none: if the company's work is not one of these trades, name nothing for it - never the nearest code.
2. Never from: the company's or another company's NAME, a client or project owner, another contractor on a project, a certificate or standard it holds (ISO, LEED), a policy, its staff, its equipment or vehicles, its offices, a sentence about quality, safety or values, or a tool or method it uses in its own work (3D printing, BIM, software) - only what it sells as a service or product. Work it does INSIDE a project of another trade names its own trade (electrical works in fit-out projects are electrical, not fit-out).
3. A line that lists the company's own works as its title or tagline (for example under or beside its name: "Waterproofing, Epoxy Flooring & Painting Works") states what it does: name every trade it lists.
4. A group brochure: name the trades of the companies of the group that the text describes as doing them. The same for the company's own factory, workshop or division (a "joinery production factory" is joinery).
5. For EVERY code give "quote": a line copied EXACTLY, word for word, from the text - the line that most directly names that service or product itself (for example "applied textured decorative paints", not a general sentence about the company), and "reason": one short sentence. A code you cannot quote is not named.
6. Prefer the specific trade the text names (fire fighting, HVAC, plumbing, electrical) and add mep_general only when the text offers combined MEP / electromechanical contracting.
7. Be complete: read the whole text and name EVERY trade it shows the company offers, not only the main one.

Return STRICT JSON only: {"trades":[{"code":"...","quote":"...","reason":"..."}]}`;
}

export function choiceRequest(text: string, kind: 'profile' | 'catalogue', defs: TradeDef[], subject: unknown) {
  return { fn: 'supplier_doc_trades', task_class: CHOICE_TASK_CLASS, subject: subject ?? null, temperature: 0,
    sys_stable: choiceSystem(defs), sys: '',
    input: [{ role: 'user', content: [{ type: 'text', text: `The company's ${kind === 'catalogue' ? 'catalogue' : 'profile'} text:\n\n${text.slice(0, CHOICE_TEXT_MAX)}` }] }] };
}

/** Letters and digits only, lower case, one space: how a quote is found in the text it came from. */
export const quoteKey = (s: string) => String(s ?? '').toLowerCase().normalize('NFKC').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();

/** The model's answer, checked by code: active codes only, each with a quote that is in the text. */
export function checkChoice(content: string, text: string, defs: TradeDef[]): ChoiceResult {
  let parsed: { trades?: unknown } | null = null;
  try { const s = String(content ?? ''); parsed = JSON.parse(s.slice(s.indexOf('{'), s.lastIndexOf('}') + 1)); } catch { parsed = null; }
  if (!parsed || !Array.isArray(parsed.trades)) return { ok: false, error: 'the answer was not the JSON asked for' };
  const codes = new Set(defs.map((d) => d.code));
  const hay = ' ' + quoteKey(text) + ' ';
  const trades: TradeChoice[] = [], rejected: { code: string; why: string }[] = [];
  for (const t of parsed.trades as Record<string, unknown>[]) {
    const code = String(t?.code ?? '').trim(), quote = String(t?.quote ?? '').trim(), reason = String(t?.reason ?? '').trim().slice(0, 300);
    if (!codes.has(code)) { rejected.push({ code, why: 'not an active trade code' }); continue; }
    const q = quoteKey(quote);
    if (q.length < 3) { rejected.push({ code, why: 'no quoted line' }); continue; }
    // A PDF breaks a sentence across lines, and the model may quote across the break: every line of the quote must
    // then be in the text, each word for word (a line of fewer than 3 letters is not evidence and is skipped).
    const parts = quote.split(/\r?\n/).map(quoteKey).filter((x) => x.length >= 3);
    const found = hay.includes(' ' + q + ' ') || (parts.length > 1 && parts.every((x) => hay.includes(' ' + x + ' ')));
    if (!found) { rejected.push({ code, why: `the quote is not in the document: "${quote.slice(0, 80)}"` }); continue; }
    if (trades.some((x) => x.code === code)) continue;
    trades.push({ code, quote: quote.slice(0, 240), reason });
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
  return async (text, kind) => {
    try {
      defs ??= await tradeDefs(admin);
      if (!defs) return { ok: false, error: 'the trade list could not be read' };
      if (!cred) { const { data } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_ai').maybeSingle(); cred = data?.value ?? null; }
      if (!cred) return { ok: false, error: 'no model credential' };
      const d = defs;
      const chosen = await twice(async () => { const g = await gateway(choiceRequest(text, kind, d, opts.subject)); return g.ok ? checkChoice(g.content, text, d) : g; });
      if (!chosen.ok || !chosen.trades.length) return chosen;
      const kept = await twice(async () => { const g = await gateway(verifyRequest(chosen.trades, d, opts.subject, text)); return g.ok ? checkVerify(g.content, chosen) : g; });
      return kept;
    } catch (e) { return { ok: false, error: String((e as Error)?.message || e).slice(0, 200) }; }
  };
  async function gateway(req: Record<string, unknown>): Promise<{ ok: true; content: string } | { ok: false; error: string }> {
    const r = await fetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/ai_gateway', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...(opts.headers ?? {}) }, signal: AbortSignal.timeout(120_000),
      body: JSON.stringify({ __secret: cred, ...req }),
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
  return `You check trades proposed for a UAE company from its own profile. Each proposal is a trade code, a line quoted from the profile, the lines around that quote in the profile (context), and a reason. Judge the quote together with its context. Trade definitions (code = name (covers: services)):
${list}

KEEP a proposal only when the quoted line shows that the company ITSELF sells this now, as a service or a product, and it falls under that trade's definition.
DROP it when the line is: history ("began as", "formerly"), an internal function of the company (its own IT, HR, fleet), a tool or method it uses for its own work, an accessory sold alongside its main goods rather than a line of business, work that belongs to a different trade in the list, a client, a project or another company's work, or a certificate, policy or value.

Return STRICT JSON only: {"keep":["code",...],"drop":[{"code":"...","why":"..."}]}`;
}
/** The quoted line with the lines around it in the document (code, not the model): a quote cut short ("supply and
 *  installation, modernization,") is checked with what it belongs to (measured on Al Nas Elevators, run 7). */
export function quoteContext(text: string, quote: string, around = 2): string {
  const lines = String(text ?? '').split(/\r?\n/);
  const first = quoteKey(String(quote ?? '').split(/\r?\n/)[0] ?? '');
  const i = first ? lines.findIndex((l) => (' ' + quoteKey(l) + ' ').includes(' ' + first + ' ') || (first.includes(quoteKey(l)) && quoteKey(l).length >= 12)) : -1;
  return i < 0 ? quote : lines.slice(Math.max(0, i - around), i + around + 1).join('\n').slice(0, 600);
}
export function verifyRequest(trades: TradeChoice[], defs: TradeDef[], subject: unknown, text = '') {
  return { fn: 'supplier_doc_trades', task_class: CHOICE_TASK_CLASS, subject: subject ?? null, temperature: 0,
    sys_stable: verifySystem(defs), sys: '',
    input: [{ role: 'user', content: [{ type: 'text', text: 'Proposals:\n' + JSON.stringify(trades.map((t) => ({ code: t.code, quote: t.quote, context: text ? quoteContext(text, t.quote) : t.quote, reason: t.reason })), null, 1) }] }] };
}
/** The check's answer applied by code: only codes it kept stay; the rest are rejected with its reason. */
export function checkVerify(content: string, chosen: { trades: TradeChoice[]; rejected: { code: string; why: string }[] }): ChoiceResult {
  let parsed: { keep?: unknown; drop?: unknown } | null = null;
  try { const s = String(content ?? ''); parsed = JSON.parse(s.slice(s.indexOf('{'), s.lastIndexOf('}') + 1)); } catch { parsed = null; }
  if (!parsed || !Array.isArray(parsed.keep)) return { ok: false, error: 'the check was not the JSON asked for' };
  const keep = new Set((parsed.keep as unknown[]).map((c) => String(c).trim()));
  const why = new Map((Array.isArray(parsed.drop) ? parsed.drop as Record<string, unknown>[] : []).map((d) => [String(d?.code ?? ''), String(d?.why ?? '')]));
  return { ok: true, trades: chosen.trades.filter((t) => keep.has(t.code)),
    rejected: [...chosen.rejected, ...chosen.trades.filter((t) => !keep.has(t.code)).map((t) => ({ code: t.code, why: 'the second look dropped it: ' + (why.get(t.code) || 'not kept').slice(0, 160) }))] };
}
