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
  assert(/\(Suppliers\|Customers\)\$\/\.test\(root\)[\s\S]{0,200}shellFolders\(/.test(idx));
  assert(/shell_folders: shells\.empty\.length/.test(idx));
  // the worker never deletes from the shell check: delete_v2 appears only in purge.ts paths and removeEmptiedSource
  assert(!/delete_v2/.test(idx.slice(idx.indexOf('async function listingCheck'), idx.indexOf('// ── THE TAGGED SANDBOX RUN'))));
});
