// ONE lazy door to the vendored SheetJS (28 Sep 2026, it_engineer). The module is ~1 MB; imported
// statically it is parsed on every cold start of every function whose graph reaches doc_read, which
// includes supplier_api and supplier_portal — the supplier journey's two hot functions — although no
// journey step reads a spreadsheet. A dynamic import with a literal path is still bundled (the same
// pattern supplier_catalog_ingest uses), so nothing is fetched at runtime; it is only evaluated late.
// The promise is kept so the second workbook in the same isolate does not re-import.
// Since 16 Nov 2026 the only importer is ../doc_read/workbook_local.ts (the SheetJS engine a function registers by
// importing it); supplier_api registers the remote engine instead and does not upload SheetJS (doc_read/workbook_engine.ts).
// @deno-types="./sheetjs-0.20.3/types/index.d.ts"
import type * as XLSXNS from './sheetjs-0.20.3/xlsx.mjs';

let loading: Promise<typeof XLSXNS> | null = null;
export function loadXlsx(): Promise<typeof XLSXNS> {
  // @deno-types="./sheetjs-0.20.3/types/index.d.ts"
  return (loading ??= import('./sheetjs-0.20.3/xlsx.mjs'));
}
