// supplier_onboard/history.ts — the onboarding conversation is read from the DATABASE, not from the browser
// (customer_support, 19 Nov 2026; founder ledger 1474, "never lose the conversation or start it again").
//
// Measured on origin/main 9d82984d4: supplier_onboard/index.ts built the model's history from body.history alone, the copy
// the browser sends. A client could forge it (put words in the supplier's mouth that the extraction then reads as stated)
// or drop it (a reload, another device: the second message started the profile again). Nothing stored the turns at all,
// so there was no record to read. The portal has read its conversation from assistant_logs since 18 Oct 2026
// (sales_engineer/actions/portal.ts, chat_history.openConversation); this does the same:
//   - every turn is written to assistant_logs under one key per signed-in user, onb-<auth user id> (the user is verified
//     by the auth server, so nobody reads or writes another supplier's onboarding), audience 'supplier_onboard' (no
//     ':<id>', so the support-case triggers on assistant_logs, which wire 'customer:<uuid>' / 'supplier:<lead id>', skip it);
//   - the history is that stored transcript. The browser's copy is used only when the database holds no turn for the key
//     (the first turn, or a read that failed), exactly as the portal does: when both exist, the database wins.
// prevented by: supplier_onboard/history.test.ts
import { clientHistory, convIdOf, loadTranscript, type ChatMsg } from '../_shared/chat_history.ts';

export const ONBOARD_AUDIENCE = 'supplier_onboard';

/** The conversation key of one signed-in user's onboarding ('' when the id is unusable: nothing is read or stored). */
export const onboardKey = (userId: unknown): string => convIdOf('onb-' + String(userId ?? ''));

/** The turns before this message: the stored transcript, or the browser's copy only when nothing is stored. */
// deno-lint-ignore no-explicit-any
export async function onboardTurns(admin: any, key: string, browser: unknown, text: string): Promise<{ turns: ChatMsg[]; from: 'database' | 'browser' | 'none' }> {
  const stored = key ? await loadTranscript(admin, key) : null;
  if (stored && stored.length) return { turns: stored, from: 'database' };
  // the browser often sends the message being answered as its last turn; it is the message, not history
  const b = clientHistory(browser).filter((t, i, a) => t.content.trim() && !(i === a.length - 1 && t.role === 'user' && t.content.trim() === text.trim()));
  return { turns: b, from: b.length ? 'browser' : 'none' };
}

/** Stores the turn that was answered. A failed write never fails the extraction; it is logged. */
// deno-lint-ignore no-explicit-any
export async function recordOnboardTurn(admin: any, key: string, text: string, reply: string): Promise<void> {
  if (!key) return;
  try {
    const { error } = await admin.from('assistant_logs').insert({ message: text, reply, conv_id: key, seat: 'sales_engineer', answered: true,
      audience: ONBOARD_AUDIENCE, path: 'supplier_onboard', matched_ids: [] });
    if (error) console.error('supplier_onboard: the turn was not stored', error.message);
  } catch (e) { console.error('supplier_onboard: the turn was not stored', String((e as Error)?.message ?? e)); }
}
