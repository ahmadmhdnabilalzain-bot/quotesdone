// doc_extract's workbook-engine ops: the far end of _shared/doc_read/workbook_remote.ts (16 Nov 2026, it_engineer).
//
// supplier_api does not upload SheetJS any more (its deploy failed 413 at 4.70 MB; see workbook_engine.ts). When it
// reads a workbook or a .doc/.msg it POSTs the bytes here, after the same requireInternal gate as every other caller:
//   {op:'read_workbook',      b64}  ->  {ok:true, names, rows}            (workbook_engine.ts SheetsRead)
//   {op:'read_compound_file', b64}  ->  {ok:true, entries:[[path,b64]]|null}
//   a reader error                  ->  422 {ok:false, error:'unreadable', message}   (the caller turns it into a refusal)
// The read is the LOCAL engine (workbook_local.ts, imported here), so this op can never call itself. Nothing is stored,
// logged or indexed: the bytes are read and answered, and doc_extract's own document queue is not touched.
import { decodeBase64, encodeBase64 } from 'jsr:@std/encoding@1/base64';
import { localWorkbookEngine } from '../_shared/doc_read/workbook_local.ts';
import { REMOTE_READ_MAX_BYTES, type WorkbookEngine } from '../_shared/doc_read/workbook_engine.ts';

export const WORKBOOK_OPS = new Set(['read_workbook', 'read_compound_file']);

type OpAnswer = { status: number; body: Record<string, unknown> };

/** The answer to an engine op, or null when the body asks for none (doc_extract then drains its queue as before). */
// deno-lint-ignore no-explicit-any
export async function workbookOp(body: any, engine: WorkbookEngine = localWorkbookEngine): Promise<OpAnswer | null> {
  const op = body?.op;
  if (typeof op !== 'string' || !WORKBOOK_OPS.has(op)) return null;
  const b64 = typeof body.b64 === 'string' ? body.b64 : '';
  if (!b64) return { status: 400, body: { ok: false, error: 'bad_request', message: 'no b64 bytes were sent' } };
  // Decoded size from the text length, checked BEFORE decoding, so an oversized body is never turned into bytes.
  const approxBytes = Math.floor(b64.length / 4) * 3;
  if (approxBytes > REMOTE_READ_MAX_BYTES + 2) {
    return { status: 413, body: { ok: false, error: 'too_large', message: `the file is about ${approxBytes} bytes, over the ${REMOTE_READ_MAX_BYTES} this reader takes` } };
  }
  let bytes: Uint8Array;
  try { bytes = decodeBase64(b64); } catch { return { status: 400, body: { ok: false, error: 'bad_request', message: 'b64 is not base64' } }; }
  try {
    if (op === 'read_workbook') {
      const r = await engine.sheets(bytes);
      return { status: 200, body: { ok: true, names: r.names, rows: r.rows } };
    }
    const m = await engine.compoundFile(bytes);
    return { status: 200, body: { ok: true, entries: m ? [...m].map(([path, data]) => [path, encodeBase64(data)]) : null } };
  } catch (e) {
    return { status: 422, body: { ok: false, error: 'unreadable', message: String((e as Error)?.message || e).slice(0, 300) } };
  }
}
