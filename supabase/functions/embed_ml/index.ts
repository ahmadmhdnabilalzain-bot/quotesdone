// embed_ml — THE MULTILINGUAL EMBEDDER'S ONE HOME. Seat: it_engineer (shared platform). 24 Sep 2026.
//
// The model (_shared/ml_embed.ts, 45.5 MB) loads only in this function's workers, so no seat and no LLM path
// ever carries it: a seat asks over HTTP (_shared/ml_embed_client.ts) and on any failure takes the gte-small path.
// It used to live in ai_gateway; that deploy failed (npm import) and the full model could not fit a worker.
//
//   { action: 'query', text }   one question -> its vector ('[...]', space 'ml'); 503 embed_failed when there is none
//   { action: 'tick', limit }   one pass of the knowledge_vector_ml queue, at most ML_TICK_MAX rows (resilience_ping
//                               is the clock; the backlog is embedded by .github/workflows/ml-embed-backfill.yml on a
//                               runner, not here). The gate and the daily cap live in fn_ml_embed_claim.
//   { action: 'gte', text }     one text -> its gte-small vector (Supabase.ai), for the runner backfill's
//                               support/ceo rows, so the gte space is only ever made by Supabase's own model
// Authenticated like ai_gateway: the caller presents cred_fn_ai (context fn.ai, scope includes 'embed_ml') and
// names itself in `fn`.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { embedQueryMl, embedQueueOnce, ML_TICK_MAX } from '../_shared/ml_embed.ts';
import { embedLine } from '../_shared/gte_embed.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method !== 'POST') return J({ ok: false, error: 'method' }, 405);
  const body = await req.json().catch(() => null) as Record<string, unknown> | null;
  if (!body) return J({ ok: false, error: 'bad_json' }, 400);
  const auth = await requireInternal(admin, body.__secret, 'embed_ml', body.fn);
  if (!auth.ok) return J({ ok: false, error: auth.error }, auth.status);
  if (body.action === 'query') {
    const v = await embedQueryMl(String(body.text || ''));
    return v ? J({ ok: true, space: 'ml', embedding: '[' + v.join(',') + ']' }) : J({ ok: false, error: 'embed_failed' }, 503);
  }
  if (body.action === 'gte') {
    const v = await embedLine(String(body.text || ''));
    return v ? J({ ok: true, space: 'gte', embedding: '[' + v.join(',') + ']' }) : J({ ok: false, error: 'embed_failed' }, 503);
  }
  if (body.action === 'tick') {
    const r = await embedQueueOnce(admin, Math.max(1, Math.min(Number(body.limit) || ML_TICK_MAX, ML_TICK_MAX)));
    return J(r, r.ok ? 200 : 503);
  }
  return J({ ok: false, error: 'unknown_action' }, 400);
});
