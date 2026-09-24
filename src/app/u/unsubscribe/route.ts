// /u/unsubscribe — the unsubscribe link in every supplier mail (24 Sep 2026, marketing, ledger 993).
//
// MEASURED 24 Sep 2026: this path was a next.config.mjs rewrite straight to the `unsubscribe` edge
// function, and Supabase serves every edge-function response on *.supabase.co as `text/plain` with
// `X-Content-Type-Options: nosniff`, whatever Content-Type the function sets. So a supplier who clicked
// "Unsubscribe" saw the page's raw HTML source, with no button they could press, and the only way out
// left was a mail client's one-click POST. The rewrite could not fix the header; this handler can.
//
// It forwards the method, the query string and the form body to the function unchanged (so the RFC 8058
// one-click POST and the confirm button still reach it, and the function keeps every rule: token check,
// GET is safe, POST suppresses), and returns the function's own status and body as HTML.
// It holds no secret: the function is public (verify_jwt off) and checks its own signed token.
export const dynamic = 'force-dynamic';

const FN = `${(process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://htdblwldjkcgjvmqkbeh.supabase.co').replace(/\/$/, '')}/functions/v1/unsubscribe`;

async function forward(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const init: RequestInit = { method: req.method, headers: {}, redirect: 'manual', cache: 'no-store' };
  if (req.method === 'POST') {
    const ct = req.headers.get('content-type');
    if (ct) (init.headers as Record<string, string>)['content-type'] = ct;
    init.body = await req.text();
  }
  const r = await fetch(FN + url.search, init);
  return new Response(await r.text(), {
    status: r.status,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' },
  });
}

export const GET = forward;
export const POST = forward;
