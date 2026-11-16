// oneFileConverterAndOneEdgeCall.test.mjs — two portal helpers that had drifted apart are one each (16 Nov 2026,
// it_engineer; simplification wave B, SITE-09).
// node --test src/components/portal/oneFileConverterAndOneEdgeCall.test.mjs
//
// MEASURED (READ, 16 Nov 2026):
//   1. fileToImages existed twice. The customer's (me/newRequest/helpers.ts) turns a HEIC, HEIF or TIFF photo into JPEG
//      pages through ocrClient.toJpegPages; the supplier's (portal/supplier/core/upload.ts) sent any image/* up raw, so a
//      supplier's HEIC or multi-page TIFF quotation reached extract_quote as bytes the model reader cannot open.
//   2. orders/api.ts and predict/api.ts were the same file except predict's AbortSignal.timeout(20_000), whose comment
//      says a request that never answered "used to leave the surface on its loader forever"; orders still could.
// Fails if either copy comes back, or if the one converter stops sending a HEIC/TIFF through toJpegPages.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (p) => fs.readFileSync(new URL(p, import.meta.url), 'utf8');
const code = (p) => read(p).split(/\r?\n/).filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n');

test('one fileToImages: both portals take it from me/fileImages.ts, and neither defines its own', () => {
  const supplier = code('./supplier/core/upload.ts');
  const customer = code('../me/newRequest/helpers.ts');
  assert.doesNotMatch(supplier, /function fileToImages\b/, 'the supplier upload defines its own fileToImages again');
  assert.doesNotMatch(customer, /function fileToImages\b/, 'the customer helpers define their own fileToImages again');
  assert.match(supplier, /from '@\/components\/me\/fileImages'/);
  assert.match(customer, /from '\.\.\/fileImages'/);
  assert.match(code('../me/fileImages.ts'), /export async function fileToImages\(/);
});

test('a HEIC or TIFF from either portal goes through toJpegPages, never up raw', async () => {
  // FileReader for fileToB64, and no createImageBitmap: toJpegPages then refuses a HEIC with HEIC_UNSUPPORTED, which
  // is exactly the proof that the HEIC reached the converter (the old supplier copy returned its bytes instead).
  globalThis.FileReader = class { readAsDataURL() { this.result = 'data:image/heic;base64,AAAA'; this.onloadend?.(); this.onload?.(); } };
  const { fileToImages } = await import('../me/fileImages.ts');
  const heic = { name: 'IMG_0001.HEIC', type: 'image/heic', size: 4, arrayBuffer: async () => new ArrayBuffer(4) };
  await assert.rejects(fileToImages(heic), /HEIC_UNSUPPORTED/);
  const noType = { name: 'quote.heif', type: '', size: 4, arrayBuffer: async () => new ArrayBuffer(4) };
  await assert.rejects(fileToImages(noType), /HEIC_UNSUPPORTED/, 'a HEIF the browser gave no type is still recognised by its name');
  const other = await fileToImages({ name: 'notes.bin', type: 'application/octet-stream', size: 4 });
  assert.deepEqual(other.images, [], 'a file that is neither an image nor a PDF is sent as it is, with no pages');
});

test('one edge call for the customer portal surfaces: orders waits 20 s like predict, from one shared helper', () => {
  const shared = code('./customerCall.ts');
  assert.match(shared, /signal: AbortSignal\.timeout\(20_000\)/);
  for (const p of ['./orders/api.ts', './predict/api.ts']) {
    const s = code(p);
    assert.doesNotMatch(s, /fetch\(/, `${p} makes its own request again`);
    assert.match(s, /export \{ call, type ApiResult \} from '\.\.\/customerCall'/, `${p} does not take call from customerCall`);
  }
});
