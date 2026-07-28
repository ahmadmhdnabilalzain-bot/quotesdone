import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const FALLBACK_MODELS = ['anthropic/claude-sonnet-4.6','openai/gpt-4o','google/gemini-2.0-flash-001','meta-llama/llama-3.3-70b-instruct'];
const LIMIT_PER_HOUR = 40;

const FAQ = `You are the QuotesDone Help assistant — a friendly, concise in-app support agent for QuotesDone, a UAE marketplace where a customer describes what they need and verified suppliers send quotes.\n\nHOW QUOTESDONE WORKS (answer ONLY from this; never invent):\n- Posting a request is FREE for customers. You describe your job by voice, photo, drawing or text; our AI builds a clean request and sends it ANONYMOUSLY to matched, verified UAE suppliers.\n- Suppliers reply with quotes. You see all quotes side by side (shown as Supplier A, B, C) with price, lead time, etc. — without seeing who they are yet.\n- When you pick a quote, you pay a small REVEAL FEE to unlock that supplier's contact details and connect directly. Use the PRICING block for exact numbers.\n- It is a SOURCING tool: get fast, comparable quotes without visiting companies or repeating yourself. No site visits and no on-platform haggling.\n- Privacy: your details and the suppliers' details stay hidden until a reveal. We never sell your data.\n- You can cancel or close a request anytime before you reveal or complete it.\n- Quotes arrive as suppliers respond, usually within a day or two depending on the trade. If none come in, we keep sourcing and let you know.\n- Works in English and Arabic.\n\nBEHAVIOUR:\n- LANGUAGE: Detect the language of the customer's latest message and reply in THAT language. If they write in Arabic, reply in clear, natural, professional Modern Standard Arabic (fluent and correct). If they write in English, reply in English. Always mirror their latest language even if earlier messages used another.\n- Be brief, warm and clear — usually 1 to 4 sentences. No long essays, no markdown headings.\n- For questions about the customer's OWN requests, quotes or status, use ONLY the ACCOUNT DATA provided.\n- If you are unsure, or it is a complaint, a refund or dispute, a payment problem, or a legal/contract question that needs a person, say so and tell them to email info@quotesdone.com — the team will help.\n- Never give legal, financial or investment advice. Never invent prices, policies, timelines, or supplier names.\n- Only discuss QuotesDone. Politely decline unrelated topics.`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const msgs = Array.isArray(body.messages) ? body.messages.filter((m: any) => m && (m.role === 'user' || m.role === 'assistant') && typeof m.content === 'string').slice(-12) : [];
    if (!msgs.length) return J({ error: 'no message' }, 400);

    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    let user: any = null;
    if (jwt) { const { data: { user: u } } = await admin.auth.getUser(jwt); user = u; }
    if (!user || !user.email) {
      return J({ reply: 'Please sign in (or create your free account) to chat with support — it only takes your email and a 6-digit code. Then I can help with how things work, fees, and the status of your own requests. — يُرجى تسجيل الدخول أو إنشاء حساب مجاني للدردشة مع الدعم.', auth_required: true });
    }
    const who = user.email.toLowerCase();

    let acct = `ACCOUNT DATA: Signed in as ${who} (no requests yet).`;
    const { data: cust } = await admin.from('customers').select('id,full_name').eq('email', who).maybeSingle();
    if (cust) {
      const { data: inq } = await admin.from('inquiries').select('id,category,emirate,status,summary,outcome,created_at').eq('customer_id', cust.id).order('created_at', { ascending: false }).limit(8);
      const ids = (inq || []).map((i: any) => i.id);
      const qc: Record<string, number> = {};
      if (ids.length) { const { data: qs } = await admin.from('quotes').select('inquiry_id').in('inquiry_id', ids); (qs || []).forEach((q: any) => { qc[q.inquiry_id] = (qc[q.inquiry_id] || 0) + 1; }); }
      const lines = (inq || []).map((i: any) => `• Request #${i.id}: ${i.category || 'request'} in ${i.emirate || 'UAE'} — status "${i.status}"${i.outcome ? ' (' + i.outcome + ')' : ''} — ${qc[i.id] || 0} quote(s)${i.summary ? ' — ' + String(i.summary).slice(0, 90) : ''}`);
      acct = `ACCOUNT DATA: Signed in as ${cust.full_name || who}.\nTheir recent requests (${lines.length}):\n${lines.join('\n') || '(no requests yet)'}`;
    }

    const hourAgo = new Date(Date.now() - 3600e3).toISOString();
    const { count: used } = await admin.from('ai_usage').select('id', { count: 'exact', head: true }).eq('email', who).gte('created_at', hourAgo);
    if ((used || 0) >= LIMIT_PER_HOUR) return J({ reply: "You've sent a lot of messages in a short time — please try again in a little while, or email info@quotesdone.com and we'll help." });
    await admin.from('ai_usage').insert({ email: who, kind: 'support' });

    const { data: sec } = await admin.from('app_secrets').select('value').eq('key', 'openrouter_api_key').maybeSingle();
    if (!sec?.value) return J({ reply: 'Our help assistant is offline right now — please email info@quotesdone.com and the team will get back to you.' });

    // PROMPT LEAK 27 Jul 2026 ------------------------------------------------------------------
    // This selected pricing_config with '*' and JSON.stringify'd the ENTIRE row into the system
    // prompt of a customer-facing chatbot, labelled "authoritative — use these exact numbers".
    // That row is not customer data: it carries supplier-side commercial terms (supplier_reg_fee,
    // supplier_reg_period, supplier_free_count) and an internal operations flag
    // (auto_approve_suppliers, i.e. whether we are vetting suppliers by hand). A model handed that
    // block and told it is authoritative will read any of it back to whoever asks, and the person
    // asking is a member of the public. Only the customer-facing numbers go in now: the reveal
    // rate and cap that actually apply today (promo window if one is live, standard otherwise) and
    // the refund window. Never serialise a whole config row into a public prompt.
    const { data: pc } = await admin.from('pricing_config').select('promo_until,promo_reveal_rate,promo_reveal_cap,standard_reveal_rate,standard_reveal_cap,refund_window_working_days').limit(1).maybeSingle();
    const promoLive = !!pc?.promo_until && new Date() <= new Date(pc.promo_until);
    const fees: Record<string, unknown> | null = pc ? { reveal_fee_percent: Number(promoLive ? pc.promo_reveal_rate : pc.standard_reveal_rate) * 100, refund_window_working_days: pc.refund_window_working_days } : null;
    // The cap column is set to a sentinel (99,999,999) when there is effectively no cap — quoting
    // that figure at a customer reads as a bug, so it is only included when it really binds.
    if (fees && pc) { const cap = Number(promoLive ? pc.promo_reveal_cap : pc.standard_reveal_cap); if (cap > 0 && cap < 1e6) fees.reveal_fee_cap_aed = cap; }
    const pricing = fees ? `PRICING (authoritative — use these exact numbers for any fee question; the reveal fee is a percentage of the accepted quote and is the only fee a customer pays):\n${JSON.stringify(fees)}` : 'PRICING: a small reveal fee applies to unlock a chosen supplier; if asked the exact number and it is not provided, say it is shown at the reveal step.';

    const system = `${FAQ}\n\n${pricing}\n\n${acct}`;
    let reply = '';
    for (const model of FALLBACK_MODELS) {
      try {
        const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', headers: { 'Authorization': `Bearer ${sec.value}`, 'Content-Type': 'application/json', 'HTTP-Referer': 'https://quotesdone.com', 'X-Title': 'QuotesDone Support' }, body: JSON.stringify({ model, max_tokens: 600, temperature: 0.3, messages: [{ role: 'system', content: system }, ...msgs] }) });
        if (!r.ok) continue;
        const d = await r.json();
        const c = d?.choices?.[0]?.message?.content;
        if (c) { reply = c; break; }
      } catch (_e) { /* try next model */ }
    }
    if (!reply) return J({ reply: 'Sorry, I had trouble answering just now — please try again, or email info@quotesdone.com.' });
    return J({ reply });
  } catch (e) { return J({ reply: 'Something went wrong on my side — please email info@quotesdone.com and we will help.' }); }
});
