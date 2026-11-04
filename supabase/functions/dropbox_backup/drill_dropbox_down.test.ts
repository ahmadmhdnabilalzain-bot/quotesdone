// DRILL D6 (docs/release/qualification_matrix.md §5.1): the Dropbox archive down. Seat accountable:
// it_engineer. Offline, against the REAL dropbox_backup handler (queue run, mode process_only) with
// fetch and env stubbed (_shared/twilio_free_harness.ts): a stateful doc_backups queue and the
// app_secrets token row are answered below, storage serves each file by HTTP Range, and
// api/content.dropboxapi.com are the dispatcher at the bottom of this file. Nothing reaches a network.
//
// Injected: Dropbox 503 on every upload; the upload connection failing (network / timeout); the
// token endpoint 503 (provider outage); the refresh token refused (invalid_grant: the token invalid
// for good); an upload that lands but whose verification (files/get_metadata) answers 503.
// Expected, in the matrix's terms:
//   safe      no row is marked 'done' that Dropbox has not confirmed by size AND content_hash
//   nothing lost  a row that failed is 'error' with its reason and attempts+1 (fn_doc_backups_next
//             claims 'error' rows again with backoff while attempts < 5); a row never reached is
//             released to 'pending' at once; a token outage claims nothing at all
//   visible   an agent_runs row under 'dropbox_backup' names the failure (error, or warn for a
//             passing provider condition)
//   recovery  the next run, Dropbox back, uploads and verifies the same rows with no hand. The one
//             exception is a refused refresh token: only the founder can re-authorise the app.
//
// The positive control: Dropbox up, both rows are uploaded, verified and marked done; and a stale
// access token (401) is refreshed once inside the run and the upload completes.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { dropboxContentHash } from './content_hash.ts';

type Row = Record<string, unknown>;
type Mode = { upload: number | 'network' | 'timeout'; token: number | 'refused'; meta: number; staleFirst?: boolean };
const UP: Mode = { upload: 200, token: 200, meta: 200 };
let mode: Mode = UP;
const dbxLog: string[] = [];
const uploaded = new Map<string, Uint8Array>();
let issued = 0;            // access tokens handed out in the current run

const FILES: Record<string, Uint8Array> = {
  'zz/d6/one.pdf': new TextEncoder().encode('%PDF-1.4 ZZ DEMO D6 one'),
  'zz/d6/two.pdf': new TextEncoder().encode('%PDF-1.4 ZZ DEMO D6 two, a little longer'),
};
function queue() {
  return Object.keys(FILES).map((p, i) => ({ id: 601 + i, attempts: 0, status: 'pending', bucket: 'supplier-docs', path: p, source: 'storage',
    dropbox_path: '/QuotesDone Backup/ZZ DEMO D6/' + p.split('/').pop(), upload_state: null, error: null } as Row));
}

function world(rows: Row[]) {
  const w = { rows, runs: [] as Row[], claimedCalls: 0, token: null as null | { value: string; updated_at: string } };
  const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
  const filt = (u: URL, k: string) => (u.searchParams.get(k) || '').replace(/^eq\./, '');
  const stub: Stub = {
    rpc: { fn_internal_auth: { ok: true, context: 'fn.backup_kick', credential_id: 1 } },
    handle: async (req, u) => {
      const p = u.pathname;
      if (p === '/rest/v1/rpc/fn_doc_backups_next') {
        w.claimedCalls++;
        const run = String((await req.clone().json()).p_run);
        const take = w.rows.filter((r) => ['pending', 'error'].includes(String(r.status)) && Number(r.attempts) < 5);
        for (const r of take) Object.assign(r, { status: 'processing', claimed_by: run });
        return J(take.map((r) => ({ ...r })));
      }
      if (p === '/rest/v1/doc_backups' && req.method === 'PATCH') {
        const body = await req.clone().json();
        const ids = u.searchParams.get('id')?.startsWith('in.') ? u.searchParams.get('id')!.slice(4, -1).split(',').map(Number) : [Number(filt(u, 'id'))];
        const touched: Row[] = [];
        for (const r of w.rows.filter((x) => ids.includes(Number(x.id)))) {
          if (u.searchParams.get('status') && r.status !== filt(u, 'status')) continue;
          if (u.searchParams.get('claimed_by') && r.claimed_by !== filt(u, 'claimed_by')) continue;
          Object.assign(r, body); touched.push({ id: r.id });
        }
        return J(touched);
      }
      if (p === '/rest/v1/agent_runs' && req.method === 'POST') { w.runs.push(await req.clone().json()); return J([], 201); }
      if (p === '/rest/v1/app_secrets' && filt(u, 'key') === 'dropbox_access_token') {
        if (req.method === 'GET') return J(w.token ? [{ ...w.token }] : []);
        const body = await req.clone().json();
        if (req.method === 'POST') { if (w.token) return J({ code: '23505', message: 'duplicate' }, 409); w.token = { value: body.value, updated_at: '2026-11-03T00:00:00.000Z' }; return J({ updated_at: w.token.updated_at }, 201); }
        if (req.method === 'PATCH') {
          if (!w.token || w.token.updated_at !== filt(u, 'updated_at')) return J([]);
          w.token = { value: body.value, updated_at: body.updated_at }; return J([{ updated_at: body.updated_at }]);
        }
      }
      const sign = p.match(/^\/storage\/v1\/object\/sign\/([^/]+)\/(.+)$/);
      if (sign && req.method === 'POST') return J({ signedURL: `/object/sign/${sign[1]}/${sign[2]}?token=zz` });
      if (sign && req.method === 'GET') {
        const bytes = FILES[decodeURIComponent(sign[2])];
        if (!bytes) return J({ error: 'not_found' }, 404);
        const [a, b] = (req.headers.get('range') || 'bytes=0-').replace('bytes=', '').split('-').map(Number);
        const part = bytes.slice(a, Math.min(bytes.length, (b || bytes.length - 1) + 1));
        return new Response(part, { status: 206, headers: { 'content-range': `bytes ${a}-${a + part.length - 1}/${bytes.length}` } });
      }
      return undefined;
    },
  };
  return { w, stub };
}

async function handler() {
  const h = await loadFunction('dropbox_backup', () => import('./index.ts'));
  const g = globalThis as unknown as { __d6?: boolean };
  if (!g.__d6) {
    g.__d6 = true;
    const inner = globalThis.fetch;
    globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const req = input instanceof Request ? input : new Request(String(input), init);
      const u = new URL(req.url);
      const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
      if (u.hostname === 'api.dropboxapi.com' && u.pathname === '/oauth2/token') {
        dbxLog.push('token');
        if (mode.token === 'refused') return J({ error: 'invalid_grant', error_description: 'refresh token is malformed' }, 400);
        if (mode.token !== 200) return J({ error: 'server_error' }, mode.token);
        return J({ access_token: 'sl.zz-d6-run-' + (++issued), expires_in: 14400 });
      }
      if (u.hostname === 'content.dropboxapi.com' || u.hostname === 'api.dropboxapi.com') {
        const ep = u.pathname.replace('/2/', '');
        dbxLog.push(ep);
        const bearer = req.headers.get('authorization') || '';
        if (mode.staleFirst && bearer.endsWith('sl.zz-d6-run-1')) return J({ error_summary: 'expired_access_token/' }, 401);
        if (ep === 'files/upload') {
          if (mode.upload === 'network') throw new TypeError('error sending request: connection reset');
          if (mode.upload === 'timeout') throw new DOMException('The signal has been aborted', 'TimeoutError');
          if (mode.upload !== 200) return J({ error_summary: 'internal_error/' }, mode.upload);
          const arg = JSON.parse(req.headers.get('dropbox-api-arg') || '{}');
          uploaded.set(arg.path, new Uint8Array(await req.arrayBuffer()));
          return J({ path_display: arg.path });
        }
        if (ep === 'files/get_metadata') {
          if (mode.meta !== 200) return J({ error_summary: 'internal_error/' }, mode.meta);
          const { path } = await req.json();
          const b = uploaded.get(path);
          if (!b) return J({ error_summary: 'path/not_found/' }, 409);
          return J({ '.tag': 'file', size: b.length, content_hash: await dropboxContentHash(b) });
        }
        return J({});
      }
      return inner(input, init);
    }) as typeof fetch;
  }
  return h;
}
async function run(rows: Row[], m: Mode) {
  mode = m; dbxLog.length = 0; uploaded.clear(); issued = 0;
  const h = await handler();
  const { w, stub } = world(rows);
  // chain 1: a drain link, so the run is the queue walk alone (the unfinished sign-up purge runs on chain 0)
  const r = await invoke(h, stub, { __secret: 'stub-internal-credential-0123456789', mode: 'process_only', chain: 1 });
  return { r, w };
}
const runs = (w: { runs: Row[] }, status: string) => w.runs.filter((x) => x.agent === 'dropbox_backup' && x.status === status);

Deno.test('D6 positive control: Dropbox up, both documents are uploaded, verified and marked done', async () => {
  const { r, w } = await run(queue(), UP);
  assertEquals(r.status, 200, JSON.stringify(r.json));
  assertEquals(w.rows.map((x) => x.status), ['done', 'done']);
  assert(w.rows.every((x) => typeof x.dropbox_content_hash === 'string' && x.verified_at), 'each is confirmed by content_hash');
  assertEquals(runs(w, 'ok').length >= 1, true);
});

Deno.test('D6 positive control: a stale access token (401) is refreshed once inside the run and the upload completes', async () => {
  const { w } = await run(queue(), { ...UP, staleFirst: true });
  assertEquals(w.rows.map((x) => x.status), ['done', 'done']);
  assertEquals(dbxLog.filter((x) => x === 'token').length, 2, 'one token for the run, one refresh after the 401');
});

for (const [label, upload] of [['503', 503], ['network failure', 'network'], ['timeout', 'timeout']] as [string, Mode['upload']][]) {
  Deno.test(`D6 Dropbox upload ${label}: nothing is marked done, each row is 'error' with its reason, and the next run recovers it`, async () => {
    const rows = queue();
    const { r, w } = await run(rows, { ...UP, upload });
    assertEquals(r.status, 200);
    assertEquals(dbxLog.filter((x) => x === 'files/upload').length, 6, 'three tries per row (upload.ts send), then the row fails');
    assertEquals(w.rows.map((x) => x.status), ['error', 'error'], 'safe: nothing done that Dropbox did not confirm');
    assert(w.rows.every((x) => Number(x.attempts) === 1 && /files\/upload .*after 3 tries/.test(String(x.error))), 'nothing lost: the reason and attempts are on the row ' + JSON.stringify(w.rows.map((x) => x.error)));
    assert(runs(w, 'error').some((x) => /failed document/.test(String(x.note))), 'visible: an error run names the failed documents');
    // recovery: Dropbox is back; fn_doc_backups_next claims the 'error' rows again (attempts < 5)
    const again = await run(w.rows, UP);
    assertEquals(again.w.rows.map((x) => x.status), ['done', 'done'], 'the next run uploads them with no hand');
    assert(again.w.rows.every((x) => x.verified_at && x.error === null));
  });
}

Deno.test('D6 Dropbox token endpoint 503: nothing is claimed, nothing is marked failed, the run is logged warn', async () => {
  const rows = queue();
  const { r, w } = await run(rows, { ...UP, token: 503 });
  assertEquals(r.status, 503);
  assertEquals(r.json.error, 'dropbox_token_unavailable');
  assertEquals(w.claimedCalls, 0, 'no row was claimed');
  assertEquals(w.rows.map((x) => [x.status, x.attempts]), [['pending', 0], ['pending', 0]]);
  assertEquals(runs(w, 'warn').length, 1, 'visible, as a passing provider condition');
  const again = await run(w.rows, UP);
  assertEquals(again.w.rows.map((x) => x.status), ['done', 'done']);
});

Deno.test('D6 refresh token refused (token invalid for good): the first row fails loudly, the rest go back to pending', async () => {
  const rows = queue();
  const { w } = await run(rows, { ...UP, token: 'refused' });
  assertEquals(w.rows.map((x) => x.status), ['error', 'pending'], 'the unreached row is released at once, not left processing');
  assertEquals(w.rows[0].error, 'no_dropbox_auth');
  assertEquals(w.rows[1].claimed_by, null);
  assert(runs(w, 'error').some((x) => /no_dropbox_auth/.test(String(x.note))), 'visible: an error run names no_dropbox_auth');
  assertEquals(dbxLog.filter((x) => x === 'files/upload').length, 0, 'no upload without a token');
});

Deno.test('D6 upload lands but its verification answers 503: the row is not marked done', async () => {
  const rows = queue();
  const { w } = await run(rows, { ...UP, meta: 503 });
  assertEquals(w.rows.map((x) => x.status), ['error', 'error']);
  assert(w.rows.every((x) => /get_metadata 503/.test(String(x.error))), JSON.stringify(w.rows.map((x) => x.error)));
  const again = await run(w.rows, UP);
  assertEquals(again.w.rows.map((x) => x.status), ['done', 'done']);
});
