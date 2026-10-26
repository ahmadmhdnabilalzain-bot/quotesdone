// doc_read — the dispatcher. One entry point, readDocument(), for every file the sales side reads.
//
// THE GATE COMES FIRST. The bytes go through sanitizeUpload() with SAFE_DOCS before any reader sees
// them: the type is decided by the BYTES (never the name or the declared type), executables / HTML /
// SVG / script / PDF polyglots / macro-bearing Office files are refused by shape, and the size is
// capped. A container's children (zip entries, email attachments) come back through this same
// function, so every child is re-sniffed and re-sanitized, and nesting is capped at LIMITS.maxDepth.
//
// WHAT NEEDS SOMETHING OUTSIDE THIS FUNCTION is said, not guessed: a photo or a scan comes back with
// needs:'ocr' (the customer's browser OCRs it for free, see src/components/me/ocrClient.ts), a DWG past
// dwg.ts's edge-sized ceiling (queued for the CAD worker by customer_api), a Revit model or a MicroStation
// DGN with needs:'cad_conversion' / 'bim_conversion', and the reason is in notes. A DWG is READ (dwg.ts, LibreDWG) since 22 Sep 2026.
import { sanitizeUpload, SAFE_DOCS } from '../attachment.ts';
import { type Extracted, type ReadContext, type ReadResult, LIMITS, empty, ok, refuse } from './types.ts';
import { readPdf } from './pdf.ts';
import { readZip } from './zip.ts';
import { readDocx, readOdf, readPptx, readWorkbook } from './office.ts';
import { readCsv, readRtf, readTxt } from './text.ts';
import { readDoc, readMsg } from './ole.ts';
import { readEml } from './email.ts';
import { readDxf } from './cad.ts';
import { readDwg } from './dwg.ts';
import { readIfc } from './ifc.ts';
import { readGaeb } from './gaeb.ts';
import { readRvt } from './rvt.ts';
import { dgnVersion } from './dgn.ts';

type Reader = (bytes: Uint8Array, ctx: ReadContext) => Promise<ReadResult>;
const needs = (kind: string, need: NonNullable<Extracted['needs']>, note: string): Reader => () => Promise.resolve(ok(empty(kind, [note], need)));
// 22 Sep 2026. These notes become the BOQ's missing_info the customer reads, so each says what to send
// instead, in English here and in Arabic on screen (src/lib/boqNotes.ts). A Revit model is read for what
// is certain (rvt.ts: version, family/project, workshared, the embedded preview) and asked for an IFC,
// which Revit exports natively and ifc.ts reads fully. A DGN is recognised (V7 by its ISFF header, V8 by
// its OLE2 storages) and asked for DWG / DXF / PDF: V8 is Bentley's closed format (only the commercial
// ODA/Bentley SDKs read it); a V7 reader is possible (GDAL libdgn, MIT) and not built, on the founder's
// 22 Sep order of work: DWG, DXF and PDF first.
export const DGN_NOTE = 'A MicroStation DGN drawing cannot be read here yet. Save it from MicroStation as DWG or DXF (File > Save As) or print it to PDF and upload that; its quantities are then read directly.';
const DGN_V8_NOTE = 'This is a MicroStation DGN V8 file.';
const DGN_V7_NOTE = (d: string) => `This is a MicroStation DGN V7 (${d}) file.`;
const readDgn: Reader = (bytes) => {
  const v = dgnVersion(bytes);
  const which = v === 'v8' ? DGN_V8_NOTE : v ? DGN_V7_NOTE(v === 'v7-3d' ? '3D' : '2D') : null;
  return Promise.resolve(ok(empty('dgn', which ? [which, DGN_NOTE] : [DGN_NOTE], 'cad_conversion')));
};
const OCR_NOTE = 'A photo or scan has no text layer; its words are read by OCR in the customer’s browser, or by a vision model when inference is allowed.';

const READERS: Record<string, Reader> = {
  'application/pdf': readPdf,
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': readWorkbook,
  'application/vnd.ms-excel': readWorkbook,
  'text/csv': readCsv,
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': readDocx,
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': readPptx,
  'application/vnd.oasis.opendocument.text': readOdf,
  'application/vnd.oasis.opendocument.spreadsheet': readOdf,
  'application/vnd.oasis.opendocument.presentation': readOdf,
  'application/msword': readDoc,
  'application/rtf': readRtf,
  'text/plain': readTxt,
  'message/rfc822': readEml,
  'application/vnd.ms-outlook': readMsg,
  'image/vnd.dxf': readDxf,
  'application/x-step': readIfc,
  'application/x-gaeb+xml': readGaeb,
  'application/zip': readZip,
  'image/vnd.dwg': readDwg,
  'application/vnd.autodesk.revit': readRvt,
  'image/vnd.dgn': readDgn,
  'image/jpeg': needs('image', 'ocr', OCR_NOTE),
  'image/png': needs('image', 'ocr', OCR_NOTE),
  'image/webp': needs('image', 'ocr', OCR_NOTE),
  'image/gif': needs('image', 'ocr', OCR_NOTE),
  'image/tiff': needs('image', 'ocr', OCR_NOTE),
  'image/heic': needs('image', 'ocr', OCR_NOTE),
};

export type DocumentRead = ReadResult & { mime?: string };

/** Bytes (or base64) from anyone -> what the document says, or a refusal with the reason. */
export async function readDocument(input: Uint8Array | string, filename: string, declaredMime = '', depth = 0, opts: { textOnly?: boolean } = {}): Promise<DocumentRead> {
  const s = sanitizeUpload({ input, declaredMime, filename, allow: SAFE_DOCS, maxBytes: LIMITS.maxBytes });
  if (!s.ok) return refuse(s.error, s.detail);
  const reader = READERS[s.mime];
  if (!reader) return refuse('file_type_not_allowed', `no reader for ${s.mime}`);
  const ctx: ReadContext = { filename, depth, textOnly: !!opts.textOnly, readChild: (b, name, d) => readDocument(b, name, '', d, opts) };
  try {
    const r = await reader(s.bytes, ctx);
    return r.ok ? { ...r, mime: s.mime } : r;
  } catch (e) {
    return refuse('unreadable_document', String((e as Error)?.message || e).slice(0, 160));
  }
}
