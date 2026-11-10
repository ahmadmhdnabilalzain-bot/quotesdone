// inquiry_reading — THE PORTAL AND WHATSAPP KEEP THE EXPERT'S STATE TOO (10 Nov 2026, sales_engineer with customer_support for
// WhatsApp; founder ledger 1572, 1579, 1586).
//
// The request chat's model answers in JSON, so it names the trades, the options it put and the one chosen itself
// (inquiry_intake/handle.ts). The portal and WhatsApp replies are prose (one streamed call; the WhatsApp reply's own JSON
// carries only the answer), so nothing recorded which taxonomy trades a job there was about, which solutions were offered or
// which one the customer chose: the next turn could offer them again, and the request it became named no service.
//
// THIS READS IT, by reasoning and never by matching words (ruling 890): one bounded json_extraction call per customer turn,
// started beside the reply and never awaited by it, given the trade taxonomy, the reference options shown, our last reply and
// their message, answering {trade_codes, problem, options_offered, chosen_option, condition, budget, service_keys}. Each
// value is kept only when it exists (validCodes, readSolution, validServiceKeys) and goes to public.inquiry_state through
// fn_inquiry_state_merge. The NEXT turn's reply reads it (its trade's packs, the solution so far). A failed or slow reading
// changes nothing: the reply has already gone and the state stays as it was.
// prevented by: supabase/functions/_shared/inquiry_reading.test.ts
import { readSolution, solutionPatch, type Problem, type SolutionReading } from './solution_catalogue.ts';
import { placeTrades, taxonomyBlock, validCodes, validServiceKeys, type TaxTrade, type TradeService } from './inquiry_trades.ts';
import type { StatePatch } from './inquiry_state.ts';

export interface ReadingInput { taxonomy: TaxTrade[]; problems: Problem[]; services?: TradeService[]; lastSeat: string; message: string; heldCodes?: string[] }
export interface Reading extends SolutionReading { trade_codes: string[]; service_keys: string[] }

/** The reading call's prompt: the taxonomy, the options the reply could offer, our last reply and their message. */
export function readingPrompt(i: ReadingInput): { sys: string; input: string } {
  const opts = i.problems.flatMap((p) => p.options.map((o) => `${p.code}/${o.code}: ${o.en}`));
  const svc = (i.services ?? []).map((s) => `${s.trade_code}.${s.code}: ${s.label_en}`);
  return {
    sys: 'You read one turn of a UAE procurement chat (our sales engineer and a customer) and report, as JSON only, what it establishes. '
      + 'Never guess: leave a field empty when the turn does not show it. Return {"trade_codes":[], "problem":"", "options_offered":[], "chosen_option":"", '
      + '"condition":{"object":"","material":"","condition":"","location":"","use":"","constraint":""}, "budget":"", "service_keys":[]}.\n'
      + '- trade_codes: the one to four taxonomy codes below that do the job the customer wants, most central first' + (i.heldCodes?.length ? ` (held so far: ${i.heldCodes.join(', ')}; keep them unless the job changed)` : '') + '.\n'
      + '- options_offered: the solutions OUR LAST REPLY put to them, as the option keys below when one fits, else a few words each.\n'
      + '- chosen_option: the one the customer\'s MESSAGE chooses (an option key below, or a few words), "" when they chose none.\n'
      + '- problem: the situation key below their job is, "" when none fits. condition: their own words for the thing and its state. budget: only a budget they state.\n'
      + '- service_keys: the service keys below the job needs, only when the turn makes it clear.\n\n'
      + taxonomyBlock(i.taxonomy)
      + (opts.length ? '\n\nOPTION KEYS (problem/option):\n' + opts.join('\n') : '')
      + (svc.length ? '\n\nSERVICE KEYS:\n' + svc.join('\n') : ''),
    input: (i.lastSeat ? 'OUR LAST REPLY: ' + i.lastSeat.slice(-1500) + '\n' : '') + 'CUSTOMER MESSAGE: ' + i.message.slice(0, 1500),
  };
}

/** The reading's answer, kept only where it names what exists. */
export function parseReading(text: string | null | undefined, i: Pick<ReadingInput, 'taxonomy' | 'services'>): Reading | null {
  const m = String(text ?? '').match(/\{[\s\S]*\}/);
  if (!m) return null;
  let o: Record<string, unknown>;
  try { o = JSON.parse(m[0]); } catch { return null; }
  const codes = validCodes(o.trade_codes, i.taxonomy), keys = validServiceKeys(o.service_keys, i.services);
  // The placement follows the services, as in the request chat (inquiry_trades.ts placeTrades, finding b1 of 10 Nov 2026).
  const placed = codes.length ? placeTrades(codes, keys) : null;
  return { ...readSolution(o), trade_codes: placed?.by === 'services' ? placed.codes : codes, service_keys: placed?.by === 'services' ? placed.keys : keys };
}

/** The state patch of a reading: the solution half (solution_catalogue.solutionPatch) plus the trade codes, and the service
 *  keys it read when no chosen option already names them. */
export function readingPatch(r: Reading): StatePatch {
  const p: StatePatch = { ...solutionPatch(r) };
  if (r.trade_codes.length) p.trade_codes = r.trade_codes;
  if (!p.specs?.service_keys && r.service_keys.length) p.specs = { ...(p.specs ?? {}), service_keys: r.service_keys.join(', ') };
  return p;
}

/** The bounded call. `ask` is the surface's own json_extraction call (sys, input, ms) -> content; null on any failure. */
export async function readInquiry(ask: (sys: string, input: string, ms: number) => Promise<string | null>, i: ReadingInput, deadline: number): Promise<Reading | null> {
  const ms = deadline - Date.now();
  if (ms < 1_500 || !i.taxonomy.length || !i.message.trim()) return null;
  const p = readingPrompt(i);
  try { return parseReading(await ask(p.sys, p.input, ms), i); } catch { return null; }
}

/** The portal's `ask`: one json_extraction call through the gateway with the seat's credential (the shape
 *  sales_engineer/conversation_plan.extractSlots uses). Never throws; null on any failure. */
export function gatewayAsk(o: { gateway: string; secret: string; fn: string; agent: string }, f: typeof fetch = fetch) {
  return async (sys: string, input: string, ms: number): Promise<string | null> => {
    try {
      const r = await f(o.gateway, { method: 'POST', headers: { 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(ms),
        body: JSON.stringify({ __secret: o.secret, fn: o.fn, agent: o.agent, task_class: 'json_extraction', sys, input,
          max: 400, temperature: 0, cache_ttl_min: 0, try_faq: false, client_timeout_ms: ms }) });
      const j = await r.json().catch(() => null) as { content?: unknown } | null;
      return typeof j?.content === 'string' ? j.content : null;
    } catch { return null; }
  };
}
