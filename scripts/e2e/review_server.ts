// scripts/e2e/review_server.ts — the pre-deploy stand-in for the nine quotation-review actions.
// Assigned: sales_engineer. Started by scripts/e2e/supplier_quote_review.mjs; not part of the product.
//
// WHY IT EXISTS. The review lives in supabase/functions/supplier_api, and the E2E drives the REAL
// portal against production. Before the SQL is applied and the function deployed, production answers
// nothing for these nine actions, so there would be no way to see the conversation work in a browser
// without deploying it first — which is exactly the order this repository refuses. This process runs
// the SAME code (quote_review_actions.ts, unchanged) with the conversation held in memory
// (quote_review_memory_repo.ts), and forwards `inbox`, `submit_quote` and `quote_pdf` to production,
// so the job, its scrubbers, the hold gate and the submission are the real ones.
//
//   deno run --allow-net --allow-env --allow-read scripts/e2e/review_server.ts
//   PORT (default 8787), QD_ANON_KEY (required: the project's publishable key), QD_FN_URL
//
// It holds no service-role key and cannot write a table: every database effect it has is one that
// production's own supplier_api performed for the caller's own session.
import { reviewAction, REVIEW_ACTIONS, type Self, type Supplier } from '../../supabase/functions/supplier_api/quote_review_actions.ts';
import { memoryReviewRepo } from '../../supabase/functions/supplier_api/quote_review_memory_repo.ts';
import type { ReviewDeps } from '../../supabase/functions/supplier_api/quote_review_flow.ts';
import { sanitizeUpload, SAFE_DOCS } from '../../supabase/functions/_shared/attachment.ts';

const PORT = Number(Deno.env.get('PORT') || 8787);
const ANON = Deno.env.get('QD_ANON_KEY') || '';
const FN_URL = Deno.env.get('QD_FN_URL') || 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_api?forceFunctionRegion=ap-southeast-1';
if (!ANON) { console.error('review_server: QD_ANON_KEY is required'); Deno.exit(2); }

/** One conversation store per supplier, for the life of this process. */
const stores = new Map<number, ReturnType<typeof memoryReviewRepo>>();
const storeFor = (id: number) => { let s = stores.get(id); if (!s) { s = memoryReviewRepo(); stores.set(id, s); } return s; };

const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'authorization, content-type, apikey, x-client-info', 'access-control-allow-methods': 'POST, OPTIONS' };
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { ...CORS, 'content-type': 'application/json' } });

/** Production's own supplier_api, as the caller. Every read and every write goes through it. */
const selfFor = (auth: string): Self => async (body) => {
  const r = await fetch(FN_URL, { method: 'POST', headers: { authorization: auth, apikey: ANON, 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const text = await r.text();
  try { return { status: r.status, json: JSON.parse(text) }; } catch { return { status: r.status, json: { error: text.slice(0, 300) } }; }
};

/** The byte-type gate only: this process does no malware lookup, so it reaches nothing. */
const scan: ReviewDeps['scan'] = (data, filename, mime) => {
  const s = sanitizeUpload({ input: data, declaredMime: mime, filename, allow: SAFE_DOCS });
  return Promise.resolve(s.ok
    ? { ok: true as const, bytes: s.bytes, mime: s.mime, name: filename }
    : { ok: false as const, status: 415, code: String(s.error), message: 'That file type cannot be accepted.' });
};

Deno.serve({ port: PORT, onListen: () => console.log(`review_server: listening on http://127.0.0.1:${PORT} → ${FN_URL}`) }, async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json(405, { error: 'post_only' });
  const auth = req.headers.get('authorization') || '';
  if (!auth) return json(401, { error: 'unauthorized' });
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json(400, { error: 'bad_json' }); }
  const action = String(body.action || '');
  if (!REVIEW_ACTIONS.has(action)) return json(404, { error: 'not_a_review_action', code: 'not_a_review_action' });

  const self = selfFor(auth);
  // The caller's own company, resolved by production from their session — never from this body.
  const me = await self({ action: 'me' });
  const s = (me.json as { supplier?: { id?: number; company_name?: string | null; locale?: string | null; claimed_by?: string | null } }).supplier;
  if (!s || !s.id || !s.claimed_by) return json(me.status === 200 ? 403 : me.status, { error: 'no_company', code: 'no_company' });
  const sup: Supplier = { id: Number(s.id), company_name: s.company_name ?? null, locale: s.locale ?? null };

  try {
    const res = await reviewAction({ sup, email: String(s.claimed_by).toLowerCase(), self, body, repo: storeFor(sup.id).repo, scan });
    return json(res.status, res.json);
  } catch (e) {
    console.error('review_server:', action, e);
    return json(500, { error: String(e instanceof Error ? e.message : e), code: 'standin_error' });
  }
});
