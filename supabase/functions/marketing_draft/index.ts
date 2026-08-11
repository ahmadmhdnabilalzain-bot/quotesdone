// marketing_draft — the Marketing department's content_draft executor (autonomous).
// Generates on-brand content for the task and SAVES it as a DRAFT (content_drafts, status='draft').
// It never publishes and never spends: content_publish and ad_spend stay gated (unwired), so nothing
// goes public or costs money without the founder. Read + draft only.
// Auth: __secret (cos_execute / cron) OR admin-email JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const llm = makeLlm(SONNET_FIRST, { max: 1100, temperature: 0.4 });
const CHANNELS = new Set(['social', 'seo', 'email', 'blog', 'whatsapp']);
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function authed(req: Request, body: any): Promise<boolean> {
  if (body?.__secret && (await requireInternal(admin, body.__secret, 'marketing_draft')).ok) return true;
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''); if (!jwt) return false;
  const { data: { user } } = await admin.auth.getUser(jwt);
  const allow = (await sec('admin_emails') || 'management@quotesdone.com').split(',').map((s) => s.trim().toLowerCase());
  return !!(user?.email && allow.includes(user.email.toLowerCase()));
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!(await authed(req, body))) return J({ error: 'forbidden' }, 403);

    let title = String(body.title || '').trim(), detail = String(body.detail || '').trim(), objectiveText = '';
    if (body.task_id) {
      const { data: t } = await admin.from('org_tasks').select('title,detail,objective_id').eq('id', body.task_id).maybeSingle();
      if (t) { title = title || t.title || ''; detail = detail || t.detail || ''; if (t.objective_id) { const { data: o } = await admin.from('org_objectives').select('objective').eq('id', t.objective_id).maybeSingle(); objectiveText = o?.objective || ''; } }
    }
    if (!title) title = 'Draft marketing content for QuotesDone';

    // Brand voice / company context (always-on distilled knowledge).
    let brain = ''; try { const { data } = await admin./* _capped: fn_agent_context ignores any p_max_chars below 22,000 (measured 11 Aug 2026: ask 3,000 get ~30,000), so the cap on this line was decorative and LAYER 2b/2c were never emitted without a query. */ rpc('fn_agent_context_capped', { p_agent_key: 'marketing', p_max_chars: 6000, p_query: String(title).slice(0,400) }); brain = data ? String(data) : ''; } catch (_e) {}

    // Retrieved depth: pull the most relevant chunks from the queryable UAE marketing library for THIS task
    // (regulation/PDPL, SEO, paid media, WhatsApp/lifecycle, influencer, B2B, analytics...). On-demand, not always-on.
    let libref = '';
    try {
      const q = (title + ' ' + detail + ' ' + objectiveText).slice(0, 300);
      const { data: hits } = await admin.rpc('fn_marketing_library_search', { p_query: q, p_limit: 3 });
      if (Array.isArray(hits) && hits.length) {
        libref = '\n\nUAE MARKETING REFERENCE (retrieved for this task — apply what is relevant; never quote verbatim; treat legal/regulated/paid-media specifics as verify-before-acting):\n'
          + hits.map((h: any) => ('• [' + String(h.title).slice(0, 80) + '] ' + String(h.content).replace(/\s+/g, ' ').slice(0, 650))).join('\n');
      }
    } catch (_e) { /* generation proceeds on the always-on knowledge alone */ }

    const sys = 'You write concise, on-brand marketing content for QuotesDone, a UAE B2B anonymous quotation marketplace (buyers post RFQs; verified suppliers quote; buyer reveals a supplier for a fee). Practical, trustworthy, pro-SME, UAE-aware. NEVER invent statistics, prices, or client names. Choose the single most appropriate channel for the task from: social, seo, email, blog, whatsapp. Return STRICT minified JSON only: {"channel":"...","title":"...","body":"...","card_headline":"...","card_eyebrow":"..."}. body is the finished content ready for review (not a description). card_headline is a punchy on-image headline of AT MOST 8 words (no hashtags, no emoji); card_eyebrow is a 2-3 word label (e.g. "How it works", "For suppliers").' + (brain ? ('\n\n' + brain) : '') + libref;
    const user = 'MARKETING TASK: ' + title + (detail ? ('\n' + detail) : '') + (objectiveText ? ('\nParent objective: ' + objectiveText) : '') + '\n\nWrite the content now and return the JSON.';
    const raw = (await llm(sys, user, 1100) || '').trim();
    if (!raw) return J({ error: 'marketing_llm_unavailable' }, 502);

    let parsed: any = null;
    try { parsed = JSON.parse(raw.replace(/^```(json)?/i, '').replace(/```$/, '').trim()); } catch (_e) { const m = raw.match(/\{[\s\S]*\}/); if (m) { try { parsed = JSON.parse(m[0]); } catch (_e2) {} } }
    const channel = CHANNELS.has(String(parsed?.channel || '').toLowerCase()) ? String(parsed.channel).toLowerCase() : 'social';
    const draftTitle = String(parsed?.title || title).slice(0, 200);
    const draftBody = String(parsed?.body || raw).slice(0, 6000);
    if (draftBody.length < 30) return J({ error: 'draft_too_short' }, 502);

    // Make a self-branded image for the post (in-house, no external image model). Non-fatal.
    let imageUrl: string | null = null;
    const cardHeadline = String(parsed?.card_headline || draftTitle).slice(0, 90);
    const cardEyebrow = String(parsed?.card_eyebrow || '').slice(0, 30);
    try {
      const ir = await fetch(FN + '/marketing_image', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: await sec('cred_fn_marketing_draft'), title: cardHeadline, eyebrow: cardEyebrow }), signal: AbortSignal.timeout(50000) });
      const ij = await ir.json().catch(() => ({} as any)); if (ij?.ok && ij.url) imageUrl = ij.url;
    } catch (_e) { /* draft still saves without an image */ }

    const { data: ins } = await admin.from('content_drafts').insert({ channel, title: draftTitle, body: draftBody, status: 'draft', source: 'marketing', image_url: imageUrl }).select('id').maybeSingle();

    return J({ ok: true, draft_id: ins?.id || null, channel, image_url: imageUrl,
      note: 'Drafted ' + channel + ' content "' + draftTitle.slice(0, 80) + '"' + (imageUrl ? ' with a self-made branded image' : '') + ' and saved it for review (status=draft, not published). Publishing stays gated for the founder.',
      preview: draftBody.slice(0, 400) });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
