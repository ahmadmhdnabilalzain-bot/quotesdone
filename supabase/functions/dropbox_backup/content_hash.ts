// Dropbox content_hash, computed locally so an upload can be CONFIRMED rather than assumed.
// Dropbox's definition: split the file into 4 MiB blocks, SHA-256 each block, concatenate the
// binary digests, SHA-256 that, hex. Fed incrementally, so an upload session can hash while it
// streams without holding the whole file. A chunked upload that stops mid-file carries its block
// digests (blockHexes) to the next run, which resumes the hash with `new DropboxHasher(blocks)`.
export const BLOCK = 4 * 1024 * 1024;
const hex = (b: Uint8Array) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');

export class DropboxHasher {
  private digests: Uint8Array[];
  private buf = new Uint8Array(BLOCK);
  private fill = 0;

  constructor(blocks: string[] = []) {
    this.digests = blocks.map((h) => new Uint8Array(h.match(/../g)!.map((x) => parseInt(x, 16))));
  }

  async update(data: Uint8Array): Promise<void> {
    let off = 0;
    while (off < data.length) {
      const n = Math.min(BLOCK - this.fill, data.length - off);
      this.buf.set(data.subarray(off, off + n), this.fill);
      this.fill += n; off += n;
      if (this.fill === BLOCK) await this.flush();
    }
  }

  // Only meaningful on a block boundary: a partial block cannot be carried between runs.
  blockHexes(): string[] {
    if (this.fill !== 0) throw new Error('blockHexes: not on a 4 MiB boundary');
    return this.digests.map(hex);
  }

  private async flush(): Promise<void> {
    if (this.fill === 0) return;
    this.digests.push(new Uint8Array(await crypto.subtle.digest('SHA-256', this.buf.slice(0, this.fill))));
    this.fill = 0;
  }

  async hex(): Promise<string> {
    await this.flush();
    const all = new Uint8Array(this.digests.length * 32);
    this.digests.forEach((d, i) => all.set(d, i * 32));
    return hex(new Uint8Array(await crypto.subtle.digest('SHA-256', all)));
  }
}

export async function dropboxContentHash(data: Uint8Array): Promise<string> {
  const h = new DropboxHasher(); await h.update(data); return h.hex();
}
