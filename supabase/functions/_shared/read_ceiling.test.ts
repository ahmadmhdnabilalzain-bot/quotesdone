// A licence or certificate too large to read is refused before it is decoded or parsed (3 Nov 2026, sales_engineer). Replays the
// 28 Oct document walk: a 24 MB licence ended supplier_portal at the edge's CPU cap (HTTP 546) and process_docs still did at 19.3 MB.
// deno test -A --no-lock --node-modules-dir=auto supabase/functions/_shared/read_ceiling.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { b64Size, READ_MAX_BYTES, toB64, tooLargeToRead } from './document_expiry.ts';
// customer_api and supplier_api are index.ts plus modules since 9 Nov 2026: read the whole function, as the node checks do.
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

Deno.test('the size of a base64 upload is known without decoding it', () => {
  for (const n of [0, 1, 2, 3, 1000, 1001, 1002]) assertEquals(b64Size(toB64(new Uint8Array(n))), n);
  assertEquals(b64Size('data:application/pdf;base64,' + toB64(new Uint8Array(10))), 10);
  assertEquals(READ_MAX_BYTES, 10 * 1024 * 1024);   // what 9.66 MB passing and 14.5 MB failing on production measured (28 Oct, 1 Nov)
});

Deno.test('the refusal is plain English with our own code (suppliers read English, never platform text)', () => {
  const r = tooLargeToRead(24 * 1048576, 'trade licence');
  assertEquals(r.code, 'file_too_large_read');
  assert(/24\.0 MB/.test(r.message) && /10 MB/.test(r.message) && !/[؀-ۿ]/.test(r.message), r.message);
});

// Code shape, comments removed (apply-discipline section 7): the ceiling stands before the decode and before the readers.
const before = (src: string, a: string, b: string) => { const i = src.indexOf(a), j = src.indexOf(b); return i >= 0 && j >= 0 && i < j; };
Deno.test('supplier_api process_docs and supplier_portal save_documents refuse above the ceiling before any read', () => {
  const api = functionSource('supplier_api').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`\\])\/\/.*$/gm, '$1'), portal = functionSource('supplier_portal').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`\\])\/\/.*$/gm, '$1');
  assert(before(api, 'b64Size(lic.original_b64) > READ_MAX_BYTES', 'sanitizeAndScan({ input: String(lic.original_b64)'), 'process_docs decodes a licence before its size is checked');
  assert(before(api, 'licBytes.bytes.length > READ_MAX_BYTES', 'readLicenceName(licBytes.bytes'), 'process_docs reads a stored licence before its size is checked');
  assert(before(portal, 'b64Size(it.original_b64) > READ_MAX_BYTES', 'sanitizeAndScan({ input: String(it.original_b64), declaredMime: it.mime, filename: it.filename || kindStr'), 'save_documents decodes a document before its size is checked');
});
