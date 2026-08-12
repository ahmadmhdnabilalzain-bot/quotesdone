// kb_deepen v3 — WEB-GROUNDED deep mastery. For an agent it (1) maps the sub-topics a world-class
// master of that domain knows (the "regions of the brain"), then (2) for each uncovered topic it
// RESEARCHES THE REAL WEB (web plugin via ai_gateway — authoritative UAE authority/standard/manufacturer
// sources), writes a grounded reference brief, and ingests it — with the REAL source URLs as the
// citation — into the permanent knowledge base (kb_chunks, embedded + retrievable). No knowledge is
// invented from model memory; every brief is sourced. Rolls through topics across runs so each agent's
// knowledge keeps growing and is never deleted. Covers EVERY agent — trades and functions alike.
// __secret gated (cron/on-demand/head-of-staff).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const BASE = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const GW = BASE + '/ai_gateway';
const T0 = Date.now();
const mapper = makeLlm(SONNET_FIRST, { max: 1200, temperature: 0.3 });   // topic map (cheap, no web)
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try { await admin.from('agent_runs').insert({ agent: 'kb_deepen', status, counts, note: String(note || '').slice(0, 500), started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() }); } catch (_e) { /* */ }
}
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
function parseJson(s: string): any {
  if (!s) return null;
  let t = String(s).trim().replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
  const a = t.indexOf('['); if (a > 0) t = t.slice(a);
  try { return JSON.parse(t); } catch (_e) { /* model wrapped or truncated the array - salvage below */ }
  const start = t.indexOf('['); if (start < 0) return null;
  // 1) balanced span: strips any prose the model appended after the array
  let depth = 0, end = -1;
  for (let i = start; i < t.length; i++) {
    const ch = t[i];
    if (ch === '[') depth++;
    else if (ch === ']') { depth--; if (depth === 0) { end = i; break; } }
  }
  if (end > start) { try { return JSON.parse(t.slice(start, end + 1)); } catch (_e) { /* fall through */ } }
  // 2) truncated mid-array (hit max_tokens): keep the complete quoted strings
  const items = t.slice(start).match(/"(?:[^"\\]|\\.)*"/g);
  if (items && items.length) { try { return JSON.parse('[' + items.join(',') + ']'); } catch (_e) { /* noop */ } }
  return null;
}
const slugify = (s: string) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 48);

// Web-grounded research: pulls real UAE sources and returns { brief, sources[] }. Sourced, not invented.
// Runs through ai_gateway (v3): the web plugin is passed through and the citation annotations come
// back on the gateway response, so the routing, budget and cost logging all apply to it.
async function research(topic: string, label: string): Promise<{ brief: string; sources: string[] }> {
  const key = await sec('cred_fn_kb_deepen'); if (!key) return { brief: '', sources: [] };
  const sys = 'You are a meticulous UAE (Dubai-focused) B2B market researcher supporting a ' + label + '. Research the sub-topic from AUTHORITATIVE, CURRENT sources — UAE government authorities and regulators, standards bodies, reputable manufacturers/suppliers and established trade references. Then write a DEEP, factual reference brief (350-600 words) a top specialist would rely on, covering as relevant: what it is and how it is made/works; the grades/types/thicknesses/variants and how to choose; quality tiers (premium vs standard); the UAE authorities, approvals and standards that apply; real price drivers and realistic UAE ballpark ranges; where it is used and what it enables; common mistakes, failure modes and red flags; and the sharp questions a pro asks. Ground every specific in what you actually find in the sources. HARD RULE: never fabricate a code number, authority name, standard or figure — if a precise number is not found, name the requirement without inventing one. Output ONLY the brief prose (no preamble, no bibliography list).';
  const user = 'Deeply research for the UAE (Dubai) market, sub-topic: "' + topic + '" (for a ' + label + '). Write the grounded reference brief.';
  try {
    const ac = new AbortController(); const to = setTimeout(() => ac.abort(), 45000);
    const r = await fetch(GW, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: key, fn: 'kb_deepen', plugins: [{ id: 'web', max_results: 6 }], max: 2000, temperature: 0.2, sys, input: [{ role: 'user', content: user }] }), signal: ac.signal });
    clearTimeout(to);
    const j = await r.json();
    const brief = String(j?.content || '').trim();
    const urls: string[] = ((j?.annotations || []) as any[]).map((a) => a?.url_citation?.url || a?.url || '').filter(Boolean);
    const sources = Array.from(new Set(urls)).slice(0, 6);
    return { brief, sources };
  } catch (_e) { return { brief: '', sources: [] }; }
}

// Roster the cron rotates through: trade category agents + core functional agents.
const FUNCTIONAL = ['marketing', 'finance', 'cfo', 'legal', 'it', 'security', 'operations', 'analytics', 'strategy'];

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'kb_deepen');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const perRun = Math.max(1, Math.min(8, Number(body.topics ?? 2)));
    const BUDGET_MS = 115000; // stop before the edge wall-clock (~150s) so the run always logs cleanly

    // resolve agent: explicit, or auto-pick the roster agent with the FEWEST deep topics (grows the thinnest first)
    let agent = String(body.agent || '').trim();
    let label = agent;
    const { data: cats } = await admin.from('category_agents').select('slug,name').eq('active', true);
    const roster: { key: string; label: string }[] = [
      ...((cats as any[]) || []).map((c) => ({ key: c.slug, label: (c.name || c.slug) + ' specialist' })),
      ...FUNCTIONAL.map((k) => ({ key: k, label: k })),
    ];
    const { data: existing } = await admin.from('kb_chunks').select('source_id').like('source_id', 'uae_kb:deep::%');
    const coveredTopics: Record<string, Set<string>> = {};
    for (const r of ((existing as any[]) || [])) { const m = String(r.source_id).match(/^uae_kb:deep::([^:]+)::([^#]+)/); if (m) { (coveredTopics[m[1]] = coveredTopics[m[1]] || new Set()).add(m[2]); } }
    if (!agent) {
      let best = roster[0]?.key || ''; let bestN = Infinity;
      for (const r of roster) { const n = (coveredTopics[r.key]?.size) || 0; if (n < bestN) { bestN = n; best = r.key; } }
      agent = best;
    }
    if (!agent) { await logRun('skipped', {}, 'no agent to deepen'); return J({ ok: true, note: 'no agent' }); }
    label = (roster.find((r) => r.key === agent)?.label) || agent;
    const already = coveredTopics[agent] || new Set<string>();

    // optional: caller supplies explicit topics to fill (head-of-staff on-demand); else map the domain.
    let topics: string[] = Array.isArray(body.topics_list) ? body.topics_list.map((x: any) => String(x).trim()).filter(Boolean) : [];
    if (!topics.length) {
      const mapSys = 'You are curating the KNOWLEDGE MAP for a world-class master of "' + label + '" operating in the UAE (Dubai-focused) B2B market. List the concrete sub-topics this master carries deep, book-level knowledge of — the specific materials, systems, techniques, tools, regulations, financial/marketing methods, or domain areas someone would ask them about (e.g. for fit-out: MDF, plywood, veneers, laminates, solid surface, steel framing, glass partitions, gypsum systems, flooring types, joinery hardware, finishes, MEP coordination; for marketing: Meta Ads setup & optimisation, creative/video concepting, SEO, funnel design, attribution). Output ONLY a JSON array of 20-30 short topic names (2-4 words each), specific and non-overlapping.';
      const mapOut = parseJson((await mapper(mapSys, 'Domain: ' + label + '. List the deep sub-topics.')) || '');
      topics = Array.isArray(mapOut) ? mapOut.map((x: any) => String(x).trim()).filter(Boolean) : [];
    }
    if (!topics.length) { await logRun('error', { agent }, 'topic map generation returned nothing for ' + agent); return J({ ok: false, agent, error: 'no_topic_map' }); }

    // pick the next uncovered topics and RESEARCH a grounded brief for each
    const todo = topics.filter((t) => !already.has(slugify(t))).slice(0, perRun);
    let added = 0; const done: string[] = []; let stopped = false; let ungrounded = 0;
    for (const topic of todo) {
      if (Date.now() - T0 > BUDGET_MS) { stopped = true; break; }
      const { brief, sources } = await research(topic, label);
      if (brief.length < 300) continue;
      if (!sources.length) ungrounded++;   // keep it (web-informed) but track that no citation URL came back
      const sid = 'deep::' + agent + '::' + slugify(topic);
      const citation = sources.length ? ('Web-researched (UAE) — sources: ' + sources.join(' ; ')) : 'Web-researched (UAE sources)';
      const r = await fetch(BASE + '/kb_ingest_text', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_kb_deepen'), source_id: sid, title: label + ' — ' + topic, category: agent, citation, text: brief }) });
      const jd = await r.json().catch(() => ({} as any));
      if (jd?.ok) { added++; done.push(topic); }
    }
    const note = 'Deepened ' + agent + ' (' + label + '): +' + added + ' web-researched topic(s) [' + done.join(', ') + ']' + (ungrounded ? ' (' + ungrounded + ' without source URLs)' : '') + (stopped ? ' (stopped on time budget)' : '') + '. Coverage ' + (already.size + added) + '/' + topics.length + ' mapped topics.';
    await logRun(added ? 'ok' : 'error', { agent, topic_map: topics.length, covered_before: already.size, added, ungrounded, remaining: topics.length - already.size - added, stopped }, note);
    // `note` IS THE WORK, AND IT WAS ONLY EVER TOLD TO agent_runs (12 Aug 2026). The string above
    // already names every topic researched and the coverage it reached; logRun got it and the HTTP
    // response did not. fn_action_invoke_collect reads the response body to fill
    // org_tasks.result.deliverable, which ten routines then read — fn_task_lesson,
    // fn_learning_loop_sweep, fn_task_review, fn_ws_company_os among them. So all 70 of this
    // function's succeeded invocations in the last 7 days closed their task with a NULL
    // deliverable and put nothing into the learning loop, while a complete account of the work sat
    // one property away. Returning it costs nothing and is not new information.
    return J({ ok: true, agent, label, note, topic_map: topics.length, covered_before: already.size, added, topics_added: done, ungrounded, remaining: topics.length - already.size - added, stopped });
  } catch (e) { await logRun('error', {}, 'kb_deepen crashed: ' + String((e as Error)?.message || e)); return J({ error: String((e as Error)?.message || e) }, 500); }
});
