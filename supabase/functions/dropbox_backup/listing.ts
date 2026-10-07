// The daily listing check (it_engineer, 7 Oct 2026; founder gate, ledger 1162).
//
// Until v12 the daily check re-read only NEW rows; an existing copy was re-read by a weekly random
// sample of 20 of 24,156, so a file deleted from Dropbox could stay unnoticed for years. Dropbox lists
// 2,000 entries per call with each file's content_hash and size, so the whole tree (24k files) is read
// in about a dozen calls and compared with every doc_backups row, every day:
//   missing  a row 'done' whose file is not in the listing   (confirmed one by one before it is reported)
//   changed  a row 'done' whose file is listed with another content_hash
//   stray    a listed file no doc_backups row names (counted, never deleted)
// Paths are compared NFC-normalised and lower-cased on both sides: Dropbox paths are case-insensitive,
// and its path_lower is not guaranteed to equal Postgres lower() for every script.
import type { DropboxClient } from './dropbox.ts';

// id/n/m (Dropbox file id, name, server_modified) are kept so the walk also refreshes public.dropbox_files.
export type Listed = { p: string; h: string; s: number; id?: string; n?: string; m?: string };
// [id, dropbox_path, dropbox_content_hash, status] as fn_it_backup_listing_expected returns it
export type Expected = [number, string, string | null, string];
export type Compared = { expected: number; listed: number; missing: number[]; changed: { id: number; hash: string; size: number }[]; stray: number };

export const pathKey = (p: string) => p.normalize('NFC').toLowerCase();

export function compareListing(expected: Expected[], listed: Listed[]): Compared {
  const byPath = new Map(listed.map((l) => [pathKey(l.p), l]));
  const known = new Set(expected.map((e) => pathKey(e[1])));
  const missing: number[] = []; const changed: Compared['changed'] = []; let done = 0;
  for (const [id, path, hash, status] of expected) {
    if (status !== 'done') continue;
    done++;
    const l = byPath.get(pathKey(path));
    if (!l) missing.push(id);
    else if (hash && l.h !== hash) changed.push({ id, hash: l.h, size: l.s });
  }
  let stray = 0;
  for (const l of listed) if (!known.has(pathKey(l.p))) stray++;
  return { expected: done, listed: listed.length, missing, changed, stray };
}

// Every file under `root`, recursively. `complete` is false when the deadline stopped the walk: an
// incomplete listing is never compared (every file not yet listed would read as missing).
export async function listTree(dbx: DropboxClient, root: string, deadline: number, now: () => number = Date.now): Promise<{ entries: Listed[]; complete: boolean }> {
  const entries: Listed[] = [];
  let r = await dbx.call('api', 'files/list_folder', { path: root, recursive: true, include_deleted: false, limit: 2000 });
  for (;;) {
    const t = await r.text();
    if (r.status === 409 && t.includes('not_found')) return { entries, complete: true };   // the folder is gone: every file in it is missing
    if (!r.ok) throw new Error('list_folder ' + r.status + ' ' + t.slice(0, 160));
    const j = JSON.parse(t);
    for (const e of j.entries || []) if (e['.tag'] === 'file') entries.push({ p: String(e.path_display || e.path_lower), h: String(e.content_hash || ''), s: Number(e.size), id: e.id, n: e.name, m: e.server_modified });
    if (!j.has_more) return { entries, complete: true };
    if (now() >= deadline) return { entries, complete: false };
    r = await dbx.call('api', 'files/list_folder/continue', { cursor: j.cursor });
  }
}

// The roots the daily check lists: every top folder of the backup, and Company's sub-folders one by one
// so the large Database Exports folder is listed last and alone. Never _selftest or _sandbox (probes and
// tagged demo runs); _archive (moved, never deleted, copies) IS listed.
export async function dailyRoots(dbx: DropboxClient): Promise<string[]> {
  const names = async (path: string) => {
    const r = await dbx.call('api', 'files/list_folder', { path, recursive: false, include_deleted: false, limit: 2000 });
    if (!r.ok) throw new Error('list_folder ' + path + ' ' + r.status + ' ' + (await r.text()).slice(0, 160));
    const j = await r.json();
    return (j.entries || []).filter((e: Record<string, string>) => e['.tag'] === 'folder').map((e: Record<string, string>) => String(e.name));
  };
  const top = (await names('/QuotesDone Backup')).filter((n: string) => n !== '_selftest' && n !== '_sandbox');
  const roots: string[] = [];
  for (const n of top) {
    if (n !== 'Company') { roots.push('/QuotesDone Backup/' + n); continue; }
    for (const s of await names('/QuotesDone Backup/Company')) roots.push('/QuotesDone Backup/Company/' + s);
  }
  return roots.sort((a, b) => Number(/Database Exports$/.test(a)) - Number(/Database Exports$/.test(b)));
}

// public.dropbox_files is refreshed from the same walk (it_engineer, 7 Oct 2026: last synced 7 Sep, and
// seven routines still read it). Sent in slices so no request carries 21k rows; the LAST slice of a
// completely listed root removes the rows under that root this walk did not see.
export const FILES_SLICE = 2000;
export function fileSlices(entries: Listed[], n = FILES_SLICE) {
  const rows = entries.map((e) => ({ id: e.id ?? null, path: e.p, name: e.n ?? e.p.replace(/^.*\//, ''), size: e.s, hash: e.h, modified: e.m ?? null }));
  const out: { rows: typeof rows; final: boolean }[] = [];
  for (let i = 0; i < rows.length; i += n) out.push({ rows: rows.slice(i, i + n), final: i + n >= rows.length });
  if (!out.length) out.push({ rows: [], final: true });
  return out;
}
