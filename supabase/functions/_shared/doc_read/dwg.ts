// dwg — a DWG drawing READ, not pictured: its entities go through the same take-off as an ASCII DXF (22 Sep 2026).
//
// WHY. Founder instructions 31, 63 and 64: read every drawing format to the OpenConstructionERP bar,
// real quantity take-off from DWG, not images. Until today a DWG came back needs:'cad_conversion' and
// the only "conversion" was cad_convert, which rasterises the sheet on CloudConvert and reads nothing.
//
// HOW. LibreDWG (GNU, GPL-3.0-or-later) compiled to WebAssembly by @mlightcad/libredwg-web 0.7.14
// (GPL-3.0) opens the DWG and returns its entities as JSON. dwgToDxf() writes the entity kinds the DXF
// reader measures back out as ASCII DXF group codes, and readDxf() (cad.ts) does the take-off. There is
// ONE take-off; a DWG and a DXF of the same plan cannot disagree because of two measuring codes.
//
// LICENCE. The WASM runs server-side only. GPL-3 obligations attach to DISTRIBUTING the program; running
// it in an edge function distributes nothing. It must NOT be bundled into anything shipped to a browser
// or an app. The .wasm (9.5 MB) is not in the function bundle: it is fetched once per isolate from
// jsDelivr's npm mirror and refused unless its SHA-256 matches the pinned value below.
//
// MEASURED 22 Sep 2026 on LibreDWG's own test drawings (test/test-data at 34f02f5, fetched at test time,
// never committed): the R14, 2000, 2004, 2007, 2013 and 2018 editions of the same drawing each gave the
// same 67 entities. Deno 2.9 on the dev machine, CPU time (the edge caps CPU at 2 s per request):
//   cold isolate, 20 KB DWG   ~550 ms   (fetch + SHA-256 + WASM compile is most of it)
//   cold isolate, 149 KB DWG  ~1,000 ms;   cold, 582 KB DWG ~1,100-1,500 ms;   warm, 150-580 KB 140-330 ms
//   process RSS 135-225 MB (Deno CLI, includes the runtime; the edge's 256 MB was not measured here).
// Against the AutoCAD-written ASCII DXF of the same drawing (also in test-data) the take-off is
// IDENTICAL for the 2004, 2007, 2010, 2013 and 2018 editions. KNOWN LIBREDWG DEFECT: in the R14 and 2000
// editions it returns the closed 3D polyline with 3 of its 4 vertices, so that layer reads 0.95 sqm and
// 0.43 m short. dwg_samples.check.ts pins both facts, so a LibreDWG upgrade that fixes or worsens it shows.
// So the edge reads DWGs up to DWG_MAX_BYTES and says what to do past it. scripts/dwg_takeoff.ts runs
// this same reader with no ceiling where there is no CPU cap (a CI worker, a laptop).
//
// WHAT IT NEVER DOES. SPLINE, ELLIPSE, HATCH, MLINE, 3D solids, tables and multileaders are counted by
// type in the notes, not measured. Blocks are not exploded (same as DXF). Identity is NOT scrubbed here.
import { readDxf } from './cad.ts';
import { empty, ok, refuse, type ReadContext, type ReadResult } from './types.ts';

const PKG = '@mlightcad/libredwg-web@0.7.14';
const WASM_URL = `https://cdn.jsdelivr.net/npm/${PKG}/wasm/libredwg-web.wasm`;
const WASM_SHA256 = '431576487027122a28e5ac99d91fe6366f81ecda743a4676878c75c85fe82c53';

/** DWG version stamp -> release name (the first six bytes of every DWG). */
const RELEASE: Record<string, string> = {
  AC1012: 'R13', AC1014: 'R14', AC1015: 'AutoCAD 2000', AC1018: 'AutoCAD 2004', AC1021: 'AutoCAD 2007',
  AC1024: 'AutoCAD 2010', AC1027: 'AutoCAD 2013', AC1032: 'AutoCAD 2018',
};

/**
 * Past this size a DWG is not opened in an edge function. The 2 s CPU cap kills the isolate silently
 * (no catch runs), so the ceiling is the largest file MEASURED to fit cold (582 KB at ~1.5 s), rounded
 * up a little, and the note says what to send instead. Raise it only with a measurement on the edge.
 */
export const DWG_MAX_BYTES = 640 * 1024;

type P = { x?: number; y?: number; z?: number };
// deno-lint-ignore no-explicit-any
type DwgEntity = Record<string, any> & { type: string; layer?: string };
export type DwgDb = { header?: Record<string, unknown>; entities: DwgEntity[] };

const RAD2DEG = 180 / Math.PI;
const oneLine = (s: unknown) => String(s ?? '').replace(/\r?\n/g, '\\P');

/**
 * LibreDWG's entity JSON -> ASCII DXF text, for the kinds readDxf measures. Angles arrive in radians
 * and leave in degrees (DXF). Everything else is returned by type in `skipped`, so the caller can say
 * exactly what was not measured.
 */
export function dwgToDxf(db: DwgDb): { dxf: string; skipped: Map<string, number> } {
  const out: string[] = [];
  const g = (c: number, v: unknown) => { out.push(String(c), String(v)); };
  const pt = (p: P | undefined, base = 10) => { g(base, p?.x ?? 0); g(base + 10, p?.y ?? 0); g(base + 20, p?.z ?? 0); };
  const skipped = new Map<string, number>();
  g(0, 'SECTION'); g(2, 'HEADER');
  const u = Number(db.header?.INSUNITS);
  if (Number.isFinite(u)) { g(9, '$INSUNITS'); g(70, u); }
  g(0, 'ENDSEC'); g(0, 'SECTION'); g(2, 'ENTITIES');
  for (const e of db.entities) {
    const head = (t: string) => { g(0, t); g(8, e.layer || '0'); };
    switch (e.type) {
      case 'LINE': head('LINE'); pt(e.startPoint, 10); pt(e.endPoint, 11); break;
      case 'CIRCLE': head('CIRCLE'); pt(e.center); g(40, e.radius ?? 0); break;
      case 'ARC':
        head('ARC'); pt(e.center); g(40, e.radius ?? 0);
        g(50, (e.startAngle ?? 0) * RAD2DEG); g(51, (e.endAngle ?? 0) * RAD2DEG); break;
      case 'LWPOLYLINE':
        // DWG stores an LWPOLYLINE's "closed" as flag bit 512; DXF writes it as bit 1 of code 70. Passing
        // the DWG flag through unchanged would read every closed room outline as open and lose its area
        // (and bit 1 in DWG means "has extrusion", so it would also close open ones).
        head('LWPOLYLINE'); g(70, (e.flag ?? 0) & 512 ? 1 : 0);
        for (const v of e.vertices ?? []) { g(10, v.x ?? 0); g(20, v.y ?? 0); if (v.bulge) g(42, v.bulge); }
        break;
      case 'POLYLINE2D': case 'POLYLINE3D':
        head('POLYLINE'); g(70, (e.flag ?? 0) & 1);
        for (const v of e.vertices ?? []) { g(0, 'VERTEX'); g(8, e.layer || '0'); pt(v); if (v.bulge) g(42, v.bulge); }
        g(0, 'SEQEND'); break;
      case 'INSERT': head('INSERT'); g(2, e.name ?? ''); pt(e.insertionPoint); break;
      case 'TEXT': head('TEXT'); g(1, oneLine(e.text)); break;
      case 'ATTRIB': head('ATTRIB'); g(1, oneLine(e.text?.text ?? e.text)); break;
      case 'MTEXT': head('MTEXT'); g(1, oneLine(e.text)); break;
      case 'DIMENSION': head('DIMENSION'); g(1, oneLine(e.text)); if (e.measurement) g(42, e.measurement); break; // R14 stores none (0)
      default: skipped.set(e.type, (skipped.get(e.type) ?? 0) + 1);
    }
  }
  g(0, 'ENDSEC'); g(0, 'EOF');
  return { dxf: out.join('\n') + '\n', skipped };
}

// ---- the WASM: compiled once per isolate, a FRESH instance per drawing ---------------------------------
// MEASURED 22 Sep 2026: one instance reused across drawings failed with "null function" on the second
// file (example_2013 then example_2010; each alone reads fine). LibreDWG keeps global state between
// reads. So the compiled module is cached (the ~9.5 MB compile is the expensive part) and every drawing
// gets its own instance and its own memory, which the garbage collector takes back afterwards.
// deno-lint-ignore no-explicit-any
let compiled: Promise<{ m: any; mod: WebAssembly.Module }> | null = null;
async function sha256Hex(b: Uint8Array<ArrayBuffer>): Promise<string> {
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', b));
  return [...h].map((x) => x.toString(16).padStart(2, '0')).join('');
}
// deno-lint-ignore no-explicit-any
async function freshLibreDwg(): Promise<any> {
  compiled ??= (async () => {
    const r = await fetch(WASM_URL);
    if (!r.ok) throw new Error(`libredwg wasm fetch ${r.status}`);
    const bin = new Uint8Array(await r.arrayBuffer());
    if (await sha256Hex(bin) !== WASM_SHA256) throw new Error('libredwg wasm checksum mismatch');
    // A string LITERAL, not built from PKG: the edge bundler only includes dynamic imports it can read
    // statically. Keep it equal to PKG (dwg.test.ts asserts they match).
    return { m: await import('npm:@mlightcad/libredwg-web@0.7.14'), mod: await WebAssembly.compile(bin) };
  })().catch((e) => { compiled = null; throw e; });
  const { m, mod } = await compiled;
  const inst = await m.createModule({
    // Emscripten's hook: hand over an instance of the already-compiled module instead of compiling again.
    // This build awaits the hook's return value as the exports, so it returns what `done` returns.
    instantiateWasm: (imports: WebAssembly.Imports, done: (i: WebAssembly.Instance, m: WebAssembly.Module) => unknown) =>
      WebAssembly.instantiate(mod, imports).then((i) => done(i, mod)),
  });
  return m.LibreDwg.createByWasmInstance(inst);
}

/** Customer-facing: these become the BOQ's missing_info. English here; the screens show them in Arabic through src/lib/boqNotes.ts. */
export const DWG_SEND_DXF = 'Save the drawing as DXF (File > Save As > AutoCAD DXF) or PDF and upload that.';

export async function readDwg(bytes: Uint8Array, ctx: ReadContext, maxBytes = DWG_MAX_BYTES): Promise<ReadResult> {
  const stamp = new TextDecoder('latin1').decode(bytes.subarray(0, 6));
  const release = RELEASE[stamp] ?? stamp;
  if (!/^AC10\d\d$/.test(stamp)) return refuse('dwg_unreadable', 'Not a DWG file (no AC10xx version stamp).');
  if (bytes.length > maxBytes) {
    return ok(empty('dwg', [`This DWG (${release}, ${Math.round(bytes.length / 1024)} KB) is larger than the ${Math.round(maxBytes / 1024)} KB read directly.`, DWG_SEND_DXF], 'cad_conversion'));
  }
  let db: DwgDb;
  try {
    const L = await freshLibreDwg();
    const data = L.dwg_read_data(bytes, 0 /* Dwg_File_Type.DWG */);
    if (!data) return refuse('dwg_unreadable', `LibreDWG could not open this ${release} file.`);
    try { db = L.convert(data); } finally { L.dwg_free(data); }
  } catch (e) {
    return ok(empty('dwg', [`The DWG reader could not run (${String((e as Error)?.message || e).slice(0, 120)}).`, DWG_SEND_DXF], 'cad_conversion'));
  }
  const { dxf, skipped } = dwgToDxf(db);
  const r = await readDxf(new TextEncoder().encode(dxf), ctx);
  if (!r.ok) return r;
  const notes = [`Read from DWG (${release}) by LibreDWG: ${db.entities.length} entities.`];
  if (skipped.size) notes.push(`Not measured (counted only): ${[...skipped].map(([t, n]) => `${t} x${n}`).join(', ')}.`);
  return ok({ ...r, kind: 'dwg', notes: [...notes, ...r.notes] });
}
