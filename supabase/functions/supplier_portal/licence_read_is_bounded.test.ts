// THE DOCUMENTS TAB NEVER HOLDS A STORED LICENCE BEHIND A MODEL THAT DOES NOT ANSWER (11 Nov 2026, customer_support; the
// registration certification's J5 finding, checked on the other licence door). save_documents asked license_extract with no
// timeout, before the one write that attaches the stored file to the supplier's row; a model that hung held the answer to the
// edge's wall clock, the portal gave up at 90 s, and the file never reached the row.
//
// Drives supplier_portal's OWN save_documents over a stubbed fetch, with the document model switched on and license_extract
// NEVER answering until the test releases it. Before the fix this did not answer within 30 s. No value is real: ZZ DEMO,
// example.invalid, a 1x1 PNG. Prevented by this file; the budget is _shared/licence_read_state.ts MODEL_ANSWER_BUDGET_MS.
import { assert, assertEquals } from 'jsr:@std/assert@1';

Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');

const SUP = { id: 990002, company_name: 'ZZ DEMO Documents Tab Trading LLC', claimed_by: 'zz-demo-docs@example.invalid' };
const SECRETS: Record<string, string> = { cred_fn_supplier_portal: 'zz-demo-cred', document_expiry_ai: 'on' };
const PNG_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

const calls: { method: string; path: string; body: string }[] = [];
let release!: () => void;
const released = new Promise<void>((ok) => { release = ok; });

globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init);
  const u = new URL(req.url);
  const body = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
  calls.push({ method: req.method, path: u.pathname, body });
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);
  if (u.pathname === '/functions/v1/license_extract') {
    // a model that does not answer: only the caller's own abort, or the test's release, ends the wait
    await Promise.race([released, new Promise((_, no) => req.signal.addEventListener('abort', () => no(new DOMException('aborted', 'AbortError'))))]);
    return json({ error: 'ai_error' }, 502);
  }
  if (u.pathname.startsWith('/functions/v1/')) return json({ ok: true });
  if (u.pathname.startsWith('/storage/v1/object/list/')) return json([]);
  if (u.pathname.startsWith('/storage/v1/object/sign/')) return json({ signedURL: '/object/sign/zz?token=zz' });
  if (u.pathname.startsWith('/storage/v1/object/')) return json({ Key: u.pathname, Id: 'zz' });
  if (u.pathname.startsWith('/rest/v1/rpc/')) return json(null);
  const one = (req.headers.get('Accept') || '').includes('vnd.pgrst.object');
  if (u.pathname === '/rest/v1/app_secrets') {
    const v = SECRETS[(u.searchParams.get('key') || '').replace(/^eq\./, '')];
    if (v === undefined) return one ? json({ message: 'none' }, 406) : json([]);
    return one ? json({ value: v }) : json([{ value: v }]);
  }
  if (u.pathname === '/rest/v1/leads' && req.method === 'GET') return one ? json({ id: SUP.id }) : json([{ id: SUP.id }]);
  if (req.method === 'PATCH' || req.method === 'DELETE') return new Response(null, { status: 204 });
  if (req.method === 'POST') return new Response(null, { status: 201 });
  return one ? json({ message: 'none' }, 406) : json([]);
}) as typeof fetch;

// deno-lint-ignore no-explicit-any
(globalThis as any).EdgeRuntime = { waitUntil: (_p: Promise<unknown>) => {} };

const { documentActions } = await import('./actions/documents.ts');
const { MODEL_ANSWER_BUDGET_MS } = await import('../_shared/licence_read_state.ts');

Deno.test({
  name: 'save_documents attaches a stored licence and answers within the model budget when the model does not answer',
  sanitizeOps: false, sanitizeResources: false,
  fn: async () => {
    const t0 = Date.now();
    const action = 'save_documents';
    const b = { action, items: [{ kind: 'license', original_b64: PNG_B64, mime: 'image/png', filename: 'ZZ_DEMO_licence_photo.png' }] };
    const run = documentActions({ email: SUP.claimed_by, sup: SUP, supId: SUP.id, b, action } as never);
    const guard = new Promise<'cut'>((ok) => setTimeout(() => ok('cut'), 30_000));
    const r = await Promise.race([run, guard]);
    const ms = Date.now() - t0;
    try {
      assert(r !== 'cut', 'save_documents did not answer within 30 s while the model was silent');
      assert(ms < MODEL_ANSWER_BUDGET_MS + 5_000, `answered in ${ms} ms; the model may hold it at most ${MODEL_ANSWER_BUDGET_MS} ms`);
      const write = calls.find((c) => c.method === 'PATCH' && c.path === '/rest/v1/leads' && /"license_doc_path":"licence\/990002\//.test(c.body));
      assert(write, 'the stored licence was never attached to the row');
      assertEquals(JSON.parse(write.body).licence_read_state, 'ours_failed', 'a model that did not answer leaves the licence ours to read again');
    } finally { release(); }
  },
});
