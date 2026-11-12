// THE QUESTIONS ARE A RECORD, NOT A SCREEN (12 Nov 2026, sales_engineer; built by it_engineer). Founder rulings 1647 ("where the
// profile is not straightforward the agent gets specific": "what sort of staff"; pools "through a subcontractor"), 1628 (the AI
// proposes, the supplier confirms) and 1645 (his standard for every screen). Design: docs/reports/2026-11-12-supplier-service-profiling.md
// 3.3 (vagueness), 3.8 (the questions are a record) and 3.10; slice 4. Table: scripts/sql/a_supplier_is_asked_what_his_documents_could_not_say.sql.
//
// MEASURED (12 hard profiles, 12 Nov 2026): 0 questions asked in 18 readings; 22 of 22 partner services dropped. Reader @5
// (supplier_profile_reading.proposalOf) now drafts the questions; this module keeps them (storeQuestions, when a reading lands),
// lists them (listQuestions, for the Services tab) and takes one answer at a time (answerQuestion). NO MODEL IS CALLED HERE: the
// options were fixed at reading time, so an answer is one read and one write (report 3.12: under 1 s). "Something else" words are
// stored at once as his own words and mapped behind (the existing rewrite path, injected by the caller as `mapWords`); a key that
// fits comes back as a card of its own ('new_key'), never as a key put on his list for him.
//
// NOTHING HERE WRITES supplier_capabilities.services. An answer is his answer; it becomes a service only when he presses Confirm
// (capabilityConfirm, the one writer), which also records the answers in the confirmation ledger.

import { aboutHash, LIMITS, type QuestionOption, type SupplierServiceQuestionDraft } from './supplier_profile_reading.ts';
import { activeServiceRows } from './service_vocabulary.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;

export const TABLE = 'supplier_service_question';
/** The order cards are put to him, most blocking first: report 3.3's "nothing-evidenced, vague, partner, shown, umbrella, licence",
 *  with a trade card after the partner card (12 Nov 2026, walk of the recorded decoration company: three trade cards came before
 *  the pools question the founder named) and the "Something else" follow-up last. */
export const QUESTION_ORDER = ['nothing', 'vague', 'partner', 'trade_services', 'shown', 'umbrella', 'licence', 'new_key'] as const;
/** A visit to Services after this long since his last answer is a new sitting: questions kept as 'later' are offered then (3.2, 3.3). */
export const NEW_SITTING_MS = 6 * 3600_000;
export const OTHER_MAX = 120;
/** The "nothing" card's box takes a line or two of what his company does (its textarea's own limit). */
export const NOTHING_MAX = 500;
/** A card about a vague statement carries at most this many chips, and the card shows every one (round-2 review of slice 4, finding C:
 *  no "More"). Measured 12 Nov 2026 on the live catalogue: labour_supply has 18 active services, and in catalogue order the founder's own
 *  examples ("professional experts", "freelancers") come 12th and 15th on the staff card; a cap of 10 would have cut both. */
export const VAGUE_CHIPS = 20;
const READER_KINDS = new Set(['nothing', 'vague', 'trade_services', 'partner', 'shown', 'umbrella', 'licence']);
const KEYED_KINDS = new Set(['vague', 'trade_services', 'partner', 'shown', 'umbrella', 'new_key']);
/** Kinds whose chips are candidates he never evidenced: a key that is only the `same` twin of one he has is not asked. */
const CANDIDATE_KINDS = new Set(['umbrella', 'shown', 'trade_services']);

export type Status = 'open' | 'later' | 'answered' | 'skipped' | 'expired';
export type QuestionRow = {
  id: number; supplier_id: number; kind: string; about: Record<string, unknown>; about_hash: string; prompt_en: string;
  options: QuestionOption[]; multi: boolean; status: Status; answer: Answer | null; source: string; asked_at?: string; answered_at?: string | null;
};
/** One answer. picked: indexes into options; none: "None of these"; only_inside: "Only inside our own projects" (shown);
 *  other: "Something else" in his words; per: for a partner card, per option index, own team / through the partner / not offered. */
export type Answer = { picked?: number[]; none?: boolean; only_inside?: boolean; other?: string; per?: Record<string, 'own' | 'partner' | 'no'> };

const rank = (k: string) => { const i = (QUESTION_ORDER as readonly string[]).indexOf(k); return i < 0 ? QUESTION_ORDER.length : i; };
const optKeys = (q: { options?: QuestionOption[] }) => (q.options ?? []).map((o) => o.key).filter((k): k is string => !!k);
const tidy = (s: unknown) => String(s ?? '').replace(/\s+/g, ' ').trim();

/** The keys he has already DECIDED by answering: every keyed option of an answered question, chosen or not (3.8: "a declined
 *  candidate is remembered (answered, not chosen) and never asked again unless a new document evidences it"). */
export function decidedKeys(rows: Pick<QuestionRow, 'status' | 'options'>[]): Set<string> {
  return new Set(rows.filter((r) => r.status === 'answered').flatMap((r) => optKeys(r)));
}

/** service_implication rows with same = true, as key -> its twins (both ways). */
export function twinsOf(rows: { from: string; to: string }[]): Map<string, Set<string>> {
  const m = new Map<string, Set<string>>();
  for (const { from, to } of rows) { (m.get(from) ?? m.set(from, new Set()).get(from)!).add(to); (m.get(to) ?? m.set(to, new Set()).get(to)!).add(from); }
  return m;
}

/**
 * WHAT A NEW READING ADDS (pure). The drafts proposalOf made, against what this supplier's rows already hold:
 *  * a draft already stored (same kind and about_hash) is not stored again (the table's unique key would ignore it too);
 *  * a keyed option he already decided in an answered question is not asked again, nor a key he already has (`has`: the
 *    reading's tick and partner lists and his confirmed services), nor, on a candidate card, a key that is only the `same` twin
 *    of one he has (service_implication.same: one piece of work under two keys; confirming one is confirming the other);
 *  * a keyed card left with no option is dropped; a 'nothing' or 'licence' card already answered is not asked again;
 *  * at most LIMITS.openCards cards are open at once across old and new (the rest 'later', offered on his next visit).
 */
/** A 'shown' card none of whose options is a key his documents evidence is proposalOf's trade-wide fallback (a caption or brand
 *  phrase no key covers asks its trade's whole service list). MEASURED 12 Nov 2026 on the recorded hard-profile set (run 1f18dbf5):
 *  the glossy fit-out profile's one caption "DHA fit-out approvals" drafted a card of the six visa and PRO services, and the tools
 *  distributor's brand line "Karcher cleaning equipment" a card of eight cleaning WORKS (goods are not works). Such a card is
 *  stored only when the trade's own captions name it at least twice, and never from a brand line. */
export const FALLBACK_MIN_CAPTIONS = 2;
type Evidence = { basis: string; trade: string | null; keys: string[] };
function fallbackAllowed(d: SupplierServiceQuestionDraft, evidence: Evidence[] | undefined): boolean {
  if (!evidence) return true;
  // A TRADE CARD FOR WORDS HE IS ALREADY OFFERED. A trade whose only evidence is his own statements that no key covers (they are
  // listed on screen 1 "in his words") is not asked as "You work in <trade>" as well. Measured 12 Nov 2026 on the recorded decoration
  // company (H01): "Garden lighting", "Boundary walls" and "Gazebos" drafted three cards (Electrical; Masonry; Fencing and shades)
  // before the pools question, two of them trades the answer key says he is not in.
  // The same when the trade's other phrases were mapped to another trade's key ("Pergolas" read under fencing and shades, mapped to
  // aluminium.pergolas_shades): what he said is on his list already, under the key that names it.
  if (d.kind === 'trade_services') {
    const t = d.about.trade;
    // ...but only where something else of his IS listed with a key: a profile with no keyed statement of its own (the recruitment company,
    // H02: "We supply staff and similar services", its trade read as recruitment) keeps its trade card, or that trade would be his only as
    // free text (independent review of slice 4, 12 Nov 2026: the rule above dropped 12 of 12 trade cards, this one among them).
    if (!evidence.some((e) => e.basis === 'stated' && e.keys.length)) return true;
    const of = evidence.filter((e) => e.trade === t || e.keys.some((k) => k.startsWith(t + '.')));
    const covered = (e: Evidence) => (e.keys.length ? !e.keys.some((k) => k.startsWith(t + '.')) : e.basis === 'stated' || e.basis === 'partner');
    return !(of.length > 0 && of.every(covered));
  }
  if (d.kind !== 'shown') return true;
  const evidenced = new Set(evidence.flatMap((e) => e.keys));
  if (d.options.some((o) => o.key && evidenced.has(o.key))) return true;
  const of = evidence.filter((e) => e.trade === d.about.trade);
  return !of.some((e) => e.basis === 'brand') && of.filter((e) => e.basis === 'shown').length >= FALLBACK_MIN_CAPTIONS;
}

export function toStore(drafts: SupplierServiceQuestionDraft[], existing: Pick<QuestionRow, 'kind' | 'about_hash' | 'status' | 'options'>[],
  has: ReadonlySet<string>, twins: Map<string, Set<string>> = new Map(), evidence?: Evidence[], catalogue?: CatalogueRow[]): SupplierServiceQuestionDraft[] {
  // an EXPIRED question is not stored for this purpose: a later reading that drafts it again asks it again (storeQuestions reopens the row)
  const stored = new Set(existing.filter((r) => r.status !== 'expired').map((r) => `${r.kind}|${r.about_hash}`));
  const decided = decidedKeys(existing);
  const answeredKinds = new Set(existing.filter((r) => r.status === 'answered').map((r) => r.kind));
  // keys already put to him on a card of this reading (or an open one): a candidate card never asks the same work again, nor its twin
  const asked = new Set(existing.filter((r) => r.status === 'open' || r.status === 'later').flatMap((r) => (r.options ?? []).map((o) => o.key).filter((k): k is string => !!k)));
  const twinOfHeld = (k: string) => [...(twins.get(k) ?? [])].some((t) => has.has(t) || (asked.has(t)));
  let open = existing.filter((r) => r.status === 'open').length;
  const umbExisting = existing.filter((r) => r.status === 'open' && r.kind === 'umbrella');
  let umbOpen = umbExisting.length, umbChips = umbExisting.reduce((n, r) => n + (r.options?.length ?? 0), 0), umbWaits = false;
  const out: SupplierServiceQuestionDraft[] = [];
  for (const d of [...drafts].sort((a, b) => rank(a.kind) - rank(b.kind))) {
    if (stored.has(`${d.kind}|${d.about_hash}`) || !fallbackAllowed(d, evidence)) continue;
    if ((d.kind === 'nothing' || d.kind === 'licence') && answeredKinds.has(d.kind)) continue;
    const base = d.kind === 'vague' && catalogue?.length ? catalogueOptions(d, catalogue, twins, new Set([...has, ...decided])) : d.options;
    const options = KEYED_KINDS.has(d.kind)
      ? base.filter((o) => !o.key || (!decided.has(o.key) && !has.has(o.key) && !(CANDIDATE_KINDS.has(d.kind) && (asked.has(o.key) || twinOfHeld(o.key)))))
      : base;
    if (KEYED_KINDS.has(d.kind) && d.options.length && !options.length) continue;
    // open by OUR order (not the draft's), at most LIMITS.openCards across old and new, umbrella at most 2 cards and 12 chips
    let ok = open < LIMITS.openCards;
    // umbrella cards come most likely first: once one waits, the ones after it wait too (no one-chip card jumps the queue)
    if (ok && d.kind === 'umbrella') { ok = !umbWaits && umbOpen < LIMITS.umbrellaCards && umbChips + options.length <= LIMITS.umbrellaChips; if (ok) { umbOpen++; umbChips += options.length; } else umbWaits = true; }
    if (ok) open++;
    out.push({ ...d, options, status: ok ? 'open' : 'later' });
    for (const o of options) if (o.key) asked.add(o.key);
  }
  return out;
}

/** One active catalogue service: its key, its trade, its English name and its aliases (taxonomy_trade_service, paged). */
export type CatalogueRow = { key: string; trade: string; label: string; aliases: string[] };
/**
 * WORDS THAT NAME NO KIND OF WORK ON THEIR OWN (round-2 review of slice 4, finding B). A suggestion is covered by a catalogue service only
 * when every word of it that is NOT one of these is in that one service's name or aliases; one shared word was enough before, and turned
 * "Medical staff", "Temporary staff", "Event staff" and "Staff transport" into "Cleaners & housekeeping staff" (they share only "staff").
 *   staff         - every staffing service says it ("cleaners & housekeeping STAFF"); the kind of staff is the other word
 *   supply        - "X supply" is X ("driver supply"); the goods-or-works distinction is the mapping's, not this match's
 *   service       - "maintenance services", "IT services": the trade's word for itself
 *   work          - "civil works", "joinery works": names the trade, not the job
 *   maintenance   - every trade has its maintenance service; "AC maintenance" is about AC
 *   repair        - the same: "door and window repairs" is about doors and windows, not any repair service
 *   installation  - "rack installation": what is installed is the content
 *   system        - "fire alarm systems", "irrigation systems": the kind is the other word
 *   equipment     - "drivers & equipment operators" must not swallow "medical equipment"
 *   material      - "waterproofing & insulation materials" must not swallow "glass sheets ... materials"
 *   rental        - "plant rental", "equipment rental": what is rented is the content
 * Each is compared after the same singular form (stem), so their plurals are generic too.
 */
const stem = (w: string) => (w.endsWith('ies') ? w.slice(0, -3) + 'y' : /(ses|xes|ches|shes)$/.test(w) ? w.slice(0, -2) : w.endsWith('s') && !w.endsWith('ss') ? w.slice(0, -1) : w);
export const GENERIC_WORDS: ReadonlySet<string> = new Set(['staff', 'supply', 'service', 'work', 'maintenance', 'repair', 'installation', 'system', 'equipment', 'material', 'rental'].map(stem));
/** Words of two letters that name a field of work (round-3 review of slice 4, finding 6: the alias "IT contractors" read as "contractors",
 *  and "Contractors" mapped to professional staff). Kept when written in capitals in the suggestion, and always in the catalogue's
 *  own names and aliases, which are stored in lower case. */
const ACRONYMS = new Set(['it', 'ac', 'hr', 'pr', 'qa', 'av', 'cv', 'ev', 'ui', 'ux']);
const stemWords = (t: string, catalogueText = false) => new Set((t.match(/[A-Za-z]{2,}/g) ?? [])
  .filter((w) => w.length >= 3 || /^[A-Z]{2}$/.test(w) || (catalogueText && ACRONYMS.has(w.toLowerCase())))
  .map((w) => w.toLowerCase()).filter((w) => w !== 'and' && w !== 'the' && w !== 'for' && w !== 'our').map(stem));
/** Words stripped from a SERVICE's own name or alias when asking whether it says the same thing as a thin suggestion (round-3 review,
 *  finding 3): only these three name no kind of work there. "Pool MAINTENANCE" and "Waterproofing & insulation MATERIALS" keep their
 *  activity, so "Pools" and "Insulation" do not become them. The suggestion's side still sets every GENERIC_WORDS word aside. */
export const SERVICE_SIDE_GENERIC: ReadonlySet<string> = new Set(['staff', 'supply', 'service'].map(stem));
/** Activity words of a suggestion that a service must also say, or the two contradict ("Roof REPAIRS" is not roof waterproofing). */
const ACTIVITY = new Set([...GENERIC_WORDS].filter((w) => !SERVICE_SIDE_GENERIC.has(w)));
/** The service of `ofT` that covers a suggestion: every non-generic word of it is in that one service's name or aliases (none: null).
 *  A THIN suggestion (fewer than two non-generic words) needs more: the service must say the same thing, i.e. the non-generic words of
 *  its name, or of one of its aliases taken whole, must all be in the suggestion too. Coordinator, 12 Nov 2026 (ruling 1647, wrong keys
 *  break cross-matching): "Roof repairs" has one non-generic word, "roof", which "Roof waterproofing" contains, so it was mapped to
 *  waterproofing; a roofer who repairs is not a waterproofer. "Drivers" still maps to labour_supply.drivers_operators through its alias
 *  "drivers supply" (non-generic: drivers), which says the same thing. */
export function coveringService(label: string, ofT: CatalogueRow[]): CatalogueRow | null {
  const said = stemWords(label);
  const need = [...said].filter((w) => !GENERIC_WORDS.has(w));
  if (!need.length) return null;
  const core = (t: string) => [...stemWords(t, true)].filter((w) => !SERVICE_SIDE_GENERIC.has(w));
  const same = (t: string) => { const c = core(t); return c.length > 0 && c.every((w) => said.has(w)); };
  return ofT.find((c) => {
    const have = stemWords([c.label, ...c.aliases].join(' '), true);
    if (!need.every((w) => have.has(w))) return false;
    // a bracket in a name lists examples ("Hospitality staff (waiters, stewards, kitchen helpers)"): the name without it is what it says
    return need.length >= 2 || same(c.label) || same(c.label.replace(/\s*\([^)]*\)/g, '')) || c.aliases.some(same);
  }) ?? null;
}
/** The services of `ofT` a suggestion loosely names: all its non-generic words in the service's name or aliases, and every ACTIVITY word
 *  of the suggestion (repair, rental, installation ...) in the service's own NAME, or the two contradict: "Roof repairs" is not "Roof
 *  waterproofing" although one of its aliases is "roof leak repair" (coordinator, 12 Nov 2026); "Office staff" carries no activity word
 *  and loosely names only "Office & admin staff" on a staff card. */
export function looseServices(label: string, ofT: CatalogueRow[]): CatalogueRow[] {
  const said = stemWords(label);
  const need = [...said].filter((w) => !GENERIC_WORDS.has(w));
  if (!need.length) return [];
  return ofT.filter((c) => {
    const have = stemWords([c.label, ...c.aliases].join(' '), true);
    const name = stemWords(c.label, true);
    return need.every((w) => have.has(w)) && [...said].filter((w) => ACTIVITY.has(w)).every((w) => name.has(w));
  });
}

/**
 * THE CHIPS OF A VAGUE CARD COME FROM THE CATALOGUE (founder's own example, ruling 1647: "what sort of staff do they supply? Labourers?
 * Professional experts or freelancers?"; independent review of slice 4, 12 Nov 2026). The recorded recruitment card offered eight
 * model-written chips, two of them catalogue keys; the live catalogue holds 18 labour_supply services. So, deterministically and with no
 * model call, a vague card about a statement in trade T offers:
 *   1. the model's suggestions in its order: one that IS a key as that key (any trade); one with no key as the service of T that covers
 *      it (coveringService: every non-generic word of it in that service's name or aliases); any other exactly as the model wrote it;
 *   2. T's remaining active services in catalogue order, ONLY when at least half of the suggestions are keys of T or covered by T
 *      (round-2 review, finding B: the maintenance company's card was padded with insulation, the IT company's with cybersecurity);
 * never a key he has or decided, never the `same` twin of one already offered or held, at most VAGUE_CHIPS. "None of these" and
 * "Something else" are the card's own, always last. With no trade to draw from, the reading's options stand.
 */
export function catalogueOptions(d: Pick<SupplierServiceQuestionDraft, 'about' | 'options'>, catalogue: CatalogueRow[], twins: Map<string, Set<string>>, exclude: ReadonlySet<string>): QuestionOption[] {
  const tally = new Map<string, number>();
  for (const o of d.options) if (o.key) tally.set(o.key.split('.')[0], (tally.get(o.key.split('.')[0]) ?? 0) + 1);
  const t = (d.about.trade && catalogue.some((c) => c.trade === d.about.trade) ? d.about.trade : [...tally].sort((a, b) => b[1] - a[1])[0]?.[0]) ?? null;
  const ofT = catalogue.filter((c) => c.trade === t);
  if (!t || !ofT.length) return d.options;
  const labelOf = new Map(catalogue.map((c) => [c.key, c.label]));
  const out: QuestionOption[] = [];
  const taken = new Set<string>();
  const twinTaken = (k: string) => [...(twins.get(k) ?? [])].some((x) => taken.has(x) || exclude.has(x));
  const add = (k: string) => { if (out.length < VAGUE_CHIPS && !taken.has(k) && !exclude.has(k) && !twinTaken(k) && labelOf.has(k)) { taken.add(k); out.push({ key: k, label_en: labelOf.get(k)!, own_words: false }); } };
  let ofTrade = 0;
  for (const o of d.options) {
    if (o.key) { add(o.key); if (o.key.startsWith(t + '.')) ofTrade++; continue; }
    // the service that says the same thing; else the ONE service of the trade it loosely names, with nothing contradicting (round-3
    // review, finding 1: "Office staff" kept in his words hid "Office & admin staff", so his one chip for office staff matched nothing)
    const loose = looseServices(o.label_en, ofT);
    const c = coveringService(o.label_en, ofT) ?? (loose.length === 1 ? loose[0] : null);
    if (c) { add(c.key); ofTrade++; continue; }
    // several services name it loosely: his words stay, and those services are offered beside them (the trade is appended below)
    if (out.length < VAGUE_CHIPS && !out.some((x) => x.label_en.toLowerCase() === o.label_en.toLowerCase())) out.push(o);
  }
  if (ofTrade * 2 >= d.options.length) for (const c of ofT) add(c.key);
  return out;
}

/** The active catalogue, every page (taxonomy_trade_service through service_vocabulary.activeServiceRows); [] when it cannot be read. */
export async function readCatalogue(admin: Admin): Promise<CatalogueRow[]> {
  try {
    const { data, error } = await activeServiceRows<{ trade_code: string; code: string; label_en: string; aliases?: unknown }>(admin, 'trade_code,code,label_en,aliases');
    if (error) return [];
    return data.filter((r) => r.trade_code && r.code && r.label_en)
      .map((r) => ({ key: `${r.trade_code}.${r.code}`, trade: r.trade_code, label: r.label_en, aliases: Array.isArray(r.aliases) ? (r.aliases as unknown[]).map(String) : [] }));
  } catch { return []; }
}

/** His answer, checked against the card it answers. Code only: no model, nothing inferred. */
export function checkAnswer(q: Pick<QuestionRow, 'kind' | 'options' | 'multi'>, raw: unknown): { ok: true; answer: Answer } | { ok: false; code: string } {
  const a = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const n = q.options.length;
  const out: Answer = {};
  if (a.picked !== undefined) {
    if (!Array.isArray(a.picked)) return { ok: false, code: 'answer_bad_pick' };
    const picked = [...new Set(a.picked.map(Number))];
    if (picked.some((i) => !Number.isInteger(i) || i < 0 || i >= n)) return { ok: false, code: 'answer_bad_pick' };
    if (!q.multi && picked.length > 1) return { ok: false, code: 'answer_one_only' };
    if (picked.length) out.picked = picked.sort((x, y) => x - y);
  }
  if (a.none === true) out.none = true;
  if (a.only_inside === true && q.kind === 'shown') out.only_inside = true;
  const other = tidy(a.other).slice(0, q.kind === 'nothing' ? NOTHING_MAX : OTHER_MAX);
  if (other.length >= 2) out.other = other;
  if (q.kind === 'partner') {
    const per = (a.per && typeof a.per === 'object' ? a.per : {}) as Record<string, unknown>;
    const ok: Record<string, 'own' | 'partner' | 'no'> = {};
    for (const [i, v] of Object.entries(per)) {
      const ix = Number(i);
      if (!Number.isInteger(ix) || ix < 0 || ix >= n || !['own', 'partner', 'no'].includes(String(v))) return { ok: false, code: 'answer_bad_pick' };
      ok[String(ix)] = v as 'own' | 'partner' | 'no';
    }
    if (Object.keys(ok).length !== n) return { ok: false, code: 'answer_incomplete' };
    return { ok: true, answer: { per: ok } };
  }
  if ((out.none || out.only_inside) && (out.picked?.length || out.other)) return { ok: false, code: 'answer_conflict' };
  if (q.kind === 'nothing' && !out.other) return { ok: false, code: 'answer_empty' };
  if (!out.picked?.length && !out.none && !out.only_inside && !out.other) return { ok: false, code: 'answer_empty' };
  return { ok: true, answer: out };
}

/** service_implication's `same` rows, read only when the column exists (the catalogue branch adds it; absent = no twins). */
async function sameRows(admin: Admin): Promise<{ from: string; to: string }[]> {
  try {
    const { data, error } = await admin.from('service_implication').select('from_code,implies_trade,implies_code').eq('active', true).eq('same', true);
    if (error || !Array.isArray(data)) return [];
    return (data as { from_code: string; implies_trade: string; implies_code: string }[]).map((r) => ({ from: r.from_code, to: `${r.implies_trade}.${r.implies_code}` }));
  } catch { return []; }
}
async function rowsOf(admin: Admin, supplierId: number): Promise<QuestionRow[]> {
  const { data, error } = await admin.from(TABLE).select('id,supplier_id,kind,about,about_hash,prompt_en,options,multi,status,answer,source,asked_at,answered_at')
    .eq('supplier_id', supplierId).order('id', { ascending: true }).limit(200);
  if (error) throw new Error(error.message);
  return (data ?? []) as QuestionRow[];
}

/**
 * A READING LANDED (`listed`: the keys of his tick list; a partner card asks the partner list itself): its drafted questions are stored for this supplier (proposeFromRead calls this after the reading is stored).
 * Idempotent: a re-read of the same documents adds nothing (same kind and about_hash), never re-asks what he answered, and an
 * open or later question an earlier reading drafted that this reading no longer drafts is 'expired' (his documents changed: the
 * sentence it quoted is gone). Never throws; `error` says why nothing was stored (the table not applied yet, a write refused).
 */
export async function storeQuestions(admin: Admin, supplierId: number, drafts: SupplierServiceQuestionDraft[], listed: string[] = [], evidence?: Evidence[]): Promise<{ stored: number; expired: number; error?: string }> {
  try {
    const existing = await rowsOf(admin, supplierId);
    const { data: cap } = await admin.from('supplier_capabilities').select('services').eq('supplier_id', supplierId).maybeSingle();
    const has = new Set([...listed, ...(Array.isArray(cap?.services) ? cap!.services as string[] : [])]);
    const now = new Set(drafts.map((d) => `${d.kind}|${d.about_hash}`));
    const stale = existing.filter((r) => (r.status === 'open' || r.status === 'later') && READER_KINDS.has(r.kind)
      && /^supplier_doc_trades@/.test(r.source) && !now.has(`${r.kind}|${r.about_hash}`));
    if (stale.length) {
      const { error } = await admin.from(TABLE).update({ status: 'expired' }).eq('supplier_id', supplierId).in('id', stale.map((r) => r.id));
      if (error) return { stored: 0, expired: 0, error: error.message };
    }
    const live = existing.filter((r) => !stale.includes(r)).map((r) => r);
    const [twins, catalogue] = await Promise.all([sameRows(admin).then(twinsOf), readCatalogue(admin)]);
    const add = toStore(drafts, live, has, twins, evidence, catalogue);
    if (!add.length) return { stored: 0, expired: stale.length };
    // a question an earlier reading drafted, that expired, and that this reading drafts again: the same row is asked again
    const expiredRow = new Map(existing.filter((r) => r.status === 'expired').map((r) => [`${r.kind}|${r.about_hash}`, r.id]));
    const row = (d: SupplierServiceQuestionDraft) => ({ prompt_en: d.prompt_en, options: d.options, multi: d.multi, status: d.status, source: d.source, about: d.about });
    for (const d of add.filter((x) => expiredRow.has(`${x.kind}|${x.about_hash}`))) {
      const { error } = await admin.from(TABLE).update({ ...row(d), asked_at: new Date().toISOString(), answer: null, answered_at: null })
        .eq('supplier_id', supplierId).eq('id', expiredRow.get(`${d.kind}|${d.about_hash}`));
      if (error) return { stored: 0, expired: stale.length, error: error.message };
    }
    const fresh = add.filter((x) => !expiredRow.has(`${x.kind}|${x.about_hash}`));
    if (fresh.length) {
      const { error } = await admin.from(TABLE).upsert(fresh.map((d) => ({ supplier_id: supplierId, kind: d.kind, about_hash: d.about_hash, ...row(d) })),
        { onConflict: 'supplier_id,kind,about_hash', ignoreDuplicates: true });
      if (error) return { stored: 0, expired: stale.length, error: error.message };
    }
    return { stored: add.length, expired: stale.length };
  } catch (e) { return { stored: 0, expired: 0, error: String((e as Error)?.message || e).slice(0, 200) }; }
}

/** The questions as the Services tab shows them: every one not expired, in the order they are asked. On a new sitting (no card
 *  open and his last answer NEW_SITTING_MS ago, or none at all) the cards kept as 'later' are offered, at most LIMITS.openCards. */
export async function listQuestions(admin: Admin, supplierId: number, nowMs = Date.now()): Promise<QuestionRow[]> {
  let rows = (await rowsOf(admin, supplierId)).filter((r) => r.status !== 'expired');
  const lastAnswer = Math.max(0, ...rows.map((r) => (r.answered_at ? Date.parse(r.answered_at) : 0)));
  if (!rows.some((r) => r.status === 'open') && rows.some((r) => r.status === 'later') && nowMs - lastAnswer >= NEW_SITTING_MS) {
    const next = rows.filter((r) => r.status === 'later').sort((a, b) => rank(a.kind) - rank(b.kind) || a.id - b.id).slice(0, LIMITS.openCards).map((r) => r.id);
    const { error } = await admin.from(TABLE).update({ status: 'open' }).eq('supplier_id', supplierId).in('id', next);
    if (!error) rows = rows.map((r) => (next.includes(r.id) ? { ...r, status: 'open' as const } : r));
  }
  return rows.sort((a, b) => rank(a.kind) - rank(b.kind) || a.id - b.id);
}

export type MapWords = (text: string) => Promise<{ key: string; label_en: string }[]>;
export type AnswerOpts = { waitUntil?: ((p: Promise<unknown>) => void) | null; mapWords?: MapWords | null };

/**
 * ONE ANSWER, written at once (services_answer). The question must be his: it is read by id AND his supplier id (resolved from
 * his own session by supplier_api), so another supplier's question answers 404 exactly as one that does not exist. An answered
 * question may be answered again (he went Back and changed it); an expired one is refused (his documents changed). An answer
 * after he confirmed is stored and changes nothing he confirmed until he presses Update (the response says so: `confirmed`).
 * "Something else" words are kept in the answer at once; mapping them runs after the response.
 */
export async function answerQuestion(admin: Admin, supplierId: number, body: Record<string, unknown>, opts: AnswerOpts = {}): Promise<[number, Record<string, unknown>]> {
  const id = Number(body.id);
  if (!Number.isInteger(id) || id <= 0) return [400, { ok: false, error: 'bad_question_id', code: 'question_bad_id' }];
  const { data: q, error } = await admin.from(TABLE).select('id,supplier_id,kind,about,about_hash,prompt_en,options,multi,status,answer,source')
    .eq('id', id).eq('supplier_id', supplierId).maybeSingle();
  if (error) return [500, { ok: false, error: 'question_read_failed', code: 'question_read_failed' }];
  if (!q) return [404, { ok: false, error: 'question_not_found', code: 'question_not_found' }];
  if (q.status === 'expired') return [409, { ok: false, error: 'question_expired', code: 'question_expired' }];
  const c = checkAnswer(q as QuestionRow, body.answer);
  if (!c.ok) return [400, { ok: false, error: c.code, code: c.code }];
  const at = new Date().toISOString();
  const { data: saved, error: upErr } = await admin.from(TABLE).update({ status: 'answered', answer: c.answer, answered_at: at })
    .eq('id', id).eq('supplier_id', supplierId).select('id,kind,status,answer,answered_at').maybeSingle();
  if (upErr || !saved) return [500, { ok: false, error: 'answer_write_failed', code: 'answer_write_failed' }];
  const { data: cap } = await admin.from('supplier_capabilities').select('confirmed_at').eq('supplier_id', supplierId).maybeSingle();
  const words = c.answer.other;
  if (words && opts.mapWords && q.kind !== 'new_key') {
    const job = mapOtherWords(admin, supplierId, q as QuestionRow, words, opts.mapWords);
    if (opts.waitUntil) opts.waitUntil(job); else await job;
  }
  return [200, { ok: true, question: saved, confirmed: !!cap?.confirmed_at }];
}

/** "Something else" words, mapped behind (the existing rewrite path): a key that fits and that he has not decided comes back as
 *  one 'new_key' card quoting his words. His words stay his words in the answer whatever this finds. Never throws. */
export async function mapOtherWords(admin: Admin, supplierId: number, q: QuestionRow, words: string, mapWords: MapWords): Promise<void> {
  try {
    const found = await mapWords(words);
    const rows = await rowsOf(admin, supplierId);
    const { data: cap } = await admin.from('supplier_capabilities').select('services').eq('supplier_id', supplierId).maybeSingle();
    const has = new Set(Array.isArray(cap?.services) ? cap!.services as string[] : []);
    const decided = decidedKeys(rows);
    const options = found.filter((o, i) => found.findIndex((x) => x.key === o.key) === i && !has.has(o.key) && !decided.has(o.key))
      .slice(0, LIMITS.options).map((o) => ({ key: o.key, label_en: o.label_en, own_words: false }));
    if (!options.length) return;
    const about = { quote: words, doc: null, trade: options[0].key.split('.')[0], words: [words], from_question: q.id };
    const { error } = await admin.from(TABLE).upsert([{ supplier_id: supplierId, kind: 'new_key', about, about_hash: aboutHash('new_key', { quote: words.toLowerCase() }),
      prompt_en: `You wrote "${words}". Is it one of these?`, options, multi: true, status: 'open', source: 'something_else' }],
    { onConflict: 'supplier_id,kind,about_hash', ignoreDuplicates: true });
    if (error) console.error(JSON.stringify({ at: 'supplier_service_questions.mapOtherWords', supplier: supplierId, error: error.message }));
  } catch (e) { console.error(JSON.stringify({ at: 'supplier_service_questions.mapOtherWords', supplier: supplierId, error: String((e as Error)?.message || e).slice(0, 200) })); }
}

/** The answered questions as the confirmation ledger records them (capabilityConfirm): [] before the table exists. */
export async function answeredForLedger(admin: Admin, supplierId: number): Promise<{ id: number; kind: string; about: unknown; options: unknown; answer: unknown; answered_at: string | null }[]> {
  try {
    const { data, error } = await admin.from(TABLE).select('id,kind,about,options,answer,answered_at').eq('supplier_id', supplierId).eq('status', 'answered').limit(200);
    return error || !Array.isArray(data) ? [] : data;
  } catch { return []; }
}
