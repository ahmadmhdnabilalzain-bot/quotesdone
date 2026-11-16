// workbook_remote — supplier_api's engine: the bytes go to doc_extract, the answer comes back as the same read.
// fetch is STUBBED in every test (no network); the stub answers through doc_extract's own op handler, so the remote
// read is compared with the local read of the same ZZ DEMO bytes.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/doc_read/workbook_remote.test.ts
import { assert, assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { remoteWorkbookEngine } from './workbook_remote.ts';
import { registerWorkbookEngine, REMOTE_READ_MAX_BYTES } from './workbook_engine.ts';
import { localWorkbookEngine } from './workbook_local.ts';
import { workbookOp } from '../../doc_extract/workbook_op.ts';
import { readWorkbook } from './office.ts';
import { readDoc, readMsg } from './ole.ts';
import { odsFixture, xlsxFixture } from './office.fixtures.ts';
import { docFixture, msgFixture } from './ole.fixtures.ts';
import { empty, ok } from './types.ts';

const URL_ = 'http://127.0.0.1:1';
const ctx = { filename: 'f', depth: 0, readChild: () => Promise.resolve(ok(empty('csv'))) };
type Call = { url: string; init: RequestInit; body: Record<string, unknown> };

/** Replace fetch for the length of `f`; `answer` decides each response. */
async function withFetch<T>(answer: (c: Call) => Promise<Response>, f: (calls: Call[]) => Promise<T>): Promise<T> {
  const real = globalThis.fetch;
  const calls: Call[] = [];
  globalThis.fetch = ((input: string | URL | Request, init: RequestInit = {}) => {
    const c = { url: String(input), init, body: JSON.parse(String(init.body)) };
    calls.push(c);
    return answer(c);
  }) as typeof fetch;
  try { return await f(calls); } finally { globalThis.fetch = real; }
}
const throughDocExtract = async (c: Call) => {
  const a = await workbookOp(c.body);
  return a ? new Response(JSON.stringify(a.body), { status: a.status }) : new Response('{}', { status: 400 });
};
const engine = (credential: string | null = 'zz-demo-cred') => remoteWorkbookEngine({ url: URL_, credential: () => Promise.resolve(credential) });

Deno.test('a workbook read through doc_extract is the same read as the local one, posted with the caller\'s credential and a deadline', async () => {
  for (const fixture of [await xlsxFixture(), await odsFixture()]) {
    registerWorkbookEngine(localWorkbookEngine);
    const local = await readWorkbook(fixture, ctx);
    registerWorkbookEngine(engine());
    const remote = await withFetch(throughDocExtract, async (calls) => {
      const r = await readWorkbook(fixture, ctx);
      assertEquals(calls.length, 1);
      assertEquals(calls[0].url, `${URL_}/functions/v1/doc_extract`);
      assertEquals(calls[0].init.method, 'POST');
      assertEquals(calls[0].body.op, 'read_workbook');
      assertEquals(calls[0].body.__secret, 'zz-demo-cred');
      assert(calls[0].init.signal instanceof AbortSignal, 'the call carries a deadline');
      return r;
    });
    assert(local.ok);
    assertEquals(remote, local);
  }
});

Deno.test('a .doc and a .msg read through doc_extract are the same reads as the local ones', async () => {
  for (const [read, bytes] of [[readDoc, docFixture()], [readMsg, msgFixture()]] as const) {
    registerWorkbookEngine(localWorkbookEngine);
    const local = await read(bytes, ctx);
    registerWorkbookEngine(engine());
    const remote = await withFetch(throughDocExtract, async (calls) => {
      const r = await read(bytes, ctx);
      assertEquals(calls.map((c) => c.body.op), ['read_compound_file']);
      return r;
    });
    assert(local.ok, JSON.stringify(local));
    assertEquals(remote, local);
  }
});

Deno.test('doc_extract refusing the credential is a refusal of the workbook, not a throw', async () => {
  registerWorkbookEngine(engine());
  const r = await withFetch(() => Promise.resolve(new Response('{"error":"forbidden"}', { status: 403 })), () => xlsxFixture().then((b) => readWorkbook(b, ctx)));
  assertEquals(r, { ok: false, error: 'unreadable', detail: 'the workbook could not be read: the workbook reader answered 403' });
});

Deno.test('a timed-out or failed call is a refusal, not a throw', async () => {
  registerWorkbookEngine(engine());
  const r = await withFetch(() => Promise.reject(new DOMException('Signal timed out.', 'TimeoutError')), () => xlsxFixture().then((b) => readWorkbook(b, ctx)));
  assertEquals(r, { ok: false, error: 'unreadable', detail: 'the workbook could not be read: the workbook reader did not answer: Signal timed out.' });
  const d = await withFetch(() => Promise.reject(new TypeError('connection refused')), () => readDoc(docFixture(), ctx));
  assertEquals(d, { ok: false, error: 'unreadable', detail: 'the compound file could not be read: the workbook reader did not answer: connection refused' });
});

Deno.test('the reader\'s own message comes back: a password-protected workbook is still refused as encrypted', async () => {
  registerWorkbookEngine(engine());
  const r = await withFetch(() => Promise.resolve(new Response(JSON.stringify({ ok: false, error: 'unreadable', message: 'File is password-protected' }), { status: 422 })), () => xlsxFixture().then((b) => readWorkbook(b, ctx)));
  assert(!r.ok);
  assertEquals(r.error, 'encrypted');
});

Deno.test('an answer that is not a workbook is refused', async () => {
  registerWorkbookEngine(engine());
  const r = await withFetch(() => Promise.resolve(new Response(JSON.stringify({ ok: true, names: 'ZZ DEMO' }), { status: 200 })), () => xlsxFixture().then((b) => readWorkbook(b, ctx)));
  assertEquals(r, { ok: false, error: 'unreadable', detail: 'the workbook could not be read: the workbook reader answered something that is not a workbook' });
});

Deno.test('no credential, or more bytes than the reader takes: nothing is sent', async () => {
  await withFetch(throughDocExtract, async (calls) => {
    await assertRejects(() => engine(null).sheets(new Uint8Array([1])), Error, 'no credential to reach the workbook reader');
    await assertRejects(() => engine().compoundFile(new Uint8Array(REMOTE_READ_MAX_BYTES + 1)), Error, `over the ${REMOTE_READ_MAX_BYTES} bytes the workbook reader takes`);
    assertEquals(calls.length, 0);
  });
  registerWorkbookEngine(null);
});

Deno.test('one retry on a 5xx or a dropped connection, none on a timeout or a 4xx; every call names document_id -1', async () => {
  registerWorkbookEngine(engine());
  let n = 0;
  const flaky = (c: Call) => (++n === 1 ? Promise.resolve(new Response('{}', { status: 503 })) : throughDocExtract(c));
  const local = await (async () => { const { readWorkbook: rw } = await import('./office.ts'); return rw; })();
  await withFetch(flaky, async (calls) => {
    const r = await xlsxFixture().then((b) => local(b, ctx));
    assertEquals(r.ok, true);
    assertEquals(calls.length, 2);
    assertEquals(calls.every((c) => c.body.document_id === -1), true);
  });
  await withFetch(() => Promise.reject(new DOMException('Signal timed out.', 'TimeoutError')), async (calls) => {
    await xlsxFixture().then((b) => readWorkbook(b, ctx));
    assertEquals(calls.length, 1);
  });
  await withFetch(() => Promise.reject(new TypeError('connection refused')), async (calls) => {
    await xlsxFixture().then((b) => readWorkbook(b, ctx));
    assertEquals(calls.length, 2);
  });
  await withFetch(() => Promise.resolve(new Response('{"error":"forbidden"}', { status: 403 })), async (calls) => {
    await xlsxFixture().then((b) => readWorkbook(b, ctx));
    assertEquals(calls.length, 1);
  });
});
