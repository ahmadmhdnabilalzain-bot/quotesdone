// kb_deepen — builds DEEP, topic-organized mastery for an agent, one region of the "brain" at a time.
// For an agent it (1) generates the topic map a world-class master of that domain would know, then
// (2) writes a deep, structured brief for the next few UNCOVERED topics and ingests them into the
// permanent knowledge base (kb_chunks, embedded + retrievable via kb_query). It rolls through topics
// across runs so each agent's knowledge keeps growing and is never deleted. Applies to EVERY agent —
// trades (fit-out, CCTV…) and functions (marketing, finance, legal, IT…). __secret gated (cron/on-demand).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { makeLlm, OPUS_FIRST, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const BASE = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const T0 = Date.now();
const mapper = makeLlm(SONNET_FIRST, { max: 1200, temperature: 0.3 });   // topic map
const author = makeLlm(OPUS_FIRST, { max: 2200, temperature: 0.3 });     // the deep brief per topic
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try { await admin.from('agent_runs').insert({ agent: 'kb_deepen', status, counts, note: String(note || '').slice(0, 500), started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() }); } catch (_e) { /* */ }
}
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
function parseJson(s: string): any { if (!s) return null; let t = String(s).trim().replace(/^```(?:json)?/i, '').replace(/```$/, '').trim(); const a = t.indexOf('['); if (a > 0) t = t.slice(a); try { return JSON.parse(t); } catch (_e) { return null; } }
const slugify = (s: string) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 48);

// Roster the cron rotates through: trade category agents + core functional agents.
const FUNCTIONAL = ['marketing', 'finance', 'cfo', 'legal', 'it', 'security', 'operations', 'analytics', 'strategy'];

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    if (body.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
    const perRun = Math.max(1, Math.min(8, Number(body.topics ?? 2)));
    const BUDGET_MS = 110000; // stop authoring before the edge wall-clock (~150s) so the run always logs cleanly

    // resolve agent: explicit, or auto-pick the roster agent with the FEWEST deep chunks (grows the thinnest first)
    let agent = String(body.agent || '').trim();
    let label = agent;
    const { data: cats } = await admin.from('category_agents').select('slug,name').eq('active', true);
    const roster: { key: string; label: string }[] = [
      ...((cats as any[]) || []).map((c) => ({ key: c.slug, label: (c.name || c.slug) + ' specialist' })),
      ...FUNCTIONAL.map((k) => ({ key: k, label: k })),
    ];
    // count existing deep chunks per agent (source_id pattern uae_kb:deep::<agent>::<topic>#i)
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

    // 1) topic map — what a master of this domain knows in depth
    const mapSys = 'You are curating the KNOWLEDGE MAP for a world-class master of "' + label + '" operating in the UAE (Dubai-focused) B2B market. List the concrete sub-topics this master carries deep, book-level knowledge of — the specific materials, systems, techniques, tools, regulations, financial/marketing methods, or domain areas someone would ask them about (e.g. for fit-out: MDF, plywood, veneers, laminates, solid surface, steel framing, glass partitions, gypsum systems, flooring types, joinery hardware, finishes, MEP coordination; for marketing: Meta Ads setup & optimisation, creative/video concepting, SEO, funnel design, attribution). Output ONLY a JSON array of 20-30 short topic names (2-4 words each), specific and non-overlapping.';
    const mapOut = parseJson((await mapper(mapSys, 'Domain: ' + label + '. List the deep sub-topics.')) || '');
    const topics: string[] = Array.isArray(mapOut) ? mapOut.map((x: any) => String(x).trim()).filter(Boolean) : [];
    if (!topics.length) { await logRun('error', { agent }, 'topic map generation returned nothing for ' + agent); return J({ ok: false, agent, error: 'no_topic_map' }); }

    // 2) pick the next uncovered topics and author a deep brief for each
    const todo = topics.filter((t) => !already.has(slugify(t))).slice(0, perRun);
    let added = 0; const done: string[] = []; let stopped = false;
    for (const topic of todo) {
      if (Date.now() - T0 > BUDGET_MS) { stopped = true; break; } // leave headroom to log + return
      const briefSys = 'You are the world\'s foremost master of "' + label + '" advising on the UAE (Dubai) market. Write a DEEP, encyclopedic reference brief on the sub-topic "' + topic + '" — the kind a top expert carries in their head. Cover, as relevant: what it is and how it is made/works; the grades/types/thicknesses/variants and how to choose; quality tiers (what makes one premium vs standard); technical specs, standards and the UAE authorities/approvals that apply; typical UAE price drivers and ballpark ranges; where it is used and what designs/outcomes it enables; common mistakes, failure modes and red flags; and the sharp questions a pro asks. Be concrete, specific and UAE-accurate. 350-600 words. HARD RULE: never invent exact code numbers, authority names or figures — if unsure of a precise number, name the requirement without a fabricated number. Output ONLY the brief prose, no headings list or preamble.';
      const brief = String((await author(briefSys, 'Sub-topic: ' + topic + ' (for a ' + label + ' in the UAE). Write the deep reference brief.')) || '').trim();
      if (brief.length < 300) continue;
      const sid = 'deep::' + agent + '::' + slugify(topic);
      const r = await fetch(BASE + '/kb_ingest_text', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('inbound_secret'), source_id: sid, title: label + ' — ' + topic, category: agent, citation: 'QuotesDone deep knowledge: ' + label + ' / ' + topic, text: brief }) });
      const jd = await r.json().catch(() => ({} as any));
      if (jd?.ok) { added++; done.push(topic); }
    }
    const note = 'Deepened ' + agent + ' (' + label + '): +' + added + ' topic(s) [' + done.join(', ') + ']' + (stopped ? ' (stopped on time budget)' : '') + '. Coverage ' + (already.size + added) + '/' + topics.length + ' mapped topics.';
    await logRun(added ? 'ok' : 'error', { agent, topic_map: topics.length, covered_before: already.size, added, remaining: topics.length - already.size - added, stopped }, note);
    return J({ ok: true, agent, label, topic_map: topics.length, covered_before: already.size, added, topics_added: done, remaining: topics.length - already.size - added, stopped });
  } catch (e) { await logRun('error', {}, 'kb_deepen crashed: ' + String((e as Error)?.message || e)); return J({ error: String((e as Error)?.message || e) }, 500); }
});
