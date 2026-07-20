import services from '@/content/services.json';
import legal from '@/content/legal.json';
import marketing from '@/content/marketing.json';
import blog from '@/content/blog.json';

export const dynamic = 'force-dynamic';

const BASE = 'https://quotesdone.com';
const EM = ['abu-dhabi', 'ajman', 'dubai', 'fujairah', 'ras-al-khaimah', 'sharjah', 'umm-al-quwain'];

export async function GET() {
  const rows: string[] = [];
  const push = (path: string, pri: number, both = true) => {
    rows.push(`<url><loc>${BASE}${path}</loc><changefreq>weekly</changefreq><priority>${pri.toFixed(1)}</priority></url>`);
    if (both) rows.push(`<url><loc>${BASE}/ar${path}</loc><changefreq>weekly</changefreq><priority>${(pri * 0.9).toFixed(1)}</priority></url>`);
  };
  push('', 1.0);
  for (const slug of Object.keys(marketing as Record<string, unknown>)) push('/' + slug, slug === 'services' ? 0.8 : 0.6);
  for (const slug of Object.keys(legal as Record<string, unknown>)) push('/' + slug, 0.3);
  for (const slug of Object.keys(services as Record<string, unknown>)) {
    push('/services/' + slug, 0.7);
    for (const e of EM) push('/services/' + slug + '-in-' + e, 0.6);
  }
  // Blog posts come from the same baked content file the /blog/[slug] route
  // uses. This previously fetched Supabase at request time and swallowed any
  // error in a catch — the anon role lacked SELECT on blog_posts, so all 32
  // posts were silently absent from the sitemap.
  for (const slug of Object.keys(blog as Record<string, unknown>)) {
    rows.push(`<url><loc>${BASE}/blog/${slug}</loc><changefreq>monthly</changefreq><priority>0.5</priority></url>`);
  }
  const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${rows.join('\n')}\n</urlset>`;
  return new Response(xml, { headers: { 'Content-Type': 'application/xml; charset=utf-8', 'Cache-Control': 'public, max-age=3600, s-maxage=3600' } });
}
