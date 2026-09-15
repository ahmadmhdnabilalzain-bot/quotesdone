// deno test supabase/functions/dropbox_backup/upload.test.ts
// A synthetic 3.1-chunk file against a fake Dropbox that fails one chunk with a 503, loses the answer
// to another (409 incorrect_offset at the right place), and a deadline that stops the run mid-file.
// The resumed run must finish, the bytes Dropbox assembled must equal the source, and the hash must
// equal Dropbox's content_hash of the whole file.
import { assertEquals, assert, assertRejects } from 'jsr:@std/assert@1';
import { DropboxClient } from './dropbox.ts';
import { dropboxContentHash } from './content_hash.ts';
import { CHUNK, uploadFile } from './upload.ts';

function fakeDropbox() {
  const sessions = new Map<string, Uint8Array[]>();
  const files = new Map<string, Uint8Array>();
  let appends = 0; const faults = { fail503At: 2, lostAnswerAt: 3 };
  const f = async (url: string, init: RequestInit): Promise<Response> => {
    const ep = url.split('/2/')[1];
    const arg = JSON.parse(String((init.headers as Record<string, string>)['Dropbox-API-Arg'] || 'null'));
    const body = new Uint8Array((init.body as Uint8Array) ?? new Uint8Array(0));
    if (ep === 'files/upload_session/start') { const id = 'S' + sessions.size; sessions.set(id, []); return Response.json({ session_id: id }); }
    if (ep === 'files/upload_session/append_v2') {
      appends++;
      if (appends === faults.fail503At) return new Response('busy', { status: 503 });
      const parts = sessions.get(arg.cursor.session_id)!; const have = parts.reduce((n, p) => n + p.length, 0);
      if (arg.cursor.offset !== have) return Response.json({ error: { '.tag': 'incorrect_offset', correct_offset: have } }, { status: 409 });
      parts.push(body);
      if (appends === faults.lostAnswerAt) return Response.json({ error: { '.tag': 'incorrect_offset', correct_offset: have + body.length } }, { status: 409 });
      return new Response(null, { status: 200 });
    }
    if (ep === 'files/upload_session/finish') {
      const parts = sessions.get(arg.cursor.session_id)!; const all = new Uint8Array(arg.cursor.offset); let o = 0;
      for (const p of parts) { all.set(p, o); o += p.length; }
      files.set(arg.commit.path, all); return Response.json({ size: all.length });
    }
    if (ep === 'files/upload') { files.set(arg.path, body); return Response.json({ size: body.length }); }
    return new Response('unknown ' + ep, { status: 400 });
  };
  return { f, files };
}

const SIZE = 3 * CHUNK + 123_457;
const src = new Uint8Array(SIZE); for (let i = 0; i < SIZE; i++) src[i] = (i * 31 + (i >> 13)) & 255;
const read = (o: number, n: number) => Promise.resolve(src.slice(o, o + n));
const noSleep = () => Promise.resolve();

Deno.test('a large file survives a failed chunk, a lost answer and a stopped run', async () => {
  const fake = fakeDropbox();
  const dbx = new DropboxClient({ token: () => Promise.resolve('T'), refreshes: 0, reused: 0 }, fake.f);
  const first = await uploadFile(dbx, '/QuotesDone Backup/_selftest/big.bin', SIZE, read, { maxChunks: 2, sleep: noSleep });
  assert(!first.done, 'the first run must stop mid-file');
  if (first.done) return;
  assertEquals(first.state.offset, 2 * CHUNK);
  const second = await uploadFile(dbx, '/QuotesDone Backup/_selftest/big.bin', SIZE, read, { state: JSON.parse(JSON.stringify(first.state)), sleep: noSleep });
  assert(second.done);
  if (!second.done) return;
  assertEquals(fake.files.get('/QuotesDone Backup/_selftest/big.bin'), src);
  assertEquals(second.hash, await dropboxContentHash(src));
  assertEquals(first.retries + second.retries, 2, 'one 503 retry and one lost answer');
});

Deno.test('a small file is one upload with the right hash', async () => {
  const fake = fakeDropbox(); const dbx = new DropboxClient({ token: () => Promise.resolve('T'), refreshes: 0, reused: 0 }, fake.f);
  const r = await uploadFile(dbx, '/x/مستند 🏗️.pdf', 1000, read);
  assert(r.done);
  if (r.done) assertEquals(r.hash, await dropboxContentHash(src.slice(0, 1000)));
});

Deno.test('resume state for a different size is refused', async () => {
  const fake = fakeDropbox(); const dbx = new DropboxClient({ token: () => Promise.resolve('T'), refreshes: 0, reused: 0 }, fake.f);
  await assertRejects(() => uploadFile(dbx, '/x', SIZE, read, { state: { session_id: 'S0', offset: CHUNK, size: SIZE + 1, blocks: [] } }));
});
