// The SSRF guard must FIRE. Not "exists": fire.
//
// The whole reason this file exists is that the last version of this guard was shipped with a regex
// that could not match an IP address, and nothing executed it for a day. `deno test` grants no
// permissions by default, so every assertion below is over a pure function — no network, no
// filesystem, no deploy. Run it: `deno test supabase/functions/_shared/safe_url.test.ts`, or
// `npm test`, which discovers every *.test.ts in the repository.
import { assertEquals } from 'jsr:@std/assert@1';
import { safeFetch, unsafeUrl } from './safe_url.ts';

Deno.test('refuses loopback, RFC1918, link-local and CGNAT in dotted-quad form', () => {
  for (const u of [
    'http://127.0.0.1/x.pdf',
    'http://127.1.2.3/x.pdf',
    'http://10.0.0.8/x.pdf',
    'http://172.16.5.5/x.pdf',
    'http://172.31.255.254/x.pdf',
    'http://192.168.1.1/x.pdf',
    'http://169.254.169.254/latest/meta-data/iam/security-credentials/',
    'http://100.64.0.1/x.pdf',
  ]) assertEquals(unsafeUrl(u), 'private_address', u);
  // 0.0.0.0 is refused one branch earlier, by name, exactly as the recovered guard did it. The
  // reason code differs; the refusal is the assertion that matters.
  assertEquals(unsafeUrl('http://0.0.0.0/x.pdf'), 'internal_host');
});

Deno.test('refuses the ranges the recovered guard did not cover', () => {
  assertEquals(unsafeUrl('http://224.0.0.1/x'), 'private_address');    // multicast
  assertEquals(unsafeUrl('http://240.0.0.1/x'), 'private_address');    // reserved
  assertEquals(unsafeUrl('http://255.255.255.255/x'), 'private_address');
  assertEquals(unsafeUrl('http://198.18.0.1/x'), 'private_address');   // benchmarking
  assertEquals(unsafeUrl('http://192.0.0.1/x'), 'private_address');    // IETF protocol assignments
});

Deno.test('refuses an address spelled as an integer, octal or hex', () => {
  // The WHATWG URL parser normalises all three to the hostname 127.0.0.1 before the guard runs.
  // This test is what proves that, rather than the comment claiming it.
  assertEquals(new URL('http://2130706433/').hostname, '127.0.0.1');
  assertEquals(unsafeUrl('http://2130706433/x'), 'private_address');
  assertEquals(unsafeUrl('http://0x7f000001/x'), 'private_address');
  assertEquals(unsafeUrl('http://0177.0.0.1/x'), 'private_address');
});

Deno.test('refuses IPv6 loopback, ULA, link-local and IPv4-mapped loopback', () => {
  assertEquals(unsafeUrl('http://[::1]/x'), 'private_address');
  assertEquals(unsafeUrl('http://[::]/x'), 'private_address');
  assertEquals(unsafeUrl('http://[fd00::1]/x'), 'private_address');
  assertEquals(unsafeUrl('http://[fc00::1]/x'), 'private_address');
  assertEquals(unsafeUrl('http://[fe80::1]/x'), 'private_address');
  // v4-mapped: a loopback address written as IPv6. The recovered guard let both of these through.
  assertEquals(unsafeUrl('http://[::ffff:127.0.0.1]/x'), 'private_address');
  assertEquals(unsafeUrl('http://[::ffff:7f00:1]/x'), 'private_address');
  assertEquals(unsafeUrl('http://[::ffff:169.254.169.254]/x'), 'private_address');
});

Deno.test('refuses internal names', () => {
  for (const u of [
    'http://localhost/x', 'http://api.localhost/x', 'http://db.internal/x',
    'http://printer.local/x', 'http://wiki.intranet/x', 'http://nas.lan/x',
    'http://files.corp/x', 'http://vault.private/x', 'http://router.home.arpa/x',
  ]) assertEquals(unsafeUrl(u), 'internal_host', u);
});

Deno.test('refuses every scheme that is not http or https', () => {
  for (const u of [
    'file:///etc/passwd',
    'file://C:/Windows/win.ini',
    'gopher://127.0.0.1:11211/_stats',
    'ftp://ftp.example.com/x.pdf',
    'data:text/html;base64,PHNjcmlwdD4=',
    'blob:https://example.com/abc',
    'jar:http://example.com/a.zip!/b',
  ]) assertEquals(unsafeUrl(u), 'scheme_not_http', u);
});

Deno.test('refuses unparseable input rather than letting it through', () => {
  for (const u of ['', 'not a url', '///', 'http://']) {
    const r = unsafeUrl(u);
    assertEquals(r === null, false, `${JSON.stringify(u)} was allowed`);
  }
});

Deno.test('allows a real public document URL — a guard that refuses everything is not a guard', () => {
  assertEquals(unsafeUrl('https://www.dm.gov.ae/code.pdf'), null);
  assertEquals(unsafeUrl('https://8.8.8.8/x.pdf'), null);
  assertEquals(unsafeUrl('https://resend-attachments.s3.amazonaws.com/abc/def.pdf'), null);
  assertEquals(unsafeUrl('http://93.184.216.34/x.pdf'), null);
  assertEquals(unsafeUrl('https://[2606:4700::1]/x'), null);
});

// CWE-918 audit, 19 Oct 2026: a redirect to an internal address must be refused BEFORE it is requested.
// The fake fetch records every url it is asked for; the metadata address must never appear in that list.
Deno.test('a redirect to the metadata address is refused before the internal hop is requested', async () => {
  const asked: string[] = [];
  const fake = ((u: string) => {
    asked.push(String(u));
    if (String(u).startsWith('https://zz-demo.example.invalid/')) return Promise.resolve(new Response(null, { status: 302, headers: { location: 'http://169.254.169.254/latest/meta-data/' } }));
    return Promise.resolve(new Response('internal', { status: 200 }));
  }) as typeof fetch;
  const r = await safeFetch('https://zz-demo.example.invalid/doc.pdf', { fetchImpl: fake });
  assertEquals([r.ok, (r as { error?: string }).error], [false, 'url_refused_after_redirect']);
  assertEquals(asked, ['https://zz-demo.example.invalid/doc.pdf']);
});

Deno.test('a public-to-public redirect is still followed', async () => {
  const fake = ((u: string) => Promise.resolve(String(u).endsWith('/a')
    ? new Response(null, { status: 301, headers: { location: '/b' } })
    : new Response('ok', { status: 200 }))) as typeof fetch;
  const r = await safeFetch('https://zz-demo.example.invalid/a', { fetchImpl: fake });
  assertEquals([r.ok, r.ok && r.finalUrl], [true, 'https://zz-demo.example.invalid/b']);
});
