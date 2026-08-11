// boost_recommend — the paid-media RECOMMEND step (capability-gated, per the claude-ads methodology now
// in the marketing agent's knowledge). It audits available signals, applies the hard rules (3x kill,
// learning-phase budget, tracking gate, only-boost-with-traction), and if a boost is warranted it writes
// a source-grounded proposal into review_queue(kind='boost_budget') for the FOUNDER to fund. It never
// spends and never touches an ad account — money out is the founder's gate. Auth: __secret OR admin JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const llm = makeLlm(SONNET_FIRST, { max: 900, temperature: 0.3 });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function authed(req: Request, body: any): Promise<boolean> {
  if ((await requireInternal(admin, body?.__secret, 'boost_recommend')).ok) return true;
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

    // Don't stack boost proposals: if one is already pending review, do nothing.
    const { count: pending } = await admin.from('review_queue').select('id', { count: 'exact', head: true }).eq('kind', 'boost_budget').eq('status', 'pending');
    if ((pending || 0) > 0) return J({ ok: true, recommend: false, reason: 'a boost proposal is already awaiting founder review' });

    // Marketing brain (now includes the paid-media hard rules) + candidate content to boost.
    let brain = ''; try { const { data } = await admin./* _capped: fn_agent_context ignores any p_max_chars below 22,000 (measured 11 Aug 2026: ask 3,000 get ~30,000), so the cap on this line was decorative and LAYER 2b/2c were never emitted without a query. */ rpc('fn_agent_context_capped', { p_agent_key: 'marketing', p_max_chars: 7000, p_query: 'paid media boost budget rules' }); brain = data ? String(data) : ''; } catch (_e) {}
    const { data: posts } = await admin.from('content_drafts').select('id,title,channel,status,review_status,created_at').in('status', ['published', 'staged', 'draft']).order('created_at', { ascending: false }).limit(12);
    const candidates = (posts || []).map((p: any) => '- #' + p.id + ' [' + p.status + '/' + (p.review_status || '-') + '] ' + (p.title || '').slice(0, 80)).join('\n') || '(no posts yet)';
    const golive = (await sec('marketing_golive')) || 'false';

    const sys = 'You are the paid-media lead for QuotesDone (UAE B2B anonymous quotation marketplace). Decide whether to propose a paid BOOST right now, strictly following your paid-media hard rules (audit before spend, only boost content with real organic traction, tracking must be verified, define a funnel objective + expected CPA + a 3x kill stop-loss + a review date, recommend the SMALLEST budget that can exit learning). You never spend - you only propose a budget for the founder to fund. Be conservative: if there is no live ad tracking, no published post with proven traction, or the pipeline is pre-launch, recommend NOTHING and say what data/condition is needed first. Return STRICT minified JSON only: {"recommend":true|false,"reason":"...","post_ref":<id or null>,"budget_aed":<int or null>,"objective":"awareness|consideration|conversion|null","expected":"<expected reach/CPA in plain words>","kill_criteria":"...","review_in_days":<int or null>}.';
    const user = 'Marketing go-live switch: ' + golive + ' (if false, the platform has not launched paid yet).\n\nRECENT CONTENT (boost candidates):\n' + candidates + '\n\nNote: no live ad-account metrics are connected yet, so you cannot audit real CPA/ROAS. Decide accordingly and return the JSON.\n\n' + (brain ? ('YOUR KNOWLEDGE:\n' + brain.slice(0, 4000)) : '');

    const raw = (await llm(sys, user, 900) || '').trim();
    if (!raw) return J({ error: 'llm_unavailable' }, 502);
    let p: any = null;
    try { p = JSON.parse(raw.replace(/^```(json)?/i, '').replace(/```$/, '').trim()); } catch (_e) { const m = raw.match(/\{[\s\S]*\}/); if (m) { try { p = JSON.parse(m[0]); } catch (_e2) { /* noop */ } } }
    if (!p || p.recommend !== true) {
      return J({ ok: true, recommend: false, reason: String(p?.reason || 'no boost warranted now') });
    }

    const budget = Math.max(0, Math.min(Number(p.budget_aed) || 0, 100000));
    const title = 'Boost recommendation: AED ' + budget + (p.objective ? (' (' + p.objective + ')') : '');
    const summary = String(p.reason || '').slice(0, 400);
    const { data: ins } = await admin.from('review_queue').insert({
      kind: 'boost_budget', dept_key: 'marketing', title, summary,
      payload: { post_ref: p.post_ref ?? null, budget_aed: budget, objective: p.objective ?? null, expected: p.expected ?? null, kill_criteria: p.kill_criteria ?? null, review_in_days: p.review_in_days ?? null },
      status: 'pending',
    }).select('id').maybeSingle();

    return J({ ok: true, recommend: true, review_id: ins?.id || null, budget_aed: budget, note: 'Boost proposal queued for founder funding (no spend until approved).' });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
