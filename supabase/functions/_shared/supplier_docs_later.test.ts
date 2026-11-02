// supplier_docs_later — a profile or catalogue uploaded straight to storage is gated on its stored bytes before it is
// read, a refused one is removed and never read, and a read stuck 'reading' is re-read once.
// deno test -A --no-lock --node-modules-dir=auto supabase/functions/_shared/supplier_docs_later.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { sanitizeUpload } from './attachment.ts';
import { readDocForTrades, type TradeResolveDeps } from './supplier_doc_trades.ts';
import { pdfjsText } from './doc_read/pdf.ts';
import { LIMITS } from './doc_read/types.ts';

// malware.ts builds its client at import; the scan itself is replaced below by the real type gate alone.
Deno.env.set('SUPABASE_URL', Deno.env.get('SUPABASE_URL') ?? 'http://127.0.0.1:1');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? 'test');
const { gateStored, ownPath, stuckOf } = await import('./supplier_docs_later.ts');

// deno-lint-ignore no-explicit-any
const typeGateOnly = async (o: any) => { const s = sanitizeUpload(o); return s.ok ? { ok: true, result: s, scan: {} } : { ok: false, status: 415, body: { error: s.error, detail: s.detail } }; };
const fakeAdmin = (row: Record<string, unknown>) => {
  const log: string[] = [];
  const admin = {
    storage: { from: () => ({ remove: async (p: string[]) => { log.push('remove ' + p.join(',')); return {}; } }) },
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: row }) }) }),
      update: (u: Record<string, unknown>) => ({ eq: async () => { log.push('update ' + JSON.stringify(u)); return {}; } }),
    }),
  };
  return { admin, log };
};

Deno.test('a stored file that fails the type gate is refused, removed from storage and the row, and never read', async () => {
  const path = 'catalogs/7/1_cat.pdf';
  const { admin, log } = fakeAdmin({ company_profile_doc_path: null, catalog_doc_paths: ['catalogs/7/0_old.pdf', path] });
  const html = new TextEncoder().encode('<html><script>alert(1)</script></html>');
  // deno-lint-ignore no-explicit-any
  const d = await gateStored(admin, 7, { path, name: 'cat.pdf', kind: 'catalogue', gate: true }, { fetch: async () => ({ bytes: html }), scan: typeGateOnly as any });
  assert(d.refused, 'refused');
  assertEquals(d.bytes, undefined);
  assertEquals(log, ['remove ' + path, 'update {"catalog_doc_paths":["catalogs/7/0_old.pdf"]}']);
  const never = async () => { throw new Error('a refused file was read'); };
  const ev = await readDocForTrades(d, { chooseTrades: never, normTrades: never } as unknown as TradeResolveDeps);
  assertEquals(ev.status, 'refused');
  assertEquals(ev.trades, []);
});

Deno.test('a stored PDF that passes the gate is read from the gated bytes, with its sniffed type', async () => {
  const { admin, log } = fakeAdmin({});
  const pdf = new TextEncoder().encode('%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n');
  // deno-lint-ignore no-explicit-any
  const d = await gateStored(admin, 7, { path: 'profiles/7/1_p.pdf', name: 'p.pdf', kind: 'profile', gate: true }, { fetch: async () => ({ bytes: pdf }), scan: typeGateOnly as any });
  assertEquals(d.refused, undefined);
  assertEquals(d.mime, 'application/pdf');
  assertEquals(d.bytes?.length, pdf.length);
  assertEquals(log, []);
});

Deno.test('a file over 100 MB is refused without being scanned', async () => {
  const { admin } = fakeAdmin({});
  const d = await gateStored(admin, 7, { path: 'profiles/7/big.pdf', name: 'big.pdf', kind: 'profile', gate: true },
    { fetch: async () => ({ error: 'file_too_large' as const }), scan: (() => { throw new Error('scanned'); }) as never });
  assert(d.refused?.startsWith('file_too_large'));
});

Deno.test('only the supplier\'s own folder of that kind is its own', () => {
  assert(ownPath('profiles/7/1_p.pdf', 'profile', 7));
  assert(!ownPath('profiles/8/1_p.pdf', 'profile', 7));
  assert(!ownPath('catalogs/7/1_p.pdf', 'profile', 7));
  assert(!ownPath('profiles/7/../8/x.pdf', 'profile', 7));
});

Deno.test('a read stuck 10 minutes is re-read once; a re-read one and a fresh one are not', () => {
  const now = Date.parse('2026-10-19T10:00:00Z');
  const ev = (path: string, minutesAgo: number, extra: Record<string, unknown> = {}) =>
    ({ path, name: path, kind: 'catalogue', status: 'reading', trades: [], read_at: new Date(now - minutesAgo * 60_000).toISOString(), ...extra });
  const out = stuckOf([{ supplier_id: 7, source_docs: { docs: [ev('a', 12), ev('b', 12, { retry: true }), ev('c', 3), { ...ev('d', 40), status: 'read' }] } }], now);
  assertEquals(out.map((s) => s.docs.map((d) => [d.path, d.gate])), [[['a', true]]]);
});

Deno.test('the 25 MB read limit holds unless the caller asks for the 100 MB supplier-paper limit', async () => {
  const big = new Uint8Array(LIMITS.maxBytes + 1);
  const capped = await pdfjsText(big.slice());
  assert(capped.status === 'failed' && /read limit/.test(capped.detail || ''));
  const paper = await pdfjsText(big, undefined, undefined, undefined, LIMITS.maxPaperBytes);
  assert(paper.status === 'failed' && !/read limit/.test(paper.detail || ''), 'read past the 25 MB cap (and failed only as not-a-PDF)');
});

// 2 Nov 2026, ledger 1442 (profile-read walk on the live site): a scanned PDF stayed needs_ocr because only pictures went to the model.
Deno.test('a picture and a PDF with no text layer go to the model with two attempts; a text PDF and a failed answer leave the document as it was', async () => {
  const { readProfileByModel } = await import('./supplier_docs_later.ts');
  const pdf = (content: string) => {
    const o = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 >>', '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
      `<< /Length ${content.length} >>\nstream\n${content}\nendstream`, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'];
    let s = '%PDF-1.4\n'; const off: number[] = []; o.forEach((b, i) => { off.push(s.length); s += `${i + 1} 0 obj\n${b}\nendobj\n`; });
    const x = s.length; s += `xref\n0 ${o.length + 1}\n0000000000 65535 f \n` + off.map((n) => String(n).padStart(10, '0') + ' 00000 n \n').join('') + `trailer\n<< /Size ${o.length + 1} /Root 1 0 R >>\nstartxref\n${x}\n%%EOF\n`;
    return new TextEncoder().encode(s);
  };
  const answer = { ok: true, profile: { lines: ['Our services', '- Elevator installation'] } };
  const calls: Record<string, unknown>[] = [];
  const ask = (replies: unknown[]) => async (b: Record<string, unknown>) => { calls.push(b); return (replies.shift() ?? null) as never; };
  // a picture: the page goes as an image; the first attempt fails, the second answers
  const png = { path: 'p', name: 'p.png', kind: 'profile' as const, mime: 'image/png', bytes: new Uint8Array([1, 2, 3]), photo_text: undefined as string | undefined };
  assertEquals(await readProfileByModel(png, ask([null, answer])), { asked: true, ok: true });
  assertEquals([calls.length, Object.keys(calls[0])], [2, ['images']]);
  assertEquals(png.photo_text?.includes('Elevator installation'), true);
  // a scanned PDF (no text layer): the file itself goes
  calls.length = 0;
  const scan = { path: 's', name: 's.pdf', kind: 'profile' as const, mime: 'application/pdf', bytes: pdf(''), photo_text: undefined as string | undefined };
  assertEquals(await readProfileByModel(scan, ask([answer])), { asked: true, ok: true });
  assertEquals(Object.keys(calls[0]).sort(), ['file_b64', 'filename', 'mime']);
  assert(!!scan.photo_text);
  // known-bad controls: a PDF that HAS a text layer is not sent (code reads its text); both attempts failing leaves it as it was
  calls.length = 0;
  const text = { path: 't', name: 't.pdf', kind: 'profile' as const, mime: 'application/pdf', bytes: pdf('BT /F1 12 Tf 20 100 Td (Our services - Elevator installation - Flooring works - HVAC works) Tj ET'), photo_text: undefined as string | undefined };
  assertEquals(await readProfileByModel(text, ask([answer])), { asked: false, ok: false });
  assertEquals([calls.length, text.photo_text], [0, undefined]);
  const failing = { path: 'f', name: 'f.png', kind: 'profile' as const, mime: 'image/png', bytes: new Uint8Array([1]), photo_text: undefined as string | undefined };
  assertEquals(await readProfileByModel(failing, ask([null, { ok: false }])), { asked: true, ok: false });
  assertEquals(failing.photo_text, undefined);
  assertEquals((await readProfileByModel({ path: 'x', name: 'x.docx', kind: 'profile' as const, mime: 'application/msword', bytes: new Uint8Array([1]) }, ask([answer]))).asked, false);
});
