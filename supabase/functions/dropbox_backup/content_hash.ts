// Dropbox content_hash, computed locally so an upload can be CONFIRMED rather than assumed.
// Dropbox's definition: split the file into 4 MiB blocks, SHA-256 each block, concatenate the
// binary digests, SHA-256 that, hex. Fed incrementally, so an upload session can hash while it
// streams without holding the whole file.
const BLOCK = 4 * 1024 * 1024;

export class DropboxHasher {
  private digests: Uint8Array[] = [];
  private buf = new Uint8Array(BLOCK);
  private fill = 0;

  async update(data: Uint8Array): Promise<void> {
    let off = 0;
    while (off < data.length) {
      const n = Math.min(BLOCK - this.fill, data.length - off);
      this.buf.set(data.subarray(off, off + n), this.fill);
      this.fill += n; off += n;
      if (this.fill === BLOCK) await this.flush();
    }
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
    const h = new Uint8Array(await crypto.subtle.digest('SHA-256', all));
    return Array.from(h, (b) => b.toString(16).padStart(2, '0')).join('');
  }
}

export async function dropboxContentHash(data: Uint8Array): Promise<string> {
  const h = new DropboxHasher(); await h.update(data); return h.hex();
}
