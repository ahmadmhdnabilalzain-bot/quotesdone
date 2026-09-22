// dwg_samples.check — REAL DWG files through readDwg, checked against the ASCII DXF of the same drawing.
//
// The recurrence check for "a DWG is pictured, not read" (founder instructions 31, 63, 64; 22 Sep 2026).
// If DWG reading breaks — the WASM URL or checksum, the LibreDWG JSON shape, the DWG closed-flag mapping,
// radians vs degrees — the DWG take-off stops matching the DXF take-off and this fails.
//
// The drawings are LibreDWG's own test data (GPL-3.0 repository, provenance not stated upstream), so they
// are FETCHED at a pinned commit and checked by hash, never committed here. That needs the network, which
// the `npm test` Deno suite deliberately does not grant, so it is not a *.test.ts: .github/workflows/
// checks.yml runs it as its own step with --allow-net limited to the two hosts it reads.
//
//   deno test --no-lock --node-modules-dir=auto --allow-read=. \
//     --allow-net=raw.githubusercontent.com,cdn.jsdelivr.net supabase/functions/_shared/doc_read/dwg_samples.check.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readDwg } from './dwg.ts';
import { readDxf } from './cad.ts';
import type { Extracted, ReadResult } from './types.ts';

const BASE = 'https://raw.githubusercontent.com/LibreDWG/libredwg/34f02f54b9aacb5708c1d3d2070efb3e4b2d8c43/test/test-data/';
// name: [sha256 prefix of .dwg, of .dxf, entities LibreDWG returns]
const SAMPLES: Record<string, [string, string, number]> = {
  sample_2000: ['4b8d9b1396a6d0de', '4b81b4de8331c808', 6],
  sample_2018: ['cbbac87415e5fc90', '9618b5cef57867be', 6],
  example_r14: ['aec626c5680584c7', 'b5db43eb376b8e6a', 67],
  example_2000: ['34574244d7556d1e', '43284cbdddbeb872', 67],
  example_2004: ['e72d5e86d5d36d64', '4689329440cd8d3c', 67],
  example_2007: ['fe2d27229f67ae80', 'c51b813e30c56860', 67],
  example_2010: ['457fb3d06cacd16d', 'fcd9ce4b2cf58c5b', 67],
  example_2013: ['ce80953e4881899c', '951f7910d1ea8ccc', 67],
  example_2018: ['7bc7721224003062', 'e64b0cfb6e1587f9', 67],
};
// KNOWN LIBREDWG DEFECT (measured 22 Sep 2026): in the R14 and 2000 editions the closed 3D polyline on
// the third layer comes back with 3 of its 4 vertices. Pinned, so a fix upstream (or a new loss) shows.
const SHORT: Record<string, Record<string, number>> = {
  example_r14: { 'layer TAVOLO_3 sqm': 0.95, 'layer TAVOLO_3 m': 0.43 },
  example_2000: { 'layer Tavolo 3 sqm': 0.95, 'layer Tavolo 3 m': 0.43 },
};

const good = (r: ReadResult): Extracted => { if (!r.ok) throw new Error(`${r.error}: ${r.detail}`); return r; };
async function get(name: string, sha: string): Promise<Uint8Array> {
  const r = await fetch(BASE + name);
  assert(r.ok, `${name}: HTTP ${r.status}`);
  const b = new Uint8Array(await r.arrayBuffer());
  const h = [...new Uint8Array(await crypto.subtle.digest('SHA-256', b))].map((x) => x.toString(16).padStart(2, '0')).join('');
  assertEquals(h.slice(0, 16), sha, `${name} is not the pinned file`);
  return b;
}
const byKey = (e: Extracted) => new Map(e.quantities.map((x) => [`${x.section} ${x.unit}`, x.qty ?? 0]));

for (const [name, [dwgSha, dxfSha, entities]] of Object.entries(SAMPLES)) {
  Deno.test(`${name}.dwg is read, and its take-off matches its own DXF`, async () => {
    const ctx = { filename: name + '.dwg', depth: 0 };
    const dwg = good(await readDwg(await get(name + '.dwg', dwgSha), ctx));
    const dxf = good(await readDxf(await get(name + '.dxf', dxfSha), ctx));
    assertEquals([dwg.kind, dwg.needs], ['dwg', null], dwg.notes.join(' | '));
    assert(dwg.notes[0].includes(`${entities} entities`), dwg.notes[0]);
    const a = byKey(dwg), b = byKey(dxf);
    assertEquals([...a.keys()].sort(), [...b.keys()].sort());
    for (const [k, want] of b) {
      const short = SHORT[name]?.[k] ?? 0;
      assertEquals(+(want - a.get(k)!).toFixed(2), short, `${name} ${k}: DWG ${a.get(k)} vs DXF ${want}`);
    }
    assert(dwg.quantities.length > 0 && dwg.text.length > 0);
  });
}

Deno.test('example_2018: the absolute figures a QS would read', async () => {
  const e = good(await readDwg(await get('example_2018.dwg', SAMPLES.example_2018[0]), { filename: 'x.dwg', depth: 0 }));
  const m = byKey(e);
  assertEquals(e.quantities.filter((x) => x.unit === 'nos').map((x) => `${x.description}=${x.qty}`), ['block CIRKLO_PUNKTOJ=8', 'block bloko=2']);
  assertEquals([m.get('layer Tavolo 3 sqm'), m.get('layer Tavolo 3 m'), m.get('layer Tavolo 2 m')], [129.36, 80.56, 12.64]);
  assert(e.notes.some((n) => n.includes('SPLINE x2')), 'unmeasured kinds are named');
});
