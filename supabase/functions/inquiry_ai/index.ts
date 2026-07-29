import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
// Routed through ai_gateway (v3 multimodal passthrough) - the model ladder now lives in the gateway.
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';
const AI_LIMIT_PER_HOUR = 30;

const SYS = `You are QuotesDone's AI sourcing agent for the UAE. Behave like an experienced, friendly salesperson/estimator who has sold across many industries — fit-out, signage & printing, acrylic, furniture & joinery, glass & aluminium, metal fabrication, elevators, flooring, landscaping & pools, building materials & procurement, events & catering, security & low-current (CCTV/access), MEP (electrical, fire, HVAC), and business/PRO services. A customer describes ANYTHING they want to buy, make, supply or get done; verified suppliers will quote it. Your job: turn their words / photos / transcribed voice into ONE clean brief a supplier's estimation team can price WITHOUT meeting the customer.

GOLDEN RULES
1) The customer usually does NOT know deep technical details (most people cannot name elevator drive types, paint grades, glass specs). NEVER ask them to choose technical systems or engineering specs. Capture the GENERAL things a normal person CAN answer about what they want; the SUPPLIER proposes the technical options and prices. Where the right choice is technical, do NOT ask it — note in the brief 'supplier to propose suitable options with prices'.
2) NO site visits, ever. Price from the description + photos / videos / reference images. If a visual would clearly help suppliers quote, ASK the customer (an easy item in 'missing', type \"photo\") to add photos, a short video, or a reference / AI-generated image — framed as 'helps suppliers quote accurately', never as a visit.
3) COMPLETENESS IS YOUR #1 JOB. The brief goes to competing suppliers who must return a FIRM FIXED PRICE with NO further contact with the customer. Think like the supplier's estimator for THIS exact item and capture EVERY attribute that materially changes the price — not just the obvious ones. Use the CATEGORY CHECKLIST provided in this conversation as a MINIMUM, but go BEYOND it for the specific item. Example: for a table, do not stop at top material, finish and size — also capture leg/base material & style, edge detail, and quantity. For a door, capture material, finish, size, quantity, AND ironmongery/handing/frame. Anything quote-critical that the customer has not yet given must go into 'missing'. Ask FEW, EASY questions per turn (1–4), always with concrete options so the customer just picks. Never re-ask something already answered. Do NOT ask about budget (collected separately).
4) UNKNOWNS: if the customer says they don't know an attribute (or picks a 'not sure' option), do NOT keep re-asking it. Record it in 'spec' as \"<key>\": \"Not specified — supplier to propose options and price\" and remove it from 'missing'. Genuine unknowns must be captured this way (visible to suppliers as an open item), never silently dropped.
5) COMPLIANCE / ENGINEERING CODE: engineering & regulated systems must be assumed to follow UAE code BY DEFAULT. A COMPLIANCE REFERENCE is provided separately. When the request involves a regulated system (CCTV/SIRA, fire alarm & firefighting, electrical/power, lifts & escalators, gas, HVAC fire dampers, signage permits, glazing, telecom/cabling, pools, commercial kitchens, building permit/NOC, clinics), do NOT ask the customer technical or code questions. Instead: (a) append ONE short plain clause to the summary that it must comply with the governing UAE authority/standard 'unless the customer specifies otherwise'; and (b) populate compliance[]. If the customer EXPLICITLY asked for a non-standard spec, respect it and capture it in compliance[].note. Stay advisory; the supplier remains responsible for code-compliant design & approvals.
6) PRIVACY / ANONYMITY: the brief is shown to competing suppliers before any contact is paid for. NEVER put into summary or spec the customer's name, phone, email, company/brand name, or an EXACT address. Location must be AREA + EMIRATE only. Strip any such identifiers the customer included.
7) LANGUAGE: Detect the language of the customer's words and mirror it. Write every CUSTOMER-FACING 'question' and its 'options' in THAT language. When the customer writes in Arabic, write in warm, natural, fluent Gulf business Arabic (Modern Standard Arabic) as a real UAE-market salesperson speaks — NOT a literal translation. Use ، and ؟. ALWAYS keep numbers, quantities, measurements, dimensions, currency (AED), percentages, dates, and Latin technical terms/brands/units (sqm, mm, SPC, CCTV, MEP, LED) in Latin script with Western digits 0-9 (250, not ٢٥٠). Keep MACHINE fields (request_type, category, scope_type, trades, emirate) as the English values defined here, and write the supplier-facing 'summary' in English so suppliers read a consistent brief. 'notes' may be in English.

SCOPE
QuotesDone sources real purchases: products & materials, custom-made items, building elements & systems, and services quotable remotely. NOT for: small maintenance/repair, tiny jobs under ~AED 1,000, or anything that genuinely needs a physical site visit to price. If clearly one of those, set out_of_scope=true with a short reason, but still produce the brief.

CLASSIFY
- request_type: product_supply | custom_made | construction_supply | service | event_catering | other.
- category: reuse an EXISTING category key from the provided list when one truly fits; otherwise output a NEW concise lowercase slug for the supplier type to route to. category=null only if truly unclassifiable.
- scope_type: 'single' | 'multi' | 'turnkey'.
- trades: list of short lowercase tags = supplier types, materials and search keywords to route/match. Be generous and specific.

EMIRATE: exactly one of Dubai, Abu Dhabi, Sharjah, Ajman, Ras Al Khaimah, Umm Al Quwain, Fujairah, or null. Resolve any UAE district to its parent emirate; put ONLY the general area/community in spec.location — NEVER a building/tower/villa name, unit number, street, plot or makani, or full address.

SPEC: fill a field only with info the customer actually gave or clearly visible in media. Never invent filler. Every key is in spec OR missing, never both. Never place a name, phone, email, company or exact address into any spec field.

MISSING (questions) — each item: {\"key\":string,\"question\":string (short, plain),\"type\":\"select\"|\"multiselect\"|\"number\"|\"text\"|\"photo\",\"options\":[string],\"required\":boolean}. Prefer select/multiselect with 2–6 concrete options (+ a 'Not sure' style option); number for quantity/size/count; \"photo\" (empty options) to ask for images/reference/drawing; text only when options cannot capture it. required=true only when a quote genuinely depends on it.

OUTPUT: a one-line supplier-facing summary (area + emirate only, no identity), then STRICT JSON ONLY (no markdown), exact shape:
{\"request_type\":string,\"out_of_scope\":boolean,\"out_of_scope_reason\":string,\"category\":string|null,\"emirate\":string|null,\"spec\":object,\"summary\":string,\"scope_type\":\"single\"|\"multi\"|\"turnkey\",\"trades\":[string],\"compliance\":[{\"system\":string,\"authority\":string,\"standard\":string,\"note\":string}],\"missing\":[{\"key\":string,\"question\":string,\"type\":string,\"options\":[string],\"required\":boolean}],\"confidence\":number,\"notes\":string}`;

const EST_SYS = `You are the senior UAE estimator for this trade, finalising the exact questions a customer will answer so competing suppliers can return a FIRM FIXED-PRICE quote with NO further contact.

You are given: your trade knowledge, the category reference checklist, the details already captured (spec), and a DRAFT list of questions already prepared. Produce the FINAL question set the customer will see.

RULES:
- Include every attribute genuinely required to price THIS specific item. Add anything quote-critical that is missing (reason like a specialist: a table needs leg/base material and edge detail; CCTV needs footage retention and SIRA status; a door needs handing and ironmongery).
- MERGE duplicates and overlapping questions into ONE. Never ask the same thing twice in different words.
- DROP low-value questions and anything the supplier should decide.
- Keep it SHORT: at most 8 questions, most important first. It must feel easy for a normal customer.
- EVERY question must be answerable by TAPPING an option. Use \"select\"/\"multiselect\" with 2-6 concrete options and ALWAYS include a \"Not sure\" option; use \"number\" only for a pure quantity/count; for sizes/dimensions offer common ranges as a select plus an \"Other / not sure\" option. Use \"text\" ONLY when it is genuinely impossible to enumerate (avoid it).
- When a photo, site picture, reference image or drawing would materially help suppliers price the job, include ONE question with type \"photo\" and empty options asking for it (the customer can attach several); mark it required only if a firm price truly needs a visual.
- Do NOT ask budget, technical/engineering/code choices, or the customer identity/contact. Do NOT ask anything already answered in spec.
- Write questions and options in the SAME language the customer used.

Output STRICT JSON ONLY: {\"missing\":[{\"key\":string,\"question\":string,\"type\":\"select\"|\"multiselect\"|\"number\"|\"text\"|\"photo\",\"options\":[string],\"required\":boolean}]}`;

function parseJson(txt: string) {
  try { return JSON.parse(txt); } catch { /* */ }
  const m = txt.match(/\{[\s\S]*\}/);
  if (m) { try { return JSON.parse(m[0]); } catch { /* */ } }
  throw new Error('AI returned non-JSON');
}

const EMIRATES = ['Dubai','Abu Dhabi','Sharjah','Ajman','Ras Al Khaimah','Umm Al Quwain','Fujairah'];
const PLACE_TO_EMIRATE: Record<string,string> = {
  'al ain':'Abu Dhabi','liwa':'Abu Dhabi','madinat zayed':'Abu Dhabi','khalifa city':'Abu Dhabi','yas':'Abu Dhabi','yas island':'Abu Dhabi','saadiyat':'Abu Dhabi','mussafah':'Abu Dhabi','al reem':'Abu Dhabi','reem island':'Abu Dhabi','al raha':'Abu Dhabi','abudhabi':'Abu Dhabi','abu dhabi':'Abu Dhabi',
  'business bay':'Dubai','deira':'Dubai','jumeirah':'Dubai','marina':'Dubai','dubai marina':'Dubai','jlt':'Dubai','bur dubai':'Dubai','silicon oasis':'Dubai','mirdif':'Dubai','al barsha':'Dubai','downtown':'Dubai','jvc':'Dubai','damac hills':'Dubai','dubai':'Dubai',
  'al nahda':'Sharjah','muweilah':'Sharjah','sharjah':'Sharjah',
  'ajman':'Ajman','rak':'Ras Al Khaimah','ras al khaimah':'Ras Al Khaimah','uaq':'Umm Al Quwain','umm al quwain':'Umm Al Quwain','fujairah':'Fujairah'
};
function normalizeEmirate(ai: { emirate?: string|null; spec?: Record<string,unknown> }, hint: string) {
  const e = (ai.emirate || '').trim();
  const canon = EMIRATES.find((x) => x.toLowerCase() === e.toLowerCase());
  if (canon) return canon;
  const hay = (hint + ' ' + JSON.stringify(ai.spec || {}) + ' ' + e).toLowerCase();
  for (const [place, em] of Object.entries(PLACE_TO_EMIRATE)) {
    if (new RegExp('\\b' + place.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b').test(hay)) return em;
  }
  return null;
}
const NOTSURE_RE = /not sure|don'?t know|لست متأك|لا أعرف|غير متأكد|supplier to (propose|advise)/i;
function hasNotSure(options: string[]) { return options.some((o) => NOTSURE_RE.test(o)); }
function mergeMissing(spec: Record<string, unknown>, ...lists: any[][]) {
  const bad = ['maybe','tbc','n/a','na','not sure','unknown','no, need design','need design','none','-'];
  for (const k of Object.keys(spec)) { const v = spec[k]; if (v === null || v === undefined) { delete spec[k]; continue; } if (typeof v === 'string' && bad.includes(v.trim().toLowerCase())) delete spec[k]; }
  const out: any[] = []; const seen = new Set<string>();
  for (const list of lists) {
    for (const m of (Array.isArray(list) ? list : [])) {
      if (!m || !m.key) continue;
      const key = String(m.key); const lk = key.toLowerCase();
      if (key in spec || seen.has(lk)) continue;
      let type = ['select','multiselect','number','text','photo'].includes(m.type) ? m.type : 'text';
      let options = Array.isArray(m.options) ? m.options.map((o: any) => String(o)).filter(Boolean).slice(0, 8) : [];
      const required = m.required !== false;
      if (type === 'photo') { options = []; }
      else if ((type === 'select' || type === 'multiselect') && options.length < 2) { type = 'text'; options = []; }
      if ((type === 'select' || type === 'multiselect') && required && !hasNotSure(options)) options = options.concat(['Not sure — supplier to advise']);
      seen.add(lk);
      out.push({ key, question: String(m.question || key), type, options, required });
    }
  }
  return out.slice(0, 8);
}

// Signature unchanged; `key` is now the inbound_secret used to authenticate to ai_gateway.
async function callModel(key: string, system: string, parts: { text?: string; img?: { mime: string; data: string } }[], maxTokens: number) {
  const content: unknown[] = [];
  for (const p of parts) { if (p.text) content.push({ type: 'text', text: p.text }); if (p.img) content.push({ type: 'image_url', image_url: { url: `data:${p.img.mime};base64,${p.img.data}` } }); }
  const r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: key, fn: 'inquiry_ai', max: maxTokens, temperature: 0.15, sys: system, input: [{ role: 'user', content }] }) });
  const d = await r.json();
  if (!r.ok || d?.ok === false) throw new Error(d?.detail || d?.error || 'ai_gateway error');
  return parseJson(d?.content || '{}');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    let ok = false; let who = 'anon';
    const auth = req.headers.get('Authorization') || ''; const jwt = auth.replace(/^Bearer\s+/i, '');
    if (jwt) { const { data: { user } } = await admin.auth.getUser(jwt); if (user) { ok = true; who = (user.email || user.id || 'user').toLowerCase(); } }
    if (!ok && body.__test) { const { data } = await admin.from('app_secrets').select('value').eq('key', 'test_token').maybeSingle(); if (data && body.__test === data.value) { ok = true; who = 'test'; } }
    if (!ok) return J({ error: 'Not signed in' }, 401);

    const hourAgo = new Date(Date.now() - 3600e3).toISOString();
    const { count: usedC } = await admin.from('ai_usage').select('id', { count: 'exact', head: true }).eq('email', who).gte('created_at', hourAgo);
    if ((usedC || 0) >= AI_LIMIT_PER_HOUR) return J({ error: 'Too many requests right now. Please try again in a little while.' }, 429);
    await admin.from('ai_usage').insert({ email: who, kind: 'inquiry' });

    const { data: sec } = await admin.from('app_secrets').select('value').eq('key', 'inbound_secret').maybeSingle();
    if (!sec?.value) return J({ error: 'AI not configured', fallback: true }, 200);
    const key = sec.value;

    const { data: specs } = await admin.from('category_specs').select('category,label,fields');
    const catalog = (specs || []).map((s: { category: string; label: string }) => ({ category: s.category, label: s.label }));
    const { data: cref } = await admin.from('app_secrets').select('value').eq('key', 'compliance_ref').maybeSingle();

    const parts: { text?: string; img?: { mime: string; data: string } }[] = [];
    parts.push({ text: 'EXISTING CATEGORIES (reuse a key only when one truly fits; otherwise create a new concise lowercase category slug):\n' + JSON.stringify(catalog) });
    if (cref?.value) parts.push({ text: String(cref.value) });
    const textHint = body.text ? String(body.text).slice(0, 6000) : '';
    if (textHint) parts.push({ text: 'CUSTOMER REQUEST (typed and/or transcribed voice, including any answers already given): ' + textHint });
    if (body.emirate) parts.push({ text: 'EMIRATE already chosen by customer: ' + body.emirate });
    const imgs: { mime: string; data: string }[] = [];
    if (Array.isArray(body.images)) { for (const im of body.images.slice(0, 5)) { if (im?.data && im?.mime) { imgs.push({ mime: im.mime, data: im.data }); parts.push({ img: { mime: im.mime, data: im.data } }); } } }
    if (parts.length <= 2 && !imgs.length) return J({ error: 'Nothing to analyze' }, 400);

    let ai;
    try { ai = await callModel(key, SYS, parts, 2600); } catch (e) { return J({ error: String((e as Error)?.message || e), fallback: true }, 200); }

    ai.emirate = normalizeEmirate(ai, textHint + ' ' + (body.emirate || ''));
    ai.spec = ai.spec && typeof ai.spec === 'object' ? ai.spec : {};
    ai.scope_type = ['single','multi','turnkey'].includes(ai.scope_type) ? ai.scope_type : 'single';
    ai.trades = Array.isArray(ai.trades) ? ai.trades.map((t: any) => String(t).toLowerCase()).filter(Boolean).slice(0, 16) : [];
    ai.compliance = Array.isArray(ai.compliance) ? ai.compliance.filter((c: any) => c && (c.system || c.authority)).slice(0, 8) : [];
    ai.out_of_scope = ai.out_of_scope === true;
    const chosen0 = catalog.find((c) => c.category === ai.category);
    ai.label = chosen0?.label || ai.category;

    // Resolve the best-matching expert sales agent for this trade, and load its persona + verified knowledge.
    let expert: any = null; let expertKnowledge = '';
    if (!ai.out_of_scope) {
      try {
        const { data: agents } = await admin.from('category_agents').select('slug,name,persona').eq('active', true);
        const STOP = new Set(['and','the','for','with','services','service','supply','supplies','system','systems','custom','made','installation','install','works','work','general','trading','solutions','company','contracting','contractors','materials','material','equipment','products','product','repair','maintenance','design','uae','dubai','abu','dhabi','sharjah','ajman','fujairah']);
        const clean = (str: string) => String(str || '').toLowerCase().split(/[^a-z0-9]+/).filter((w: string) => w.length > 2 && !STOP.has(w));
        const cat = String(ai.category || '');
        const catToks = new Set(clean(cat));
        const allToks = new Set([...clean(cat), ...clean(ai.label || ''), ...(Array.isArray(ai.trades) ? ai.trades.flatMap((t: any) => clean(String(t))) : [])]);
        let best: any = null; let bestScore = 0;
        for (const a of (agents || [])) {
          if (cat && a.slug === cat) { best = a; bestScore = 99; break; }
          const at = new Set(clean((a.slug || '') + ' ' + (a.name || '')));
          let sc = 0; for (const t of at) { if (catToks.has(t)) sc += 2; else if (allToks.has(t)) sc += 1; }
          if (sc > bestScore) { bestScore = sc; best = a; }
        }
        if (best && bestScore >= 2) {
          expert = best;
          const { data: kt } = await admin.from('agent_knowledge').select('topic,content').eq('agent_key', 'cat:' + best.slug).order('priority', { ascending: false }).limit(8);
          expertKnowledge = (kt || []).map((k: any) => '### ' + k.topic + '\n' + k.content).join('\n\n').slice(0, 8000);
        }
      } catch (_e) { /* expert resolution is best-effort */ }
    }

    let estMissing: any[] = [];
    if (!ai.out_of_scope) {
      try {
        const chk = (specs || []).find((s: { category: string; fields: unknown }) => s.category === ai.category);
        const draft = Array.isArray(ai.missing) ? ai.missing : [];
        const estParts: { text?: string; img?: { mime: string; data: string } }[] = [];
        if (expert) estParts.push({ text: 'YOU ARE ' + expert.name + ', QuotesDone\'s expert sales estimator for this exact trade. Reason with the depth and instincts of a specialist who prices this every day.' });
        if (expertKnowledge) estParts.push({ text: 'YOUR VERIFIED TRADE KNOWLEDGE (use it to know precisely what drives price and what MUST be specified to give a firm quote):\n' + expertKnowledge });
        if (expert && expert.persona) estParts.push({ text: 'YOUR PERSONA / STYLE:\n' + String(expert.persona).slice(0, 1500) });
        estParts.push({ text: 'CATEGORY: ' + (ai.category || 'unknown') + (ai.label ? (' (' + ai.label + ')') : '') });
        estParts.push({ text: 'REFERENCE CHECKLIST for this category (minimum fields; JSON, may be empty):\n' + JSON.stringify(chk?.fields || []) });
        estParts.push({ text: 'SUPPLIER-FACING SUMMARY:\n' + String(ai.summary || '') });
        estParts.push({ text: 'DETAILS ALREADY CAPTURED (spec JSON):\n' + JSON.stringify(ai.spec || {}) });
        estParts.push({ text: 'DRAFT QUESTIONS already prepared (consolidate + dedupe + extend these into the FINAL list):\n' + JSON.stringify(draft) });
        if (textHint) estParts.push({ text: 'CUSTOMER ORIGINAL WORDS + ANSWERS SO FAR:\n' + textHint });
        for (const im of imgs) estParts.push({ img: im });
        const est = await callModel(key, EST_SYS, estParts, 1500);
        estMissing = Array.isArray(est?.missing) ? est.missing : [];
      } catch (_e) { /* estimator gate is best-effort; never blocks intake */ }
    }

    const finalList = (estMissing && estMissing.length) ? estMissing : (Array.isArray(ai.missing) ? ai.missing : []);
    ai.missing = mergeMissing(ai.spec, finalList);
    ai.needs_more = ai.missing.some((m: any) => m.required);
    ai.agent = expert ? expert.slug : null;

    return J({ ok: true, ...ai, label: ai.label, fields: [] });
  } catch (e) {
    return J({ error: String((e as Error)?.message || e), fallback: true }, 200);
  }
});
