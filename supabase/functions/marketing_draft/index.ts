// marketing_draft — the Marketing department's content_draft executor (autonomous).
// Generates on-brand content for the task and SAVES it as a DRAFT (content_drafts, status='draft').
// It never publishes and never spends: content_publish and ad_spend stay gated (unwired), so nothing
// goes public or costs money without the founder. Read + draft only.
// Auth: __secret (cos_execute / cron) OR admin-email JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const llm = makeLlm(SONNET_FIRST, { max: 1100, temperature: 0.4 });
const CHANNELS = new Set(['social', 'seo', 'email', 'blog', 'whatsapp']);
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function authed(req: Request, body: any): Promise<boolean> {
  if (body.__secret && body.__secret === (await sec('inbound_secret'))) return true;
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

    // Brand voice / company context for the marketing agent.
    let brain = ''; try { const { data } = await admin.rpc('fn_agent_context', { p_agent_key: 'marketing', p_max_chars: 6000 }); brain = data ? String(data) : ''; } catch (_e) {}

    const sys = 'You write concise, on-brand marketing content for QuotesDone, a UAE B2B anonymous quotation marketplace (buyers post RFQs; verified suppliers quote; buyer reveals a supplier for a fee). Practical, trustworthy, pro-SME, UAE-aware. NEVER invent statistics, prices, or client names. Choose the single most appropriate channel for the task from: social, seo, email, blog, whatsapp. Return STRICT minified JSON only: {"channel":"...","title":"...","body":"..."}. body is the finished content ready for review (not a description).' + (brain ? ('\n\n' + brain) : '');
    const user = 'MARKETING TASK: ' + title + (detail ? ('\n' + detail) : '') + (objectiveText ? ('\nParent objective: ' + objectiveText) : '') + '\n\nWrite the content now and return the JSON.';
    const raw = (await llm(sys, user, 1100) || '').trim();
    if (!raw) return J({ error: 'marketing_llm_unavailable' }, 502);

    let parsed: any = null;
    try { parsed = JSON.parse(raw.replace(/^```(json)?/i, '').replace(/```$/, '').trim()); } catch (_e) { const m = raw.match(/\{[\s\S]*\}/); if (m) { try { parsed = JSON.parse(m[0]); } catch (_e2) {} } }
    const channel = CHANNELS.has(String(parsed?.channel || '').toLowerCase()) ? String(parsed.channel).toLowerCase() : 'social';
    const draftTitle = String(parsed?.title || title).slice(0, 200);
    const draftBody = String(parsed?.body || raw).slice(0, 6000);
    if (draftBody.length < 30) return J({ error: 'draft_too_short' }, 502);

    const { data: ins } = await admin.from('content_drafts').insert({ channel, title: draftTitle, body: draftBody, status: 'draft', source: 'marketing' }).select('id').maybeSingle();

    return J({ ok: true, draft_id: ins?.id || null, channel,
      note: 'Drafted ' + channel + ' content "' + draftTitle.slice(0, 80) + '" and saved it for review (status=draft, not published). Publishing stays gated for the founder.',
      preview: draftBody.slice(0, 400) });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
