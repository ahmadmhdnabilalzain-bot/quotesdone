// designer v2 — the Designer agent's image engine. Generates on-brand images via OpenAI gpt-image-1,
// hosts them publicly (brand bucket), returns a URL usable in Meta ads, Postiz, or the blog.
// Auth: __secret == inbound_secret. Secret needed to generate: openai_api_key.
// Actions: 'status' (readiness), 'generate' (default).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { paidProviderGate } from '../_shared/paid_gate.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA = Deno.env.get('SUPABASE_URL')!;
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
async function sec(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

const SIZE: Record<string, string> = {
  square: '1024x1024', instagram: '1024x1024', facebook_feed: '1024x1024', social: '1024x1024',
  portrait: '1024x1536', story: '1024x1536', reel: '1024x1536', instagram_story: '1024x1536',
  landscape: '1536x1024', blog: '1536x1024', linkedin: '1536x1024', ad: '1024x1024',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' } });
  const body = await req.json().catch(() => ({} as any));
  // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
  // per-context credential and the legacy shared secret, and records which one called.
  const __auth = await requireInternal(admin, body?.__secret, 'designer');
  if (!__auth.ok) return J({ error: 'forbidden' }, 403);

  const key = await sec('openai_api_key');
  const fallback = await sec('default_post_image');
  const action = String(body.action || 'generate');

  // Readiness probe for the Agents console / callers.
  if (action === 'status') {
    return J({ ok: true, ready: !!key, model: 'gpt-image-1', sizes: Object.keys(SIZE), has_fallback: !!fallback,
      message: key ? 'Designer ready.' : 'Set app_secrets.openai_api_key to enable image generation.' });
  }
  if (action !== 'generate') return J({ error: 'unknown_action' }, 400);

  const brief = String(body.prompt || body.brief || '').trim();
  if (!brief) return J({ error: 'empty_prompt' }, 400);
  const purpose = String(body.purpose || 'social');
  const size = SIZE[String(body.size || purpose).toLowerCase()] || '1024x1024';
  const started = new Date().toISOString();

  // No key: don't fail hard — tell the caller it's not configured and offer the brand fallback image.
  if (!key) {
    await admin.from('agent_runs').insert({ agent: 'designer', started_at: started, finished_at: new Date().toISOString(), status: 'skipped', note: 'openai_api_key not set' }).then(() => null, () => null);
    return J({ ok: false, ready: false, error: 'openai_not_configured', need: ['openai_api_key'], fallback_url: fallback || null, message: 'Image generation is not active yet — add the openai_api_key secret. A brand fallback image is available.' }, 200);
  }

  // KERNEL K12 — this was the fifth door, and it consulted nothing.
  //
  // gpt-image-1 on api.openai.com is paid inference. The 16 Aug audit traced four callers of
  // openrouter.ai and gated them; this one reaches a different host, so a search for "openrouter"
  // never found it and it went to a paid provider on every invocation with no gate of any kind.
  // It now asks the same single authority every other paid client asks, and a gate it cannot read
  // is a refusal.
  {
    const gate = await paidProviderGate(admin, 'openai/gpt-image-1');
    if (!gate.allowed) {
      await admin.from('agent_runs').insert({
        agent: 'designer', started_at: started, finished_at: new Date().toISOString(), status: 'skipped',
        note: `skipped_due_to_zero_cost_mode: ${gate.rule} — ${gate.reason}`.slice(0, 250),
      }).then(() => null, () => null);
      return J({ ok: false, ready: false, error: 'paid_provider_denied', rule: gate.rule,
        reason: gate.reason, fallback_url: fallback || null, cost_usd: 0,
        message: 'No image was generated and no paid provider was called. ' + gate.reason }, 200);
    }
  }

  try {
    let brain = ''; try { const { data } = await admin./* _capped: fn_agent_context ignores any p_max_chars below 22,000 (measured 11 Aug 2026: ask 3,000 get ~30,000), so the cap on this line was decorative and LAYER 2b/2c were never emitted without a query. */ rpc('fn_agent_context_capped', { p_agent_key: 'designer', p_max_chars: 3000 }); brain = data ? String(data) : ''; } catch (_e) {}
    const brandLine = 'Brand: QuotesDone, a modern UAE B2B marketplace. Visual style: clean, professional, trustworthy, tech-forward; teal/deep-green brand accent (#0E7C73) with crisp white space; UAE business context (offices, trades, SMEs) where relevant. Avoid clutter and stocky clichés. If the brief asks for a headline area, leave clean negative space for text to be added later — do not render long paragraphs of text.';
    const prompt = brandLine + (brain ? ('\n' + brain.slice(0, 1500)) : '') + '\n\nDesign request: ' + brief;

    const r = await fetch('https://api.openai.com/v1/images/generations', {
      method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'gpt-image-1', prompt: prompt.slice(0, 3800), size, n: 1 }),
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) { await admin.from('agent_runs').insert({ agent: 'designer', started_at: started, finished_at: new Date().toISOString(), status: 'error', note: JSON.stringify(j).slice(0, 250) }); return J({ ok: false, error: j?.error?.message || 'image_generation_failed', status: r.status }, 200); }
    const b64 = j?.data?.[0]?.b64_json;
    if (!b64) return J({ ok: false, error: 'no_image_returned' }, 200);

    const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    const path = 'designer/' + Date.now() + '-' + purpose.replace(/[^a-z0-9]+/gi, '-').slice(0, 24) + '.png';
    const up = await admin.storage.from('brand').upload(path, bytes, { contentType: 'image/png', upsert: true });
    if (up.error) return J({ ok: false, error: up.error.message }, 200);
    const url = SUPA + '/storage/v1/object/public/brand/' + path;

    await admin.from('content_drafts').insert({ channel: 'image', title: ('Design: ' + brief).slice(0, 200), body: url, status: 'ready', source: 'agent:designer' }).then(() => null, () => null);
    await admin.from('agent_runs').insert({ agent: 'designer', started_at: started, finished_at: new Date().toISOString(), status: 'ok', counts: { size, purpose } });
    return J({ ok: true, url, size, purpose });
  } catch (e) {
    await admin.from('agent_runs').insert({ agent: 'designer', started_at: started, finished_at: new Date().toISOString(), status: 'error', note: String(e).slice(0, 200) });
    return J({ error: String((e as Error)?.message || e) }, 200);
  }
});
