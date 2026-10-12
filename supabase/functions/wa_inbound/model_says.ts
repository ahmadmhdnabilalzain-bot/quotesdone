// model_says — every CONVERSATION reply on WhatsApp is written by a model in that turn. Seat: customer_support.
// Founder rulings 1195/1196/1197 (12 Oct 2026): code decides WHAT happened (a routine's result, a document's read,
// a menu option's own data) and hands it over as facts; the words are the model's (_shared/ai_reply.ts: the company
// brief, the model ladder, the figure + reply guard with a model rewrite, suppliers always in English).
// Code never substitutes text: when no model answers, the reply is '' and NOTHING conversational is sent.
// Notifications (OTP, receipts, case-reference receipts, status notices, the accepted-offer confirmation, the
// founder's FIGURES report) are not conversation and do not come through here.
// prevented by: wa_inbound/model_says.test.ts, wa_inbound/menu_flow_model_written.test.ts,
//               wa_inbound/no_unwritten_send.test.ts
import { aiReply } from '../_shared/ai_reply.ts';
import type { ThinkDeps, Turn } from '../_shared/think.ts';

export type SayAudience = 'customer' | 'supplier' | 'visitor' | 'founder';
export interface SayRequest {
  audience: SayAudience;
  lang: 'en' | 'ar';
  message: string;              // what the person wrote this turn
  situation: string;            // what code decided / the routine returned — the facts the reply must convey
  conversation?: Turn[];
  subject?: Record<string, unknown>;
}
export interface Said { text: string; model: string | null; attempts: string[]; ms: number }

export const WA_RULES = 'Plain text for WhatsApp (no markdown), under about 90 words; put each phone number, email or link on its own line, exactly as given in the facts.';

/** The model's words for this turn, or text '' when no model answered (the caller then sends nothing). */
export async function modelSays(deps: ThinkDeps, r: SayRequest): Promise<Said> {
  const t0 = Date.now();
  try {
    const out = await aiReply(deps, {
      seat: 'customer_support', channel: 'whatsapp', audience: r.audience, lang: r.lang,
      message: r.message || '(no text — they pressed a menu option or sent a file)',
      conversation: r.conversation,
      facts: 'WHAT HAS HAPPENED ON THIS TURN (decided by our systems; convey it accurately, do not change or add to it):\n' + r.situation,
      rules: WA_RULES, subject: r.subject,
    });
    return { text: String(out.reply || '').trim(), model: out.model, attempts: out.attempts, ms: Date.now() - t0 };
  } catch (e) {
    return { text: '', model: null, attempts: ['error: ' + String((e as Error)?.message || e).slice(0, 120)], ms: Date.now() - t0 };
  }
}
