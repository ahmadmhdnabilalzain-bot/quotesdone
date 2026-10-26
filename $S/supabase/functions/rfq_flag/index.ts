// rfq_flag — an approved supplier flags that an RFQ's scope is unclear.
//
// ONE CONCEPT, NOT TWO (14 Sep 2026, website audit). This used to write an agent_actions row of
// kind 'rfq_clarification' for staff and email the customer "please add detail" — a question the
// customer could read and never answer, because nothing before the reveal could carry a reply.
// Production held 0 such rows when it was replaced. The pre-reveal anonymous Q&A now lives in
// messages_api (clarify_ask / clarify_answer over public.rfq_clarification), so a flag IS a
// question: this forwards the supplier's own session to clarify_ask and the customer answers it
// in the portal, where every matched supplier sees the answer. Matching, masking, rate limiting and
// the customer notification all happen in that one writer.
import { observe } from '../_shared/observe.ts';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const DEFAULT_Q = 'The scope of this request is unclear to me. Could you add the missing detail — scope, quantities, location or timeline — so I can quote accurately?';
Deno.serve(observe('rfq_flag', async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const auth = req.headers.get('Authorization') || '';
    if (!/^Bearer\s+\S+/i.test(auth)) return J({ error: 'unauthorized' }, 401);
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const inquiryId = String(body.inquiry_id || '');
    if (!inquiryId) return J({ error: 'inquiry_id required' }, 400);
    const note = String(body.note || '').trim().slice(0, 500);
    const r = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/messages_api?forceFunctionRegion=ap-southeast-1`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: auth, apikey: Deno.env.get('SUPABASE_ANON_KEY') || '' },
      body: JSON.stringify({ action: 'clarify_ask', inquiry_id: inquiryId, text: note || DEFAULT_Q, source: 'rfq_flag' }),
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok || !j?.ok) return J({ ok: false, ...(j || {}) }, r.ok ? 400 : r.status);
    return J({ ok: true, flagged: true, clarification_id: j.id ?? null });
  } catch (e) { return J({ ok: false, error: String((e as Error)?.message || e) }, 500); }
}));
