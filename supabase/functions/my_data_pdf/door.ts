// my_data_pdf/door.ts — "Download my data" on both portals: the person's own data copy as a PDF in the QuotesDone template.
//
// customer_support (built by it_engineer), 12 Nov 2026, founder ledgers 1669 and 1671 ("Download my data should be a
// pdf with our template"). The template and the brand fonts live server-side (_shared/doc_template.ts,
// ../pdf_native/render.ts), so the document is made here. pdf_native itself is an INTERNAL door (an internal secret or
// an admin aal2 session) that stores what it draws in a shared bucket; a person's data copy must do neither, so this is
// its own door, and it reuses only the pure renderer.
//
// WHO CAN REACH IT, AND WHAT IS KEPT:
//   - the caller's own session: signedInUser refuses an absent, expired or revoked token (401) and says "try again"
//     when auth is down (503), never "signed out";
//   - the data is read AS THAT PERSON: pdpl_request_me('export') is called with the caller's JWT, so the routine's own
//     check decides whose data it is (the JWT e-mail, which must be a verified account e-mail) and logs the request in
//     pdpl_requests and pdpl_operator_log as every export is. There is no parameter naming whose data to draw;
//   - the service-role client reads only the letterhead identity (company_registration, company_brand);
//   - nothing is stored (no bucket, no table row beyond the routine's own request log) and nothing of the document is
//     logged: observe() records the status and the time only. The bytes go back in the response, marked no-store;
//   - CORS answers only the site's own origins (siteCors), as every endpoint returning personal data does.
//   - verify_jwt = false in supabase/config.toml (review of #1986, item 6), so the CLI deploys it that way: this door checks
//     the session itself through signedInUser, which refuses a bad token locally and answers an auth outage with a
//     retryable 503 instead of the gateway's 401 ("signed out"), and the browser's CORS preflight (no Authorization
//     header) reaches the OPTIONS answer below. Nothing here is reachable without a signed-in person's own token.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { refusalBody, signedInUser } from '../_shared/signed_in_user.ts';
import { docIdentity } from '../_shared/doc_template.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { dataCopyBody, fileName, type Lang, type Role } from './document.ts';

const URL_ = Deno.env.get('SUPABASE_URL')!;
// Read when used, not at import: the test runner grants three environment names and this is not one of them.
const anonKey = () => { try { return Deno.env.get('SUPABASE_ANON_KEY') || ''; } catch { return ''; } };
const admin = createClient(URL_, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const ASSET = URL_ + '/storage/v1/object/public/brand';
// THE PREFLIGHT ALLOWS EVERY HEADER THE PAGE SENDS (13 Nov 2026, the founder's own iPhone, quotesdone.ae 07:49 Dubai time: "Something
// went wrong. Please try again."). PrivacyControls.tsx sends apikey, Authorization and Content-Type; this list said only
// 'authorization, content-type', so every browser refused to send the POST after the preflight (the edge log shows two OPTIONS 200
// and no POST). It had never worked in a real browser. Two signed-in walks and the author's own browser proof all passed, because
// each drove Playwright with request interception on (to tag demo traffic), and an intercepted request is not held to the preflight's
// header list. Prevented by: scripts/checks/every_header_the_site_sends_a_function_is_allowed_by_its_preflight.test.mjs, which reads
// both sides for every function the site calls, and door.test.ts.
// cache-control and pragma: the page fetches with cache: 'no-store'. By the Fetch standard a browser adds those two headers after the
// preflight list is computed, so they need no listing, and Chromium was measured not to ask for them. Safari could not be run here and
// it is the browser that failed, so they are listed anyway: allowing a header nobody sends costs nothing.
const CORS = { 'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info, cache-control, pragma', 'Access-Control-Expose-Headers': 'Content-Disposition' };
const NO_STORE = { 'Cache-Control': 'no-store, private, max-age=0', Pragma: 'no-cache', 'X-Content-Type-Options': 'nosniff' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, ...NO_STORE, 'Content-Type': 'application/json; charset=utf-8' } });

// The fonts and the lockup are public brand assets; kept for the life of the isolate (they change with a rebrand, not a day).
const assets = new Map<string, Uint8Array | null>();
async function fetchBytes(path: string): Promise<Uint8Array | null> {
  if (assets.has(path)) return assets.get(path)!;
  let b: Uint8Array | null = null;
  try { const r = await timedFetch(`${ASSET}/${path}`); if (r.ok) b = new Uint8Array(await r.arrayBuffer()); } catch { b = null; }
  if (b) assets.set(path, b);
  return b;
}

/** Which portal's copy this is. The portal says; the export confirms (a person with no company record is a customer). */
export function roleFor(asked: unknown, exp: Record<string, unknown>): Role {
  const hasCompany = Array.isArray(exp.supplier_records) && exp.supplier_records.length > 0;
  const hasAccount = Array.isArray(exp.customer_accounts) && exp.customer_accounts.length > 0;
  if (asked === 'supplier' && hasCompany) return 'supplier';
  if (asked === 'customer' && hasAccount) return 'customer';
  return hasCompany && !hasAccount ? 'supplier' : 'customer';
}

export async function handle(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return J({ error: 'method_not_allowed' }, 405);
  const who = await signedInUser(admin, req.headers.get('Authorization'));
  if (!who.ok) return J(refusalBody(who), who.status);
  // deno-lint-ignore no-explicit-any
  const body: any = await req.json().catch(() => ({}));
  const lang: Lang = body?.lang === 'ar' ? 'ar' : 'en';

  // The export, as the person: the same routine and the same check the JSON copy goes through.
  const r = await timedFetch(`${URL_}/rest/v1/rpc/pdpl_request_me`, {
    method: 'POST',
    headers: { apikey: anonKey(), Authorization: req.headers.get('Authorization')!, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_kind: 'export' }),
  });
  if (!r.ok) return J({ error: 'export_failed' }, 502);
  const j = await r.json().catch(() => null);
  if (!j?.ok || !j.export) {
    const code = String(j?.code || 'export_refused');
    return J({ ok: false, code }, code === 'email_not_verified' ? 403 : code === 'too_many_exports' ? 429 : 409);
  }

  const doc = dataCopyBody({ exp: j.export, lang, role: roleFor(body?.role, j.export) });
  const out = await renderPdf(doc, { fetchBytes, identity: await docIdentity(admin) });
  if (!out.ok) return J({ error: 'render_failed' }, 500);
  return new Response(out.bytes as unknown as BodyInit, { status: 200, headers: { ...CORS, ...NO_STORE,
    'Content-Type': 'application/pdf', 'Content-Disposition': `attachment; filename="${fileName()}"` } });
}
