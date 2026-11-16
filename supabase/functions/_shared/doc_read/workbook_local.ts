// workbook_local — the SheetJS workbook engine, in THIS isolate, registered by importing this file (16 Nov 2026,
// it_engineer). See workbook_engine.ts for why the seam exists (supplier_api's upload: 413 at 4.70 MB).
//
// HOW A FUNCTION USES IT. One line at the top of its index.ts:
//     import '../_shared/doc_read/workbook_local.ts'; // reads workbooks and .doc/.msg here (SheetJS)
// A side-effect import, not an exported register call, because the import IS what puts SheetJS in the function's
// upload: the line that adds the 503 KB and the line that turns the reader on are the same line, so neither can be
// present without the other. scripts/checks/every_office_reader_has_an_engine.test.mjs fails a function whose graph
// reaches office.ts or ole.ts with neither this import nor the remote engine, and fails supplier_api if SheetJS
// reaches its graph again.
//
// NEVER import this from a _shared module: that would put SheetJS back into every function that imports the module,
// supplier_api included. Function entries (and doc_extract, which answers the remote engine) only.
//
// The read options are exactly the ones office.ts / ole.ts used before the seam: CACHED values only (cellFormula
// false), no HTML / number formats / styles / VBA, sheetRows SHEET_LIMITS.sheetRows; rows as sheet_to_json
// {header:1, raw:true, defval:'', blankrows:false}. SheetJS itself is still loaded on the first read
// (../vendor/xlsx_lazy.ts), not at boot.
import { loadXlsx } from '../vendor/xlsx_lazy.ts';
import { registerWorkbookEngine, SHEET_LIMITS, type CompoundFileRead, type SheetsRead, type WorkbookEngine } from './workbook_engine.ts';
import type { Cell } from './types.ts';

type Entry = { name: string; type: number; content?: ArrayLike<number> };

export const localWorkbookEngine: WorkbookEngine = {
  where: 'local',

  async sheets(bytes: Uint8Array): Promise<SheetsRead> {
    const XLSX = await loadXlsx();
    const wb = XLSX.read(bytes, { type: 'array', cellFormula: false, cellHTML: false, cellNF: false, cellStyles: false, bookVBA: false, sheetRows: SHEET_LIMITS.sheetRows });
    const rows = wb.SheetNames.slice(0, SHEET_LIMITS.maxSheets).map((name) => {
      const ws = wb.Sheets[name];
      return ws ? XLSX.utils.sheet_to_json<Cell[]>(ws, { header: 1, raw: true, defval: '', blankrows: false }) : null;
    });
    return { names: [...wb.SheetNames], rows };
  },

  async compoundFile(bytes: Uint8Array): Promise<CompoundFileRead> {
    const { CFB } = await loadXlsx();
    let c: { FullPaths: string[]; FileIndex: Entry[] };
    try { c = CFB.read(bytes, { type: 'array' }); } catch { return null; }
    if (!c?.FullPaths?.length) return null;
    const root = c.FullPaths[0];
    const m = new Map<string, Uint8Array>();
    c.FullPaths.forEach((p, i) => { if (i) m.set(p.slice(root.length).toLowerCase(), new Uint8Array(c.FileIndex[i].content ?? [])); });
    return m;
  },
};

registerWorkbookEngine(localWorkbookEngine);
