// Uploading one file to Dropbox so that neither a failed chunk nor a run that ends mid-file loses it
// (owner: sales_engineer, 14 Sep 2026).
//
// Every file larger than CHUNK goes through an upload session. Each chunk is retried up to three
// times with backoff on a network error, 429 or 5xx. A 409 incorrect_offset whose correct_offset is
// exactly the end of the chunk just sent means the append landed and only its answer was lost, so it
// is taken as success. When the run's deadline passes, the session id, offset and the 4 MiB block
// digests are returned as `state`; the next run passes it back and continues from that offset
// (Dropbox keeps a session open for 7 days). CHUNK is a multiple of 4 MiB so the content hash can be
// carried between runs block by block.
import { DropboxHasher, dropboxContentHash } from './content_hash.ts';
import type { DropboxClient } from './dropbox.ts';

export const CHUNK = 8 * 1024 * 1024;
export type UploadState = { session_id: string; offset: number; size: number; blocks: string[] };
export type ReadChunk = (offset: number, length: number) => Promise<Uint8Array>;
export type UploadResult = { done: true; hash: string; chunks: number; retries: number } | { done: false; state: UploadState; chunks: number; retries: number };

const sleepMs = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));
const retryable = (s: number) => s === 429 || s >= 500;

// One Dropbox call with up to `tries` attempts. Throws with the status and body on a final failure,
// so the caller's error text is what the IT engineer classifies.
async function send(dbx: DropboxClient, endpoint: string, arg: unknown, bytes: Uint8Array, counter: { retries: number },
                    sleep: (ms: number) => Promise<void>, tries = 3): Promise<Response> {
  for (let i = 1; ; i++) {
    let r: Response | null = null; let err = '';
    try { r = await dbx.call('content', endpoint, arg, bytes); } catch (e) { err = String((e as Error)?.message || e); if (err === 'no_dropbox_auth') throw e; }
    if (r && !retryable(r.status)) return r;
    if (i >= tries) throw new Error(`${endpoint} ${r ? r.status + ' ' + (await r.text()).slice(0, 160) : 'network ' + err.slice(0, 160)} after ${tries} tries`);
    if (r) await r.body?.cancel();
    counter.retries++;
    await sleep(1000 * 2 ** (i - 1));
  }
}

export async function uploadFile(dbx: DropboxClient, dest: string, size: number, read: ReadChunk,
  opts: { state?: UploadState | null; deadline?: number; maxChunks?: number; sleep?: (ms: number) => Promise<void> } = {}): Promise<UploadResult> {
  const sleep = opts.sleep ?? sleepMs; const counter = { retries: 0 };
  const commit = { path: dest, mode: 'overwrite', autorename: false, mute: true, strict_conflict: false };

  if (size <= CHUNK && !opts.state) {
    const bytes = await read(0, size);
    if (bytes.length !== size) throw new Error(`read ${bytes.length} of ${size} bytes`);
    const r = await send(dbx, 'files/upload', commit, bytes, counter, sleep);
    if (!r.ok) throw new Error('dbx_upload ' + r.status + ' ' + (await r.text()).slice(0, 200));
    await r.body?.cancel();
    return { done: true, hash: await dropboxContentHash(bytes), chunks: 1, retries: counter.retries };
  }

  let st = opts.state ?? null; let chunks = 0;
  if (st && st.size !== size) throw new Error(`resume state is for ${st.size} bytes, the file is ${size}`);
  const hasher = new DropboxHasher(st?.blocks ?? []);
  if (!st) {
    const r = await send(dbx, 'files/upload_session/start', { close: false }, new Uint8Array(0), counter, sleep);
    if (!r.ok) throw new Error('session_start ' + r.status + ' ' + (await r.text()).slice(0, 160));
    st = { session_id: String((await r.json()).session_id), offset: 0, size, blocks: [] };
  }
  while (st.offset < size) {
    // The deadline is the run's wall clock; maxChunks lets the self-test stop a real upload mid-file.
    if ((opts.deadline !== undefined && Date.now() >= opts.deadline) || (opts.maxChunks !== undefined && chunks >= opts.maxChunks)) {
      return { done: false, state: { ...st, blocks: hasher.blockHexes() }, chunks, retries: counter.retries };
    }
    const len = Math.min(CHUNK, size - st.offset);
    const buf = await read(st.offset, len);
    if (buf.length !== len) throw new Error(`read ${buf.length} of ${len} bytes at ${st.offset}`);
    const r = await send(dbx, 'files/upload_session/append_v2', { cursor: { session_id: st.session_id, offset: st.offset }, close: false }, buf, counter, sleep);
    if (!r.ok) {
      const t = await r.text();
      const correct = r.status === 409 ? Number(JSON.parse(t || '{}')?.error?.correct_offset) : NaN;
      if (correct !== st.offset + len) throw new Error('append ' + r.status + ' ' + t.slice(0, 160));
      counter.retries++;
    } else await r.body?.cancel();
    await hasher.update(buf);
    st.offset += len; chunks++;
  }
  const r = await send(dbx, 'files/upload_session/finish', { cursor: { session_id: st.session_id, offset: size }, commit }, new Uint8Array(0), counter, sleep);
  if (!r.ok) throw new Error('finish ' + r.status + ' ' + (await r.text()).slice(0, 160));
  await r.body?.cancel();
  return { done: true, hash: await hasher.hex(), chunks, retries: counter.retries };
}
