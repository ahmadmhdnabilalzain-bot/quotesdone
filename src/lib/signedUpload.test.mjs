// node --test src/lib/signedUpload.test.mjs
// Browser perfection walk, 12 Nov 2026 (customer_support), H2: Submit uploaded files of up to 100 MB with nothing on the screen
// but "Submitting…". An upload that is asked for its progress reports it as the bytes go, and still never throws.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { putWithProgress, signedUploadRequest } from './signedUpload.ts';

// A stand-in XMLHttpRequest that sends in four steps, then answers `status` (or fails the way a dropped line does).
const fakeXhr = (status, fail = null) => class {
  constructor() { this.upload = {}; this.headers = {}; this.status = 0; this.responseText = ''; }
  open(m, u) { this.method = m; this.url = u; }
  setRequestHeader(k, v) { this.headers[k] = v; }
  send(body) {
    const total = body?.size ?? 100;
    queueMicrotask(() => {
      for (const n of [1, 2, 3, 4]) this.upload.onprogress?.({ lengthComputable: true, loaded: (total * n) / 4, total });
      if (fail) return this[fail]();
      this.status = status; this.responseText = status === 200 ? '{}' : 'refused'; this.onload();
    });
  }
};

test('an upload asked for its progress reports it as it goes and ends at 1', async () => {
  const f = new Blob([new Uint8Array(4000)], { type: 'image/jpeg' });
  const { url, init } = signedUploadRequest('https://x.supabase.co', 'ANON', 'supplier-docs', 'licenses/1/1_a.jpg', 'TOK', f, 'image/jpeg');
  const seen = [];
  const r = await putWithProgress(url, init, (p) => seen.push(p), fakeXhr(200));
  assert.deepEqual(r, { ok: true, status: 200, text: '{}' });
  assert.deepEqual(seen, [0.25, 0.5, 0.75, 1, 1]);
});

test('a refusal is its status, and a dropped line or a timeout is status 0, never a throw', async () => {
  const f = new Blob([new Uint8Array(10)]);
  const { url, init } = signedUploadRequest('https://x.supabase.co', 'ANON', 'supplier-docs', 'p', 'T', f);
  assert.equal((await putWithProgress(url, init, () => {}, fakeXhr(400))).status, 400);
  assert.deepEqual(await putWithProgress(url, init, () => {}, fakeXhr(0, 'onerror')), { ok: false, status: 0, text: 'network' });
  assert.deepEqual(await putWithProgress(url, init, () => {}, fakeXhr(0, 'ontimeout')), { ok: false, status: 0, text: 'timeout' });
});
