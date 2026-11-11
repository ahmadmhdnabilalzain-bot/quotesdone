// _shared/support_case_memory.ts — every conversation is a case, and a reply works from the case's summary
// (customer_support's record, built by it_engineer, 11 Nov 2026).
//
// Founder ruling 1635 (11 Nov 2026): "Every conversation is a case with a case number. After each exchange the agent
// records a summary of the case. When the same customer or supplier writes again, the agent decides whether it is the same
// matter (then it works from that case's summary instead of rereading the whole chat) or a different matter (then it
// opens a new case)." Ruling 1631: the history is read before every reply, economically. Ruling 1634: nothing is deleted.
//
// The case itself already existed (public.support_case, one person across channels through support_customer_profile;
// fn_support_touch attaches each message to the person's newest open case). What this adds, with
// scripts/sql/every_support_case_keeps_a_summary_and_the_reply_reads_it.sql:
//   1. chooseCase: given ONLY the person's open cases (number, title, summary), continue one or open a new one. Code first
//      (no open case: new; the message names an open case's number: that case), then one lean medium-effort decision.
//   2. caseBlock + CASE_TURNS: the reply gets the case summary inside its cached prefix and the last CASE_TURNS turns
//      verbatim, instead of the whole transcript (ai_reply.ts `caseMemory`).
//   3. summariseExchange: after an exchange, one cheap call (class case_summary: GPT-6 Luna Pro, high effort) rewrites the
//      structured summary; CODE then checks it: a promise or a date that our reply and the previous summary never stated is
//      dropped, so a model cannot record a promise we did not make. Written through fn_support_case_summary_write, which
//      refuses a stale version.
// Every step degrades to today's behaviour: until the SQL is applied (fn_support_open_cases absent), or when a read fails,
// caseMemoryFor returns null and the reply reads the whole conversation as before.
// prevented by: _shared/support_case_memory.test.ts

import type { ThinkDeps, Turn } from './think.ts';
import { think } from './think.ts';
import { surfaceEffort } from './effort_policy.ts';

/** Turns of the chosen case a reply reads verbatim, beside the case summary. */
export const CASE_TURNS = 6;
export const SUMMARY_CLASS = 'case_summary';
export const CASE_SURFACE = 'support.case_match';
const CASE_REF = /\bQD-[A-Z0-9-]{3,}\b/gi;

export interface CaseSummary { asked: string; said_or_did: string; promised: { what: string; by: string | null }[]; open: string[] }
export interface OpenCase { case_ref: string; title: string | null; summary_text: string | null; summary_version: number; status?: string; last_activity_at?: string }
export interface CaseMemory { ref: string; summaryText: string; version: number; profile: number; confirm?: { title: string | null; days: number } }
// 'confirm' (it_engineer, 11 Nov 2026): the person writes after a long gap and the router cannot tell whether it is the same
// matter. The reply then asks ONE short question naming the case ("Is this about your aluminium windows request QD-…?")
// instead of guessing either way; their answer decides on the next turn (a named number or a clear new matter).
export type Choice = { choice: 'continue'; case_ref: string; by: 'code' | 'model' } | { choice: 'new'; by: 'code' | 'model' | 'held' }
  | { choice: 'confirm'; case_ref: string; by: 'code' | 'model'; days: number };
/** A gap longer than this since the case last moved, with the router unsure, is asked about rather than assumed. */
export const CONFIRM_AFTER_DAYS = 7;

const clip = (s: unknown, n: number) => String(s ?? '').replace(/\s+/g, ' ').trim().slice(0, n);

/** The summary as the reply reads it: short, in a fixed order, promises with their dates. */
export function renderSummary(s: CaseSummary): string {
  const promised = s.promised.length ? s.promised.map((p) => '- ' + p.what + (p.by ? ' (by ' + p.by + ')' : '')).join('\n') : '- nothing';
  const open = s.open.length ? s.open.map((o) => '- ' + o).join('\n') : '- nothing';
  return ['ASKED: ' + (s.asked || '-'), 'WE SAID OR DID: ' + (s.said_or_did || '-'), 'WE PROMISED:\n' + promised, 'STILL OPEN:\n' + open].join('\n').slice(0, 2000);
}

/** The block the reply's cached prefix carries: the case number, and its summary. */
export function caseBlock(m: Pick<CaseMemory, 'ref' | 'summaryText'> & { confirm?: CaseMemory['confirm'] }): string {
  if (m.confirm) {
    return `THE PERSON WRITES AGAIN AFTER ${m.confirm.days} DAYS, and it is not clear whether this message is about case ${m.ref}`
      + (m.confirm.title ? ` (${m.confirm.title})` : '') + '. Do not assume either way: ask ONE short question that names the case by its subject '
      + `and number (for example: "Is this about your ${m.confirm.title || 'earlier'} request ${m.ref}?"), and do not answer as if it were that case `
      + 'until they say. What the case recorded, for that question only:\n' + m.summaryText;
  }
  return `THIS CASE (${m.ref}), as recorded after the last exchange. Work from it: never ask again for what it shows was given, `
    + 'never repeat what it shows we already said, and keep every promise it lists. The last few turns follow as messages.\n'
    + m.summaryText;
}

const words = (s: string) => new Set(String(s).toLowerCase().match(/[\p{L}\p{N}]{3,}/gu) ?? []);
/** A promise is ours only when most of its words appear in what we said (this reply, or the promises already recorded). */
function stated(what: string, said: string): boolean {
  const w = [...words(what)];
  if (!w.length) return false;
  const have = words(said);
  return w.filter((x) => have.has(x)).length / w.length >= 0.6;
}

/** CODE checks the model's summary. Shape and length are enforced; a promise or a date nobody stated is dropped. */
export function checkSummary(raw: unknown, ctx: { ourReply: string; previous?: CaseSummary | null; previousText?: string }): CaseSummary | null {
  // deno-lint-ignore no-explicit-any
  const j = raw as any;
  if (!j || typeof j !== 'object' || typeof j.asked !== 'string' || typeof j.said_or_did !== 'string') return null;
  const said = ctx.ourReply + '\n' + (ctx.previousText ?? '') + '\n' + (ctx.previous?.promised ?? []).map((p) => p.what + ' ' + (p.by ?? '')).join('\n');
  const promised = (Array.isArray(j.promised) ? j.promised : []).slice(0, 8)
    .map((p: unknown) => (typeof p === 'string' ? { what: p, by: null } : p as { what?: unknown; by?: unknown }))
    .map((p: { what?: unknown; by?: unknown }) => ({ what: clip(p.what, 200), by: p.by == null || p.by === '' ? null : clip(p.by, 60) }))
    .filter((p: { what: string }) => p.what && stated(p.what, said))
    .map((p: { what: string; by: string | null }) => ({ ...p, by: p.by && said.toLowerCase().includes(p.by.toLowerCase()) ? p.by : null }));
  const open = (Array.isArray(j.open) ? j.open : []).slice(0, 8).map((o: unknown) => clip(o, 200)).filter(Boolean);
  return { asked: clip(j.asked, 400), said_or_did: clip(j.said_or_did, 400), promised, open };
}

/** The open-case number a message names, when it is one of this person's. */
export function namedCase(message: string, cases: readonly OpenCase[]): string | null {
  const named = (String(message).match(CASE_REF) ?? []).map((r) => r.toUpperCase());
  return cases.find((c) => named.includes(c.case_ref.toUpperCase()))?.case_ref ?? null;
}

/** Same matter or a new one. Code where code can tell; otherwise one lean decision over the open cases only. */
export async function chooseCase(deps: ThinkDeps, o: { message: string; cases: readonly OpenCase[]; audience: 'customer' | 'supplier' | 'visitor'; dedupeKey?: string; now?: number }): Promise<Choice> {
  if (!o.cases.length) return { choice: 'new', by: 'code' };
  const named = namedCase(o.message, o.cases);
  if (named) return { choice: 'continue', case_ref: named, by: 'code' };
  const options = [
    ...o.cases.map((c) => ({ id: 'continue:' + c.case_ref, meaning: `the same matter as case ${c.case_ref}: ${clip(c.title, 160)}. ${clip(c.summary_text, 600)}` })),
    { id: 'new', meaning: 'a different matter from every case above: a new case' },
    { id: 'unsure', meaning: 'the message alone does not say whether it is one of the cases above or a new matter' },
  ];
  // NOT SURE: the newest open case, as fn_support_touch has always done, unless it has been quiet for CONFIRM_AFTER_DAYS: then ask.
  const unsure = (by: 'code' | 'model'): Choice => {
    const c = o.cases[0];
    const quietMs = (o.now ?? Date.now()) - (Date.parse(String(c.last_activity_at ?? '')) || Number.NaN);
    const days = Math.floor(quietMs / 86_400_000);
    return Number.isFinite(quietMs) && days >= CONFIRM_AFTER_DAYS ? { choice: 'confirm', case_ref: c.case_ref, by, days } : { choice: 'continue', case_ref: c.case_ref, by };
  };
  try {
    const r = await think(deps, {
      lean: true, seat: 'customer_support', surface: CASE_SURFACE, question: o.message.slice(0, 2000), dedupeKey: o.dedupeKey,
      context: { audience: o.audience }, decision: { name: 'case_match', options },
      plan: { steps: [] }, effort: surfaceEffort(CASE_SURFACE), queueWhenHeld: false,
    } as never);
    const choice = r.status === 'answered' ? r.decision?.choice ?? null : null;
    const ref = choice?.startsWith('continue:') ? choice.slice('continue:'.length) : null;
    if (ref && o.cases.some((c) => c.case_ref === ref)) return { choice: 'continue', case_ref: ref, by: 'model' };
    if (choice === 'new') return { choice: 'new', by: 'model' };
  } catch (_e) { /* held below */ }
  // 'unsure', not answered, or an answer naming no case of theirs
  return unsure('model');
}

/** Before a reply: the person's open cases, the decision, and the case the reply works from. null = read the whole chat. */
export async function caseMemoryFor(deps: ThinkDeps, o: {
  message: string; channel: string; audience: 'customer' | 'supplier' | 'visitor'; partyId?: string | null; email?: string | null; phone?: string | null;
  lang?: string; dedupeKey?: string;
}): Promise<CaseMemory | null> {
  try {
    const { data, error } = await deps.rpc('fn_support_open_cases', { p_party_kind: o.audience === 'visitor' ? 'unknown' : o.audience,
      p_party_id: o.partyId ?? null, p_email: o.email ?? null, p_phone: o.phone ?? null });
    // deno-lint-ignore no-explicit-any
    const d = data as any;
    if (error || !d?.profile) return null;
    const cases = (Array.isArray(d.cases) ? d.cases : []) as OpenCase[];
    const pick = await chooseCase(deps, { message: o.message, cases, audience: o.audience, dedupeKey: o.dedupeKey });
    // a 'confirm' is filed on the case it asks about (fn_support_case_route knows continue and new); the answer re-routes next turn
    const routed = await deps.rpc('fn_support_case_route', { p_profile: d.profile, p_choice: pick.choice === 'new' ? 'new' : 'continue',
      p_case_ref: pick.choice !== 'new' ? pick.case_ref : null, p_channel: o.channel, p_text: o.message.slice(0, 4000), p_lang: o.lang ?? null });
    // deno-lint-ignore no-explicit-any
    const ref = (routed.data as any)?.case_ref as string | undefined;
    if (routed.error || !ref) return null;
    const c = cases.find((x) => x.case_ref === ref);
    if (pick.choice === 'confirm') {
      // the question is asked even before the case has a summary: its title (or number) is what it names
      return { ref, summaryText: c?.summary_text || clip(c?.title, 160) || ref, version: c?.summary_version ?? 0, profile: Number(d.profile),
        confirm: { title: c?.title ? clip(c.title, 80) : null, days: pick.days } };
    }
    return { ref, summaryText: c?.summary_text ?? '', version: c?.summary_version ?? 0, profile: Number(d.profile) };
  } catch (_e) { return null; }
}

export const SUMMARY_SYSTEM = 'You keep the case record of a customer support agency. Rewrite the case summary after the exchange below. '
  + 'Return ONLY a JSON object: {"title": one line naming the matter, "asked": what the person wants, in one or two sentences, '
  + '"said_or_did": what we told them or did, in one or two sentences, "promised": [{"what": a promise WE made, in our words, '
  + '"by": the date or time we gave, or null}], "open": [each thing still to be done or answered]}. Keep every earlier promise '
  + 'that is not fulfilled. Record only promises our reply or the earlier summary states; never infer one. Plain facts, no advice.';

/** After an exchange: one cheap call rewrites the summary, code checks it, the database keeps every version. Never throws. */
export async function summariseExchange(deps: ThinkDeps, o: {
  memory: CaseMemory; previous?: CaseSummary | null; theirMessage: string; ourReply: string; seat?: string; subject?: Record<string, unknown>;
}): Promise<{ ok: boolean; reason?: string }> {
  try {
    const input = 'THE SUMMARY SO FAR:\n' + (o.memory.summaryText || '(none: this is the first exchange of the case)')
      + '\n\nTHEIR MESSAGE:\n' + o.theirMessage.slice(0, 4000) + '\n\nOUR REPLY:\n' + o.ourReply.slice(0, 4000);
    const r = await deps.llm('synthesise', SUMMARY_SYSTEM, input, { taskClass: SUMMARY_CLASS, seat: 'customer_support' as never, max: 700,
      internal: true, ...(o.subject ? { subject: o.subject } : {}) });
    const text = String(r.content ?? '').replace(/^```(?:json)?\s*|\s*```$/g, '');
    let raw: unknown = null; try { raw = JSON.parse(text); } catch (_e) { return { ok: false, reason: 'not json' }; }
    const s = checkSummary(raw, { ourReply: o.ourReply, previous: o.previous ?? null, previousText: o.memory.summaryText });
    if (!s) return { ok: false, reason: 'bad shape' };
    // deno-lint-ignore no-explicit-any
    const title = clip((raw as any)?.title, 160);
    const w = await deps.rpc('fn_support_case_summary_write', { p_case_ref: o.memory.ref, p_expected_version: o.memory.version, p_summary: s,
      p_summary_text: renderSummary(s), p_title: title, p_written_by: o.seat ?? 'customer_support', p_model: r.model ?? null });
    // deno-lint-ignore no-explicit-any
    return w.error ? { ok: false, reason: w.error.message ?? 'write failed' } : { ok: (w.data as any)?.ok === true, reason: (w.data as any)?.reason };
  } catch (e) { return { ok: false, reason: String((e as Error)?.message ?? e).slice(0, 200) }; }
}

/** The last CASE_TURNS turns of the conversation, for a reply that has the case summary. */
export const caseTurns = (conversation: readonly Turn[]) => conversation.slice(-CASE_TURNS);
