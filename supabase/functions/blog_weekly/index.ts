// blog_weekly v1 — autonomous weekly SEO blog engine.
// Generates one SEO-optimized post from the marketing brain, avoids duplicate topics,
// publishes to blog_posts (or drafts if publish:false), logs, and files a review task.
// Auth: __secret == inbound_secret. Body: { publish?:bool=true }
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const llm = makeLlm(SONNET_FIRST, { max: 3500, temperature: 0.6 });
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
async function sec(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
const slugify = (t: string) => t.toLowerCase().replace(/&/g, ' and ').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 70);

async function llmJSON(sys: string, user: string): Promise<any | null> {
  let c = await llm(sys, user);
  if (!c) return null;
  try {
    c = String(c).replace(/^```json/i, '').replace(/^```/, '').replace(/```$/, '').trim();
    const a = c.indexOf('{'); const b = c.lastIndexOf('}'); if (a >= 0 && b > a) c = c.slice(a, b + 1);
    return JSON.parse(c);
  } catch (_e) {}
  return null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' } });
  const body = await req.json().catch(() => ({} as any));
  const __exp = await sec('inbound_secret');
  // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
  // per-context credential and the legacy shared secret, and records which one called.
  const __auth = await requireInternal(admin, body?.__secret, 'blog_weekly');
  if (!__auth.ok) return J({ error: 'forbidden' }, 403);
  const started = new Date().toISOString();
  const publish = body.publish !== false;
  try {
    const { data: recent } = await admin.from('blog_posts').select('title,slug').order('published_at', { ascending: false }).limit(40);
    const taken = (recent || []).map((r: any) => r.title).filter(Boolean);
    let brain = ''; try { const { data } = await admin.rpc('fn_agent_context', { p_agent_key: 'marketing', p_max_chars: 5000 }); brain = data ? String(data) : ''; } catch (_e) {}

    const sys = 'You are the QuotesDone content + SEO writer. QuotesDone is a UAE B2B anonymous quotation marketplace where customers post a job and verified UAE suppliers quote anonymously; the customer pays a 3% reveal fee only on the quote they accept. Write for UAE SMEs searching for pricing/how-to on business services (fit-out, AC, cleaning, CCTV, electrical, signage, facilities, movers, printing, etc.). Follow the brand voice in the knowledge below. Practical, trustworthy, no invented statistics, no fluff. British/UAE English.\n\n' + brain;
    const user = 'Write ONE fresh, SEO-optimised blog article for quotesdone.com/blog targeting a high-intent UAE search query we have NOT covered. Avoid these existing titles: ' + JSON.stringify(taken).slice(0, 1500) + '.\n\nRules:\n- Pick a specific long-tail keyword an SME would search (e.g. "office fit out cost per square foot dubai", "how to compare AC maintenance quotes uae").\n- 700-1000 words, body in clean semantic HTML using <h2>, <h3>, <p>, <ul><li>, and a short <h2>FAQ</h2> with 3 Q/A.\n- Include 2 contextual internal links: one to a relevant service on https://quotesdone.com/ and one CTA link to https://quotesdone.com/app (anchor like "get anonymous quotes"). Do not invent other pages.\n- Mention the anonymous-quotes + verified-suppliers angle naturally once; mention the 3% reveal fee only if relevant. No emojis.\n- Return ONLY minified JSON: {"title","meta_desc"(<=155 chars),"excerpt"(<=200 chars),"category"(one of: Cost Guides, How-To, Buyer Guides, Industry),"keyword","body_html"}. body_html must NOT include an <h1> (the page renders the title separately).';

    const post = await llmJSON(sys, user);
    if (!post || !post.title || !post.body_html) return J({ error: 'generation_failed' }, 200);

    let slug = slugify(post.title);
    const { data: exists } = await admin.from('blog_posts').select('slug').eq('slug', slug).maybeSingle();
    if (exists) slug = slug + '-' + Date.now().toString().slice(-4);
    const { data: mx } = await admin.from('blog_posts').select('sort').order('sort', { ascending: false }).limit(1).maybeSingle();
    const sort = (mx?.sort || 0) + 1;

    const row = {
      slug, title: String(post.title).slice(0, 200),
      excerpt: String(post.excerpt || '').slice(0, 300),
      meta_desc: String(post.meta_desc || '').slice(0, 170),
      body_html: String(post.body_html).slice(0, 40000),
      author: 'QuotesDone Team',
      category: String(post.category || 'Guides').slice(0, 60),
      published: publish, published_at: publish ? new Date().toISOString() : null,
      updated_at: new Date().toISOString(), sort,
    };
    const { data: ins, error } = await admin.from('blog_posts').insert(row).select('id,slug,title').maybeSingle();
    if (error) return J({ error: error.message }, 200);

    await admin.from('crm_tasks').insert({ title: (publish ? 'Blog published: ' : 'Blog draft ready: ') + row.title, detail: 'Keyword: ' + (post.keyword || '-') + '\nURL: https://quotesdone.com/blog/' + slug + '\nAuto-generated by the weekly blog engine — review/edit anytime.', priority: 'low', source: 'agent:marketing', status: 'open' });
    await admin.from('agent_runs').insert({ agent: 'blog_weekly', started_at: started, finished_at: new Date().toISOString(), status: 'ok', counts: { published: publish ? 1 : 0, drafted: publish ? 0 : 1 } });
    return J({ ok: true, published: publish, id: ins?.id, slug, title: row.title, keyword: post.keyword || null, url: 'https://quotesdone.com/blog/' + slug });
  } catch (e) {
    await admin.from('agent_runs').insert({ agent: 'blog_weekly', started_at: started, finished_at: new Date().toISOString(), status: 'error', note: String(e).slice(0, 200) });
    return J({ error: String((e as Error)?.message || e) }, 200);
  }
});
