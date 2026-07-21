// category_provision — when a supplier self-registers a trade we don't have,
// classify it against existing category-agents; if genuinely new, auto-provision a
// full-parity agent: persona + qualification playbook + category spec go LIVE (intake),
// the AI-generated quoting knowledge + regulation mapping are staged PENDING for founder
// approval (hybrid: live intake, gated knowledge). Idempotent per slug.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }

async function llm(sys: string, user: string, max = 1600): Promise<string> {
  const key = await sec('openrouter_api_key'); if (!key) return '';
  const MODELS = ['anthropic/claude-opus-4.8','anthropic/claude-sonnet-5'];
  for (const model of MODELS) {
    try {
      const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify({ model, max_tokens: max, temperature: 0, messages: [{ role: 'system', content: sys }, { role: 'user', content: user }] }) });
      const j = await r.json(); const c = j?.choices?.[0]?.message?.content; if (c) return c;
    } catch (_e) { /* next model */ }
  }
  return '';
}
function parseJson(s: string): any { try { const m = s.match(/\{[\s\S]*\}/); return m ? JSON.parse(m[0]) : null; } catch (_e) { return null; } }
function slugify(s: string){ return String(s||'').toLowerCase().replace(/&/g,' and ').replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'').replace(/-{2,}/g,'-').slice(0,40); }

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    if (body.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
    const raw = String(body.raw_category || body.category || '').trim();
    const hint = String(body.hint_services || '').trim();
    const leadId = body.lead_id ?? null;
    if (!raw) return J({ error: 'raw_category_required' }, 400);

    // existing service-category agents (exclude internal underscore agents)
    const { data: agents } = await admin.from('category_agents').select('slug,name').eq('active', true);
    const svc = (agents || []).filter((a: any) => !String(a.slug).includes('_'));
    const catalog = svc.map((a: any) => `${a.slug} = ${a.name}`).join('\n');

    // 1) classify: match to an existing category, or declare new
    const clsRaw = await llm(
      'You map a UAE contractor/supplier trade to a fixed catalog of service categories for a B2B quotation marketplace. Prefer matching an EXISTING category whenever the trade reasonably fits one (synonyms, sub-trades and supplier-of count as a match). Only mark NEW when the trade is clearly outside every listed category. Reply ONLY compact JSON: {"match": "<existing slug or empty>", "confidence": <0-1>, "proposed_slug": "<kebab-case>", "proposed_name": "<Title Case>", "reason": "<=15 words"}.',
      `CATALOG:\n${catalog}\n\nTRADE (as the supplier entered it): "${raw}"${hint ? `\nSERVICES: ${hint}` : ''}`, 400);
    const cls = parseJson(clsRaw) || {};
    const matched = String(cls.match || '').trim();
    if (matched && svc.some((a: any) => a.slug === matched)) {
      if (leadId) { try { await admin.from('leads').update({ categories: matched }).eq('id', leadId); } catch (_e) {} }
      return J({ ok: true, action: 'matched', matched_slug: matched, confidence: cls.confidence ?? null, reason: cls.reason || '' });
    }

    const slug = slugify(cls.proposed_slug || raw);
    const name = String(cls.proposed_name || raw).slice(0, 80);
    if (!slug) return J({ error: 'could_not_slug' }, 400);

    // idempotent: if the agent already exists, don't duplicate
    const { data: exists } = await admin.from('category_agents').select('slug').eq('slug', slug).maybeSingle();
    if (exists) return J({ ok: true, action: 'exists', slug });

    // 2) generate the full parity kit (ask for minified JSON; generous token budget)
    const genSys = 'You are a senior UAE construction/services domain expert building a new category for a B2B quotation marketplace. Produce a rich, accurate, UAE-specific kit. Ground everything in real UAE practice and authorities (DEWA, Dubai Municipality, Dubai Civil Defence/DCD, SIRA, Trakhees/DDA, MOIAT/ESMA, MOHRE, Al Sa’fat) ONLY where genuinely relevant — never invent a regulation. Output ONLY minified JSON (no markdown, no commentary) with keys: '
      + '"emoji" (1 char), "persona" (<=240 chars), "knowledge" (200-350 words: exactly what a complete itemised quote in this category must include — scope, materials/brands/specs, units, standards, install/testing, UAE approvals; expert checklist prose), '
      + '"questions" (array of 8-11 objects {key,label,type[choice|text|number|bool],options?,required(bool),decision?} — RFQ qualification; UAE authority triggers go in "decision"), '
      + '"reg_keywords" (array 3-8 lowercase terms), "supplier_requirements" (array of short strings: UAE licences/certs needed), "compliance_checklist" (array of short strings to verify on a quote). Keep arrays concise so the JSON is complete and valid.';
    let g: any = null;
    for (let attempt = 0; attempt < 2 && !g; attempt++) {
      const genRaw = await llm(genSys, `CATEGORY: ${name} (slug: ${slug})\nSupplier described it as: "${raw}"${hint ? `\nServices: ${hint}` : ''}`, 3800);
      const p = parseJson(genRaw);
      if (p && p.knowledge && Array.isArray(p.questions)) g = p;
    }
    if (!g) return J({ error: 'generation_failed', slug }, 502);

    // 3) LIVE writes: agent (intake), playbook (intake), spec (intake requirements)
    await admin.from('category_agents').insert({ slug, name, emoji: String(g.emoji || '🛠️').slice(0,4), active: true, persona: String(g.persona || '').slice(0, 500) });
    await admin.from('qualification_playbooks').insert({ category: slug, version: 1, status: 'active', questions: g.questions, effective_date: new Date().toISOString().slice(0,10) });
    try { await admin.from('category_specs').upsert({ category: slug, label: name, fields: {}, supplier_requirements: g.supplier_requirements || [], compliance_checklist: g.compliance_checklist || [], updated_at: new Date().toISOString(), reqs_updated_at: new Date().toISOString() }, { onConflict: 'category' }); } catch (_e) {}

    // 4) reg mapping proposal (staged, applied on approval)
    const kws: string[] = Array.isArray(g.reg_keywords) ? g.reg_keywords.map((s: any)=>String(s).toLowerCase()) : [];
    const { data: regs } = await admin.from('regulations').select('id,title,authority,categories').limit(200);
    const regMatches = (regs || []).filter((r: any) => { const hay = `${r.title||''} ${r.authority||''}`.toLowerCase(); return kws.some(k => k && hay.includes(k)); })
      .slice(0, 8).map((r: any) => ({ id: r.id, title: r.title, authority: r.authority }));

    // 5) founder review card — knowledge stays PENDING until approved
    const { data: card } = await admin.from('agent_actions').insert({
      agent: 'knowledge_curator', kind: 'category_knowledge', status: 'pending', risk: 'medium',
      title: 'New category auto-provisioned: ' + name,
      recommendation: 'A supplier self-registered a trade we did not have. The agent, its qualification playbook and category requirements are LIVE for intake. Review & approve the AI-generated quoting knowledge (and regulation links) to bring it to full quality.',
      detail: { signal: 'category_knowledge:' + slug, kind: 'category_knowledge', slug, name, knowledge: g.knowledge, reg_matches: regMatches, reg_keywords: kws, playbook_questions: (g.questions||[]).length, source_raw: raw, lead_id: leadId },
      target_table: 'category_agents', target_id: slug
    }).select('id').maybeSingle();

    if (leadId) { try { await admin.from('leads').update({ categories: slug }).eq('id', leadId); } catch (_e) {} }
    return J({ ok: true, action: 'provisioned', slug, name, live: ['category_agents','qualification_playbooks','category_specs'], pending: ['agent_knowledge','reg_mapping'], reg_matches: regMatches.length, review_action_id: card?.id ?? null });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
