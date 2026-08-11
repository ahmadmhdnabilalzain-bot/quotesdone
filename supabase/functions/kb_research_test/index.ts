// kb_research_test - probe: does web-grounded research work end to end, and with what sources?
//
// 29 Jul 2026: moved onto ai_gateway (llmWeb). A probe that bypasses the router proves nothing
// about production - it was testing a code path no real function would use once migrated, and its
// spend was invisible to ai_cost_log. Same question, now asked through the same door.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
// llmWeb WAS DELETED FROM _shared/llm.ts in d8a4d96 and this was its only importer, so this probe
// has not compiled since — a broken import is a function that cannot load at all, and "deploy edge
// functions" has been failing on it. The header above already says where it belongs: "moved onto
// ai_gateway ... Same question, now asked through the same door." So it asks the gateway directly,
// exactly as kb_deepen does, which keeps routing, budget and ai_cost_log applying to the probe.
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  try {
    // deno-lint-ignore no-explicit-any
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'kb_research_test');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);

    const topic = String(body.topic || 'MDF moisture resistant grade selection for joinery');
    const key = await sec('cred_fn_kb_research_test');
    if (!key) return J({ ok: false, error: 'cred_fn_kb_research_test missing' }, 500);
    // deno-lint-ignore no-explicit-any
    let r: any;
    try {
      const ac = new AbortController(); const to = setTimeout(() => ac.abort(), 45000);
      const gr = await fetch(GW, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          __secret: key, fn: 'kb_research_test',
          plugins: [{ id: 'web', max_results: 5 }], max: 900,
          sys: 'You are a UAE construction/materials researcher. Research the topic from authoritative sources and write a short grounded factual brief. Cite specifics.',
          input: [{ role: 'user', content: 'Research for the UAE (Dubai) market: ' + topic }],
        }), signal: ac.signal });
      clearTimeout(to);
      r = await gr.json();
    } catch (_e) { r = null; }
    if (!r) return J({ ok: false, error: 'gateway_unreachable' }, 502);

    // The gateway can legitimately answer without a model (FAQ, cache) or refuse (budget halt).
    // Report that plainly rather than calling it a failure - it is the router working.
    // Sources come back as OpenRouter url_citation annotations, the same shape kb_deepen reads.
    // deno-lint-ignore no-explicit-any
    const sources = Array.from(new Set(((r.annotations || []) as any[])
      .map((a) => a?.url_citation?.url || a?.url || '').filter(Boolean))) as string[];
    return J({
      ok: r.ok !== false,
      outcome: r.outcome ?? null,
      model: r.model ?? null,
      task_class: r.task_class ?? null,
      has_content: !!r.content,
      content_preview: String(r.content || '').slice(0, 400),
      source_count: sources.length,
      sources,
      cost_usd: r.cost_usd ?? null,
      why: r.why ?? null,
      raw_error: r.error ?? null,
    });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
