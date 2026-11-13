// deno test supabase/functions/dropbox_backup/move.test.ts
// A re-filed row MOVES its file (files/move_v2) instead of uploading a second copy (ruling 1680, 13 Nov 2026).
import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { moveFile } from './move.ts';

type Files = Map<string, { size: number; content_hash: string }>;
function fake(files: Files) {
  const calls: unknown[] = [];
  const dbx = {
    call(_host: 'api' | 'content', endpoint: string, arg: unknown): Promise<Response> {
      calls.push([endpoint, arg]);
      const a = arg as { from_path: string; to_path: string };
      if (endpoint !== 'files/move_v2') return Promise.resolve(new Response('unexpected', { status: 500 }));
      if (!files.has(a.from_path)) return Promise.resolve(new Response('{"error_summary":"from_lookup/not_found/.."}', { status: 409 }));
      if (files.has(a.to_path)) return Promise.resolve(new Response('{"error_summary":"to/conflict/file/.."}', { status: 409 }));
      files.set(a.to_path, files.get(a.from_path)!); files.delete(a.from_path);
      return Promise.resolve(new Response('{"metadata":{}}', { status: 200 }));
    },
  };
  const meta = (p: string) => Promise.resolve(files.has(p) ? { missing: false as const, ...files.get(p)! } : { missing: true as const });
  return { dbx, meta, calls };
}
const OLD = '/QuotesDone Backup/Suppliers/uncategorized/ZZ DEMO Co (1)/Trade licence - 1794504328051_l.pdf';
const NEW = '/QuotesDone Backup/Suppliers/Real estate brokerage & property management/ZZ DEMO CO LLC/Earlier versions/Trade licence - 2026-11-12 2025 - l.pdf';

Deno.test('a done file is moved, and the move is confirmed by size and hash: no second copy is left behind', async () => {
  const files: Files = new Map([[OLD, { size: 10, content_hash: 'h1' }]]);
  const { dbx, meta } = fake(files);
  assertEquals(await moveFile(dbx, OLD, NEW, meta, 'h1'), { moved: true, size: 10, content_hash: 'h1' });
  assertEquals([...files.keys()], [NEW]);
});

Deno.test('nothing at the old path: the row is uploaded as a new one', async () => {
  const { dbx, meta } = fake(new Map());
  assertEquals(await moveFile(dbx, OLD, NEW, meta, 'h1'), { moved: false, upload: true });
});

Deno.test('a move whose bookkeeping failed last time: the old copy is gone, so the row is uploaded again (overwrite, same bytes)', async () => {
  const { dbx, meta } = fake(new Map([[NEW, { size: 10, content_hash: 'h1' }]]));
  assertEquals(await moveFile(dbx, OLD, NEW, meta, 'h1'), { moved: false, upload: true });
});

Deno.test('a different file already at the new path is never overwritten by a move', async () => {
  const files: Files = new Map([[OLD, { size: 10, content_hash: 'h1' }], [NEW, { size: 9, content_hash: 'other' }]]);
  const { dbx, meta } = fake(files);
  await assertRejects(() => moveFile(dbx, OLD, NEW, meta, 'h1'), Error, 'already at');
  assertEquals(files.get(NEW)?.content_hash, 'other');
});

Deno.test('the same path, or no old path, is not a move', async () => {
  const { dbx, meta, calls } = fake(new Map());
  assertEquals(await moveFile(dbx, NEW, NEW, meta), { moved: false, upload: true });
  assertEquals(await moveFile(dbx, '', NEW, meta), { moved: false, upload: true });
  assertEquals(calls.length, 0);
});

Deno.test('the quotation of a quoted job is asked of customer_api with the backup credential, and its answer is the file', async () => {
  const { quotationFile } = await import('./row.ts');
  const admin = { from: () => ({ select: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve({ data: { value: 'x'.repeat(32) } }) }) }) }) };
  let sent: Record<string, unknown> = {};
  const ok = (_u: string | URL | Request, init?: RequestInit) => { sent = JSON.parse(String(init?.body)); return Promise.resolve(new Response('{"ok":true,"bucket":"backups","path":"generated/1_q.pdf"}')); };
  assertEquals(await quotationFile(admin, 'https://x', 'q1', ok as typeof fetch), { bucket: 'backups', path: 'generated/1_q.pdf' });
  assertEquals([sent.action, sent.quote_id, sent.lang], ['quotation_for_backup', 'q1', 'en']);
  const held = () => Promise.resolve(new Response('{"error":"held"}', { status: 503 }));
  await assertRejects(() => quotationFile(admin, 'https://x', 'q1', held as typeof fetch), Error, 'quotation held');
});
