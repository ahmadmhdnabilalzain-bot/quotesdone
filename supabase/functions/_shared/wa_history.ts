// wa_history - the WhatsApp conversation the model is shown, read from the rows wa_inbound already stores.
// Seat: customer_support (2 Nov 2026). Founder ruling 18 Oct (_shared/chat_history.ts): no turn limit, every turn
// stored, the whole history to the model. The portal widget got it that day; wa_inbound never did: its `say` passed the
// message and the facts but no `conversation`, so "what about the second one?" on turn 6 reached the model alone.
// Rows are wa_messages (inbound + reply on one row, created_at = arrival). A reply counts as said only when it was SENT;
// a reserved fixture number never sends (demo_identity), so for a fixture the captured reply is the conversation.
// prevented by: wa_inbound/the_whole_exchange.test.ts
import type { Turn } from './think.ts';

export const WA_HISTORY_ROWS = 500;
// deno-lint-ignore no-explicit-any
type Admin = any;

/** Every earlier turn this number had with us, oldest first, as the model's `conversation`. */
export async function waConversation(admin: Admin, from: string, before: string, capturedCounts = false): Promise<Turn[]> {
  try {
    const { data } = await admin.from('wa_messages').select('inbound,reply,sent')
      .eq('wa_from', from).lt('created_at', before).order('created_at', { ascending: false }).limit(WA_HISTORY_ROWS);
    const rows = ((data ?? []) as { inbound?: string | null; reply?: string | null; sent?: boolean | null }[]).slice().reverse();
    const out: Turn[] = [];
    for (const r of rows) {
      const said = String(r.inbound || '').trim(); if (said) out.push({ role: 'customer', text: said });
      const ours = String(r.reply || '').trim(); if (ours && (r.sent === true || capturedCounts)) out.push({ role: 'seat', text: ours });
    }
    return out;
  } catch (_e) { return []; }   // a missing history thins the answer; it never loses the message
}
