// deno test supabase/functions/dropbox_backup/content_hash_test.ts
import { DropboxHasher, dropboxContentHash } from './content_hash.ts';

const hex = (b: ArrayBuffer) => Array.from(new Uint8Array(b), (x) => x.toString(16).padStart(2, '0')).join('');
const eq = (a: string, b: string, m: string) => { if (a !== b) throw new Error(`${m}: ${a} != ${b}`); };

Deno.test('empty file is sha256 of nothing (Dropbox documented value)', async () => {
  eq(await dropboxContentHash(new Uint8Array(0)), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'empty');
});

Deno.test('one block is sha256(sha256(data))', async () => {
  const d = new TextEncoder().encode('quotesdone');
  eq(await dropboxContentHash(d), hex(await crypto.subtle.digest('SHA-256', await crypto.subtle.digest('SHA-256', d))), 'single');
});

Deno.test('streaming in odd chunks across block edges equals one shot', async () => {
  const d = new Uint8Array(9 * 1024 * 1024 + 123);
  for (let i = 0; i < d.length; i++) d[i] = (i * 31 + 7) & 255;
  const h = new DropboxHasher();
  for (let off = 0; off < d.length; off += 3_000_001) await h.update(d.subarray(off, off + 3_000_001));
  eq(await h.hex(), await dropboxContentHash(d), 'stream');
});
