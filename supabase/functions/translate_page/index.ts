import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string | undefined) || undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
const SYS = 'You are a professional English to Arabic translator for a UAE B2B quotation marketplace called QuotesDone. Translate the VISIBLE TEXT of the given HTML fragment into natural, fluent Modern Standard Arabic for UAE business users. The fragment may have unbalanced tags (a slice of a larger document) - that is fine, keep tags exactly. HARD RULES: 1) Preserve ALL HTML tags, attributes, classes, ids, hrefs and structure EXACTLY, even if unbalanced. 2) Do NOT translate: brand name QuotesDone, URLs/href/src, emails, numbers, dates, AED, code. 3) Preserve any placeholder tokens of the form {{...}} EXACTLY as-is (for example {{LOC_THE}} and {{LOC}}) - never translate, alter, space, or remove them. 4) Translate text between tags and placeholder/title/aria-label/alt attribute VALUES. 5) Faithful and precise, including legal text. 6) Output ONLY the translated HTML fragment, no fences, no notes.';
function chunk(html: string, size = 4500): string[] {
  if (html.length <= size) return [html];
  const parts = html.split(/(<[^>]+>)/); const chunks: string[] = []; let buf = '';
  for (const p of parts) { buf += p; if (p.startsWith('</') && buf.length >= size) { chunks.push(buf); buf = ''; } }
  if (buf.trim()) chunks.push(buf); return chunks;
}
// `model` is kept only for signature compatibility with the existing call sites - ai_gateway owns model choice now.
async function llm(key: string, model: string, html: string): Promise<string | null> {
  try {
    const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: key, fn: 'translate_page', sys: SYS, input: html, max: 8000, temperature: 0.2 }) });
    const jd = await r.json(); if (!r.ok) return null;
    let out = jd?.content || ''; out = out.replace(/^```[a-z]*\n?/i, '').replace(/```\s*$/, '').trim(); return out || null;
  } catch (_e) { return null; }
}
Deno.serve(async (req) => {
  const b = await req.json().catch(() => ({} as any));
  const __exp = await sec('inbound_secret');
  if (!secretOk(__exp) || b.__secret !== __exp) return J({ error: 'forbidden' }, 403);
  const key = __exp; if (!key) return J({ error: 'no_key' }, 500);
  const source = String(b.source || ''); const slug = String(b.slug || ''); const model = b.model || 'openai/gpt-4o-mini'; const limit = Math.min(Number(b.limit || 5), 8);
  const { data: row } = await admin.from('qd_deploy_src').select('data').eq('path', 'src/content/' + source + '.json').maybeSingle();
  if (!row) return J({ error: 'no_source' }, 404);
  let data: any; try { data = JSON.parse((row as any).data); } catch (_e) { return J({ error: 'bad_json' }, 500); }
  const d = data[slug]; if (!d) return J({ error: 'no_slug' }, 404);
  const cs = chunk(d.html); const total = cs.length;
  const { data: have } = await admin.from('qd_i18n_chunks').select('idx').eq('source', source).eq('slug', slug);
  const haveSet = new Set((have || []).map((x: any) => x.idx));
  const missing: number[] = []; for (let i = 0; i < total; i++) if (!haveSet.has(i)) missing.push(i);
  const work = async () => {
    let n = 0;
    for (const i of missing) { if (n >= limit) break; const ar = await llm(key, model, cs[i]); if (ar != null) { await admin.from('qd_i18n_chunks').upsert({ source, slug, idx: i, ar }); n++; } }
    const { data: nowHave } = await admin.from('qd_i18n_chunks').select('idx, ar').eq('source', source).eq('slug', slug);
    if ((nowHave || []).length >= total) {
      const byIdx = new Map((nowHave || []).map((x: any) => [x.idx, x.ar]));
      const full = Array.from({ length: total }, (_, i) => byIdx.get(i) || '').join('');
      let at = await llm(key, 'openai/gpt-4o-mini', '<h1>' + d.title + '</h1>'); at = (at || d.title).replace(/<\/?h1>/g, '').trim();
      await admin.from('qd_i18n').upsert({ source, slug, title: at, html: full, status: 'done', updated_at: new Date().toISOString() });
    }
  };
  const ER = (globalThis as any).EdgeRuntime; if (ER && ER.waitUntil) ER.waitUntil(work()); else await work();
  return J({ ok: true, source, slug, total, have: haveSet.size, missing: missing.length });
});