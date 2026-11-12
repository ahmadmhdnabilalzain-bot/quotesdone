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
  abort() { this.aborted = true; this.onabort?.(); }
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

// Review of this change, rounds 1 and 2: a stalled upload said "Uploading… 0%" for good (round 1), and then a size-based ceiling
// cut a 1.43 MB photo at 82% on a 160 kbit/s line, three times (round 2). Now only 20 s with no byte sent ends an upload.
// A stand-in XMLHttpRequest that sends `total` bytes at `bps` bytes a second, one progress event a second, on the test's clock;
// `stopAt` (0..1) is where the line goes quiet for good.
const lineXhr = (total, bps, stopAt = 2) => class {
  constructor() { this.upload = {}; this.status = 0; this.responseText = ''; }
  open() {} setRequestHeader() {}
  abort() { this.dead = true; this.onabort?.(); }
  send() {
    let sent = 0;
    const tickOnce = () => {
      if (this.dead) return;
      if (sent / total >= stopAt) return;   // quiet: no more events
      sent = Math.min(total, sent + bps);
      this.upload.onprogress?.({ lengthComputable: true, loaded: sent, total });
      if (sent >= total) { this.status = 200; this.responseText = '{}'; this.onload(); return; }
      setTimeout(tickOnce, 1000);
    };
    setTimeout(tickOnce, 1000);
  }
};
test('a 1.43 MB photo on a 160 kbit/s line goes all the way (72 s), its percentage moving, never cut', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const f = new Blob([new Uint8Array(10)]);
  const { url, init } = signedUploadRequest('https://x.supabase.co', 'ANON', 'supplier-docs', 'p', 'T', f);
  const seen = [];
  const p = putWithProgress(url, init, (x) => seen.push(x), lineXhr(1_434_978, 20_000));
  for (let i = 0; i < 80; i++) { t.mock.timers.tick(1000); await Promise.resolve(); }
  assert.deepEqual(await p, { ok: true, status: 200, text: '{}' });
  assert.ok(seen.length > 70 && seen.at(-1) === 1, 'the percentage moved the whole way: ' + seen.length + ' reports');
  assert.ok(seen.some((x) => x > 0.82 && x < 0.9), 'past the 82% where the old ceiling cut it');
});
test('an upload whose line goes quiet ends 20 s after its last byte, as status 0 "stalled"', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const f = new Blob([new Uint8Array(10)]);
  const { url, init } = signedUploadRequest('https://x.supabase.co', 'ANON', 'supplier-docs', 'p', 'T', f);
  let done = null;
  putWithProgress(url, init, () => {}, lineXhr(1_000_000, 20_000, 0.5)).then((r) => { done = r; });
  for (let i = 0; i < 25; i++) { t.mock.timers.tick(1000); await Promise.resolve(); }   // 25 s: the last byte went at 25 s
  assert.equal(done, null, 'still going while bytes moved');
  for (let i = 0; i < 19; i++) { t.mock.timers.tick(1000); await Promise.resolve(); }
  assert.equal(done, null, '19 s of quiet is not yet a stall');
  t.mock.timers.tick(1000); await Promise.resolve(); await Promise.resolve();
  assert.deepEqual(done, { ok: false, status: 0, text: 'stalled' });
});

// Review round 3, C: once every byte has left, the answer is waited for up to 60 s, not cut by the 20 s no-bytes clock.
test('after the last byte, storage is given 60 s to answer', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const f = new Blob([new Uint8Array(10)]);
  const { url, init } = signedUploadRequest('https://x.supabase.co', 'ANON', 'supplier-docs', 'p', 'T', f);
  const Quiet = class { constructor() { this.upload = {}; } open() {} setRequestHeader() {} abort() { this.onabort?.(); }
    send() { setTimeout(() => this.upload.onprogress({ lengthComputable: true, loaded: 1000, total: 1000 }), 1000); } };   // all sent, never answered
  let done = null; putWithProgress(url, init, () => {}, Quiet).then((r) => { done = r; });
  for (let i = 0; i < 30; i++) { t.mock.timers.tick(1000); await Promise.resolve(); }
  assert.equal(done, null, '30 s after the last byte it is still waiting for the answer');
  for (let i = 0; i < 31; i++) { t.mock.timers.tick(1000); await Promise.resolve(); }
  await Promise.resolve();
  assert.deepEqual(done, { ok: false, status: 0, text: 'stalled' }, 'ended 60 s after the last byte');
});

// Review round 3, B: "Cancel" ends a moving upload at once, and neither a cancel nor the 15-minute safeguard is tried again.
test('Cancel ends a moving upload as status -1 "cancelled"; the safeguard as "too_slow"; neither is transient', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const { isTransientUploadError } = await import('./signedUpload.ts');
  const f = new Blob([new Uint8Array(10)]);
  const { url, init } = signedUploadRequest('https://x.supabase.co', 'ANON', 'supplier-docs', 'p', 'T', f);
  const ac = new AbortController(); let done = null;
  putWithProgress(url, init, () => {}, lineXhr(1_000_000, 2_000), 20_000, 15 * 60_000, ac.signal).then((r) => { done = r; });
  for (let i = 0; i < 10; i++) { t.mock.timers.tick(1000); await Promise.resolve(); }
  assert.equal(done, null);
  ac.abort(); await Promise.resolve();
  assert.deepEqual(done, { ok: false, status: -1, text: 'cancelled' });
  let slow = null;
  putWithProgress(url, init, () => {}, lineXhr(100_000_000, 2_000), 20_000, 30_000).then((r) => { slow = r; });
  for (let i = 0; i < 31; i++) { t.mock.timers.tick(1000); await Promise.resolve(); }
  assert.deepEqual(slow, { ok: false, status: -1, text: 'too_slow' });
  assert.equal(isTransientUploadError({ code: 'cancelled', status: -1 }), false);
  assert.equal(isTransientUploadError({ code: 'upload_too_slow', status: -1 }), false);
});
