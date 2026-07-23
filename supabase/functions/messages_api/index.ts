// messages_api v4 - GATED customer<->supplier chat with hardened contact detection.
// Strong disclosure (email/link/UAE mobile/messaging app/solicitation) => block + ban + AED 10,000 (T&C) + owner alert.
// Borderline (a long number that might be a quantity) => message held + owner review, NO auto-ban.
// v4: llm() iterates single model (OpenRouter 'models' plural param was rejected).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    const body = await req.json().catch(() => ({})); const action = String(body.action || '');

    const { data: supLead } = await admin.from('leads').select('id,company_name,banned').eq('claimed_by', email).maybeSingle();
    const { data: cust } = await admin.from('customers').select('id,banned').eq('email', email).maybeSingle();

    if (action === 'threads') {
      const out: any[] = [];
      const push = async (inquiry_id: string, supplier_id: number, counterpart: string, subject: string, senderUnread: 'customer'|'supplier') => {
        const { data: th } = await admin.from('chat_threads').select('status').eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).maybeSingle();
        const { data: last } = await admin.from('messages').select('body,created_at').eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).eq('blocked', false).order('created_at', { ascending: false }).limit(1).maybeSingle();
        const { count } = await admin.from('messages').select('id', { count: 'exact', head: true }).eq('inquiry_id', inquiry_id).eq('supplier_id', supplier_id).eq('sender', senderUnread).eq(senderUnread === 'customer' ? 'read_by_supplier' : 'read_by_customer', false).eq('blocked', false);
        out.push({ inquiry_id, supplier_id, counterpart, subject, chat_status: th?.status || 'none', last: last?.body || null, last_at: last?.created_at || null, unread: count || 0 });
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
        out.sort((a, b) => String(b.last_at || '').localeCompare(String(a.last_at || '')));
        return J({ ok: true, role: 'customer', threads: out });
      }
      return J({ ok: true, role: null, threads: [] });
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
      const { data: m, error } = await admin.from('messages').insert({ inquiry_id, supplier_id, customer_id: rev.customer_id, sender: role, body: text, read_by_customer: role === 'customer', read_by_supplier: role === 'supplier' }).select('id,sender,body,created_at').maybeSingle();
      if (error) return J({ error: error.message }, 500);
      try {
        if (role === 'customer') { const { data: lead } = await admin.from('leads').select('claimed_by,company_name').eq('id', supplier_id).maybeSingle(); if (lead?.claimed_by) await notify([{ type: 'new_message', to_email: lead.claimed_by, to_role: 'supplier', inquiry_id, subject: 'New message from a customer on QuotesDone', body: 'You have a new message on an open project chat. Log in to your supplier portal to reply.' }]); }
        else { const { data: c } = await admin.from('customers').select('email').eq('id', rev.customer_id).maybeSingle(); const { data: lead } = await admin.from('leads').select('company_name').eq('id', supplier_id).maybeSingle(); if (c?.email) await notify([{ type: 'new_message', to_email: c.email, to_role: 'customer', inquiry_id, subject: 'New message from ' + (lead?.company_name || 'a supplier'), body: 'You have a new message on your open project chat. Log in to reply.' }]); }
      } catch (_e) {}
      return J({ ok: true, message: m });
    }

    return J({ error: 'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
