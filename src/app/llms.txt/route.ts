import geo from '@/content/geo.json';

// /llms.txt — the plain-text summary answer engines read (llmstxt.org). Owner: marketing (geo_check).
// The text lives in src/content/geo.json so the name-rule test reads exactly what is served.
export const dynamic = 'force-static';

export function GET() {
  return new Response(geo.llms.join('\n') + '\n', {
    headers: { 'content-type': 'text/plain; charset=utf-8' },
  });
}
