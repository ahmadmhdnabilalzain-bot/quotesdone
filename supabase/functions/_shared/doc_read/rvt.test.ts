// rvt.test — the Revit header reader proved on an in-memory OLE2 built with the vendored CFB writer,
// the hostile cases, and (only when QD_RVT_SAMPLE_URL is set) real public samples fetched at test
// time and never committed. QD_RVT_SAMPLE_URL takes a comma-separated list of URLs, e.g. the MIT
// magnetar-io/revit-test-datasets files on media.githubusercontent.com. CI leaves it unset.
// @deno-types="../vendor/sheetjs-0.20.3/types/index.d.ts"
import { CFB } from '../vendor/sheetjs-0.20.3/xlsx.mjs';
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { findPng, readRvt, rvtInfo, RVT_IFC_ASK, RVT_OTHER_ASK } from './rvt.ts';
import type { ReadResult } from './types.ts';

const ctx = { filename: 'model.rvt', depth: 0 };
const must = (r: ReadResult) => { if (!r.ok) throw new Error(`${r.error}: ${r.detail}`); return r; };
const u16 = (s: string) => { const b = new Uint8Array(s.length * 2), dv = new DataView(b.buffer); for (let i = 0; i < s.length; i++) dv.setUint16(2 * i, s.charCodeAt(i), true); return b; };
const cat = (...a: Uint8Array[]) => { const o = new Uint8Array(a.reduce((n, x) => n + x.length, 0)); let p = 0; for (const x of a) { o.set(x, p); p += x.length; } return o; };

// A 3 x 2 PNG: signature, IHDR, an empty IDAT, IEND (CRCs are not checked by the reader).
function png(w: number, h: number): Uint8Array {
  const chunk = (type: string, data: Uint8Array) => {
    const c = new Uint8Array(12 + data.length), dv = new DataView(c.buffer);
    dv.setUint32(0, data.length); for (let i = 0; i < 4; i++) c[4 + i] = type.charCodeAt(i); c.set(data, 8);
    return c;
  };
  const ihdr = new Uint8Array(13), dv = new DataView(ihdr.buffer); dv.setUint32(0, w); dv.setUint32(4, h); ihdr[8] = 8; ihdr[9] = 6;
  return cat(new Uint8Array([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), chunk('IHDR', ihdr), chunk('IDAT', new Uint8Array(0)), chunk('IEND', new Uint8Array(0)));
}

const PATH = 'C:\\ZZ DEMO\\Projects\\Villa.rvt';
/** BasicFileInfo shaped like Revit 2023's: binary head, then the key-value block one byte off alignment. */
function bfi(o: { format?: string; worksharing?: string; old?: boolean } = {}): Uint8Array {
  const kv = o.old
    ? `Worksharing: ${o.worksharing ?? 'Not enabled'}\r\nUsername: zz.demo\r\nCentral Model Path: \\\\srv\\ZZ DEMO\\central.rvt\r\nRevit Build: Autodesk Revit Architecture 2013 (Build: 20130531_2115(x64))\r\nLast Save Path: ${PATH}\r\nLocale when saved: RUS\r\n`
    : `Worksharing: ${o.worksharing ?? 'Not enabled'}\r\nUsername: zz.demo\r\nCentral Model Path: \r\nFormat: ${o.format ?? '2023'}\r\nBuild: 20230828_1515(x64)\r\nLast Save Path: ${PATH}\r\nLocale when saved: ENU\r\n`;
  return cat(new Uint8Array([0x0E, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0]), u16('2023'), new Uint8Array([7]), u16(kv));
}
function rvt(streams: Record<string, Uint8Array>): Uint8Array {
  const c = CFB.utils.cfb_new();
  for (const [p, b] of Object.entries(streams)) CFB.utils.cfb_add(c, '/' + p, b);
  return new Uint8Array(CFB.write(c, { type: 'array' }));
}
const preview = (p: Uint8Array) => cat(new Uint8Array(302).fill(0x19), p);
const ATOM = '<?xml version="1.0"?><entry xmlns="http://www.w3.org/2005/Atom"><title>ZZ DEMO Column</title><category><term>23.25.30.11.14.11</term><scheme>std:oc1</scheme></category><category><term>Columns</term><scheme>adsk:revit:grouping</scheme></category></entry>';

Deno.test('rvt project: version, build, preview, and nothing identifying in text or notes', async () => {
  const bytes = rvt({ BasicFileInfo: bfi(), 'RevitPreview4.0': preview(png(3, 2)), ProjectInformation: u16('ZZ DEMO') });
  const i = rvtInfo(bytes)!;
  assertEquals([i.version, i.build, i.workshared, i.family, i.locale, i.category], ['2023', '20230828_1515(x64)', false, false, 'ENU', null]);
  assertEquals([i.preview?.width, i.preview?.height], [3, 2]);
  assertEquals([...i.preview!.png.slice(0, 4)], [0x89, 0x50, 0x4E, 0x47]);
  const r = must(await readRvt(bytes, ctx));
  assertEquals([r.kind, r.needs, r.text, r.quantities.length], ['rvt', 'bim_conversion', '', 0]);
  assertEquals(r.notes, ['This Revit file was saved in Revit 2023.', 'A 3 x 2 pixel preview image was extracted from the file.', RVT_IFC_ASK, RVT_OTHER_ASK]);
  const all = r.text + r.notes.join(' ');
  for (const secret of ['ZZ DEMO', 'zz.demo', 'Villa', 'C:\\']) assert(!all.includes(secret), secret);
});

Deno.test('rvt family, workshared, Revit 2013 header', async () => {
  const fam = rvt({ BasicFileInfo: bfi({ format: '2020' }), PartAtom: new TextEncoder().encode(ATOM) });
  const r = must(await readRvt(fam, { filename: 'c.rfa', depth: 0 }));
  assertEquals(r.text, 'Revit family category: Columns');
  assertEquals(r.notes.slice(0, 2), ['This Revit file was saved in Revit 2020.', 'This Revit file is a family (.rfa), not a project model.']);
  const old = rvtInfo(rvt({ BasicFileInfo: bfi({ old: true, worksharing: 'Local' }), ProjectInformation: u16('x') }))!;
  assertEquals([old.version, old.build, old.workshared, old.locale], ['2013', '20130531_2115(x64)', true, 'RUS']);
  const ws = must(await readRvt(rvt({ BasicFileInfo: bfi({ worksharing: 'Central' }), ProjectInformation: u16('x') }), ctx));
  assert(ws.notes.includes('This Revit model is workshared (part of a team model).'));
});

Deno.test('rvt hostile: garbage, truncated, no BasicFileInfo, lying PNG, oversized streams', async () => {
  const good = rvt({ BasicFileInfo: bfi(), 'RevitPreview4.0': preview(png(3, 2)) });
  for (const bad of [new Uint8Array(0), new TextEncoder().encode('not a revit file'), good.slice(0, 700), rvt({ Other: u16('x') })]) {
    const r = await readRvt(bad, ctx);
    assertEquals(r.ok ? 'ok' : r.error, 'rvt_unreadable');
  }
  // A garbage header claiming a huge directory / sector count must still just refuse.
  const lying = good.slice(); new DataView(lying.buffer).setUint32(0x2C, 0x7FFFFFFF, true); new DataView(lying.buffer).setUint32(0x30, 0xFFFFFFF0, true);
  const lr = await readRvt(lying, ctx);
  assert(!lr.ok || lr.needs === 'bim_conversion');
  // An IHDR chunk claiming 2 GB, and a PNG with no IEND: no preview, no throw.
  const p = png(3, 2); const huge = p.slice(); new DataView(huge.buffer).setUint32(8, 0x7FFFFFFF);
  assertEquals(findPng(huge), null);
  assertEquals(findPng(p.slice(0, p.length - 12)), null);
  // A preview stream past the 2 MB cap is skipped; a BasicFileInfo past 64 KB is read from its head.
  const big = rvtInfo(rvt({ BasicFileInfo: cat(bfi(), new Uint8Array(200_000)), 'RevitPreview4.0': cat(preview(png(3, 2)), new Uint8Array(2_200_000)) }))!;
  assertEquals([big.version, big.preview], ['2023', null]);
});

const SAMPLES = (() => { try { return Deno.env.get('QD_RVT_SAMPLE_URL') ?? ''; } catch { return ''; } })();
Deno.test({ name: 'rvt real samples (QD_RVT_SAMPLE_URL)', ignore: !SAMPLES, fn: async () => {
  for (const url of SAMPLES.split(',').map((s) => s.trim()).filter(Boolean)) {
    const bytes = new Uint8Array(await (await fetch(url)).arrayBuffer());
    if (bytes.length > 20 * 1024 * 1024) { console.log(`skip ${url}: ${bytes.length} B > 20 MB`); continue; }
    const t0 = performance.now();
    const r = must(await readRvt(bytes, ctx));
    const ms = performance.now() - t0, i = rvtInfo(bytes)!;
    console.log(JSON.stringify({ file: url.split('/').pop(), bytes: bytes.length, version: i.version, build: i.build, workshared: i.workshared, family: i.family, category: i.category, preview: i.preview && `${i.preview.width}x${i.preview.height} ${i.preview.png.length} B`, ms: Math.round(ms), rss_mb: Math.round(Deno.memoryUsage().rss / 1048576) }));
    assert(i.version && /^20\d\d$/.test(i.version), 'version read');
    assert(i.preview, 'preview found');
    assert(!(r.text + r.notes.join(' ')).match(/[A-Z]:\\|\\\\/), 'no path in text or notes');
  }
} });
