// licence_pdf.mjs — generate a synthetic UAE trade licence as a real PDF.
//
// The other two fixtures in this directory are PNGs generated once with System.Drawing and checked
// in. A licence needs three variants (valid, expired, illegible) and would otherwise be three more
// binaries nobody can diff or adjust, so it is generated from data instead: change a field here and
// every test that uses it changes with it.
//
// This writes the PDF by hand rather than pulling a dependency. A single-page PDF with Type1
// Helvetica is about 40 lines of structure, and license_extract sends it to the model as a
// `file` content block (`application/pdf`), so the text has to be real text in a content stream -
// which is also why this is a better licence fixture than a rasterised image: it exercises the
// PDF passthrough branch of buildContent(), not the image branch the drawing fixture already covers.
//
// NOTHING HERE IS A REAL BUSINESS. The names, licence numbers and TRNs are invented for staging.

const esc = (s) => String(s).replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');

/** Build a one-page A4 PDF from an array of text lines. Returns a Buffer. */
export function pdfFromLines(lines, { size = 11, leading = 17, top = 800, left = 56 } = {}) {
  const body = ['BT', `/F1 ${size} Tf`, `${leading} TL`, `${left} ${top} Td`]
    .concat(lines.map((l) => `(${esc(l)}) Tj T*`))
    .concat(['ET']).join('\n');

  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] ' +
      '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    `<< /Length ${Buffer.byteLength(body, 'latin1')} >>\nstream\n${body}\nendstream`,
  ];

  // The xref table stores a byte offset per object, so the file has to be assembled and measured as
  // it is built - a wrong offset makes a PDF that opens in some readers and not others.
  let out = '%PDF-1.4\n';
  const offsets = [];
  objs.forEach((o, i) => {
    offsets.push(Buffer.byteLength(out, 'latin1'));
    out += `${i + 1} 0 obj\n${o}\nendobj\n`;
  });
  const xref = Buffer.byteLength(out, 'latin1');
  out += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n`
    + offsets.map((o) => `${String(o).padStart(10, '0')} 00000 n \n`).join('')
    + `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(out, 'latin1');
}

// A DED-style licence with every field SYS_LICENSE asks for, so a failure is the reader's and not
// the document's.
export const VALID_LICENCE = {
  legal_name: 'Al Meydan Aluminium And Glass Works L.L.C',
  license_number: '1145872',
  license_authority: 'Dubai Department of Economy and Tourism',
  emirate: 'Dubai',
  city: 'Dubai',
  issue_date: '2024-03-14',
  expiry_date: '2027-03-13',
  trn: '100447291500003',
  activities: ['Aluminium and Glass Works Installation', 'Glass Installation and Repairing',
               'Metal Doors and Windows Installation'],
};

export const EXPIRED_LICENCE = {
  ...VALID_LICENCE,
  legal_name: 'Nasser Bin Rashid Metal Works L.L.C',
  license_number: '0938441',
  issue_date: '2021-06-02',
  expiry_date: '2024-06-01',
  trn: '100882634700003',
};

export function licenceLines(d) {
  return [
    'GOVERNMENT OF DUBAI',
    d.license_authority.toUpperCase(),
    '',
    'TRADE LICENCE / RUKHSA TIJARIYA',
    '',
    `Licence Number        : ${d.license_number}`,
    `Legal Name            : ${d.legal_name}`,
    `Trade Name            : ${d.legal_name.replace(/ L\.L\.C$/, '')}`,
    `Legal Type            : Limited Liability Company (LLC)`,
    `Issuing Authority     : ${d.license_authority}`,
    `Emirate               : ${d.emirate}`,
    `City / Area           : ${d.city}, Al Quoz Industrial First`,
    `Issue Date            : ${d.issue_date.split('-').reverse().join('/')}`,
    `Expiry Date           : ${d.expiry_date.split('-').reverse().join('/')}`,
    `Tax Registration No   : ${d.trn}`,
    `Register Number       : ${Number(d.license_number) + 400000}`,
    '',
    'LICENSED ACTIVITIES',
    ...d.activities.map((a, i) => `  ${i + 1}. ${a}`),
    '',
    'This licence is valid until the expiry date shown above and must be',
    'renewed annually. Issued electronically; no signature is required.',
  ];
}

// A REAL licence is rarely one activity line. DED licences routinely carry a dozen or more listed
// activities, each a long formal phrase, plus partner and manager blocks. The simple fixture above
// measured 860 output tokens against license_extract's caller-side max:1500 - only 43% headroom -
// so this is the variant that decides whether that ceiling is actually safe or merely untested.
export const DENSE_LICENCE = {
  ...VALID_LICENCE,
  legal_name: 'Emirates Advanced Facade And Curtain Wall Contracting L.L.C',
  license_number: '1207734',
  trn: '100556183900003',
  activities: [
    'Aluminium and Glass Works Installation',
    'Curtain Walls and Cladding Installation Works',
    'Glass Installation, Tempering and Repairing',
    'Metal Doors, Windows and Frames Installation',
    'Architectural Metal Works Fabrication',
    'Fire Rated Doors and Partitions Installation',
    'Automatic Doors and Barriers Installation and Maintenance',
    'Steel Structure Fabrication and Erection Works',
    'Skylights and Roof Glazing Installation',
    'Balustrades, Handrails and Railing Installation',
    'Shopfronts and Display Windows Fitting',
    'Insulating Glass Units Assembly',
    'Powder Coating and Anodising of Aluminium Profiles',
    'Building Maintenance and Facade Cleaning Services',
    'Interior Glass Partitions and Shower Enclosures Installation',
  ],
};

/** A page that is genuinely unreadable as a licence: right shape, no registration data. */
export const ILLEGIBLE_LINES = [
  'SCANNED DOCUMENT - PAGE 1 OF 1',
  '',
  '############  ##########  ####',
  '#####   ####################',
  '',
  '.... ..... ...... ... ......',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '',
  '(the remainder of this page did not scan)',
];

export const validLicencePdf = () => pdfFromLines(licenceLines(VALID_LICENCE));
export const denseLicencePdf = () => pdfFromLines(licenceLines(DENSE_LICENCE));
export const expiredLicencePdf = () => pdfFromLines(licenceLines(EXPIRED_LICENCE));
export const illegibleLicencePdf = () => pdfFromLines(ILLEGIBLE_LINES);
