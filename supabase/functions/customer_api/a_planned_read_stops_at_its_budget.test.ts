// The planned PDF read (drawing_plan.ts) never starts a call past its own budget (review, 17 Nov 2026): a long set cannot
// hold analyze_drawing past the redaction's start-by or the edge wall. Past it the call is no answer, which readPdfPlan
// turns into the old parse failure (no server boxes).
import { assertEquals } from 'jsr:@std/assert@1';
Deno.env.set('SUPABASE_URL', Deno.env.get('SUPABASE_URL') || 'http://127.0.0.1:1');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || 'test');
const { pdfPlanCall } = await import('./lib/drawings.ts');

Deno.test('a plan call past its budget is no answer, and nothing is fetched', async () => {
  const real = globalThis.fetch; let fetched = 0;
  globalThis.fetch = (() => { fetched++; return Promise.reject(new Error('no network in this test')); }) as typeof fetch;
  try {
    assertEquals(await pdfPlanCall('x', 'JVBERi0=', Date.now() - 1)({ mode: 'plan', step: 'strips', from: 0, to: 1 }), null);
    assertEquals(await pdfPlanCall('x', 'JVBERi0=', Date.now() + 500)({ mode: 'plan', step: 'strips', from: 0, to: 1 }), null);
    assertEquals(fetched, 0);
  } finally { globalThis.fetch = real; }
});
