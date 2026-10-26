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
import { lastWasmHeapBytes, lowerMemoryFloor, readDwg, WASM_MIN_PAGES } from './dwg.ts';
import { readDxf } from './cad.ts';
import { readStored } from '../../../../scripts/cad_read_worker.ts';
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

// THE 1 GB MEMORY FLOOR (22 Sep 2026). On production every DWG died "Memory limit exceeded": the pinned
// .wasm declares a 16,384-page (1 GB) minimum. dwg.ts lowers it before compiling. This fails if the
// pinned build stops carrying that floor in the shape lowerMemoryFloor rewrites, or if reading the
// 67-entity drawing needs more than 64 MB of WASM heap (measured: 16-46 MB for the LibreDWG samples, 99 MB
// for the 2.1 MB Dynblocks.dwg, dev machine).
Deno.test('the pinned LibreDWG wasm asks for 1 GB, is lowered to 16 MB, and reads within 64 MB', async () => {
  const bin = new Uint8Array(await (await fetch('https://cdn.jsdelivr.net/npm/@mlightcad/libredwg-web@0.7.14/wasm/libredwg-web.wasm')).arrayBuffer());
  assertEquals(lowerMemoryFloor(bin), { from: 16384, to: WASM_MIN_PAGES });
  good(await readDwg(await get('example_2018.dwg', SAMPLES.example_2018[0]), { filename: 'x.dwg', depth: 0 }));
  const heap = lastWasmHeapBytes();
  assert(heap > 0 && heap <= 64 * 1048576, `WASM heap ${heap} bytes`);
});

// A DWG OF ANY SIZE (22 Sep 2026). 2018/Dynblocks.dwg (2.1 MB) is past the edge ceiling: the edge answers
// cad_conversion (and customer_api queues it), and the CAD worker's reader reads it in full.
Deno.test('a DWG past the edge ceiling is queued by the edge and read by the CAD worker', async () => {
  const b = await get('2018/Dynblocks.dwg', '95cc558d02a2596d');
  const edge = good(await readDwg(b, { filename: 'x.dwg', depth: 0 }));
  assertEquals([edge.kind, edge.needs], ['dwg', 'cad_conversion']);
  const w = good(await readStored(b, 'x.dwg'));
  assertEquals([w.kind, w.needs], ['dwg', null]);
  assertEquals(w.notes[0], 'Read from DWG (AutoCAD 2018) by LibreDWG: 121 entities.');
  assertEquals(w.quantities.length, 62);
});

// BINARY DXF (22 Sep 2026). LibreDWG's test-data carries the same drawing as binary DXF. example_2000.dxfb
// is read to the SAME take-off and text as the AutoCAD ASCII DXF. example_2018.dxfb is a smaller file:
// it holds 43 of the drawing's 89 ENTITIES records (counted in the file itself, which ends in EOF), so
// its take-off is pinned to what the file holds, not to the ASCII one.
Deno.test('binary DXF: example_2000.dxfb reads exactly as its ASCII DXF', async () => {
  const ctx = { filename: 'x.dxf', depth: 0 };
  const bin = good(await readDxf(await get('example_2000.dxfb', '6630c1c66c5b0713'), ctx));
  const asc = good(await readDxf(await get('example_2000.dxf', SAMPLES.example_2000[1]), ctx));
  assertEquals([...byKey(bin)], [...byKey(asc)]);
  assertEquals(bin.text, asc.text);
  assert(bin.notes[0].startsWith('Read from binary DXF: '), bin.notes[0]);
});

Deno.test('binary DXF: example_2018.dxfb is read to its end', async () => {
  const e = good(await readDxf(await get('example_2018.dxfb', '55505256328ff9bf'), { filename: 'x.dxf', depth: 0 }));
  const m = byKey(e);
  assertEquals([m.get('layer Tavolo 3 sqm'), m.get('layer Tavolo 3 m'), m.get('layer Tavolo 2 m')], [126.6, 65.32, 12.64]);
  assertEquals(e.notes[0], 'Read from binary DXF: 7650 group-code pairs.');
});
