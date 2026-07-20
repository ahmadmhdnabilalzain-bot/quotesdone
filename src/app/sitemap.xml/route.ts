import services from '@/content/services.json';
import legal from '@/content/legal.json';
import marketing from '@/content/marketing.json';

export const dynamic = 'force-dynamic';

const BASE = 'https://quotesdone.com';
const SB = 'https://htdblwldjkcgjvmqkbeh.supabase.co';
const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh0ZGJsd2xkamtjZ2p2bXFrYmVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA3ODU1NDYsImV4cCI6MjA5NjM2MTU0Nn0.cF9ZR_Qo1YBhLvhTLS8aANlYb6c9rTsuQS6kLxGw_Bo';
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
  try {
    const r = await fetch(`${SB}/rest/v1/blog_posts?select=slug&published=eq.true&order=published_at.desc&limit=500`, { headers: { apikey: ANON, Authorization: 'Bearer ' + ANON } });
    const posts = await r.json();
    if (Array.isArray(posts)) for (const p of posts) if (p?.slug) rows.push(`<url><loc>${BASE}/blog/${p.slug}</loc><changefreq>monthly</changefreq><priority>0.5</priority></url>`);
  } catch (_e) { /* blog optional */ }
  const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${rows.join('\n')}\n</urlset>`;
  return new Response(xml, { headers: { 'Content-Type': 'application/xml; charset=utf-8', 'Cache-Control': 'public, max-age=3600, s-maxage=3600' } });
}
