// workbook_engine — the ONE seam between doc_read and the vendored SheetJS (16 Nov 2026, it_engineer).
//
// WHY. `supabase functions deploy supplier_api --use-api` failed 413 on 16 Nov 2026: the local files in its
// module graph (deno info --json, every file under supabase/functions/) came to 4,695,339 bytes, where 4.54 MB
// had deployed on 15 Nov. 503,237 of those bytes are SheetJS (vendor/sheetjs-0.20.3/xlsx.mjs), reached ONLY
// through vendor/xlsx_lazy.ts from office.ts (readWorkbook) and ole.ts (.doc / .msg, SheetJS's CFB reader). A
// literal dynamic import() is still bundled, so loading it late saved start-up time but not upload size.
//
// WHAT THIS IS. office.ts and ole.ts no longer import SheetJS. They ask the engine registered here for
//   sheets(bytes)        the workbook's sheet names, and the rows of the first SHEET_LIMITS.maxSheets sheets
//                        (cached values only; rows[i] is null for a name with no sheet behind it), and
//   compoundFile(bytes)  an OLE2 file's streams, keyed by lowercased path below the root ('worddocument',
//                        'macros/...'), or null when the bytes are not a compound file,
// and keep every safety check of their own (zip / VBA / macro / encryption refusals, the 20-sheet note, the row
// cap) in front of and around it. An engine reports an unreadable file by throwing with the reader's message;
// office.ts / ole.ts turn that into a refusal, so a caller of readDocument never sees a throw.
//
// THE TWO ENGINES, and who registers which (scripts/checks/every_office_reader_has_an_engine.test.mjs holds it):
//   workbook_local.ts   SheetJS in this isolate. Registered by importing it, at the entry of every function
//                       whose graph reaches office.ts or ole.ts, except supplier_api and wa_inbound.
//   workbook_remote.ts  POSTs the bytes to doc_extract ({op:'read_workbook' | 'read_compound_file'}), which reads
//                       them with workbook_local. Registered by supplier_api and wa_inbound (16 Nov 2026), so SheetJS
//                       leaves their uploads.
// NO ENGINE is a refusal ('unreadable', NO_WORKBOOK_READER), never an empty read: a function that forgot to
// register one says so on the first workbook rather than reporting a supplier's BOQ as a blank sheet.
import { LIMITS, type Cell } from './types.ts';

/** The read limits both engines apply, kept here so the local and the remote read are the same read. */
export const SHEET_LIMITS = { maxSheets: 20, sheetRows: LIMITS.maxTableRows + 1 } as const;

/**
 * The most bytes the remote engine sends and doc_extract reads: LIMITS.maxBytes, the 25 MB every upload is accepted at.
 * Only the words-only supplier path (readDocument opts.maxBytes = LIMITS.maxPaperBytes) can hand a larger workbook or
 * .msg, and on supplier_api that one is refused with this number in the reason rather than sent as ~33 MB of base64.
 */
export const REMOTE_READ_MAX_BYTES = LIMITS.maxBytes;

export type SheetsRead = { names: string[]; rows: (Cell[][] | null)[] };
export type CompoundFileRead = Map<string, Uint8Array> | null;

export interface WorkbookEngine {
  /** 'local' reads in this isolate; 'remote' asks doc_extract. */
  readonly where: 'local' | 'remote';
  sheets(bytes: Uint8Array): Promise<SheetsRead>;
  compoundFile(bytes: Uint8Array): Promise<CompoundFileRead>;
}

export const NO_WORKBOOK_READER = 'this function has no workbook reader';

let registered: WorkbookEngine | null = null;

/** Set (or, with null, clear) this isolate's engine. The last registration wins. */
export function registerWorkbookEngine(engine: WorkbookEngine | null): void {
  registered = engine;
}

export function workbookEngine(): WorkbookEngine | null {
  return registered;
}
