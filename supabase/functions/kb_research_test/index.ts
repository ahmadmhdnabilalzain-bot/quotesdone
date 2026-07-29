// kb_research_test - probe: does web-grounded research work end to end, and with what sources?
//
// 29 Jul 2026: moved onto ai_gateway (llmWeb). A probe that bypasses the router proves nothing
// about production - it was testing a code path no real function would use once migrated, and its
// spend was invisible to ai_cost_log. Same question, now asked through the same door.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { llmWeb } from '../_shared/llm.ts';

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
    const __exp = await sec('inbound_secret');
    if (!secretOk(__exp) || body.__secret !== __exp) return J({ error: 'forbidden' }, 403);

    const topic = String(body.topic || 'MDF moisture resistant grade selection for joinery');
    const r = await llmWeb(
      'You are a UAE construction/materials researcher. Research the topic from authoritative sources and write a short grounded factual brief. Cite specifics.',
      'Research for the UAE (Dubai) market: ' + topic,
      { fn: 'kb_research_test', max: 900, maxResults: 5 },
    );
    if (!r) return J({ ok: false, error: 'gateway_unreachable' }, 502);

    // The gateway can legitimately answer without a model (FAQ, cache) or refuse (budget halt).
    // Report that plainly rather than calling it a failure - it is the router working.
    const sources = (r.sources as string[]) || [];
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
