// exec_agents — Executive Intelligence layer. Each officer reads live metrics and writes a
// prioritized action plan into exec_reports. Secret-gated (cron/internal). Action: run {officer} | run_all.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function parseJson(s: string): any { if (!s) return null; const m = s.match(/\{[\s\S]*\}/); if (!m) return null; try { return JSON.parse(m[0]); } catch { return null; } }
const llm = makeLlm(SONNET_FIRST, { max: 1600, temperature: 0.25 }); // shared OpenRouter client (Sonnet-first + 25s timeout)

const OFFICERS: Record<string, { name: string; rpc: string; brief: string }> = {
  strategy: { name: 'AI Strategy Officer', rpc: 'fn_strategy_metrics', brief: 'You continuously IMPROVE the business (not run it). From the metrics identify: categories with high demand but too few suppliers; coverage gaps (categories without engineered requirements, playbooks or mapped regulations); funnel leaks (abandoned RFQs, low response rate, slow first quote). Output a prioritized action plan the founder can approve.' },
  operations: { name: 'Operations Director', rpc: 'fn_ops_metrics', brief: 'You run the marketplace. From the metrics find what is slowing it down: RFQs open with no quotes, suppliers matched but not quoting, slow first-response, stuck pipeline stages, overdue activities. Recommend concrete unblocking actions.' },
  procurement_quality: { name: 'Procurement Quality Officer', rpc: 'fn_quality_metrics', brief: 'You protect quality. From the metrics flag: RFQs missing category/scope/emirate; RFQs with too few suppliers invited; low quote completeness scores; RFQs that are not comparable (only one quote). Recommend fixes that raise quote quality and comparability.' },
  data_science: { name: 'Data Scientist', rpc: 'fn_data_metrics', brief: 'You analyze trends. From the metrics identify category demand growth/decline, most competitive categories, price spread/volatility, and seasonality. Recommend where to invest supply/marketing and any pricing guidance.' },
  product_ux: { name: 'Product & UX Officer', rpc: 'fn_voice_metrics', brief: 'You are the voice of the customer. From the metrics (low ratings + comments, disputes, abandoned RFQs, repeat customers) infer friction and product/UX issues. Recommend product changes and where users drop off.' },
  competitive: { name: 'Competitive Intelligence Officer', rpc: 'fn_strategy_metrics', brief: 'Assess QuotesDone competitive position from internal proxies (category coverage vs demand, response rate, savings). Note explicitly that live competitor tracking needs an external data connector (SEO/ads/traffic) to be complete, and list what to monitor.' }
};

async function runOfficer(k: string): Promise<any> {
  const cfg = OFFICERS[k]; if (!cfg) return { error: 'unknown officer' };
  const { data: metrics } = await admin.rpc(cfg.rpc);
  const sys = 'You are ' + cfg.name + ' for QuotesDone, the UAE anonymous B2B quotation marketplace. ' + cfg.brief + ' Be concrete, specific to the numbers, and honest about small sample sizes. Return ONLY JSON: {"summary":string,"findings":[string],"recommendations":[{"action":string,"impact":"high|medium|low","effort":"high|medium|low","confidence":number}]}. 3-6 findings, 3-6 recommendations, most important first.';
  const raw = await llm(sys, 'LIVE METRICS (JSON):\n' + JSON.stringify(metrics || {}), 1800);
  const parsed = parseJson(raw || '');
  const row: any = { officer: k, period: new Date().toISOString().slice(0, 10), metrics: metrics || {},
    summary: parsed?.summary || ('Metrics captured; AI synthesis unavailable this run.'),
    findings: Array.isArray(parsed?.findings) ? parsed.findings : [],
    recommendations: Array.isArray(parsed?.recommendations) ? parsed.recommendations : [] };
  const { data: ins } = await admin.from('exec_reports').insert(row).select('id').maybeSingle();
  try { await admin.from('agent_runs').insert({ agent: 'exec:' + k, started_at: new Date().toISOString(), finished_at: new Date().toISOString(), status: 'ok', counts: { recs: row.recommendations.length } }); } catch (_e) {}
  return { officer: k, report_id: ins?.id, recommendations: row.recommendations.length, ai: !!parsed };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' } });
  try {
    const body = await req.json().catch(() => ({} as any));
    const __exp = await sec('inbound_secret');
    if (!secretOk(__exp) || body.__secret !== __exp) return J({ error: 'forbidden' }, 403);
    const action = String(body.action || 'run_all');
    if (action === 'run') return J(await runOfficer(String(body.officer || 'strategy')));
    if (action === 'run_all') { const out: any[] = []; for (const k of Object.keys(OFFICERS)) out.push(await runOfficer(k)); return J({ ok: true, ran: out }); }
    if (action === 'latest') { const { data } = await admin.from('exec_reports').select('*').order('created_at', { ascending: false }).limit(Math.min(Number(body.limit) || 12, 50)); return J({ ok: true, reports: data || [] }); }
    return J({ error: 'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
