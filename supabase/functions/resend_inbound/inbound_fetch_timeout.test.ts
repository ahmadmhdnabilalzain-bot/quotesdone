// Every Resend API read has a timeout (it_engineer, 10 Nov 2026, channels audit R7). fetch is a stub: no network.
// Red before: fetchInboundEmail and fetchInboundAttachmentBytes passed no signal, so a stalled Resend held the worker until the
// edge wall-clock killed it.
import { assert, assertEquals } from 'jsr:@std/assert@1';

Deno.test('both Resend reads carry a timeout, and a timed-out read is null (the caller\'s not-fetched path)', async () => {
  // the module builds its service client at import: give it the stub project first (as resend_inbound/index.test.ts does)
  if (!Deno.env.get('SUPABASE_URL')) Deno.env.set('SUPABASE_URL', 'https://db.invalid');
  if (!Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')) Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'stub-service-role');
  const { fetchInboundAttachmentBytes, fetchInboundEmail, RESEND_READ_MS } = await import('./lib/inbound_fetch.ts');
  const real = globalThis.fetch; const signals: (AbortSignal | null | undefined)[] = [];
  globalThis.fetch = ((_u: unknown, init?: RequestInit) => { signals.push(init?.signal); return Promise.reject(new DOMException('timed out', 'TimeoutError')); }) as typeof fetch;
  try {
    assertEquals(await fetchInboundEmail('em_zz_demo', 're_stub'), null);
    assertEquals(await fetchInboundAttachmentBytes('em_zz_demo', 'att_zz', 're_stub'), null);
  } finally { globalThis.fetch = real; }
  assertEquals(signals.length, 2);
  assert(signals.every((s) => s instanceof AbortSignal), 'a Resend read went out with no timeout');
  assertEquals(RESEND_READ_MS, 15_000);
});
