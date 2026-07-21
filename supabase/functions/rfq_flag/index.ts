// rfq_flag — lets an approved supplier flag that an RFQ's scope is unclear.
// Records a founder escalation (agent_actions) and notifies the customer so they
// can add detail (self-correcting a weak Smart Engine brief). Supplier-JWT auth.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    const { data: sup } = await admin.from('leads').select('id,company_name').eq('claimed_by', email).maybeSingle();
    if (!sup) return J({ error: 'claim your company first' }, 400);
    const body = await req.json().catch(() => ({} as any));
    const inquiryId = String(body.inquiry_id || '');
    const note = String(body.note || '').slice(0, 500);
    if (!inquiryId) return J({ error: 'inquiry_id required' }, 400);
    // must be a real match for this supplier
    const { data: match } = await admin.from('inquiry_matches').select('id').eq('inquiry_id', inquiryId).eq('supplier_id', sup.id).maybeSingle();
    if (!match) return J({ error: 'not matched to this request' }, 403);
    const { data: inq } = await admin.from('inquiries').select('id,customer_id,category,summary').eq('id', inquiryId).maybeSingle();
    if (!inq) return J({ error: 'request not found' }, 404);
    // dedupe: one open clarification per inquiry+supplier
    const { data: dupe } = await admin.from('agent_actions').select('id').eq('kind', 'rfq_clarification').eq('target_id', inquiryId).contains('detail', { supplier_id: sup.id }).in('status', ['pending', 'needs_review']).maybeSingle();
    if (!dupe) {
      await admin.from('agent_actions').insert({ agent: 'intake', kind: 'rfq_clarification', status: 'pending', risk: 'medium', title: 'Scope unclear flagged on RFQ ' + inquiryId.slice(0, 8), recommendation: 'A supplier flagged this brief as unclear' + (note ? ': ' + note : '') + '. Review the brief and, if needed, ask the customer to clarify.', detail: { supplier_id: sup.id, supplier: sup.company_name, note, category: inq.category, summary: inq.summary }, target_table: 'inquiries', target_id: inquiryId });
    }
    // notify the customer to add detail
    try { const { data: c } = await admin.from('customers').select('email,full_name').eq('id', inq.customer_id).maybeSingle(); if (c?.email && /@/.test(c.email)) { await admin.from('notifications').insert({ type: 'clarification_requested', to_email: c.email, to_role: 'customer', inquiry_id: inquiryId, channel: 'email', status: 'queued', subject: 'A supplier needs a quick clarification on your request', body: 'Hi ' + (c.full_name || 'there') + ',\n\nA supplier reviewing your request' + (inq.summary ? ' “' + inq.summary + '”' : '') + ' asked for a small clarification so they can quote accurately. Please open your request on QuotesDone and add any missing detail (scope, quantities, location or timeline).\n\nThis helps you get sharper, comparable quotes. Thank you!' }); } } catch (_e) { /* */ }
    return J({ ok: true, flagged: true });
  } catch (e) { return J({ ok: false, error: String((e as Error)?.message || e) }, 500); }
});
