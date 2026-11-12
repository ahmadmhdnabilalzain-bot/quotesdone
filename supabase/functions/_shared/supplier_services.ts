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
import { finishRewrite, impliedServices, splitPhrases, tidy, type Implication, type ServiceTerm } from './service_rewrite.ts';
import { activeServiceRows, serviceVocab } from './service_vocabulary.ts';
import { liveProfileReader, proposalOf, type ProfileReader, type ProfileReading, type Proposal } from './supplier_profile_reading.ts';
import { tradeOfWords } from './reasoned_matching.ts';
import { defaultDeps } from './think.ts';
import { runtimeWaitUntil } from './async_webhook.ts';
import { aliasPairsOf, type AliasPair, type LicenceCheck, type ProposedService } from './profile_services.ts';
import { listQuestions } from './supplier_service_questions.ts';

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

/** The trades kept at Confirm among those his documents proposed: one he held already, chose at sign-up, or ticked a service in. */
export function keepTickedProposed(sent: string[], proposed: string[], held: string[], signup: string | null, stated: string[]): string[] {
  return sent.filter((t) => !proposed.includes(t) || held.includes(t) || t === signup || stated.some((k) => k.startsWith(t + '.')));
}

export async function servicesState(admin: Admin, supplierId: number) {
  // Independent reads, started together.
  const [base, rows, lead, questions] = await Promise.all([
    capabilityState(admin, supplierId),
    serviceRows(admin),
    admin.from('leads').select('sector,service_emirates').eq('id', supplierId).maybeSingle().then((r: { data: { sector?: unknown; service_emirates?: unknown } | null }) => r.data, () => null),
    // the questions put to him (slice 4): [] before the table exists, or when it cannot be read; the tab then shows the tick list alone
    listQuestions(admin, supplierId).catch(() => []),
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
  // supplier_doc_trades.readTogether (the model, ruling 1627), each with the line it was understood from and the model's licence judgement.
  // OFFERED, NOT TICKED: founder 862 ("it start unticked") and 857 (a service is his only when he ticks it) stand; the tab
  // shows them first, marked as proposed, with one button that ticks them all for him to review.
  const src = (cap?.source_docs && typeof cap.source_docs === 'object') ? cap.source_docs as Record<string, unknown> : {};
  const labelByKey = new Map(rows.map((r) => [serviceKey(r.trade_code, r.code), r]));
  const proposedServices = (Array.isArray(src.proposed_services) ? src.proposed_services as ProposedService[] : [])
    .filter((p) => p && known.has(p.key))
    .map((p) => ({ key: p.key, trade: p.trade, label_en: labelByKey.get(p.key)?.label_en ?? p.label_en, label_ar: labelByKey.get(p.key)?.label_ar ?? '',
                   phrase: p.phrase, snippet: p.snippet, via: p.via, licence: p.licence, doc: p.doc, stated: ticked.includes(p.key),
                   delivery: p.delivery === 'partner' ? 'partner' as const : 'own' as const, partner_name: p.partner_name ?? null,
                   basis: p.basis ?? (p.delivery === 'partner' ? 'partner' as const : 'stated' as const), check: !!p.check }));
  const licenceCheck = (src.licence_check && typeof src.licence_check === 'object') ? src.licence_check as LicenceCheck : null;
  // THE READING (reader @5, 12 Nov 2026, ruling 1647; supplier_profile_reading.ts): what was read off his documents, the tick list (the
  // services he is shown, unticked), the services through a partner, the phrases kept in his own words, and the questions drafted for
  // him (shown in slice 4). Older records have none: null.
  const rd = (src.reading && typeof src.reading === 'object') ? src.reading as Record<string, unknown> : null;
  const reading = rd ? { reader: rd.reader ?? null, read_at: rd.read_at ?? null, summary: rd.summary ?? '', tick: rd.tick ?? [], partner: rd.partner ?? [],
    own_words: rd.own_words ?? [], questions: rd.questions ?? [], licence: rd.licence ?? null, areas: rd.areas ?? [], roles: rd.roles ?? [], brands: rd.brands ?? [] } : null;
  // while the mapping runs: the summary and his services in his own words, as soon as step A has read them (reader @5, "not laggy")
  const progress = (src.reading_progress && typeof src.reading_progress === 'object') ? src.reading_progress : null;
  return {
    proposed_services: proposedServices, licence_check: licenceCheck, reading, tick_list: (reading?.tick ?? []) as unknown[], reading_progress: progress,
    // THE QUESTIONS (slice 4, ruling 1647): the rows of public.supplier_service_question, each answered one at a time by
    // services_answer; what he delivers through a partner, as he last confirmed it.
    questions, services_partner: Array.isArray(cap?.services_partner) ? cap!.services_partner as string[] : [],
    // the emirates he named at sign-up: "Where you work" on the check screen until he confirms his own (coverage_emirates)
    declared_emirates: Array.isArray(lead?.service_emirates) ? (lead!.service_emirates as unknown[]).map(String) : [],
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
// So ADDING a service is ONE free text box (plus the mic, behind the same flag as before). Since 12 Nov 2026 (rulings
// 1663/1664) the MODEL reads what he wrote, as it reads his documents (servicesRewrite below); a text made only of our own
// service names is those services. The supplier is shown the rewrite, adds or removes, and confirms; only then is anything saved.
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

/** THE PREVIEW: what the supplier typed (or dictated) on the Services tab, READ BY THE MODEL (12 Nov 2026, it_engineer for
 *  sales_engineer; founder rulings 1663/1664/1666: "sales age, any chat with customers, widget, anything like that, it's not code
 *  first"; LLM-first audit A3; review of PR #1980). Until today his words went to exact names and aliases, then gte-small vectors
 *  (service_meaning), and the model was asked only when code matched NOTHING: "Supply & fix of gypsum partitions and some painting
 *  touch-ups" matched "painting" exactly and the model never read the sentence. Now NOTHING is listed as his here; everything is
 *  OFFERED, off until he adds it (`meaning.proposals`, the list the tab already shows unticked):
 *   * EVERY PART IS ONE OF OUR SERVICE NAMES (exactLabelsOf): the text, split at commas, semicolons and lines, is in every part the
 *     English or Arabic label of exactly ONE service in the whole catalogue, character for character after trimming and case. Those
 *     services are offered (because 'exact_label') and no model is asked: a known fact, not a reading of his words. Even so it is
 *     never listed for him ("Plastic" is the label of recycling_scrap.plastic; a plastics trader may mean something else);
 *   * ANYTHING ELSE IS THE MODEL'S: the same two steps that read his documents (supplier_profile_reading.readInTwoSteps), on his
 *     claims only (claimsOnly), in parts of REWRITE_PART_CHARS read at once. Code only CHECKS that each quote is in his words and each
 *     key is ours, and proposalOf decides what is offered. A service his words say goes through a PARTNER is never offered (the tab
 *     and "Something else" cannot yet keep it as partner work, and one tap would make it his own): its line stays his own words;
 *   * SUPPLY ONLY is his own answer (`supply_only` in the request) when he gave one, else what the model read in these words, else
 *     what the reading of his documents said (source_docs.reading.supply_only); never a word list (audit A4). The tab's toggle
 *     changes the answer on screen without asking again;
 *   * NO ANSWER WITHIN REWRITE_DEADLINE_MS, or none at all: 200 with every part of his text kept as his own words, meaning.state
 *     'unavailable' and a plain line saying so. He loses nothing; nothing re-reads them later (no "owed" state exists for typed words).
 *  `opts.reader` is for tests: the live reader is supplier_profile_reading.liveProfileReader. Nothing is saved here. */
export type RewriteOpts = { reader?: ProfileReader; deadlineMs?: number };
// THE WAIT (estimates from the hard-profile recordings, scripts/e2e/services_hard_profiles/recorded.json, 12 Nov 2026, NOT measured on
// typed text): step A on 413-490 character profiles took 22-57 s, step B 11-27 s a call. A typed line whose claims code can name (a
// catalogue name or alias of the model's own words) needs no step B. REWRITE_PART_CHARS: a 2,000-character text is read as four
// parts at once, each the size of the shortest recorded profiles, not as one 2,000-character read (18-75 s measured, plus mapping).
// REWRITE_DEADLINE_MS: below the tab's 90 s (src/components/portal/supplier/api.ts REASONING_TIMEOUT_MS) with room for the catalogue
// read and the network, so he is never told "Could not read that text" while the server is still reading.
export const REWRITE_PART_CHARS = 600, REWRITE_DEADLINE_MS = 70_000;
export const REWRITE_UNAVAILABLE_EN = 'We kept your words exactly as you wrote them. We could not read them just now: you can save them as they are, or try again in a minute.';
/** The services the text names when EVERY part of it is exactly one service's English or Arabic label; null otherwise. */
export function exactLabelsOf(text: string, services: ServiceTerm[]): ServiceTerm[] | null {
  const norm = (x: string) => String(x ?? '').replace(/\s+/g, ' ').trim().toLowerCase();
  const byLabel = new Map<string, ServiceTerm | null>();
  for (const sv of services) for (const l of [sv.label_en, sv.label_ar]) {
    const k = norm(l); if (!k) continue;
    const cur = byLabel.get(k);
    byLabel.set(k, cur === undefined || (cur && cur.trade_code === sv.trade_code && cur.code === sv.code) ? sv : null);   // a label two services share is neither's
  }
  const parts = String(text ?? '').split(/\r?\n|[,\u060C;\u061B]+/).map(norm).filter(Boolean);
  const hits = parts.map((p) => byLabel.get(p) ?? null);
  return parts.length && hits.every((h) => !!h) ? hits as ServiceTerm[] : null;
}
const TYPED_PATH = 'services_tab:typed';
type Offer = { key: string; trade: string; label_en: string; label_ar: string; because: 'model' | 'exact_label'; word: null; lines: string[]; delivery: 'own'; check?: true };
export async function servicesRewrite(admin: Admin, supplierId: number, body: Record<string, unknown>, opts: RewriteOpts = {}): Promise<[number, Record<string, unknown>]> {
  // ONE INPUT: the supplier's own words, typed or dictated, up to RAW_TEXT_MAX. "Read my catalogue" (from_catalogue, 21 Sep 2026)
  // read his uploaded catalogue here by exact names and meaning: a second, word-and-vector reading of a document, DELETED on
  // 11 Nov 2026 (customer_support; founder ruling 1627). His catalogue is read by the model with all his other documents when he
  // uploads it (supplier_doc_trades.readTogether), and what it understood is offered above as proposed services.
  const raw = String(body.text ?? '').slice(0, RAW_TEXT_MAX);
  if (raw.trim().length < 2) return [400, { error: 'empty_text', code: 'services_empty_text' }];
  // the names only (serviceVocab also loads both 1,151-row vector columns, which nothing here reads since the model reads his words)
  const [vocab, map] = await Promise.all([activeServiceRows<ServiceTerm>(admin, 'trade_code,code,label_en,label_ar'), implicationMap(admin)]);
  const services = vocab.data;
  // his own answer ("We also install" / "We only supply" on the tab) wins over every reading
  const override = typeof body.supply_only === 'boolean' ? body.supply_only as boolean : undefined;
  const { data: capRow } = await admin.from('supplier_capabilities').select('services_removed,profile_supply_only:source_docs->reading->supply_only').eq('supplier_id', supplierId).maybeSingle();
  const removed = [...new Set([
    ...(Array.isArray(capRow?.services_removed) ? capRow!.services_removed as string[] : []),
    ...(Array.isArray(body.removed) ? (body.removed as unknown[]).map(String) : []),
  ])];
  const byKey = new Map(services.map((s) => [s.trade_code + '.' + s.code, s]));
  const label = (code: string) => {
    const s = byKey.get(code);
    return s ? { en: s.label_en, ar: s.label_ar } : { en: code.replace(/[._]/g, ' '), ar: code.replace(/[._]/g, ' ') };
  };
  const profileSays = capRow?.profile_supply_only === true || capRow?.profile_supply_only === 'true' ? true : capRow?.profile_supply_only === false || capRow?.profile_supply_only === 'false' ? false : null;
  const exact = exactLabelsOf(raw, services);
  let reading: ProfileReading | null = null, proposal: Proposal | null = null, unavailable: string | null = null;
  if (!exact) {
    const read = opts.reader ?? liveProfileReader(admin, { subject: { supplier_id: supplierId, surface: 'services_rewrite' } });
    const said = override === undefined ? undefined : override ? 'my company only supplies goods; we do no installation or other work on site.' : 'my company also installs and does the work on site.';
    let timer: ReturnType<typeof setTimeout> | undefined;
    const late = new Promise<{ ok: false; error: string }>((res) => { timer = setTimeout(() => res({ ok: false, error: `no answer within ${opts.deadlineMs ?? REWRITE_DEADLINE_MS} ms` }), opts.deadlineMs ?? REWRITE_DEADLINE_MS); });
    const r = await Promise.race([read([{ path: TYPED_PATH, name: 'what the supplier typed on the Services tab', kind: 'profile', text: raw }], null,
      { said, claimsOnly: true, partChars: REWRITE_PART_CHARS }), late]).finally(() => clearTimeout(timer));
    if (r.ok) { reading = r.reading; proposal = proposalOf(r.reading, r.taxonomy, r.implications); }
    else { unavailable = r.error; console.error(JSON.stringify({ at: 'supplier_services.servicesRewrite', supplier: supplierId, error: r.error })); }
  }
  // SUPPLY ONLY: his answer, else the model's reading of these words, else the reading of his documents; unsaid is not supply only
  const proposedSo = reading?.supply_only ?? profileSays ?? false;
  const supplyOnly = override ?? proposedSo;
  const by = override !== undefined ? 'his_answer' : typeof reading?.supply_only === 'boolean' ? 'his_words' : profileSays !== null ? 'his_documents' : 'unsaid';
  // HIS OWN WORDS, exactly as he wrote them: no answer keeps every part; else each line a claim no key covers, each vague line, and
  // each line his words say goes through a partner
  const own = unavailable !== null ? splitPhrases(raw)
    : [...(proposal?.own_words ?? []).map((w) => w.quote), ...(reading?.vague ?? []).filter((v) => v.doc && v.quote).map((v) => v.quote), ...(proposal?.partner ?? []).map((x) => x.quote)];
  const rw = finishRewrite([...new Set(own)].map((q) => ({ kind: 'unmatched' as const, text: q, from: q })));
  // WHAT IS OFFERED, OFF UNTIL HE ADDS IT: his own claims and the work he describes, each with his line (never a partner service)
  const offered: Offer[] = exact
    ? exact.map((sv) => ({ key: sv.trade_code + '.' + sv.code, trade: sv.trade_code, label_en: sv.label_en, label_ar: sv.label_ar, because: 'exact_label', word: null, lines: [sv.label_en], delivery: 'own' }))
    : [...(proposal?.tick ?? []), ...(proposal?.shown ?? [])].map((x) => ({ key: x.key, trade: x.trade, label_en: label(x.key).en, label_ar: label(x.key).ar, because: 'model' as const, word: null, lines: [x.quote], delivery: 'own' as const, ...(x.check ? { check: true as const } : {}) }));
  const proposals = offered.filter((o, i) => offered.findIndex((y) => y.key === o.key) === i && byKey.has(o.key));
  // WHAT THE OFFERED SERVICES ALSO COVER (ruling 439), ONE level, struck out like them: nothing he has not said yes to is on
  const implied: ImpliedOut[] = impliedServices([...new Set([...proposals.map((p) => p.key), ...proposals.map((p) => p.trade)])], map, proposals.map((p) => p.key), removed, true)
    .filter((i) => byKey.has(i.key)).map((i) => {
      const l = label(i.key);
      return {
        key: i.key, label_en: l.en, label_ar: l.ar, trade: i.key.split('.')[0], removed: i.removed,
        because: i.because.map((b) => ({ from: b.from, from_label_en: label(b.from).en, from_label_ar: label(b.from).ar, en: b.en, ar: b.ar })),
      };
    });
  return [200, {
    ok: true, raw_text: raw, items: rw.items, service_keys: rw.service_keys, own_words: rw.own_words,
    summary_en: reading?.summary || rw.summary_en, summary_ar: rw.summary_ar, implied,
    pending_taxonomy: rw.items.filter((i) => i.kind === 'unmatched').map((i) => i.text),
    supply_only: { proposed: proposedSo, applied: supplyOnly, by },
    meaning: { state: unavailable !== null ? 'unavailable' : exact ? 'exact_labels' : 'model', proposals },
    source: { kind: 'typed' },
    ...(unavailable !== null ? { model: { state: 'unavailable', message_en: REWRITE_UNAVAILABLE_EN } } : {}),
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
  const { data: prevCap } = await admin.from('supplier_capabilities').select('services_removed,services,trades,proposed_trades,confirmed_at').eq('supplier_id', supplierId).maybeSingle();
  const removed = [...new Set([...(Array.isArray(prevCap?.services_removed) ? prevCap!.services_removed as string[] : []), ...arr(body.removed)])]
    .filter((s) => known.has(s) && !implied.includes(s) && !stated.includes(s));
  // ASKED, NEVER ASSUMED (slice 4, report 3.7 and decision 4): for a supplier profiled by the questions (`asked`), every curated
  // implication of what he confirmed that he did not tick himself is REMOVED, so fn_services_effective adds nothing he was never
  // asked about. Suppliers confirmed before keep ruling 439's behaviour until they are asked (slice 8).
  // NEVER for a supplier who confirmed before (independent review of slice 4, 12 Nov 2026): his implied services were his by ruling 439
  // and he was never asked about them; a new document must not strip them on his next Update (lead 19398: 39 services, 8 trades).
  if (body.asked === true && !prevCap?.confirmed_at) {
    const map = await implicationMap(admin);
    const sources = new Set([...stated, ...stated.map((k) => k.split('.')[0]), ...arr(body.trades)]);
    for (const i of map) if (sources.has(i.from) && known.has(i.to) && !stated.includes(i.to) && !implied.includes(i.to) && !removed.includes(i.to)) removed.push(i.to);
  }
  // THROUGH A PARTNER: a subset of what he states (capabilityConfirm enforces it again, as the one writer)
  const own = cleanExtras(arr(body.own_words).map((w) => tidy(w)));
  // ...a key he states, or his own words for work through a partner ("Jacuzzi", no key): the words keep their partner basis beside them
  // (both sit in `services`, so the subset rule holds; review of slice 4, finding 12)
  const partner = [...new Set(arr(body.partner).map((w) => (stated.includes(w) ? w : tidy(w))))].filter((k) => stated.includes(k) || own.includes(k));
  const raw = String(body.raw_text ?? '').slice(0, RAW_TEXT_MAX);

  const vocabTrades = (await capabilityVocabulary(admin)).trades as { code: string; umbrella_code?: string | null }[];
  const umbrellaOf = Object.fromEntries(vocabTrades.map((t) => [t.code, t.umbrella_code]));
  const held = Array.isArray(prevCap?.trades) ? prevCap!.trades as string[] : [];
  const trades = new Set(keepTickedRefine(arr(body.trades).map((t) => t.trim()).filter(Boolean).slice(0, 25), held, umbrellaOf, stated));
  for (const k of stated) trades.add(k.split('.')[0]);
  // A TRADE HIS DOCUMENTS PROPOSED IS HIS ONLY WHEN HE TICKED A SERVICE IN IT (review of branch 2, 12 Nov 2026; ruling 1647): a trade alone
  // receives every request that names no service, so a listed trade he ticked nothing in is never confirmed for him. A trade he already
  // held, or chose at sign-up (his own answer), stays. Whatever a client sends, it holds here.
  const proposedByDocs = Array.isArray(prevCap?.proposed_trades) ? prevCap!.proposed_trades as string[] : [];
  if (proposedByDocs.length) {
    const { data: lead } = await admin.from('leads').select('sector').eq('id', supplierId).maybeSingle();
    const keep = new Set(keepTickedProposed([...trades], proposedByDocs, held, signupTradeOf(lead?.sector, vocabTrades), stated));
    for (const t of [...trades]) if (!keep.has(t)) trades.delete(t);
  }
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
  // "Where you work" on the check screen: what he sends wins; else what is stored; else what he declared at sign-up
  const sentCoverage = arr(body.coverage_emirates).map((e) => e.trim()).filter(Boolean);
  const coverage = sentCoverage.length ? sentCoverage : Array.isArray(cap?.coverage_emirates) && cap.coverage_emirates.length ? cap.coverage_emirates : declaredEmirates;

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
    services: [...stated, ...own], services_partner: partner,
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
    return [200, { ...out, services: stated, partner, implied, removed, own_words: own, resolved, proposed_trades: [], reading_words: toReason, aliasing }];
  }
  const fresh = await propose(proposals);
  return [200, { ...out, services: stated, partner, implied, removed, own_words: own, resolved, proposed_trades: fresh.map((p) => p.code), aliasing }];
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
