// The /u/* mail links: a public edge function served as HTML on our own domain.
//
// Supabase serves every edge-function response on *.supabase.co as `text/plain` with
// `X-Content-Type-Options: nosniff`, whatever Content-Type the function sets (measured 24 Sep 2026 on
// /u/unsubscribe: the customer saw raw HTML source). A route handler can set the header; a rewrite cannot.
// This forwards the method, the query string and the form body unchanged and returns the function's own
// status and body as HTML. It holds no secret: each function it serves is public (verify_jwt off) and
// checks its own token.
export function forwardToFunction(name: string) {
  const fn = `${(process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://htdblwldjkcgjvmqkbeh.supabase.co').replace(/\/$/, '')}/functions/v1/${name}`;
  return async function forward(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const init: RequestInit = { method: req.method, headers: {}, redirect: 'manual', cache: 'no-store' };
    if (req.method === 'POST') {
      const ct = req.headers.get('content-type');
      if (ct) (init.headers as Record<string, string>)['content-type'] = ct;
      init.body = await req.text();
    }
    const r = await fetch(fn + url.search, init);
    return new Response(await r.text(), {
      status: r.status,
      headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' },
    });
  };
}
