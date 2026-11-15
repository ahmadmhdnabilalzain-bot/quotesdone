import { siteCors } from '../_shared/site_origins.ts';
// messages_api — the customer's unified inbox, the post-reveal customer<->supplier chat, and the
// pre-reveal anonymous Q&A (clarify_*).
//
// 14 Sep 2026: post-reveal chat no longer waits on an approval queue and no longer bans for sharing
// contact details. After a paid reveal both parties already hold each other's contact details, so
// the detector that blocked them and auto-suspended accounts policed a secret that no longer
// existed; and the "Admin → Agents → approvals" queue it routed chat requests to was removed by the
// founder's 7-8 Sep rulings (two seats, no approval queue). Contact stripping now applies only
// where anonymity is the product: the pre-reveal Q&A below.
import { SITE_KEPT_FOR_SUPPLIERS, forSuppliers, keptNotice, keptPartsOf, readOwner } from '../supplier_api/what_a_supplier_receives.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';

import { observe } from '../_shared/observe.ts';
import { isCustomerCorrespondence } from '../_shared/customer_mail.ts';
import { asLocale } from '../_shared/registered_locale.ts';
import { requestDelivery } from '../_shared/deliver.ts';
// The supplier's alias on this job is the same one its own quotation prints (audit 21 Sep 2026, finding 29).
import { customerSupplierLetters, jobAlias } from '../_shared/quote_labels.ts';
import { HELD_NOTICE, hasArabic, holdForEnglish, mailMatched, supplierMail } from '../_shared/supplier_english.ts';
import { buildSupplierMailbox } from './mailbox.ts';
import { stripContact, stripSupplierQuestion } from './strip_contact.ts';
import { sanctionedLead } from '../_shared/sanctioned.ts';
import { refusalBody, signedInUser } from '../_shared/signed_in_user.ts';
import { isClosedRequest } from '../_shared/request_closed.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const clip = (v: unknown, n: number) => String(v ?? '').trim().slice(0, n);
const WARNING = 'Messages here are kept on record for both of you. Please keep them about this job.';

async function notify(rows: Record<string, unknown>[]) { try { if (rows.length) await requestDelivery(admin, rows); } catch (_e) {} }

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
// Identities are masked both ways: suppliers appear to the customer as "Supplier A/B..." by the letter his quotes carry
// (_shared/quote_labels.ts customerSupplierLetters; until 15 Nov 2026 the match order), to a supplier by the job's
// match-order aliases (jobAlias); the customer never appears at all, and contact details are stripped from
// both texts here, server-side, before anything is stored or emailed.
// The scrubber itself (STRIP, scrubName, stripContact) lives in ./strip_contact.ts since 3 Nov 2026.
type Res = { status: number; body: Record<string, unknown> };
const R = (status: number, body: Record<string, unknown>): Res => ({ status, body });

async function clarify(action: string, b: Record<string, unknown>, supLead: any, cust: any): Promise<Res> {
  if (action === 'clarify_answer') {
    if (!cust) return R(403, { error: 'forbidden' });
    const id = Number(b.id);
    if (!id) return R(400, { error: 'id_required' });
    const { data: row } = await admin.from('rfq_clarification').select('id,inquiry_id,kind,question,answered_at').eq('id', id).maybeSingle();
    if (!row) return R(404, { error: 'not_found' });
    const { data: inq } = await admin.from('inquiries').select('id,customer_id,category,emirate,status,project_id').eq('id', row.inquiry_id).maybeSingle();
    if (!inq || inq.customer_id !== cust.id) return R(403, { error: 'not_your_inquiry' });
    if (row.kind !== 'question') return R(400, { error: 'not_a_question' });
    if (row.answered_at) return R(409, { error: 'already_answered' });
    const { data: me } = await admin.from('customers').select('full_name').eq('id', cust.id).maybeSingle();
    // The PROJECT name too (3 Nov 2026, identity_never_leaks_before_reveal.mjs: "Site is ZZ Dune Heights Villa 2" reached
    // every matched supplier in 20 of 20 answers). No pattern recognises a project name; only knowing it removes it.
    const { data: proj } = inq.project_id ? await admin.from('projects').select('name').eq('id', inq.project_id).maybeSingle() : { data: null };
    const text = stripContact(b.text, [me?.full_name], [proj?.name]);
    if (text.replace(/\[removed\]/g, '').trim().length < 1) return R(400, { error: 'text_required' });
    // Every matched supplier reads this answer, and suppliers read English only (_shared/supplier_english.ts):
    // Arabic is kept as written and the supplier copy is held until the model route writes its English.
    const nowIso = new Date().toISOString();
    if (hasArabic(text)) {
      const { data: upd, error } = await admin.from('rfq_clarification').update({ answer_as_written: text, english_held_at: nowIso, answered_at: nowIso })
        .eq('id', id).is('answered_at', null).select('id');
      if (error) return R(500, { error: 'save_failed' });
      if (!upd?.length) return R(409, { error: 'already_answered' });
      try { await holdForEnglish(admin, id, text); } catch (_e) { return R(500, { error: 'save_failed' }); }
      return R(200, { ok: true, id, answer: text, notified: 0, held_for_english: true, notice: HELD_NOTICE.ar, notice_en: HELD_NOTICE.en });
    }
    // THE SUPPLIER COPY PASSES THE PORTAL'S GATE (13 Nov 2026, review of F2 item 1): stripContact knew the name and the project
    // only, so "The site is Villa 15, Al Barsha 2, near Mall of the Emirates." reached every matched supplier. The owner's
    // e-mail, phone, project, stated site and the old supplier's terms are seeds now (supplier_api/what_a_supplier_receives.ts).
    // What cannot be proved clean is kept for the customer, sent to nobody, and he is told why. (Arabic, above, is gated when
    // its English is written: _shared/supplier_english.ts finishEnglish.)
    const owner = await readOwner(admin, String(row.inquiry_id));
    const supplierCopy = forSuppliers(text, owner);
    if (!supplierCopy) {
      const { error } = await admin.from('rfq_clarification').update({ answer: SITE_KEPT_FOR_SUPPLIERS, answer_as_written: text, answered_at: nowIso }).eq('id', id).is('answered_at', null);
      if (error) return R(500, { error: 'save_failed' });
      const kept = keptPartsOf(text, owner); const n = keptNotice(kept);
      return R(200, { ok: true, id, answer: text, notified: 0, kept_from_suppliers: true, kept_parts: kept, notice: n.ar, notice_en: n.en });
    }
    const { error } = await admin.from('rfq_clarification').update({ answer: supplierCopy, answer_as_written: text, answered_at: nowIso }).eq('id', id).is('answered_at', null);
    if (error) return R(500, { error: 'save_failed' });
    const notified = await mailMatched(admin, String(row.inquiry_id), supplierMail('question', inq, row.question, supplierCopy));
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
    if (isClosedRequest(inq.status)) return R(409, { error: 'inquiry_closed' });
    // The supplier's question: contacts AND brands out before the customer reads it (strip_contact.ts stripSupplierQuestion).
    const text = stripSupplierQuestion(b.text, [supLead.company_name]);
    if (text.replace(/\[removed\]/g, '').trim().length < 3) return R(400, { error: 'text_required' });
    // Five a day per supplier per request: enough to scope a job, too few to turn it into a chat.
    const since = new Date(Date.now() - 24 * 3600e3).toISOString();
    const { count } = await admin.from('rfq_clarification').select('id', { count: 'exact', head: true }).eq('inquiry_id', inquiry_id).eq('supplier_id', supLead.id).gte('asked_at', since);
    if ((count || 0) >= 5) return R(429, { error: 'too_many_questions' });
    const source = b.source === 'rfq_flag' ? 'rfq_flag' : 'portal';
    const { data: ins, error } = await admin.from('rfq_clarification').insert({ inquiry_id, supplier_id: supLead.id, kind: 'question', question: text, source }).select('id').single();
    if (error || !ins) return R(500, { error: 'save_failed' });
    const label = jobAlias(order, Number(supLead.id));   // the supplier's own alias on this job, what the supplier is shown
    try {
      // THE CUSTOMER'S LETTER for this supplier (_shared/quote_labels.ts, 15 Nov 2026): the one his quote cards, quotation and
      // comparison use, so "Supplier B asked..." is the same Supplier B whose quote arrives later. Unreadable: no letter at all.
      const custLetter = (await customerSupplierLetters(admin, inquiry_id)).get(String(supLead.id));
      const custLabel = custLetter ? 'Supplier ' + custLetter : 'A supplier';
      const { data: c } = await admin.from('customers').select('email,full_name,locale').eq('id', inq.customer_id).maybeSingle();
      if (c?.email && /@/.test(c.email)) {
        // customers.locale through the one helper: 'ar-AE' is Arabic too, which the exact test missed.
        const ar = asLocale(c.locale) === 'ar';
        await notify([{ type: 'clarification_requested', to_email: c.email, to_role: 'customer', inquiry_id, channel: 'email', status: 'queued',
          subject: ar ? 'استفسار من أحد المورّدين بشأن طلبكم' : 'A supplier has a question about your request',
          body: ar
            ? ('حضرة ' + (c.full_name || 'العميل الكريم') + '،\n\nتحية طيبة وبعد،\n\nوردنا من ' + (custLetter ? 'المورّد ' + custLetter : 'أحد المورّدين') + ' استفسار بشأن طلبكم (' + (inq.category || '') + '):\n\n«' + text + '»\n\nيُرجى فتح طلبكم على QuotesDone والرد على الاستفسار من هناك؛ إذ يصل ردّكم إلى جميع المورّدين المدعوّين دون اسمكم أو رقمكم، ليسعّروا جميعًا النطاق نفسه.')
            : ('Hi ' + (c.full_name || 'there') + ',\n\n' + custLabel + ' asked about your ' + (inq.category || '') + ' request:\n\n"' + text + '"\n\nOpen your request on QuotesDone and answer it there. Your answer reaches every invited supplier without your name or number, so they can all quote the same scope.') }]);
      }
    } catch (_e) { /* the question is stored either way; the portal shows it on the next load */ }
    return R(200, { ok: true, id: ins.id, supplier_label: label });
  }

  if (action === 'clarify_list') {
    const { data: rows, error } = await admin.from('rfq_clarification').select('id,supplier_id,kind,question,answer,answer_as_written,english_held_at,asked_at,answered_at').eq('inquiry_id', inquiry_id).order('asked_at', { ascending: true }).limit(200);
    if (error) return R(500, { error: 'load_failed' });
    // A supplier never sees a text whose English is still held: it reads as not answered yet, and a held note is not
    // listed. The customer sees what they wrote, as written.
    const forSupplier = (r: any) => (r.english_held_at ? { ...r, answer: null, answered_at: null } : r);
    const shaped = (rows || []).map((r: any) => (isOwner ? { ...r, answer: r.answer_as_written ?? r.answer } : forSupplier(r)));
    const visible = shaped.filter((r: any) => isOwner || (r.kind === 'note' && r.answer) || Number(r.supplier_id) === Number(supLead?.id) || r.answered_at);
    // the customer reads each supplier by HIS letter (the quotes' one); a supplier reads the job's own aliases
    const custLetters = isOwner ? await customerSupplierLetters(admin, inquiry_id) : null;
    const labelOf = (sid: number) => custLetters ? (custLetters.has(String(sid)) ? 'Supplier ' + custLetters.get(String(sid)) : 'Supplier') : jobAlias(order, sid);
    const items = visible.map((r: any) => ({
      id: r.id, kind: r.kind, question: r.question ?? null, answer: r.answer ?? null, asked_at: r.asked_at, answered_at: r.answered_at ?? null,
      held_for_english: isOwner && !!r.english_held_at,
      supplier_label: r.supplier_id == null ? null : labelOf(Number(r.supplier_id)),
      mine: !isOwner && Number(r.supplier_id) === Number(supLead?.id),
    }));
    return R(200, { ok: true, role: isOwner ? 'customer' : 'supplier', items });
  }
  return R(400, { error: 'unknown action' });
}

Deno.serve(siteCors(observe('messages_api', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  // KEEP-WARM (resilience_ping, 14 Sep 2026). No auth, no DB, before anything else: the isolate is
  // what needs exercising, not a real answer. See the header of resilience_ping/index.ts.
  if (req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });
  try {
    // Local refusal first, a bounded auth call, and 503 (not 401) when auth is down — _shared/signed_in_user.ts.
    const who = await signedInUser(admin, req.headers.get('Authorization'));
    if (!who.ok) return J(refusalBody(who), who.status);
    const { email } = who;
    const body = await req.json().catch(() => ({})); const action = String(body.action || '');

    const { data: supLead } = await admin.from('leads').select('id,company_name,banned').eq('claimed_by', email).maybeSingle();
    // phone_verified is read here because waPhoneOf gates the WhatsApp channel on it — see the note
    // above otherChannels. Selecting `phone` without it is what made an unverified number usable.
    const { data: cust } = await admin.from('customers').select('id,banned,phone,email,phone_verified').eq('email', email).maybeSingle();

    // The supplier's Messages tab: the reveal gate and the revealed jobs' threads (./mailbox.ts).
    if (action === 'mailbox') {
      if (!supLead) return J({ error: 'forbidden', code: 'not_a_supplier' }, 403);
      return J(await buildSupplierMailbox(admin, Number(supLead.id)));
    }

    if (action === 'threads') {
      const out: any[] = [];
      // One thread's three reads run together, and every thread runs together: this was a strict
      // sequence — per revealed quote a leads lookup, then three queries, one after another — so the
      // unread badge the portal loads on every visit grew by four round trips per reveal. The list is
      // sorted by last_at below, so the order threads finish in does not matter.
      const push = async (inquiry_id: string, supplier_id: number, counterpart: string, subject: string, senderUnread: 'customer'|'supplier') => {
        const [{ data: th }, { data: last }, { count }] = await Promise.all([
          admin.from('chat_threads').select('status').eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).maybeSingle(),
          admin.from('messages').select('body,created_at').eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).eq('blocked', false).order('created_at', { ascending: false }).limit(1).maybeSingle(),
          admin.from('messages').select('id', { count: 'exact', head: true }).eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).eq('sender', senderUnread).eq(senderUnread === 'customer' ? 'read_by_supplier' : 'read_by_customer', false).eq('blocked', false),
        ]);
        out.push({ channel: 'chat', inquiry_id, supplier_id, counterpart, subject, chat_status: th?.status || 'none', last: last?.body || null, last_at: last?.created_at || null, unread: count || 0 });
      };
      if (supLead) {
        const { data: tx } = await admin.from('transactions').select('inquiry_id, inquiries(category,summary)').eq('supplier_id', supLead.id).not('revealed_at', 'is', null);
        await Promise.all((tx || []).map((t) => push(t.inquiry_id, supLead.id, 'Customer', (t as any).inquiries?.summary || (t as any).inquiries?.category || 'Inquiry', 'customer')));
        out.sort((a, b) => String(b.last_at || '').localeCompare(String(a.last_at || '')));
        return J({ ok: true, role: 'supplier', threads: out });
      }
      if (cust) {
        const { data: tx } = await admin.from('transactions').select('inquiry_id, supplier_id, inquiries(category,summary)').eq('customer_id', cust.id).not('revealed_at', 'is', null);
        const supIds = [...new Set((tx || []).map((t) => t.supplier_id).filter((v) => v != null))];
        const [{ data: leadRows }, others] = await Promise.all([
          supIds.length ? admin.from('leads').select('id,company_name').in('id', supIds) : Promise.resolve({ data: [] as { id: number; company_name: string | null }[] }),
          otherChannels(cust),
        ]);
        const nameOf = new Map((leadRows || []).map((l: any) => [Number(l.id), l.company_name]));
        await Promise.all((tx || []).map((t) => push(t.inquiry_id, t.supplier_id, nameOf.get(Number(t.supplier_id)) || 'Supplier', (t as any).inquiries?.summary || (t as any).inquiries?.category || 'Inquiry', 'supplier')));
        for (const c of others) out.push(c);
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
    // THE COUNTERPARTY, NOT ONLY THE CALLER (founder instruction 516, 18 Sep 2026). The `banned`
    // line below asks whether the person TYPING is banned; nothing asked whether the supplier being
    // typed AT is. So a customer opened a live thread with, and e-mailed, a sanctioned party. One
    // line here covers the thread open, the send and the notification that follows it.
    if (await sanctionedLead(admin, supplier_id)) return J({ error: 'This conversation is closed.', code: 'account_sanctioned' }, 403);
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
      if (banned) return J({ error: 'Your account is suspended.', code: 'account_suspended' }, 403);
      if (status === 'banned') return J({ error: 'This chat is closed due to a policy violation.', code: 'chat_banned' }, 403);
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
      if (banned) return J({ error: 'Your account is suspended for sharing contact details off-platform.', code: 'suspended_offplatform' }, 403);
      if (status !== 'open') return J({ error: 'Chat is not open. Request a chat first.', code: 'chat_not_open', chat_status: status }, 403);
      const text = clip(body.body, 2000); if (!text) return J({ error: 'empty', code: 'empty_message' }, 400);

      // §16 A DOCUMENT INSIDE THE CONVERSATION. The path is a storage path the caller already
      // uploaded through the same buckets the rest of the portal uses; only its SHAPE is trusted
      // here, never its contents, and it is stored on the message rather than merged into the body
      // so the contact detector above still sees the text a human wrote and nothing else.
      const attach = clip(body.attachment_path, 400);
      const attachOk = attach.length > 0 && /^[A-Za-z0-9][A-Za-z0-9/_.-]{2,}$/.test(attach) && !attach.includes('..');
      const attachName = clip(body.attachment_name, 180) || (attachOk ? attach.split('/').pop() || 'attachment' : '');
      const { data: m, error } = await admin.from('messages').insert({ inquiry_id, supplier_id, customer_id: rev.customer_id, sender: role, body: text, attachment_path: attachOk ? attach : null, read_by_customer: role === 'customer', read_by_supplier: role === 'supplier' }).select('id,sender,body,created_at,attachment_path').maybeSingle();
      if (error) { console.error('messages_api: send insert failed —', error.message); return J({ error: 'We could not send that message. Please try again.', code: 'message_send_failed' }, 500); }
      // A supplier who writes to the customer HAS contacted them (Supplier Agreement v9, cl. 11: respond
      // within 5 working days of the reveal). Measured 21 Sep 2026 (supplier audit, finding 36): sending
      // left the job "Respond by …" until the supplier also pressed "I have contacted the customer". The
      // message is the record; the acknowledgement follows it. `rev` is the reveal transaction itself.
      if (role === 'supplier' && rev?.id) {
        try { await admin.from('transactions').update({ supplier_ack_at: new Date().toISOString() }).eq('id', rev.id).is('supplier_ack_at', null); } catch (_e) { /* the message is delivered either way */ }
      }
      // The vault is the index of everything the customer holds, so a file dropped into a chat has
      // to appear there too — otherwise §14's "find the warranty document" cannot find one that
      // arrived by chat. ref_table='messages' is the link documents already models for every other
      // origin (inquiries, leads, quotes). Best-effort: a failed registration must not lose the
      // message that carried the file.
      if (attachOk && m) {
        try {
          // THE BUCKET IS OURS TO SET, NOT THE CALLER'S (field-tampering hardening, it_engineer 19 Oct
          // 2026, launch-checklist security pass). body.attachment_bucket let the sender name the bucket
          // the documents row points at. Nothing signs a ref_table='messages' row today, so this is not
          // live-exploitable, but the day fn_customer_document_refs grows a messages branch it would be a
          // cross-party file-read: send a chat attachment pointing at another customer's object in
          // agent-docs/finance-docs, then fetch it through customer_documents. The chat attachment always
          // lives in 'uploads' (see the SHAPE-only comment above); hard-code it.
          await admin.from('documents').insert({ bucket: 'uploads', path: attach, file_name: attachName,
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
  } catch (e) { console.error('messages_api: unhandled —', String((e as Error)?.message || e)); return J({ error: 'Something went wrong. Please try again.', code: 'unexpected_error' }, 500); }
})));
