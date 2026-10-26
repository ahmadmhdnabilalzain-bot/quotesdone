// zip — the archive layer under every OOXML / ODF reader and the reader for a plain .zip upload.
//
// WHY. A .docx, .pptx, .xlsx, .odt and .ods are all zips, and a customer's "drawings.zip" is a zip of
// documents. Handing any of them to an inflater is handing it a decompression ratio: 16 MB of zeros
// deflates to about 16 KB (1,000:1). So the bill is read FIRST, from the central directory, which
// states every entry's size uncompressed, and the archive is refused before one byte is inflated.
//
// WHAT IT READS. The central directory (via attachment.ts zipExpansionWithinLimits for the entry
// count, total and ratio caps in LIMITS), then each entry's local header. Method 0 (stored) and 8
// (deflate, through the built-in DecompressionStream('deflate-raw')) only. Inflation is streamed and
// aborted the moment the output passes the caller's cap, whatever the directory claimed.
//
// WHAT IT NEVER DOES. It does not open ZIP64 archives, encrypted entries (general-purpose flag bit 0)
// or methods other than 0 and 8 — each is refused or noted, never guessed at. It does not extract to
// disk, follow paths, or nest past LIMITS.maxDepth. CRCs are not verified: a corrupt entry yields
// garbage text for that one entry, not a crash, and the bytes are never executed.
import { zipExpansionWithinLimits } from '../attachment.ts';
import { empty, LIMITS, ok, refuse, type ReadContext, type ReadResult, type Refusal } from './types.ts';

export type ZipEntry = { name: string; method: number; flags: number; compressedSize: number; size: number; localOffset: number };

const u16 = (b: Uint8Array, at: number) => b[at] | (b[at + 1] << 8);
const u32 = (b: Uint8Array, at: number) => (b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)) >>> 0;
const utf8 = new TextDecoder('utf-8');

/** Every entry the central directory lists, or a refusal (bomb, zip64, encrypted, unreadable). */
export function listZip(b: Uint8Array): { ok: true; entries: ZipEntry[] } | Refusal {
  const v = zipExpansionWithinLimits(b, { maxEntries: LIMITS.maxZipEntries, maxTotalBytes: LIMITS.maxZipTotalBytes, maxRatio: LIMITS.maxZipRatio });
  if (!v.ok) return refuse(v.error, v.detail);
  let eocd = -1;
  for (let i = b.length - 22; i >= Math.max(0, b.length - 65557); i--) {
    if (b[i] === 0x50 && b[i + 1] === 0x4b && b[i + 2] === 0x05 && b[i + 3] === 0x06) { eocd = i; break; }
  }
  const count = u16(b, eocd + 10);
  const entries: ZipEntry[] = [];
  for (let at = u32(b, eocd + 16), k = 0; k < count; k++) {
    const nlen = u16(b, at + 28);
    const name = utf8.decode(b.subarray(at + 46, at + 46 + nlen));
    const e: ZipEntry = { name, flags: u16(b, at + 8), method: u16(b, at + 10), compressedSize: u32(b, at + 20), size: u32(b, at + 24), localOffset: u32(b, at + 42) };
    if (e.compressedSize === 0xffffffff || e.size === 0xffffffff || e.localOffset === 0xffffffff) {
      return refuse('zip_unreadable', `entry ${name} uses ZIP64 sizes; this reader does not accept ZIP64`);
    }
    if (e.flags & 1) return refuse('encrypted', `entry ${name} is password-protected; the archive cannot be read without the password`);
    entries.push(e);
    at += 46 + nlen + u16(b, at + 30) + u16(b, at + 32);
  }
  return { ok: true, entries };
}

/** One entry's bytes. Throws past `maxOut` output bytes (declared OR actual), on a bad header or an unknown method. */
export async function readZipEntry(b: Uint8Array, e: ZipEntry, maxOut: number): Promise<Uint8Array> {
  if (e.size > maxOut) throw new Error(`entry ${e.name} declares ${e.size} bytes, over the ${maxOut} cap`);
  const at = e.localOffset;
  if (u32(b, at) !== 0x04034b50) throw new Error(`entry ${e.name} has no local header`);
  const start = at + 30 + u16(b, at + 26) + u16(b, at + 28);
  const data = b.slice(start, start + e.compressedSize);
  if (data.length !== e.compressedSize) throw new Error(`entry ${e.name} is truncated`);
  if (e.method === 0) return data;
  if (e.method !== 8) throw new Error(`entry ${e.name} uses compression method ${e.method}; only stored and deflate are read`);
  const ds = new DecompressionStream('deflate-raw');
  const w = ds.writable.getWriter();
  w.write(data).catch(() => {});
  w.close().catch(() => {});
  const r = ds.readable.getReader();
  const chunks: Uint8Array[] = [];
  let n = 0;
  for (;;) {
    const { done, value } = await r.read();
    if (done) break;
    n += value.length;
    if (n > maxOut) { await r.cancel().catch(() => {}); throw new Error(`entry ${e.name} inflates past the ${maxOut} byte cap`); }
    chunks.push(value);
  }
  const out = new Uint8Array(n);
  let o = 0; for (const c of chunks) { out.set(c, o); o += c.length; }
  return out;
}

/** A .zip upload: every document inside, each read by the dispatcher one level deeper. */
export async function readZip(bytes: Uint8Array, ctx: ReadContext): Promise<ReadResult> {
  if (ctx.depth >= LIMITS.maxDepth) return refuse('too_deep', `archive nested ${ctx.depth} levels deep; the limit is ${LIMITS.maxDepth}`);
  const l = listZip(bytes);
  if (!l.ok) return l;
  const doc = empty('zip');
  const names: string[] = [];
  for (const e of l.entries) {
    const base = e.name.split('/').pop() ?? '';
    if (e.name.endsWith('/') || e.name.startsWith('__MACOSX/') || base.startsWith('.')) continue;
    names.push(e.name);
    if (e.size > LIMITS.maxEntryBytes) { doc.notes.push(`${e.name}: ${e.size} bytes is over the ${LIMITS.maxEntryBytes} byte entry cap; not read`); continue; }
    if (!ctx.readChild) { doc.notes.push(`${e.name}: listed, not read (no reader supplied)`); continue; }
    try {
      const r = await ctx.readChild(await readZipEntry(bytes, e, LIMITS.maxEntryBytes), e.name, ctx.depth + 1);
      if (r.ok) { const { ok: _ok, ...child } = r; doc.children.push({ name: e.name, doc: child }); }
      else doc.notes.push(`${e.name}: ${r.error} — ${r.detail}`);
    } catch (err) {
      doc.notes.push(`${e.name}: ${(err as Error).message}`);
    }
  }
  doc.text = names.join('\n');
  return ok(doc);
}
