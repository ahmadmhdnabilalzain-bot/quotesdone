// _shared/turn_replay.ts — a message sent twice in a row is answered once (it_engineer, 11 Nov 2026, ruling 1631).
//
// MEASURED (assistant_logs, 30 days to 11 Nov 2026, synthetic traffic excluded): assistant_logs 4875, a portal turn, is the
// same message in the same conversation 1 s after the one before it, and it was answered again with the same reply: a
// second model call, and the customer shown the answer twice. A double click, a retried request or a reconnect does that.
// Ruling 1631: an agent "never treats a message as a new conversation and never repeats itself".
// THE RULE (code, no model): when the newest stored turn of this conversation is the same message (whitespace and case
// folded), less than REPLAY_WINDOW_S old, and was answered, that answer is returned as it is and nothing new is stored.
// prevented by: _shared/turn_replay.test.ts

export const REPLAY_WINDOW_S = 60;

export interface StoredTurn { id?: number; message?: string | null; reply?: string | null; created_at?: string | null }

const norm = (s: unknown) => String(s ?? '').replace(/\s+/g, ' ').trim().toLowerCase();

/** The stored answer to replay, or null when this message must be answered. */
export function replayOf(last: StoredTurn | null | undefined, message: string, now = Date.now(), windowS = REPLAY_WINDOW_S): StoredTurn | null {
  if (!last || !String(last.reply ?? '').trim()) return null;
  if (!norm(message) || norm(last.message) !== norm(message)) return null;
  const at = Date.parse(String(last.created_at ?? ''));
  if (!Number.isFinite(at) || now - at > windowS * 1000 || now < at - 5_000) return null;
  return last;
}

/** The newest stored turn of one conversation (one indexed row). null when there is none or it cannot be read. */
// deno-lint-ignore no-explicit-any
export async function lastTurn(admin: any, convId: string): Promise<StoredTurn | null> {
  if (!convId) return null;
  try {
    const { data, error } = await admin.from('assistant_logs').select('id,message,reply,created_at').eq('conv_id', convId)
      .order('id', { ascending: false }).limit(1).maybeSingle();
    return error ? null : (data ?? null);
  } catch (_e) { return null; }
}
