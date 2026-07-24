// content_revise — the "comment -> it changes" half of the marketing review gate. It picks up drafts the
// founder sent back (review_status='changes_requested' with a founder_comment), rewrites the post to address
// the comment (on-brand, using the marketing knowledge), and puts it back in the review queue as 'pending'.
// Never publishes. Auth: __secret (cron) OR admin JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const llm = makeLlm(SONNET_FIRST, { max: 1100, temperature: 0.4 });
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

    const { data: drafts } = await admin.from('content_drafts')
      .select('id,title,body,channel,founder_comment')
      .eq('review_status', 'changes_requested').not('founder_comment', 'is', null).limit(5);
    if (!drafts || !drafts.length) return J({ ok: true, revised: 0, note: 'nothing to revise' });

    let brain = ''; try { const { data } = await admin.rpc('fn_agent_context', { p_agent_key: 'marketing', p_max_chars: 6000 }); brain = data ? String(data) : ''; } catch (_e) {}
    const sys = 'You revise a QuotesDone marketing post to address the founder feedback exactly, keeping it on-brand (UAE B2B anonymous quotation marketplace; practical, trustworthy, pro-SME; never invent stats/prices/client names). Change exactly what the feedback asks and improve the post; keep the same channel and intent. Return STRICT minified JSON only: {"title":"...","body":"..."}. body is the finished revised post.' + (brain ? ('\n\n' + brain.slice(0, 4500)) : '');

    const results: any[] = [];
    for (const d of drafts) {
      const user = 'CHANNEL: ' + (d.channel || 'social') + '\nCURRENT TITLE: ' + (d.title || '') + '\nCURRENT POST:\n' + (d.body || '') + '\n\nFOUNDER FEEDBACK (address this exactly):\n' + (d.founder_comment || '') + '\n\nReturn the revised JSON.';
      const raw = (await llm(sys, user, 1100) || '').trim();
      let p: any = null;
      try { p = JSON.parse(raw.replace(/^```(json)?/i, '').replace(/```$/, '').trim()); } catch (_e) { const m = raw.match(/\{[\s\S]*\}/); if (m) { try { p = JSON.parse(m[0]); } catch (_e2) { /* noop */ } } }
      const newBody = String(p?.body || '').trim();
      if (newBody.length < 20) { results.push({ id: d.id, ok: false, reason: 'revision_failed' }); continue; }
      await admin.from('content_drafts').update({
        title: String(p?.title || d.title || '').slice(0, 200), body: newBody.slice(0, 6000),
        review_status: 'pending', founder_comment: null, reviewed_at: null,
      }).eq('id', d.id);
      results.push({ id: d.id, ok: true });
    }
    return J({ ok: true, revised: results.filter((r) => r.ok).length, results, note: 'Revised drafts are back in the founder review queue as pending.' });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
