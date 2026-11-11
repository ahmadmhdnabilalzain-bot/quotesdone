// WHAT A SUPPLIER'S OWN DOCUMENTS SAY HE DOES, AS SERVICES; WHETHER HIS LICENCE COVERS IT; AND HIS OWN WORDS FOR IT
// (10 Nov 2026, sales_engineer; founder ledger 1573, 1579, 1586).
//
// Founder, 10 Nov 2026 (1573): "the agent reads the company profile and trade licence, understands what the company does,
// checks the licence activities against the profile, proposes extracted keywords/services the supplier ticks or adds to;
// those keywords drive the cross-matching". 1579: "for every trade, product and service, not just that case".
//
// MEASURED (design audit 10 Nov 2026, section 3.1-3.2): the profile proposed TRADES only (supplier_doc_trades.ts), so the
// supplier's own specific lines ("PVC decorative panels") were never offered as services; nothing compared the licence's
// activities with the profile; and a phrase a supplier confirmed could never become a name matching reads.
//
// WHAT LIVES HERE (pure, tested offline in profile_services.test.ts; the I/O is in supplier_doc_trades.ts and
// supplier_services.ts):
//   * servicesOfText: a profile or catalogue's offer lines -> SERVICE keys, each with the supplier's own words as its
//     evidence. A line or list part that IS a service's name (service_rewrite.rewriteServices, exact) first; then meaning
//     over the stored service vectors (service_meaning.proposeByMeaning) for the lines nothing named, within the request's
//     meaning budget. Text becomes a code here, at onboarding, and the supplier confirms it; matching reads codes only.
//   * licenceCheck: each proposed service against the trades the licence's ACTIVITIES name (supplier_doc_trades reads only
//     the activities line of a licence). 'supported' when the licence names the service's trade, 'not_covered' when a
//     licence was read and does not, 'unclear' when no activities could be read. It never rejects anything: a service
//     not covered is still proposed, shown to the supplier with the reason, and put to the sales engineer
//     (agent_actions licence_scope_check). The ruling-based holds (fn_sales_engineer_verifies_supplier) are untouched.
//   * proposedServicesOf: the documents' services merged, one per key, with the licence check on each.
//   * aliasPairsOf: the supplier's own short phrases for services he CONFIRMED -> the alias queue
//     (public.fn_service_alias_propose); a phrase is a name only once the sales engineer approves it.
//   * stateServiceKeys: inquiry_state.specs.service_keys (written by the expert-advice catalogue, branch
//     sales_engineer-expert-advice) -> the request's exact service keys, preferred over reading its prose.
// prevented by: supabase/functions/_shared/profile_services.test.ts, supabase/functions/_shared/general_matching.test.ts
import { rewriteServices, type ServiceTerm } from './service_rewrite.ts';
import { MEANING_MAX_LINES, meaningCandidates, meaningClauses, proposeByMeaning, type MeaningService } from './service_meaning.ts';
import { embedLines, type Embedder } from './meaning_embed.ts';

export type ServiceHit = {
  key: string; trade: string; label_en: string;
  via: 'exact_name' | 'meaning';
  /** the supplier's own words for it: the list part that IS its name, or the clause meaning read */
  phrase: string;
  /** the line of the document it was found on */
  snippet: string;
  similarity?: number;
};
export type ServicesRead = { services: ServiceHit[]; meaning: 'on' | 'service_vectors_missing' | 'embedding_unavailable' | 'budget_spent' | 'nothing_to_read' };
/** tradeLabels / tradeAliases: the trade confirmation tradesOfText already applies to a supplier's document (service_meaning
 *  proposeByMeaning, 13 Oct 2026): a meaning hit stands only when the line holds its TRADE's own name or alias. */
export type ServicesDeps = { services: MeaningService[]; embed: Embedder; budget: { left: number }; tradeLabels?: Record<string, string>; tradeAliases?: Record<string, string[]> };

export const SNIPPET_LEN = 180;
const lines = (text: string) => [...new Set(String(text ?? '').split(/\r?\n/).map((l) => l.replace(/\s+/g, ' ').trim()).filter((l) => l.length >= 2))];

/** The services a document's text states, exact names first, then meaning for what nothing named. Never throws. */
export async function servicesOfText(text: string, deps: ServicesDeps, opts: { supplyOnly?: boolean } = {}): Promise<ServicesRead> {
  const out = new Map<string, ServiceHit>();
  const unnamed: string[] = [];
  for (const line of lines(text)) {
    const rw = rewriteServices(line, deps.services as ServiceTerm[], { supplyOnly: opts.supplyOnly });
    for (const it of rw.items) {
      if (it.kind === 'service' && !out.has(it.key)) {
        out.set(it.key, { key: it.key, trade: it.trade, label_en: it.label_en, via: 'exact_name', phrase: it.part ?? it.from, snippet: line.slice(0, SNIPPET_LEN) });
      }
    }
    if (rw.items.some((i) => i.kind === 'unmatched') || !rw.items.length) unnamed.push(line);
  }
  const done = (meaning: ServicesRead['meaning']): ServicesRead => ({ services: [...out.values()].sort((a, b) => a.key.localeCompare(b.key)), meaning });
  const origin = new Map<string, string>();
  for (const l of unnamed) for (const c of meaningClauses(l)) if (!origin.has(c)) origin.set(c, l);
  if (!origin.size) return done('nothing_to_read');
  if (!deps.services.some((s) => s.vec || s.vec_ml)) return done('service_vectors_missing');
  if (deps.budget.left <= 0) return done('budget_spent');
  const todo = meaningCandidates([...origin.keys()], deps.services, Math.min(MEANING_MAX_LINES, deps.budget.left));
  if (!todo.length) return done('nothing_to_read');
  deps.budget.left -= todo.length;
  const read = await embedLines(todo, deps.embed);
  if (!read.some((l) => l.vec)) return done('embedding_unavailable');
  // THE TRADE MUST AGREE HERE TOO (11 Nov 2026, customer_support; paid registration certification, 06:07 UTC). This call left out
  // the confirmation tradesOfText passes, so a profile's services were proposed on the vector and one head word alone: "...with
  // our own team and equipment." -> Recording studio equipment (musical_pro_audio) for four unrelated companies, "doors, frames
  // and architraves" -> Spectacle frames, "bathroom accessories" -> hotel Room accessories. The 13 Oct rule (183 false lines on
  // 29 real profiles without it) applies to services exactly as to trades. Prevented by:
  // _shared/a_proposed_service_is_grounded_in_the_suppliers_own_documents.test.ts
  for (const p of proposeByMeaning(read, deps.services, { stated: [...out.keys()], supplyOnly: opts.supplyOnly, tradeLabels: deps.tradeLabels, tradeAliases: deps.tradeAliases })) {
    if (out.has(p.key)) continue;
    const clause = p.lines[0] ?? '';
    out.set(p.key, { key: p.key, trade: p.trade, label_en: p.label_en, via: 'meaning', phrase: clause, snippet: (origin.get(clause) ?? clause).slice(0, SNIPPET_LEN), similarity: p.similarity });
  }
  return done('on');
}

// ── THE LICENCE AGAINST THE PROFILE ──────────────────────────────────────────────────────────────────────────────────
export type LicenceStatus = 'supported' | 'not_covered' | 'unclear';
export type LicenceCheck = {
  /** a licence was read and its activities line could be read */
  read: boolean;
  activities: string[];
  /** the trades the activities name (the licence document's trades) */
  licence_trades: string[];
  not_covered: string[];
  checked_at: string;
};
export type ProposedService = ServiceHit & { doc: string; licence: LicenceStatus };

type DocLike = { kind: string; status: string; name: string; trades?: { code: string }[]; services?: ServiceHit[]; activities?: string[] };

export function licenceStatus(trade: string, check: Pick<LicenceCheck, 'read' | 'licence_trades'>): LicenceStatus {
  if (!check.read) return 'unclear';
  return check.licence_trades.includes(trade) ? 'supported' : 'not_covered';
}

/** The trades a supplier's own documents ground a service in: the trades a document itself named (the model's choice, proven
 *  by a quoted line, or code's exact and confirmed reading) and the trades its licence's activities name. */
export function groundedTrades(doc: Pick<DocLike, 'trades'>, check: Pick<LicenceCheck, 'licence_trades'>): Set<string> {
  return new Set([...(doc.trades ?? []).map((t) => t.code), ...check.licence_trades]);
}

/** The documents' proposed services, one per key (the first document that named it), each checked against the licence.
 *
 *  A SERVICE IS PROPOSED ONLY IN A TRADE THE SUPPLIER'S OWN DOCUMENTS GROUND (11 Nov 2026, customer_support; paid registration
 *  certification, 06:07-06:47 UTC). Every company was offered absurd services beside the right ones, the same in both runs:
 *  Recording studio equipment for the MEP, joinery, HVAC and bus companies, Spectacle frames for the joiner, Office & warehouse
 *  leasing for the MEP contractor, Same-day delivery for the packaging maker, Equipment rental for the bus company. Each was a
 *  service whose trade NOTHING in his documents named: the profile's trades were chosen and proven (the model quoting the line),
 *  but its services were read across all 1,100 services, each on its own. A service now stands only when its trade is one this
 *  document named or his licence's activities name; the trade decision is the proven one, the service only says which part of it.
 *  The founder's 862/857 (offered, never ticked) and the licence check are unchanged. Prevented by:
 *  _shared/a_proposed_service_is_grounded_in_the_suppliers_own_documents.test.ts */
export function proposedServicesOf(docs: DocLike[], now = new Date().toISOString()): { proposed: ProposedService[]; licence_check: LicenceCheck } {
  const lic = docs.find((d) => d.kind === 'licence' && d.status === 'read');
  const activities = (lic?.activities ?? []).map((a) => String(a).trim()).filter(Boolean);
  const check: LicenceCheck = {
    read: !!lic && activities.length > 0,
    activities,
    licence_trades: [...new Set((lic?.trades ?? []).map((t) => t.code))].sort(),
    not_covered: [], checked_at: now,
  };
  const seen = new Map<string, ProposedService>();
  for (const d of docs) {
    if (d.kind === 'licence' || d.status !== 'read') continue;
    const grounded = groundedTrades(d, check);
    for (const s of d.services ?? []) if (!seen.has(s.key) && grounded.has(s.trade)) seen.set(s.key, { ...s, doc: d.name, licence: licenceStatus(s.trade, check) });
  }
  const proposed = [...seen.values()].sort((a, b) => a.key.localeCompare(b.key));
  check.not_covered = proposed.filter((p) => p.licence === 'not_covered').map((p) => p.key);
  return { proposed, licence_check: check };
}

// ── THE SUPPLIER'S OWN WORDS -> THE ALIAS QUEUE ──────────────────────────────────────────────────────────────────────
// A NAME IS A SHORT NOUN PHRASE: a line of a brochure is not proposed as one. Six words is the longest curated alias of the
// 1,103 services (measured 10 Nov 2026 on the live vocabulary: "supply and installation of AC units" style names).
export const ALIAS_MAX_WORDS = 6;
export type AliasPair = { phrase: string; key: string };
export function aliasPairsOf(candidates: { phrase: string; key: string }[], stated: string[]): AliasPair[] {
  const keep = new Set(stated);
  const out = new Map<string, AliasPair>();
  for (const c of candidates) {
    const phrase = String(c.phrase ?? '').replace(/\s+/g, ' ').trim().replace(/^[\s,.;:•·*\-–—]+|[\s,.;:•·*\-–—]+$/g, '');
    const words = phrase.split(' ').filter(Boolean).length;
    if (!keep.has(c.key) || phrase.length < 3 || phrase.length > 120 || words > ALIAS_MAX_WORDS) continue;
    const k = phrase.toLowerCase() + '|' + c.key;
    if (!out.has(k)) out.set(k, { phrase, key: c.key });
  }
  return [...out.values()].slice(0, 40);
}

// ── THE REQUEST'S SERVICES, FROM ITS STATE ───────────────────────────────────────────────────────────────────────────
// The expert-advice catalogue (branch sales_engineer-expert-advice) writes the option the customer chose as exact service
// keys into inquiry_state.specs.service_keys. A spec value is a string (inquiry_state.SpecEntry), so the keys arrive as
// "wallpaper.wall_panels" or a list joined by commas, spaces or "|"; an array is accepted too. Only key-shaped values that
// the live vocabulary holds are returned (`known`); anything else is dropped, never guessed.
const KEY = /^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/;
export function stateServiceKeys(state: { specs?: Record<string, unknown> } | null | undefined, known?: Set<string>): string[] {
  const raw = state?.specs?.service_keys as unknown;
  const v = raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as { value?: unknown }).value : raw;
  const parts = Array.isArray(v) ? v.map(String) : typeof v === 'string' ? v.split(/[\s,;|]+/) : [];
  return [...new Set(parts.map((s) => s.trim().toLowerCase()).filter((s) => KEY.test(s) && (!known || known.has(s))))].sort();
}
