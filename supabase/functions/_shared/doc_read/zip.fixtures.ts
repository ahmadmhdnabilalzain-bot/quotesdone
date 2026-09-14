// zip.fixtures — an in-memory zip WRITER for doc_read tests and the before/after audit. Never touches disk.
// Entries are deflated with the built-in CompressionStream('deflate-raw') unless `store` is set;
// `flags` lets a fixture set general-purpose bits (bit 0 = encrypted) to exercise the refusals.
export type FixtureEntry = { name: string; data: string | Uint8Array; store?: boolean; flags?: number };

const CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; }
  return t;
})();
export function crc32(b: Uint8Array): number {
  let c = 0xffffffff;
  for (const x of b) c = CRC[(c ^ x) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

export async function deflateRaw(b: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await new Response(new Blob([new Uint8Array(b)]).stream().pipeThrough(new CompressionStream('deflate-raw'))).arrayBuffer());
}

export async function zipFixture(entries: FixtureEntry[]): Promise<Uint8Array> {
  const enc = new TextEncoder();
  const locals: Uint8Array[] = [], centrals: Uint8Array[] = [];
  let offset = 0;
  for (const e of entries) {
    const raw = typeof e.data === 'string' ? enc.encode(e.data) : e.data;
    const body = e.store ? raw : await deflateRaw(raw);
    const name = enc.encode(e.name);
    const flags = (e.flags ?? 0) | 0x800, method = e.store ? 0 : 8, crc = crc32(raw);
    const lh = new DataView(new ArrayBuffer(30));
    lh.setUint32(0, 0x04034b50, true); lh.setUint16(4, 20, true); lh.setUint16(6, flags, true); lh.setUint16(8, method, true);
    lh.setUint32(14, crc, true); lh.setUint32(18, body.length, true); lh.setUint32(22, raw.length, true); lh.setUint16(26, name.length, true);
    const ch = new DataView(new ArrayBuffer(46));
    ch.setUint32(0, 0x02014b50, true); ch.setUint16(4, 20, true); ch.setUint16(6, 20, true); ch.setUint16(8, flags, true); ch.setUint16(10, method, true);
    ch.setUint32(16, crc, true); ch.setUint32(20, body.length, true); ch.setUint32(24, raw.length, true); ch.setUint16(28, name.length, true);
    ch.setUint32(42, offset, true);
    locals.push(new Uint8Array(lh.buffer), name, body);
    centrals.push(new Uint8Array(ch.buffer), name);
    offset += 30 + name.length + body.length;
  }
  const cdSize = centrals.reduce((n, c) => n + c.length, 0);
  const eocd = new DataView(new ArrayBuffer(22));
  eocd.setUint32(0, 0x06054b50, true); eocd.setUint16(8, entries.length, true); eocd.setUint16(10, entries.length, true);
  eocd.setUint32(12, cdSize, true); eocd.setUint32(16, offset, true);
  const parts = [...locals, ...centrals, new Uint8Array(eocd.buffer)];
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0; for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}

/** 16 MB of zeros deflated to ~16 KB: a ~1,000:1 ratio against the 120:1 cap. */
export const zipBombFixture = () => zipFixture([{ name: 'boq.txt', data: new Uint8Array(16 * 1024 * 1024) }]);

/** One entry with general-purpose flag bit 0 set, as a password-protected zip writes it. */
export const encryptedZipFixture = () => zipFixture([{ name: 'boq.txt', data: 'Porcelain tiles 600x600  120 sqm', flags: 1 }]);
