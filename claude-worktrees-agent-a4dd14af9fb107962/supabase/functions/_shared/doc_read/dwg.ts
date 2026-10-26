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
// ON PRODUCTION NONE OF THIS RAN until 22 Sep 2026: see THE 1 GB MEMORY FLOOR below. The edge reads DWGs
// up to DWG_MAX_BYTES; past it, or when the edge worker dies, customer_api queues the drawing for
// scripts/cad_read_worker.ts, which runs this same reader with no ceiling (a GitHub runner, no CPU cap).
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
 * Past this size a DWG is not opened in an edge function; customer_api queues it for the CAD worker
 * (scripts/cad_read_worker.ts, no CPU cap), which runs this same reader with no ceiling. MEASURED 22 Sep
 * 2026, dev machine, cold isolate, process CPU (includes V8's compile threads): 1.4 MB / 5 entities
 * 0.45 s; 569 KB / 67 entities 0.80 s; 562 KB / 2,551 entities 1.9 s; 2.1 MB / 121 entities 2.7 s. Size
 * does not predict the cost - entities and objects do - so this ceiling is not what keeps the edge safe:
 * customer_api treats a worker that dies (546) exactly like a file over the ceiling and queues it. The
 * ceiling only spares a customer the wait for an edge attempt that is very likely to die.
 */
export const DWG_MAX_BYTES = 1536 * 1024;

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
  // The job's own names (22 Sep 2026): carried into the DXF text so cad_identity.ts can take them out of
  // the take-off. readDxf measures nothing from them.
  for (const k of ['PROJECTNAME', 'HYPERLINKBASE', 'LASTSAVEDBY']) {
    const v = String(db.header?.[k] ?? '').trim();
    if (v) { g(9, '$' + k); g(1, oneLine(v)); }
  }
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
      // The tag (CLIENT, PROJECT, DRAWN ...) is what tells cad_identity a value names a party.
      case 'ATTRIB': head('ATTRIB'); g(1, oneLine(e.text?.text ?? e.text)); if (e.tag) g(2, oneLine(e.tag)); break;
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
// ---- THE 1 GB MEMORY FLOOR (22 Sep 2026) ---------------------------------------------------------------
// MEASURED ON PRODUCTION, 22 Sep 2026: every DWG sent to the deployed drawing_boq — 22 KB, 183 KB, 408 KB,
// 569 KB — came back HTTP 546 WORKER_RESOURCE_LIMIT in 0.6-4.0 s, and the function log says "Memory limit
// exceeded". The same bytes read fine on a laptop, which is why #821 reported DWG as read. The cause is in
// the .wasm itself: its memory section declares a MINIMUM of 16,384 pages (Emscripten INITIAL_MEMORY=1GB),
// so instantiating it asks for 1 GB before a single byte of the drawing is read. A desktop reserves that
// lazily; the edge counts it and kills the worker. So NO DWG of any size was ever read on production.
// The build also carries memory GROWTH (its glue's growMemory calls wasmMemory.grow), so the floor is not
// needed: lowerMemoryFloor rewrites the minimum to WASM_MIN_PAGES in place — same LEB128 width, so no other
// byte moves — AFTER the pinned SHA-256 has been checked on the original bytes. Memory then grows only as
// far as the drawing needs; dwg.test.ts and dwg_samples.check.ts measure how far.
export const WASM_MIN_PAGES = 256;   // 16 MB; the largest sample measured grows past it on its own
export function lowerMemoryFloor(bin: Uint8Array, pages = WASM_MIN_PAGES): { from: number; to: number } {
  let p = 8;
  const leb = () => { let r = 0, s = 0, b: number; do { b = bin[p++]; r += (b & 0x7f) * 2 ** s; s += 7; } while (b & 0x80 && s < 35); return r; };
  while (p < bin.length) {
    const id = bin[p++], size = leb(), start = p;
    if (id === 5) {
      if (leb() !== 1) throw new Error('libredwg wasm: expected one memory');
      p++;                                   // flags: bit 0 says a maximum follows the minimum
      const at = p, from = leb(), width = p - at;
      if (pages >= from) return { from, to: from };
      for (let i = 0, v = pages; i < width; i++, v = Math.floor(v / 128)) bin[at + i] = (v & 0x7f) | (i < width - 1 ? 0x80 : 0);
      return { from, to: pages };
    }
    p = start + size;
  }
  throw new Error('libredwg wasm: no memory section');
}

/** The WASM heap of the last drawing opened, in bytes (measurement only). */
let heapOf = () => 0;
export const lastWasmHeapBytes = () => heapOf();
// deno-lint-ignore no-explicit-any
async function freshLibreDwg(): Promise<any> {
  compiled ??= (async () => {
    const r = await fetch(WASM_URL);
    if (!r.ok) throw new Error(`libredwg wasm fetch ${r.status}`);
    const bin = new Uint8Array(await r.arrayBuffer());
    if (await sha256Hex(bin) !== WASM_SHA256) throw new Error('libredwg wasm checksum mismatch');
    lowerMemoryFloor(bin);
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
  heapOf = () => inst.HEAPU8?.byteLength ?? 0;
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
