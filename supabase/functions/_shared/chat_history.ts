// THE WHOLE CONVERSATION, EVERY TURN (customer_support + sales_engineer, 18 Oct 2026).
//
// The founder chatted about a custom wardrobe in the portal on 14 Oct (assistant_logs 3694-3699). On the SECOND turn the
// reply asked again for the "width and height" he had given one turn earlier, and by the fifth it said "I can't see its
// earlier details here". Three windows cut the conversation, and the portal had none at all:
//   - ChatWidget sent history.slice(-6) and site_assistant sliced -6 again (600 chars each): turn 1 was gone by turn 4;
//   - aiReply (every channel through supportReply) kept the last 8 turns;
//   - sales_engineer 'assist' never read body.history, so every portal turn reached the model with no conversation.
// Founder ruling (18 Oct): NO turn limit, even at 500 messages; every turn stored; the full history to the model; the
// [SUPERSEDED for what a reply reads: ledger 1572 (10 Nov 2026) set the estate's hard cap of 100 messages per conversation
// (inquiry_state.ts MESSAGE_CAP), and a reply with no case summary reads at most those 100 (case_context.ts, wa_inbound/say.ts).
// Every turn is still stored.]
// stable prefix cached. So the transcript is read from assistant_logs by conv_id (the database, not the browser, is the
// record), and fitHistory hands it to the model whole.
//
// Both reply models carry a 1,000,000-token window (model_registry 13 Oct 2026: claude-sonnet-5.5 1,000,000; the
// fallback gemini-3.8-flash 1,048,576). The knowledge brief is ~65k tokens, so HISTORY_BUDGET_CHARS (~500k tokens)
// leaves room for the rest. Only past that — thousands of turns — is anything left out, and then every turn the PERSON
// wrote stays verbatim (their words are where every fact of their job lives), with our newest replies and the earlier
// replies that share words with the message in hand.
// ponytail: past the budget the selection is lexical, not a model-written summary; a summary pass belongs here only if
// a real conversation ever reaches ~2M characters.
// prevented by: _shared/chat_history.test.ts

export type ChatMsg = { role: 'user' | 'assistant'; content: string };

/** ~500k tokens of history; the brief, rules and reply fit beside it in a 1M window. */
export const HISTORY_BUDGET_CHARS = 2_000_000;
/** One stored message is never cut below this (the widget input is 500 chars; a pasted spec can be longer). */
export const MAX_TURN_CHARS = 8_000;

const words = (s: string) => new Set(String(s).toLowerCase().match(/[\p{L}\p{N}]{3,}/gu) ?? []);

/** The model's view of the conversation: everything, unless it exceeds the budget (see the header). Order is kept. */
export function fitHistory(turns: ChatMsg[], message = '', budget = HISTORY_BUDGET_CHARS): ChatMsg[] {
  const all = turns.filter((t) => t && String(t.content || '').trim())
    .map((t) => ({ role: t.role === 'assistant' ? 'assistant' as const : 'user' as const, content: String(t.content).slice(0, MAX_TURN_CHARS) }));
  const size = (xs: ChatMsg[]) => xs.reduce((n, t) => n + t.content.length, 0);
  if (size(all) <= budget) return all;
  const keep = new Set<number>();
  let used = 0;
  // 1. every turn the person wrote, newest first, until (pathologically) even those exceed the budget
  for (let i = all.length - 1; i >= 0; i--) if (all[i].role === 'user' && used + all[i].content.length <= budget) { keep.add(i); used += all[i].content.length; }
  // 2. our replies that share the most words with the message in hand (retrieval of the exact earlier turn), then newest
  const q = words(message);
  const replies = all.map((t, i) => ({ t, i })).filter((x) => x.t.role === 'assistant')
    .map((x) => ({ ...x, hit: [...words(x.t.content)].filter((w) => q.has(w)).length }))
    .sort((a, b) => (b.hit - a.hit) || (b.i - a.i));
  for (const r of replies) if (used + r.t.content.length <= budget) { keep.add(r.i); used += r.t.content.length; }
  return all.filter((_, i) => keep.has(i));
}

/** assistant_logs rows (oldest first) as conversation turns: the person's message, then the reply they were given. */
export function transcriptFromRows(rows: { message?: string | null; reply?: string | null }[]): ChatMsg[] {
  const out: ChatMsg[] = [];
  for (const r of rows ?? []) {
    if (r?.message) out.push({ role: 'user', content: String(r.message) });
    if (r?.reply) out.push({ role: 'assistant', content: String(r.reply) });
  }
  return out;
}

// A LATE ANSWER LANDS UNDER ITS OWN QUESTION, NEVER UNDER THE NEXT ONE (sales_engineer, 17 Nov 2026; founder ledger 1474).
// Measured on production (continuity run b7bdf916, agent_runs 13:12:32Z and 13:13:13Z): portal turn 8 got no answer (every
// model route open-circuit; the turn was not filed for the re-ask), so its assistant_logs row kept reply NULL and
// transcriptFromRows handed the model a question with nothing after it. On turn 9 the model answered BOTH, and the portal
// showed "No, QuotesDone is not legally liable..." (turn 8's answer) under "What would a typical price be for aluminium
// windows for a villa?". Their words stay in the history (they carry the facts of the job); the model is told that message
// was never answered and that this reply answers only the newest one. Model input only: what is stored and what
// assist_history shows are unchanged. A turn the re-ask answers later is answered in its own row, under its own question.
export const UNANSWERED_NOTE = '[No answer to this message reached them. Do not answer it in this reply: answer only their newest MESSAGE, unless that message asks about this one.]';
/** The model's copy of the conversation: a message of theirs with no reply after it is marked as never answered. */
export function markUnanswered(turns: ChatMsg[]): ChatMsg[] {
  return turns.map((t, i) => (t.role !== 'user' || turns[i + 1]?.role === 'assistant'
    // cut so the note survives fitHistory's MAX_TURN_CHARS (an unanswered 9,000-character spec lost its note at the end)
    ? t : { role: 'user' as const, content: String(t.content).slice(0, MAX_TURN_CHARS - UNANSWERED_NOTE.length - 2) + '\n\n' + UNANSWERED_NOTE }));
}

/** Every stored turn of one conversation, oldest first, paged so no row limit can cut it. null when unreadable. */
// deno-lint-ignore no-explicit-any
export async function loadTranscript(admin: any, convId: string): Promise<ChatMsg[] | null> {
  if (!convId) return [];
  const rows: { message: string | null; reply: string | null }[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await admin.from('assistant_logs').select('message,reply').eq('conv_id', convId)
      .order('id', { ascending: true }).range(from, from + 999);
    if (error) return null;
    rows.push(...(data ?? []));
    if (!data || data.length < 1000) break;
  }
  return transcriptFromRows(rows);
}

/** The browser's copy, used only when the database has none yet (the first turn, or a row still being written). */
export function clientHistory(h: unknown): ChatMsg[] {
  return Array.isArray(h) ? h.map((x: any) => ({ role: x?.role === 'assistant' ? 'assistant' as const : 'user' as const, content: String(x?.content ?? '') })) : [];
}

/** A conversation id the caller may use: letters, digits and dashes, 8-64 long. */
export const convIdOf = (v: unknown): string => { const s = String(v ?? '').replace(/[^a-zA-Z0-9-]/g, '').slice(0, 64); return s.length >= 8 ? s : ''; };

// ── ONE CONVERSATION PER PERSON, THAT NOTHING CAN LOSE (founder ruling 1255, 19 Oct 2026) ──────────────────────────
// "No matter what, the agent can't lose the chat. Cache shouldn't be cleared until the inquiry is made fully."
//   - A visitor's chat lives under v-<id>, the id kept in the browser's localStorage (survives a reload, a closed browser
//     and a return days later); a signed-in person's under a-<account>, the same key on the widget and in the portal.
//   - Signing up mid-conversation carries it over: the portal's first load after sign-in (assist_history with adopt)
//     ADOPTS the visitor chat, however old, into the account (conv_id rewritten, nothing deleted), so the sales engineer sees everything said before
//     sign-up, and the visitor id then reads nothing for anyone else.
//   - Every turn reloads the whole conversation from assistant_logs, so a provider's prompt cache expiring changes the
//     price of a turn, never what the model is given. Nothing here deletes a row; retention (fn_conversation_retention_
//     purge) only blanks rows five years after the party's last activity.
// SECURITY (review of #1438, 19 Oct 2026): a visitor id is a bearer secret (whoever presents it reads that chat), so
// only a full random UUID v4 (122 random bits, crypto.randomUUID in ChatWidget) is accepted. Anything else gets no stored
// history and nothing is moved. Adoption into an account happens ONLY when the caller passes adopt (sales_engineer
// 'assist_history', sent once by the portal right after sign-in), and only once: adoption re-keys the rows, so a second
// account presenting the same id moves 0. There is NO age limit (ruling 1255: a chat on Monday and a sign-up on Thursday
// must still meet in the portal); the full UUID held in that browser's permanent storage is what proves the same visitor.
// pending is true only when visitor rows may still be waiting (the move failed), so the portal keeps the id and retries.
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export const visitorIdOf = (v: unknown): string => { const s = String(v ?? '').trim().toLowerCase(); return UUID_V4.test(s) ? s : ''; };
export const visitorKey = (conv: unknown) => { const id = visitorIdOf(conv); return id ? 'v-' + id : ''; };
export const accountKey = (kind: 'customer' | 'supplier', id: string) => (id ? 'a-' + (kind === 'supplier' ? 's' : 'c') + '-' + id : '');

/** The key a new turn is written under, and every turn of the conversation so far. turns is null when unreadable. */
// deno-lint-ignore no-explicit-any
export async function openConversation(admin: any, o: { account?: string; visitorConv?: string; adopt?: boolean }): Promise<{ key: string; turns: ChatMsg[] | null; adopted: number; pending?: boolean }> {
  const v = visitorKey(o.visitorConv);
  if (!o.account) return { key: v, turns: v ? await loadTranscript(admin, v) : [], adopted: 0 };
  let adopted = 0, pending = false;
  if (v && o.adopt) {
    const { data, error } = await admin.from('assistant_logs').update({ conv_id: o.account }).eq('conv_id', v).select('id');
    if (error) pending = true; else adopted = (data ?? []).length;
  }
  return { key: o.account, turns: await loadTranscript(admin, o.account), adopted, pending };
}
