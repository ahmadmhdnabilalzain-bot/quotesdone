// email_history - the e-mail conversation the model is shown: this address's earlier mail and what we sent back
// (customer_support, 19 Nov 2026; founder ledger 1474, "never lose the conversation or start it again").
//
// Measured on origin/main 9d82984d4: email_triage handed both reply roads (aiReply and think) only the new mail, plus the
// case summary when the person's case had one. A second mail ("and the second villa?") reached the model alone, the way
// wa_inbound's did before wa_history.ts (2 Nov 2026) and the portal's before chat_history.ts (18 Oct 2026). On production
// on 19 Nov 2026, 9 addresses among the 100 inbound_messages rows had written more than once, and all 10 inbound_reply
// notifications had been sent: any later mail from those 9 reached the model with no memory of the earlier ones.
//
// What the model is given, oldest first: every earlier inbound_messages row FROM this address (before this mail), and
// every e-mail notification we SENT TO this address (our replies in the thread, the invitation a supplier is answering),
// whenever it went. Then the same treatment the chat doors get (chat_history.ts): markUnanswered, so a mail that got no
// reply is not answered now under the new one, and fitHistory, the estate's character budget with every one of their
// words kept first. loadCaseContext then cuts it to MESSAGE_CAP, or the case's last CASE_TURNS when the case has a summary.
//
// WHOSE MAIL (personal data): rows are matched on the ONE address, by equality (whereAddress, never a pattern: address_
// filter.ts), so no other person's mail or reply is ever read. A forged From cannot read anything out: the reply goes to the
// From address itself (fn_inbox_send writes notifications.to_email = from_email), so whatever the model was shown is sent
// only to the person it belongs to. A message carrying a code (a sign-in or verification code) is never shown, and a
// link carrying a token (?t= or &t=) is shown as [link].
// Measured 19 Nov 2026: inbound_messages.from_email and notifications.to_email carry no "Name <addr>" form and no capital.
// A failed read thins the answer and is logged; it never costs the reply (wa_history.ts, drill D10).
// prevented by: _shared/email_history.test.ts
import { fitHistory, markUnanswered } from './chat_history.ts';
import { normalEmail, whereAddress } from './address_filter.ts';
import type { Turn } from './think.ts';

/** Rows read from each table: the newest this many (an address with more is a pathology fitHistory would cut anyway). */
export const EMAIL_HISTORY_ROWS = 200;
/** A notification type that carries a secret is never shown to a model (none in channel 'email' on 19 Nov 2026). */
const SECRET_TYPE = /otp|code|password|verif|magic_link|login/i;

// deno-lint-ignore no-explicit-any
type Admin = any;
type Item = { at: string; ours: boolean; text: string };

// A SIGN-IN LINK NEVER REACHES A PROMPT (review of 36435809d, 19 Nov 2026): invitations and replies carry portal?t=<token>
// links, and a mail of theirs can quote one. The whole link becomes [link], so the model still knows a link was there.
export const LINK_WITH_TOKEN = /[^\s"'<>(\[]*[?&]t=[^\s"'<>)\]]*/g;
export const redactLinks = (s: string) => s.replace(LINK_WITH_TOKEN, '[link]');
const mailText = (subject: unknown, body: unknown) => {
  const s = redactLinks(String(subject ?? '').trim()), b = redactLinks(String(body ?? '').trim());
  return b ? (s ? 'Subject: ' + s + '\n\n' + b : b) : '';
};

/** Every earlier exchange this address had with us by e-mail, oldest first, as the model's `conversation`. */
export async function emailConversation(admin: Admin, o: { email: unknown; beforeId: number; party: 'customer' | 'supplier'; fixture?: boolean },
  onUnavailable?: (error: string) => void): Promise<Turn[]> {
  const addr = normalEmail(o.email);
  if (!/@/.test(addr) || !(o.beforeId > 0)) return [];
  const failed = (e: unknown) => { try { onUnavailable?.(String((e as Error)?.message ?? e).slice(0, 300)); } catch (_e) { /* best effort */ } };
  const items: Item[] = [];
  try {
    const [inb, out] = await Promise.all([
      whereAddress(admin.from('inbound_messages').select('id,subject,body,created_at'), 'from_email', addr)
        .lt('id', o.beforeId).order('id', { ascending: false }).limit(EMAIL_HISTORY_ROWS),
      whereAddress(admin.from('notifications').select('type,subject,body,status,created_at'), 'to_email', addr)
        .eq('channel', 'email').order('created_at', { ascending: false }).limit(EMAIL_HISTORY_ROWS),
    ]);
    if (inb.error) failed(inb.error.message || 'inbound_messages read failed');
    if (out.error) failed(out.error.message || 'notifications read failed');
    for (const r of (inb.data ?? []) as { subject?: string; body?: string; created_at?: string }[]) {
      const text = mailText(r.subject, r.body); if (text) items.push({ at: String(r.created_at ?? ''), ours: false, text });
    }
    for (const r of (out.data ?? []) as { type?: string; subject?: string; body?: string; status?: string; created_at?: string }[]) {
      if (SECRET_TYPE.test(String(r.type ?? ''))) continue;
      // said only when it was SENT; a fixture address never sends, so for one the captured message is the conversation
      if (!(r.status === 'sent' || (o.fixture && r.status !== 'cancelled'))) continue;
      const text = mailText(r.subject, r.body); if (text) items.push({ at: String(r.created_at ?? ''), ours: true, text });
    }
  } catch (e) { failed(e); return []; }
  items.sort((a, b) => (a.at < b.at ? -1 : a.at > b.at ? 1 : Number(a.ours) - Number(b.ours)));
  const fitted = fitHistory(markUnanswered(items.map((x) => ({ role: x.ours ? 'assistant' as const : 'user' as const, content: x.text }))));
  return fitted.map((t) => ({ role: t.role === 'assistant' ? 'seat' as const : o.party, text: t.content }));
}
