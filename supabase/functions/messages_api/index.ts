// messages_api v4 - GATED customer<->supplier chat with hardened contact detection.
// Strong disclosure (email/link/UAE mobile/messaging app/solicitation) => block + ban + AED 10,000 (T&C) + owner alert.
// Borderline (a long number that might be a quantity) => message held + owner review, NO auto-ban.
// v4: llm() iterates single model (OpenRouter 'models' plural param was rejected).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
import { observe } from '../_shared/observe.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const clip = (v: unknown, n: number) => String(v ?? '').trim().slice(0, n);
const WARNING = 'Keep everything inside QuotesDone. Do NOT share phone numbers, emails, links, WhatsApp/social handles, or try to move the deal off-platform. Sharing contact details breaches the Terms you accepted at sign-up and triggers an immediate account ban and a AED 10,000 penalty.';
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function ownerEmail(){ const v = await sec('admin_emails'); return String(v || 'management@quotesdone.com').split(',')[0].trim(); }
async function notify(rows: Record<string, unknown>[]) { try { if (rows.length) await admin.from('notifications').insert(rows); } catch (_e) {} }
const llm = makeLlm(SONNET_FIRST, { max: 700 }); // shared OpenRouter client (Sonnet-first ladder + 25s timeout)

// Hardened detector: normalises Arabic-Indic digits, spelled-out numbers, 'at'/'dot' obfuscation and spaced digits.
function detectContact(raw: string){
  const types = new Set<string>(); const strong = new Set<string>();
  const low = String(raw || '').toLowerCase();
  const ar = '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹';
  let t = low.replace(/[٠-٩۰-۹]/g, (c) => String(ar.indexOf(c) % 10));
  const nw: Record<string,string> = { zero:'0', oh:'0', one:'1', two:'2', three:'3', four:'4', five:'5', six:'6', seven:'7', eight:'8', nine:'9' };
  const spelled = t.replace(/\b(zero|oh|one|two|three|four|five|six|seven|eight|nine)\b/g, (w) => nw[w]);
  const collapse = (s: string) => s.replace(/(\d)[\s.\-_()]+(?=\d)/g, '$1');
  const dt = collapse(t), ds = collapse(spelled);
  const emailObf = t.replace(/\s*[\(\[]?\s*at\s*[\)\]]?\s*/g, '@').replace(/\s*[\(\[]?\s*dot\s*[\)\]]?\s*/g, '.');
  const emailRe = /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/;
  if (emailRe.test(t) || emailRe.test(emailObf)) { types.add('email'); strong.add('email'); }
  if (/(https?:\/\/|www\.)\S+/.test(t) || /\b[a-z0-9-]{2,}\.(com|net|ae|org|io|co|me|info|biz|app|link)\b/.test(t)) { types.add('link'); strong.add('link'); }
  const uaeRe = /(?:\+?971|00971|0)?5\d{8}/;
  if (uaeRe.test(dt) || uaeRe.test(ds)) { types.add('phone'); strong.add('phone'); }
  else if (/\d{9,}/.test(dt) || /\d{9,}/.test(ds)) { types.add('phone_generic'); } // borderline only
  if (/(whats\s*app|whatsapp|wa\.me|telegram|t\.me|viber|botim|snapchat|skype|instagram)/.test(t)) { types.add('messaging_app'); strong.add('messaging_app'); }
  if (/(call me|whatsapp me|my number|my mobile|my cell|reach me on|contact me directly|outside the platform|off[\s-]?platform|deal directly|my email|email me at|text me on|here is my number|this is my number|save my number)/.test(t)) { types.add('solicitation'); strong.add('solicitation'); }
  if (/(^|\s)@[a-z0-9_.]{3,}/.test(low)) { types.add('handle'); } // borderline (could be '@ 5pm')
  return { hit: types.size > 0, types: [...types], strong: strong.size > 0 };
}

async function revealed(inquiry_id: string, supplier_id: number) {
  const { data } = await admin.from('transactions').select('id,customer_id').eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).not('revealed_at', 'is', null).maybeSingle();
  return data || null;
}
async function resolveCat(category: unknown){
  if (!category) return null; const c = String(category).toLowerCase().trim(); if (!c) return null;
  const { data } = await admin.from('category_agents').select('slug,name').eq('active', true);
  for (const r of (data || [])) { const s = String(r.slug).toLowerCase(); const n = String(r.name).toLowerCase(); if (c === s || c.includes(s) || s.includes(c) || c.includes(n) || n.includes(c)) return r; }
  return null;
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
  const em = /^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$/.test(cEmail)
    ? (await admin.from('inbound_messages')
        .select('id,from_email,to_email,subject,ai_summary,body,created_at,replied_at')
        .or(`from_email.eq.${cEmail},to_email.eq.${cEmail}`)
        .order('created_at', { ascending: false }).limit(50)).data
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
          .select('id,from_email,to_email,subject,ai_summary,body,created_at,replied_at')
          .or(`from_email.eq.${cEmail},to_email.eq.${cEmail}`)
          .order('created_at', { ascending: true }).limit(50);
        const messages = (em || []).map((r: Record<string, unknown>) => ({
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
    const status = th?.status || 'none';

    if (action === 'request_chat') {
      const q = clip(body.question, 1500); if (!q) return J({ error: 'question required' }, 400);
      if (banned) return J({ error: 'Your account is suspended.' }, 403);
      if (status === 'open') return J({ ok: true, status: 'open', note: 'Chat is already open.' });
      if (status === 'requested') return J({ ok: true, status: 'requested', note: 'Your request is pending review.' });
      if (status === 'banned') return J({ error: 'This chat is closed due to a policy violation.' }, 403);
      const { data: inq } = await admin.from('inquiries').select('category,summary,emirate').eq('id', inquiry_id).maybeSingle();
      const cat = await resolveCat(inq?.category);
      const sys = 'You are the ' + (cat ? cat.name : 'category') + ' sales/expert agent for QuotesDone, a UAE B2B quotation marketplace. A ' + role + ' wants to ask the other party something on a revealed inquiry. Decide if THIS needs a direct human-to-human chat, or if you can answer it yourself. Generic / process / pricing-norm / scope-clarification questions: answer them. Only complex custom scoping, negotiation, scheduling/site coordination, or anything truly requiring the other party should open a chat. Reply ONLY JSON: {"needs_chat":true|false,"answer":"<your helpful answer if you can resolve it, else empty>"}.';
      const out = await llm(sys, 'Category: ' + (inq?.category || '') + '\nProject: ' + (inq?.summary || '') + (inq?.emirate ? ' (' + inq.emirate + ')' : '') + '\nAsked by: ' + role + '\nQuestion: ' + q, 700);
      let needs = true, answer = '';
      if (out) { const m = out.match(/\{[\s\S]*\}/); if (m) { try { const pj = JSON.parse(m[0]); needs = pj.needs_chat !== false; answer = String(pj.answer || ''); } catch (_e) {} } }
      if (!needs && answer) return J({ ok: true, answered: true, answer });
      await admin.from('chat_threads').upsert({ inquiry_id, supplier_id, customer_id: rev.customer_id, status: 'requested', reason: q, requested_by: role, category: inq?.category || null }, { onConflict: 'inquiry_id,supplier_id' });
      const agentKey = cat ? ('cat:' + cat.slug) : 'followup';
      try { await admin.from('agent_actions').insert({ agent: agentKey, kind: 'open_chat', status: 'pending', risk: 'low', title: 'Chat requested — ' + (cat ? cat.name : (inq?.category || 'inquiry')) + (inq?.emirate ? ' / ' + inq.emirate : ''), recommendation: 'open the chat only if a direct discussion is genuinely needed', target_table: 'chat_threads', target_id: inquiry_id + ':' + supplier_id, detail: { inquiry_id, supplier_id, by: role, category: inq?.category, question: q } }); } catch (_e) {}
      await notify([{ type: 'chat_request', to_email: await ownerEmail(), to_role: 'admin', inquiry_id, subject: 'Chat requested on QuotesDone — ' + (cat ? cat.name : (inq?.category || 'inquiry')), body: 'A ' + role + ' asked to open a direct chat on inquiry ' + inquiry_id + '.\n\nQuestion: ' + q + '\n\nThe ' + (cat ? cat.name : 'category') + ' agent judged it needs a human conversation. Approve or decline it in Admin → Agents → approvals.' }]);
      return J({ ok: true, requested: true, note: 'Sent for review. You will be notified if the chat is opened.' });
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
      const det = detectContact(text);
      if (det.hit) {
        await admin.from('chat_violations').insert({ inquiry_id, supplier_id, sender_role: role, sender_email: email, matched: det.types.join(',') + (det.strong ? '' : ' (borderline)'), body: text.slice(0, 1000) });
        await admin.from('messages').insert({ inquiry_id, supplier_id, customer_id: rev.customer_id, sender: role, body: '[blocked]', redacted_body: text.slice(0, 1000), blocked: true, flagged: true, read_by_customer: true, read_by_supplier: true });
        if (det.strong) {
          await admin.from('chat_threads').update({ status: 'banned', strikes: 1, closed_at: new Date().toISOString() }).eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id);
          if (role === 'supplier') await admin.from('leads').update({ banned: true, banned_reason: 'Shared contact info in chat (' + det.types.join(',') + ')' }).eq('id', supplier_id);
          else await admin.from('customers').update({ banned: true, banned_reason: 'Shared contact info in chat (' + det.types.join(',') + ')' }).eq('id', rev.customer_id);
          await notify([{ type: 'chat_violation', to_email: await ownerEmail(), to_role: 'admin', inquiry_id, subject: '⚠ Contact-info disclosure blocked on QuotesDone', body: 'A ' + role + ' (' + email + ') tried to share contact info (' + det.types.join(', ') + ') on inquiry ' + inquiry_id + '. The message was blocked, the chat closed, and the account auto-suspended per the Terms (AED 10,000 penalty applies). Review in Admin.\n\nAttempted: ' + text.slice(0, 400) }]);
          return J({ ok: false, blocked: true, warning: 'Your message was blocked and your account has been suspended. ' + WARNING });
        } else {
          await notify([{ type: 'chat_review', to_email: await ownerEmail(), to_role: 'admin', inquiry_id, subject: 'Possible contact info held for review on QuotesDone', body: 'A ' + role + ' (' + email + ') sent a message on inquiry ' + inquiry_id + ' that looks like it may contain a phone number or contact detail (borderline match: ' + det.types.join(', ') + '). It was held and NOT delivered, and the account was NOT auto-suspended. Review in Admin and ban manually if it was a real disclosure attempt.\n\nMessage: ' + text.slice(0, 400) }]);
          return J({ ok: false, blocked: true, review: true, warning: 'Your message looks like it may include a phone number or contact detail, so it was held. Keep all details on QuotesDone. If that was a quantity or project number, please write it in words and resend.' });
        }
      }
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
