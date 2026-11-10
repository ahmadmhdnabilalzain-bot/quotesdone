// inquiry_state — ONE STATE PER INQUIRY CONVERSATION, READ AND WRITTEN BY EVERY SURFACE (10 Nov 2026, sales_engineer, with
// customer_support for the shared state; founder ledger 1572: "Hard limit 100 messages per inquiry, and nothing said in
// message 2 may be forgotten by message 30+").
//
// MEASURED (design audit 10 Nov 2026): the request chat, the portal assistant, WhatsApp and the widget shared nothing but
// the stored transcript. "New request" after a portal chat opened a blank request; no surface had a message limit; and a
// customer who said "I don't know" in Egyptian or Levantine Arabic ("mesh 3aref", "ma ba3ref", "madri") was not recorded as
// not knowing, so the same spec could be asked again.
//
// WHAT LIVES HERE (pure functions, tested offline in inquiry_state.test.ts), and what the table holds
// (scripts/sql/every_inquiry_conversation_keeps_one_state_every_surface_reads.sql):
//   * the conversation keys of each surface;
//   * THE 100-MESSAGE CAP as code: converge from message 80 (ask only for what is missing), summarise from 95, hand off to
//     the sales engineer's queue at 100, and never send message 101. Every message counts, the customer's and ours;
//   * saysDontKnow: "I don't know" in English, Modern Standard Arabic, Egyptian, Levantine and Gulf Arabic and Arabizi. It
//     only ever applies to the spec the seat asked last (the caller names it), and only adds a key to "unknown", which
//     blocks asking that key again: it never fills a spec (exact specs or the quote is held, founder 14 Sep 2026);
//   * dialectOf: the register the customer writes in, a LABEL kept on the state for the reply rule and the eval. It
//     decides nothing about what they asked (ruling 890): the reply model reads their words itself;
//   * blockedKeys and stateSummary: what may never be asked again, and the state as text for a prompt;
//   * mergeState / readState / carryState: the database calls, each answering null when the table cannot be read (the
//     SQL is applied at merge), so no surface depends on it to answer a customer.
// prevented by: supabase/functions/_shared/inquiry_state.test.ts

export type Surface = 'request_chat' | 'portal_assistant' | 'widget' | 'whatsapp';
export type Dialect = 'gulf' | 'egyptian' | 'levantine' | 'msa' | 'english' | 'arabizi' | 'mixed';
export type Script = 'arabic' | 'latin' | 'arabizi' | 'mixed';
export type StateStatus = 'open' | 'converging' | 'summarising' | 'handed_off' | 'carried' | 'closed';
export interface SpecEntry { value: string; turn?: number | null; first_turn?: number | null; changed_from?: string | null; src?: string }
export interface InquiryState {
  conv_key: string; surface: Surface; party_key?: string | null; episode_from?: number; intake_id?: string | null;
  source_key?: string | null; carried_to?: string | null; trade?: string | null; trade_codes?: string[];
  specs: Record<string, SpecEntry>; unknown: Record<string, { turn?: number | null; said?: string }>;
  asked: Record<string, { count: number; last_turn?: number | null }>;
  language?: 'en' | 'ar' | null; dialect?: Dialect | null; dialect_by?: 'model' | 'markers' | null; script?: Script | null;
  message_count: number; status: StateStatus; handoff_id?: number | null;
  // PHASE 2 (ledger 1572/1579/1586): the expert's half. Codes are those of solution_catalogue.json; a model's option that
  // the catalogue lacks is kept by its own short code with problem null (the agent advises past the catalogue's edge).
  condition?: Record<string, { value: string; turn?: number | null; changed_from?: string | null }>;
  options_offered?: OfferedOption[];
  chosen_option?: (OfferedOption & { label?: string; changed_from?: { problem: string | null; option: string } }) | null;
  budget?: { value: string; turn?: number | null; changed_from?: string | null } | null;
}
export interface OfferedOption { problem: string | null; option: string; turn?: number | null; src?: string }
export interface StatePatch {
  turn?: number; party_key?: string; episode_from?: number; src?: string;
  specs?: Record<string, string | { value: string; turn?: number }>;
  unknown?: Record<string, string | { said?: string; turn?: number }>;
  asked?: string[]; message_count?: number; language?: 'en' | 'ar'; dialect?: Dialect | null; dialect_by?: 'model' | 'markers';
  script?: Script | null; trade?: string | null; trade_codes?: string[]; intake_id?: string; handoff_id?: number; status?: StateStatus;
  condition?: Record<string, string>; options_offered?: { problem: string | null; option: string }[];
  chosen_option?: { problem: string | null; option: string; label?: string }; budget?: string;
}

// ── the conversation keys ────────────────────────────────────────────────────────────────────────────────────────────
export const intakeKey = (intakeId: string) => 'intake:' + intakeId;
/** The portal's one conversation per customer (ruling 1255) holds many jobs; each job from its episode start is one inquiry. */
export const portalKey = (accountKey: string, episodeFrom: number) => accountKey + '#' + Math.max(0, Math.floor(episodeFrom || 0));
export const whatsappKey = (phone: string) => 'wa:' + String(phone || '').replace(/^whatsapp:/, '');

// ── THE 100-MESSAGE CAP (founder ledger 1572) ───────────────────────────────────────────────────────────────────────
export const MESSAGE_CAP = 100;
export const CONVERGE_AT = 80;
export const SUMMARISE_AT = 95;
export type CapStage = 'normal' | 'converge' | 'summarise' | 'handoff' | 'over';
/** The stage of the reply about to be written, by its number in the conversation (every message counts, both sides).
 *  Message 100 is the hand-off reply; past it nothing is sent at all (`over`): the sales engineer has the request. */
export function capStage(replyNumber: number): CapStage {
  const n = Math.floor(Number(replyNumber) || 0);
  if (n > MESSAGE_CAP) return 'over';
  if (n === MESSAGE_CAP) return 'handoff';
  if (n >= SUMMARISE_AT) return 'summarise';
  if (n >= CONVERGE_AT) return 'converge';
  return 'normal';
}
export const statusOfStage = (s: CapStage): StateStatus =>
  s === 'converge' ? 'converging' : s === 'summarise' ? 'summarising' : s === 'handoff' || s === 'over' ? 'handed_off' : 'open';
/** What the reply model is told at each stage (code decides the stage; the model writes the words, ruling 1196). */
export function capRule(s: CapStage, replyNumber?: number): string {
  const at = (n?: number) => (n ? ` (this reply is message ${n} of ${MESSAGE_CAP})` : '');
  if (s === 'converge') return `THIS CONVERSATION IS NEAR ITS LIMIT${at(replyNumber)}. Ask only for the required details still missing, one at a time; no other question and no new topic.`;
  if (s === 'summarise') return `THIS CONVERSATION IS AT ITS LIMIT${at(replyNumber)}. Give a short summary of the request as we hold it and the items still open, and ask them to confirm it or answer the open items. No other question.`;
  if (s === 'handoff') return `THIS IS THE LAST MESSAGE OF THIS CONVERSATION (message ${MESSAGE_CAP} of ${MESSAGE_CAP}). Tell them, in one or two sentences, that our sales engineer now has their whole request and will continue with them here, and that nothing they said needs repeating. Ask nothing.`;
  return '';
}

// ── "I DON'T KNOW", in every way the UAE's customers write it ──────────────────────────────────────────────────────
// Arabic is compared after removing diacritics and tatweel and unifying alef, ya and ta marbuta, the way the portal's
// detectors already normalise (conversation_trade.normalise), so one form covers its spellings.
export function arNorm(s: string): string {
  return String(s || '').toLowerCase().replace(/[ً-ْٰـ]/g, '').replace(/[أإآٱ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه')
    .replace(/ؤ/g, 'و').replace(/ئ/g, 'ي').replace(/[؟?!.,،؛:"'()]/g, ' ').replace(/\s+/g, ' ').trim();
}
const DONT_KNOW_EN = /\b(not sure|unsure|don'?t know|dont know|do not know|no idea|no clue|idk|not decided|haven'?t decided|can'?t say|no preference)\b/i;
// MSA, Egyptian, Levantine, Gulf (normalised forms; each is a whole phrase, so "اعرف" inside another sentence is not one)
const DONT_KNOW_AR = new RegExp('(^|\\s)(' + [
  'لا اعرف', 'لا ادري', 'لست متاكد', 'لست متاكدا', 'لست متاكده', 'غير متاكد', 'غير متاكده', 'لا علم لي', 'ليس لدي فكره',
  'مش عارف', 'مش عارفه', 'مش عارفين', 'معرفش', 'ماعرفش', 'ما اعرفش', 'مش متاكد', 'مش متاكده', 'معنديش فكره', 'مش فاكر',
  'ما بعرف', 'مابعرف', 'ما بعرفش', 'ما عندي فكره', 'ماني متاكد', 'مانيش متاكد', 'مش اكيد',
  'مدري', 'ما ادري', 'ماادري', 'ما اعرف', 'مااعرف', 'مو متاكد', 'مب متاكد', 'ما عندي علم', 'ما ني متاكد',
].join('|') + ')(\\s|$)');
// Arabizi: Arabic written in Latin letters with digits for the letters Latin lacks
const DONT_KNOW_ARABIZI = /\b(m[ei]?sh|msh|mush)\s+(3a?r[ie]?f[ae]?|3arfa|mt2a?k[ei]d|met2aked)\b|\bma?3raf(sh|ish)\b|\bma\s*ba3r[ae]f\b|\bmba3r[ae]f\b|\bmadri\b|\bma\s*adri\b|\bmo\s+mt2a?k[ei]d\b/i;
export function saysDontKnow(text: string): boolean {
  const t = String(text || '');
  return DONT_KNOW_EN.test(t) || DONT_KNOW_AR.test(arNorm(t)) || DONT_KNOW_ARABIZI.test(t);
}

// ── THE REGISTER THEY WRITE IN (a label: the reply model reads their words itself) ─────────────────────────────────
// Each marker is a word the guide knowledge/brief/gulf_arabic_guide.md lists as belonging to ONE dialect group; a word
// shared by two (شو: Emirati and Levantine; مش: Egyptian and Levantine; ليش) is left out, so a marker never misleads.
const MARK: Record<'egyptian' | 'levantine' | 'gulf', RegExp> = {
  egyptian: new RegExp('(^|\\s)(' + ['عايز', 'عاوز', 'عايزه', 'عاوزه', 'عايزين', 'ازاي', 'دلوقتي', 'كده', 'كدا', 'بتاع', 'بتاعي', 'بتاعت', 'فين', 'امتي', 'مفيش', 'معرفش', 'اوي', 'حضرتك', 'ده', 'دي'].join('|') + ')(\\s|$)', 'g'),
  levantine: new RegExp('(^|\\s)(' + ['بدي', 'بدنا', 'بدك', 'هيك', 'هلق', 'منيح', 'زغير', 'هيدا', 'هيدي', 'هاد', 'مبارح', 'فيكن', 'بعرف', 'عم بفكر', 'عم فكر'].join('|') + ')(\\s|$)', 'g'),
  gulf: new RegExp('(^|\\s)(' + ['ابي', 'ابغي', 'ابغا', 'نبي', 'تبي', 'يبي', 'وايد', 'شلون', 'اشلون', 'شنو', 'الحين', 'زين', 'مدري', 'جذي', 'هني', 'مب', 'حقي', 'يبيله'].join('|') + ')(\\s|$)', 'g'),
};
// a Latin word with a digit standing for an Arabic letter (3aref, ba3ref, 7ammam); a measurement or an ordinal is not one
const ARABIZI_WORD = /\b[a-z]*[235789][a-z]+\b|\b[a-z]{2,}[235789]\b/gi;
const NOT_ARABIZI = /^\d+(mm|cm|m|kg|ft|in|sqm|sqft|x|st|nd|rd|th|kw|hp|ton|tons|pcs|pc|l|ltr)$/i;
const arabiziWordsIn = (s: string) => (s.match(ARABIZI_WORD) || []).filter((w) => !NOT_ARABIZI.test(w) && /[a-z]{2,}/i.test(w.replace(/\d/g, ''))).length;
const ARABIZI_MARK: Record<'egyptian' | 'levantine' | 'gulf', RegExp> = {
  egyptian: /\b(3a[yw]ez|3ayz|ezay|ezzay|delwa2ty|dilwa2ti|keda|kda|ma3rafsh|feen|mafeesh|awi|bta3)\b/gi,
  levantine: /\b(badd?i|bade|badna|hek|halla2|kteer|ktir|mnih|ba3ref|ba3rif|zgheer|hayda)\b/gi,
  gulf: /\b(abi|abgha|ab8a|shlon|wayed|wayid|al7een|alhin|zain|madri|shino|shno)\b/gi,
};
const count = (re: RegExp, s: string) => (s.match(re) || []).length;
/** The dialect and script of the customer's own messages (theirs only, never our replies). null: nothing to read. */
export function dialectOf(customerTexts: string[]): { dialect: Dialect; script: Script; scores: Record<string, number> } | null {
  const all = customerTexts.map((t) => String(t || '')).join('\n');
  const arabic = (all.match(/[؀-ۿ]/g) || []).length;
  const latin = (all.match(/[A-Za-z]/g) || []).length;
  if (!arabic && !latin) return null;
  const arabiziWords = arabiziWordsIn(all);
  const n = ' ' + arNorm(all).replace(/\s/g, '  ') + ' ';
  const scores: Record<string, number> = { egyptian: 0, levantine: 0, gulf: 0 };
  for (const d of ['egyptian', 'levantine', 'gulf'] as const) scores[d] = count(MARK[d], n) + count(ARABIZI_MARK[d], all);
  const isArabizi = latin > arabic && (arabiziWords >= 2 || (arabiziWords >= 1 && Object.values(scores).some((x) => x > 0)));
  const script: Script = isArabizi ? 'arabizi' : arabic >= latin ? 'arabic' : arabic > 0 ? 'mixed' : 'latin';
  const ranked = Object.entries(scores).sort((x, y) => y[1] - x[1]);
  const dialect: Dialect = ranked[0][1] > 0 && ranked[0][1] === ranked[1][1] ? 'mixed'
    : ranked[0][1] > 0 ? ranked[0][0] as Dialect
    : script === 'arabizi' ? 'arabizi' : script === 'arabic' || script === 'mixed' ? 'msa' : 'english';
  return { dialect, script, scores };
}
/** The reply rule for an Arabic reply. A supplier is always answered in English (ruling 1008), so this is never asked
 *  for one. The register is the customer's: their dialect's polite everyday wording when they write one, formal Gulf
 *  Arabic when they write Modern Standard Arabic or the dialect is unclear (founder ledger 1572; ruling 586: professional,
 *  never a literal translation). */
export function arabicRegister(dialect?: Dialect | null): string {
  const named = dialect === 'egyptian' ? 'Egyptian' : dialect === 'levantine' ? 'Levantine (Lebanese/Syrian)' : dialect === 'gulf' ? 'Gulf (Emirati)' : null;
  return named
    ? `Arabic in the customer's own register: they write ${named} Arabic, so answer in polite, professional ${named} Arabic (its everyday words, never slang, jokes or a caricature of it), Western digits`
    : `Arabic in the customer's own register: mirror the dialect they write in (Egyptian, Levantine or Gulf) in polite, professional wording, never slang of your own; formal Gulf Arabic when they write Modern Standard Arabic or the dialect is unclear. Western digits`;
}

// ── WHAT MAY NEVER BE ASKED AGAIN, AND THE STATE AS TEXT ───────────────────────────────────────────────────────────
/** Every key the state holds a value for, and every key the customer said they do not know: never asked again. */
export function blockedKeys(st: Pick<InquiryState, 'specs' | 'unknown' | 'budget'> | null | undefined): Set<string> {
  return new Set([...Object.keys(st?.specs ?? {}), ...Object.keys(st?.unknown ?? {}), ...(st?.budget?.value ? ['budget'] : [])]);
}
/** The state for a prompt: every fact with the message it came from, the does-not-know list, the count. '' when empty. */
export function stateSummary(st: Pick<InquiryState, 'specs' | 'unknown' | 'message_count' | 'budget'> | null | undefined, label: (k: string) => string = (k) => k.replace(/_/g, ' ')): string {
  if (!st) return '';
  const specs = Object.entries(st.specs ?? {}).filter(([k]) => k !== 'service_keys');   // codes for matching, not a fact they said
  const unknown = Object.keys(st.unknown ?? {}).filter((k) => !(k in (st.specs ?? {})) && !(k === 'budget' && st.budget?.value));
  if (!specs.length && !unknown.length && !st.budget?.value) return '';
  const lines = ['THE REQUEST AS OUR SYSTEMS HOLD IT (kept from every message of this conversation; never ask for any of it again):'];
  if (st.budget?.value) lines.push(`- budget: "${String(st.budget.value).slice(0, 120)}"` + (st.budget.turn ? ` (message ${st.budget.turn})` : '')
    + (st.budget.changed_from ? ` (they changed this; earlier "${String(st.budget.changed_from).slice(0, 80)}"; only the latest counts)` : ''));
  for (const [k, v] of specs) lines.push(`- ${label(k)}: "${String(v.value).slice(0, 200)}"` + (v.first_turn ? ` (message ${v.first_turn})` : '')
    + (v.changed_from ? ` (they changed this; earlier "${String(v.changed_from).slice(0, 120)}"; only the latest counts)` : ''));
  if (unknown.length) lines.push('THEY SAID THEY DO NOT KNOW (never ask again; it is settled with them later or at the site visit): ' + unknown.map(label).join(', '));
  return lines.join('\n');
}

/** The patch's language/dialect/script fields from the customer's own messages; {} when nothing can be read. */
export function registerPatch(customerTexts: string[], lang: 'en' | 'ar'): Pick<StatePatch, 'language' | 'dialect' | 'dialect_by' | 'script'> {
  const d = dialectOf(customerTexts);
  return { language: lang, ...(d ? { dialect: d.dialect, dialect_by: 'markers' as const, script: d.script } : {}) };
}

// ── the database: every call answers null rather than throw (the table is applied at merge) ───────────────────────
// deno-lint-ignore no-explicit-any
type Admin = any;
export async function readState(admin: Admin, convKey: string): Promise<InquiryState | null> {
  if (!convKey) return null;
  try {
    const { data, error } = await admin.from('inquiry_state').select('*').eq('conv_key', convKey).maybeSingle();
    return error || !data ? null : data as InquiryState;
  } catch { return null; }
}
export async function mergeState(admin: Admin, convKey: string, surface: Surface, patch: StatePatch): Promise<InquiryState | null> {
  if (!convKey) return null;
  try {
    const { data, error } = await admin.rpc('fn_inquiry_state_merge', { p_conv_key: convKey, p_surface: surface, p_patch: patch });
    return error || !data || typeof data !== 'object' ? null : data as InquiryState;
  } catch { return null; }
}
export async function carryState(admin: Admin, fromKey: string, toKey: string, surface: Surface, intakeId: string | null): Promise<InquiryState | null> {
  try {
    const { data, error } = await admin.rpc('fn_inquiry_state_carry', { p_from_key: fromKey, p_to_key: toKey, p_surface: surface, p_intake_id: intakeId });
    return error || !data || typeof data !== 'object' ? null : data as InquiryState;
  } catch { return null; }
}
/** The customer's newest portal job that has not been carried into a request yet, or null. */
export async function openPortalEpisode(admin: Admin, accountKey: string): Promise<InquiryState | null> {
  if (!accountKey) return null;
  try {
    const { data, error } = await admin.from('inquiry_state').select('*').eq('party_key', accountKey).eq('surface', 'portal_assistant')
      .in('status', ['open', 'converging', 'summarising']).order('updated_at', { ascending: false }).limit(1);
    return error || !Array.isArray(data) || !data.length ? null : data[0] as InquiryState;
  } catch { return null; }
}

/** The portal job's transcript as request-chat turns, each marked as carried (the request reads the whole job). */
export function carriedTurns(transcript: { role: 'user' | 'assistant'; content: string }[], from: number): { role: 'user' | 'assistant'; text: string; carried: 'portal' }[] {
  return transcript.slice(Math.max(0, from)).filter((t) => String(t.content || '').trim())
    .map((t) => ({ role: t.role === 'assistant' ? 'assistant' as const : 'user' as const, text: String(t.content), carried: 'portal' as const }));
}
