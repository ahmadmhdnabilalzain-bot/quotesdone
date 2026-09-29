// THE MARKETING SEAT'S BUSINESS DEVELOPMENT, FROM THE COMMAND LINE (marketing, 22 Sep 2026; instruction 722).
//
//   node scripts/marketing/business_development.mjs prospects <prospects.json>
//   node scripts/marketing/business_development.mjs bake            # released articles -> src/content/blog.json
//
// The ingest-article and approve commands were REMOVED on 29 Sep 2026 (founder 1058, 1059; #1114): a blog is a market
// topic the marketing seat drafts and the CEO seat reviews (supabase/functions/marketing/duties.ts blog_article). A
// hand-written article, or an approval by the founder or Claude, could never be released, so neither door is kept.
//
// prospects: people found on PUBLIC pages (company site, directory, press). LinkedIn is never scraped, and a
// person whose only source is LinkedIn is refused. Each: full_name, role_title, company, segment
// (developer|contractor_procurement|consultant|facility_manager), language (en|ar), source_urls[], optional
// emirate, linkedin_url (only if publicly linked), opening_line + opening_line_url (a cited sentence about the
// COMPANY, never a personal detail).
//
// bake: the website blog is baked at build (src/content/blog.json, /blog/[slug], the sitemap and the
// BlogPosting data all read it). Released articles are written into it here; commit the file in a PR and the
// deploy publishes them. The seat marks each live when its page answers, which schedules its LinkedIn post.
// Then run: node scripts/checks/blog_index_matches_data.mjs
//
// UTF-8 throughout (a Windows-shell curl once sent Arabic as question marks). Never prints a key.
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REF = 'htdblwldjkcgjvmqkbeh';
const REPO = fileURLToPath(new URL('../..', import.meta.url));
const [cmd, a1] = process.argv.slice(2);
const mgmtToken = () => (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

async function sql(query) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + mgmtToken(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ query, read_only: true }),
  });
  const j = await r.json();
  if (!Array.isArray(j)) throw new Error('query failed: ' + JSON.stringify(j).slice(0, 300));
  return j;
}

async function call(action, payload) {
  const keys = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`, { headers: { Authorization: 'Bearer ' + mgmtToken() } })).json();
  const service = keys.find?.((k) => k.name === 'service_role')?.api_key;
  const cred = (await sql("select value from public.app_secrets where key = 'cred_fn_marketing_outreach'"))[0]?.value;
  if (!service || !cred) throw new Error('could not read the service key or cred_fn_marketing_outreach');
  const r = await fetch(`https://${REF}.supabase.co/functions/v1/marketing_outreach`, {
    method: 'POST', headers: { 'Content-Type': 'application/json; charset=utf-8', Authorization: 'Bearer ' + service },
    body: JSON.stringify({ __secret: cred, action, ...payload }),
  });
  return r.json().catch(() => ({ ok: false, status: r.status }));
}

async function main() {
  if (cmd === 'prospects') return call('ingest_prospects', { prospects: JSON.parse(readFileSync(a1, 'utf8')) });
  if (cmd === 'bake') {
    const rows = await sql(`select slug, title_en, excerpt_en, meta_desc_en, category_en, body_html_en, title_ar, excerpt_ar,
                                   meta_desc_ar, category_ar, body_html_ar, released_at
                              from public.marketing_article where status in ('released', 'live') and not is_demo order by released_at`);
    const file = join(REPO, 'src/content/blog.json');
    const blog = JSON.parse(readFileSync(file, 'utf8'));
    let added = 0;
    for (const r of rows) {
      if (!blog[r.slug]) added++;
      blog[r.slug] = {
        slug: r.slug, title: r.title_en, excerpt: r.excerpt_en, meta_desc: r.meta_desc_en, body_html: r.body_html_en,
        author: 'QuotesDone', category: r.category_en, published_at: r.released_at,
        // newest first on /blog: the index sorts ascending, the 32 June guides use 10..320
        sort: -Number(String(r.released_at).slice(0, 10).replace(/-/g, '')),
        ar: { title: r.title_ar, excerpt: r.excerpt_ar, meta_desc: r.meta_desc_ar, category: r.category_ar, body_html: r.body_html_ar },
      };
    }
    writeFileSync(file, JSON.stringify(blog, null, 2) + '\n');   // the file's own format: a bake adds lines, never reflows
    return { ok: true, released: rows.length, added, file: 'src/content/blog.json' };
  }
  console.error('usage: node scripts/marketing/business_development.mjs prospects <file> | bake');
  process.exit(2);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().then((out) => { console.log(JSON.stringify(out, null, 2)); process.exit(out?.ok === false ? 1 : 0); })
    .catch((e) => { console.error(String(e?.message || e)); process.exit(1); });
}
