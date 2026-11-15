// drawing_file_redact — ONE entry for "the drawing file a supplier may open": the customer's PDF, DWG or DXF,
// anonymised and PROVED before it is released (28 Sep 2026, sales_engineer; founder ledger 30, 31, 32, 580, 703).
// A file is released only when its verifier passes: it opens, its geometry is the original's, its take-off counts
// are the original's, and no identifier is left anywhere in it. Anything else is `ok:false` with the reason.
// Formats: PDF and DWG / DXF only (founder ruling 1000, 28 Sep 2026) — _shared/drawing_format.ts refuses the rest.
import { redactPdfVector, verifyPdfRedaction } from './pdf_vector_redact.ts';
import { redactCadFile, verifyCadRedaction } from './cad_file_redact.ts';

export type DrawingFile =
  | { ok: true; kind: 'pdf' | 'dxf' | 'dxf_binary' | 'dwg'; bytes: Uint8Array; ext: 'pdf' | 'dxf'; mime: string; proof: Record<string, unknown> }
  | { ok: false; held: string; detail?: unknown };

const isPdf = (b: Uint8Array) => new TextDecoder('latin1').decode(b.subarray(0, 5)) === '%PDF-';

/** `maxDwgBytes`: dwg.ts's edge ceiling on the edge (default), Infinity on the CAD worker. */
export async function anonymisedDrawingFile(bytes: Uint8Array, seeds: string[], opts: { maxDwgBytes?: number; identity?: Set<string> | null } = {}): Promise<DrawingFile> {
  try {
    if (isPdf(bytes)) {
      const r = await redactPdfVector(bytes, seeds);
      if (!r.ok) return { ok: false, held: 'pdf_' + r.held, detail: r.detail };
      const v = await verifyPdfRedaction(bytes, r.bytes, seeds);
      if (!v.ok) return { ok: false, held: 'pdf_not_verified', detail: v.problems.slice(0, 8) };
      return { ok: true, kind: 'pdf', bytes: r.bytes, ext: 'pdf', mime: 'application/pdf',
        proof: { removed_runs: r.removed_runs, removed_images: r.removed_images, kept_runs: r.kept_runs, pages: v.pages, geometry_ops: v.geometry_ops, counts: v.counts } };
    }
    const r = await redactCadFile(bytes, seeds, opts);
    if (!r.ok) return { ok: false, held: 'cad_' + r.held, detail: r.detail };
    const v = await verifyCadRedaction(r.before_dxf, r.dxf, seeds, r, [], r.removed);
    if (!v.ok) return { ok: false, held: 'cad_not_verified', detail: v.problems.slice(0, 8) };
    return { ok: true, kind: r.source, bytes: r.bytes, ext: 'dxf', mime: 'image/vnd.dxf',
      proof: { source: r.source, entities: v.entities, geometry_pairs: v.geometry_pairs, counts: v.counts, values_changed: r.changed, strings_removed: r.removed.length } };
  } catch (e) {
    return { ok: false, held: 'exception', detail: String((e as Error)?.message || e).slice(0, 160) };
  }
}
