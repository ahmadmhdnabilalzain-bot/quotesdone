// dgn — which MicroStation DGN a file is, so the caller can answer it honestly (22 Sep 2026).
//
// WHY. Founder instructions 31, 63, 64 and 696: every drawing format is read or answered truthfully.
// On 22 Sep DGN was set to MINIMAL: recognise the version, do not measure. A v7 (ISFF) reader is not
// built here; the caller says the file must be sent as DXF or PDF.
//
// HOW. v7 (ISFF): the first element is the type-9 design-file control block, so the file starts
// 08 09 FE 02 (2D) or C8 09 FE 02 (3D) — the same test as GDAL libdgn's DGNTestOpen (dgnopen.cpp,
// Frank Warmerdam, MIT). v8 is an OLE2 compound file (Bentley proprietary; only the Bentley/ODA SDKs
// read it): OLE2 magic, then a directory entry whose UTF-16LE name starts "Dgn" followed by ~ ^ or -.
// The entries are read at 128-byte slots in the header's first directory sector and in the first
// 64 KB, nothing else, so a hostile file costs at most ~70 KB of reading.
//
// MEASURED 22 Sep 2026 on GDAL's autotest/ogr/data/dgnv8/test_dgnv8.dgn (27,648 bytes, fetched, never
// committed): its first directory sector (sector 44, offset 23,040) holds Root Entry, Dgn^Ix, Dgn~Mix,
// Dgn-Md; the directory also holds Dgn~H, Dgn~S, Dgn~Mf, Dgn~Mh. GDAL's smalltest.dgn, seed_2d.dgn and
// DGNSample_v7.dgn start 08 09 FE 02; seed_3d.dgn starts C8 09 FE 02.
//
// WHAT IT NEVER DOES. It does not read geometry, text, levels or units from either version, and it
// does not treat a cell library (08 05 17 00) as a drawing.

const OLE_MAGIC = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];
const SCAN_BYTES = 64 * 1024;

/** One 128-byte OLE directory entry at `o`: is its name "Dgn~…", "Dgn^…" or "Dgn-…"? */
function dgnEntryAt(b: Uint8Array, o: number): boolean {
  if (o < 0 || o + 128 > b.length) return false;
  const len = b[o + 64] | (b[o + 65] << 8);            // name length in bytes, terminator included
  if (len < 10 || len > 64) return false;
  return b[o] === 0x44 && b[o + 1] === 0 && b[o + 2] === 0x67 && b[o + 3] === 0 && b[o + 4] === 0x6e && b[o + 5] === 0 &&
    (b[o + 6] === 0x7e || b[o + 6] === 0x5e || b[o + 6] === 0x2d) && b[o + 7] === 0;
}

/** A DGN v8 (OLE2 compound file with a Bentley "Dgn…" storage). */
export function isDgnV8(bytes: Uint8Array): boolean {
  if (bytes.length < 512 || OLE_MAGIC.some((m, i) => bytes[i] !== m)) return false;
  const shift = bytes[30] | (bytes[31] << 8);
  const sector = shift === 9 || shift === 12 ? 1 << shift : 512;
  const first = (bytes[48] | (bytes[49] << 8) | (bytes[50] << 16) | (bytes[51] << 24)) >>> 0;
  const dir = (first + 1) * sector;                    // sector n starts after the one-sector header
  if (first < 0xfffffffa && dir < bytes.length) {
    for (let o = dir; o < dir + sector; o += 128) if (dgnEntryAt(bytes, o)) return true;
  }
  for (let o = 512; o + 128 <= Math.min(bytes.length, SCAN_BYTES); o += 128) if (dgnEntryAt(bytes, o)) return true;
  return false;
}

/** 'v7-2d' | 'v7-3d' from the ISFF control-block header, 'v8' from the OLE2 directory, else null. */
export function dgnVersion(bytes: Uint8Array): 'v7-2d' | 'v7-3d' | 'v8' | null {
  if (bytes.length >= 4 && bytes[1] === 0x09 && bytes[2] === 0xfe && bytes[3] === 0x02) {
    if (bytes[0] === 0x08) return 'v7-2d';
    if (bytes[0] === 0xc8) return 'v7-3d';
  }
  return isDgnV8(bytes) ? 'v8' : null;
}
