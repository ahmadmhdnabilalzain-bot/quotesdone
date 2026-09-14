import { execFileSync } from 'node:child_process';
import services from '@/content/services.json';
import legal from '@/content/legal.json';
import marketing from '@/content/marketing.json';
import blog from '@/content/blog.json';

// Built once per deploy: every input is a file in the repository, so there is nothing for a
// request-time render to learn. (It was force-dynamic.)
export const dynamic = 'force-static';

const BASE = 'https://quotesdone.com';

// <lastmod> is the date the content behind a URL last changed — the last commit touching its
// source file — never the build time, which would claim every page changed on every deploy.
// ponytail: on a shallow clone a file untouched within the clone depth reports the oldest commit
// in the clone (too recent, never too old); if git is absent the tag is omitted, not guessed.
const lastmod = (() => {
  const memo = new Map<string, string | null>();
  return (...files: string[]): string | null => {
    const key = files.join('|');
    if (!memo.has(key)) {
      let d: string | null = null;
      try { d = execFileSync('git', ['log', '-1', '--format=%cs', '--', ...files], { encoding: 'utf8' }).trim() || null; } catch { d = null; }
      memo.set(key, d);
    }
    return memo.get(key)!;
  };
})();

type Post = { published_at: string | null; ar?: { title?: string } };

export async function GET() {
  const rows: string[] = [];
  const url = (loc: string, mod: string | null, freq: string, pri: number) =>
    `<url><loc>${loc}</loc>${mod ? `<lastmod>${mod}</lastmod>` : ''}<changefreq>${freq}</changefreq><priority>${pri.toFixed(1)}</priority></url>`;
  const push = (path: string, pri: number, mod: string | null) => {
    rows.push(url(`${BASE}${path}`, mod, 'weekly', pri));
    rows.push(url(`${BASE}/ar${path}`, mod, 'weekly', pri * 0.9));
  };
  push('', 1.0, lastmod('messages/en.json', 'messages/ar.json', 'src/components'));
  const mk = lastmod('src/content/marketing.json');
  for (const slug of Object.keys(marketing as Record<string, unknown>)) push('/' + slug, slug === 'services' ? 0.8 : 0.6, mk);
  const lg = lastmod('src/content/legal.json');
  for (const slug of Object.keys(legal as Record<string, unknown>)) push('/' + slug, 0.3, lg);
  // Only the 24 canonical service pages. The 168 emirate variants per locale canonicalise to these
  // (src/lib/seo.ts splitServiceSlug) and a sitemap lists canonical URLs only.
  const sv = lastmod('src/content/services.json');
  for (const slug of Object.keys(services as Record<string, unknown>)) push('/services/' + slug, 0.7, sv);
  // Two public pages that are React routes, not marketing.json entries. /supplier stopped being the
  // portal on 14 Sep 2026 and is the supplier sales page; its copy lives in messages/*.json.
  const msgs = ['messages/en.json', 'messages/ar.json'];
  push('/supplier', 0.7, lastmod('src/app/[locale]/supplier/page.tsx', ...msgs));
  push('/how-it-works', 0.6, lastmod('src/app/[locale]/how-it-works', ...msgs));
  // Blog posts come from the same baked content file the /blog/[slug] route uses. The /ar URL is
  // listed only for a post that carries an Arabic branch.
  for (const [slug, p] of Object.entries(blog as unknown as Record<string, Post>)) {
    const mod = p.published_at ? p.published_at.slice(0, 10) : null;
    rows.push(url(`${BASE}/blog/${slug}`, mod, 'monthly', 0.5));
    if (p.ar?.title) rows.push(url(`${BASE}/ar/blog/${slug}`, mod, 'monthly', 0.45));
  }
  const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${rows.join('\n')}\n</urlset>`;
  return new Response(xml, { headers: { 'Content-Type': 'application/xml; charset=utf-8', 'Cache-Control': 'public, max-age=3600, s-maxage=3600' } });
}
