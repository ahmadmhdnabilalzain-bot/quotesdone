// Public, rate-limited intake for crashes that happen in the visitor's browser (launch checklist,
// 19 Nov 2026, it_engineer). error.tsx and global-error.tsx post here through reportClientError()
// (src/lib/clientErrorReport.ts, which also says exactly what is and is never sent).
//
// This route writes nothing itself. It cleans the report again (the browser is not trusted), takes a
// per-IP slot from the estate's one limiter (rl_check, the same RPC public_site and site_assistant
// spend: 20 reports per IP per 10 minutes, the IP hashed so the limiter row holds no address), and
// forwards to the site_error_ingest edge function with SITE_ERROR_INGEST_SECRET, exactly as
// src/instrumentation.ts does for server errors. error_events is written by that function only.
//
// A LIMITER OUTAGE FAILS OPEN, a missing ingest secret fails quietly: the page that crashed has
// already failed once and must not fail twice, and the answer is always an empty 204 to the browser
// (429 when limited). A coarse per-instance cap sits behind the limiter so an outage of the limiter
// cannot turn this into an unbounded writer. Cookies, headers and bodies are never read beyond the
// JSON report; nothing is logged.
import { SUPA_URL } from '@/lib/supaEnv';
import { cleanReport } from '@/lib/clientErrorReport';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const MAX_BODY = 4096;
const PER_IP = 20;
const WINDOW_S = 600;
const INSTANCE_PER_MIN = 60;
let minute = 0, count = 0;
function instanceBusy(): boolean {
  const m = Math.floor(Date.now() / 60_000);
  if (m !== minute) { minute = m; count = 0; }
  return ++count > INSTANCE_PER_MIN;
}

const serviceKey = () => process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '';

async function hashIp(ip: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('client_error:' + ip));
  return Array.from(new Uint8Array(d)).slice(0, 12).map((x) => x.toString(16).padStart(2, '0')).join('');
}

async function allowed(ip: string): Promise<boolean> {
  const key = serviceKey();
  if (!key || !SUPA_URL) return true; // no limiter reachable: the instance cap still applies
  try {
    const r = await fetch(`${SUPA_URL}/rest/v1/rpc/rl_check`, {
      method: 'POST',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_key: 'client_error_ip:' + (await hashIp(ip)), p_limit: PER_IP, p_seconds: WINDOW_S }),
      signal: AbortSignal.timeout(2500),
    });
    if (!r.ok) return true;
    return (await r.json().catch(() => true)) !== false;
  } catch { return true; }
}

export async function POST(req: Request) {
  const none = (status: number) => new Response(null, { status, headers: { 'Cache-Control': 'no-store' } });
  // Same-origin only: a cross-site page cannot post fabricated crashes through a visitor's browser.
  const origin = req.headers.get('origin');
  const host = req.headers.get('host');
  if (origin) { try { if (new URL(origin).host !== host) return none(403); } catch { return none(403); } }
  const secret = process.env.SITE_ERROR_INGEST_SECRET;
  if (!secret || !SUPA_URL) return none(204);
  let text = '';
  try { text = await req.text(); } catch { return none(400); }
  if (text.length > MAX_BODY) return none(413);
  let parsed: unknown = null;
  try { parsed = JSON.parse(text); } catch { return none(400); }
  const report = cleanReport(parsed);
  if (!report) return none(400);
  if (instanceBusy()) return none(429);
  const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown';
  if (!(await allowed(ip))) return none(429);
  try {
    await fetch(`${SUPA_URL}/functions/v1/site_error_ingest`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-qd-site-secret': secret },
      body: JSON.stringify({
        kind: 'runtime_error', message: report.message, route: 'client', path: report.path, digest: report.digest,
        render_source: 'client', user_agent: report.user_agent,
        env: process.env.VERCEL_ENV || 'unknown', deployment: process.env.VERCEL_DEPLOYMENT_ID || null,
      }),
      signal: AbortSignal.timeout(3000),
    }).catch(() => {});
  } catch { /* reporting never throws */ }
  return none(204);
}
