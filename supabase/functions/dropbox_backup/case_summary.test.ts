// A case summary reaches the person's Dropbox folder as <folder>/cases/<case number>.md (ruling 1635, customer_support,
// 11 Nov 2026). The integration's sandbox run needs the SQL applied and the function deployed, which this build does not
// do, so the request is proved here through the REAL backupRow -> renderGenerated -> caseSummaryFile -> storage ->
// uploadFile -> verifyUploaded path, on a stubbed fetch: what Dropbox receives, byte for byte, for a ZZ DEMO case.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { backupRow, type Row } from './row.ts';
import { DropboxClient } from './dropbox.ts';
import { dropboxContentHash } from './content_hash.ts';
import { caseMarkdown, dubaiStamp } from '../_shared/case_dropbox.ts';

const REF = 'QD-S-ZZDEMO1';
const DEST = '/QuotesDone Backup/Customers/ZZ DEMO Case Probe (c0ffee00)/cases/' + REF + '.md';
const caseRow = (v: number, said: string) => ({
  case_ref: REF, title: 'ZZ DEMO windows quote', subject: 'Widget: windows', status_plain: 'waiting_on_them',
  summary_text: `ASKED: ZZ DEMO a quote for 4 windows\nWE SAID OR DID: ${said}\nWE PROMISED:\n- send the quotes (by tomorrow)\nSTILL OPEN:\n- nothing`,
  summary_version: v, summary_updated_at: '2026-11-11T10:00:00Z', opened_at: '2026-11-11T09:00:00Z', last_activity_at: '2026-11-11T10:00:00Z',
  channels: ['widget', 'email'], party_kind: 'customer', customer_profile_id: 77,
});

// deno-lint-ignore no-explicit-any
type Db = Record<string, any[]>;
function fakeAdmin(db: Db) {
  const files = new Map<string, { bytes: Uint8Array; contentType: string }>();
  const writes: { table: string; patch: Record<string, unknown>; filters: [string, unknown][] }[] = [];
  const from = (table: string) => {
    const filters: [string, unknown][] = []; let patch: Record<string, unknown> | null = null;
    const rows = () => (db[table] ?? []).filter((r) => filters.every(([k, v]) => r[k] === v));
    // deno-lint-ignore no-explicit-any
    const b: any = {
      select: () => b, order: () => b, eq: (k: string, v: unknown) => { filters.push([k, v]); return b; },
      update: (p: Record<string, unknown>) => { patch = p; return b; },
      maybeSingle: () => Promise.resolve({ data: rows()[0] ?? null, error: null }),
      then: (ok: (x: unknown) => unknown) => {
        if (patch) { writes.push({ table, patch, filters: [...filters] }); return Promise.resolve({ error: null }).then(ok); }
        return Promise.resolve({ data: rows(), error: null }).then(ok);
      },
    };
    return b;
  };
  const storage = { from: (bucket: string) => ({
    upload: (path: string, bytes: Uint8Array, o: { upsert?: boolean; contentType?: string }) => {
      assert(o.upsert, 'the case file is overwritten in storage, one object per case');
      files.set(bucket + '/' + path, { bytes, contentType: String(o.contentType) }); return Promise.resolve({ error: null });
    },
    createSignedUrl: (path: string) => Promise.resolve({ data: { signedUrl: 'https://storage.test/' + bucket + '/' + path }, error: null }),
  }) };
  return { admin: { from, storage }, files, writes };
}

/** The storage reads (HTTP Range, as storageSource makes them) answered from the fake bucket; anything else is refused. */
function withStorageFetch(files: Map<string, { bytes: Uint8Array }>, run: () => Promise<void>) {
  const real = globalThis.fetch;
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    if (!url.startsWith('https://storage.test/')) throw new Error('unexpected request: ' + url + ' (no PDF renderer, no other call)');
    const f = files.get(url.slice('https://storage.test/'.length))!;
    const m = /bytes=(\d+)-(\d+)/.exec(new Headers(init?.headers).get('Range') ?? '')!;
    const a = Number(m[1]); const z = Math.min(Number(m[2]), f.bytes.length - 1);
    return Promise.resolve(new Response(f.bytes.slice(a, z + 1), { status: 206, headers: { 'Content-Range': `bytes ${a}-${z}/${f.bytes.length}` } }));
  }) as typeof fetch;
  return run().finally(() => { globalThis.fetch = real; });
}

/** Dropbox, stubbed: every request recorded; files/upload keeps the bytes; get_metadata answers what was uploaded. */
function fakeDropbox() {
  const calls: { url: string; arg: Record<string, unknown>; body: Uint8Array | null }[] = [];
  const stored = new Map<string, Uint8Array>();
  const f = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input); const h = new Headers(init?.headers);
    assertEquals(h.get('Authorization'), 'Bearer ZZDEMO-TOKEN');
    if (url.endsWith('/files/upload')) {
      const arg = JSON.parse(h.get('Dropbox-API-Arg')!); const body = new Uint8Array(init!.body as Uint8Array);
      calls.push({ url, arg, body }); stored.set(String(arg.path), body);
      return new Response(JSON.stringify({ '.tag': 'file', path_display: arg.path, size: body.length }), { status: 200 });
    }
    if (url.endsWith('/files/get_metadata')) {
      const arg = JSON.parse(String(init!.body)); calls.push({ url, arg, body: null });
      const b = stored.get(String(arg.path));
      if (!b) return new Response('{"error_summary":"path/not_found/"}', { status: 409 });
      return new Response(JSON.stringify({ '.tag': 'file', size: b.length, content_hash: await dropboxContentHash(b) }), { status: 200 });
    }
    throw new Error('unexpected Dropbox call ' + url);
  }) as typeof fetch;
  const dbx = new DropboxClient({ token: () => Promise.resolve('ZZDEMO-TOKEN'), refreshes: 0, reused: false } as never, f);
  return { dbx, calls, stored };
}

const row = (): Row => ({ id: 9001, attempts: 0, source: 'generated', gen_kind: 'case_summary', gen_ref: REF, bucket: null, path: null,
  dropbox_path: DEST, entity: 'customer', entity_id: 'c0ffee00-0000-4000-8000-000000000001', status: 'processing', upload_state: null });

Deno.test('a ZZ DEMO case: Dropbox receives ONE files/upload of <folder>/cases/<case>.md, overwrite, the case as text, then it is verified', async () => {
  const db: Db = {
    support_case: [caseRow(2, 'took the sizes')],
    support_case_promise: [{ case_ref: REF, what: 'send the quotes', due_at: '2026-11-12T14:00:00Z', due_basis: 'stated', owner_seat: 'sales_engineer', status: 'open', closed_how: null }],
    support_customer_profile: [{ id: 77, display_name: 'ZZ DEMO Case Probe' }],
  };
  const { admin, files, writes } = fakeAdmin(db);
  const { dbx, calls } = fakeDropbox();
  await withStorageFetch(files, async () => {
    const out = await backupRow(admin, dbx, row(), { supabaseUrl: 'https://project.test', deadline: Date.now() + 30_000, release: { claimed_at: null, claimed_by: null } });
    assert('done' in out, 'the row is done: ' + JSON.stringify(out));
  });
  // the request Dropbox received
  const up = calls.filter((c) => c.url === 'https://content.dropboxapi.com/2/files/upload');
  assertEquals(up.length, 1);
  assertEquals(up[0].arg, { path: DEST, mode: 'overwrite', autorename: false, mute: true, strict_conflict: false });
  const text = new TextDecoder().decode(up[0].body!);
  assert(text.startsWith('# Case ' + REF + ': ZZ DEMO windows quote\n'), text.slice(0, 80));
  assert(text.includes('- With: ZZ DEMO Case Probe') && text.includes('- Status: waiting on them') && text.includes('- Channels: widget, email'));
  assert(text.includes('WE SAID OR DID: took the sizes'), 'the summary itself');
  assert(text.includes('| send the quotes | ' + dubaiStamp('2026-11-12T14:00:00Z') + ' | Sales Engineer | open |'), 'the promise ledger row');
  assertEquals(calls.filter((c) => c.url === 'https://api.dropboxapi.com/2/files/get_metadata').map((c) => c.arg.path), [DEST], 'verified after upload');
  // the storage copy dropbox_backup reads it from: one object per case, text/markdown
  assertEquals([...files.keys()], ['backups/generated/cases/' + REF + '.md']);
  assertEquals(files.get('backups/generated/cases/' + REF + '.md')!.contentType, 'text/markdown; charset=utf-8');
  // and the row is marked with what Dropbox holds
  const done = writes.find((w) => w.table === 'doc_backups' && w.patch.status === 'done')!;
  assertEquals(done.patch.dropbox_content_hash, await dropboxContentHash(up[0].body!));
  assertEquals(writes.find((w) => w.table === 'doc_backups' && 'path' in w.patch)?.patch.path, 'generated/cases/' + REF + '.md');
});

Deno.test('a newer summary version overwrites the same Dropbox file with the case as it is now', async () => {
  const db: Db = { support_case: [caseRow(2, 'took the sizes')], support_case_promise: [], support_customer_profile: [] };
  const { admin, files } = fakeAdmin(db);
  const { dbx, calls, stored } = fakeDropbox();
  await withStorageFetch(files, async () => {
    await backupRow(admin, dbx, row(), { supabaseUrl: 'x', deadline: Date.now() + 30_000, release: {} });
    db.support_case = [caseRow(3, 'sent the four quotes')];
    await backupRow(admin, dbx, row(), { supabaseUrl: 'x', deadline: Date.now() + 30_000, release: {} });
  });
  assertEquals(calls.filter((c) => c.url.endsWith('/files/upload')).map((c) => c.arg.path), [DEST, DEST], 'one path, written twice');
  const now = new TextDecoder().decode(stored.get(DEST)!);
  assert(now.includes('sent the four quotes') && now.includes('- Summary version: 3') && !now.includes('took the sizes'), 'the newer version is what Dropbox holds');
});

Deno.test('a case with no summary yet is not written (the row fails and is retried, never an empty file)', async () => {
  const { admin, files } = fakeAdmin({ support_case: [{ ...caseRow(0, ''), summary_text: null }] });
  const { dbx, calls } = fakeDropbox();
  let err = '';
  await withStorageFetch(files, async () => {
    try { await backupRow(admin, dbx, row(), { supabaseUrl: 'x', deadline: Date.now() + 30_000, release: {} }); } catch (e) { err = String((e as Error).message); }
  });
  assertEquals(err, 'case_has_no_summary');
  assertEquals(calls.length, 0);
});

Deno.test('the text is plain Markdown a person can read: an undated promise says so, a closed one says how', () => {
  const md = caseMarkdown(caseRow(4, 'x') as never, [
    { what: 'call them | back', due_at: '2026-11-13T10:00:00Z', due_basis: 'assumed', owner_seat: 'customer_support', status: 'open', closed_how: null },
    { what: 'send the quotes', due_at: '2026-11-12T14:00:00Z', due_basis: 'stated', owner_seat: 'sales_engineer', status: 'kept', closed_how: 'quotes delivered: notification 12' },
  ], null);
  assert(md.includes('| call them / back | 2026-11-13 14:00 Dubai (no date was given) | Customer Support | open |'), md);
  assert(md.includes('| kept: quotes delivered: notification 12 |'));
  assert(md.includes('- With: a customer'));
});
