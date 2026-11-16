// complaint_register — a complaint on ANY channel enters the complaints register (customer_support, 16 Nov 2026; COO hole H2).
//
// MEASURED (READ, origin/main 55489dde7): only contact_submit/index.ts called fn_complaint_open. email_triage read a mail as
// `complaint` and only replied; WhatsApp reported it to the CEO seat (general_turn.ts fn_support_report_to_ceo); the widget and
// the portal chat filed nothing. complaint_tickets had 0 rows ever (SELECT), so the acknowledge-in-2 / respond-in-10 working-day
// clocks of the Complaints Policy never started for a complaint that came any other way.
//
// WHO DECIDES IT IS A COMPLAINT: the model, in the reading each door already makes (ruling 1663: the LLM understands, code only
// checks; "do not add a model call per message where the call that already writes the reply can also return the understanding"):
//   * e-mail, WhatsApp, the widget: the needs-a-person reading carries a second choice in the SAME call, `complaint`
//     (COMPLAINT_OPTIONS below; reasoned_decisions.ts needsAPerson, reasoned_channels.ts whatsappReadings); e-mail also takes its
//     triage model's own `complaint` category;
//   * the portal: the turn reading (inquiry_reading.ts) returns `complaint`, one sentence, or "".
// Code never reads the words. It opens the ticket once per message (fn_complaint_open_from_message, keyed on the message), with
// what the channel already holds about the person (never an e-mail looked up from a phone), and checks that a reply carried
// the ticket before it counts as the acknowledgement. Never throws: the reply to the person matters more than the register.
// prevented by: _shared/complaint_register.test.ts, _shared/complaint_register_scenarios.test.ts and
// scripts/sql/every_inbound_message_is_answered_or_closed_with_its_reason_and_a_complaint_on_any_channel_is_registered_probe.sql

export type ComplaintChannel = 'email' | 'whatsapp' | 'widget' | 'portal';

/** The second choice of the needs-a-person reading. Chosen by the model, never by a word list. */
export const COMPLAINT_OPTIONS = [
  { id: 'complaint', meaning: 'they express dissatisfaction they want QuotesDone to address: a complaint about QuotesDone, a supplier, a customer, a quote, a charge, a refund, a delay, the service or how they were treated, including a dispute or an accusation, whether or not they also ask for a person -- however it is worded, in any language' },
  { id: 'not_a_complaint', meaning: 'anything else: a question (including how complaints, refunds or disputes work), a request, a fault report with no dissatisfaction aimed at us, thanks, or a request for a person with no complaint' },
];
export const isComplaint = (choice: unknown): boolean => choice === 'complaint';

export interface ComplaintReport {
  channel: ComplaintChannel;
  /** one ticket per MESSAGE: email:<inbound id>, whatsapp:<message sid>, widget:<hash>, portal:<conversation>:<turn> */
  sourceKey: string;
  message: string;
  /** why the model read it as a complaint (its own words), kept on the ticket */
  reading?: string | null;
  email?: string | null;            // only when the channel already holds it
  phone?: string | null;            // WhatsApp's own number; never used to look an e-mail up
  name?: string | null;
  partyKind?: 'customer' | 'supplier' | null;
  partyId?: string | null;
  caseRef?: string | null;
  lang?: 'en' | 'ar' | null;
  fixture?: boolean;
}
export interface Ticket { ticket: string; respondDue: string; acknowledgeDue: string; duplicate: boolean; acknowledged: boolean; jobs: string[] }
export type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<{ data?: unknown; error?: { message?: string } | null }>;

const EMAIL = /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i;

/** Opens (or finds) the ticket for this message. Never throws. */
export async function registerComplaint(rpc: Rpc, r: ComplaintReport): Promise<{ opened: boolean; ticket?: Ticket; reason?: string }> {
  try {
    const key = String(r.sourceKey ?? '').trim();
    if (!key || key.length > 300) return { opened: false, reason: 'no source key: a ticket is opened once per message' };
    if (/@/.test(key)) return { opened: false, reason: 'the source key must carry no address' };
    if (!String(r.message ?? '').trim()) return { opened: false, reason: 'empty message' };
    const email = r.email && EMAIL.test(r.email.trim()) ? r.email.trim().toLowerCase() : null;
    const { data, error } = await rpc('fn_complaint_open_from_message', {
      p_channel: r.channel, p_source_key: key, p_message: String(r.message).slice(0, 4000), p_reading: r.reading ? String(r.reading).slice(0, 600) : null,
      p_email: email, p_phone: r.phone ?? null, p_name: r.name ?? null,
      p_party_kind: r.partyKind === 'customer' || r.partyKind === 'supplier' ? r.partyKind : null, p_party_id: r.partyId ? String(r.partyId) : null,
      p_case_ref: r.caseRef ?? null, p_lang: r.lang === 'ar' ? 'ar' : r.lang === 'en' ? 'en' : null, p_fixture: r.fixture === true,
    });
    if (error) return { opened: false, reason: String(error.message ?? 'rpc error').slice(0, 200) };
    const d = (data ?? {}) as Record<string, unknown>;
    if (d.ok !== true || typeof d.ticket !== 'string') return { opened: false, reason: String(d.reason ?? 'not opened').slice(0, 200) };
    return { opened: true, ticket: { ticket: d.ticket, respondDue: String(d.respond_due ?? ''), acknowledgeDue: String(d.acknowledge_due ?? ''),
      duplicate: d.duplicate === true, acknowledged: d.acknowledged === true, jobs: Array.isArray(d.inquiry_refs) ? d.inquiry_refs.map(String) : [] } };
  } catch (e) {
    return { opened: false, reason: 'threw: ' + String((e as Error)?.message || e).slice(0, 200) };
  }
}

/** The date a person is given, in Dubai time, as YYYY-MM-DD (the form the complaint e-mails already use). */
export function dueDate(iso: string): string {
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) return '';
  return new Date(t + 4 * 3600_000).toISOString().slice(0, 10);
}

/** What the reply is written knowing: the ticket is registered and must be named. Facts for the model, never the reply itself. */
export function complaintFact(t: Ticket): string {
  const due = dueDate(t.respondDue);
  return 'THEIR COMPLAINT IS REGISTERED: reference ' + t.ticket + '. In the reply, tell them it is registered under that reference'
    + (due ? ' and that our final response will reach them by ' + due : '') + ', and answer the rest of what they wrote. Do not judge the complaint or promise an outcome.';
}

/** The reply that went carried the ticket: that IS the acknowledgement on this channel. Returns whether it was stamped. */
export async function acknowledgeIfCarried(rpc: Rpc, t: Ticket | null | undefined, sentText: string | null | undefined, how: string): Promise<boolean> {
  try {
    if (!t || t.acknowledged || !sentText || !sentText.includes(t.ticket)) return false;
    const { data, error } = await rpc('fn_complaint_acknowledge', { p_ticket: t.ticket, p_how: how });
    return !error && data === true;
  } catch { return false; }
}

/** A stable key with no identity in it (for the widget, whose caller is an address or an account). */
export async function hashedKey(channel: ComplaintChannel, raw: string): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode('complaint:' + channel + ':' + raw)));
  return channel + ':' + Array.from(d.slice(0, 12), (b) => b.toString(16).padStart(2, '0')).join('');
}
