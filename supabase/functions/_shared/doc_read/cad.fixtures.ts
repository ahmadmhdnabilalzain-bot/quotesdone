// cad fixtures — a small ASCII DXF whose true quantities are known by construction.
// Imported by cad.test.ts and by the before/after audit; pure, no I/O.
//
// dxfFixture(): $INSUNITS 4 (mm). Layer FLOOR: one closed 5000 x 4000 LWPOLYLINE = 20.00 sqm, 18.00 m
// perimeter. Layer WALLS: two LINEs, 5000 + 4000 = 9.00 m. Block D-900 inserted 3 times in ENTITIES
// (its definition in BLOCKS holds a LINE that must NOT be counted). TEXT "LIVING ROOM" and an Arabic
// MTEXT with formatting codes.

/** Group-code/value pairs -> DXF text. */
export function dxfFrom(pairs: [number, string | number][]): Uint8Array {
  return new TextEncoder().encode(pairs.map(([c, v]) => `${String(c).padStart(3)}\n${v}`).join('\n') + '\n');
}

/**
 * The same pairs as a BINARY DXF, written independently of cad.ts's reader: 2-byte codes (R13+) or
 * 1-byte codes (R12). Only the codes the fixtures use: 0-9 / 100 / 102 / 300-369 / 999 / 1000-1009 strings, 10-59 and 1010-1059
 * reals, 60-79 and 1060-1070 int16, 90-99 and 1071 int32.
 */
export function dxfBinaryFrom(pairs: [number, string | number][], wide = true): Uint8Array {
  const out: number[] = [...new TextEncoder().encode('AutoCAD Binary DXF\r\n\x1a\x00')];
  const push = (n: number, len: number, f: (d: DataView) => void) => { const b = new Uint8Array(len); f(new DataView(b.buffer)); out.push(...b); void n; };
  for (const [c, v] of pairs) {
    if (wide) push(c, 2, (d) => d.setInt16(0, c, true)); else out.push(c);
    const str = c <= 9 || c === 100 || c === 102 || (c >= 300 && c <= 369) || c === 999 || (c >= 1000 && c <= 1009);
    if (str) out.push(...new TextEncoder().encode(String(v)), 0);
    else if ((c >= 10 && c <= 59) || (c >= 1010 && c <= 1059)) push(c, 8, (d) => d.setFloat64(0, Number(v), true));
    else if ((c >= 60 && c <= 79) || (c >= 1060 && c <= 1070)) push(c, 2, (d) => d.setInt16(0, Number(v), true));
    else if ((c >= 90 && c <= 99) || c === 1071) push(c, 4, (d) => d.setInt32(0, Number(v), true));
    else throw new Error(`dxfBinaryFrom: code ${c} not supported by the fixture writer`);
  }
  return new Uint8Array(out);
}

export const dxfSection =(name: string, body: [number, string | number][]): [number, string | number][] =>
  [[0, 'SECTION'], [2, name], ...body, [0, 'ENDSEC']];

export const dxfFixture = (): Uint8Array => dxfFrom(dxfFixturePairs());
export function dxfFixturePairs(): [number, string | number][] {
  const line = (layer: string, x1: number, y1: number, x2: number, y2: number): [number, string | number][] =>
    [[0, 'LINE'], [8, layer], [10, x1], [20, y1], [30, 0], [11, x2], [21, y2], [31, 0]];
  const insert = (x: number): [number, string | number][] => [[0, 'INSERT'], [8, 'DOORS'], [2, 'D-900'], [10, x], [20, 0], [30, 0]];
  return [
    ...dxfSection('HEADER', [[9, '$ACADVER'], [1, 'AC1027'], [9, '$INSUNITS'], [70, 4]]),
    ...dxfSection('BLOCKS', [[0, 'BLOCK'], [8, '0'], [2, 'D-900'], [70, 0], [10, 0], [20, 0], [30, 0], ...line('WALLS', 0, 0, 900, 0), [0, 'ENDBLK']]),
    ...dxfSection('ENTITIES', [
      [0, 'LWPOLYLINE'], [8, 'FLOOR'], [90, 4], [70, 1], [10, 0], [20, 0], [10, 5000], [20, 0], [10, 5000], [20, 4000], [10, 0], [20, 4000],
      ...line('WALLS', 0, 0, 5000, 0),
      ...line('WALLS', 5000, 0, 5000, 4000),
      ...insert(1000), ...insert(2000), ...insert(3000),
      [0, 'TEXT'], [8, 'ANNO'], [10, 2500], [20, 2000], [40, 250], [1, 'LIVING ROOM'],
      [0, 'MTEXT'], [8, 'ANNO'], [10, 2500], [20, 1500], [40, 250], [1, '{\\fArial|b0|i0;غرفة المعيشة}\\Pالمطبخ %%c50'],
    ]),
    [0, 'EOF'],
  ];
}

/**
 * dxfTitleBlockFixture(): the same plan carrying the client's identity everywhere a real drawing does —
 * $PROJECTNAME / $LASTSAVEDBY, a LAYER table record and a 2000 mm LINE on layer 'AL MANSOORI VILLA'
 * (with 1001/1000 extended data naming him), a title-block TEXT "CLIENT: Ahmed Al Mansoori", an ATTRIB,
 * an MTEXT whose name is split by a font code, an XREF block whose path names the project folder, and an
 * OBJECTS XRECORD. Every one of them must be gone after redactDxf; every quantity must be unchanged.
 */
export function dxfTitleBlockFixture(): Uint8Array {
  const src = new TextDecoder().decode(dxfFixture());
  const extra = dxfFrom([
    [0, 'LINE'], [8, 'AL MANSOORI VILLA'], [10, 0], [20, 0], [30, 0], [11, 2000], [21, 0], [31, 0], [1001, 'ACAD'], [1000, 'owner Ahmed Al Mansoori'],
    [0, 'TEXT'], [8, 'TITLE'], [10, 0], [20, -500], [40, 100], [1, 'CLIENT: Ahmed Al Mansoori'],
    [0, 'INSERT'], [8, 'TITLE'], [2, 'TB'], [66, 1], [10, 0], [20, -800],
    [0, 'ATTRIB'], [8, 'TITLE'], [10, 0], [20, -800], [40, 100], [1, 'Ahmed Al Mansoori'], [2, 'OWNER'],
    [0, 'SEQEND'], [8, 'TITLE'],
    [0, 'MTEXT'], [8, 'TITLE'], [10, 0], [20, -1100], [40, 100], [3, '{\\fArial|b0;Ahmed Al} Mans'], [1, 'oori\\PVilla 12'],
  ]);
  const head = dxfFrom([[9, '$PROJECTNAME'], [1, 'Mansoori Residence'], [9, '$LASTSAVEDBY'], [1, 'ahmed.m']]);
  const tables = dxfFrom(dxfSection('TABLES', [
    [0, 'TABLE'], [2, 'LAYER'], [70, 2],
    [0, 'LAYER'], [2, '0'], [70, 0], [62, 7], [6, 'CONTINUOUS'],
    [0, 'LAYER'], [2, 'AL MANSOORI VILLA'], [70, 0], [62, 1], [6, 'CONTINUOUS'],
    [0, 'ENDTAB'],
  ]));
  const xrefBlock = dxfFrom([[0, 'BLOCK'], [8, '0'], [2, 'SITE'], [70, 4], [10, 0], [20, 0], [30, 0], [3, 'SITE'], [1, 'C:\\Projects\\Mansoori\\site.dwg'], [0, 'ENDBLK']]);
  const objects = dxfFrom(dxfSection('OBJECTS', [[0, 'XRECORD'], [5, '1F'], [100, 'AcDbXrecord'], [1, 'Mansoori Residence']]));
  const d = new TextDecoder();
  const out = src
    .replace('  9\n$INSUNITS', d.decode(head) + '  9\n$INSUNITS')
    .replace('  0\nSECTION\n  2\nBLOCKS\n', d.decode(tables) + '  0\nSECTION\n  2\nBLOCKS\n' + d.decode(xrefBlock))
    .replace('  0\nENDSEC\n  0\nEOF', d.decode(extra) + '  0\nENDSEC\n' + d.decode(objects) + '  0\nEOF');
  return new TextEncoder().encode(out);
}
