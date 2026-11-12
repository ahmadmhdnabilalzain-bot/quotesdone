// A SUPPLIER'S PROFILE IS READ FIRST AND MAPPED SECOND (12 Nov 2026). Seat: sales_engineer (the reading); it_engineer (the build).
// Founder rulings 1647 ("read the profile really well ... be smart about the services each supplier does ... if this step is done
// wrong everything after it goes wrong"), 1627 (the AI reads the documents as a person would; not word matching, not the licence)
// and 1628 (the AI proposes, the supplier confirms, matching is code over confirmed keys). Design and measurement:
// docs/reports/2026-11-12-supplier-service-profiling.md, Part 3 (3.1 the reading, 3.2 umbrella, 3.3 vagueness, 3.10 the table).
//
// WHY TWO STEPS. One prompt carried the whole catalogue (55,000-69,000 tokens) and 16 precision rules that suppressed everything the
// catalogue could not name: on 12 hard profiles it found 85 of 114 stated services (47% on the broad, vague or glossy ones), dropped
// 22 of 22 partner services, asked nothing and left 4 of 12 companies "held" for ever. Read first, map second:
//   A. THE READING (profileReadSystem): the documents and our 223 trade NAMES, no services. Every specific service or product line the
//      documents evidence, each with its sentence and its BASIS (stated / shown / partner / brand), the vague statements with the one
//      question to ask, what a company of this kind commonly also does, the licence's fit, brands, areas, roles.
//   B. THE MAPPING (profileMapSystem): each phrase of A onto the service keys it IS, or none, against only the services of the trades
//      A named, their curated adjacent trades and their umbrella parents and children.
// CODE CHECKS, AND ONLY CHECKS (checkReading, applyMapping): a quote must be in a document that is not the trade licence, a key must
// be in the catalogue and in the slice the mapping was shown. A claim that fails is dropped, never repaired.
// CODE DECIDES WHAT IS LISTED AND WHAT IS ASKED (proposalOf, pure): stated + verified + mapped is the tick list, UNTICKED; partner,
// shown and brand are asked; a phrase with no key is kept in his own words; a trade with no service is asked; nothing is ever written
// into supplier_capabilities.services from here (only his tick, capabilityConfirm).
// One reading, not a vote: there is no "held". A reading that finds nothing is the question "what does your company do".

import { answerJson, choiceTaskClass, gatewayCall, inPool, quoteFinder, quoteKey, textChunks } from './supplier_trade_choice.ts';
import { activeServiceRows } from './service_vocabulary.ts';
import { surfaceEffort } from './effort_policy.ts';

export const PROFILE_READER = 'supplier_doc_trades@5';
/** Step A's entry in effort_policy.SURFACES: the clock it runs inside and the effort measured to fit it. */
export const READ_SURFACE = 'supplier_doc_trades.profile_reading';

// ── THE CONTRACT ────────────────────────────────────────────────────────────────────────────────────────────────────────
export type Basis = 'stated' | 'shown' | 'partner' | 'brand';
/** One thing the documents evidence, checked: its quote is in `doc` (a document that is not the licence). `keys` after the mapping;
 *  `code_keys`: those of `keys` code matched by the catalogue's own name or approved alias (the rest the model mapped). `licence`: the
 *  reading's judgement of this claim against the licence's activities (as reader @4 judged each service). */
export type Claim = { words: string; quote: string; basis: Basis; partner_name: string | null; trade: string | null; doc: string; keys: string[];
  code_keys?: string[]; licence?: 'covered' | 'not_covered' | 'unclear' };
export type ReadOption = { label: string; trade: string | null; keys: string[] };
export type VagueEntry = { quote: string; doc: string | null; why: string; ask: string; options: ReadOption[] };
export type AlsoAsk = { because: string; options: ReadOption[] };
export type LicenceFit = { covers_profile: 'yes' | 'partly' | 'no' | 'no_licence'; note: string };
/** What step A read and step B mapped, after code's checks. Stored in supplier_capabilities.source_docs.reading with the proposal. */
export type ProfileReading = {
  summary: string; evidence: Claim[]; vague: VagueEntry[]; also_ask: AlsoAsk[]; licence: LicenceFit;
  brands: { name: string; relation: string; goods: string }[]; areas: string[]; roles: string[];
  rejected: { what: string; why: string }[];
};
/** The catalogue slice code needs: every active trade with its active services (read through service_vocabulary.activeServiceRows,
 *  all of them), its umbrella parent, and the curated adjacent pairs (taxonomy_trade_adjacent, active). */
export type Taxonomy = {
  trades: { code: string; label: string; umbrella_code?: string | null; services: { key: string; label: string; aliases?: string[] }[] }[];
  adjacent: [string, string][];
};
/** public.service_implication, active rows: `from` is a service key or a trade code; `to` the implied service key. */
export type Implication = { from: string; to: string; reason?: string | null };

/**
 * THE QUESTION ROWS (slice 4 builds the table, the actions and the cards against THIS shape; it is produced here, from slice 3).
 * One row of public.supplier_service_question as designed in the report's section 3.10, without the columns the database owns
 * (`id`, `supplier_id`, `asked_at`, `answered_at`, `reminded_at`, `answer`). The writer adds `supplier_id` and inserts on the
 * unique (supplier_id, kind, about_hash), so a question is never asked twice.
 *   kind       which card: 'nothing' (the documents do not say what the company does), 'vague' (a statement names a category,
 *              not the thing), 'trade_services' (a trade evidenced with no service under it), 'partner' (delivered through
 *              someone else: own team / partner / not offered, per option), 'shown' (only in project captions or a brand list:
 *              "do you take these as jobs on their own?"), 'umbrella' (what a company like his commonly also does), 'licence'
 *              (the licence and the profile disagree). The later kinds of 3.10 (new_evidence, quoted, declined, new_key,
 *              still_right) are raised by other triggers (slice 7), never by a reading.
 *   about      his own sentence and where it is: { quote, doc, trade, words?, partner_name? } (null where none applies)
 *   about_hash a stable hash of the FACTS the question is about (kind, trade, the document, the option keys; never the model's wording,
 *              review of 12 Nov 2026): a re-read of the same documents drafts the same hash, so an answered question is never re-asked
 *   prompt_en  the card's question, in English (ruling 1008), quoting his own words where there are any
 *   options    at most 8 chips: a catalogue key with its label, or (key null, own_words true) a label kept in his own words if chosen.
 *              "None of these" and "Something else" are the card's own, never options here.
 *   multi      true when he may tap several options
 *   status     'open' (asked now: at most 5 cards in one sitting, in the order nothing, vague, trade_services, partner, shown,
 *              umbrella, licence) or 'later' (stored, offered on his next visit; never discarded)
 *   source     the reader version that asked it (PROFILE_READER)
 */
export type QuestionKind = 'nothing' | 'vague' | 'trade_services' | 'partner' | 'shown' | 'umbrella' | 'licence';
export type QuestionOption = { key: string | null; label_en: string; own_words: boolean };
export type SupplierServiceQuestionDraft = {
  kind: QuestionKind;
  about: { quote: string | null; doc: string | null; trade: string | null; words?: string[]; partner_name?: string | null };
  about_hash: string; prompt_en: string; options: QuestionOption[]; multi: boolean; status: 'open' | 'later'; source: string;
};
/** A service listed for his tick (never ticked for him), with the sentence it was read from. `check` (added 12 Nov 2026, review of
 *  branch 2): the key rests on the model's mapping alone, with no word of its name in his sentence: shown "please check" and left out of
 *  "Tick all". `licence`: the claim's licence judgement. Both optional: a reader of the first contract ignores them. */
export type TickItem = { key: string; label_en: string; trade: string; words: string; quote: string; doc: string; check?: boolean; licence?: 'covered' | 'not_covered' | 'unclear' };
/** A service the documents say is delivered through someone else: listed with its sentence, marked, unticked; asked in slice 4. */
export type PartnerItem = TickItem & { partner_name: string | null };
/** A phrase no key covers: kept exactly as his words, never dropped and never mapped onto the nearest key. */
export type OwnWordsItem = { words: string; quote: string; basis: Basis; trade: string | null; doc: string };
/** `trades`: the trades LISTED for him, only those in which a stated claim mapped to a key (review of branch 2, 12 Nov 2026).
 *  `shown` (added 12 Nov 2026): services seen only in his project captions or brand list, listed until slice 4 asks them, marked, unticked. */
export type Proposal = {
  trades: { code: string; quote: string; words: string; doc: string }[];
  tick: TickItem[]; partner: PartnerItem[]; own_words: OwnWordsItem[]; shown: (TickItem & { basis: 'shown' | 'brand' })[];
  questions: SupplierServiceQuestionDraft[];
};

export const LIMITS = { openCards: 5, options: 8, umbrellaChips: 12, umbrellaCards: 2, vague: 3, alsoAsk: 8 } as const;
// Step A's parts: 4,000 characters each (the chooser's were 14,000), five read at once. Measured 12 Nov 2026 on the hard-profile set at
// medium, run 519c9b06: with 6,000-character parts the glossy 30-page profile (5,300 characters in one part) took 112.5 s in one call,
// past the reading's 110 s clock; every other reading call was 18-75 s on profiles of 400-2,000 characters. Step B: 8 phrases a call,
// every call at once, each part's phrases mapped as soon as that part is read (review of branch 2: 15 phrases a call reached 110.8 s of
// the 115 s wall in run 1f18dbf5, and a call past it lost its phrases).
export const READ_PART_CHARS = 4_000, MAP_PHRASES = 8, PARALLEL = 5;

const str = (x: unknown) => String(x ?? '').trim();
const BASES = new Set<Basis>(['stated', 'shown', 'partner', 'brand']);
const HEADING_ONLY = /^(?:\d+ )?(?:our |core |main |key |list of )*(?:services?|products?|product range|scope(?: of (?:work|works|services|supply))?|activities|what we do|capabilities|divisions|solutions|expertise)$/;

// ── THE PROMPTS (lifted from the prototype measured in report 2.4, run 78f4e8f5: 89 of 91 stated services) ─────────────
export function profileReadSystem(trades: { code: string; label: string }[]): string {
  return `You are the sales engineer of a UAE business-to-business procurement marketplace. You read ALL the documents one supplier company uploaded (company profile, catalogues, trade licence) the way an experienced person would, to understand everything this company can do for a customer. Your reading decides which customer requests reach this supplier: a service you miss is business the supplier never sees, and a service you invent is a request sent to a company that cannot quote it.

Our trades (code = name). Use them only to say which trade a service belongs to:
${trades.map((t) => `${t.code} = ${t.label}`).join('\n')}

Return STRICT JSON only, in this shape:
{"summary":"two plain English sentences saying what this company is and does",
 "evidence":[{"words":"a short English name for this ONE service or product line as a customer would ask for it, at most 8 words (translate Arabic)","quote":"ONE line copied EXACTLY, word for word, from the documents, in its original language, that shows it","basis":"stated|shown|partner|brand","partner_name":null,"trade":"the trade code it belongs to, or null when none of our trades covers it","licence":"covered when the trade licence's activities cover it, not_covered when a licence is given and does not, unclear when no licence is given"}],
 "vague":[{"quote":"the vague line, copied exactly","why":"what a customer request could not be matched on","ask":"the one short question a sharp sales engineer would ask the supplier, in plain English","options":[{"label":"a specific option, 1 to 5 words","trade":"trade code or null"}]}],
 "also_ask":[{"because":"the evidence that makes these likely, in a few words","options":[{"label":"1 to 5 words","trade":"trade code or null"}]}],
 "licence":{"covers_profile":"yes|partly|no|no_licence","note":"one sentence when the licence and the other documents disagree, else empty"},
 "brands":[{"name":"brand","relation":"authorised_distributor|stocked|used","goods":"what that brand's goods are, a few words"}],
 "areas":["emirates the documents say the company serves"],
 "roles":["at most two of: manufacturer|distributor|supplier|installer|contractor|turnkey_fitout|maintenance|consultant"]}

RULES
1. EVERYTHING THE DOCUMENTS EVIDENCE, ONE ITEM EACH. A broad word covers many services: list every SPECIFIC service or product line the documents show, one evidence item per service (a line naming three services is three items, each quoting that line). One item per distinct service a customer would ask for: do not split one service into its parts (planting, lawns and palm trees are one item, garden planting). Read the whole text: lists, headings, sentences, project captions, brand lists. A service the documents show for different kinds of premises is one item per kind they show (office fit-out, retail fit-out, restaurant fit-out are three items), and each work a project caption lists is an item of its own (a caption "kitchens, wardrobes, wood panelling" is three items).
2. BASIS says how the documents show it.
   "stated": the company says it offers this: an item of its services or products list, a heading, its title or tagline, or a sentence saying what it does.
   "shown": it appears only in the company's own project descriptions or captions (work it has done), not in a statement of what it offers.
   "partner": the documents say it is delivered through a partner, a subcontractor, a sister or group company, the manufacturer, or is "arranged", "managed" or "provided" through someone else. Give "partner_name" when the documents name them. Never mark partner work as stated.
   "brand": it follows only from a brand the company lists (a named brand's goods are a product line the documents do not otherwise state).
3. THE QUOTE IS THE PROOF. Copy it exactly from a document that is NOT the trade licence. The trade licence lists permitted activities; it says what the company may do, not what it does, so nothing is evidenced from the licence alone.
4. NEVER FROM: the company's or another company's name, a client, a certificate or standard it holds, a policy, a value, a vision or mission statement, a slogan, its staff or organisation chart, equipment or software it uses in its own work, or an internal function. History the company has left behind ("founded as a garments trader") is not a service. A FEATURE of how it delivers its service is not a service of its own: the visas, insurance and accommodation of the staff it supplies, delivery of its own goods, a warranty, a replacement guarantee, a helpdesk, a free site visit.
5. GOODS ARE NOT WORKS. Name goods as goods ("power tools supply") and works as works ("AC installation"). A company that only sells is never given installation or contracting work unless the documents say it does that work.
6. VAGUE. A statement of what the company OFFERS is vague when it names a category without saying the thing: "we supply staff and similar services", "all kinds of building materials", "all kinds of maintenance works", "and much more", "etc.", "solutions". Do NOT turn a vague statement into evidence items for services it does not name. Put it in "vague" with ONE question and 4 to 9 specific options a UAE company of this kind commonly offers, most common first. THE QUESTION ASKS FOR THE SPECIFIC KINDS OF THE MAIN THING LEFT OPEN: for a company that supplies staff, what sort of staff (general labourers, skilled tradesmen, drivers, cleaners, security guards, hospitality staff, office staff, engineers and technicians, freelancers); for a materials trader, which materials it stocks; for a maintenance company, which works it carries out. Never ask a general "what other services do you provide" question while the main offer itself is unspecified. When a line is partly specific ("A/C, plumbing, electrical, etc."), the named things are evidence items and the open part is a vague entry. A slogan or a marketing sentence is not a vague statement of offer. At most 3 vague entries, the one about the company's main offer first.
7. ALSO ASK (thinking of everything they can do). Think of what a company of this kind commonly does beyond what its documents show: at most 8 options in total, most likely first, only services a real company like this one is likely to do, never something already in "evidence" or "vague". Leave it empty when the documents are already complete and specific. These become questions to the supplier; they are never assumed.
8. NOTHING THERE. When the documents do not say what the company does, return "evidence":[] and one "vague" entry asking what the company does, with "options":[].
9. English only in "summary", "words", "ask", "why", "because" and every option. Quotes stay in the document's language.`;
}

export function profileMapSystem(slice: string): string {
  return `You map short descriptions of a UAE supplier's services and products onto our catalogue of service keys. This is the part of the catalogue for this supplier's trades. Each line is: trade code = trade name (services: service key = service name; ...).
${slice}

You are given numbered phrases; some carry the line of the supplier's document they came from, for context. For EACH phrase return the catalogue service keys whose name covers exactly that work or those goods.
RULES
1. THE KEY THAT NAMES THIS WORK, OR NONE. Usually one key, at most two (two only when the catalogue lists the same work under two trades, or the phrase names two things). A key fits when its name says the same work in other words ("monthly garden maintenance" is Garden maintenance). When no service key covers it, return "keys":[] - never a merely related key. A phrase with no key is kept in the supplier's own words; nothing is lost by leaving it empty.
2. "trade": the catalogue trade the phrase belongs to, when one does, even when no service key fits; otherwise null.
3. Goods are not works: a supply or trading phrase gets a goods key (a product line of a goods trade), never an installation or contracting key, and the reverse.
4. Judge the phrase by what it IS, not by a word in it. A part of a job is not the trade's whole work: boundary walls are not "Blockwork & masonry", garden lighting is not "Lighting supply & installation". A phrase that names one work with a word about how it is done ("AC duct cleaning and disinfection") takes the key of that work only, never a second key for the extra word.
5. THE PHRASE'S OWN TRADE FIRST. When its own trade (the "trade" the phrase was read with) has a key for this work, use that key; take a key of another trade only when the phrase is that other trade's work, never because the other trade has a similar name ("DEWA and Civil Defence approvals" of an MEP contractor is MEP authority approvals, not engineering consultancy).
Return STRICT JSON only: {"map":[{"i":1,"keys":["trade.service"],"trade":"trade code or null"}]}`;
}

// ── CODE'S CHECKS ───────────────────────────────────────────────────────────────────────────────────────────────────────
export type ReadDoc = { path: string; name: string; kind: 'profile' | 'catalogue' | 'licence'; text: string };

/** Step A's answer, checked by code: every evidence quote is in a document that is not the licence (the document it is in is
 *  recorded), every trade is one of ours or null, a basis that is not one of the four is asked (shown), never listed. */
export function checkReading(content: string, docs: ReadDoc[], tradeCodes: ReadonlySet<string>): { ok: true; reading: ProfileReading } | { ok: false; error: string } {
  const p = answerJson(content, 'evidence') as Record<string, unknown> | null;
  if (!p || !Array.isArray(p.evidence)) return { ok: false, error: 'the reading was not the JSON asked for: ' + JSON.stringify(String(content ?? '').slice(0, 120)) };
  const finders = docs.filter((d) => d.kind !== 'licence' && d.text.trim()).map((d) => ({ d, has: quoteFinder(d.text) }));
  const docOf = (q: string) => (q && quoteKey(q).length >= 3 ? finders.find((f) => f.has(q))?.d.path ?? null : null);
  const trade = (x: unknown) => (tradeCodes.has(str(x)) ? str(x) : null);
  const rejected: { what: string; why: string }[] = [];
  const evidence: Claim[] = [];
  for (const e of p.evidence as Record<string, unknown>[]) {
    const words = str(e?.words).slice(0, 120), quote = str(e?.quote).slice(0, 400);
    if (!words) continue;
    // a heading alone ("Our services", "Products") is where a list starts, not the proof of any one thing on it (review of branch 2)
    if (HEADING_ONLY.test(quoteKey(quote))) { rejected.push({ what: words, why: `a heading alone proves nothing: "${quote.slice(0, 80)}"` }); continue; }
    const doc = docOf(quote);
    if (!doc) { rejected.push({ what: words, why: `the quote is not in a document that is not the trade licence: "${quote.slice(0, 80)}"` }); continue; }
    const b = str(e?.basis) as Basis;
    if (evidence.some((x) => x.words.toLowerCase() === words.toLowerCase() && x.quote === quote)) continue;
    // no judgement given: none recorded, and the profile's fit stands for it (supplier_doc_trades.readInTwoSteps)
    const lic = str(e?.licence);
    evidence.push({ words, quote, basis: BASES.has(b) ? b : 'shown', partner_name: str(e?.partner_name) || null, trade: trade(e?.trade), doc, keys: [],
      ...(lic === 'covered' || lic === 'not_covered' || lic === 'unclear' ? { licence: lic as 'covered' | 'not_covered' | 'unclear' } : {}) });
  }
  const options = (a: unknown): ReadOption[] => (Array.isArray(a) ? a : []).map((o) => ({ label: str((o as Record<string, unknown>)?.label ?? o).slice(0, 80), trade: trade((o as Record<string, unknown>)?.trade), keys: [] }))
    .filter((o) => o.label).slice(0, 9);
  const vague: VagueEntry[] = (Array.isArray(p.vague) ? p.vague as Record<string, unknown>[] : []).slice(0, LIMITS.vague).map((v) => {
    const quote = str(v?.quote).slice(0, 400);
    return { quote, doc: docOf(quote), why: str(v?.why).slice(0, 240), ask: str(v?.ask).slice(0, 240), options: options(v?.options) };
  }).filter((v) => v.ask);
  const also_ask: AlsoAsk[] = (Array.isArray(p.also_ask) ? p.also_ask as Record<string, unknown>[] : []).map((v) => ({ because: str(v?.because).slice(0, 200), options: options(v?.options) }))
    .filter((v) => v.options.length);
  const lic = (p.licence ?? {}) as Record<string, unknown>;
  const cov = str(lic.covers_profile);
  return { ok: true, reading: {
    summary: str(p.summary).slice(0, 600), evidence, vague, also_ask,
    licence: { covers_profile: (['yes', 'partly', 'no', 'no_licence'].includes(cov) ? cov : 'partly') as LicenceFit['covers_profile'], note: str(lic.note).slice(0, 300) },
    brands: (Array.isArray(p.brands) ? p.brands as Record<string, unknown>[] : []).map((b) => ({ name: str(b?.name).slice(0, 80), relation: str(b?.relation).slice(0, 40), goods: str(b?.goods).slice(0, 120) })).filter((b) => b.name).slice(0, 40),
    areas: (Array.isArray(p.areas) ? p.areas : []).map(str).filter(Boolean).slice(0, 7),
    roles: (Array.isArray(p.roles) ? p.roles : []).map(str).filter(Boolean).slice(0, 2),
    rejected } };
}

/** Several parts' readings as one: claims once (same words and quote), the first part's summary and licence fit. */
export function mergeReadings(rs: ProfileReading[]): ProfileReading {
  const out: ProfileReading = { ...rs[0], evidence: [], vague: [], also_ask: [], brands: [], areas: [], roles: [], rejected: [] };
  for (const r of rs) {
    for (const e of r.evidence) if (!out.evidence.some((x) => x.words.toLowerCase() === e.words.toLowerCase())) out.evidence.push(e);
    for (const v of r.vague) if (out.vague.length < LIMITS.vague && !out.vague.some((x) => x.ask === v.ask)) out.vague.push(v);
    for (const a of r.also_ask) out.also_ask.push(a);
    for (const b of r.brands) if (!out.brands.some((x) => x.name.toLowerCase() === b.name.toLowerCase())) out.brands.push(b);
    for (const a of r.areas) if (!out.areas.includes(a)) out.areas.push(a);
    for (const a of r.roles) if (!out.roles.includes(a) && out.roles.length < 2) out.roles.push(a);
    out.rejected.push(...r.rejected);
  }
  // a part that read nothing while another read something: its "what does the company do" entry is not a question
  if (out.evidence.length) out.vague = out.vague.filter((v) => v.options.length || v.quote);
  return out;
}

/** The trades the mapping is shown for a set of trades: they, their curated adjacent trades, their umbrella parents and children. */
export function sliceTrades(named: string[], tax: Taxonomy): string[] {
  const T = new Set(named);
  for (const [a, b] of tax.adjacent) { if (named.includes(a)) T.add(b); if (named.includes(b)) T.add(a); }
  for (const t of tax.trades) { if (t.umbrella_code && named.includes(t.umbrella_code)) T.add(t.code); if (named.includes(t.code) && t.umbrella_code) T.add(t.umbrella_code); }
  return tax.trades.filter((t) => T.has(t.code)).map((t) => t.code);
}
export const sliceText = (codes: string[], tax: Taxonomy) => tax.trades.filter((t) => codes.includes(t.code))
  .map((t) => `${t.code} = ${t.label} (services: ${t.services.map((s) => `${s.key} = ${s.label}`).join('; ')})`).join('\n');

/** Every phrase step B maps: the claims (with their line, for context), then every option of the vague and also-ask entries. Only
 *  phrases that carry one of our trades are mapped (a phrase with no trade has no slice of the catalogue to be mapped onto). */
export type Phrase = { n: number; text: string; words: string; trade: string; ref: { keys: string[]; trade: string | null; code_keys?: string[] } };
export function phrasesOf(r: ProfileReading): Phrase[] {
  const all: { text: string; words: string; ref: { keys: string[]; trade: string | null; code_keys?: string[] } }[] = [
    ...r.evidence.map((e) => ({ text: `${e.words}  [trade: ${e.trade}; from: ${e.quote.slice(0, 160)}]`, words: e.words, ref: e })),
    ...r.vague.flatMap((v) => v.options.map((o) => ({ text: o.label, words: o.label, ref: o as ReadOption & { code_keys?: string[] } }))),
    ...r.also_ask.flatMap((a) => a.options.map((o) => ({ text: o.label, words: o.label, ref: o as ReadOption & { code_keys?: string[] } }))),
  ];
  return all.map((x, i) => ({ n: i + 1, text: x.text, words: x.words, trade: x.ref.trade ?? '', ref: x.ref })).filter((x) => x.trade);
}

// MAPPED BY CODE FIRST (review of branch 2, 12 Nov 2026: a key listed in one run and not the other, H04 mep_amc, H08 deep_cleaning, came from
// the model's mapping). A phrase that IS a catalogue service's own name or one of its approved aliases (letters and digits, "and" aside) is
// that key, by code, every time; only the phrases code cannot place go to the model.
const nameKey = (x: string) => quoteKey(x).split(' ').filter((w) => w && w !== 'and' && w !== 'the').join(' ');
const NAME_INDEX = new WeakMap<Taxonomy, Map<string, string[]>>();
export function nameIndex(tax: Taxonomy): Map<string, string[]> {
  let m = NAME_INDEX.get(tax);
  if (m) return m;
  m = new Map();
  for (const t of tax.trades) for (const sv of t.services) for (const n of [sv.label, ...(sv.aliases ?? [])]) {
    const k = nameKey(n); if (k.length < 3) continue;
    const a = m.get(k) ?? []; if (!a.includes(sv.key)) a.push(sv.key); m.set(k, a);
  }
  NAME_INDEX.set(tax, m);
  return m;
}
/** The keys a phrase's words name exactly, among the trades its mapping would be shown; [] when code cannot place it. */
export function codeKeysOf(ph: Phrase, tax: Taxonomy): string[] {
  const shown = new Set(sliceTrades([ph.trade], tax));
  return (nameIndex(tax).get(nameKey(ph.words)) ?? []).filter((k) => shown.has(k.split('.')[0])).slice(0, 2);
}
/** Step B's answer for one call, checked by code: a key must be a catalogue key of a trade the call was shown. */
export function applyMapping(content: string, phrases: Phrase[], shown: ReadonlySet<string>, tax: Taxonomy, rejected: { what: string; why: string }[]): boolean {
  const m = answerJson(content, 'map') as { map?: unknown } | null;
  if (!m || !Array.isArray(m.map)) return false;
  const keys = new Set(tax.trades.flatMap((t) => t.services.map((s) => s.key)));
  const byN = new Map(phrases.map((p) => [p.n, p]));
  for (const e of m.map as Record<string, unknown>[]) {
    const ph = byN.get(Number(e?.i)); if (!ph) continue;
    for (const key of (Array.isArray(e?.keys) ? e.keys : []).map(String).slice(0, 2)) {
      if (!keys.has(key)) { rejected.push({ what: key, why: 'not a catalogue service key' }); continue; }
      if (!shown.has(key.split('.')[0])) { rejected.push({ what: key, why: 'not a service of a trade the mapping was shown' }); continue; }
      if (!ph.ref.keys.includes(key)) ph.ref.keys.push(key);
    }
    const t = str(e?.trade); if (shown.has(t)) ph.ref.trade = t;
  }
  return true;
}

// ── THE PROPOSAL (pure): what is listed, what is asked, what is kept in his words ────────────────────────────────────────
/** FNV-1a over the kind and the about, hex: stable across runs and runtimes (the unique key's third column). */
export function aboutHash(kind: string, about: unknown): string {
  let h = 0x811c9dc5;
  for (const ch of kind + '|' + JSON.stringify(about)) { h ^= ch.codePointAt(0)!; h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16).padStart(8, '0');
}
const ORDER: QuestionKind[] = ['nothing', 'vague', 'trade_services', 'partner', 'shown', 'umbrella', 'licence'];
const quoted = (q: string) => `"${q.replace(/\s+/g, ' ').slice(0, 160)}"`;
const listOf = (a: string[]) => a.length <= 1 ? a.join('') : `${a.slice(0, -1).join(', ')} and ${a[a.length - 1]}`;

export function proposalOf(r: ProfileReading, tax: Taxonomy, implications: Implication[], opts: { licenceActivities?: string[]; source?: string } = {}): Proposal {
  const source = opts.source ?? PROFILE_READER;
  const tradeOf = new Map(tax.trades.map((t) => [t.code, t]));
  const labelOf = new Map(tax.trades.flatMap((t) => t.services.map((s) => [s.key, s.label] as const)));
  const tick: TickItem[] = [], partner: PartnerItem[] = [], own_words: OwnWordsItem[] = [];
  // a key the model alone mapped, with no word of its name in his sentence, is listed "please check" and left out of "Tick all"
  const sig = (x: string) => quoteKey(x).split(' ').filter((w) => w.length >= 4 && !/^(supply|installation|install|services?|works?|and|with|systems?|maintenance|repairs?|contracting|contracts?|equipment|general|design|annual|complete|full)$/.test(w));
  // (a name with no distinctive word, "Maintenance & annual contracts", cannot be checked this way and is not marked)
  const checkOf = (e: Claim, k: string) => { if ((e.code_keys ?? []).includes(k)) return false; const w = sig(labelOf.get(k) ?? '');
    return w.length > 0 && !w.some((x) => quoteKey(e.words + ' ' + e.quote).includes(x.slice(0, 5))); };
  const item = (e: Claim, key: string): TickItem => ({ key, label_en: labelOf.get(key) ?? key, trade: key.split('.')[0], words: e.words, quote: e.quote, doc: e.doc,
    ...(checkOf(e, key) ? { check: true } : {}), ...(e.licence ? { licence: e.licence } : {}) });
  // stated, verified (checkReading) and mapped: listed for his tick
  for (const e of r.evidence) if (e.basis === 'stated') for (const k of e.keys) if (!tick.some((x) => x.key === k)) tick.push(item(e, k));
  // through a partner: listed with its sentence, marked, never as his own; a key he also states himself is his own
  for (const e of r.evidence) if (e.basis === 'partner') for (const k of e.keys) if (!tick.some((x) => x.key === k) && !partner.some((x) => x.key === k)) partner.push({ ...item(e, k), partner_name: e.partner_name });
  // a phrase no key covers is kept in his words (stated and partner are his statements; shown and brand are asked below)
  for (const e of r.evidence) if (!e.keys.length) own_words.push({ words: e.words, quote: e.quote, basis: e.basis, trade: e.trade, doc: e.doc });
  const known = new Set([...tick, ...partner].map((x) => x.key));
  const shownItems = r.evidence.filter((e) => (e.basis === 'shown' || e.basis === 'brand') && e.keys.some((k) => !known.has(k)));
  // SHOWN, LISTED UNTIL SLICE 4 ASKS IT (review of branch 2): nothing the reading found is invisible to him; marked, unticked
  const shown: Proposal['shown'] = [];
  for (const e of shownItems) for (const k of e.keys) if (!known.has(k) && !shown.some((x) => x.key === k)) shown.push({ ...item(e, k), basis: e.basis as 'shown' | 'brand' });
  // THE TRADES LISTED FOR HIM: only those in which a STATED claim mapped to a key (review of branch 2, 12 Nov 2026: every trade any claim
  // named, his own words, project captions and brands included, put 115 trades on 16 suppliers, 12 of them wrong, e.g. a tools distributor
  // given cleaning from "Karcher"; a trade alone receives every request that names no service, and Confirm kept them all)
  const trades: Proposal['trades'] = [];
  // (a "please check" listing lists no trade: its trade becomes his when he ticks it)
  for (const x of tick) if (!x.check && tradeOf.has(x.trade) && !trades.some((t) => t.code === x.trade)) trades.push({ code: x.trade, quote: x.quote, words: x.words, doc: x.doc });
  // THE TRADES ASKED, NOT LISTED: a stated claim of a trade no key covers (too broad to match on), and the trade a vague statement of offer
  // names ("we supply staff and similar services" is labour supply: the trade most of its options are keys of, when at least two are)
  const askTrades: Proposal['trades'] = [];
  for (const e of r.evidence) if (e.basis === 'stated' && !e.keys.length && e.trade && tradeOf.has(e.trade) && !trades.some((t) => t.code === e.trade) && !askTrades.some((t) => t.code === e.trade)) askTrades.push({ code: e.trade, quote: e.quote, words: e.words, doc: e.doc });
  for (const v of r.vague) {
    const n = new Map<string, number>();
    for (const o of v.options) for (const t of new Set(o.keys.map((k) => k.split('.')[0]))) n.set(t, (n.get(t) ?? 0) + 1);
    const [top, c] = [...n].sort((a, b) => b[1] - a[1])[0] ?? [null, 0];
    if (top && c >= 2 && tradeOf.has(top) && v.doc && !trades.some((t) => t.code === top) && !askTrades.some((t) => t.code === top)) askTrades.push({ code: top, quote: v.quote, words: v.ask, doc: v.doc });
  }
  const qs: Omit<SupplierServiceQuestionDraft, 'status' | 'about_hash' | 'source'>[] = [];
  const opt = (o: ReadOption): QuestionOption[] => o.keys.length ? o.keys.map((k) => ({ key: k, label_en: labelOf.get(k) ?? o.label, own_words: false })) : [{ key: null, label_en: o.label, own_words: true }];
  const dedupe = (a: QuestionOption[]) => a.filter((o, i) => a.findIndex((x) => (o.key ? x.key === o.key : !x.key && x.label_en.toLowerCase() === o.label_en.toLowerCase())) === i).slice(0, LIMITS.options);
  // NOTHING: the documents do not say what the company does
  const vagueAsked = r.vague.filter((v) => v.options.length);
  if (!r.evidence.length && !vagueAsked.length) {
    qs.push({ kind: 'nothing', about: { quote: null, doc: null, trade: null }, prompt_en: 'Your profile does not say what your company does. Tell us in a line or two.', options: [], multi: false });
  }
  // VAGUE: his own sentence, the one question, its options (a key wherever one exists, else his words if he picks it)
  for (const v of vagueAsked) {
    // his sentence is quoted only when checkReading found it in his own text (v.doc); otherwise the question is asked without a quote
    qs.push({ kind: 'vague', about: { quote: v.doc ? v.quote : null, doc: v.doc, trade: v.options.find((o) => o.trade)?.trade ?? null },
      prompt_en: v.doc ? `Your profile says: ${quoted(v.quote)} ${v.ask}` : v.ask, options: dedupe(v.options.flatMap(opt)), multi: true });
  }
  // A TRADE WITH NO SERVICE (code, no judgement): too broad to match on, so its services are asked
  // covered only by an option he can tap as a KEY of that trade (12 Nov 2026, H05 held out: "Floor repairs" named flooring with no key,
  // and the flooring card was never drafted, so "Tiling maintenance" left a trade with no service he could confirm)
  const coveredByVague = new Set(vagueAsked.flatMap((v) => v.options.flatMap((o) => o.keys.map((k) => k.split('.')[0]))));
  // a trade whose only evidence is project captions or brands is asked as a "shown" card below, never as a trade card (H09, 12 Nov 2026)
  const shownOnly = (code: string) => r.evidence.filter((e) => e.trade === code || e.keys.some((k) => k.startsWith(code + '.'))).every((e) => e.basis === 'shown' || e.basis === 'brand');
  for (const t of askTrades) {
    const has = (k: string) => k.startsWith(t.code + '.');
    if ([...known].some(has) || shownItems.some((e) => e.keys.some(has)) || coveredByVague.has(t.code) || shownOnly(t.code)) continue;
    const def = tradeOf.get(t.code)!;
    if (!def.services.length) continue;
    qs.push({ kind: 'trade_services', about: { quote: t.quote, doc: t.doc, trade: t.code }, prompt_en: `You work in ${def.label}. Which of these do you do or supply?`,
      options: def.services.slice(0, LIMITS.options).map((s) => ({ key: s.key, label_en: s.label, own_words: false })), multi: true });
  }
  // THROUGH A PARTNER: one card per partner (or per trade when unnamed), his sentence quoted
  const byPartner = new Map<string, Claim[]>();
  for (const e of r.evidence) if (e.basis === 'partner') { const g = e.partner_name || e.trade || 'partner'; byPartner.set(g, [...(byPartner.get(g) ?? []), e]); }
  for (const es of byPartner.values()) {
    const options = dedupe(es.flatMap((e): QuestionOption[] => e.keys.length ? e.keys.filter((k) => !tick.some((x) => x.key === k)).map((k) => ({ key: k, label_en: labelOf.get(k) ?? e.words, own_words: false })) : [{ key: null, label_en: e.words, own_words: true }]));
    if (!options.length) continue;
    qs.push({ kind: 'partner', about: { quote: es[0].quote, doc: es[0].doc, trade: es[0].trade, words: es.map((e) => e.words), partner_name: es[0].partner_name },
      prompt_en: `Your profile says these are delivered ${quoted(es[0].quote)}. How do you deliver them?`, options, multi: true });
  }
  // SHOWN in project captions, or following from a brand: "do you take these as jobs on their own?", one card per trade
  // one card per trade, the trades with the most shown work first (report 3.1: a profile with no stated service is asked by trade); a
  // shown item no key covers asks its trade's services, so the card of a trade seen only in captions still has something to tap
  const byTrade = new Map<string, Claim[]>();
  for (const e of shownItems) { const g = e.keys.find((k) => !known.has(k))!.split('.')[0]; byTrade.set(g, [...(byTrade.get(g) ?? []), e]); }
  for (const e of r.evidence) if ((e.basis === 'shown' || e.basis === 'brand') && !e.keys.length && e.trade && tradeOf.has(e.trade) && shownOnly(e.trade)) byTrade.set(e.trade, [...(byTrade.get(e.trade) ?? []), e]);
  for (const [g, es] of [...byTrade].sort((a, b) => b[1].length - a[1].length)) {
    const keyed = es.flatMap((e) => e.keys.filter((k) => !known.has(k)).map((k) => ({ key: k, label_en: labelOf.get(k) ?? e.words, own_words: false })));
    const options = dedupe(keyed.length ? keyed : (tradeOf.get(g)?.services ?? []).filter((x) => !known.has(x.key)).map((x) => ({ key: x.key, label_en: x.label, own_words: false })));
    if (!options.length) continue;
    const brand = es.every((e) => e.basis === 'brand');
    const what = keyed.length ? listOf([...new Set(options.slice(0, 3).map((o) => o.label_en.toLowerCase()))]) : `${tradeOf.get(g)!.label.toLowerCase()} work`;
    qs.push({ kind: 'shown', about: { quote: es[0].quote, doc: es[0].doc, trade: g, words: es.map((e) => e.words) },
      prompt_en: brand ? `Your brand list shows ${what}. Do you supply these?` : `Your projects show ${what}. Do you take these as jobs on their own?`, options, multi: true });
  }
  // UMBRELLA: what a company like his commonly also does. Candidates in the design's order (3.2): his trades' own services he did not
  // evidence, the curated implications of what he did, the reading's also-ask; at most 12 chips on 2 open cards, the rest later.
  const asked = new Set([...known, ...shownItems.flatMap((e) => e.keys), ...vagueAsked.flatMap((v) => v.options.flatMap((o) => o.keys))]);
  // his MAIN trades only: those holding at least two of his listed services, at most three (measured 12 Nov 2026 on H01: every service of all
  // 13 trades he touched gave 7 umbrella cards, most of them work a decorator never named, such as road marking and car parks)
  const ownTrades = [...new Set(tick.map((x) => x.trade))].filter((t) => tick.filter((x) => x.trade === t).length >= 2)
    .sort((a, b) => tick.filter((x) => x.trade === b).length - tick.filter((x) => x.trade === a).length).slice(0, 3);
  const fromTrades = ownTrades.flatMap((c) => (tradeOf.get(c)?.services ?? []).map((s) => s.key));
  const fromImpl = implications.filter((i) => tick.some((x) => x.key === i.from || x.trade === i.from)).map((i) => i.to).filter((k) => labelOf.has(k));
  const fromAlso = r.also_ask.flatMap((a) => a.options.flatMap((o) => o.keys));
  const cand = [...new Set([...fromAlso, ...fromImpl, ...fromTrades])].filter((k) => !asked.has(k));
  const alsoLabels = r.also_ask.flatMap((a) => a.options.filter((o) => !o.keys.length).map((o) => o.label));
  const chips = cand.map((k) => ({ key: k, label_en: labelOf.get(k)!, own_words: false } as QuestionOption));
  for (let i = 0; i < chips.length; i += LIMITS.options) {
    const options = chips.slice(i, i + LIMITS.options);
    qs.push({ kind: 'umbrella', about: { quote: null, doc: null, trade: options[0].key!.split('.')[0], words: i ? undefined : alsoLabels.slice(0, 8) },
      prompt_en: 'Companies like yours often also do these. Tap any you do.', options, multi: true });
  }
  // THE LICENCE AND THE PROFILE DISAGREE
  const allTrades = [...trades, ...askTrades];
  if (r.licence.covers_profile === 'no' && (opts.licenceActivities ?? []).length && allTrades.length) {
    const acts = opts.licenceActivities!.slice(0, 3).join(', ');
    const about = listOf(allTrades.slice(0, 2).map((t) => tradeOf.get(t.code)!.label.toLowerCase()));
    qs.push({ kind: 'licence', about: { quote: r.licence.note || null, doc: null, trade: allTrades[0].code },
      prompt_en: `Your trade licence lists ${acts}. Your profile is about ${about}. Which is your business today?`,
      options: [{ key: null, label_en: 'What my profile says', own_words: true }, { key: null, label_en: 'Both', own_words: true }, { key: null, label_en: 'What my licence says', own_words: true }], multi: false });
  }
  // at most 5 cards in one sitting, most blocking first; at most 12 umbrella chips on 2 open cards
  const sorted = qs.map((q, i) => ({ q, i })).sort((a, b) => ORDER.indexOf(a.q.kind) - ORDER.indexOf(b.q.kind) || a.i - b.i).map((x) => x.q);
  let open = 0, umbOpen = 0, umbChips = 0;
  const questions = sorted.map((q) => {
    let ok = open < LIMITS.openCards;
    if (ok && q.kind === 'umbrella') { ok = umbOpen < LIMITS.umbrellaCards && umbChips + q.options.length <= LIMITS.umbrellaChips; if (ok) { umbOpen++; umbChips += q.options.length; } }
    if (ok) open++;
    // the hash is of FACTS (kind, trade, document, option keys; a vague card also its line as found in his text), never of the model's
    // wording: a re-read asks no answered question again
    const keys = q.kind === 'vague' || q.kind === 'nothing' || q.kind === 'licence' ? [] : q.options.map((o) => o.key ?? '').filter(Boolean).sort();
    return { ...q, about_hash: aboutHash(q.kind, { trade: q.about.trade, doc: q.about.doc, keys, ...(q.kind === 'vague' ? { line: quoteKey(q.about.quote ?? '') } : {}) }), status: (ok ? 'open' : 'later') as 'open' | 'later', source };
  });
  return { trades, tick, partner, own_words, shown, questions };
}

// ── THE TWO STEPS (the model call is injected: the edge function's gateway, or recorded answers in the offline test) ──────
export type Ask = (step: 'read' | 'map', system: string, text: string) => Promise<{ ok: true; content: string } | { ok: false; error: string }>;
export type TwoStepTimes = { read_ms: number; map_ms: number; read_calls: number; map_calls: number };

/** Step A over the documents in parts of READ_PART_CHARS (five at once; a part that timed out is read in halves, twice at most). Step B
 *  starts on each part's phrases as soon as that part is read: code maps the phrases that ARE a catalogue name or alias, the model the
 *  rest in calls of MAP_PHRASES, every call at once; a failed call is retried in halves, twice at most. A phrase that still could not be
 *  mapped is OWED: the reading is not proposed (unavailable, nothing guessed) and the re-read sweep reads it again; never silently left
 *  in his own words. `onRead`: called with the reading as soon as step A has landed, before the mapping ends (the tab shows it). */
export async function readInTwoSteps(docs: ReadDoc[], company: string | null, tax: Taxonomy, ask: Ask, opts: { onRead?: (r: ProfileReading) => Promise<void> } = {}): Promise<{ ok: true; reading: ProfileReading; times: TwoStepTimes } | { ok: false; error: string }> {
  const codes = new Set(tax.trades.map((t) => t.code));
  const own = docs.filter((d) => d.kind !== 'licence' && d.text.trim());
  if (!own.length) return { ok: false, error: 'no profile or catalogue text to read' };
  const licence = docs.filter((d) => d.kind === 'licence' && d.text.trim()).map((d) => `=== licence: ${d.name} ===\n${d.text}`).join('\n\n');
  const body = own.map((d) => `=== ${d.kind}: ${d.name} ===\n${d.text}`).join('\n\n');
  const parts = textChunks(body, READ_PART_CHARS);
  const head = parts.length > 1 ? parts[0].slice(0, 2000) : '';
  const sys = profileReadSystem(tax.trades);
  const who = company ? `The company registered as: ${company.slice(0, 160)}\n\n` : '';
  const t0 = Date.now(); let readCalls = 0, mapCalls = 0, summary = '';
  const readPart = async (p: string, i: number, depth = 0): Promise<{ ok: true; reading: ProfileReading } | { ok: false; error: string }> => {
    readCalls++;
    const text = `${who}The company's documents, each under its own header:\n\n${i && head ? `[The documents open with this, for context only - do not quote it:]\n${head}\n[The part to read and quote from:]\n` : ''}${p}${licence ? `\n\n${licence}` : ''}`;
    const a = await ask('read', sys, text);
    const r = a.ok ? checkReading(a.content, own, codes) : a;
    if (r.ok || depth >= 2 || p.length < 1500 || !/gateway_deadline|546|cut off|timed? ?out|50[24]/i.test(r.error)) return r;
    const halves = await Promise.all(textChunks(p, Math.ceil(p.length / 2) + 200).map((h) => readPart(h, i || 1, depth + 1)));
    const bad = halves.find((x) => !x.ok); if (bad) return bad;
    return { ok: true, reading: mergeReadings(halves.map((x) => (x as { reading: ProfileReading }).reading)) };
  };
  const owed: Phrase[] = [], refused: { what: string; why: string }[] = [];
  const mapCall = async (ch: Phrase[], depth = 0): Promise<void> => {
    mapCalls++;
    const shown = sliceTrades([...new Set(ch.map((x) => x.trade))], tax);
    const a = await ask('map', profileMapSystem(sliceText(shown, tax)), `Company: ${company ?? ''}. ${summary}\n\nPhrases:\n${ch.map((x) => `${x.n}. ${x.text}`).join('\n')}`);
    if (a.ok && applyMapping(a.content, ch, new Set(shown), tax, refused)) return;
    if (ch.length > 1 && depth < 2) { const h = Math.ceil(ch.length / 2); await Promise.all([mapCall(ch.slice(0, h), depth + 1), mapCall(ch.slice(h), depth + 1)]); return; }
    owed.push(...ch);
  };
  const mapPart = async (r: ProfileReading) => {
    const model: Phrase[] = [];
    for (const ph of phrasesOf(r)) {
      const k = codeKeysOf(ph, tax);
      if (k.length) { ph.ref.keys = [...new Set([...ph.ref.keys, ...k])]; ph.ref.code_keys = k; } else model.push(ph);
    }
    const calls: Phrase[][] = []; for (let i = 0; i < model.length; i += MAP_PHRASES) calls.push(model.slice(i, i + MAP_PHRASES));
    await Promise.all(calls.map((ch) => mapCall(ch)));
  };
  const mapping: Promise<void>[] = [];
  const each = await inPool(parts, PARALLEL, async (p, i) => {
    const r = await readPart(p, i);
    if (r.ok) { if (i === 0) summary = r.reading.summary; mapping.push(mapPart(r.reading)); }
    return r;
  });
  const bad = each.find((x) => !x.ok);
  if (bad) { await Promise.allSettled(mapping); return bad as { ok: false; error: string }; }
  const reading = mergeReadings(each.map((x) => (x as { reading: ProfileReading }).reading));
  const read_ms = Date.now() - t0;
  const told = opts.onRead ? opts.onRead(reading).catch(() => {}) : Promise.resolve();
  await Promise.all(mapping); await told;
  reading.rejected.push(...refused);
  if (owed.length) return { ok: false, error: `the mapping is owed for ${owed.length} phrase(s) (${owed.slice(0, 4).map((x) => x.words).join('; ')}): read again by the sweep` };
  return { ok: true, reading, times: { read_ms, map_ms: Date.now() - t0 - read_ms, read_calls: readCalls, map_calls: mapCalls } };
}

// ── THE LIVE READER (an edge function's) ─────────────────────────────────────────────────────────────────────────────
// EFFORT, BY THE ESTATE'S RULE (rulings 1630 and 1642; report 3.12). Both steps run on the class supplier_trade_choice (HIGH: it reads
// documents and decides). It is background work behind the upload, so it stays high with a limit that fits: smaller parts, calls in
// parallel. Measured on the hard-profile set at high (12 Nov 2026, effort_policy.SURFACES 'supplier_doc_trades.profile_reading'):
// the MAPPING fits its call's clock at high and stays at the class's effort; the READING did not (one call 113 s on a 1,900-character
// profile, another past the gateway's wall and read in halves for 197 s), so step A asks the effort its clock measured, recorded
// there as the clock's effort, never as "proven medium".
export type ProfileReadResult = { ok: true; reading: ProfileReading; taxonomy: Taxonomy; implications: Implication[]; times: TwoStepTimes } | { ok: false; error: string };
/** `opts.onRead`: called as soon as step A has landed, with the reading before its keys (the tab shows the summary and his claims while
 *  the mapping runs: the founder's "not laggy", review of branch 2). */
export type ProfileReader = (docs: ReadDoc[], company: string | null, opts?: { onRead?: (r: ProfileReading) => Promise<void> }) => Promise<ProfileReadResult>;
/** The whole catalogue (every active service, paged), the umbrella parents, the curated adjacent pairs and implications. */
// deno-lint-ignore no-explicit-any
export async function readTaxonomy(admin: any): Promise<{ taxonomy: Taxonomy; implications: Implication[] } | null> {
  const [t, s, a, i] = await Promise.all([
    admin.from('taxonomy_trade').select('code,label,umbrella_code').eq('active', true).order('code'),
    activeServiceRows<{ trade_code: string; code: string; label_en: string; aliases: string[] | null }>(admin, 'trade_code,code,label_en,aliases'),
    admin.from('taxonomy_trade_adjacent').select('a_code,b_code').eq('active', true),
    admin.from('service_implication').select('from_code,implies_trade,implies_code').eq('active', true),
  ]);
  if (t.error || s.error || !t.data?.length) return null;
  const by = new Map<string, { key: string; label: string; aliases?: string[] }[]>();
  for (const r of s.data) (by.get(r.trade_code) ?? by.set(r.trade_code, []).get(r.trade_code)!).push({ key: `${r.trade_code}.${r.code}`, label: r.label_en, aliases: (r.aliases ?? []).filter((a) => typeof a === 'string') });
  return {
    taxonomy: { trades: (t.data as { code: string; label: string; umbrella_code: string | null }[]).map((x) => ({ ...x, services: by.get(x.code) ?? [] })),
      adjacent: ((a.data ?? []) as { a_code: string; b_code: string }[]).map((x) => [x.a_code, x.b_code] as [string, string]) },
    implications: ((i.data ?? []) as { from_code: string; implies_trade: string; implies_code: string }[]).map((x) => ({ from: x.from_code, to: `${x.implies_trade}.${x.implies_code}` })),
  };
}
/** `onAnswer`: the hard-profile runner records every answer here, so the offline test replays them at USD 0 (never set in production). */
// deno-lint-ignore no-explicit-any
export function liveProfileReader(admin: any, opts: { subject?: unknown; headers?: Record<string, string>; onAnswer?: (step: 'read' | 'map', text: string, content: string | null, ms: number, error?: string) => void } = {}): ProfileReader {
  let tax: { taxonomy: Taxonomy; implications: Implication[] } | null = null, cred: string | null = null;
  return async (docs, company, ro = {}) => {
    try {
      tax ??= await readTaxonomy(admin);
      if (!tax) return { ok: false, error: 'the catalogue could not be read' };
      if (!cred) { const { data } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_ai').maybeSingle(); cred = data?.value ?? null; }
      if (!cred) return { ok: false, error: 'no model credential' };
      const c = cred;
      // one retry of a call whose answer was not JSON (measured on the 29 real files: 1 of 28 answers came back as prose)
      const ask: Ask = async (_step, system, text) => {
        const req = { fn: 'supplier_doc_trades', task_class: choiceTaskClass(), subject: opts.subject ?? null, temperature: 0, sys_stable: system, sys: '',
          ...(_step === 'read' ? { effort: surfaceEffort(READ_SURFACE) } : {}),
          input: [{ role: 'user', content: [{ type: 'text', text }] }] };
        const t = Date.now();
        let a = await gatewayCall(c, req, opts.headers);
        if (a.ok && !answerJson(a.content, _step === 'read' ? 'evidence' : 'map')) a = await gatewayCall(c, req, opts.headers);
        // every answer, a failure too: the offline replay must take the path the live reading took (a part read in halves)
        opts.onAnswer?.(_step, text, a.ok ? a.content : null, Date.now() - t, a.ok ? undefined : a.error);
        return a;
      };
      const r = await readInTwoSteps(docs, company, tax.taxonomy, ask, { onRead: ro.onRead });
      return r.ok ? { ...r, taxonomy: tax.taxonomy, implications: tax.implications } : r;
    } catch (e) { return { ok: false, error: String((e as Error)?.message || e).slice(0, 200) }; }
  };
}
