// compliance_watch.test.ts (it_engineer, OPS_LOOPS, 16 Nov 2026): the daily compliance fetch reads only allowlisted hosts,
// signs a page by its readable text, records every source it was given, and never treats a failed fetch as a check.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { hostAllowed, readableText, readSource, runComplianceWatch } from './compliance_watch.ts';

const page = (body: string, status = 200, headers: Record<string, string> = { 'content-type': 'text/html; charset=utf-8' }) =>
  new Response(body, { status, headers });

Deno.test('a host is allowed only when it is a registered source host (with or without www.)', () => {
  const allowed = ['www.dm.gov.ae', 'tdra.gov.ae'];
  assert(hostAllowed('https://www.dm.gov.ae/a', allowed));
  assert(hostAllowed('https://dm.gov.ae/a', allowed));
  assert(hostAllowed('https://www.tdra.gov.ae/x', allowed));
  assert(!hostAllowed('https://evil.example/a', allowed));
  assert(!hostAllowed('https://dm.gov.ae.evil.example/a', allowed));
  assert(!hostAllowed('not a url', allowed));
});

Deno.test('the readable text drops scripts, styles and tags, so a new script nonce is not a change', () => {
  const a = readableText('<html><script>var n="1"</script><style>p{}</style><p>Fire code 2026 edition</p></html>');
  const b = readableText('<html><script>var n="2"</script><p>Fire code   2026 edition</p></html>');
  assertEquals(a, 'Fire code 2026 edition');
  assertEquals(a, b);
});

Deno.test('a page is read and signed; the same text gives the same signature', async () => {
  const body = '<html><body><h1>Civil Defence</h1><p>' + 'The UAE Fire and Life Safety Code of Practice applies. '.repeat(3) + '</p></body></html>';
  const f = (() => Promise.resolve(page(body))) as unknown as typeof fetch;
  const s = { id: 1, authority: 'DCD', topic: 'fire', url: 'https://www.dcd.gov.ae/code' };
  const r1 = await readSource(s, ['www.dcd.gov.ae'], f);
  const r2 = await readSource(s, ['www.dcd.gov.ae'], f);
  assert(r1.ok, JSON.stringify(r1));
  assert(r1.signature?.startsWith('v2:'));
  assertEquals(r1.signature, r2.signature);
  assert(r1.excerpt?.includes('Fire and Life Safety'));
});

Deno.test('a source on a host outside the allowlist is never fetched', async () => {
  let called = 0;
  const f = (() => { called++; return Promise.resolve(page('x')); }) as unknown as typeof fetch;
  const r = await readSource({ id: 2, authority: 'x', topic: 'y', url: 'https://evil.example/' }, ['www.dcd.gov.ae'], f);
  assertEquals(r.ok, false);
  assertEquals(r.error, 'host_not_allowlisted');
  assertEquals(called, 0);
});

Deno.test('a redirect to a host outside the allowlist is refused before it is requested', async () => {
  const asked: string[] = [];
  const f = ((u: string) => {
    asked.push(String(u));
    return Promise.resolve(new Response(null, { status: 302, headers: { location: 'https://tracker.example/landing' } }));
  }) as unknown as typeof fetch;
  const r = await readSource({ id: 3, authority: 'x', topic: 'y', url: 'https://www.dm.gov.ae/rules' }, ['www.dm.gov.ae'], f);
  assertEquals(r.ok, false);
  assertEquals(asked, ['https://www.dm.gov.ae/rules']);
});

Deno.test('a failed fetch and an empty page are recorded as failures, never as checks', async () => {
  const f404 = (() => Promise.resolve(page('gone', 404))) as unknown as typeof fetch;
  const r = await readSource({ id: 4, authority: 'x', topic: 'y', url: 'https://www.rta.ae/p' }, ['www.rta.ae'], f404);
  assertEquals(r.ok, false);
  assert(r.error?.startsWith('http_404'));
  const fEmpty = (() => Promise.resolve(page('<html><script>x</script></html>'))) as unknown as typeof fetch;
  const e = await readSource({ id: 5, authority: 'x', topic: 'y', url: 'https://www.rta.ae/p' }, ['www.rta.ae'], fEmpty);
  assertEquals(e.ok, false);
  assert(e.error?.startsWith('empty_page'));
});

Deno.test('the step records every due source, then settles once', async () => {
  const calls: { fn: string; args?: Record<string, unknown> }[] = [];
  const rpc = (fn: string, args?: Record<string, unknown>) => {
    calls.push({ fn, args });
    if (fn === 'fn_compliance_sources_due') return Promise.resolve({ allowed_hosts: ['www.dcd.gov.ae'], sources: [
      { id: 1, authority: 'DCD', topic: 'fire', url: 'https://www.dcd.gov.ae/a' },
      { id: 2, authority: 'X', topic: 'y', url: 'https://other.example/b' }] });
    if (fn === 'fn_compliance_source_record') return Promise.resolve({ outcome: (args?.p as { ok: boolean }).ok ? 'asked' : 'failed' });
    return Promise.resolve({ ok: true });
  };
  const f = (() => Promise.resolve(page('<p>' + 'Building and fire safety rules for Dubai. '.repeat(3) + '</p>'))) as unknown as typeof fetch;
  const out = await runComplianceWatch(rpc, { fetchImpl: f });
  assertEquals(calls.filter((c) => c.fn === 'fn_compliance_source_record').length, 2);
  assertEquals(calls.at(-1)?.fn, 'fn_compliance_watch_settle');
  assertEquals([out.fetched, out.failed, out.changed_or_new], [1, 1, 1]);
});
