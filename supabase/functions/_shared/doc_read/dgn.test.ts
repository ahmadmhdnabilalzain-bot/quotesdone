// dgn.test — version sniffing on synthetic bytes; QD_DGN_SAMPLES=1 also checks GDAL's real samples.
import { assertEquals } from 'jsr:@std/assert@1';
import { dgnVersion, isDgnV8 } from './dgn.ts';

/** An OLE2 file whose first directory sector (512-byte sectors) is `dirSector`, holding one entry `name`. */
function ole(name: string, dirSector: number, size = (dirSector + 2) * 512): Uint8Array {
  const b = new Uint8Array(size);
  b.set([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
  b[30] = 9;                                            // sector shift: 512
  new DataView(b.buffer).setUint32(48, dirSector, true);
  const o = (dirSector + 1) * 512 + 128;                // second slot (the first is Root Entry)
  for (let i = 0; i < name.length; i++) b[o + i * 2] = name.charCodeAt(i);
  b[o + 64] = (name.length + 1) * 2;
  return b;
}

Deno.test('v7 2D and 3D are told apart by the control-block header', () => {
  assertEquals(dgnVersion(new Uint8Array([0x08, 0x09, 0xfe, 0x02, 0, 0])), 'v7-2d');
  assertEquals(dgnVersion(new Uint8Array([0xc8, 0x09, 0xfe, 0x02, 0, 0])), 'v7-3d');
  assertEquals(dgnVersion(new Uint8Array([0x08, 0x05, 0x17, 0x00])), null); // cell library, not a drawing
});

Deno.test('v8 is found by its Dgn storage, near the start or past 64 KB via the header', () => {
  assertEquals(dgnVersion(ole('Dgn~H', 3)), 'v8');
  assertEquals(isDgnV8(ole('Dgn^Ix', 200)), true);      // directory at ~100 KB: found through the header
});

Deno.test('other OLE files, truncated and random bytes are not DGN', () => {
  assertEquals(isDgnV8(ole('WordDocument', 3)), false);
  assertEquals(isDgnV8(ole('Dgn', 3)), false);          // "Dgn" alone is not a Bentley storage name
  assertEquals(isDgnV8(ole('Dgn~H', 3).subarray(0, 600)), false);
  assertEquals(dgnVersion(new Uint8Array(0)), null);
  const r = new Uint8Array(4096); crypto.getRandomValues(r);
  r.set([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
  new DataView(r.buffer).setUint32(48, 0xffffffff, true); // directory sector past any buffer
  assertEquals(typeof isDgnV8(r), 'boolean');
});

Deno.test({
  name: 'real samples from GDAL autotest (QD_DGN_SAMPLES=1)',
  // The suite runs with env access to three names only (scripts/checks/run.mjs): no access = skip.
  ignore: (() => { try { return Deno.env.get('QD_DGN_SAMPLES') !== '1'; } catch { return true; } })(),
  fn: async () => {
    const B = 'https://raw.githubusercontent.com/OSGeo/gdal/master';
    const cases: [string, string][] = [
      ['autotest/ogr/data/dgn/smalltest.dgn', 'v7-2d'],
      ['ogr/ogrsf_frmts/dgn/data/seed_2d.dgn', 'v7-2d'],
      ['ogr/ogrsf_frmts/dgn/data/seed_3d.dgn', 'v7-3d'],
      ['autotest/ogr/data/dgnv8/test_dgnv8.dgn', 'v8'],
    ];
    for (const [p, want] of cases) {
      const r = await fetch(`${B}/${p}`);
      const b = new Uint8Array(await r.arrayBuffer());
      assertEquals([p, dgnVersion(b)], [p, want]);
    }
  },
});
