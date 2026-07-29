// agent_autogen — when suppliers arrive from a category we don't cover yet, auto-create a full expert
// sales agent for it: persona + verified knowledge pack + intake checklist. Daily cron + callable.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'agent_autogen', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
let LLM_CALLS = 0, PARSE_FAILS = 0, SAVE_FAILS = 0, SPEC_FAILS = 0, EMPTY_KNOWLEDGE = 0; let LAST_ERR = '';
function summarize(results: any[], considered: number) {
  const made = results.filter((r) => r.ok);
  const genFailed = results.filter((r) => !r.ok && r.error === 'generation_failed');
  const other = results.filter((r) => !r.ok && r.error !== 'generation_failed');
  let note: string;
  if (results.length === 0) { note = 'no uncovered supplier/inquiry categories found; no new expert agents needed this run'; }
  else if (made.length === 0 && genFailed.length) { note = 'NO expert category agents created this run: the model returned nothing usable for all ' + genFailed.length + ' uncovered trade(s) [' + genFailed.map((r) => r.trade).join(', ') + '], so suppliers and inquiries in those trades stay uncovered with no persona, knowledge or intake checklist'; }
  else if (made.length === 0) { note = 'no expert category agents created this run; ' + results.length + ' candidate(s) were all skipped (' + other.map((r) => r.trade + ':' + r.error).join(', ') + ')'; }
  else { note = 'created ' + made.length + ' expert category agent(s): ' + made.map((m) => m.slug).join(', ') + (genFailed.length ? ('; ' + genFailed.length + ' trade(s) produced nothing usable from the model and remain uncovered') : ''); }
  if (EMPTY_KNOWLEDGE > 0) { note += ' | ' + EMPTY_KNOWLEDGE + ' agent(s) were created with an EMPTY knowledge pack and will talk to UAE customers with no trade expertise'; }
  if (SPEC_FAILS > 0) { note += ' | ' + SPEC_FAILS + ' intake checklist(s) failed to save, so those categories collect no quote-critical fields'; }
  if (SAVE_FAILS > 0) { note += ' | ' + SAVE_FAILS + ' database write(s) failed during provisioning'; }
  if (LAST_ERR) { note += ' | last error: ' + LAST_ERR; }
  const bad = SAVE_FAILS > 0 || SPEC_FAILS > 0 || EMPTY_KNOWLEDGE > 0 || (results.length > 0 && made.length === 0 && genFailed.length > 0);
  return { status: bad ? 'error' : 'ok', note, counts: { considered, attempted: results.length, created: made.length, generation_failed: genFailed.length, skipped: other.length, llm_calls: LLM_CALLS, parse_failures: PARSE_FAILS, empty_knowledge_packs: EMPTY_KNOWLEDGE, save_failures: SAVE_FAILS, checklist_failures: SPEC_FAILS } };
}
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
const MODELS = ['anthropic/claude-sonnet-5', 'anthropic/claude-opus-4.8']; // Sonnet-first for cost (fleet policy)

async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function slugify(s: string) { return String(s || '').toLowerCase().replace(/&/g, ' and ').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40); }
function tokens(s: string) { return new Set(String(s || '').toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length > 2)); }
function parseJson(txt: string) { try { return JSON.parse(txt); } catch { /* */ } const m = txt.match(/\{[\s\S]*\}/); if (m) { try { return JSON.parse(m[0]); } catch { /* */ } } return null; }

async function llm(key: string, sys: string, user: string, max = 4500) {
  LLM_CALLS++;
  const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: key, fn: 'agent_autogen', sys, input: user, max, temperature: 0.2 }) });
  const d = await r.json();
  if (!r.ok) { LAST_ERR = 'ai_gateway HTTP ' + r.status + ': ' + String(d?.error || ''); throw new Error(d?.error || 'ai_gateway error'); }
  return d?.content || '';
}

const GEN_SYS = `You create a new expert trade category for QuotesDone, a UAE B2B quotation marketplace where customers post jobs and verified suppliers submit anonymised fixed-price quotes. Given a supplier trade/category name, output EVERYTHING needed to launch a first-class expert sales agent for it, grounded in real UAE market practice.

Return STRICT JSON ONLY (no markdown), exact shape:
{
  "name": "Human category name (Title Case)",
  "emoji": "one relevant emoji",
  "slug": "lowercase-hyphen-slug",
  "persona": "2-4 sentences: a seasoned UAE [trade] sales estimator — warm, expert, practical, pro-SME; knows what drives price and how to guide a customer to a quotable brief without a site visit",
  "knowledge": [ { "topic": "short topic", "content": "150-350 words of verified, specific UAE trade knowledge", "priority": 1 } ],
  "checklist": [ { "key": "snake_case", "question": "short plain customer-facing question", "type": "select|multiselect|number|text", "options": ["concrete option", "Not sure"], "required": true } ]
}

RULES:
- knowledge: EXACTLY 6 topics covering: (1) what materially drives price in this trade, (2) the specifications a customer MUST provide to get a firm quote, (3) UAE compliance/authority & standards IF the trade is regulated (else market norms), (4) common customer mistakes / things they forget, (5) typical scope inclusions vs exclusions, (6) a concise quoting checklist an estimator runs through. Be specific to the UAE. Do NOT invent prices or fake statistics.
- checklist: 5-9 quote-critical fields the customer must answer for a supplier to price WITHOUT contacting them. Prefer select/multiselect with 2-6 concrete options plus a 'Not sure' option; number for quantities/sizes. required=true only when a quote genuinely depends on it.
- Keep it honest and non-hyped. Output JSON only.`;

async function generateFor(key: string, trade: string) {
  const raw = await llm(key, GEN_SYS, 'Trade / category: ' + trade + '\nCountry: United Arab Emirates.');
  const j = parseJson(raw);
  if (!j || !j.name) { PARSE_FAILS++; LAST_ERR = 'model output for trade "' + trade + '" was unparseable or had no name; agent not created'; return null; }
  const slug = slugify(j.slug || j.name || trade);
  if (!slug) { PARSE_FAILS++; LAST_ERR = 'model output for trade "' + trade + '" produced an empty slug; agent not created'; return null; }
  const knowledge = Array.isArray(j.knowledge) ? j.knowledge.filter((k: any) => k && k.topic && k.content).slice(0, 8) : [];
  const checklist = Array.isArray(j.checklist) ? j.checklist.filter((c: any) => c && c.key && c.question).slice(0, 12) : [];
  return { slug, name: String(j.name).slice(0, 80), emoji: String(j.emoji || '🧩').slice(0, 8), persona: String(j.persona || '').slice(0, 2000), knowledge, checklist };
}

async function provision(key: string, trade: string, agentSlugs: Set<string>) {
  const g = await generateFor(key, trade);
  if (!g) return { trade, ok: false, error: 'generation_failed' };
  if (agentSlugs.has(g.slug)) return { trade, ok: false, error: 'slug_exists', slug: g.slug };
  const _ca = await admin.from('category_agents').insert({ slug: g.slug, name: g.name, emoji: g.emoji, persona: g.persona, active: true });
  if (_ca && (_ca as any).error) { SAVE_FAILS++; LAST_ERR = 'category_agents insert failed for ' + g.slug + ': ' + String((_ca as any).error?.message || ''); }
  if (g.knowledge.length) { const _ak = await admin.from('agent_knowledge').insert(g.knowledge.map((k: any, i: number) => ({ agent_key: 'cat:' + g.slug, topic: String(k.topic).slice(0, 120), content: String(k.content).slice(0, 6000), priority: Number(k.priority) || (g.knowledge.length - i) }))); if (_ak && (_ak as any).error) { SAVE_FAILS++; LAST_ERR = 'agent_knowledge insert failed for ' + g.slug + ': ' + String((_ak as any).error?.message || ''); } }
  else { EMPTY_KNOWLEDGE++; LAST_ERR = 'agent ' + g.slug + ' was created with no knowledge topics from the model'; }
  try { const _cs = await admin.from('category_specs').upsert({ category: g.slug, label: g.name, fields: g.checklist }, { onConflict: 'category' }); if (_cs && (_cs as any).error) { SPEC_FAILS++; LAST_ERR = 'category_specs upsert failed for ' + g.slug + ': ' + String((_cs as any).error?.message || ''); } } catch (_e) { SPEC_FAILS++; LAST_ERR = 'category_specs upsert threw for ' + g.slug + ': ' + String(_e); }
  agentSlugs.add(g.slug);
  return { trade, ok: true, slug: g.slug, name: g.name, topics: g.knowledge.length, checklist: g.checklist.length };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    const __exp = await sec('inbound_secret');
    if (!secretOk(__exp) || body.__secret !== __exp) { await logRun('error', { created: 0 }, 'call rejected: wrong or missing inbound secret; no expert category agents were created'); return J({ error: 'forbidden' }, 403); }
    const key = __exp; if (!key) { await logRun('error', { created: 0 }, 'inbound_secret missing from app_secrets: no expert category agents created this run, uncovered supplier trades stay uncovered'); return J({ error: 'AI not configured' }, 200); }
    const max = Math.max(1, Math.min(5, Number(body.max) || 3));

    const { data: agents } = await admin.from('category_agents').select('slug,name');
    const agentSlugs = new Set((agents || []).map((a: any) => a.slug));
    const agentTokenSets = (agents || []).map((a: any) => tokens((a.slug || '') + ' ' + (a.name || '')));
    const covered = (trade: string) => { const tt = tokens(trade); for (const s of agentTokenSets) { for (const t of tt) if (s.has(t)) return true; } return false; };

    const results: any[] = [];
    if (body.category) { results.push(await provision(key, String(body.category), agentSlugs)); const sF = summarize(results, 1); await logRun(sF.status, { ...sF.counts, mode: 'forced' }, 'forced provisioning of "' + String(body.category) + '": ' + sF.note); return J({ ok: true, mode: 'forced', results }); }

    const wanted = new Map<string, number>();
    const { data: sup } = await admin.from('leads').select('sector').eq('claimed', true).not('sector', 'is', null).limit(2000);
    for (const l of (sup || [])) { const v = String(l.sector || '').trim(); if (v) wanted.set(v.toLowerCase(), (wanted.get(v.toLowerCase()) || 0) + 1); }
    const { data: inq } = await admin.from('inquiries').select('category').not('category', 'is', null).gte('created_at', new Date(Date.now() - 60 * 864e5).toISOString()).limit(2000);
    for (const i of (inq || [])) { const v = String(i.category || '').trim(); if (v) wanted.set(v.toLowerCase(), (wanted.get(v.toLowerCase()) || 0) + 1); }

    const candidates = [...wanted.entries()].filter(([t]) => t.length >= 3 && !covered(t) && !agentSlugs.has(slugify(t))).sort((a, b) => b[1] - a[1]).slice(0, max);
    for (const [trade] of candidates) results.push(await provision(key, trade, agentSlugs));

    const made = results.filter((r) => r.ok);
    if (made.length) {
      const owner = String(await sec('admin_emails') || 'management@quotesdone.com').split(',')[0].trim();
      try { const _aa = await admin.from('agent_actions').insert({ agent: 'autogen', kind: 'agent_created', status: 'pending', risk: 'low', title: made.length + ' new expert category agent(s) auto-created: ' + made.map((m) => m.name).join(', '), recommendation: 'review the new agent persona/knowledge/checklist in admin; adjust if needed', target_table: 'category_agents', target_id: null, detail: { made } }); if (_aa && (_aa as any).error) { SAVE_FAILS++; LAST_ERR = 'agent_actions insert failed: ' + String((_aa as any).error?.message || ''); } } catch (_e) { SAVE_FAILS++; LAST_ERR = 'agent_actions insert threw: ' + String(_e); }
      try { const _nt = await admin.from('notifications').insert({ type: 'agent_created', to_email: owner, to_role: 'admin', channel: 'email', subject: 'QuotesDone: new expert agent(s) created for uncovered categories', body: 'Auto-created expert sales agents for: ' + made.map((m) => m.name + ' (' + m.slug + ')').join(', ') + '. Each has a persona, a verified knowledge pack and an intake checklist. Review in the admin Agents console.' }); if (_nt && (_nt as any).error) { SAVE_FAILS++; LAST_ERR = 'notifications insert failed: ' + String((_nt as any).error?.message || ''); } } catch (_e) { SAVE_FAILS++; LAST_ERR = 'notifications insert threw: ' + String(_e); }
    }
    const sS = summarize(results, candidates.length);
    await logRun(sS.status, { ...sS.counts, mode: 'scan' }, sS.note);
    return J({ ok: true, mode: 'scan', considered: candidates.length, results });
  } catch (e) { await logRun('error', { created: 0, llm_calls: LLM_CALLS, parse_failures: PARSE_FAILS }, 'agent_autogen crashed before completing; uncovered trades were not provisioned this run: ' + String((e as Error)?.message || e)); return J({ error: String((e as Error)?.message || e) }, 500); }
});

