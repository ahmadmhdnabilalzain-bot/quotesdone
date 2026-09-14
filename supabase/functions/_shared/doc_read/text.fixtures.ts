// text.fixtures — TXT / CSV / RTF bytes with BOQ-like content in English and one Arabic line.
// Shared by text.test.ts and the before/after audit; pure, in memory.
export const ARABIC_LINE = 'بلاط سيراميك للحمامات 40 م2';
const enc = new TextEncoder();

export const txtFixture = async () => enc.encode(`Bill of Quantities\nPorcelain tiles 600x600  120 sqm\nGypsum ceiling  85 sqm\n${ARABIC_LINE}\n`);

/** The same content saved by Excel as "Unicode text": UTF-16LE with a BOM. */
export async function txtUtf16leFixture(): Promise<Uint8Array> {
  const s = `Porcelain tiles 600x600  120 sqm\n${ARABIC_LINE}\n`;
  const b = new Uint8Array(2 + s.length * 2);
  b[0] = 0xff; b[1] = 0xfe;
  for (let i = 0; i < s.length; i++) { const c = s.charCodeAt(i); b[2 + i * 2] = c & 0xff; b[3 + i * 2] = c >> 8; }
  return b;
}

/** Arabic Windows ANSI: 'بلاط' is C8 E1 C7 D8 in windows-1256; not valid UTF-8. */
export async function txt1256Fixture(): Promise<Uint8Array> {
  return new Uint8Array([...enc.encode('Porcelain tiles 600x600  120 sqm\n'), 0xc8, 0xe1, 0xc7, 0xd8, ...enc.encode(' 40 sqm\n')]);
}

export const csvFixture = async () => enc.encode(
  'Description,Qty,Unit,Rate\r\n' +
  '"Porcelain tiles 600x600, matt",120,sqm,45.50\r\n' +
  '"Skirting ""10cm"" high",85,lm,12\r\n' +
  `${ARABIC_LINE},40,sqm,38\r\n`,
);

/** Word-style RTF: fonttbl with an Arabic \fcharset178 font, a header, info, a field, and a 2-row table. */
export const rtfFixture = async () => enc.encode([
  '{\\rtf1\\ansi\\ansicpg1252\\deff0{\\fonttbl{\\f0\\fswiss Arial;}{\\f1\\fnil\\fcharset178 Arial;}}',
  '{\\colortbl;\\red0\\green0\\blue0;}{\\*\\generator Riched20;}{\\info{\\title Secret title}{\\author ACME LLC}}',
  '{\\header \\pard Header ACME LLC\\par}',
  '\\pard Bill of quantities\\par',
  'Porcelain tiles 600x600\\tab 120 sqm\\par',
  "{\\f1 \\'c8\\'e1\\'c7\\'d8 }{\\uc1\\u1587?\\u1610?\\u1585?\\u1575?\\u1605?\\u1610?\\u1603?}\\par",
  '\\trowd\\cellx2000\\cellx3000\\cellx4000\\cellx5000',
  '\\pard\\intbl Description\\cell Qty\\cell Unit\\cell Rate\\cell\\row',
  '\\trowd\\cellx2000\\cellx3000\\cellx4000\\cellx5000',
  '\\pard\\intbl Porcelain tiles 600x600\\cell 120\\cell sqm\\cell 45.50\\cell\\row',
  '\\pard After table\\par',
  '{\\field{\\*\\fldinst HYPERLINK "http://evil.example"}{\\fldrslt link text}}\\par',
  '}',
].join('\n'));
