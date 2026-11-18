// deno test supabase/functions/dropbox_backup/empty_source.test.ts
// A move to another trade removes the folder it emptied, and only an empty one (sales_engineer, 17 Nov 2026; founder ruling 1726).
// The case: Shine Carpets (supplier 2936) filed under "Cleaning & facility services" at 08:38, re-filed under "Upholstery & soft
// furnishing" at 08:45; the old folder was left holding only an empty "Earlier versions" folder.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { moveFile, partyFolder, removeEmptiedSource, shellFolders } from './move.ts';

const OLD = '/QuotesDone Backup/Suppliers/Cleaning & facility services/ZZ DEMO SHINE CO';
const NEW = '/QuotesDone Backup/Suppliers/Upholstery & soft furnishing/ZZ DEMO SHINE CO';
type Node = { tag: 'file' | 'folder'; size?: number; hash?: string };
function fakeTree(tree: Map<string, Node>) {
  const calls: string[] = [];
  const under = (root: string) => [...tree.entries()].filter(([p]) => p.toLowerCase().startsWith(root.toLowerCase() + '/'));
  const dbx = {
    call(_h: 'api' | 'content', endpoint: string, arg: unknown): Promise<Response> {
      calls.push(endpoint);
      const a = arg as Record<string, string>;
      if (endpoint === 'files/move_v2') {
        if (!tree.has(a.from_path)) return Promise.resolve(new Response('{"error_summary":"from_lookup/not_found/"}', { status: 409 }));
        tree.set(a.to_path, tree.get(a.from_path)!); tree.delete(a.from_path);
        return Promise.resolve(new Response('{}', { status: 200 }));
      }
      if (endpoint === 'files/list_folder') {
        if (!tree.has(a.path)) return Promise.resolve(new Response('{"error_summary":"path/not_found/"}', { status: 409 }));
        return Promise.resolve(new Response(JSON.stringify({ has_more: false, entries: under(a.path).map(([p, n]) => ({ '.tag': n.tag, path_display: p })) })));
      }
      if (endpoint === 'files/delete_v2') {
        tree.delete(a.path); for (const [p] of under(a.path)) tree.delete(p);
        return Promise.resolve(new Response('{}', { status: 200 }));
      }
      return Promise.resolve(new Response('unexpected', { status: 500 }));
    },
  };
  const meta = (p: string) => Promise.resolve(tree.get(p)?.tag === 'file' ? { missing: false as const, size: tree.get(p)!.size!, content_hash: tree.get(p)!.hash! } : { missing: true as const });
  return { dbx, meta, calls };
}

Deno.test('the party folder of a path is Suppliers/<trade>/<name> or Customers/<name>, never higher', () => {
  assertEquals(partyFolder(OLD + '/Earlier versions/Trade licence - a.pdf'), OLD);
  assertEquals(partyFolder('/QuotesDone Backup/Customers/ZZ DEMO Buyer (c0ffee00)/cases/QD-1.md'), '/QuotesDone Backup/Customers/ZZ DEMO Buyer (c0ffee00)');
  for (const p of ['/QuotesDone Backup/Suppliers/Cleaning & facility services', '/QuotesDone Backup/Suppliers', '/QuotesDone Backup/Finance/Revenue Invoices/x.pdf',
    '/QuotesDone Backup/Company/Database Exports/a.csv', '/Other/Suppliers/a/b/c.pdf', '']) assertEquals(partyFolder(p), null, p);
});

Deno.test('Shine Carpets: the last file moved out, the old folder with only an empty "Earlier versions" is removed', async () => {
  const tree = new Map<string, Node>([[OLD, { tag: 'folder' }], [OLD + '/Earlier versions', { tag: 'folder' }],
    [OLD + '/Earlier versions/Not a trade licence - a.pdf', { tag: 'file', size: 9, hash: 'h1' }], [NEW, { tag: 'folder' }]]);
  const { dbx, meta } = fakeTree(tree);
  const from = OLD + '/Earlier versions/Not a trade licence - a.pdf', to = NEW + '/Earlier versions/Not a trade licence - a.pdf';
  assertEquals((await moveFile(dbx, from, to, meta, 'h1')).moved, true);
  assertEquals(await removeEmptiedSource(dbx, from, to), 'removed');
  assert(![...tree.keys()].some((p) => p.startsWith(OLD)), 'nothing of the old folder is left');
  assert(tree.has(to));
});

Deno.test('a folder that still holds a file is never deleted (the other files have not moved yet)', async () => {
  const tree = new Map<string, Node>([[OLD, { tag: 'folder' }], [OLD + '/Company Details.pdf', { tag: 'file', size: 1, hash: 'h' }]]);
  const { dbx, calls } = fakeTree(tree);
  assertEquals(await removeEmptiedSource(dbx, OLD + '/Trade licence.pdf', NEW + '/Trade licence.pdf'), 'kept_has_files');
  assert(!calls.includes('files/delete_v2') && tree.has(OLD + '/Company Details.pdf'));
});

Deno.test('a move inside the same party folder, outside the party tree, or a listing that fails deletes nothing', async () => {
  const tree = new Map<string, Node>([[OLD, { tag: 'folder' }]]);
  const { dbx, calls } = fakeTree(tree);
  assertEquals(await removeEmptiedSource(dbx, OLD + '/a.pdf', OLD + '/Earlier versions/a.pdf'), 'same_folder');
  assertEquals(await removeEmptiedSource(dbx, '/QuotesDone Backup/Finance/x.pdf', NEW + '/x.pdf'), 'not_a_party_folder');
  const broken = { call: () => Promise.resolve(new Response('server error', { status: 500 })) };
  assertEquals(await removeEmptiedSource(broken, OLD + '/a.pdf', NEW + '/a.pdf'), 'unlisted');
  assert(!calls.includes('files/delete_v2'));
});

Deno.test('the nightly shell check lists empty folders and folders no record files into, and deletes nothing', () => {
  const S = '/QuotesDone Backup/Suppliers';
  const entries = [
    { '.tag': 'folder', path_display: OLD }, { '.tag': 'folder', path_display: OLD + '/Earlier versions' },          // the shell
    { '.tag': 'folder', path_display: NEW }, { '.tag': 'file', path_display: NEW + '/Trade licence - a.jpg' },     // a real supplier
    { '.tag': 'folder', path_display: S + '/Flooring/ZZ DEMO Test Co' }, { '.tag': 'file', path_display: S + '/Flooring/ZZ DEMO Test Co/x.pdf' }, // nobody's
    { '.tag': 'folder', path_display: S + '/Flooring' },                                                            // a trade folder is not a party
  ];
  const r = shellFolders(entries, [NEW + '/Trade licence - a.jpg']);
  assertEquals(r.empty, [OLD]);
  assertEquals(r.no_party, [S + '/Flooring/ZZ DEMO Test Co']);
});

Deno.test('wiring: a confirmed move prunes its source, and the nightly listing runs the shell check on Suppliers and Customers', () => {
  const row = Deno.readTextFileSync(new URL('./row.ts', import.meta.url));
  assert(/if \(mv\.moved\) \{[\s\S]{0,2000}removeEmptiedSource\(dbx, String\(row\.moved_from\), String\(row\.dropbox_path\)\)/.test(row));
  const idx = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assert(/if \(PARTY_ROOT\.test\(root\)\) \{\s+partyListed\.add\(root\);[\s\S]{0,200}shellFolders\(/.test(idx));
  assert(/const PARTY_ROOT = \/\^\\\/QuotesDone Backup\\\/\(Suppliers\|Customers\)\$\//.test(idx));
  // review of #2051: 'shells' is reported only when every party tree was listed to its end; else the finding is left as it is
  assert(/const complete = partyRoots\.length > 0 && partyRoots\.every\(\(r\) => partyListed\.has\(r\)\);\s+return \{ summary: complete \? \{[^}]*shell_folders: shells\.empty\.length/.test(idx));
  // a root the deadline cut short is skipped before it can be counted as listed
  assert(idx.indexOf('if (!t.complete) { summary.unlisted_roots++; continue; }') < idx.indexOf('partyListed.add(root)'));
  // the worker never deletes from the shell check: delete_v2 appears only in purge.ts paths and removeEmptiedSource
  assert(!/delete_v2/.test(idx.slice(idx.indexOf('async function listingCheck'), idx.indexOf('// ── THE TAGGED SANDBOX RUN'))));
});

// review of #2051: a folder listed over several pages, and a file that lands between the listing and the delete
function paged(pages: Record<string, unknown>[][], after?: Record<string, unknown>[][]) {
  const calls: string[] = []; let i = 0, round = 0;
  const dbx = { call(_h: 'api' | 'content', endpoint: string): Promise<Response> {
    calls.push(endpoint);
    if (endpoint === 'files/list_folder') { i = 0; round++; }
    if (endpoint === 'files/list_folder' || endpoint === 'files/list_folder/continue') {
      const src = round > 1 && after ? after : pages; const p = src[i] ?? []; i++;
      return Promise.resolve(Response.json({ entries: p, has_more: i < src.length, cursor: 'c' + i }));
    }
    if (endpoint === 'files/delete_v2') return Promise.resolve(new Response('{}'));
    return Promise.resolve(new Response('unexpected', { status: 500 }));
  } };
  return { dbx, calls };
}
Deno.test('a file on the third page of the listing keeps the folder (every page is read)', async () => {
  const { dbx, calls } = paged([[{ '.tag': 'folder', path_display: OLD + '/a' }], [{ '.tag': 'folder', path_display: OLD + '/b' }], [{ '.tag': 'file', path_display: OLD + '/b/x.pdf' }]]);
  assertEquals(await removeEmptiedSource(dbx, OLD + '/y.pdf', NEW + '/y.pdf'), 'kept_has_files');
  assertEquals(calls.filter((c) => c === 'files/list_folder/continue').length, 2);
  assert(!calls.includes('files/delete_v2'));
});
Deno.test('a file that lands between the listing and the delete keeps the folder (it is listed again first)', async () => {
  const empty = [[{ '.tag': 'folder', path_display: OLD + '/Earlier versions' }]];
  const landed = [[{ '.tag': 'folder', path_display: OLD + '/Earlier versions' }, { '.tag': 'file', path_display: OLD + '/Trade licence.pdf' }]];
  const { dbx, calls } = paged(empty, landed);
  assertEquals(await removeEmptiedSource(dbx, OLD + '/y.pdf', NEW + '/y.pdf'), 'changed_before_delete');
  assert(!calls.includes('files/delete_v2'));
  const ok = paged(empty);
  assertEquals(await removeEmptiedSource(ok.dbx, OLD + '/y.pdf', NEW + '/y.pdf'), 'removed');
  assertEquals(ok.calls.filter((c) => c === 'files/list_folder').length, 2, 'listed twice before the delete');
});
