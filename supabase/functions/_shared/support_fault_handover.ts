// support_fault_handover — "it is broken" reaches the IT engineer as a real hand-over. Seat: customer_support (the hand-over)
// for it_engineer (the repair). Founder rulings 1705 (15 Nov 2026: "The IT engineer should solve it, not report it") and 1574.
//
// MEASURED 15 Nov 2026 (SP/audit/SUPPORT_IT.md): 0 support.root_cause hand-overs to it_engineer in 30 days. support_reply.ts
// named it_engineer as the owner of "the site or app is broken, an error, a login or upload fault" and only returned the name;
// supportReply() has no live caller today. The live surfaces read every message with the reasoned decision needs_a_person
// (reasoned_decisions.ts); its third option, site_fault, is chosen by the MODEL (ruling 1663: the LLM understands, code only
// checks), and a surface that sees it calls handFaultToIt with what it already knows.
//
// What is handed over: the channel, a case key (never an address or a phone), the person's last turns MASKED here
// (identity_text.ts scrubIdentityText) and again in the database (fn_it_mask_text), the language and side, and the e-mail ONLY
// when the channel already holds it (e-mail sender, a signed-in portal). Never looked up from a phone ("a phone may confirm,
// never select"). public.fn_support_hands_it_a_fault files it once per case per hour, opens support:fault:<hash> for the IT
// engineer and the support.root_cause hand-over (path live_fault); the person is told through support when the fix is verified
// (fn_support_fault_fixed). Never throws: the reply to the person matters more than the hand-over, and a failed hand-over is
// returned as filed:false with the reason.
// prevented by: _shared/support_fault_handover.test.ts
import { scrubIdentityText } from './identity_text.ts';

export type FaultChannel = 'widget' | 'whatsapp' | 'email' | 'portal';
export interface FaultReport {
  channel: FaultChannel;
  caseKey: string;                         // a stable key for the conversation: never an e-mail or a phone
  message: string;                         // the person's message that reported the fault
  conversation?: { role: string; text: string }[];
  email?: string | null;                   // only when the channel already knows it
  lang?: 'en' | 'ar';
  audience?: 'customer' | 'supplier' | 'visitor';
}
export type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<{ data?: unknown; error?: { message?: string } | null }>;

const PERSON_ROLES = new Set(['user', 'person', 'customer', 'supplier', 'visitor', 'in']);
/** The person's own turns only, newest last, at most 3, each masked and cut to 1,000 characters. */
export function maskedTurns(r: Pick<FaultReport, 'message' | 'conversation'>): { role: string; text: string }[] {
  const theirs = (r.conversation ?? []).filter((t) => PERSON_ROLES.has(String(t?.role ?? '').toLowerCase())).map((t) => String(t.text ?? ''));
  const all = [...theirs, String(r.message ?? '')].map((t) => t.trim()).filter(Boolean);
  const unique = all.filter((t, i) => all.indexOf(t) === i);
  return unique.slice(-3).map((t) => ({ role: 'person', text: scrubIdentityText(t, '█').slice(0, 1000) }));
}

/** A case key that carries no identity: a short SHA-256 of whatever the surface keys the conversation on. */
export async function caseKeyOf(channel: FaultChannel, raw: string): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(channel + ':' + raw)));
  return channel + ':' + Array.from(d.slice(0, 12), (b) => b.toString(16).padStart(2, '0')).join('');
}

export async function handFaultToIt(rpc: Rpc, r: FaultReport): Promise<{ filed: boolean; reason?: string; issueKey?: string; canTell?: boolean }> {
  try {
    if (!r.caseKey || /@|\d{7,}/.test(r.caseKey)) return { filed: false, reason: 'the case key must carry no address or number' };
    const email = r.email && /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(r.email.trim()) ? r.email.trim().toLowerCase() : null;
    const { data, error } = await rpc('fn_support_hands_it_a_fault', {
      p_channel: r.channel, p_case_key: r.caseKey, p_lang: r.lang === 'ar' ? 'ar' : 'en',
      p_audience: r.audience ?? 'visitor', p_turns: maskedTurns(r), p_email: email,
    });
    if (error) return { filed: false, reason: String(error.message ?? 'rpc error').slice(0, 200) };
    const d = (data ?? {}) as { filed?: boolean; reason?: string; issue_key?: string; can_tell?: boolean };
    return { filed: d.filed === true, reason: d.reason, issueKey: d.issue_key, canTell: d.can_tell };
  } catch (e) {
    return { filed: false, reason: 'threw: ' + String((e as Error)?.message || e).slice(0, 200) };
  }
}
