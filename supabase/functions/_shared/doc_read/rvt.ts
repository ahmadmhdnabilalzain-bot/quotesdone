// rvt — what a Revit file (.rvt / .rfa) says about itself, read without Autodesk (22 Sep 2026).
//
// WHY. Founder instructions 31, 63, 64 and 696: read every drawing format, and for Revit "no need for
// Revit, I am sure there is an alternative". Until today an .rvt came back with one fixed "cannot be
// read" note. The alternatives were checked on 22 Sep 2026:
//   Autodesk APS Model Derivative   paid                                        -> not allowed
//   ODA BimRv SDK                   commercial licence                          -> not allowed
//   cad2data (datadrivenconstruction) closed Windows .exe built on ODA; no source, no OSI licence -> not allowed
//   pyRevit, RevitFileUtility       need Revit / read the same header this file reads
//   rvt-rs (DrunkOnJava, Apache-2.0, Rust, pushed 20 Sep 2026) the only open reader of the model itself;
//                                   its README says "Generic real-project typed element extraction is
//                                   mostly unsolved", with walls/doors/windows/columns proven on Revit
//                                   2024 files only. Not reliable enough to quote from, and a Rust->WASM
//                                   port is its own project. Revisit when it covers every release.
// So this reads what is CERTAIN and asks for the IFC export Revit makes natively.
//
// WHAT IT READS. An .rvt is an OLE2 compound file. It is opened by rootStreams() below, NOT by the
// vendored SheetJS CFB that ole.ts uses: CFB.read copies every stream of the file and was MEASURED at
// 54 -> 212 MB RSS on a 6.9 MB .rvt (at that ratio, not measured, a 20 MB upload would pass the edge's 256 MB). Four root streams:
//   BasicFileInfo      a binary head, then a UTF-16LE "Key: value" block at an ODD byte offset (so it
//                      is decoded at both alignments): Format (the Revit year; 2013-era files have
//                      "Revit Build: Autodesk Revit Architecture 2013 (Build: ...)" instead), Build,
//                      Worksharing, Locale when saved.
//   RevitPreview4.0    a Revit header (223-304 bytes on the samples) then a PNG, returned as found.
//   PartAtom           families only: Atom XML whose adsk:revit:grouping category is the family's
//                      category ("Columns", "Doors"). Projects have no PartAtom but a ProjectInformation
//                      stream, which is how a family is told from a project.
//   TransmissionData   XML listing external file references (keynote tables, links) with their paths;
//                      nothing to quote from, so it is NOT read.
//
// MEASURED 22 Sep 2026, Deno 2.9 on the dev machine, on public samples fetched at test time (never
// committed): magnetar-io/revit-test-datasets (MIT) Revit_IFC5_Einhoven.rvt 913,408 B Revit 2023,
// Column_Sqaure.rfa 360,448 B and I_Single-Flush.rfa 307,200 B Revit 2020; vchekalin/ScheduleAPIDemo
// rac_basic_sample_project.rvt 6,909,952 B Revit 2013. All four gave the right Revit year and build,
// workshared false, family true for the two .rfa (categories Columns, Doors), and a 128 x 128 PNG
// preview (483-1,286 B) byte-identical to the one SheetJS CFB extracts. rvtInfo: 1-2 ms each, RSS
// 32-38 MB before -> 33-39 MB after (+1 MB at most, the 6.9 MB file included). Not measured on the edge
// or on a file over 7 MB. Re-run: QD_RVT_SAMPLE_URL=<urls> deno test ... rvt.test.ts.
//
// WHAT IT NEVER DOES. It never puts the Last Save Path, Central Model Path, Username or any document
// GUID into text or notes: those identify the customer and notes are shown to suppliers. It does not
// read elements or quantities (see WHY), runs nothing, and caps every stream it decodes.
import { empty, ok, refuse, type ReadContext, type ReadResult } from './types.ts';

const MAX_INFO = 64 * 1024, MAX_PREVIEW = 2 * 1024 * 1024;
const PNG_SIG = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

export const RVT_IFC_ASK = 'The building elements and quantities inside a Revit file are not read here. Please export it from Revit as IFC (File > Export > IFC, then Modify setup, and on the Property Sets tab tick "Export base quantities" so areas and volumes come through) and upload the .ifc file; its quantities are then read directly.';
// Named constants, so src/lib/boqNotes.test.mjs finds every sentence and fails on one with no Arabic.
const RVT_VERSION_NOTE = (v: string) => `This Revit file was saved in Revit ${v}.`;
const RVT_NO_VERSION_NOTE = 'The Revit version could not be read from this file.';
const RVT_FAMILY_NOTE = 'This Revit file is a family (.rfa), not a project model.';
const RVT_WORKSHARED_NOTE = 'This Revit model is workshared (part of a team model).';
const RVT_PREVIEW_NOTE = (w: number, h: number) => `A ${w} x ${h} pixel preview image was extracted from the file.`;
export const RVT_OTHER_ASK ='A DWG or DXF export of the plans (File > Export > CAD Formats) or a PDF of the drawing sheets can be uploaded instead.';

export type RvtInfo = {
  version: string | null;
  build: string | null;
  workshared: boolean | null;
  family: boolean;
  locale: string | null;
  category: string | null;
  preview: { png: Uint8Array; width: number; height: number } | null;
};

type Stream = { size: number; read: (cap: number) => Uint8Array | null };
const END = 0xFFFFFFFE;

/**
 * The ROOT-level streams of an OLE2 compound file [MS-CFB], by lowercased name, each read lazily and
 * only up to a cap (see the header for why this is not SheetJS CFB.read). This walks the header, the
 * FAT and the directory and copies only the few KB asked for. Every sector id is checked
 * against the file and every chain walk is bounded by the sector count, so a cyclic or lying FAT ends.
 * Null when the bytes are not a compound file.
 */
function rootStreams(b: Uint8Array): Map<string, Stream> | null {
  const SIG = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
  if (b.length < 512 || !SIG.every((v, i) => b[i] === v)) return null;
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength), u32 = (o: number) => dv.getUint32(o, true);
  const shift = dv.getUint16(0x1E, true), ssz = 1 << shift;
  if (shift !== 9 && shift !== 12 || dv.getUint16(0x20, true) !== 6) return null;
  const nSec = Math.floor((b.length - ssz) / ssz), at = (s: number) => (s + 1) * ssz;
  // FAT sector ids: 109 in the header, the rest in the DIFAT chain.
  const fatSecs: number[] = [];
  for (let i = 0; i < 109; i++) { const s = u32(0x4C + 4 * i); if (s < nSec) fatSecs.push(s); }
  for (let d = u32(0x44), n = 0; d < nSec && n < nSec; n++) {
    for (let i = 0; i < ssz / 4 - 1; i++) { const s = u32(at(d) + 4 * i); if (s < nSec) fatSecs.push(s); }
    d = u32(at(d) + ssz - 4);
  }
  const per = ssz / 4;
  const fat = (s: number) => { const f = fatSecs[Math.floor(s / per)]; return f === undefined ? END : u32(at(f) + 4 * (s % per)); };
  const chain = (start: number, maxSecs: number) => {
    const out: number[] = [];
    for (let s = start; s < nSec && out.length < Math.min(maxSecs, nSec); s = fat(s)) out.push(s);
    return out;
  };
  const gather = (secs: number[], size: number, cap: number) => {
    const n = Math.min(size, cap, secs.length * ssz), o = new Uint8Array(n);
    for (let i = 0; i * ssz < n; i++) o.set(b.subarray(at(secs[i]), at(secs[i]) + Math.min(ssz, n - i * ssz)), i * ssz);
    return o;
  };
  const dir = gather(chain(u32(0x30), nSec), nSec * ssz, 4 * 1024 * 1024); // 4 MB = 32,768 entries
  const ent = (i: number) => {
    const o = i * 128; if (o + 128 > dir.length) return null;
    const e = new DataView(dir.buffer, dir.byteOffset + o, 128), nl = Math.min(e.getUint16(64, true), 64);
    return { name: new TextDecoder('utf-16le').decode(dir.subarray(o, o + Math.max(0, nl - 2))), type: dir[o + 66],
      l: e.getUint32(68, true), r: e.getUint32(72, true), c: e.getUint32(76, true), start: e.getUint32(116, true), size: e.getUint32(120, true) };
  };
  const root = ent(0);
  if (!root || root.type !== 5) return null;
  const cutoff = u32(0x38), miniSecs = () => chain(root.start, Math.ceil(root.size / ssz));
  let mini: number[] | null = null, miniFat: Uint8Array | null = null;
  const m = new Map<string, Stream>();
  // The root's children form a red-black tree over left/right siblings: walked with a bounded stack.
  const stack = [root.c], seen = new Set<number>();
  while (stack.length && seen.size < dir.length / 128) {
    const i = stack.pop()!; if (i >= dir.length / 128 || seen.has(i)) continue; seen.add(i);
    const e = ent(i); if (!e) continue;
    stack.push(e.l, e.r);
    if (e.type !== 2) continue;
    m.set(e.name.toLowerCase(), { size: e.size, read: (cap) => {
      if (e.size >= cutoff) return gather(chain(e.start, Math.ceil(Math.min(e.size, cap) / ssz)), e.size, cap);
      mini ??= miniSecs();
      miniFat ??= gather(chain(u32(0x3C), u32(0x40)), u32(0x40) * ssz, 16 * 1024 * 1024);
      const n = Math.min(e.size, cap), o = new Uint8Array(n), mf = new DataView(miniFat.buffer, miniFat.byteOffset, miniFat.byteLength);
      for (let s = e.start, k = 0; k * 64 < n; k++) {
        const off = s * 64, sec = mini[Math.floor(off / ssz)];
        if (sec === undefined || 4 * s + 4 > mf.byteLength) return null;
        o.set(b.subarray(at(sec) + off % ssz, at(sec) + off % ssz + Math.min(64, n - k * 64)), k * 64);
        s = mf.getUint32(4 * s, true);
      }
      return o;
    } });
  }
  return m;
}

const head = (s: Stream | undefined, cap: number) => { try { return s ? s.read(cap) : null; } catch { return null; } };

/** The "Key: value" text of BasicFileInfo, from both byte alignments (the block sits at an odd offset). */
function infoText(b: Uint8Array): string {
  const d = new TextDecoder('utf-16le');
  return [0, 1].map((o) => d.decode(b.subarray(o, o + ((b.length - o) & ~1)))).join('\n');
}

/** The PNG inside RevitPreview4.0: from its signature to the end of its IEND chunk, with IHDR's size. */
export function findPng(b: Uint8Array): RvtInfo['preview'] {
  let s = -1;
  for (let i = 0; i + 8 <= b.length && s < 0; i++) if (PNG_SIG.every((v, k) => b[i + k] === v)) s = i;
  if (s < 0) return null;
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
  let p = s + 8, width = 0, height = 0;
  while (p + 12 <= b.length) {
    const len = dv.getUint32(p), type = String.fromCharCode(b[p + 4], b[p + 5], b[p + 6], b[p + 7]);
    if (len > b.length - p - 12) return null; // a chunk claiming more bytes than exist
    if (p === s + 8) { if (type !== 'IHDR' || len < 8) return null; width = dv.getUint32(p + 8); height = dv.getUint32(p + 12); }
    p += 12 + len;
    if (type === 'IEND') return width && height ? { png: b.slice(s, p), width, height } : null;
  }
  return null;
}

/** Everything certain about a Revit file; null when it is not a compound file with a BasicFileInfo. */
export function rvtInfo(bytes: Uint8Array): RvtInfo | null {
  let m: Map<string, Stream> | null;
  try { m = rootStreams(bytes); } catch { m = null; }
  const bfi = head(m?.get('basicfileinfo'), MAX_INFO);
  if (!m || !bfi) return null;
  const t = infoText(bfi);
  // A key follows a line break, or (the first key) a stray binary char; never a letter or a space, so
  // "Build" does not match inside "Revit Build".
  const line = (k: string) => t.match(new RegExp(`(?:^|[^A-Za-z ])${k}:([^\\r\\n\\0]*)`))?.[1]?.trim() || null;
  const revitBuild = line('Revit Build'); // Revit 2013-era: "Autodesk Revit Architecture 2013 (Build: 20130531_2115(x64))"
  const version = line('Format')?.match(/^\d{4}$/)?.[0] ?? revitBuild?.match(/\b(20\d\d)\b/)?.[1] ?? null;
  const build = (line('Build') ?? revitBuild)?.match(/\d{8}_\d{4}(?:\(x\d+\))?/)?.[0] ?? null;
  const ws = line('Worksharing');
  const pv = m.get('revitpreview4.0');
  const pvBytes = pv && pv.size <= MAX_PREVIEW ? head(pv, MAX_PREVIEW) : null;
  const atom = head(m.get('partatom'), MAX_INFO);
  const category = atom ? new TextDecoder().decode(atom)
    .match(/<category>\s*<term>([^<]{1,80})<\/term>\s*<scheme>adsk:revit:grouping<\/scheme>/)?.[1]?.trim() ?? null : null;
  return {
    version, build,
    workshared: ws ? !/^not enabled$/i.test(ws) : null,
    family: !!atom || !m.has('projectinformation'),
    locale: line('Locale when saved')?.match(/^[A-Z]{3}$/)?.[0] ?? null,
    category,
    preview: pvBytes ? findPng(pvBytes) : null,
  };
}

export function readRvt(bytes: Uint8Array, _ctx: ReadContext): Promise<ReadResult> {
  const info = rvtInfo(bytes);
  if (!info) return Promise.resolve(refuse('rvt_unreadable', 'Not a readable Revit file: no OLE2 compound file with a BasicFileInfo stream.'));
  const notes: string[] = [];
  notes.push(info.version ? RVT_VERSION_NOTE(info.version) : RVT_NO_VERSION_NOTE);
  if (info.family) notes.push(RVT_FAMILY_NOTE);
  if (info.workshared) notes.push(RVT_WORKSHARED_NOTE);
  if (info.preview) notes.push(RVT_PREVIEW_NOTE(info.preview.width, info.preview.height));
  notes.push(RVT_IFC_ASK, RVT_OTHER_ASK);
  const e = empty('rvt', notes, 'bim_conversion');
  if (info.category) e.text = `Revit family category: ${info.category}`;
  return Promise.resolve(ok(e));
}
