// compliance_archive's HANDLER, end to end in memory (review 2 of 13 Nov 2026, item 1). The certificate's compare-and-set write
// is retried on a blip. When the blip arrives AFTER the write committed (a dropped connection: `fetch failed`), the retry
// matches no row because this call's own write already filled signed_terms_path. The handler used to take that for a lost race
// and delete the file while the row named it. Now it reads the row again: naming this render, the write won and the file stays.
// The genuine lost race still removes its own render, and a row that cannot be read back keeps the file.
//
// Incapable of reaching anything: Deno.serve, fetch, the environment and EdgeRuntime are stubbed before index.ts is imported;
// every request is answered here from a table, and the party is a ZZ DEMO supplier on @example.invalid.
import { assert, assertEquals } from 'jsr:@std/assert@1';

type Call = { method: string; url: string; body: string };
const calls: Call[] = [];
const LEAD_ID = 990000001;
const RENDER = 'suppliers/ZZ_DEMO_TnC-Acceptance-new.pdf';
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { 'content-type': 'application/json' } });

// mode: 'lost_answer' = the first PATCH commits and its answer is lost; 'lost_race' = another caller named its own render first;
// 'unreadable' = like lost_answer, but the read-back fails too.
let mode: 'lost_answer' | 'lost_race' | 'unreadable' = 'lost_answer';
let rowPath: string | null = null;

function answer(method: string, url: URL, accept: string): Response | Promise<Response> {
  const p = url.pathname; const one = /vnd\.pgrst\.object/.test(accept);
  const rows = (r: unknown[]) => (one ? (r.length ? json(r[0]) : json(null)) : json(r));
  if (p === '/rest/v1/rpc/fn_internal_auth') return json({ ok: true, context: 'zz-test', credential_id: 1, legacy: false });
  if (p === '/functions/v1/pdf_native') return json({ ok: true, path: RENDER, url: 'https://example.invalid/render.pdf' });
  if (p.startsWith('/storage/v1/object/sign/')) return json({ signedURL: '/object/sign/signed-terms/x?token=zz' });
  if (p === '/rest/v1/leads' && method === 'PATCH') {
    const patchNo = calls.filter((c) => c.method === 'PATCH' && c.url.startsWith('/rest/v1/leads')).length;
    if (mode === 'lost_race') { rowPath = 'suppliers/the-winner.pdf'; return json([]); }
    if (patchNo === 1 && rowPath === null) { rowPath = RENDER; return Promise.reject(new TypeError('fetch failed')); } // committed, answer lost
    return json(rowPath === null ? [{ id: LEAD_ID }] : []); // the retry's compare-and-set: signed_terms_path is no longer null
  }
  if (p === '/rest/v1/leads' && method === 'GET') {
    const sel = url.searchParams.get('select') ?? '';
    if (sel === 'signed_terms_path') {
      if (mode === 'unreadable') return json({ code: '57014', message: 'canceling statement due to statement timeout' }, 500);
      return rows([{ signed_terms_path: rowPath }]);
    }
    return rows([{ id: LEAD_ID, claimed_by: 'zz-demo-cert@example.invalid', company_name: 'ZZ DEMO Trading', contact_name: 'ZZ DEMO',
      accepted_terms_at: '2026-11-15T08:00:00Z', accepted_terms_version: 'v5', signed_terms_path: null, signed_terms_at: null }]);
  }
  if (method === 'GET') return rows([]);
  return json([], 201);
}

const box: { handler?: (req: Request) => Promise<Response> } = {};
async function setUp() {
  if (box.handler) return box.handler;
  const env: Record<string, string> = { SUPABASE_URL: 'http://127.0.0.1:9', SUPABASE_SERVICE_ROLE_KEY: 'not-a-key' };
  (Deno.env as { get: (k: string) => string | undefined }).get = (k: string) => env[k];
  (Deno as unknown as { serve: unknown }).serve = (h: (req: Request) => Promise<Response>) => { box.handler = h; return { finished: Promise.resolve(), shutdown: () => Promise.resolve() }; };
  (globalThis as { EdgeRuntime?: unknown }).EdgeRuntime = { waitUntil: (_p: Promise<unknown>) => {} };
  globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
    const req = input instanceof Request ? input : new Request(String(input), init);
    const url = new URL(req.url);
    if (url.hostname !== '127.0.0.1') throw new Error('the test reached ' + url.host);
    calls.push({ method: req.method, url: url.pathname + url.search, body: req.method === 'GET' ? '' : await req.clone().text() });
    return answer(req.method, url, req.headers.get('accept') ?? '');
  }) as typeof fetch;
  await import('./index.ts');
  assert(box.handler, 'compliance_archive registered its handler');
  return box.handler;
}

async function sign(): Promise<{ status: number; body: Record<string, unknown> }> {
  calls.length = 0; rowPath = null;
  const handler = await setUp();
  const quiet = console.error; console.error = () => {};
  try {
    const res = await handler(new Request('http://127.0.0.1:9/functions/v1/compliance_archive', { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ action: 'sign', kind: 'supplier', id: LEAD_ID, __secret: 'zz-internal-credential-for-a-test-only' }) }));
    return { status: res.status, body: await res.json() };
  } finally { console.error = quiet; }
}
const removes = () => calls.filter((c) => c.method === 'DELETE' && c.url.startsWith('/storage/v1/object/signed-terms'));
const leadWrites = () => calls.filter((c) => c.method === 'PATCH' && c.url.startsWith('/rest/v1/leads'));

Deno.test('compliance_archive sign: a write that lands and then loses its answer keeps the certificate the row names', async () => {
  mode = 'lost_answer';
  const { status, body } = await sign();
  assertEquals(leadWrites().length, 2, 'the blip was retried once');
  assertEquals(rowPath, RENDER, 'the row names this render');
  assertEquals(removes().length, 0, 'the certificate the row names is not deleted');
  assertEquals(status, 200);
  assertEquals(body.ok, true);
  assert(body.reused !== true, 'answered as the write that won, not as a lost race');
  assertEquals(calls.filter((c) => c.url.startsWith('/rest/v1/rpc/fn_it_engineer_finding_upsert')).length, 0, 'no finding: the write was recorded');
});

Deno.test('compliance_archive sign: the genuine lost race still removes its own render and returns the winner', async () => {
  mode = 'lost_race';
  const { status, body } = await sign();
  assertEquals(rowPath, 'suppliers/the-winner.pdf');
  const rm = removes();
  assertEquals(rm.length, 1, 'its own render is removed');
  assert(rm[0].body.includes(RENDER) && !rm[0].body.includes('the-winner'), 'only its own render, never the winner');
  assertEquals(status, 200);
  assertEquals(body.reused, true);
});

Deno.test('compliance_archive sign: a write whose answer was lost and a row that cannot be read back keep the file', async () => {
  mode = 'unreadable';
  const { status, body } = await sign();
  assertEquals(removes().length, 0, 'nothing is deleted when it cannot be told whose file the row names');
  const kept = calls.find((c) => c.method === 'POST' && c.url.startsWith('/rest/v1/agent_runs') && c.body.includes('orphan_kept'));
  assert(kept, 'the kept file is written down for a person to clean up');
  assertEquals(status, 200);
  assertEquals(body.ok, true);
});
