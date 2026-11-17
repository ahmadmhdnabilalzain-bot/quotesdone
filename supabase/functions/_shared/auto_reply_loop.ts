// _shared/auto_reply_loop.ts — two machines never answer each other for ever (it_engineer, 11 Nov 2026).
//
// THE RULE (founder, 11 Nov 2026, with rulings 1631/1636): when our automated replies to the same address reach LOOP_CAP (3)
// inside LOOP_WINDOW_MS (one hour) with no human-sounding message from them in between, we stop replying and flag it.
// Code decides it, on every channel that delivers our reply to an address: WhatsApp (wa_inbound/burst.ts turnGate) and
// email (email_triage, beside the daily answer cap). A web chat (the widget, the portal) shows its reply only in the page
// that asked, so no responder at an address can answer it back; SMS is never answered automatically (sms_inbound).
//
// WHY A CAP AND NOT ONLY THE HEADERS. Email already refuses a mail whose headers or subject say a machine wrote it
// (_shared/customer_mail.ts noAutoReply: Auto-Submitted, X-Autoreply, Precedence, the usual subject lines). A business
// WhatsApp auto-reply carries no header at all, and an email auto-responder that sets none, or a ticket system that opens
// a ticket for every mail and confirms it, answers each of our replies. Each of those replies is then answered by us, and
// the loop costs a model call and a message each turn until someone notices. The cap is the backstop that needs no header.
//
// HUMAN-SOUNDING. A message is machine-sounding when it reads as an auto-reply (the phrases below, English and Arabic) or
// repeats, word for word, a message of theirs already in the window (a responder sends the same text every time; a person
// rarely sends the same 20+ characters twice). Anything else is human: a single human message resets the count.
// prevented by: _shared/auto_reply_loop.test.ts
import { whereAddress } from './address_filter.ts';

export const LOOP_CAP = 3;
export const LOOP_WINDOW_MS = 60 * 60_000;

const AUTO_EN = /\b(auto(?:matic|mated)?[- ]?(?:reply|response|responder|generated|message)|out of (?:the )?office|away from (?:the |my )?(?:office|desk)|(?:i am|i'm) (?:currently )?(?:out|away|on (?:annual )?leave|travell?ing)\b|this (?:is an? )?(?:automated|automatic|unmonitored)\b|(?:do not|don't|please do not) reply to this|sent automatically|we have received your (?:message|email|request)|your (?:ticket|request|case) (?:number|#|id)|thank(?:s| you) for (?:contacting|reaching out to|messaging|your (?:message|email|enquiry|inquiry))[^.!\n]{0,60}(?:we|our team|one of our)[^.!\n]{0,40}(?:get back|respond|reply|contact you)|(?:our )?(?:business|working|office) hours are)/i;
const AUTO_AR = /(رد (?:تلقائي|آلي)|رسالة (?:تلقائية|آلية)|خارج المكتب|(?:أنا |انا )?في إجازة|تم استلام رسالتك|سنرد عليك في أقرب|سيتم الرد عليك|ساعات العمل|لا تقم بالرد)/;

const norm = (s: string) => String(s || '').toLowerCase().replace(/\s+/g, ' ').trim();

/** Whether a message of theirs reads as a machine's: an auto-reply phrase, or a 20+ character repeat of an earlier one. */
export function machineSounding(text: string, earlierTheirs: readonly string[] = []): boolean {
  const t = norm(text);
  if (!t) return false;   // a photo or a file with no caption: a person sends those
  if (AUTO_EN.test(t) || AUTO_AR.test(t)) return true;
  return t.length >= 20 && earlierTheirs.some((e) => norm(e) === t);
}

export interface LoopEvent { at: number; who: 'us' | 'them'; text: string }
export interface LoopVerdict { stop: boolean; oursSinceHuman: number; lastHumanAt: number | null }

/** A word-for-word repeat reads as a machine only when it came this soon after our reply (WhatsApp, burst.ts). A responder answers
 *  within seconds of our message; a person who sends the same words again (nobody answered them, or they are making a point)
 *  takes longer than this to read our reply and type or paste it (final audit 12 Nov 2026, integration F8: the same 20+
 *  character message four times in an hour silenced anyone, the founder's own number included). */
export const AUTO_REPEAT_MS = 15_000;

/** Whether the next automated reply would be one too many. `events` holds both sides (any order); `now` is the decision.
 *  `repeatWithinMs`: a repeat counts as machine-sounding only when it arrived that soon after our last reply (unset: any time). */
export function loopVerdict(events: readonly LoopEvent[], now: number = Date.now(), cap = LOOP_CAP, windowMs = LOOP_WINDOW_MS,
  o: { repeatWithinMs?: number } = {}): LoopVerdict {
  const inWindow = events.filter((e) => e.at >= now - windowMs && e.at <= now).sort((a, b) => a.at - b.at);
  let lastHumanAt: number | null = null;
  let lastOursAt: number | null = null;
  const theirs: string[] = [];
  for (const e of inWindow) {
    if (e.who !== 'them') { lastOursAt = e.at; continue; }
    const quick = o.repeatWithinMs == null || (lastOursAt !== null && e.at - lastOursAt <= o.repeatWithinMs);
    const machine = machineSounding(e.text) || (quick && machineSounding(e.text, theirs));
    if (!machine) lastHumanAt = e.at;
    theirs.push(e.text);
  }
  const ours = inWindow.filter((e) => e.who === 'us' && (lastHumanAt === null || e.at > lastHumanAt)).length;
  return { stop: ours >= cap, oursSinceHuman: ours, lastHumanAt };
}

// ---- email: the hour of one address, read from the outbox and the inbox (email_triage, beside the daily answer cap) ----------
// deno-lint-ignore no-explicit-any
type Admin = any;

/** Whether an automatic answer to this mail would be one too many. When it would, an it_engineer finding is raised here.
 *  A read that fails answers false (the daily cap and the header rules still stand): the cap may never stop a real answer
 *  on a database blip. `m` is the inbound_messages row being answered. */
export async function mailLoopHeld(admin: Admin, m: { id?: unknown; from_email?: unknown; subject?: unknown; body?: unknown }, now: number = Date.now()): Promise<boolean> {
  const addr = String(m.from_email ?? '').trim().toLowerCase();
  if (!addr) return false;
  const since = new Date(now - LOOP_WINDOW_MS).toISOString();
  try {
    const [ours, theirs] = await Promise.all([
      whereAddress(admin.from('notifications').select('created_at,sent_at').eq('type', 'inbound_reply').in('status', ['sent', 'sending']),
        'to_email', addr).gte('created_at', since).limit(200),
      whereAddress(admin.from('inbound_messages').select('id,created_at,subject,body'), 'from_email', addr).gte('created_at', since).limit(200),
    ]);
    if (ours.error || theirs.error) return false;
    const events: LoopEvent[] = [
      ...((ours.data ?? []) as { created_at?: string; sent_at?: string | null }[]).map((r) => ({ at: Date.parse(String(r.sent_at ?? r.created_at ?? '')) || 0, who: 'us' as const, text: '' })),
      ...((theirs.data ?? []) as { id?: unknown; created_at?: string; subject?: string; body?: string }[]).filter((r) => String(r.id) !== String(m.id))
        .map((r) => ({ at: Date.parse(String(r.created_at ?? '')) || 0, who: 'them' as const, text: [r.subject, String(r.body ?? '').slice(0, 2000)].filter(Boolean).join('\n') })),
      { at: now, who: 'them', text: [m.subject, String(m.body ?? '').slice(0, 2000)].filter(Boolean).join('\n') },
    ];
    const v = loopVerdict(events, now);
    if (!v.stop) return false;
    try {
      await admin.rpc('fn_it_engineer_finding_upsert', {
        p_issue_key: 'email_triage:auto_reply_loop', p_title: 'Automatic email answers to one address reached ' + LOOP_CAP + ' within an hour with no human-sounding mail between them; answering stopped',
        p_where: 'edge function email_triage (_shared/auto_reply_loop.ts)', p_blast: 'customer_facing', p_affected: 1,
        p_evidence: { message_id: m.id ?? null, domain: addr.split('@')[1] ?? null, answers_since_a_person: v.oursSinceHuman, cap: LOOP_CAP, window_min: LOOP_WINDOW_MS / 60_000 },
        p_ruled_out: [], p_undetermined: [], p_raised_by: 'customer_support',
      });
    } catch (_e) { /* the stop stands even when the finding cannot be written */ }
    return true;
  } catch (_e) { return false; }
}
