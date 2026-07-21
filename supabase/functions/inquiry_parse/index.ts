// inquiry_parse — normalises a customer inquiry into the SAME controlled vocabulary the supplier
// side uses, so matching becomes set intersection rather than text similarity.
// Writes public.inquiry_requirement. Also reports whether the job spans several trades, which is what
// drives the customer-facing fork: one contractor for everything, or a specialist per trade.
// Secret-guarded; wired into nothing yet.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
const MODELS = ['anthropic/claude-sonnet-5', 'anthropic/claude-opus-4.8'];
const PARSER_VERSION = 'inquiry_parse@1';

async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function parseJson(t: string) { let s = String(t || '').trim(); const f = s.match(/```(?:json)?\s*([\s\S]*?)```/i); if (f) s = f[1].trim(); try { return JSON.parse(s); } catch { const m = s.match(/\{[\s\S]*\}/); if (m) { try { return JSON.parse(m[0]); } catch { /* */ } } return null; } }
function clip(v: unknown, n: number) { return String(v == null ? '' : v).slice(0, n); }
function strArr(v: unknown, n: number, len = 120): string[] { return Array.isArray(v) ? v.map((x) => clip(x, len)).filter(Boolean).slice(0, n) : []; }
function numOrNull(v: unknown): number | null { const n = Number(v); return Number.isFinite(n) && n > 0 ? n : null; }

// delivery_mode -> which role capability the supplier must have
function needFor(mode: string): string {
  if (mode === 'supply_only') return 'supplies';
  if (mode === 'turnkey') return 'whole_scope';
  return 'executes';
}

const SYS = `You are QuotesDone's request analyst for the UAE construction, fit-out, MEP and building-services market. You read a customer's request and express it in a controlled vocabulary so it can be matched against suppliers who have confirmed exactly what they do. Sending a request to a supplier who cannot do it costs us that supplier, so be precise and conservative.\n\nUse ONLY the codes given in the user message.\n\nRULES\n1. trades_required = every distinct trade the job genuinely needs. A request to "change the flooring, repaint, and redo the toilet plumbing" needs flooring + painting + plumbing. Do not add a trade the customer did not actually ask for.\n2. delivery_mode is one of:\n   supply_only        - customer only wants materials/products delivered; they install themselves or have their own contractor\n   supply_and_install - customer wants the product supplied AND installed (the common case)\n   install_only       - customer already has the material, needs labour/installation only\n   turnkey            - a combined multi-trade scope the customer wants ONE company to take end to end\n   Choose turnkey ONLY when the customer clearly wants a single company for the whole job.\n3. products = the specific items/systems requested, generic and concrete ("VRF indoor units", "porcelain floor tiles"), never brand names.\n4. brands_specified = brands the customer explicitly named (empty if none).\n5. project_type = office fit-out, villa, apartment, retail, hospitality, industrial, infrastructure, or null.\n6. value_estimate = approximate AED value if the customer stated a budget or it is confidently inferable from quantities, else null. Never guess wildly.\n7. missing = what the customer still needs to tell us before a supplier could actually price this.\n\nReturn STRICT JSON only:\n{"trades_required":[code],"delivery_mode":string,"products":[string],"brands_specified":[string],"project_type":string|null,"value_estimate":number|null,"multi_trade":boolean,"reasoning":string,"missing":[string],"confidence":{"trades":0.0,"delivery_mode":0.0}}`;

async function callModel(key: string, user: string) {
  let last = '';
  for (const model of MODELS) {
    for (let at = 0; at < 2; at++) {
      try {
        const r = await fetch('https://openrouter.ai/api/v1/chat/completions', {
          method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ model, max_tokens: 1600, temperature: 0.1, messages: [
            { role: 'system', content: [{ type: 'text', text: SYS, cache_control: { type: 'ephemeral' } }] },
            { role: 'user', content: user } ] })
        });
        const jd = await r.json();
        if (!r.ok) { last = 'http ' + r.status + ' ' + clip(jd?.error?.message, 140); continue; }
        const p = parseJson(jd?.choices?.[0]?.message?.content || '');
        if (p && Object.keys(p).length) return { ai: p, err: '' };
        last = 'unparseable model output';
      } catch (e) { last = clip((e as Error)?.message || e, 140); }
    }
  }
  return { ai: null, err: last };
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    if (body.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
    const key = await sec('openrouter_api_key'); if (!key) return J({ error: 'no_ai_key' }, 500);

    const inquiryId = String(body.inquiry_id || '');
    const probe = clip(body.probe_text || '', 8000);
    if (!inquiryId && !probe) return J({ error: 'inquiry_id_or_probe_text_required' }, 400);

    let inq: any = body.inquiry || {};
    if (inquiryId) {
      const { data } = await admin.from('inquiries')
        .select('id,category,summary,raw_input,spec,boq,emirate,budget,scope_type,trades')
        .eq('id', inquiryId).maybeSingle();
      if (!data && !probe) return J({ error: 'inquiry_not_found' }, 404);
      if (data) inq = data;
    }

    const { data: tr } = await admin.from('taxonomy_trade').select('code,label').eq('active', true).order('sort');
    const vocab = 'CONTROLLED VOCABULARY — trades (use ONLY these codes):\n' +
      (tr || []).map((t: any) => `  ${t.code} — ${t.label}`).join('\n');

    const jobText = probe || [
      inq.summary && 'Summary: ' + inq.summary,
      inq.raw_input && 'Customer wrote: ' + inq.raw_input,
      inq.category && 'Stated category: ' + inq.category,
      inq.budget && 'Budget: ' + inq.budget,
      inq.spec && Object.keys(inq.spec || {}).length ? 'Details: ' + JSON.stringify(inq.spec).slice(0, 2000) : '',
      inq.boq ? 'BOQ: ' + JSON.stringify(inq.boq).slice(0, 2000) : '',
      inq.emirate && 'Emirate: ' + inq.emirate,
    ].filter(Boolean).join('\n');

    const { ai, err } = await callModel(key, vocab + '\n\nCUSTOMER REQUEST:\n' + jobText + '\n\nReturn the requirement JSON.');
    if (!ai) return J({ error: 'ai_failed', detail: err }, 502);

    const okTrade = new Set((tr || []).map((t: any) => t.code));
    const trades = strArr(ai.trades_required, 12, 40).filter((c) => okTrade.has(c));
    const dropped = strArr(ai.trades_required, 12, 40).filter((c) => !okTrade.has(c));
    const MODES = ['supply_only', 'supply_and_install', 'install_only', 'turnkey'];
    const mode = MODES.includes(String(ai.delivery_mode)) ? String(ai.delivery_mode) : 'supply_and_install';
    const products = strArr(ai.products, 25);
    const multiTrade = trades.length > 1;

    // authorities legally mandated by the requested trades
    const { data: authRows } = await admin.from('taxonomy_trade')
      .select('authority_required').in('code', trades.length ? trades : ['__none__']);
    const authority = [...new Set(([] as string[]).concat(...(authRows || []).map((r: any) => r.authority_required || [])))];

    const req_out = {
      trades_required: trades,
      role_required: needFor(mode),
      delivery_mode: mode,
      emirate: clip(inq.emirate || '', 40) || null,
      authority_required: authority,
      products_norm: products,
      brands_specified: strArr(ai.brands_specified, 12, 60),
      project_type: ai.project_type ? clip(ai.project_type, 60) : null,
      value_band: numOrNull(ai.value_estimate),
      scope_type: multiTrade ? 'multi' : 'single',
      confidence: { trades: Number(ai?.confidence?.trades) || 0, delivery_mode: Number(ai?.confidence?.delivery_mode) || 0 },
      missing_fields: strArr(ai.missing, 8, 200),
    };

    // The multi-trade fork is the CUSTOMER's decision, not ours. We only report that the choice exists;
    // intake asks, and the answer determines whether this stays one inquiry (turnkey, whole_scope) or is
    // split into one child inquiry per trade.
    const fork = multiTrade && mode !== 'turnkey' ? {
      needed: true,
      trades,
      question: 'This job covers ' + trades.join(', ') +
        '. Would you like one contractor to handle everything, or separate quotes from a specialist for each part?',
      options: [
        { value: 'single_contractor', label: 'One contractor for the whole job', effect: 'Simpler to manage — one point of responsibility.' },
        { value: 'split_by_trade',   label: 'A specialist for each part',        effect: 'Usually cheaper, and a true specialist on every trade.' },
      ],
    } : { needed: false };

    if (inquiryId && !probe) {
      const { error: upErr } = await admin.from('inquiry_requirement').upsert({
        inquiry_id: inquiryId,
        trades_required: req_out.trades_required,
        role_required: req_out.role_required,
        emirate: req_out.emirate,
        authority_required: req_out.authority_required,
        products_norm: req_out.products_norm,
        brands_specified: req_out.brands_specified,
        project_type: req_out.project_type,
        value_band: req_out.value_band,
        scope_type: req_out.scope_type,
        confidence: req_out.confidence,
        missing_fields: req_out.missing_fields,
        parsed_at: new Date().toISOString(),
        parser_version: PARSER_VERSION,
      }, { onConflict: 'inquiry_id' });
      if (upErr) return J({ error: 'requirement_write_failed', detail: upErr.message }, 500);
    }

    return J({ ok: true, probe: !!probe, requirement: req_out, fork,
      reasoning: clip(ai.reasoning, 400), vocabulary_rejected: dropped, parser_version: PARSER_VERSION });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
