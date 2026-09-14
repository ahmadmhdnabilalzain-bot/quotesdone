// ole.fixtures — .doc and .msg files built in memory with the vendored CFB writer, for the ole
// reader's tests and the before/after audit. Names are ZZ DEMO and addresses @example.invalid.
//
// docFixture is a minimal but VALID Word 97 file: a FIB (wIdent 0xA5EC, nFib 0xC1, fWhichTblStm set,
// fcClx/lcbClx filled), a 1Table stream holding a two-piece Clx, and a zeroed 0Table decoy, so reading
// the wrong table stream fails loudly. Piece 1 is compressed cp1252 (the English BOQ line); piece 2 is
// UTF-16LE (the Arabic line, a 2x2 table, and a HYPERLINK field whose code must not appear in the text).
// @deno-types="../vendor/sheetjs-0.20.3/types/index.d.ts"
import { CFB } from '../vendor/sheetjs-0.20.3/xlsx.mjs';
import { ARABIC_LINE, BOQ_CSV, BOQ_LINE } from './email.fixtures.ts';

export const DOC_PIECE_1 = BOQ_LINE + '\r';
export const DOC_PIECE_2 = ARABIC_LINE + '\r' + 'Item\x07Qty\x07\x07Paint\x0750\x07\x07' +
  'See \x13 HYPERLINK "https://example.invalid" \x14the drawing\x15 for sizes.\r';

function u16(s: string): Uint8Array {
  const b = new Uint8Array(s.length * 2), dv = new DataView(b.buffer);
  for (let i = 0; i < s.length; i++) dv.setUint16(i * 2, s.charCodeAt(i), true);
  return b;
}

function ole(streams: Record<string, Uint8Array>): Uint8Array {
  const c = CFB.utils.cfb_new();
  for (const [p, b] of Object.entries(streams)) CFB.utils.cfb_add(c, '/' + p, b);
  return new Uint8Array(CFB.write(c, { type: 'array' }));
}

export function docFixture(opts: { encrypted?: boolean; macro?: boolean; brokenClx?: boolean } = {}): Uint8Array {
  const AT1 = 0x400, AT2 = 0x500, FC_CLX = 16, LCB_CLX = 33;
  const wd = new Uint8Array(AT2 + DOC_PIECE_2.length * 2), dv = new DataView(wd.buffer);
  dv.setUint16(0, 0xA5EC, true);
  dv.setUint16(2, 0xC1, true);
  dv.setUint16(0x0A, 0x0200 | (opts.encrypted ? 0x0100 : 0), true);
  dv.setUint32(0x1A2, FC_CLX, true);
  dv.setUint32(0x1A6, opts.brokenClx ? 0 : LCB_CLX, true);
  for (let i = 0; i < DOC_PIECE_1.length; i++) wd[AT1 + i] = DOC_PIECE_1.charCodeAt(i);
  wd.set(u16(DOC_PIECE_2), AT2);

  const table = new Uint8Array(FC_CLX + LCB_CLX), t = new DataView(table.buffer, FC_CLX);
  t.setUint8(0, 0x02);
  t.setUint32(1, 28, true); // PlcPcd: 3 CPs + 2 PCDs = 12 + 16
  [0, DOC_PIECE_1.length, DOC_PIECE_1.length + DOC_PIECE_2.length].forEach((cp, i) => t.setUint32(5 + 4 * i, cp, true));
  t.setUint32(5 + 12 + 2, ((AT1 * 2) | 0x40000000) >>> 0, true); // compressed: fc = offset * 2, bit 30
  t.setUint32(5 + 12 + 8 + 2, AT2, true);

  const streams: Record<string, Uint8Array> = { WordDocument: wd, '1Table': table, '0Table': new Uint8Array(64) };
  if (opts.macro) streams['Macros/VBA/_VBA_PROJECT'] = new Uint8Array(8);
  return ole(streams);
}

export const docMacroFixture = (): Uint8Array => docFixture({ macro: true });

export const MSG_SUBJECT = 'ZZ DEMO villa fit-out BOQ';
export const MSG_BODY = 'Please price the attached.\r\n' + BOQ_LINE;

/** An Outlook message with `attachments` copies of boq.csv (the first named boq.csv, then boq-N.csv). */
export function msgFixture(attachments = 1): Uint8Array {
  const streams: Record<string, Uint8Array> = {
    '__substg1.0_0037001F': u16(MSG_SUBJECT),
    '__substg1.0_1000001F': u16(MSG_BODY),
    '__substg1.0_0C1A001F': u16('ZZ DEMO Buyer'),
    '__substg1.0_5D01001F': u16('buyer@example.invalid'),
  };
  for (let i = 0; i < attachments; i++) {
    const dir = `__attach_version1.0_#${i.toString(16).toUpperCase().padStart(8, '0')}`;
    streams[`${dir}/__substg1.0_37010102`] = BOQ_CSV;
    streams[`${dir}/__substg1.0_3707001F`] = u16(i ? `boq-${i}.csv` : 'boq.csv');
  }
  return ole(streams);
}
