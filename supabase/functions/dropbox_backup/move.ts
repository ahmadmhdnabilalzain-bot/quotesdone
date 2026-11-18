// A FILE WHOSE PLACE CHANGED IS MOVED, NOT UPLOADED A SECOND TIME (it_engineer, 13 Nov 2026; founder ruling 1680).
//
// Measured 13 Nov 2026: the worker could only upload. When fn_enqueue_doc_backups re-filed a done row to a new dropbox_path (a supplier
// named by his licence, a replaced licence), the file was uploaded again at the new path and the old copy stayed where it was: the
// founder's folder held three files labelled "Trade licence". Now a re-filed row carries moved_from (the path the done file is in) and
// the worker calls files/move_v2 first. The moved file is confirmed by get_metadata (size and content hash), as an upload is.
//   moved   : the file is now at the new path (confirmed)
//   upload  : nothing is at the old path any more (moved by hand, or never uploaded there): the caller uploads as for a new row
// A destination that already holds a file is never overwritten by a move: unless the old copy is gone and the destination is the
// same bytes (an earlier move whose bookkeeping failed), it throws, the row fails loudly and the IT check sees it.
import type { DropboxClient } from './dropbox.ts';

export type MoveOutcome = { moved: true; size: number; content_hash: string } | { moved: false; upload: true };
type Meta = { missing: true } | { missing: false; size: number; content_hash: string };

export async function moveFile(
  dbx: Pick<DropboxClient, 'call'>, from: string, to: string, meta: (path: string) => Promise<Meta>, expectedHash?: string | null,
): Promise<MoveOutcome> {
  if (!from || !to || from === to) return { moved: false, upload: true };
  // THE FILE AT THE OLD PATH MUST BE THE ONE THIS ROW FILED (review of #1997, D4/D7): a revision filed under the same plain name, or a
  // second upload of a licence with the same original name, may already have overwritten it. Then this row's own stored copy is
  // uploaded to its new place instead, and the newer file stays where it is.
  if (expectedHash) {
    const at = await meta(from);
    if (at.missing || at.content_hash !== expectedHash) return { moved: false, upload: true };
  }
  const r = await dbx.call('api', 'files/move_v2', { from_path: from, to_path: to, autorename: false, allow_ownership_transfer: false });
  const t = await r.text();
  if (r.ok) {
    const m = await meta(to);
    if (m.missing) throw new Error('move: missing at ' + to + ' after files/move_v2 answered ' + r.status);
    if (expectedHash && m.content_hash !== expectedHash) throw new Error('move: content_hash at the new path is not the one uploaded');
    return { moved: true, size: m.size, content_hash: m.content_hash };
  }
  if (r.status === 409 && /from_lookup\/not_found/.test(t)) return { moved: false, upload: true };
  if (r.status === 409 && /to\/conflict/.test(t)) {
    const [src, dst] = [await meta(from), await meta(to)];
    if (src.missing && !dst.missing && (!expectedHash || dst.content_hash === expectedHash)) return { moved: true, size: dst.size, content_hash: dst.content_hash };
    throw new Error('move: a file is already at ' + to + (src.missing ? '' : ' and the old copy is still at ' + from));
  }
  throw new Error('files/move_v2 ' + r.status + ' ' + t.slice(0, 160));
}

// A MOVE TO ANOTHER TRADE LEAVES NO EMPTY FOLDER BEHIND (sales_engineer, 17 Nov 2026; founder ruling ledger 1726, 18 Nov 2026: "no empty or
// useless folder ever ... a move to another trade removes the emptied source"). Measured: Shine Carpets (supplier 2936) was filed at
// /QuotesDone Backup/Suppliers/Cleaning & facility services/SHINE CARPETS WASHING L.L.C at 08:38 and re-filed under Upholstery & soft
// furnishing at 08:45 when his trade was set. Every file moved, and the old folder stayed with an empty "Earlier versions" folder, which
// the founder opened. After a move, the party folder the file left (Suppliers/<trade>/<name> or Customers/<name>, never anything
// higher) is listed; when NOT ONE file is anywhere beneath it, it is deleted (files/delete_v2: Dropbox keeps it in "Deleted files").
// A folder holding any file is never touched. A failure never fails the move: the nightly listing finds what is left (shellFolders).
export const BACKUP_ROOT = '/QuotesDone Backup';
/** The party folder a backup path sits in: /QuotesDone Backup/Suppliers/<trade>/<name> or /QuotesDone Backup/Customers/<name>, else null. */
export function partyFolder(path: string): string | null {
  const parts = String(path || '').split('/');
  if (parts[0] !== '' || '/' + parts[1] !== BACKUP_ROOT) return null;
  if (parts[2] === 'Suppliers' && parts.length >= 6 && parts[3] && parts[4]) return parts.slice(0, 5).join('/');
  if (parts[2] === 'Customers' && parts.length >= 5 && parts[3]) return parts.slice(0, 4).join('/');
  return null;
}
type Entry = { '.tag'?: string; path_display?: string; path_lower?: string };
/** Every entry beneath a folder (recursive), or null when it cannot be listed completely. 'gone' when the folder is not there. */
async function listAll(dbx: Pick<DropboxClient, 'call'>, folder: string): Promise<Entry[] | 'gone' | null> {
  let r = await dbx.call('api', 'files/list_folder', { path: folder, recursive: true, include_deleted: false, limit: 2000 });
  const out: Entry[] = [];
  for (let page = 0; page < 50; page++) {
    const t = await r.text();
    if (r.status === 409 && t.includes('not_found')) return 'gone';
    if (!r.ok) return null;
    const j = JSON.parse(t);
    out.push(...(j.entries || []));
    if (!j.has_more) return out;
    r = await dbx.call('api', 'files/list_folder/continue', { cursor: j.cursor });
  }
  return null;
}
export type PruneOutcome = 'removed' | 'kept_has_files' | 'same_folder' | 'not_a_party_folder' | 'gone' | 'unlisted' | 'error';
/** After a move from `from` to `to`: removes the party folder `from` was in only if no file is anywhere beneath it. Never throws. */
export async function removeEmptiedSource(dbx: Pick<DropboxClient, 'call'>, from: string, to: string): Promise<PruneOutcome> {
  try {
    const src = partyFolder(from);
    if (!src) return 'not_a_party_folder';
    if (src.toLowerCase() === (partyFolder(to) ?? '').toLowerCase()) return 'same_folder';
    const all = await listAll(dbx, src);
    if (all === 'gone') return 'gone';
    if (all === null) return 'unlisted';
    if (all.some((e) => e['.tag'] === 'file')) return 'kept_has_files';
    const d = await dbx.call('api', 'files/delete_v2', { path: src });
    await d.text().catch(() => '');
    return d.ok ? 'removed' : 'error';
  } catch (_e) { return 'error'; }
}

/** THE NIGHTLY SHELL CHECK (ruling 1726): from a recursive listing of /QuotesDone Backup/Suppliers and /Customers (folders and files),
 *  every party folder with no file anywhere beneath it ('empty'), and every one no doc_backups row files anything into ('no_party':
 *  a demo or test party, or one that no longer exists). Listed and raised as a finding, never deleted here. */
export function shellFolders(entries: Entry[], expectedPaths: string[]): { empty: string[]; no_party: string[] } {
  const folders = new Map<string, string>(), withFile = new Set<string>(), owned = new Set<string>();
  for (const e of entries) {
    const p = String(e.path_display || e.path_lower || '');
    const pf = partyFolder(p + (e['.tag'] === 'folder' ? '/x' : ''));
    if (!pf) continue;
    if (!folders.has(pf.toLowerCase())) folders.set(pf.toLowerCase(), pf);
    if (e['.tag'] === 'file') withFile.add(pf.toLowerCase());
  }
  for (const p of expectedPaths) { const pf = partyFolder(p); if (pf) owned.add(pf.toLowerCase()); }
  const empty = [...folders.keys()].filter((k) => !withFile.has(k)).map((k) => folders.get(k)!).sort();
  const no_party = [...folders.keys()].filter((k) => withFile.has(k) && !owned.has(k)).map((k) => folders.get(k)!).sort();
  return { empty, no_party };
}
