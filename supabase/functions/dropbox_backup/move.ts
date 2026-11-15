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
