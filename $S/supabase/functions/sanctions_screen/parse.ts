// THE PARSERS FOR THE TWO SANCTIONS SOURCES, SEPARATED FROM THE FETCH SO THEY CAN BE TESTED (18 Sep 2026,
// it_engineer). index.ts does the network, the storage and the screening call; everything that turns bytes
// into names lives here and is proved by parse.test.ts against fixtures, because the one thing that cannot
// be proved in CI is a third-party download.
//
// WHY REGEX AND NOT AN XML PARSER. The UN consolidated list is ~2.1 MB of a flat, machine-generated schema
// with no namespaces, no CDATA around the name fields and no attributes that matter to us. An edge function
// has a CPU cap that a wall-clock deadline does not bound (the estate has already lost a job to it), and a
// DOM parse of 2 MB allocates the whole tree; a linear scan does not. If the UN ever changes the shape, the
// count drops and `entries` on the screening_run row says so — which is why the count is recorded per run
// and not just the names.

export type ParsedEntry = { entry_type: 'individual' | 'entity'; reference: string | null; name: string };

const tag = (block: string, name: string): string[] => {
  const out: string[] = [];
  const re = new RegExp('<' + name + '>([\\s\\S]*?)</' + name + '>', 'g');
  for (const m of block.matchAll(re)) out.push(decode(m[1]));
  return out;
};

const decode = (s: string) =>
  s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_m, d) => String.fromCodePoint(Number(d)))
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ').trim();

function blocks(xml: string, name: string): string[] {
  const out: string[] = [];
  const re = new RegExp('<' + name + '>([\\s\\S]*?)</' + name + '>', 'g');
  for (const m of xml.matchAll(re)) out.push(m[1]);
  return out;
}

// One listed person or organisation yields its primary name AND every alias, because a sanctioned party
// that trades under an alias is exactly the case a screen exists to catch. Empty and one-character names
// are dropped: the UN list carries empty <THIRD_NAME/> elements on most individuals, and a single letter
// would match half the register on token overlap.
// `??` falls through on null and undefined only, and the UN list emits PRESENT-BUT-EMPTY elements all
// over (<THIRD_NAME/>, and <REFERENCE_NUMBER></REFERENCE_NUMBER> on some entries). `tag()` returns '' for
// those, so `?? next` would have kept the empty string and never reached the DATAID fallback.
const firstNonEmpty = (...v: Array<string | undefined>): string | null => v.find((x) => x && x.trim()) ?? null;

export function parseUnXml(xml: string): ParsedEntry[] {
  const out: ParsedEntry[] = [];
  const push = (entry_type: 'individual' | 'entity', reference: string | null, name: string) => {
    const n = name.trim();
    if (n.length >= 2) out.push({ entry_type, reference, name: n });
  };
  for (const b of blocks(xml, 'INDIVIDUAL')) {
    const ref = firstNonEmpty(tag(b, 'REFERENCE_NUMBER')[0], tag(b, 'DATAID')[0]);
    const full = ['FIRST_NAME', 'SECOND_NAME', 'THIRD_NAME', 'FOURTH_NAME']
      .map((t) => tag(b, t)[0] ?? '').filter(Boolean).join(' ');
    push('individual', ref, full);
    for (const a of tag(b, 'ALIAS_NAME')) push('individual', ref, a);
  }
  for (const b of blocks(xml, 'ENTITY')) {
    const ref = firstNonEmpty(tag(b, 'REFERENCE_NUMBER')[0], tag(b, 'DATAID')[0]);
    push('entity', ref, tag(b, 'FIRST_NAME')[0] ?? '');
    for (const a of tag(b, 'ALIAS_NAME')) push('entity', ref, a);
  }
  return out;
}

// THE UAE LOCAL TERRORIST LIST IS PUBLISHED AS A PDF AND A LEGACY EXCEL WORKBOOK, AND ONLY THE EXCEL IS
// PARSED (recorded on every screening_run row as a limitation, not hidden). The sheet names are Arabic and
// the two DE-LISTING sheets must be excluded: a de-listed party is precisely the one we must NOT ban.
export const UAE_INDIVIDUAL_SHEETS = ['الأفراد', 'الافراد'];
export const UAE_ENTITY_SHEETS = ['التنظيمات', 'الكيانات'];
const UAE_SKIP = /رفع|شطب|delist|de-list/i;

// THE SHEET IS READ OFF ITS OWN HEADER ROW, NOT GUESSED (rewritten 18 Sep 2026 against the real file).
//
// The first version took the LONGEST text cell in each row as the name. Measured against the actual
// workbook (183,808 bytes, 5 sheets), that is wrong in both directions: it parsed 320 "names", of which
// the first three on every sheet were the sheet title and the merged section captions, and on the
// organisations sheet the longest cell is "مدرج بموجب قرار مجلس الوزراء رقم (41) لسنة 2014" — the
// listing resolution, not a name. A screening list with resolution texts in it is a list that matches
// on the wrong thing, and 174 + 146 rows of it would have been compared against 22,267 leads.
//
// The file is in fact perfectly regular, and says so itself: on each sheet, row index 2 is a header row
// whose first cell is '#', data begins on the next row, and the NAME columns are exactly those whose
// header contains الاسم (name). So the header is used:
//   الأفراد    A1:S174, header '#' | التصنيف | الجنسية | اسم العائلة (عربي) | (لاتيني) | الاسم الكامل …
//   التنظيمات  A1:E78,  header '#' | التصنيف | الاسم الكامل (بالحروف اللاتينية) | الاسم | معلومات أخرى
//   الكيانات   A1:EZ145, header '#' | التصنيف | الاسم الكامل (عربي) | (لاتيني) | الاسم | رقم الرخصة …
// EVERY name column is emitted, not just one: a listed party appears in Arabic and in Latin script and
// often under a second known name, and a supplier could be registered under any of them.
//
// If no header row is found the sheet yields NOTHING rather than a guess, which the caller records as
// `unparseable` — a wrong list is worse than a missing one, and the run row says which it was.
const UAE_NAME_HEADER = /الاسم|name/i;
const UAE_PLACEHOLDER = /^(-{1,3}|n\/?a|غير معروف|لا يوجد)$/i;

// deno-lint-ignore no-explicit-any
export function parseUaeWorkbook(wb: any): ParsedEntry[] {
  const out: ParsedEntry[] = [];
  const seen = new Set<string>();
  for (const sheetName of (wb?.SheetNames ?? []) as string[]) {
    if (UAE_SKIP.test(sheetName)) continue;
    const isInd = UAE_INDIVIDUAL_SHEETS.some((s) => sheetName.includes(s));
    const isEnt = UAE_ENTITY_SHEETS.some((s) => sheetName.includes(s));
    if (!isInd && !isEnt) continue;
    // DENSE, NOT SPARSE. sheetRows assigns by column index, so a column the workbook emits no cell for
    // leaves a real array HOLE — and Array.prototype.map and .filter SKIP holes rather than visiting
    // them. Reading the header with .map/.filter would therefore step straight over a name column whose
    // header cell happened to be absent, and lose it in silence with nothing on the run row to say so
    // (independent review). Every row is widened to the same length with explicit '' first, so from
    // here on an index is either a value or an empty string and never a hole.
    const raw = sheetRows(wb.Sheets[sheetName]);
    const width = raw.reduce((w, r) => Math.max(w, r.length), 0);
    const rows = raw.map((r) =>
      Array.from({ length: width }, (_v, i) => String(r[i] ?? '').replace(/\s+/g, ' ').trim()));

    const headerAt = rows.findIndex((r) => r[0] === '#');
    if (headerAt < 0) continue;
    const header = rows[headerAt];
    const nameCols: number[] = [];
    for (let i = 0; i < width; i++) if (UAE_NAME_HEADER.test(header[i])) nameCols.push(i);
    if (!nameCols.length) continue;

    for (const row of rows.slice(headerAt + 1)) {
      // Column 0 is the listing's own sequence number. A row without one is a spacer or a trailing
      // note, never an entry.
      const reference = (row[0] ?? '').trim();
      if (!/^\d+$/.test(reference)) continue;
      for (const c of nameCols) {
        const name = (row[c] ?? '').trim();
        if (name.length < 2 || UAE_PLACEHOLDER.test(name)) continue;
        // The same party's Arabic and Latin names are separate entries; the same STRING twice is not.
        const key = sheetName + ' ' + reference + ' ' + name;
        if (seen.has(key)) continue;
        seen.add(key);
        out.push({ entry_type: isInd ? 'individual' : 'entity', reference, name });
      }
    }
  }
  return out;
}

// deno-lint-ignore no-explicit-any
function sheetRows(sheet: any): unknown[][] {
  if (!sheet || !sheet['!ref']) return [];
  const rows: Record<number, unknown[]> = {};
  for (const addr of Object.keys(sheet)) {
    if (addr.startsWith('!')) continue;
    const m = addr.match(/^([A-Z]+)(\d+)$/);
    if (!m) continue;
    const r = Number(m[2]);
    const c = [...m[1]].reduce((acc, ch) => acc * 26 + (ch.charCodeAt(0) - 64), 0) - 1;
    (rows[r] ||= [])[c] = sheet[addr].w ?? sheet[addr].v;
  }
  return Object.keys(rows).sort((a, b) => Number(a) - Number(b)).map((k) => rows[Number(k)]);
}

// THE UAE PAGE DOES NOT LINK A STABLE FILE. The FileID changes when a new list is published, so the page is
// re-read for the current "Download Excel File" link and the last known FileID is the fallback. Returning
// null rather than throwing lets the caller record WHICH half failed on the screening_run row.
export const UAE_PAGE = 'https://www.uaeiec.gov.ae/en-us/un-page';
export const UAE_FALLBACK_FILE_ID = '0433bfdb-8a3d-44db-9015-90cbbf48f6f6';
// Measured 18 Sep 2026: application/vnd.ms-excel, "LS 130923 2026.xls", 183,808 bytes, magic d0cf11e0.
export const UAE_FALLBACK_URL = 'https://www.uaeiec.gov.ae/API/Upload/DownloadFile?FileID=' + UAE_FALLBACK_FILE_ID;

// THE PAGE LINKS FOURTEEN FILES AND ONLY ONE IS THE LIST (rewritten 18 Sep 2026, after the first real
// run downloaded the wrong one). The original took the FIRST href matching .xls or a FileID. Measured
// against the live page, that is `FileID=49dafd48…`, which is "Federal Decree No. 26 of 2021" — a
// 575,454-byte PDF. That is exactly what the first production run fetched: screening_run 74, status
// unparseable, "parsed 0 of 575454 bytes". The two links that are the list itself carry no anchor text
// at all (they are icons, `&nbsp;`), so no amount of reading the text around the href would find them:
//   b60dd6ac… -> application/pdf, "LS 130923 2026.pdf", 653,078 bytes
//   0433bfdb… -> application/vnd.ms-excel, "LS 130923 2026.xls", 183,808 bytes   <- the one
// So the candidates are RANKED and then the bytes decide. The caller tries them in order and keeps the
// first that is actually a workbook (isWorkbook below), which is the only property that matters and the
// only one the site cannot silently change out from under us.
//
// AND THE HOST IS FIXED, BECAUSE THE HREFS COME OUT OF SOMEBODY ELSE'S HTML (independent security
// review, before this shipped). The first version passed an absolute href through verbatim, so a
// compromised, cache-poisoned or simply edited uaeiec.gov.ae page could name ANY origin and this
// function — which runs with the service role and outbound network access — would fetch it. That is
// server-side request forgery with a government website as the injection point. Only the one host the
// list is published on is ever fetched; anything else is dropped before it becomes a candidate.
const UAE_HOST = new URL(UAE_PAGE).hostname;

export function uaeCandidateUrls(html: string): string[] {
  const out: string[] = [];
  const add = (u: string) => {
    let abs: string;
    try { abs = new URL(u, UAE_PAGE).toString(); } catch { return; }   // a malformed href is not a URL
    const parsed = new URL(abs);
    if (parsed.protocol !== 'https:') return;
    if (parsed.hostname !== UAE_HOST) return;
    if (!out.includes(abs)) out.push(abs);
  };
  // The FileID known to be the workbook goes first: it is one request when nothing has moved.
  add('https://www.uaeiec.gov.ae/API/Upload/DownloadFile?FileID=' + UAE_FALLBACK_FILE_ID);
  // A link that names a spreadsheet outright is the next best guess.
  for (const m of html.matchAll(/href\s*=\s*["']([^"']*\.xlsx?(?:[?#][^"']*)?)["']/gi)) add(m[1].trim());
  // Then every download the page offers, newest-looking first is not knowable, so: in page order.
  for (const m of html.matchAll(/href\s*=\s*["']([^"']*DownloadFile\?FileID=[0-9a-fA-F-]{36})["']/gi)) add(m[1].trim());
  return out;
}

// A LEGACY .xls IS AN OLE2 COMPOUND FILE (D0 CF 11 E0) AND .xlsx IS A ZIP (PK). Sniffing the bytes is
// what stops a PDF being handed to the workbook reader and coming back as "0 names parsed", which reads
// like an empty sanctions list and is not one.
export function isWorkbook(bytes: Uint8Array): boolean {
  if (bytes.length < 8) return false;
  const ole = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];
  if (ole.every((b, i) => bytes[i] === b)) return true;
  return bytes[0] === 0x50 && bytes[1] === 0x4b; // PK
}
