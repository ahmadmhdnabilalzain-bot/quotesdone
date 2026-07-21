// qa_api - anonymized pre-reveal Q&A between customer and supplier. Contact details stripped both ways.
// Auth: JWT -> email. Customer asks (by quote), supplier answers (by question id). No identities exchanged.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function notify(rows: Record<string, unknown>[]) { try { if (rows.length) await admin.from('notifications').insert(rows); } catch (_e) {} }
function stripContact(t: string){
  let s = String(t || '');
  s = s.replace(/[\w.+-]+@[\w-]+\.[\w.-]+/g, '[contact hidden]');
  s = s.replace(/\b(?:https?:\/\/|www\.)\S+/gi, '[link hidden]');
  s = s.replace(/\+?\d[\d\s\-()]{6,}\d/g, '[number hidden]');
  s = s.replace(/\b(whats\s?app|whatsapp|telegram|instagram|\bIG\b|snapchat)\b/gi, '[contact hidden]');
  return s.trim();
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    const { data: supLead } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
    const { data: cust } = await admin.from('customers').select('id').eq('email', email).maybeSingle();
    const body = await req.json().catch(() => ({})); const action = String(body.action || '');

    // CUSTOMER: ask about a quote (pre-reveal only)
    if (action === 'ask') {
      if (!cust) return J({ error: 'forbidden' }, 403);
      const { data: q } = await admin.from('quotes').select('id,inquiry_id,supplier_id').eq('id', String(body.quote_id||'')).maybeSingle();
      if (!q) return J({ error: 'Quote not found' }, 404);
      const { data: inq } = await admin.from('inquiries').select('id,customer_id,summary').eq('id', q.inquiry_id).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const { data: tx } = await admin.from('transactions').select('id').eq('inquiry_id', q.inquiry_id).eq('supplier_id', q.supplier_id).maybeSingle();
      if (tx) return J({ error: 'You have revealed this supplier — use Messages to talk directly.' }, 400);
      const { count } = await admin.from('questions').select('id', { count: 'exact', head: true }).eq('inquiry_id', q.inquiry_id).eq('supplier_id', q.supplier_id).eq('customer_id', cust.id);
      if ((count || 0) >= 3) return J({ error: 'You have reached the limit of pre-reveal questions for this supplier.' }, 429);
      const question = stripContact(String(body.question||'')).slice(0, 500);
      if (!question) return J({ error: 'Empty question' }, 400);
      const { data: ins } = await admin.from('questions').insert({ inquiry_id: q.inquiry_id, supplier_id: q.supplier_id, customer_id: cust.id, question }).select('id').maybeSingle();
      const { data: lead } = await admin.from('leads').select('claimed_by').eq('id', q.supplier_id).maybeSingle();
      if (lead?.claimed_by) await notify([{ type: 'new_question', to_email: lead.claimed_by, to_role: 'supplier', inquiry_id: q.inquiry_id, subject: 'A customer asked a question about your quote', body: 'A customer has a question about a job you quoted on QuotesDone (before revealing). Log in to your supplier portal to answer — a quick reply helps win the job.' }]);
      return J({ ok: true, id: ins?.id });
    }

    // CUSTOMER: list Q&A for a quote
    if (action === 'list') {
      if (!cust) return J({ ok: true, items: [] });
      const { data: q } = await admin.from('quotes').select('id,inquiry_id,supplier_id').eq('id', String(body.quote_id||'')).maybeSingle();
      if (!q) return J({ ok: true, items: [] });
      const { data: inq } = await admin.from('inquiries').select('customer_id').eq('id', q.inquiry_id).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'forbidden' }, 403);
      const { data: items } = await admin.from('questions').select('id,question,answer,asked_at,answered_at').eq('inquiry_id', q.inquiry_id).eq('supplier_id', q.supplier_id).eq('customer_id', cust.id).order('asked_at', { ascending: true });
      return J({ ok: true, items: items || [] });
    }

    // SUPPLIER: inbox of questions
    if (action === 'inbox') {
      if (!supLead) return J({ ok: true, items: [] });
      const { data: qsAll } = await admin.from('questions').select('id,inquiry_id,question,answer,asked_at,answered_at').eq('supplier_id', supLead.id).order('asked_at', { ascending: false }).limit(50);
      const items: any[] = [];
      for (const x of (qsAll || [])) { const { data: inq } = await admin.from('inquiries').select('summary,category,emirate').eq('id', x.inquiry_id).maybeSingle(); items.push({ ...x, inquiry_summary: inq?.summary || inq?.category || 'Inquiry', emirate: inq?.emirate || null }); }
      return J({ ok: true, items, pending: items.filter((i)=>!i.answer).length });
    }

    // SUPPLIER: answer a question
    if (action === 'answer') {
      if (!supLead) return J({ error: 'forbidden' }, 403);
      const { data: qrow } = await admin.from('questions').select('id,supplier_id,inquiry_id,customer_id').eq('id', Number(body.id||0)).maybeSingle();
      if (!qrow || qrow.supplier_id !== supLead.id) return J({ error: 'not_found' }, 404);
      const answer = stripContact(String(body.answer||'')).slice(0, 800);
      if (!answer) return J({ error: 'Empty answer' }, 400);
      await admin.from('questions').update({ answer, answered_at: new Date().toISOString() }).eq('id', qrow.id);
      const { data: c } = await admin.from('customers').select('email').eq('id', qrow.customer_id).maybeSingle();
      if (c?.email) await notify([{ type: 'question_answered', to_email: c.email, to_role: 'customer', inquiry_id: qrow.inquiry_id, subject: 'A supplier answered your question', body: 'A supplier answered your question about a job on QuotesDone. Log in to read it and decide whether to reveal their contact.' }]);
      return J({ ok: true });
    }

    return J({ error: 'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
