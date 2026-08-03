// agent_learnings_report — weekly 'what agents learned' PDF. __secret or admin-JWT gated. Optional notify=founder.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'agent_learnings_report', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
const BASE = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' } });
const esc = (s: string) => String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' } as any)[c]);
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function isAdmin(email: string){ if(!email) return false; const em=email.toLowerCase(); try{const{data}=await admin.rpc('fn_role_of',{p_email:em}); if(['owner','admin'].includes(String(data||'').toLowerCase())) return true;}catch(_e){} try{const{data}=await admin.from('app_secrets').select('value').eq('key','admin_emails').maybeSingle(); const list=String((data as any)?.value||'').toLowerCase().split(/[,;\s]+/).filter(Boolean); if(list.includes(em)) return true;}catch(_e){} return false; }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return J({ ok: true });
  try {
    const body = await req.json().catch(() => ({} as any));
    let ok = false;
    if ((await requireInternal(admin, body?.__secret, 'agent_learnings_report')).ok) ok = true;
    else { const tok = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim(); if (tok) { const { data: u } = await admin.auth.getUser(tok); const em = u?.user?.email || ''; if (em && await isAdmin(em)) ok = true; } }
    if (!ok) { if (body?.__secret) { await logRun('error', { report_generated: 0 }, 'call rejected: wrong inbound secret supplied; no weekly agent-learnings report was generated'); } return J({ error: 'unauthorized' }, 401); }

    const since = new Date(Date.now() - 7 * 864e5).toISOString();
    const [{ data: chunks }, { data: actions }, { data: decisions }, cov] = await Promise.all([
      admin.from('kb_chunks').select('category,title,created_at').gt('created_at', since).order('created_at', { ascending: false }).limit(800),
      admin.from('agent_actions').select('agent,title,status,created_at').gt('created_at', since).limit(800),
      admin.from('decision_log').select('actor,kind,decision,created_at').gt('created_at', since).limit(800),
      admin.rpc('fn_ws_knowledge'),
    ]);
    const ck = (cov?.data as any)?.coverage_kpis || {};

    const byCat: Record<string, { n: number; titles: string[] }> = {};
    for (const c of (chunks || [])) { const k = (c as any).category || 'general'; (byCat[k] ||= { n: 0, titles: [] }); byCat[k].n++; if (byCat[k].titles.length < 3) byCat[k].titles.push((c as any).title); }
    const catRows = Object.entries(byCat).sort((a, b) => b[1].n - a[1].n);
    const gapsFilled = (actions || []).filter((a: any) => /filled knowledge gap/i.test(a.title || ''));
    const byAgent: Record<string, number> = {}; for (const a of (actions || [])) byAgent[(a as any).agent || 'agent'] = (byAgent[(a as any).agent || 'agent'] || 0) + 1;
    const byActor: Record<string, number> = {}; for (const d of (decisions || [])) byActor[(d as any).actor || 'agent'] = (byActor[(d as any).actor || 'agent'] || 0) + 1;

    const range = `${since.slice(0,10)} → ${new Date().toISOString().slice(0,10)}`;
    let html = `<html><head><meta charset='utf-8'><style>body{font-family:Arial,Helvetica,sans-serif;color:#0f172a;margin:32px}h1{color:#0d5c5c}h2{color:#0d5c5c;border-bottom:2px solid #e2e8f0;padding-bottom:4px;margin-top:24px}table{border-collapse:collapse;width:100%;font-size:13px}td,th{border:1px solid #e2e8f0;padding:6px 8px;text-align:left}.k{display:inline-block;margin-right:18px}.k b{font-size:22px;color:#0d5c5c}.muted{color:#64748b;font-size:12px}</style></head><body>`;
    html += `<h1>QuotesDone — Weekly Agent Learnings</h1><div class='muted'>${range}</div>`;
    html += `<h2>Knowledge coverage</h2><div><span class='k'><b>${ck.covered ?? 0}</b><br>covered</span><span class='k'><b>${ck.thin ?? 0}</b><br>thin</span><span class='k'><b>${ck.gaps ?? 0}</b><br>gaps</span><span class='k'><b>${ck.total ?? 0}</b><br>categories</span></div>`;
    html += `<h2>New knowledge added (${(chunks || []).length} chunks)</h2>`;
    if (catRows.length) { html += `<table><tr><th>Category</th><th>Chunks</th><th>Examples</th></tr>`; for (const [cat, v] of catRows) html += `<tr><td>${esc(cat)}</td><td>${v.n}</td><td>${esc(v.titles.join('; '))}</td></tr>`; html += `</table>`; } else html += `<div class='muted'>No new knowledge this week.</div>`;
    html += `<h2>Knowledge gaps filled (${gapsFilled.length})</h2>`;
    if (gapsFilled.length) { html += `<ul>`; for (const g of gapsFilled) html += `<li>${esc((g as any).title)} <span class='muted'>${esc(((g as any).created_at||'').slice(0,10))}</span></li>`; html += `</ul>`; } else html += `<div class='muted'>None this week.</div>`;
    html += `<h2>Agent activity (${(actions || []).length} actions)</h2><table><tr><th>Agent</th><th>Actions</th></tr>`; for (const [a, n] of Object.entries(byAgent).sort((x, y) => y[1] - x[1])) html += `<tr><td>${esc(a)}</td><td>${n}</td></tr>`; html += `</table>`;
    html += `<h2>Decisions logged (${(decisions || []).length})</h2><table><tr><th>Actor</th><th>Decisions</th></tr>`; for (const [a, n] of Object.entries(byActor).sort((x, y) => y[1] - x[1])) html += `<tr><td>${esc(a)}</td><td>${n}</td></tr>`; html += `</table>`;
    html += `<div class='muted' style='margin-top:28px'>Generated automatically by the QuotesDone knowledge curator.</div></body></html>`;

    const baseCounts = { chunks: (chunks || []).length, gaps_filled: gapsFilled.length, actions: (actions || []).length, decisions: (decisions || []).length, categories_with_new_knowledge: catRows.length };
    const r = await fetch(`${BASE}/make_pdf`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_to_make_pdf'), html, title: 'Weekly Agent Learnings', name: 'agent-learnings-' + new Date().toISOString().slice(0,10), bucket: 'finance-reports', folder: 'learnings' }) });
    const jd = await r.json().catch(() => ({} as any));
    if (!jd?.url) { await logRun('error', { ...baseCounts, report_generated: 0, make_pdf_http: r.status }, 'weekly agent-learnings report FAILED to render: make_pdf returned no URL (' + String(jd?.error || 'render_failed') + '); the founder gets no weekly visibility into what the agents learned'); return J({ error: jd?.error || 'render_failed' }, 500); }

    let notifyFailed = '';
    if (body?.notify) {
      try { const _nt = await admin.from('notifications').insert({ type: 'weekly_learnings', to_role: 'founder', subject: 'Weekly agent learnings report', body: 'Your weekly report of what the agents learned is ready: ' + jd.url, html: `<p>Your weekly agent-learnings report is ready.</p><p><a href='${jd.url}'>Download the PDF</a></p>`, status: 'pending', channel: 'email' }); if (_nt && (_nt as any).error) { notifyFailed = String((_nt as any).error?.message || 'insert error'); } } catch (_e) { notifyFailed = String(_e); }
    }
    let note: string;
    if (baseCounts.chunks === 0 && baseCounts.gaps_filled === 0) { note = 'report rendered but the agents learned NOTHING this week: zero new knowledge chunks and zero knowledge gaps filled — the knowledge pipeline is producing no content'; }
    else { note = 'weekly agent-learnings report rendered: ' + baseCounts.chunks + ' new knowledge chunks across ' + catRows.length + ' categories, ' + baseCounts.gaps_filled + ' gaps filled, ' + baseCounts.actions + ' agent actions'; }
    if (notifyFailed) { note += ' | founder notification failed to queue, so the report was generated but nobody was told: ' + notifyFailed; }
    await logRun((notifyFailed || (baseCounts.chunks === 0 && baseCounts.gaps_filled === 0)) ? 'error' : 'ok', { ...baseCounts, report_generated: 1, notified: body?.notify ? (notifyFailed ? 0 : 1) : 0 }, note);
    return J({ ok: true, url: jd.url, path: jd.path, chunks: (chunks || []).length, gaps_filled: gapsFilled.length });
  } catch (e) { await logRun('error', { report_generated: 0 }, 'agent_learnings_report crashed before completing; no weekly agent-learnings report was produced: ' + String((e as Error)?.message || e)); return J({ error: String((e as Error)?.message || e) }, 500); }
});
