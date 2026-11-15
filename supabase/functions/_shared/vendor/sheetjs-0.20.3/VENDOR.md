# SheetJS 0.20.3, minified

`xlsx.mjs` is SheetJS Community Edition 0.20.3 (`https://cdn.sheetjs.com/xlsx-0.20.3/package/xlsx.mjs`, Apache-2.0),
minified on 15 Nov 2026 with esbuild 0.24.2 (`esbuild xlsx.mjs --format=esm --minify`).

- Original file: 1,008,308 bytes, sha256 `1a0fb062ee9781b13f6687371b202aaefc53b6ce55b530c027e01f9c087b77db` (in git history
  before this change). Minified: 503,237 bytes.
- Why: supplier_api's source upload reached the Supabase deploy limit ("Function source code exceeds the maximum deployment
  size (5 MB)", 413) after #2001: 4,686,568 bytes uploaded failed, 4.5 MB had passed. SheetJS was 1 MB of it, reached
  through `_shared/doc_read` (`../xlsx_lazy.ts`). Every function that reads documents uploads it.
- Proven the same: the minified module has the same 19 exports and `version` 0.20.3; a workbook written by each and read by
  the other gives the same cells in xlsx, xls, biff8, ods and csv; the CFB (old Office container) reader lists the same
  entries; and the repository's document-reading tests pass.
- To update: take the official `xlsx.mjs` of the new version, minify it the same way, and redo the checks above.
