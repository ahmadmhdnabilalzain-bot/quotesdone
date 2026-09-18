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

// deno-lint-ignore no-explicit-any
export function parseUaeWorkbook(wb: any): ParsedEntry[] {
  const out: ParsedEntry[] = [];
  for (const sheetName of (wb?.SheetNames ?? []) as string[]) {
    if (UAE_SKIP.test(sheetName)) continue;
    const isInd = UAE_INDIVIDUAL_SHEETS.some((s) => sheetName.includes(s));
    const isEnt = UAE_ENTITY_SHEETS.some((s) => sheetName.includes(s));
    if (!isInd && !isEnt) continue;
    const rows = sheetRows(wb.Sheets[sheetName]);
    for (const row of rows) {
      // The workbook has no stable column headers across editions (the 2026 file's header row is merged
      // cells), so the name is taken as the LONGEST text cell in the row and the reference as the first
      // short alphanumeric one. A row with no cell of 2+ characters is a spacer and is dropped.
      const cells = row.map((c) => String(c ?? '').replace(/\s+/g, ' ').trim()).filter(Boolean);
      if (!cells.length) continue;
      let name = '';
      for (const c of cells) if (c.length > name.length) name = c;
      if (name.length < 2) continue;
      if (/^(no|s\/?n|name|الاسم|م)$/i.test(name)) continue; // header row
      const reference = cells.find((c) => c !== name && c.length <= 20) ?? null;
      out.push({ entry_type: isInd ? 'individual' : 'entity', reference, name });
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

export function uaeExcelUrl(html: string): string | null {
  // Any href on the page that points at a .xls/.xlsx download, or a FileID query the site uses.
  const href = html.match(/href\s*=\s*["']([^"']*(?:\.xlsx?|FileID=[0-9a-f-]{36})[^"']*)["']/i);
  if (!href) return null;
  const u = href[1].trim();
  if (/^https?:/i.test(u)) return u;
  return new URL(u, UAE_PAGE).toString();
}
