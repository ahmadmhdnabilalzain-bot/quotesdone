// deno test supabase/functions/dropbox_backup/listing.test.ts
// The daily listing check must find a deleted copy and a changed copy, ignore case, never read an
// unfinished row as missing, and never compare a listing the deadline cut short.
import { assertEquals } from 'jsr:@std/assert@1';
import { DropboxClient } from './dropbox.ts';
import { compareListing, dailyRoots, listTree, type Expected } from './listing.ts';

Deno.test('a deleted copy is missing, a re-written copy is changed, a stray file is counted', () => {
  const expected: Expected[] = [
    [1, '/QuotesDone Backup/Suppliers/Cat/ZZ Co (7)/Trade licence - a.pdf', 'h1', 'done'],
    [2, '/QuotesDone Backup/Suppliers/Cat/ZZ Co (7)/Company Details.pdf', 'h2', 'done'],
    [3, '/QuotesDone Backup/Suppliers/Cat/ZZ Co (7)/Insurance - b.pdf', 'h3', 'done'],
    [4, '/QuotesDone Backup/Suppliers/Cat/ZZ Co (7)/VAT certificate - c.pdf', null, 'pending'],
  ];
  const listed = [
    { p: '/QuotesDone Backup/Suppliers/cat/zz co (7)/trade licence - a.pdf', h: 'h1', s: 10 },   // case differs: still found
    { p: '/QuotesDone Backup/Suppliers/Cat/ZZ Co (7)/Insurance - b.pdf', h: 'hX', s: 11 },
    { p: '/QuotesDone Backup/Suppliers/Cat/ZZ Co (7)/old copy.pdf', h: 'h9', s: 12 },
  ];
  const c = compareListing(expected, listed);
  assertEquals(c.expected, 3);                 // the pending row is not expected in Dropbox yet
  assertEquals(c.missing, [2]);
  assertEquals(c.changed, [{ id: 3, hash: 'hX', size: 11 }]);
  assertEquals(c.stray, 1);
});

Deno.test('Arabic names compare in NFC on both sides', () => {
  const composed = 'إ'; const decomposed = 'إ'.normalize('NFD');
  const c = compareListing([[1, `/QuotesDone Backup/Customers/${composed} (1a2b3c4d)/Customer Details.pdf`, 'h', 'done']],
    [{ p: `/QuotesDone Backup/Customers/${decomposed} (1a2b3c4d)/Customer Details.pdf`, h: 'h', s: 1 }]);
  assertEquals(c.missing, []);
});

function fakeDbx(pages: unknown[][], status = 200) {
  let i = 0; const calls: string[] = [];
  const f = (url: string, _init: RequestInit): Promise<Response> => {
    calls.push(url.split('/2/')[1]);
    if (status !== 200) return Promise.resolve(new Response(JSON.stringify({ error_summary: 'path/not_found/' }), { status }));
    const entries = pages[i] ?? []; const has_more = i < pages.length - 1; i++;
    return Promise.resolve(Response.json({ entries, has_more, cursor: 'c' + i }));
  };
  return { dbx: new DropboxClient({ token: () => Promise.resolve('t'), refreshes: 0, reused: 0 }, f), calls };
}

Deno.test('the walk follows every page; a folder that is gone lists empty and complete', async () => {
  const file = (n: number) => ({ '.tag': 'file', path_display: '/QuotesDone Backup/X/' + n, content_hash: 'h' + n, size: n });
  const { dbx, calls } = fakeDbx([[file(1), { '.tag': 'folder', path_display: '/QuotesDone Backup/X/f' }], [file(2)], [file(3)]]);
  const t = await listTree(dbx, '/QuotesDone Backup/X', Date.now() + 60_000);
  assertEquals(t.complete, true);
  assertEquals(t.entries.map((e) => e.s), [1, 2, 3]);
  assertEquals(calls, ['files/list_folder', 'files/list_folder/continue', 'files/list_folder/continue']);
  const gone = await listTree(fakeDbx([], 409).dbx, '/QuotesDone Backup/Y', Date.now() + 60_000);
  assertEquals(gone, { entries: [], complete: true });
});

Deno.test('a walk the deadline stops is reported incomplete, never compared', async () => {
  const { dbx } = fakeDbx([[{ '.tag': 'file', path_display: '/a', content_hash: 'h', size: 1 }], [], []]);
  const t = await listTree(dbx, '/QuotesDone Backup/X', 0, () => 1);
  assertEquals(t.complete, false);
});

Deno.test('the roots skip _selftest and _sandbox and list Database Exports last', async () => {
  const f = (_url: string, init: RequestInit): Promise<Response> => {
    const path = JSON.parse(String(init.body)).path;
    const folders = path === '/QuotesDone Backup' ? ['Company', 'Suppliers', '_selftest', '_sandbox', 'Customers']
      : ['Database Exports', 'Correspondence'];
    return Promise.resolve(Response.json({ entries: folders.map((name) => ({ '.tag': 'folder', name })), has_more: false }));
  };
  const roots = await dailyRoots(new DropboxClient({ token: () => Promise.resolve('t'), refreshes: 0, reused: 0 }, f));
  assertEquals(roots, ['/QuotesDone Backup/Company/Correspondence', '/QuotesDone Backup/Suppliers', '/QuotesDone Backup/Customers',
    '/QuotesDone Backup/Company/Database Exports']);
});

Deno.test('dropbox_files is refreshed in slices; only the last slice of a root may remove rows', async () => {
  const { fileSlices } = await import('./listing.ts');
  const e = Array.from({ length: 4500 }, (_, i) => ({ p: `/QuotesDone Backup/X/${i}.pdf`, h: 'h', s: i, id: 'id:' + i, n: `${i}.pdf`, m: '2026-10-07T00:00:00Z' }));
  const sl = fileSlices(e);
  assertEquals(sl.map((s) => [s.rows.length, s.final]), [[2000, false], [2000, false], [500, true]]);
  assertEquals(sl[0].rows[1], { id: 'id:1', path: '/QuotesDone Backup/X/1.pdf', name: '1.pdf', size: 1, hash: 'h', modified: '2026-10-07T00:00:00Z' });
  // an empty root still sends one final slice, so files deleted from it leave dropbox_files too
  assertEquals(fileSlices([]), [{ rows: [], final: true }]);
});

Deno.test('the walk keeps the Dropbox id, name and time for dropbox_files; _archive is listed', async () => {
  const { dbx } = fakeDbx([[{ '.tag': 'file', id: 'id:a', name: 'a.pdf', path_display: '/QuotesDone Backup/X/a.pdf', content_hash: 'h', size: 3, server_modified: '2026-10-07T01:00:00Z' }]]);
  const t = await listTree(dbx, '/QuotesDone Backup/X', Date.now() + 60_000);
  assertEquals(t.entries[0], { p: '/QuotesDone Backup/X/a.pdf', h: 'h', s: 3, id: 'id:a', n: 'a.pdf', m: '2026-10-07T01:00:00Z' });
  const f = (_url: string, init: RequestInit): Promise<Response> => {
    const path = JSON.parse(String(init.body)).path;
    const folders = path === '/QuotesDone Backup' ? ['_archive', '_selftest', '_sandbox', 'Suppliers'] : [];
    return Promise.resolve(Response.json({ entries: folders.map((name) => ({ '.tag': 'folder', name })), has_more: false }));
  };
  assertEquals(await dailyRoots(new DropboxClient({ token: () => Promise.resolve('t'), refreshes: 0, reused: 0 }, f)),
    ['/QuotesDone Backup/_archive', '/QuotesDone Backup/Suppliers']);
});
