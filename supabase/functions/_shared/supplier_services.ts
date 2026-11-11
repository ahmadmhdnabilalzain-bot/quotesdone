// WHAT A SUPPLIER SAYS IT DOES, as server actions (15 Sep 2026, sales_engineer; rewritten 18 Sep).
//
// Founder, 15 Sep 2026: the Services tab "will be our cross matching main source"; and "later this
// will be a mobile app as well. the structure need to be built in already." So every step is a
// supplier_api action with a typed request and response (docs/api/supplier_portal_services.md) and
// the React tab is one client:
//
//   services_state          -> the prepared checklist, the vocabulary, what is saved, the voice switch
//   services_resolve        -> what one phrase means as a TRADE: listed codes, or a new proposal
//   services_rewrite        -> the supplier's own words -> standard services + what they imply (preview)
//   services_save_rewrite   -> the confirmed preview, through capabilityConfirm (the ledger)
//   transcribe_service_note -> a recorded note to text, behind decision_policy supplier_voice_input_enabled
//
// ADDING IS TYPING OR SPEAKING, NOT PICKING (instruction 438, 15 Sep 2026: "for adding services its
// not a checkbox or drop down menu. i told you its a voice to text or text box. once filled the sales
// engineer will rewrite that professionally since he will cross match based on that."). The prepared
// checklist above is the sales engineer's own proposal and stays a checklist; there is ONE save, and
// it is the confirmed rewrite. services_save and its extras list were deleted with the widgets they
// served — two writers of supplier_capabilities.services is how two screens start disagreeing.
//
// WHERE IT LANDS FOR MATCHING. fn_match_capability gates on supplier_capabilities.trades +
// confirmed_at, and — when the inquiry names services — on fn_services_effective(services, trades,
// services_removed): what the supplier STATED, plus ONE level of the curated service_implication map,
// minus what it removed. A stated service is stored as '<trade>.<code>' and its trade joins trades,
// so the trade gate is fed either way. Which trade a phrase names is READ BY REASONING over the live taxonomy
// (23 Sep 2026, decision point 23; resolveText below). Words no trade is found for, or that could not be read
// under the model hold, are kept EXACTLY as the supplier wrote them and become a taxonomy_trade_proposal for
// the sales engineer — never dropped, never guessed.

import { capabilityConfirm, capabilityState, capabilityVocabulary, tradeCode } from './supplier_capability.ts';
import { finishRewrite, impliedServices, ownWordsOf, rewriteServices, splitPhrases, tidy, withExactTrades, type Implication, type ServiceTerm } from './service_rewrite.ts';
import { activeServiceRows, serviceVocab } from './service_vocabulary.ts';
import { readCatalogue, supplyOnlyOf } from './catalogue_read.ts';
import { meaningCandidates, meaningClauses, proposeByMeaning, type MeaningProposal, type MeaningService } from './service_meaning.ts';
import { embedLines, remoteEmbedder } from './meaning_embed.ts';
import { readWithModel } from './catalogue_model.ts';
import { allText, type DocEvidence } from './supplier_doc_trades.ts';
import { readDocument } from './doc_read/index.ts';
import { tradeOfWords } from './reasoned_matching.ts';
import { defaultDeps } from './think.ts';
import { runtimeWaitUntil } from './async_webhook.ts';
import { aliasPairsOf, type AliasPair, type LicenceCheck, type ProposedService } from './profile_services.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;

export type ServiceRow = { trade_code: string; code: string; label_en: string; label_ar: string; sort?: number };
export type ChecklistService = { key: string; label_en: string; label_ar: string };
export type ChecklistTrade = {
  code: string; label_en: string; label_ar: string | null;
  source: 'confirmed' | 'on_file' | 'signup' | 'documents' | 'refine';
  services: ChecklistService[];
};
export type VoiceConfig = { enabled: boolean; max_seconds: number; max_bytes: number; mime: readonly string[] };

export const MAX_EXTRAS = 25;
export const EXTRA_LEN = 120;
// Voice limits. A 16 kHz mono 16-bit WAV is 32 KB a second, so 60 s is about 1.9 MB.
export const VOICE: Omit<VoiceConfig, 'enabled'> = { max_seconds: 60, max_bytes: 2_500_000, mime: ['audio/wav', 'audio/mpeg'] };
export const VOICE_PER_HOUR = 20;
export const VOICE_FLAG = 'supplier_voice_input_enabled';

export const serviceKey = (trade: string, code: string) => `${trade}.${code}`;

/** A stored services array split into checklist keys we know and the supplier's own words. */
export function splitServices(stored: unknown, known: Set<string>): { selected: string[]; extras: string[] } {
  const selected: string[] = []; const extras: string[] = [];
  for (const raw of Array.isArray(stored) ? stored : []) {
    const s = String(raw ?? '').trim();
    if (!s) continue;
    // A key-shaped string we do not list (a retired service, or words the supplier typed that look like
    // 'a.b') is kept as the supplier's own words rather than dropped on the next load.
    if (known.has(s)) selected.push(s); else extras.push(s);
  }
  return { selected: [...new Set(selected)], extras: [...new Set(extras)] };
}

/** Trimmed, de-duplicated (case-insensitive), clipped free-text services. */
export function cleanExtras(v: unknown): string[] {
  const out: string[] = []; const seen = new Set<string>();
  for (const raw of Array.isArray(v) ? v : []) {
    const s = String(raw ?? '').replace(/\s+/g, ' ').trim().slice(0, EXTRA_LEN);
    const k = s.toLowerCase();
    if (s.length < 2 || seen.has(k)) continue;
    seen.add(k); out.push(s);
    if (out.length >= MAX_EXTRAS) break;
  }
  return out;
}

/** 'ar' when the text carries Arabic letters, 'en' when it carries anything else, '' when empty. */
export const langOf = (text: string): '' | 'ar' | 'en' => !text.trim() ? '' : /[؀-ۿ]/.test(text) ? 'ar' : 'en';

/** Which trades the checklist opens with, and why. Confirmed wins; before a confirm it is what we
 *  hold on file, the trade the supplier chose at sign-up, and what his own documents name (supplier_doc_trades.ts).
 *
 *  THE TRADE HE CHOSE AT SIGN-UP IS ALWAYS ON THE LIST BEFORE HE CONFIRMS (11 Nov 2026, customer_support, registration
 *  certification finding 4). create_company writes the trade picked in "Register your company" to leads.sector, and the list
 *  read only supplier_capabilities.trades and the documents' proposal. With the reader out (a model outage, or the free round
 *  of the certification) nothing was proposed, so the list was empty, "Confirm my services" stayed disabled, and J1, J4 and J5
 *  stayed "Pending, services unconfirmed" with no way forward. `chosen` is that trade, already checked to be a live code by
 *  the caller (signupTradeOf). After a confirm the list is what he confirmed, so a trade he removed does not come back.
 *  Prevented by: _shared/the_trade_chosen_at_signup_is_always_on_the_checklist.test.ts. */
export function preparedTrades(cap: Record<string, unknown> | null, confirmed: boolean,
  umbrellaOf: Record<string, string | null | undefined> = {}, chosen: string | null = null): { code: string; source: ChecklistTrade['source'] }[] {
  const held = Array.isArray(cap?.trades) ? (cap!.trades as string[]) : [];
  const out: { code: string; source: ChecklistTrade['source'] }[] = confirmed
    ? held.map((code) => ({ code, source: 'confirmed' as const }))
    : held.map((code) => ({ code, source: 'on_file' as const }));
  if (!confirmed) {
    // His documents are the stronger evidence: a trade they name is shown "From your documents" even when he also chose it at
    // sign-up (11 Nov 2026, paid certification run 2, J4: hvac read off his profile was labelled only "Chosen at sign-up").
    const docs = Array.isArray(cap?.proposed_trades) ? (cap!.proposed_trades as string[]) : [];
    for (const code of docs) if (!out.some((t) => t.code === code)) out.push({ code, source: 'documents' });
    if (chosen && !out.some((t) => t.code === chosen)) out.push({ code: chosen, source: 'signup' });
  }
  // SPLITS ARE OFFERED, NEVER APPLIED (founder instructions 895/899/900, 23 Sep 2026). A trade split out of
  // one the checklist already shows (taxonomy_trade.umbrella_code: corrugated_packaging out of packaging)
  // is listed after it, unticked, as 'refine'. The umbrella stays his and keeps every inquiry naming it;
  // the specific trade becomes his only through a service he ticks in it (ServicesTab sends a 'refine'
  // trade only when one of its services is ticked, and the server keeps it only then: keepTickedRefine).
  // Only under a trade he holds (not one his documents merely suggest), and one level only.
  const shown = new Set(out.map((t) => t.code));
  for (const [child, parent] of Object.entries(umbrellaOf)) {
    if (parent && held.includes(parent) && !shown.has(child)) { out.push({ code: child, source: 'refine' }); shown.add(child); }
  }
  return out;
}

/** The trade the supplier picked at sign-up (leads.sector, written by create_company), when it is a live code of the
 *  vocabulary. "My trade isn't listed" stores the typed words in the same column; those are not a code and are read by a
 *  person (Onboarding.tsx), so they are not offered as a checklist trade. */
export function signupTradeOf(sector: unknown, vocab: readonly { code: string }[]): string | null {
  const s = String(sector ?? '').trim();
  return s && vocab.some((t) => t.code === s) ? s : null;
}

async function serviceRows(admin: Admin): Promise<ServiceRow[]> {
  const { data, error } = await activeServiceRows<ServiceRow>(admin, 'trade_code,code,label_en,label_ar,sort');
  return error ? [] : data;
}

export async function voiceEnabled(admin: Admin): Promise<boolean> {
  const { data } = await admin.from('decision_policy').select('value').eq('key', VOICE_FLAG).maybeSingle();
  const v = data?.value;
  return v === true || (!!v && typeof v === 'object' && (v as { enabled?: unknown }).enabled === true);
}

/** A split trade (it names an umbrella) that the supplier does not already hold is kept only when he ticked
 *  a service in it. Offered is not confirmed (founder instructions 857, 895/899/900): whatever a client sends,
 *  the server is where this holds. */
export function keepTickedRefine(sent: string[], held: string[], umbrellaOf: Record<string, string | null | undefined>, stated: string[]): string[] {
  // Exactly the trades preparedTrades offered as refine: split from a trade he holds, not held themselves.
  return sent.filter((t) => held.includes(t) || !umbrellaOf[t] || !held.includes(umbrellaOf[t]!) || stated.some((k) => k.startsWith(t + '.')));
}

export async function servicesState(admin: Admin, supplierId: number) {
  // Independent reads, started together.
  const [base, rows, lead] = await Promise.all([
    capabilityState(admin, supplierId),
    serviceRows(admin),
    admin.from('leads').select('sector').eq('id', supplierId).maybeSingle().then((r: { data: { sector?: unknown } | null }) => r.data, () => null),
  ]);
  const byTrade: Record<string, ChecklistService[]> = {};
  for (const r of rows) (byTrade[r.trade_code] ||= []).push({ key: serviceKey(r.trade_code, r.code), label_en: r.label_en, label_ar: r.label_ar });
  const known = new Set(rows.map((r) => serviceKey(r.trade_code, r.code)));
  const cap = base.capability as Record<string, unknown> | null;
  const { selected, extras } = splitServices(cap?.services, known);
  const vocab = base.vocabulary.trades as { code: string; label: string; label_ar?: string | null; umbrella_code?: string | null }[];
  const labelOf = (code: string) => vocab.find((t) => t.code === code);
  const prepared = preparedTrades(cap, base.confirmed, Object.fromEntries(vocab.map((t) => [t.code, t.umbrella_code])), signupTradeOf(lead?.sector, vocab));
  // FIRST RUN STARTS UNTICKED (founder_instruction 862, 23 Sep 2026: "for suppliers it's as I told you
  // it start unticked"). It used to tick every service of every prepared trade — including trades the
  // sales engineer only INFERRED ('on_file', 'documents') — and one press of Confirm saved all of it as
  // the supplier's stated services. Under founder_instruction 857 a stated service is one the supplier
  // confirmed he does, so a tick the system placed would have counted as his. The prepared trades are
  // still offered, with their services listed; the supplier ticks what he does. Every client reads this
  // (the portal's ServicesTab and any mobile client of services_state), so it is decided here, once.
  const firstRun = !base.confirmed && selected.length === 0;
  const checklist: ChecklistTrade[] = prepared.map(({ code, source }) => {
    const t = labelOf(code);
    return { code, source, label_en: t?.label || code.replace(/_/g, ' '), label_ar: t?.label_ar ?? null, services: byTrade[code] || [] };
  });
  // NOTHING ON AN UNCONFIRMED ROW IS HIS (10 Nov 2026, customer_support, supplier-journey audit). capabilityConfirm is
  // the only writer of `services` in this codebase and it always confirms, so an unconfirmed row's services came from
  // the directory import (review_status 'derived': 14,733 rows on 10 Nov, free text such as 'supply', 'installation' or
  // the company's own name). Returned as extra_services they were shown as "Kept in your own words" and re-sent as
  // own_words on Confirm, which confirmed a supplier who ticked nothing (862). The ticks and the words obey one rule.
  // Prevented by: _shared/supplier_services_save.test.ts ("a derived row's words are not offered as his own").
  const ticked = firstRun || !base.confirmed ? [] : selected;
  const ownWords = base.confirmed ? extras : [];
  // WHAT THE SUPPLIER'S OWN DOCUMENTS SAY HE DOES, AS SERVICES (10 Nov 2026, ledger 1573): read at upload by
  // supplier_doc_trades (profile_services.servicesOfText), each with his own words and whether his licence covers it.
  // OFFERED, NOT TICKED: founder 862 ("it start unticked") and 857 (a service is his only when he ticks it) stand; the tab
  // shows them first, marked as proposed, with one button that ticks them all for him to review.
  const src = (cap?.source_docs && typeof cap.source_docs === 'object') ? cap.source_docs as Record<string, unknown> : {};
  const labelByKey = new Map(rows.map((r) => [serviceKey(r.trade_code, r.code), r]));
  const proposedServices = (Array.isArray(src.proposed_services) ? src.proposed_services as ProposedService[] : [])
    .filter((p) => p && known.has(p.key))
    .map((p) => ({ key: p.key, trade: p.trade, label_en: labelByKey.get(p.key)?.label_en ?? p.label_en, label_ar: labelByKey.get(p.key)?.label_ar ?? '',
                   phrase: p.phrase, snippet: p.snippet, via: p.via, licence: p.licence, doc: p.doc, stated: ticked.includes(p.key) }));
  const licenceCheck = (src.licence_check && typeof src.licence_check === 'object') ? src.licence_check as LicenceCheck : null;
  return {
    proposed_services: proposedServices, licence_check: licenceCheck,
    ok: true, confirmed: base.confirmed, first_run: firstRun,
    capability: cap, history: base.history, vocabulary: base.vocabulary, trade_proposals: base.trade_proposals,
    services_by_trade: byTrade, checklist,
    selected_services: ticked, extra_services: ownWords,
    // THE FREE-TEXT HALF (instruction 438). The checklist above is the sales engineer's PREPARED
    // proposal and stays a checklist; ADDING a service is the text box, and this is its state.
    raw_text: (cap?.services_raw_text as string | null) ?? '',
    implied_services: Array.isArray(cap?.services_implied) ? cap!.services_implied as string[] : [],
    removed_services: Array.isArray(cap?.services_removed) ? cap!.services_removed as string[] : [],
    rewritten_at: (cap?.services_rewritten_at as string | null) ?? null,
    voice: { enabled: await voiceEnabled(admin), ...VOICE } as VoiceConfig,
  };
}

const liveTaxonomy = async (admin: Admin): Promise<{ code: string; label: string }[]> =>
  ((await admin.from('taxonomy_trade').select('code,label').eq('active', true)).data || []) as { code: string; label: string }[];

/**
 * The trade codes a supplier's own words name. A slug or code resolves exactly (fn_norm_trades); any other words
 * are READ BY REASONING over the live taxonomy (reasoned_matching.ts tradeOfWords, decision point 23 — never an
 * alias match). Held: `held` is true and no code is claimed; the words go to the sales engineer as a proposal.
 */
export async function resolveText(admin: Admin, text: string, taxonomy?: { code: string; label: string }[]): Promise<{ codes: string[]; held: boolean }> {
  const exact = await exactTradesOfText(admin, text);
  if (exact.length) return { codes: exact, held: false };
  return reasonTradesOf(admin, text, taxonomy);
}
/** The exact half of resolveText: a slug or code (fn_norm_trades). No model; [] when nothing matches exactly. */
export async function exactTradesOfText(admin: Admin, text: string): Promise<string[]> {
  const { data, error } = await admin.rpc('fn_norm_trades', { p_text: text });
  return !error && Array.isArray(data) && data.length ? data.map(String) : [];
}
/** The reasoning half of resolveText (tradeOfWords over the live taxonomy): one plan call and one answer call. */
export async function reasonTradesOf(admin: Admin, text: string, taxonomy?: { code: string; label: string }[]): Promise<{ codes: string[]; held: boolean }> {
  const r = await tradeOfWords(defaultDeps(admin, 'supplier_api'), { text, trades: taxonomy ?? await liveTaxonomy(admin) });
  return { codes: r.value ?? [], held: r.value == null };
}

export async function servicesResolve(admin: Admin, body: Record<string, unknown>): Promise<[number, Record<string, unknown>]> {
  const text = cleanExtras([body.text])[0];
  if (!text) return [400, { error: 'empty_text', code: 'services_empty_text' }];
  const { codes: trades, held } = await resolveText(admin, text);
  // Held: nothing is claimed either way — neither a trade nor a new-trade code is invented from the words.
  return [200, { ok: true, text, trades, held, new_trade: trades.length || held ? null : tradeCode(text) }];
}

// ── VOICE ─────────────────────────────────────────────────────────────────────────────────────────
// THE LIMIT RESERVES BEFORE IT COUNTS (database review, 15 Sep 2026). Count-then-insert let parallel
// requests all read 19 and all pass; each request now writes its 'pending' audit row first and then
// counts the hour INCLUDING itself, so concurrent requests see one another and the cap cannot be
// overshot (at worst a burst admits fewer than 20).
export type VoiceDeps = {
  enabled: () => Promise<boolean>;
  recentCount: (supplierId: number) => Promise<number>;          // admitted-or-pending requests in the last hour, own row included
  audit: (row: Record<string, unknown>) => Promise<void>;        // a finished row (flag_off)
  start: (row: Record<string, unknown>) => Promise<(patch: Record<string, unknown>) => Promise<void>>;  // pending row -> finisher
  transcribe: (b64: string, mime: string) => Promise<{ ok: true; text: string } | { ok: false; error: string }>;
};

/** Decoded size of a base64 string, without decoding it. */
export const b64Bytes = (b64: string) => Math.floor(b64.length * 3 / 4) - (b64.endsWith('==') ? 2 : b64.endsWith('=') ? 1 : 0);

export function checkVoice(body: Record<string, unknown>): { ok: true; b64: string; mime: string; bytes: number; duration: number | null } | { ok: false; code: string; status: number } {
  const b64 = String(body.audio_b64 || '').replace(/^data:[^,]*,/, '');
  const mime = String(body.mime || '').toLowerCase().split(';')[0].trim();
  const d = Number(body.duration_ms);
  const duration = Number.isFinite(d) && d >= 0 ? Math.round(d) : null;
  if (!VOICE.mime.includes(mime)) return { ok: false, code: 'voice_bad_type', status: 415 };
  if (b64.length < 100 || !/^[A-Za-z0-9+/=\s]+$/.test(b64.slice(0, 4096))) return { ok: false, code: 'voice_empty', status: 400 };
  const bytes = b64Bytes(b64.replace(/\s+/g, ''));
  if (bytes > VOICE.max_bytes) return { ok: false, code: 'voice_too_large', status: 413 };
  if (duration !== null && duration > VOICE.max_seconds * 1000 + 1500) return { ok: false, code: 'voice_too_long', status: 413 };
  return { ok: true, b64, mime, bytes, duration };
}

/** One voice note to text. Every call leaves exactly one audit row; none holds audio or text. */
export async function transcribeServiceNote(supplierId: number, body: Record<string, unknown>, deps: VoiceDeps): Promise<[number, Record<string, unknown>]> {
  const base = { supplier_id: supplierId, bytes: 0, duration_ms: null as number | null, mime: null as string | null };
  if (!(await deps.enabled())) {
    await deps.audit({ ...base, outcome: 'flag_off' });
    return [503, { ok: false, code: 'voice_input_off', error: 'voice_input_off' }];
  }
  const v = checkVoice(body);
  const finish = await deps.start(v.ok ? { ...base, bytes: v.bytes, duration_ms: v.duration, mime: v.mime, outcome: 'pending' } : { ...base, outcome: 'pending' });
  if ((await deps.recentCount(supplierId)) > VOICE_PER_HOUR) {
    await finish({ outcome: 'rate_limited' });
    return [429, { ok: false, code: 'voice_rate_limited', error: 'voice_rate_limited', per_hour: VOICE_PER_HOUR }];
  }
  if (!v.ok) {
    await finish({ outcome: 'refused' });
    return [v.status, { ok: false, code: v.code, error: v.code }];
  }
  const r = await deps.transcribe(v.b64, v.mime);
  if (!r.ok) {
    await finish({ outcome: 'failed' });
    return [502, { ok: false, code: 'voice_failed', error: 'voice_failed' }];
  }
  const text = r.text.trim();
  const lang = langOf(text);
  await finish({ outcome: text ? 'transcribed' : 'empty', lang: lang || null, chars: text.length });
  return [200, { ok: true, text, lang }];
}

// ── THE SALES ENGINEER'S REWRITE ──────────────────────────────────────────────────────────────────
// Founder, instruction 438 (15 Sep 2026): "for adding services its not a checkbox or drop down menu.
// i told you its a voice to text or text box. once filled the sales engineer will rewrite that
// professionally since he will cross match based on that."
//
// So ADDING a service is ONE free text box (plus the mic, behind the same flag as before). The
// rewrite needs no model: a part that IS a service is that service (_shared/service_rewrite.ts), and what the
// rest MEANS is read over the stored service vectors (service_meaning.ts) and offered, off until he adds it —
// no alias word decides anything since 29 Sep 2026 (ruling 890, decision point 93). The supplier is shown
// the rewrite, removes what is wrong, and confirms; only then is anything saved.
//
//   services_rewrite      -> preview: the supplier's words -> standard services + what they imply
//   services_save_rewrite -> the confirmed preview, into supplier_capabilities (+ the ledger)
//
// WHAT MATCHING READS is fn_services_effective(services, trades, services_removed): what the supplier
// STATED, plus one level of the curated service_implication map, minus what it removed. Instruction
// 439: "make sure the sales engineer is smart in cross matching. for example someone who does
// decoration is definitely able to do flooring even through words cross matching is not there."

export const RAW_TEXT_MAX = 2000;

/** The service vocabulary (names and stored vectors) the rewrite and meaning read.
 *  ONE OWNER (22 Sep 2026): _shared/service_vocabulary.ts, so the inquiry side of matching and this
 *  supplier side read the same rows. Re-exported here because this module's callers already ask it
 *  for the tab's vocabulary. */
export { serviceVocab };

/** The own-words phrases that ARE a trade code or intake slug, resolved by public.fn_norm_trades itself
 *  (fn_norm_trades_many, one call). A phrase's words never name a trade (ruling 890; the trade-alias vocabulary
 *  this replaced, tradeVocab, fed trade_words.ts). Null when the database could not be asked: then no own-words
 *  item becomes a trade, and the save still resolves each word exactly or by reasoning (resolveText). */
export async function exactTradesOf(admin: Admin, phrases: string[]): Promise<Record<string, string[]> | null> {
  if (!phrases.length) return {};
  const { data, error } = await admin.rpc('fn_norm_trades_many', { p_texts: phrases.slice(0, 400) });
  return error || !data || typeof data !== 'object' ? null : data as Record<string, string[]>;
}

/** public.service_implication, the curated map. THE TABLE IS THE SOURCE, not the JSON seed beside it:
 *  a row the sales engineer retires stops implying immediately, without a deploy. */
export async function implicationMap(admin: Admin): Promise<Implication[]> {
  const { data, error } = await admin.from('service_implication')
    .select('from_code,implies_trade,implies_code,reason_en,reason_ar').eq('active', true);
  if (error || !Array.isArray(data)) return [];
  // Every column is NOT NULL in the table; the guard is here because a null would concatenate into
  // the string "null.tiling" and silently name a service that does not exist, rather than throwing.
  return (data as Record<string, string | null>[])
    .filter((r) => r.from_code && r.implies_trade && r.implies_code)
    .map((r) => ({
      from: String(r.from_code), to: `${r.implies_trade}.${r.implies_code}`,
      en: String(r.reason_en ?? ''), ar: String(r.reason_ar ?? ''),
    }));
}

export type ImpliedOut = {
  key: string; label_en: string; label_ar: string; trade: string; removed: boolean;
  because: { from: string; from_label_en: string; from_label_ar: string; en: string; ar: string }[];
};

/** The preview. `text` is the supplier's own words; `removed` the implied keys it has already
 *  unticked in this session, so a re-run does not silently put them back. Nothing is saved here. */
/** The supplier's most recent readable catalogue: its text layer, or the text its browser read from the
 *  photo / scan (stored beside it as <path>.ocr.txt by supplier_catalog_ingest). */
async function latestCatalogueText(admin: Admin, supplierId: number): Promise<{ name: string; text: string; source: 'document_text' | 'photo_text' } | null> {
  const { data } = await admin.from('supplier_capabilities').select('source_docs').eq('supplier_id', supplierId).maybeSingle();
  const docs = Array.isArray(data?.source_docs?.docs) ? data!.source_docs.docs as DocEvidence[] : [];
  const doc = docs.filter((d) => d.kind === 'catalogue' && d.status === 'read').sort((a, b) => String(b.read_at).localeCompare(String(a.read_at)))[0];
  if (!doc) return null;
  const want = doc.source === 'photo_text' ? `${doc.path}.ocr.txt` : doc.path;
  const { data: blob } = await admin.storage.from('supplier-docs').download(want);
  if (!blob) return null;
  const bytes = new Uint8Array(await blob.arrayBuffer());
  if (doc.source === 'photo_text') return { name: doc.name, text: new TextDecoder().decode(bytes), source: 'photo_text' };
  const r = await readDocument(bytes, doc.name, '', 0, { textOnly: true });
  return r.ok ? { name: doc.name, text: allText(r), source: 'document_text' } : null;
}

/** The meaning layer over the lines no service was found exactly for (service_meaning.ts). Never throws;
 *  says which state it is in, so the supplier and the sales engineer can tell "understood nothing"
 *  from "could not run". */
// Since 29 Sep 2026 (decision point 93) this is the ONLY way a supplier's words name a service that is not
// written exactly: the alias rules are gone. `lines` says how many candidate lines there were and how many were
// read (MEANING_MAX_LINES per request, the edge CPU cap); a line not read stays the supplier's own words.
// Each line is read CLAUSE BY CLAUSE (meaningClauses: "supply and install ducting for the new majlis" is read as
// "install ducting" and "the new majlis"), each clause in its own space (English gte-small, Arabic e5), embedded by
// embed_ml (meaning_embed.ts), at most MEANING_MAX_LINES clauses. A proposal carries the supplier's whole LINE as
// its evidence, and a line any clause of which was understood leaves his own words.
async function meaningFor(admin: Admin, services: MeaningService[], lines: string[], stated: string[], supplyOnly: boolean) {
  const origin = new Map<string, string>();
  for (const l of [...new Set(lines.map((x) => x.trim()).filter((x) => x.length >= 3))]) {
    for (const c of meaningClauses(l)) if (!origin.has(c)) origin.set(c, l);
  }
  const cand = [...origin.keys()];
  const out = (state: string, proposals: MeaningProposal[] = [], read = 0) => ({ state, proposals, lines: { candidates: cand.length, read } });
  if (!cand.length) return out('nothing_to_read');
  if (!services.some((s) => s.vec || s.vec_ml)) return out('service_vectors_missing');
  const todo = meaningCandidates(cand, services);
  const read = await embedLines(todo, remoteEmbedder(admin, 'supplier_services'));
  if (!read.some((l) => l.vec)) return out('embedding_unavailable');
  const proposals = proposeByMeaning(read, services, { stated, supplyOnly })
    .map((p) => ({ ...p, lines: [...new Set(p.lines.map((c) => origin.get(c) ?? c))] }));
  return out('on', proposals, todo.length);
}

export async function servicesRewrite(admin: Admin, supplierId: number, body: Record<string, unknown>): Promise<[number, Record<string, unknown>]> {
  // TWO INPUTS, ONE READER. The supplier's own words (typed or dictated, up to RAW_TEXT_MAX), or — with
  // from_catalogue — its latest uploaded catalogue, read whole by _shared/catalogue_read.ts (21 Sep 2026).
  const fromCatalogue = body.from_catalogue === true;
  const cat = fromCatalogue ? await latestCatalogueText(admin, supplierId) : null;
  if (fromCatalogue && !cat) return [404, { error: 'no_catalogue', code: 'services_no_catalogue' }];
  const raw = fromCatalogue ? '' : String(body.text ?? '').slice(0, RAW_TEXT_MAX);
  if (!fromCatalogue && raw.trim().length < 2) return [400, { error: 'empty_text', code: 'services_empty_text' }];
  const [services, map] = await Promise.all([serviceVocab(admin), implicationMap(admin)]);
  // SUPPLY ONLY is proposed by the words, and the supplier's own answer overrides it (supply_only true /
  // false in the request, from "we also install" on the tab).
  const override = typeof body.supply_only === 'boolean' ? body.supply_only as boolean : undefined;
  const read = cat ? readCatalogue(cat.text, services, override) : null;
  const supply = read ? read.supply : supplyOnlyOf(raw);
  const supplyOnly = override ?? supply.supply_only;
  const rw0 = read ? read.rewrite : rewriteServices(raw, services, { supplyOnly });
  // A phrase of his own words that IS a trade code or slug is shown as that trade (rule 4, exactly).
  const rw1 = withExactTrades(rw0, await exactTradesOf(admin, ownWordsOf(rw0)));

  // WHAT MEANING READS: the parts no service was written exactly for, and — from a catalogue — its sentences
  // about the company (never its spec rows: catalogue_read.ts drops those); from typed text, the phrases the
  // rewrite set aside as prose ("We are an interior fit out company"). A part meaning proposes a service for is
  // shown as that proposal (off until the supplier adds it: ServicesTab, finding SP-F-06) and leaves his own
  // words; a part it proposes nothing for, or does not reach, stays his own words — never dropped.
  const unnamed = rw1.items.filter((i) => i.kind === 'unmatched').map((i) => i.text);
  const namedFrom = new Set(rw1.items.filter((i) => i.kind !== 'unmatched').map((i) => i.from));
  const prose = read ? read.lines.statements : splitPhrases(raw).filter((p) => !namedFrom.has(p));
  const meaning = await meaningFor(admin, services, [...unnamed, ...prose], rw1.service_keys, supplyOnly);
  const understood = new Set(meaning.proposals.flatMap((p) => p.lines));
  const rw = finishRewrite(rw1.items.filter((i) => !(i.kind === 'unmatched' && understood.has(i.text))));

  // WHAT THE STATED SERVICES ALSO COVER. The sources are the stated service keys, the trades those
  // services belong to (stating "decoration" states interior_fitout too), and any trade a phrase named
  // on its own. Read ONE level: what an implied service would imply is never added.
  const byKey = new Map(services.map((s) => [s.trade_code + '.' + s.code, s]));
  const sources = [...new Set([
    ...rw.service_keys,
    ...rw.service_keys.map((k) => k.split('.')[0]),
    ...rw.items.flatMap((i) => (i.kind === 'trade' ? i.trades : [])),
  ])];
  const { data: capRow } = await admin.from('supplier_capabilities').select('services_removed').eq('supplier_id', supplierId).maybeSingle();
  const removed = [...new Set([
    ...(Array.isArray(capRow?.services_removed) ? capRow!.services_removed as string[] : []),
    ...(Array.isArray(body.removed) ? (body.removed as unknown[]).map(String) : []),
  ])];
  const label = (code: string) => {
    const s = byKey.get(code);
    return s ? { en: s.label_en, ar: s.label_ar } : { en: code.replace(/[._]/g, ' '), ar: code.replace(/[._]/g, ' ') };
  };
  // A supply-only company gets every implication back already struck out (service_rewrite.ts says why).
  const implied: ImpliedOut[] = impliedServices(sources, map, rw.service_keys, removed, supplyOnly).map((i) => {
    const l = label(i.key);
    return {
      key: i.key, label_en: l.en, label_ar: l.ar, trade: i.key.split('.')[0], removed: i.removed,
      because: i.because.map((b) => ({ from: b.from, from_label_en: label(b.from).en, from_label_ar: label(b.from).ar, en: b.en, ar: b.ar })),
    };
  });
  // CODE READ NOTHING: the model path, which answers honestly that it is switched off.
  const model = (!rw.service_keys.length && !meaning.proposals.length)
    ? await readWithModel(admin, 'text', { text: cat ? cat.text : raw }, new Set(byKey.keys()))
    : null;
  return [200, {
    ok: true, raw_text: raw, items: rw.items, service_keys: rw.service_keys, own_words: rw.own_words,
    summary_en: rw.summary_en, summary_ar: rw.summary_ar, implied,
    pending_taxonomy: rw.items.filter((i) => i.kind === 'unmatched').map((i) => i.text),
    supply_only: { proposed: supply.supply_only, applied: supplyOnly, supply_words: supply.supply_words, install_words: supply.install_words },
    meaning: { state: meaning.state, proposals: meaning.proposals, lines: meaning.lines },
    source: cat ? { kind: 'catalogue', name: cat.name, read_from: cat.source } : { kind: 'typed' },
    ...(model ? { model } : {}),
  }];
}

/** Save the confirmed rewrite. The supplier's OWN WORDS are kept for anything no service was found for
 *  -- never dropped, never guessed -- and each becomes a taxonomy_trade_proposal the sales
 *  engineer decides. The raw text, the kept implications and the removed ones are stored separately. */
/** Test seams for servicesSaveRewrite: where background work is handed (EdgeRuntime.waitUntil in production) and how a
 *  word is read by reasoning (reasonTradesOf in production). */
export type SaveRewriteOpts = {
  waitUntil?: ((p: Promise<unknown>) => void) | null;
  reason?: (text: string, taxonomy: { code: string; label: string }[]) => Promise<{ codes: string[]; held: boolean }>;
};
export async function servicesSaveRewrite(admin: Admin, supplierId: number, body: Record<string, unknown>, declaredEmirates: string[] = [], opts: SaveRewriteOpts = {}): Promise<[number, Record<string, unknown>]> {
  const rows = await serviceRows(admin);
  const known = new Set(rows.map((r) => serviceKey(r.trade_code, r.code)));
  const arr = (v: unknown) => (Array.isArray(v) ? (v as unknown[]).map((s) => String(s ?? '')) : []);
  // A TRADE THE SUPPLIER REMOVED STAYS REMOVED (audit 21 Sep 2026, finding 10: "Remove this trade",
  // Update, reload -> the card was back, "Confirmed", nothing ticked). The trade list below is rebuilt
  // from the card list PLUS every trade a stated key or an own word resolves to, so a word such as
  // "الدهانات" resolving to painting put the removed trade straight back. An explicit removal in this
  // save now wins over every derived addition: its services, implications and resolved words drop it.
  const removedTrades = new Set(arr(body.removed_trades).map((t) => t.trim()).filter(Boolean));
  const ofRemoved = (k: string) => removedTrades.has(k.split('.')[0]);
  const stated = [...new Set(arr(body.services).filter((s) => known.has(s) && !ofRemoved(s)))];
  const implied = [...new Set(arr(body.implied).filter((s) => known.has(s) && !stated.includes(s) && !ofRemoved(s)))];
  // A REMOVAL THE CLIENT DID NOT RE-SEND IS STILL A REMOVAL (TypeScript review, 18 Sep 2026). The
  // preview merges what is stored before it offers the implied list; the save has to merge it too, or
  // a client that echoes only this screen's removals would quietly re-enable a service the supplier
  // struck out weeks ago. Anything now stated or kept wins over a stale removal.
  const { data: prevCap } = await admin.from('supplier_capabilities').select('services_removed,services,trades').eq('supplier_id', supplierId).maybeSingle();
  const removed = [...new Set([...(Array.isArray(prevCap?.services_removed) ? prevCap!.services_removed as string[] : []), ...arr(body.removed)])]
    .filter((s) => known.has(s) && !implied.includes(s) && !stated.includes(s));
  const own = cleanExtras(arr(body.own_words).map((w) => tidy(w)));
  const raw = String(body.raw_text ?? '').slice(0, RAW_TEXT_MAX);

  const vocabTrades = (await capabilityVocabulary(admin)).trades as { code: string; umbrella_code?: string | null }[];
  const umbrellaOf = Object.fromEntries(vocabTrades.map((t) => [t.code, t.umbrella_code]));
  const held = Array.isArray(prevCap?.trades) ? prevCap!.trades as string[] : [];
  const trades = new Set(keepTickedRefine(arr(body.trades).map((t) => t.trim()).filter(Boolean).slice(0, 25), held, umbrellaOf, stated));
  for (const k of stated) trades.add(k.split('.')[0]);
  // The supplier's own words still resolve to a TRADE where one is found exactly or by reasoning (resolveText);
  // where none is, the
  // words stay as the supplier wrote them and the sales engineer gets a proposal to map or add.
  //
  // Words ALREADY STORED are not resolved again: they were resolved when first saved, their trade is on
  // the card list since, and their proposal already exists. Re-resolving them on every Update is what
  // made a removed trade come back on the NEXT save too (finding 10). They are still re-sent and kept.
  const storedOwn = new Set(splitServices(prevCap?.services, known).extras.map((w) => w.toLowerCase()));
  const freshOwn = own.filter((w) => !storedOwn.has(w.toLowerCase()));
  const resolved: Record<string, string[]> = {}; const proposals: string[] = [];
  // EXACT FIRST, REASONING ONLY WHERE NEEDED, AND OFF THE CLOCK WHEN IT CAN BE (27 Oct 2026, sales_engineer; supplier
  // registration walk on production). Reading an own word by reasoning is a plan call and an answer call; with three
  // words the confirm took 37-67 s (measured, HTTP 200 every time) and the supplier waited on "Saving..." throughout. A
  // browser behind an intermediary that gives up near 30 s (the walk's container did: net::ERR_FAILED,
  // MissingAllowOriginHeader at 30.2 s, while Node and curl got the 200) is told "Could not save your services." for a
  // save that landed. So a word that resolves EXACTLY (fn_norm_trades, no model) counts now; when the save already names
  // a trade, the confirm is written and answered at once and the remaining words are read by reasoning AFTER the
  // response (EdgeRuntime.waitUntil). A trade they name is added by a second confirm of the same body; words no trade is
  // found for become the sales engineer's proposals exactly as before. When nothing names a trade yet, the words are
  // still read before answering, because without them there is nothing to confirm.
  // Guard: supabase/functions/_shared/supplier_services_save.test.ts ("a confirm with a trade answers before reasoning").
  const exactFor = await Promise.all(freshOwn.map((w) => exactTradesOfText(admin, w)));
  const toReason: string[] = [];
  freshOwn.forEach((w, i) => { if (exactFor[i].length) { resolved[w] = exactFor[i]; exactFor[i].forEach((c) => trades.add(c)); } else toReason.push(w); });
  const waitUntil = opts.waitUntil === undefined ? runtimeWaitUntil() : opts.waitUntil;
  const reason = opts.reason ?? ((t: string, tax: { code: string; label: string }[]) => reasonTradesOf(admin, t, tax));
  const defer = toReason.length > 0 && [...trades].some((t) => !removedTrades.has(t)) && !!waitUntil;
  // Independent lookups, so one round trip rather than up to 25 in series.
  const taxonomy = toReason.length ? await liveTaxonomy(admin) : [];
  if (!defer && toReason.length) {
    const codesFor = (await Promise.all(toReason.map((w) => reason(w, taxonomy)))).map((r) => r.codes);
    toReason.forEach((w, i) => { const codes = codesFor[i]; resolved[w] = codes; if (codes.length) codes.forEach((c) => trades.add(c)); else proposals.push(w); });
  }
  for (const t of removedTrades) trades.delete(t);
  if (!trades.size) return [400, { error: 'nothing_recognised', code: 'services_nothing_recognised' }];

  const { data: cap } = await admin.from('supplier_capabilities')
    .select('products_norm,coverage_emirates,brands,project_types,exclusions').eq('supplier_id', supplierId).maybeSingle();
  const coverage = Array.isArray(cap?.coverage_emirates) && cap.coverage_emirates.length ? cap.coverage_emirates : declaredEmirates;

  // THIS SCREEN'S OWN COLUMNS GO IN FIRST, and the confirm second (TypeScript review, 18 Sep 2026).
  // capabilityConfirm owns `services` and sets confirmed_at — the gate fn_match_capability opens on.
  // Writing these after it meant a failure here left the supplier CONFIRMED and matchable while
  // services_removed still said something else, and matching reads services_removed. In this order a
  // failure leaves the supplier exactly as matchable as it was before, with nothing confirmed.
  const { error: upErr } = await admin.from('supplier_capabilities').upsert({
    supplier_id: supplierId, services_raw_text: raw || null,
    services_implied: implied, services_removed: removed, services_rewritten_at: new Date().toISOString(),
  }, { onConflict: 'supplier_id' });
  if (upErr) return [500, { error: 'services_rewrite_write_failed', code: 'services_rewrite_write_failed', detail: upErr.message }];

  const confirmBody = {
    trades: [...trades], roles: body.roles,
    services: [...stated, ...own],
    products: cap?.products_norm || [], coverage_emirates: coverage || [],
    brands: cap?.brands || [], project_types: cap?.project_types || [], exclusions: cap?.exclusions || [],
  };
  const [status, out] = await capabilityConfirm(admin, supplierId, confirmBody);
  if (status !== 200) return [status, out];
  // HIS OWN WORDS FOR WHAT HE CONFIRMED (10 Nov 2026, ledger 1573): kept on his capability and filed to the alias queue.
  const aliasing = await recordOwnPhrases(admin, supplierId, stated, phrasesOf(body.phrases));

  // A pending taxonomy item that never reaches the sales engineer is the supplier's words lost, so
  // the failure is logged rather than swallowed (TypeScript review, 18 Sep 2026). It does not fail
  // the confirm: the words are already stored in `services`, and this row is the review queue.
  const propose = async (words: string[]) => {
    const fresh = words.map((p) => ({ words: p, code: tradeCode(p) })).filter((p) => p.code);
    if (!fresh.length) return fresh;
    const { error: propErr } = await admin.from('taxonomy_trade_proposal').upsert(fresh.map(({ words, code }) => {
      const isAr = langOf(words) === 'ar';
      return { supplier_id: supplierId, code, label_en: isAr ? null : words, label_ar: isAr ? words : null, note: 'services free text: pending taxonomy item' };
    }), { onConflict: 'supplier_id,code', ignoreDuplicates: true });
    if (propErr) console.error('taxonomy_trade_proposal upsert failed', supplierId, propErr.message);
    return fresh;
  };
  if (defer) {
    // After the answer: the same reading and the same outcome, written as a second confirm of the same body plus what
    // the words named. A removed trade stays removed; a failure is logged, never thrown into a response already sent.
    waitUntil!((async () => {
      try {
        const codesFor = (await Promise.all(toReason.map((w) => reason(w, taxonomy)))).map((r) => r.codes);
        const more = new Set<string>(); const unnamed: string[] = [];
        toReason.forEach((w, i) => {
          if (!codesFor[i].length) { unnamed.push(w); return; }
          for (const c of codesFor[i]) if (!removedTrades.has(c) && !trades.has(c)) more.add(c);
        });
        // Only while THIS save is still the latest confirm. The reading takes 37-67 s and the tab reloads at once, so the
        // supplier can save again inside that window; confirmBody is this save's body, and confirming it then would put
        // back what the newer save changed and write a ledger version he never confirmed (reviewer, 27 Oct 2026).
        // Guard: supplier_services_save.test.ts ("a newer save inside the reading window is not overwritten").
        if (more.size) {
          const { data: latest } = await admin.from('supplier_capabilities').select('confirmed_version').eq('supplier_id', supplierId).maybeSingle();
          if (Number(latest?.confirmed_version) !== Number(out.version)) {
            console.warn('services_save_rewrite: a newer confirm landed while the words were read; not overwriting it', supplierId, [...more].join(','));
          } else {
            const [s2, o2] = await capabilityConfirm(admin, supplierId, { ...confirmBody, trades: [...trades, ...more] });
            if (s2 !== 200) console.error('services_save_rewrite: the trades the words named were not added', supplierId, JSON.stringify(o2).slice(0, 300));
          }
        }
        await propose(unnamed);
      } catch (e) { console.error('services_save_rewrite background reading failed', supplierId, String((e as Error)?.message || e)); }
    })());
    return [200, { ...out, services: stated, implied, removed, own_words: own, resolved, proposed_trades: [], reading_words: toReason, aliasing }];
  }
  const fresh = await propose(proposals);
  return [200, { ...out, services: stated, implied, removed, own_words: own, resolved, proposed_trades: fresh.map((p) => p.code), aliasing }];
}

// ── HIS OWN WORDS BECOME NAMES, THROUGH THE SALES ENGINEER (10 Nov 2026, sales_engineer; founder ledger 1573/1579) ──────
// Measured (design audit 10 Nov 2026): "PVC decorative panels", read off a profile and confirmed by the supplier, stayed a
// phrase nobody else's words could ever equal: taxonomy_trade_proposal holds trades only. Now each phrase he confirmed for a
// service — a line of his profile the documents proposed it from, or a line meaning read from his own description — is
//   * kept on his capability (supplier_capabilities.service_phrases: [{phrase, key, at}]), and
//   * filed to public.service_alias_proposal (fn_service_alias_propose). Only the sales engineer's approval
//     (fn_service_alias_decide; sales_engineer action alias_decide) makes it an alias, and an alias only translates text to
//     a code: matching still compares codes (ruling 890).
// Never fails the confirm: until the SQL is applied both writes answer an error, which is logged and returned as `aliasing`.
export const phrasesOf = (v: unknown): { phrase: string; key: string }[] =>
  (Array.isArray(v) ? v : []).flatMap((x) => (x && typeof x === 'object' ? [{ phrase: String((x as { phrase?: unknown }).phrase ?? ''), key: String((x as { key?: unknown }).key ?? '') }] : []));

export async function recordOwnPhrases(admin: Admin, supplierId: number, stated: string[], sent: { phrase: string; key: string }[]):
  Promise<{ pairs: number; proposed: number; error?: string }> {
  try {
    const { data: cap } = await admin.from('supplier_capabilities').select('source_docs,service_phrases').eq('supplier_id', supplierId).maybeSingle();
    const fromDocs = (Array.isArray(cap?.source_docs?.proposed_services) ? cap!.source_docs.proposed_services as ProposedService[] : [])
      .map((p) => ({ phrase: p.phrase, key: p.key }));
    const pairs: AliasPair[] = aliasPairsOf([...fromDocs, ...sent], stated);
    if (!pairs.length) return { pairs: 0, proposed: 0 };
    const at = new Date().toISOString();
    const prev = Array.isArray(cap?.service_phrases) ? cap!.service_phrases as { phrase: string; key: string; at?: string }[] : [];
    const merged = [...prev.filter((p) => !pairs.some((q) => q.key === p.key && q.phrase.toLowerCase() === String(p.phrase).toLowerCase())), ...pairs.map((p) => ({ ...p, at }))]
      .filter((p) => stated.includes(p.key)).slice(-100);
    const { error: upErr } = await admin.from('supplier_capabilities').update({ service_phrases: merged }).eq('supplier_id', supplierId);
    if (upErr) console.error('recordOwnPhrases: service_phrases not written', supplierId, upErr.message);
    const { data, error } = await admin.rpc('fn_service_alias_propose', { p_supplier_id: supplierId, p_pairs: pairs, p_source: 'supplier_confirmed' });
    if (error) { console.error('recordOwnPhrases: alias queue', supplierId, error.message); return { pairs: pairs.length, proposed: 0, error: error.message }; }
    const proposed = Number((data as { proposed?: number })?.proposed ?? 0);
    if (proposed > 0) {
      const target = String(supplierId);
      const { data: open } = await admin.from('agent_actions').select('id').eq('kind', 'service_alias_review').eq('status', 'pending').eq('target_id', target).limit(1);
      if (!open?.length) {
        await admin.from('agent_actions').insert({ agent: 'sales_engineer', kind: 'service_alias_review', status: 'pending', risk: 'low',
          title: `Review a supplier's own names for services he confirmed (${proposed})`,
          detail: { supplier_id: supplierId, pairs, waiting_for: 'sales_engineer to approve or reject each phrase as an alias (sales_engineer action alias_proposals / alias_decide)' },
          target_table: 'service_alias_proposal', target_id: target });
      }
    }
    return { pairs: pairs.length, proposed };
  } catch (e) {
    const m = String((e as Error)?.message || e).slice(0, 200);
    console.error('recordOwnPhrases failed', supplierId, m);
    return { pairs: 0, proposed: 0, error: m };
  }
}
