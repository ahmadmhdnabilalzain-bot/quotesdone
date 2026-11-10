// db_region.ts - an edge function that calls another edge function names the DATABASE's region (customer_support, 10 Nov 2026).
//
// WHY. Supabase runs a function in the edge region nearest its CALLER; the database is in ap-southeast-1 (Singapore). A Twilio
// webhook enters at us-east-1, so wa_inbound runs there, and every function it calls (ai_gateway, embed_ml) ran there too:
// each of their database round trips crossed the Pacific. Measured on production (agent_runs fn:ai_gateway joined to
// llm_attempt, 7 days to 10 Nov 2026), the gateway's own work BEFORE the provider call:
//   us-east-1       n=1,788  p50 3,337 ms
//   ap-southeast-1  n=534    p50   357 ms
// and from the edge logs of the WhatsApp walks (15:15-16:10Z): a gateway call refused before any model (503) p50 2,733 ms in
// us-east-1 against 391 ms in ap-southeast-1; embed_ml p50 916 ms against 170 ms, and all 419 embed_ml 546s (WORKER_LIMIT)
// in that window were us-east-1 workers. A WhatsApp turn makes two to four gateway calls in series, so ~3 s each was
// 6-12 s of every reply. One caller-to-Singapore hop costs less than the callee's dozen database trips from elsewhere.
//
// The QUERY PARAMETER, as the portals (src/lib/supaEnv.ts fnUrl) and resilience_ping's launch path already do: the edge
// routes on it, and a receiving function reads only the pathname (observe.ts pathOf, every *_test pathname match). A caller
// keeps the literal '/functions/v1/<slug>' in its own source (inDbRegion(SUPABASE_URL + '/functions/v1/ai_gateway')), so
// no_function_calls_an_undeployed_function still sees the callee.
// prevented by: _shared/db_region.test.ts
export const DB_REGION = 'ap-southeast-1';

/** `url` with forceFunctionRegion=DB_REGION added (kept as it is when it already names a region). */
export function inDbRegion(url: string): string {
  if (/[?&]forceFunctionRegion=/.test(url)) return url;
  return url + (url.includes('?') ? '&' : '?') + 'forceFunctionRegion=' + DB_REGION;
}

