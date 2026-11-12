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
// readCase returns null and the reply reads the whole conversation as before.
//
// THE REPLY NEVER WAITS ON THE DECISION (final audit 12 Nov 2026, findings W3 / integration F2; customer_support). Measured on
// production 11 Nov: the same-matter decision is a model call that never took under 4.77 s (p50 8.2-8.7 s, n=37), and the turn
// raced the whole read-and-decide against 4 s, so it lost every time: 0 summaries from 29 WhatsApp replies, 0 promises, and the
// routing finished in the background with nothing to read, so it opened a new case for almost every message (17 cases for 7
// people; one supplier 8 in 12 minutes). Now the work is split at the reply:
//   BEFORE the reply, readCase: ONE database read (fn_support_open_cases), no model. The reply works from the case the message
//     belongs to by code: the open case it names, else the newest open case (the one fn_support_touch attached it to).
//   AFTER the reply, settleExchange (kept alive past the response): the same-matter decision, with this exchange's reply to read,
//     the routing, and the summary through the versioned writer, retried when it fails. Code decides where code can tell (no open
//     case; a named case; the conversation's case has no summary yet, so there is nothing to compare a new matter against), so
//     the model is asked only when there is a recorded matter to compare with. One open case per matter.
// prevented by: _shared/support_case_memory.test.ts

import type { ThinkDeps, Turn } from './think.ts';
import { think } from './think.ts';
import { surfaceEffort } from './effort_policy.ts';
import { dueFrom, recordedPromises, stampPromises } from './case_promises.ts';

/** Turns of the chosen case a reply reads verbatim, beside the case summary. */
export const CASE_TURNS = 6;
export const SUMMARY_CLASS = 'case_summary';
export const CASE_SURFACE = 'support.case_match';
const CASE_REF = /\bQD-[A-Z0-9-]{3,}\b/gi;

// kind and due_at (11 Nov 2026, the promise ledger): kind is the model's reading of what the promise is about ('quotes' when
// it is to deliver quotations, the one kind code can see kept); due_at is code's (case_promises.ts stampPromises)
export interface CaseSummary { asked: string; said_or_did: string; promised: { what: string; by: string | null; kind?: 'quotes' | 'other'; due_at?: string | null }[]; open: string[] }
export interface OpenCase { case_ref: string; title: string | null; summary_text: string | null; summary_version: number; status?: string; last_activity_at?: string;
  /** when the case last moved before the newest message (a_returning_person_is_asked_about_their_quiet_case_not_given_a_new_one.sql) */
  prior_activity_at?: string | null }
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
      + (m.confirm.title ? ` (${m.confirm.title})` : '') + '. If the message is plainly about something else, answer it as a new matter and do not '
      + 'mention the case. Otherwise do not assume either way: ask ONE short question that names the case by its subject '
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

// NOT A PROMISE (re-check of 12 Nov 2026, R8): 7 ledger rows from 19 exchanges, none a commitment a person could keep, each due in
// 48 hours: "I will answer it straight away" (the welcome menu), "we will let you know the moment it opens", "I will send him the
// link" (after "Reply REGISTER and"), "ننبهكم فور وصول كل عرض". Our own words are read: a condition, an event we do not control,
// or an answer given at once is not a dated promise.
const CONDITIONAL = /\b(?:if|once|when|whenever|as soon as|the moment|as each|after you|reply \w+ and|send \w+ and)\b|\b(?:straight away|right away|immediately|right now|at once)\b|(?:^|\s)(?:إذا|إن|عندما|حين|فور|فورًا|حال|بمجرد|متى|لحظة)(?:\s|$)/i;
export const notADatedPromise = (what: string) => CONDITIONAL.test(String(what || ''));

/** CODE checks the model's summary. Shape and length are enforced; a promise or a date nobody stated is dropped. */
export function checkSummary(raw: unknown, ctx: { ourReply: string; previous?: CaseSummary | null; previousText?: string }): CaseSummary | null {
  // deno-lint-ignore no-explicit-any
  const j = raw as any;
  if (!j || typeof j !== 'object' || typeof j.asked !== 'string' || typeof j.said_or_did !== 'string') return null;
  // OUR WORDS ONLY (final audit 12 Nov 2026, integration F12): this compared with the whole previous summary, whose ASKED line
  // carries what the PERSON said, so "you promised a refund of AED 500 by Friday" passed as our promise on the next exchange. A
  // promise is ours when our reply states it, or the summary had already recorded it under WE PROMISED.
  const said = ctx.ourReply + '\n' + [...recordedPromises(ctx.previousText), ...(ctx.previous?.promised ?? [])].map((p) => p.what + ' ' + (p.by ?? '')).join('\n');
  const promised = (Array.isArray(j.promised) ? j.promised : []).slice(0, 8)
    .map((p: unknown) => (typeof p === 'string' ? { what: p, by: null } : p as { what?: unknown; by?: unknown }))
    .map((p: { what?: unknown; by?: unknown; kind?: unknown }) => ({ what: clip(p.what, 200), by: p.by == null || p.by === '' ? null : clip(p.by, 60), kind: p.kind }))
    .filter((p: { what: string }) => p.what && stated(p.what, said))
    .map((p: { what: string; by: string | null }) => ({ ...p, by: p.by && said.toLowerCase().includes(p.by.toLowerCase()) ? p.by : null }))
    // a promise WITH A DATE is kept, whatever else it says ("call the supplier right away and update you by 6 pm", "come back to
    // you by Sunday if they agree": review of branch B); without one, a condition, an event or an immediate answer is not a promise
    .filter((p: { what: string; by: string | null }) => p.by || dueFrom(p.what, new Date()) || !notADatedPromise(p.what))
    // the kind is one of two words, or 'other' (a model's free text never reaches the ledger as a kind)
    .map((p: { what: string; by: string | null; kind?: unknown }) => ({ what: p.what, by: p.by, kind: p.kind === 'quotes' ? 'quotes' as const : 'other' as const }));
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
    // re-check of 12 Nov 2026 (R7): 3 cases for one supplier's seven general questions about their own account, and 2 for one
    // air-conditioning job. A case is a MATTER, not a question: the same job, the same account or registration, the same request.
    { id: 'new', meaning: 'a different matter from every case above: another job, another request, or another person\'s business. '
      + 'A further question about the same job, the same request, or their own account, registration, fees or profile is NOT a new matter' },
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

/** Who the case belongs to: the identity the profile resolver matches (a customer id, a lead id, an e-mail or a phone). */
export interface CaseWho { audience: 'customer' | 'supplier' | 'visitor'; partyId?: string | null; email?: string | null; phone?: string | null }
/** What readCase found: the person's profile, their open cases (newest first), and the case the reply reads (null: no open case). */
export interface CaseRead { profile: number; cases: OpenCase[]; memory: CaseMemory | null }

/** The person's open cases, read once (fn_support_open_cases). null = the read failed or the SQL is absent. */
export async function openCases(deps: ThinkDeps, who: CaseWho): Promise<{ profile: number; cases: OpenCase[] } | null> {
  try {
    const { data, error } = await deps.rpc('fn_support_open_cases', { p_party_kind: who.audience === 'visitor' ? 'unknown' : who.audience,
      p_party_id: who.partyId ?? null, p_email: who.email ?? null, p_phone: who.phone ?? null });
    // deno-lint-ignore no-explicit-any
    const d = data as any;
    if (error || !d?.profile) return null;
    return { profile: Number(d.profile), cases: (Array.isArray(d.cases) ? d.cases : []) as OpenCase[] };
  } catch (_e) { return null; }
}

/** BEFORE a reply, with no model: the case this message belongs to by code, for the reply to work from. The open case the
 *  message names, else the newest open case (fn_support_touch attached the message to it on arrival). A newest case quiet for
 *  CONFIRM_AFTER_DAYS is handed over as a 'confirm': the reply asks whether the message is about it unless it plainly is not. */
export async function readCase(deps: ThinkDeps, o: CaseWho & { message: string; now?: number }): Promise<CaseRead | null> {
  const open = await openCases(deps, o);
  if (!open) return null;
  const { profile, cases } = open;
  if (!cases.length) return { profile, cases, memory: null };
  const named = namedCase(o.message, cases);
  // SEVERAL RECORDED MATTERS, NONE NAMED: no single case is handed to the reply (review of 12 Nov 2026). The newest open case is
  // the one fn_support_touch attached the message to, not the matter it is about: once a second matter opened, a question about
  // the first was answered from the second's summary and only six turns. Then the reply reads the whole conversation, as before
  // cases existed; the step after the reply still decides which case the exchange belongs to.
  if (!named && cases.filter((x) => (x.summary_version ?? 0) > 0 && String(x.summary_text ?? '').trim()).length > 1) return { profile, cases, memory: null };
  const c = cases.find((x) => x.case_ref === named) ?? cases[0];
  // how long it was quiet BEFORE this message: fn_support_touch has just moved last_activity_at to now (prior_activity_at keeps
  // the earlier time once the SQL is applied; before that, an idle case was closed on arrival and never reaches here)
  const quietMs = (o.now ?? Date.now()) - (Date.parse(String(c.prior_activity_at ?? c.last_activity_at ?? '')) || Number.NaN);
  const days = Math.floor(quietMs / 86_400_000);
  if (!named && Number.isFinite(quietMs) && days >= CONFIRM_AFTER_DAYS && (c.title || c.summary_text)) {
    return { profile, cases, memory: { ref: c.case_ref, summaryText: c.summary_text || clip(c.title, 160) || c.case_ref, version: c.summary_version ?? 0,
      profile, confirm: { title: c.title ? clip(c.title, 80) : null, days } } };
  }
  return { profile, cases, memory: { ref: c.case_ref, summaryText: c.summary_text ?? '', version: c.summary_version ?? 0, profile } };
}

/** AFTER the reply: same matter or a new one. Code where code can tell; otherwise the model (chooseCase) compares the message
 *  with the recorded matters. An unsure model, or one that fails, continues the newest open case (never a new case per message). */
export async function decideAfterReply(deps: ThinkDeps, o: { message: string; cases: readonly OpenCase[]; audience: CaseWho['audience']; dedupeKey?: string; now?: number }): Promise<Choice> {
  if (!o.cases.length) return { choice: 'new', by: 'code' };
  const named = namedCase(o.message, o.cases);
  if (named) return { choice: 'continue', case_ref: named, by: 'code' };
  // the conversation's own case has nothing recorded yet: there is no matter to compare a "new matter" against, so the message
  // continues it (on 11 Nov the model, shown only "Whatsapp: Hi", called nearly every message a new matter)
  const newest = o.cases[0];
  if (!(newest.summary_version > 0) || !String(newest.summary_text ?? '').trim()) return { choice: 'continue', case_ref: newest.case_ref, by: 'code' };
  // their only case holds ONE exchange and it was minutes ago: that exchange is how the conversation opened ("Hi", the welcome
  // menu), not a matter to be told apart from (the audit's conversations opened "Hi", then the job), so the job continues it
  const moved = Date.parse(String(newest.last_activity_at ?? ''));
  if (o.cases.length === 1 && newest.summary_version === 1 && Number.isFinite(moved) && (o.now ?? Date.now()) - moved < OPENER_MS) {
    return { choice: 'continue', case_ref: newest.case_ref, by: 'code' };
  }
  const pick = await chooseCase(deps, o);
  // after the reply there is nobody to ask: a 'confirm' (unsure after a long gap) was already put to them by the reply
  return pick.choice === 'confirm' ? { choice: 'continue', case_ref: pick.case_ref, by: pick.by } : pick;
}

/** The last exchange of `recent` (its last THEM line and the US line after it), at most 1,000 characters. */
export function previousExchange(recent: string | undefined): string {
  const lines = String(recent ?? '').split('\n').filter((l) => /^(THEM|US): /.test(l));
  const i = lines.map((l) => l.startsWith('THEM: ')).lastIndexOf(true);
  return (i < 0 ? lines.slice(-1) : lines.slice(i, i + 2)).join('\n').slice(0, 1000);
}

/** A case with one recorded exchange that moved this recently is the conversation's opening, continued by code. */
export const OPENER_MS = 30 * 60_000;
/** How many times the summary is written before the failure is raised (a stale version is re-read in between). */
export const SUMMARY_TRIES = 3;

/** AFTER the reply, off the reply's path: decide, route, and write the summary, retried when it fails. Never throws.
 *  `recent` is the turns before this exchange; only the last exchange of it is read (previousExchange), so an exchange whose own
 *  summary failed is caught up on the next one, and the summary never re-reads the whole case (re-check R6). */
export async function settleExchange(deps: ThinkDeps, o: CaseWho & {
  channel: string; message: string; ourReply: string; lang?: string; seat?: string; dedupeKey?: string; recent?: string;
  subject?: Record<string, unknown>; now?: number;
}): Promise<{ ok: boolean; reason?: string; ref?: string; choice?: Choice['choice']; by?: string; tries?: number }> {
  // EVERY FAILURE IS SEEN (review of 12 Nov 2026: a failed read or route returned silently); the catch-up step
  // (resilience_ping caseCatchup) writes a summary that is owed and missing, so a failure here delays it, never loses it
  const raise = async (key: string, title: string, evidence: Record<string, unknown>) => {
    try {
      await deps.rpc('fn_it_engineer_finding_upsert', { p_issue_key: key, p_title: title, p_where: 'support_case_memory.ts settleExchange (' + o.channel + ')',
        p_blast: 'customer_facing', p_affected: 1, p_evidence: { channel: o.channel, ...evidence }, p_ruled_out: [], p_undetermined: [], p_raised_by: 'customer_support' });
    } catch (_e) { /* the turn was answered; the finding is best effort */ }
  };
  try {
    const open = await openCases(deps, o);
    if (!open) { await raise('support_case:not_read_after_reply', 'The open cases could not be read after a reply, so the exchange was not recorded on its case yet', {}); return { ok: false, reason: 'no case read' }; }
    let pick = await decideAfterReply(deps, { message: o.message, cases: open.cases, audience: o.audience, dedupeKey: o.dedupeKey, now: o.now });
    if (pick.choice === 'new') {
      // TWO MESSAGES ON ONE NEW MATTER (review probe): the decision takes seconds, and another turn of the same person may have
      // opened the new case meanwhile. Read again just before opening one: a case that appeared since is continued instead.
      const again = await openCases(deps, o);
      const since = again?.cases.find((c) => !open.cases.some((x) => x.case_ref === c.case_ref));
      if (since) pick = { choice: 'continue', case_ref: since.case_ref, by: 'code' };
    }
    const routed = await deps.rpc('fn_support_case_route', { p_profile: open.profile, p_choice: pick.choice === 'new' ? 'new' : 'continue',
      p_case_ref: pick.choice !== 'new' ? pick.case_ref : null, p_channel: o.channel, p_text: o.message.slice(0, 4000), p_lang: o.lang ?? null });
    // deno-lint-ignore no-explicit-any
    const ref = (routed.data as any)?.case_ref as string | undefined;
    if (routed.error || !ref) {
      const reason = 'route: ' + String(routed.error?.message ?? (routed.data as { reason?: string } | null)?.reason ?? 'no case');
      await raise('support_case:not_routed', 'An exchange could not be routed to a case after the reply', { choice: pick.choice, reason: reason.slice(0, 200) });
      return { ok: false, reason, choice: pick.choice };
    }
    let c = open.cases.find((x) => x.case_ref === ref);
    let last: { ok: boolean; reason?: string } = { ok: false };
    for (let i = 1; i <= SUMMARY_TRIES; i++) {
      const memory: CaseMemory = { ref, summaryText: c?.summary_text ?? '', version: c?.summary_version ?? 0, profile: open.profile };
      // the previous summary, this exchange, and the ONE exchange before it (re-check of 12 Nov 2026, R6; review of branch B): never
      // the whole case, and enough that an exchange whose own summary failed is still recorded by the next one
      last = await summariseExchange(deps, { memory, theirMessage: o.message, ourReply: o.ourReply, seat: o.seat, recent: previousExchange(o.recent),
        ...(o.subject ? { subject: o.subject } : {}) });
      if (last.ok) return { ok: true, ref, choice: pick.choice, by: pick.by, tries: i };
      // another exchange of the same person wrote first: read the newer summary and write on top of it
      if (last.reason === 'stale') c = (await openCases(deps, o))?.cases.find((x) => x.case_ref === ref) ?? c;
    }
    // still not written: the it_engineer sees it, and the catch-up step writes it within its next beat
    await raise('support_case:summary_not_written', 'A case summary could not be written after ' + SUMMARY_TRIES + ' tries; the catch-up step owes it',
      { case_ref: ref, reason: String(last.reason ?? '').slice(0, 200) });
    return { ok: false, reason: last.reason ?? 'not written', ref, choice: pick.choice, by: pick.by, tries: SUMMARY_TRIES };
  } catch (e) {
    const reason = String((e as Error)?.message ?? e).slice(0, 200);
    await raise('support_case:after_reply_failed', 'The case step after a reply failed', { reason });
    return { ok: false, reason };
  }
}

/** THE CATCH-UP (review of 12 Nov 2026, SHOULD FIX 5). The step after a reply lives in the turn's worker (waitUntil); a worker
 *  killed before it ends loses that summary. Every 15 minutes (resilience_ping caseCatchup, kicked detached) the cases whose last
 *  message is newer than their summary and was answered on WhatsApp more than 5 minutes ago
 *  (fn_support_case_summaries_owed, a_case_summary_owed_after_a_reply_is_written_by_the_next_beat.sql) are summarised from the
 *  conversation itself. Other doors: the in-turn retries and a finding (their transcripts live in four different tables). */
export async function catchUpOwedSummaries(deps: ThinkDeps, readTurns: (phoneTail: string) => Promise<{ inbound: string; reply: string }[] | null>,
  limit = 3): Promise<{ ok: boolean; owed: number; written: number; failed: number; reason?: string }> {
  const { data, error } = await deps.rpc('fn_support_case_summaries_owed', { p_limit: limit });
  if (error) return { ok: false, owed: 0, written: 0, failed: 0, reason: String(error.message ?? error).slice(0, 200) };
  // deno-lint-ignore no-explicit-any
  const owed = (Array.isArray(data) ? data : []) as any[];
  let written = 0, failed = 0;
  for (const c of owed) {
    const turns = (await readTurns(String(c.phone_tail ?? '')))?.filter((x) => x.inbound.trim() && x.reply.trim()) ?? [];
    const last = turns[turns.length - 1];
    if (!last) continue;   // nothing answered yet: not owed
    const recent = turns.slice(-CASE_TURNS - 1, -1).map((x) => 'THEM: ' + clip(x.inbound, 400) + '\nUS: ' + clip(x.reply, 400)).join('\n');
    const r = await summariseExchange(deps, { memory: { ref: String(c.case_ref), summaryText: String(c.summary_text ?? ''), version: Number(c.summary_version ?? 0), profile: Number(c.profile ?? 0) },
      theirMessage: last.inbound, ourReply: last.reply, recent, seat: 'customer_support' });
    if (r.ok) { written++; continue; }
    failed++;
    try {
      await deps.rpc('fn_it_engineer_finding_upsert', { p_issue_key: 'support_case:summary_not_caught_up', p_title: 'A case summary owed after a reply could not be written by the catch-up step',
        p_where: 'resilience_ping caseCatchup (support_case_memory.ts catchUpOwedSummaries)', p_blast: 'customer_facing', p_affected: 1,
        p_evidence: { case_ref: c.case_ref, reason: String(r.reason ?? '').slice(0, 200) }, p_ruled_out: [], p_undetermined: [], p_raised_by: 'customer_support' });
    } catch (_e) { /* counted in the step's result */ }
  }
  return { ok: failed === 0, owed: owed.length, written, failed };
}

export const SUMMARY_SYSTEM = 'You keep the case record of a customer support agency. Rewrite the case summary after the exchange below. '
  + 'Return ONLY a JSON object: {"title": one line naming the matter, "asked": what the person wants, in one or two sentences, '
  + '"said_or_did": what we told them or did, in one or two sentences, "promised": [{"what": a promise WE made, in our words, '
  + '"by": the date or time we gave, in our words, or null, "kind": "quotes" when the promise is to send or deliver quotations, '
  + 'otherwise "other"}], "open": [each thing still to be done or answered]}. Keep every earlier promise, in the words it was recorded in, '
  + 'that is not fulfilled. Record only promises our reply or the earlier summary states; never infer one. A promise is something WE will do '
  + 'later: an answer given in the reply itself, a condition (if, when or once they do something) and an event we do not control (the moment '
  + 'a trade opens, as each quote arrives) are not promises. Plain facts, no advice. The whole summary stays under 150 words: keep what is '
  + 'still open, drop what is settled.';

/** After an exchange: one cheap call rewrites the summary, code checks it, the database keeps every version. Never throws. */
export async function summariseExchange(deps: ThinkDeps, o: {
  memory: CaseMemory; previous?: CaseSummary | null; theirMessage: string; ourReply: string; seat?: string; subject?: Record<string, unknown>;
  /** the turns just before this exchange (oldest first), so an exchange whose summary was lost is still recorded */
  recent?: string;
}): Promise<{ ok: boolean; reason?: string }> {
  try {
    const input = 'THE SUMMARY SO FAR:\n' + (o.memory.summaryText || '(none: this is the first exchange of the case)')
      + (o.recent?.trim() ? '\n\nTHE TURNS JUST BEFORE THIS EXCHANGE (context; record anything the summary so far is missing):\n' + o.recent.slice(0, 3000) : '')
      // BOUNDED (re-check of 12 Nov 2026, R6: 6.5 s on the first exchange, 43.1 s by the sixth, 4 of 22 at the 47 s wall): the
      // previous summary (at most 2,000 characters, renderSummary) and this exchange, each side cut at 1,500 characters
      + '\n\nTHEIR MESSAGE:\n' + o.theirMessage.slice(0, 1500) + '\n\nOUR REPLY:\n' + o.ourReply.slice(0, 1500);
    const r = await deps.llm('synthesise', SUMMARY_SYSTEM, input, { taskClass: SUMMARY_CLASS, seat: 'customer_support' as never, max: 500,
      internal: true, ...(o.subject ? { subject: o.subject } : {}) });
    const text = String(r.content ?? '').replace(/^```(?:json)?\s*|\s*```$/g, '');
    let raw: unknown = null; try { raw = JSON.parse(text); } catch (_e) { return { ok: false, reason: 'not json' }; }
    const checked = checkSummary(raw, { ourReply: o.ourReply, previous: o.previous ?? null, previousText: o.memory.summaryText });
    if (!checked) return { ok: false, reason: 'bad shape' };
    // each stated promise with its due time, read by code (case_promises.ts); the writer records each one in the ledger
    const s = stampPromises(checked, { previousText: o.memory.summaryText });
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
