// messages_api — the customer's unified inbox, the post-reveal customer<->supplier chat, and the
// pre-reveal anonymous Q&A (clarify_*).
//
// 14 Sep 2026: post-reveal chat no longer waits on an approval queue and no longer bans for sharing
// contact details. After a paid reveal both parties already hold each other's contact details, so
// the detector that blocked them and auto-suspended accounts policed a secret that no longer
// existed; and the "Admin → Agents → approvals" queue it routed chat requests to was removed by the
// founder's 7-8 Sep rulings (two seats, no approval queue). Contact stripping now applies only
// where anonymity is the product: the pre-reveal Q&A below.
import { createClient } from 'jsr:@supabase/supabase-js@2';

import { observe } from '../_shared/observe.ts';
import { isCustomerCorrespondence } from '../_shared/customer_mail.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const clip = (v: unknown, n: number) => String(v ?? '').trim().slice(0, n);
const WARNING = 'Messages here are kept on record for both of you. Please keep them about this job.';

async function notify(rows: Record<string, unknown>[]) { try { if (rows.length) await admin.from('notifications').insert(rows); } catch (_e) {} }

async function revealed(inquiry_id: string, supplier_id: number) {
  const { data } = await admin.from('transactions').select('id,customer_id').eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).not('revealed_at', 'is', null).maybeSingle();
  return data || null;
}

// ── §16 THE UNIFIED INBOX: ONE PLACE, FOUR CHANNELS ─────────────────────────────────────────────
// MEASURED 7 Aug 2026: wa_messages held 5 rows and inbound_messages 8, five edge functions touched
// each, and the customer's inbox opened NEITHER. WhatsApp and e-mail were captured by the platform
// and shown only to staff; calls were not logged anywhere with a counterparty at all (llm_calls is
// an API-usage ledger). "One unified place" was one channel.
//
// THE JOIN KEY IS THE CUSTOMER'S OWN IDENTITY, and that is the whole safety story here: wa_messages
// is matched on the customer's own phone number and inbound_messages on their own e-mail address,
// so what comes back is the customer's own correspondence with QuotesDone. Nothing is joined
// through a supplier, so this cannot leak an identity the reveal fee sells.
const CHANNELS = ['chat', 'whatsapp', 'email', 'call'];
// A UAE mobile written six ways is one number. Comparing raw text would silently return nothing
// for every customer who stored theirs with a +971 or a space.
const digits = (v: unknown) => String(v ?? '').replace(/\D+/g, '').replace(/^00971/, '971').replace(/^0/, '971');

// THE WHATSAPP CHANNEL NEEDS A VERIFIED NUMBER, NOT A TYPED ONE.
//
// wa_messages has no customer_id — the phone number is the only key, and this join was the only
// thing standing between a customer and someone else's WhatsApp history with QuotesDone. It checked
// that the number was PRESENT. `customers.phone` is whatever the account typed; `phone_verified` is
// whether they proved they hold it. MEASURED 13 Aug 2026 on production: three customer rows, two of
// them sharing one number, and one row carrying an UNVERIFIED number — which this join would have
// honoured. E-mail needs no equivalent gate: it is joined on the address in the JWT, and the OTP
// login is itself the proof of that address.
//
// The rule is exactly "can they already read this thread in WhatsApp?": whoever receives messages
// at that number can, and verification is how we know they do. Both readers — the list here and
// `channel_thread` — go through this one predicate.
const waPhoneOf = (cust: { phone?: string | null; phone_verified?: boolean | null }) =>
  cust.phone_verified === true ? digits(cust.phone) : '';

async function otherChannels(cust: { id: string; phone?: string | null; phone_verified?: boolean | null }) {
  const out: any[] = [];
  const phone = waPhoneOf(cust);
  if (phone.length >= 9) {
    const { data: wa } = await admin.from('wa_messages')
      .select('id,wa_from,wa_to,inbound,reply,created_at').order('created_at', { ascending: false }).limit(200);
    const mine = (wa || []).filter((m: any) => digits(m.wa_from) === phone || digits(m.wa_to) === phone);
    if (mine.length) out.push({ channel: 'whatsapp', inquiry_id: null, supplier_id: null,
      counterpart: 'QuotesDone on WhatsApp', subject: 'WhatsApp', chat_status: 'open',
      last: clip(mine[0].inbound || mine[0].reply, 240), last_at: mine[0].created_at, unread: 0, count: mine.length });
  }
  // The address goes into a PostgREST `or` filter, whose grammar uses , ( ) . — so it is checked
  // against a strict address shape first rather than escaped. An address that cannot appear in an
  // `or` filter unambiguously is not queried at all; returning no e-mail channel is a correct
  // answer, and building the filter anyway would let a stored address change what is selected.
  const cEmail = String((cust as any).email || '').toLowerCase();
  // isCustomerCorrespondence drops back-office mail (receipts forwarded to expenses@, rows a seat
  // owns) — the join key alone showed the founder his own expense forwards as customer mail.
  // ponytail: filtered after the 50-row window, so a heavy forwarder sees fewer than 50; push the
  // predicate into the query if that is ever measured to hide real customer mail.
  const em = /^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$/.test(cEmail)
    ? ((await admin.from('inbound_messages')
        .select('id,from_email,to_email,subject,ai_summary,body,created_at,replied_at,owner_role')
        .or(`from_email.eq.${cEmail},to_email.eq.${cEmail}`)
        .order('created_at', { ascending: false }).limit(50)).data || []).filter(isCustomerCorrespondence)
    : [];
  if ((em || []).length) out.push({ channel: 'email', inquiry_id: null, supplier_id: null,
    counterpart: 'QuotesDone by e-mail', subject: em![0].subject || 'E-mail', chat_status: 'open',
    last: clip(em![0].ai_summary || em![0].body, 240), last_at: em![0].created_at,
    unread: (em || []).filter((r: any) => !r.replied_at).length, count: em!.length });

  const { data: calls } = await admin.from('customer_calls')
    .select('id,direction,status,started_at,duration_s,summary,inquiry_id')
    .eq('customer_id', cust.id).order('started_at', { ascending: false }).limit(50);
  if ((calls || []).length) out.push({ channel: 'call', inquiry_id: calls![0].inquiry_id || null, supplier_id: null,
    counterpart: 'Calls', subject: 'Call log', chat_status: 'open',
    last: clip(calls![0].summary || (calls![0].direction + ' call, ' + calls![0].status), 240),
    last_at: calls![0].started_at, unread: 0, count: calls!.length });
  return out;
}

// ── PRE-REVEAL ANONYMOUS Q&A (website audit 14 Sep 2026, verdict ABSENT) ───────────────────────
// Every thread below is locked until a paid reveal, so between "posted" and "paid" a supplier who
// needed one measurement could not ask it and the customer could not answer. public.rfq_clarification
// is that channel, and this is its only writer of questions and answers:
//   clarify_list   {inquiry_id}   -> the owner sees everything; a matched supplier sees their own
//                                    questions plus every answered one (answers are addenda to the RFQ)
//   clarify_ask    {inquiry_id, text}  supplier session, must be matched to the inquiry
//   clarify_answer {id, text}          customer session, owner only; every matched supplier is told
// Identities are masked both ways: suppliers appear to the customer as "Supplier A/B..." in the
// order they were matched, the customer never appears at all, and contact details are stripped from
// both texts here, server-side, before anything is stored or emailed.
const STRIP: RegExp[] = [
  /[A-Za-z0-9._%+-]+\s*(?:@|\(at\)|\[at\])\s*[A-Za-z0-9.-]+\s*(?:\.|\(dot\)|\[dot\])\s*[A-Za-z]{2,}/gi,
  /(?:https?:\/\/|www\.)[^\s,;)\]]+/gi,
  /\b[A-Za-z0-9-]{2,}\.(?:ae|com|net|org|co|io|me|biz|info|app|link)(?:\.[A-Za-z]{2})?\b/gi,
  /(?:\+|00)\s?971[\s.\-]?\d(?:[\s.\-]?\d){6,10}/g,
  /\b0\d(?:[\s.\-]?\d){7,8}\b/g,
  /\b5\d(?:[\s.\-]?\d){7}\b/g,
  /\b(?:whats\s*app|wa\.me|telegram|t\.me|viber|botim|snapchat|skype|instagram)\b\S*/gi,
  /(^|\s)@[A-Za-z0-9_.]{3,}/g,
];
const NAME_STOP = new Set(['llc', 'l.l.c', 'trading', 'contracting', 'general', 'company', 'group', 'est', 'establishment', 'services', 'technical', 'the', 'and']);
// ponytail: a name is removed as whole words of 4+ letters; a nickname or misspelling survives.
// Upgrade path is customer_api's companyRe if a leak is ever measured.
function scrubName(text: string, name: unknown): string {
  const words = String(name || '').split(/[^A-Za-z؀-ۿ]+/).filter((w) => w.length >= 4 && !NAME_STOP.has(w.toLowerCase()));
  let out = text;
  for (const w of words) out = out.replace(new RegExp('(^|[^A-Za-z؀-ۿ])' + w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(?=$|[^A-Za-z؀-ۿ])', 'gi'), '$1[removed]');
  return out;
}
function stripContact(raw: unknown, names: unknown[] = []): string {
  // Arabic-Indic digits first, so ٠٥٠١٢٣٤٥٦٧ is caught by the same number patterns.
  let s = clip(raw, 1500).replace(/[٠-٩]/g, (c) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(c))).replace(/[۰-۹]/g, (c) => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(c)));
  for (const re of STRIP) s = s.replace(re, (m: string, lead?: string) => (typeof lead === 'string' && /^\s?$/.test(lead) && m.startsWith(lead) ? lead : '') + '[removed]');
  for (const n of names) s = scrubName(s, n);
  return s.trim();
}
const letterOf = (i: number) => 'Supplier ' + (i >= 0 && i < 26 ? String.fromCharCode(65 + i) : String(i + 1));
type Res = { status: number; body: Record<string, unknown> };
const R = (status: number, body: Record<string, unknown>): Res => ({ status, body });

async function clarify(action: string, b: Record<string, unknown>, supLead: any, cust: any): Promise<Res> {
  if (action === 'clarify_answer') {
    if (!cust) return R(403, { error: 'forbidden' });
    const id = Number(b.id);
    if (!id) return R(400, { error: 'id_required' });
    const { data: row } = await admin.from('rfq_clarification').select('id,inquiry_id,kind,question,answered_at').eq('id', id).maybeSingle();
    if (!row) return R(404, { error: 'not_found' });
    const { data: inq } = await admin.from('inquiries').select('id,customer_id,category,emirate,status').eq('id', row.inquiry_id).maybeSingle();
    if (!inq || inq.customer_id !== cust.id) return R(403, { error: 'not_your_inquiry' });
    if (row.kind !== 'question') return R(400, { error: 'not_a_question' });
    if (row.answered_at) return R(409, { error: 'already_answered' });
    const { data: me } = await admin.from('customers').select('full_name').eq('id', cust.id).maybeSingle();
    const text = stripContact(b.text, [me?.full_name]);
    if (text.replace(/\[removed\]/g, '').trim().length < 1) return R(400, { error: 'text_required' });
    const { error } = await admin.from('rfq_clarification').update({ answer: text, answered_at: new Date().toISOString() }).eq('id', id).is('answered_at', null);
    if (error) return R(500, { error: 'save_failed' });
    const notified = await notifyMatched(String(row.inquiry_id), inq, 'clarification_answered',
      'The customer answered a question on a request you were invited to quote',
      'On the ' + (inq.category || 'request') + (inq.emirate ? ' job in ' + inq.emirate : ' job') + ' you were invited to quote, a supplier asked:\n\n"' + String(row.question || '') + '"\n\nThe customer answered:\n\n"' + text + '"\n\nThis answer is now part of the request. Log in to your QuotesDone supplier portal to see the full request and quote.');
    return R(200, { ok: true, id, answer: text, notified });
  }

  const inquiry_id = String(b.inquiry_id || '');
  if (!inquiry_id) return R(400, { error: 'inquiry_id_required' });
  const { data: inq } = await admin.from('inquiries').select('id,customer_id,category,emirate,status').eq('id', inquiry_id).maybeSingle();
  if (!inq) return R(404, { error: 'not_found' });
  const { data: matches } = await admin.from('inquiry_matches').select('id,supplier_id').eq('inquiry_id', inquiry_id).order('id', { ascending: true });
  const order = [...new Set((matches || []).map((m: { supplier_id: number }) => Number(m.supplier_id)))];
  const isOwner = !!cust && inq.customer_id === cust.id;
  const isMatched = !!supLead && order.includes(Number(supLead.id));
  if (!isOwner && !isMatched) return R(403, { error: 'forbidden' });

  if (action === 'clarify_ask') {
    if (!isMatched) return R(403, { error: 'not_matched' });
    if (supLead.banned === true) return R(403, { error: 'suspended' });
    if (['cancelled', 'closed', 'completed'].includes(String(inq.status))) return R(409, { error: 'inquiry_closed' });
    const text = stripContact(b.text, [supLead.company_name]);
    if (text.replace(/\[removed\]/g, '').trim().length < 3) return R(400, { error: 'text_required' });
    // Five a day per supplier per request: enough to scope a job, too few to turn it into a chat.
    const since = new Date(Date.now() - 24 * 3600e3).toISOString();
    const { count } = await admin.from('rfq_clarification').select('id', { count: 'exact', head: true }).eq('inquiry_id', inquiry_id).eq('supplier_id', supLead.id).gte('asked_at', since);
    if ((count || 0) >= 5) return R(429, { error: 'too_many_questions' });
    const source = b.source === 'rfq_flag' ? 'rfq_flag' : 'portal';
    const { data: ins, error } = await admin.from('rfq_clarification').insert({ inquiry_id, supplier_id: supLead.id, kind: 'question', question: text, source }).select('id').single();
    if (error || !ins) return R(500, { error: 'save_failed' });
    const label = letterOf(order.indexOf(Number(supLead.id)));
    try {
      const { data: c } = await admin.from('customers').select('email,full_name,locale').eq('id', inq.customer_id).maybeSingle();
      if (c?.email && /@/.test(c.email)) {
        const ar = String(c.locale || '') === 'ar';
        await notify([{ type: 'clarification_requested', to_email: c.email, to_role: 'customer', inquiry_id, channel: 'email', status: 'queued',
          subject: ar ? 'لدى أحد الموردين سؤال عن طلبك' : 'A supplier has a question about your request',
          body: ar
            ? ('مرحبًا ' + (c.full_name || '') + '،\n\nسأل ' + label.replace('Supplier', 'المورّد') + ' عن طلبك (' + (inq.category || '') + '):\n\n«' + text + '»\n\nافتح طلبك في QuotesDone وأجب هناك — تصل إجابتك إلى جميع الموردين المدعوين دون اسمك أو رقمك.')
            : ('Hi ' + (c.full_name || 'there') + ',\n\n' + label + ' asked about your ' + (inq.category || '') + ' request:\n\n"' + text + '"\n\nOpen your request on QuotesDone and answer it there. Your answer reaches every invited supplier without your name or number, so they can all quote the same scope.') }]);
      }
    } catch (_e) { /* the question is stored either way; the portal shows it on the next load */ }
    return R(200, { ok: true, id: ins.id, supplier_label: label });
  }

  if (action === 'clarify_list') {
    const { data: rows, error } = await admin.from('rfq_clarification').select('id,supplier_id,kind,question,answer,asked_at,answered_at').eq('inquiry_id', inquiry_id).order('asked_at', { ascending: true }).limit(200);
    if (error) return R(500, { error: 'load_failed' });
    const visible = (rows || []).filter((r: any) => isOwner || r.kind === 'note' || Number(r.supplier_id) === Number(supLead?.id) || r.answered_at);
    const items = visible.map((r: any) => ({
      id: r.id, kind: r.kind, question: r.question ?? null, answer: r.answer ?? null, asked_at: r.asked_at, answered_at: r.answered_at ?? null,
      supplier_label: r.supplier_id == null ? null : letterOf(order.indexOf(Number(r.supplier_id))),
      mine: !isOwner && Number(r.supplier_id) === Number(supLead?.id),
    }));
    return R(200, { ok: true, role: isOwner ? 'customer' : 'supplier', items });
  }
  return R(400, { error: 'unknown action' });
}

// The same notification path matchAndNotify uses for the original invitation: one queued email
// per matched supplier, addressed to the lead, carrying only text that has been through the
// stripper above. Returns how many were queued so the caller can say so truthfully.
async function notifyMatched(inquiry_id: string, _inq: unknown, type: string, subject: string, body: string): Promise<number> {
  const { data: ms } = await admin.from('inquiry_matches').select('supplier_id').eq('inquiry_id', inquiry_id);
  const ids = [...new Set((ms || []).map((m: { supplier_id: number }) => Number(m.supplier_id)).filter(Boolean))];
  if (!ids.length) return 0;
  const { data: ls } = await admin.from('leads').select('id,email,claimed_by,banned').in('id', ids);
  const rows = (ls || []).filter((l: any) => l.banned !== true).map((l: any) => ({ id: l.id, to: String(l.claimed_by || l.email || '') })).filter((l) => /@/.test(l.to))
    .map((l) => ({ type, to_email: l.to, to_role: 'supplier', lead_id: l.id, inquiry_id, channel: 'email', status: 'queued', subject, body }));
  await notify(rows);
  return rows.length;
}

Deno.serve(observe('messages_api', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    const body = await req.json().catch(() => ({})); const action = String(body.action || '');

    const { data: supLead } = await admin.from('leads').select('id,company_name,banned').eq('claimed_by', email).maybeSingle();
    // phone_verified is read here because waPhoneOf gates the WhatsApp channel on it — see the note
    // above otherChannels. Selecting `phone` without it is what made an unverified number usable.
    const { data: cust } = await admin.from('customers').select('id,banned,phone,email,phone_verified').eq('email', email).maybeSingle();

    if (action === 'threads') {
      const out: any[] = [];
      const push = async (inquiry_id: string, supplier_id: number, counterpart: string, subject: string, senderUnread: 'customer'|'supplier') => {
        const { data: th } = await admin.from('chat_threads').select('status').eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).maybeSingle();
        const { data: last } = await admin.from('messages').select('body,created_at').eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).eq('blocked', false).order('created_at', { ascending: false }).limit(1).maybeSingle();
        const { count } = await admin.from('messages').select('id', { count: 'exact', head: true }).eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).eq('sender', senderUnread).eq(senderUnread === 'customer' ? 'read_by_supplier' : 'read_by_customer', false).eq('blocked', false);
        out.push({ channel: 'chat', inquiry_id, supplier_id, counterpart, subject, chat_status: th?.status || 'none', last: last?.body || null, last_at: last?.created_at || null, unread: count || 0 });
      };
      if (supLead) {
        const { data: tx } = await admin.from('transactions').select('inquiry_id, inquiries(category,summary)').eq('supplier_id', supLead.id).not('revealed_at', 'is', null);
        for (const t of (tx || [])) await push(t.inquiry_id, supLead.id, 'Customer', (t as any).inquiries?.summary || (t as any).inquiries?.category || 'Inquiry', 'customer');
        out.sort((a, b) => String(b.last_at || '').localeCompare(String(a.last_at || '')));
        return J({ ok: true, role: 'supplier', threads: out });
      }
      if (cust) {
        const { data: tx } = await admin.from('transactions').select('inquiry_id, supplier_id, inquiries(category,summary)').eq('customer_id', cust.id).not('revealed_at', 'is', null);
        for (const t of (tx || [])) { const { data: lead } = await admin.from('leads').select('company_name').eq('id', t.supplier_id).maybeSingle(); await push(t.inquiry_id, t.supplier_id, lead?.company_name || 'Supplier', (t as any).inquiries?.summary || (t as any).inquiries?.category || 'Inquiry', 'supplier'); }
        for (const c of (await otherChannels(cust))) out.push(c);
        out.sort((a, b) => String(b.last_at || '').localeCompare(String(a.last_at || '')));
        return J({ ok: true, role: 'customer', threads: out, channels: CHANNELS });
      }
      return J({ ok: true, role: null, threads: [] });
    }

    // ── OPENING ONE OF THE OTHER THREE CHANNELS ────────────────────────────────────────────────
    // MEASURED 13 Aug 2026, as the customer: `threads` listed "QuotesDone on WhatsApp" (10 messages)
    // and "QuotesDone by e-mail" (1 unread) for djzaino@outlook.com, and NOTHING could open either.
    // otherChannels() returns a SUMMARY per channel with inquiry_id: null — and the only reader of a
    // thread was `action: 'thread'`, which rejects a null inquiry_id at the door (400). So the count
    // was served, the unread badge counted it, the row was clickable, and the messages behind it
    // were unreachable from any customer-authed endpoint. A finished capability with no entry point.
    //
    // THE JOIN KEY IS THE CUSTOMER'S OWN IDENTITY, exactly as otherChannels already does it: their
    // own phone on wa_messages, their own e-mail on inbound_messages, their own customer_id on
    // customer_calls. Nothing is joined through a supplier, so this cannot leak the identity the
    // reveal fee sells — the same safety story as the list it opens.
    if (action === 'channel_thread') {
      if (!cust) return J({ error: 'forbidden' }, 403);
      const channel = String(body.channel || '');
      if (channel === 'whatsapp') {
        const phone = waPhoneOf(cust);
        if (phone.length < 9) return J({ ok: true, channel, counterpart: 'QuotesDone on WhatsApp', messages: [], note: 'Your WhatsApp history appears here once your mobile number is verified on your account — we only match this channel to a number you have proven you hold.' });
        const { data: wa } = await admin.from('wa_messages')
          .select('id,wa_from,wa_to,inbound,reply,created_at').order('created_at', { ascending: false }).limit(200);
        const mine = (wa || []).filter((m: Record<string, unknown>) => digits(m.wa_from) === phone || digits(m.wa_to) === phone);
        // One row holds BOTH sides of the exchange: `inbound` is what the customer sent us and
        // `reply` is what we sent back. Rendering it as one message would attribute their own words
        // to us, so the row is split into the two messages it actually is.
        const messages: Record<string, unknown>[] = [];
        for (const m of mine.slice().reverse()) {
          if (m.inbound) messages.push({ id: String(m.id) + ':in', sender: 'customer', body: clip(m.inbound, 4000), created_at: m.created_at });
          if (m.reply) messages.push({ id: String(m.id) + ':out', sender: 'quotesdone', body: clip(m.reply, 4000), created_at: m.created_at });
        }
        return J({ ok: true, channel, counterpart: 'QuotesDone on WhatsApp', chat_status: 'open', messages });
      }
      if (channel === 'email') {
        // Same strict address shape as otherChannels — an address that cannot appear in a PostgREST
        // `or` filter unambiguously is not queried at all.
        const cEmail = String((cust as Record<string, unknown>).email || '').toLowerCase();
        if (!/^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$/.test(cEmail)) return J({ ok: true, channel, counterpart: 'QuotesDone by e-mail', messages: [] });
        const { data: em } = await admin.from('inbound_messages')
          .select('id,from_email,to_email,subject,ai_summary,body,created_at,replied_at,owner_role')
          .or(`from_email.eq.${cEmail},to_email.eq.${cEmail}`)
          .order('created_at', { ascending: true }).limit(50);
        const messages = (em || []).filter(isCustomerCorrespondence).map((r: Record<string, unknown>) => ({
          id: String(r.id), sender: String(r.from_email || '').toLowerCase() === cEmail ? 'customer' : 'quotesdone',
          subject: r.subject || null, body: clip(r.body || r.ai_summary, 8000), created_at: r.created_at,
          replied_at: r.replied_at || null,
        }));
        // Opening the thread is what "read" means on e-mail — there is no per-message read flag on
        // inbound_messages, and `unread` is computed from replied_at, which only WE can set. So the
        // badge is reported here rather than cleared: claiming it read would be a write we cannot
        // honour, and a badge that clears without the thing behind it changing is a lie.
        return J({ ok: true, channel, counterpart: 'QuotesDone by e-mail', chat_status: 'open', messages, unread_note: 'Unread here means our team has not replied yet.' });
      }
      if (channel === 'call') {
        const { data: calls } = await admin.from('customer_calls')
          .select('id,direction,status,started_at,duration_s,summary,inquiry_id')
          .eq('customer_id', cust.id).order('started_at', { ascending: true }).limit(50);
        const messages = (calls || []).map((c: Record<string, unknown>) => ({
          id: String(c.id), sender: c.direction === 'inbound' ? 'customer' : 'quotesdone',
          body: clip(c.summary || (String(c.direction || '') + ' call, ' + String(c.status || '')), 4000),
          created_at: c.started_at, duration_s: c.duration_s ?? null, inquiry_id: c.inquiry_id || null,
        }));
        return J({ ok: true, channel, counterpart: 'Calls', chat_status: 'open', messages });
      }
      return J({ error: 'unknown channel' }, 400);
    }

    // Pre-reveal Q&A is keyed on the inquiry alone, never on a supplier the customer has paid to
    // see, so it is answered before the reveal gate below.
    if (action === 'clarify_list' || action === 'clarify_ask' || action === 'clarify_answer') {
      const res = await clarify(action, body, supLead, cust);
      return J(res.body, res.status);
    }

    const inquiry_id = String(body.inquiry_id || ''); const supplier_id = Number(body.supplier_id || 0);
    if (!inquiry_id || !supplier_id) return J({ error: 'missing inquiry_id/supplier_id' }, 400);
    const rev = await revealed(inquiry_id, supplier_id);
    let role: 'customer' | 'supplier' | null = null;
    if (supLead && supLead.id === supplier_id) role = 'supplier';
    else if (cust && rev && rev.customer_id === cust.id) role = 'customer';
    if (!role) return J({ error: 'forbidden' }, 403);
    if (!rev) return J({ ok: true, locked: true, messages: [], note: 'Messaging unlocks after the quote is revealed.' });
    const banned = (role === 'supplier' ? supLead?.banned : cust?.banned) === true;
    const { data: th } = await admin.from('chat_threads').select('status,reason').eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).maybeSingle();
    // POST-REVEAL CHAT OPENS ON FIRST TOUCH. It used to wait on "Admin → Agents → approvals", a
    // queue the 7-8 Sep rulings removed, so a paid reveal led to a chat nobody could ever open. A
    // transactions row is proof the customer paid to know this supplier, which is the only thing
    // the gate existed to protect. A thread closed for a policy breach stays shut.
    let status = th?.status || 'none';
    if (status !== 'open' && status !== 'banned') {
      await admin.from('chat_threads').upsert({ inquiry_id, supplier_id, customer_id: rev.customer_id, status: 'open', reason: 'opened on reveal', requested_by: role }, { onConflict: 'inquiry_id,supplier_id' });
      status = 'open';
    }

    // Kept for callers that still ask first: the answer is simply the thread's state.
    if (action === 'request_chat') {
      if (banned) return J({ error: 'Your account is suspended.' }, 403);
      if (status === 'banned') return J({ error: 'This chat is closed due to a policy violation.' }, 403);
      return J({ ok: true, status: 'open', note: 'Chat is open.' });
    }

    if (action === 'thread') {
      if (status !== 'open') return J({ ok: true, locked: true, chat_status: status, warning: WARNING, messages: [], note: status === 'requested' ? 'Your chat request is pending review.' : (status === 'banned' ? 'This chat is closed due to a policy violation.' : 'No chat open yet. Use the Ask / request a chat button to start.') });
      const { data: msgs } = await admin.from('messages').select('id,sender,body,created_at').eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).eq('blocked', false).order('created_at', { ascending: true }).limit(500);
      if (role === 'customer') await admin.from('messages').update({ read_by_customer: true }).eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).eq('sender', 'supplier').eq('read_by_customer', false);
      else await admin.from('messages').update({ read_by_supplier: true }).eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).eq('sender', 'customer').eq('read_by_supplier', false);
      let counterpart = 'Customer'; if (role === 'customer') { const { data: lead } = await admin.from('leads').select('company_name').eq('id', supplier_id).maybeSingle(); counterpart = lead?.company_name || 'Supplier'; }
      return J({ ok: true, role, counterpart, chat_status: 'open', warning: WARNING, messages: msgs || [] });
    }

    if (action === 'send') {
      if (banned) return J({ error: 'Your account is suspended for sharing contact details off-platform.' }, 403);
      if (status !== 'open') return J({ error: 'Chat is not open. Request a chat first.', chat_status: status }, 403);
      const text = clip(body.body, 2000); if (!text) return J({ error: 'empty' }, 400);

      // §16 A DOCUMENT INSIDE THE CONVERSATION. The path is a storage path the caller already
      // uploaded through the same buckets the rest of the portal uses; only its SHAPE is trusted
      // here, never its contents, and it is stored on the message rather than merged into the body
      // so the contact detector above still sees the text a human wrote and nothing else.
      const attach = clip(body.attachment_path, 400);
      const attachOk = attach.length > 0 && /^[A-Za-z0-9][A-Za-z0-9/_.-]{2,}$/.test(attach) && !attach.includes('..');
      const attachName = clip(body.attachment_name, 180) || (attachOk ? attach.split('/').pop() || 'attachment' : '');
      const { data: m, error } = await admin.from('messages').insert({ inquiry_id, supplier_id, customer_id: rev.customer_id, sender: role, body: text, attachment_path: attachOk ? attach : null, read_by_customer: role === 'customer', read_by_supplier: role === 'supplier' }).select('id,sender,body,created_at,attachment_path').maybeSingle();
      if (error) return J({ error: error.message }, 500);
      // The vault is the index of everything the customer holds, so a file dropped into a chat has
      // to appear there too — otherwise §14's "find the warranty document" cannot find one that
      // arrived by chat. ref_table='messages' is the link documents already models for every other
      // origin (inquiries, leads, quotes). Best-effort: a failed registration must not lose the
      // message that carried the file.
      if (attachOk && m) {
        try {
          await admin.from('documents').insert({ bucket: clip(body.attachment_bucket, 60) || 'uploads', path: attach, file_name: attachName,
            kind: clip(body.attachment_kind, 40) || 'chat_attachment', ref_table: 'messages', ref_id: String(m.id), status: 'received' });
        } catch (_e) { /* the message is delivered either way */ }
      }
      try {
        if (role === 'customer') { const { data: lead } = await admin.from('leads').select('claimed_by,company_name').eq('id', supplier_id).maybeSingle(); if (lead?.claimed_by) await notify([{ type: 'new_message', to_email: lead.claimed_by, to_role: 'supplier', inquiry_id, subject: 'New message from a customer on QuotesDone', body: 'You have a new message on an open project chat. Log in to your supplier portal to reply.' }]); }
        else { const { data: c } = await admin.from('customers').select('email').eq('id', rev.customer_id).maybeSingle(); const { data: lead } = await admin.from('leads').select('company_name').eq('id', supplier_id).maybeSingle(); if (c?.email) await notify([{ type: 'new_message', to_email: c.email, to_role: 'customer', inquiry_id, subject: 'New message from ' + (lead?.company_name || 'a supplier'), body: 'You have a new message on your open project chat. Log in to reply.' }]); }
      } catch (_e) {}
      return J({ ok: true, message: m });
    }

    return J({ error: 'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
