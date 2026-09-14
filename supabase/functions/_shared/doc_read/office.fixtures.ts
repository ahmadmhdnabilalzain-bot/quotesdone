// office.fixtures — minimal but structurally real docx / pptx / odt / ods / xlsx / docm, built in memory.
// Each carries the same BOQ: a Description/Qty/Unit/Rate table, "Porcelain tiles 600x600  120 sqm",
// and one Arabic line. The xlsx is written by the vendored SheetJS itself, with a formula cell whose
// CACHED value (5460) is what a reader must return. Shared by office.test.ts and the before/after audit.
// @deno-types="../vendor/sheetjs-0.20.3/types/index.d.ts"
import * as XLSX from '../vendor/sheetjs-0.20.3/xlsx.mjs';
import { ARABIC_LINE } from './text.fixtures.ts';
import { zipFixture, type FixtureEntry } from './zip.fixtures.ts';

const HEAD = ['Description', 'Qty', 'Unit', 'Rate'];
const ROW = ['Porcelain tiles 600x600', '120', 'sqm', '45.50'];
const X = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

const W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
const wp = (t: string) => `<w:p><w:r><w:t xml:space="preserve">${t}</w:t></w:r></w:p>`;
const wtr = (cells: string[]) => `<w:tr>${cells.map((c) => `<w:tc>${wp(c)}</w:tc>`).join('')}</w:tr>`;

function docxEntries(): FixtureEntry[] {
  return [
    { name: '[Content_Types].xml', data: `${X}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>` },
    { name: 'word/document.xml', data: `${X}<w:document ${W}><w:body>` +
      `<w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="4000"/></w:tabs></w:pPr><w:r><w:t>Bill of Quantities</w:t></w:r></w:p>` +
      `<w:p><w:r><w:t xml:space="preserve">Porcelain tiles 600x600</w:t></w:r><w:r><w:tab/><w:t>120 sqm</w:t></w:r></w:p>` +
      `<w:p><w:r><w:t>Line one</w:t><w:br/><w:t>Line two</w:t></w:r></w:p>` +
      wp(ARABIC_LINE) +
      `<w:tbl>${wtr(HEAD)}${wtr(ROW)}</w:tbl>` +
      `<w:p><w:del><w:r><w:delText>deleted words</w:delText></w:r></w:del></w:p>` +
      `</w:body></w:document>` },
    { name: 'word/header1.xml', data: `${X}<w:hdr ${W}>${wp('Project: Villa 12')}</w:hdr>` },
    { name: 'word/footnotes.xml', data: `${X}<w:footnotes ${W}><w:footnote>${wp('Rates exclude VAT.')}</w:footnote></w:footnotes>` },
  ];
}
export const docxFixture = () => zipFixture(docxEntries());
/** The same document carrying a VBA project, as a .docm renamed .docx would. */
export const docmFixture = () => zipFixture([...docxEntries(), { name: 'word/vbaProject.bin', data: new Uint8Array([0xd0, 0xcf, 0x11, 0xe0, 1, 2, 3]) }]);

const A = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
const ap = (t: string) => `<a:p><a:r><a:t>${t}</a:t></a:r></a:p>`;
const slide = (inner: string) => `${X}<p:sld ${A}><p:cSld><p:spTree>${inner}</p:spTree></p:cSld></p:sld>`;
const sp = (...ps: string[]) => `<p:sp><p:txBody>${ps.map(ap).join('')}</p:txBody></p:sp>`;
const atr = (cells: string[]) => `<a:tr>${cells.map((c) => `<a:tc><a:txBody>${ap(c)}</a:txBody></a:tc>`).join('')}</a:tr>`;
export const pptxFixture = () => zipFixture([
  { name: '[Content_Types].xml', data: `${X}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>` },
  { name: 'ppt/slides/slide10.xml', data: slide(sp('Closing slide', ARABIC_LINE)) },
  { name: 'ppt/slides/slide1.xml', data: slide(sp('Tender package', 'Porcelain tiles 600x600  120 sqm')) },
  { name: 'ppt/slides/slide2.xml', data: slide(`<p:graphicFrame><a:graphic><a:graphicData><a:tbl>${atr(HEAD)}${atr(ROW)}</a:tbl></a:graphicData></a:graphic></p:graphicFrame>`) },
]);

const O = 'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"';
const tc = (c: string) => /^\d+(\.\d+)?$/.test(c)
  ? `<table:table-cell office:value-type="float" office:value="${Number(c)}"><text:p>${c}</text:p></table:table-cell>`
  : `<table:table-cell office:value-type="string"><text:p>${c}</text:p></table:table-cell>`;
const ttr = (cells: string[]) => `<table:table-row>${cells.map(tc).join('')}<table:table-cell table:number-columns-repeated="16380"/></table:table-row>`;
const odfTable = `<table:table table:name="BOQ"><table:table-column table:number-columns-repeated="4"/>` +
  `<table:table-header-rows>${ttr(HEAD)}</table:table-header-rows>${ttr(ROW)}` +
  `<table:table-row table:number-rows-repeated="1048574"><table:table-cell table:number-columns-repeated="16384"/></table:table-row></table:table>`;
function odf(mime: string, body: string): Promise<Uint8Array> {
  return zipFixture([
    { name: 'mimetype', data: mime, store: true },
    { name: 'META-INF/manifest.xml', data: `${X}<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"><manifest:file-entry manifest:full-path="/" manifest:media-type="${mime}"/><manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/></manifest:manifest>` },
    { name: 'content.xml', data: `${X}<office:document-content ${O} office:version="1.2"><office:body>${body}</office:body></office:document-content>` },
    { name: 'styles.xml', data: `${X}<office:document-styles ${O} office:version="1.2"/>` },
  ]);
}
export const odtFixture = () => odf('application/vnd.oasis.opendocument.text', '<office:text>' +
  '<text:h text:outline-level="1">Bill of Quantities</text:h>' +
  '<text:p>Porcelain tiles<text:s/>600x600<text:tab/>120 sqm</text:p>' +
  `<text:p>${ARABIC_LINE}</text:p>${odfTable}</office:text>`);
export const odsFixture = () => odf('application/vnd.oasis.opendocument.spreadsheet', `<office:spreadsheet>${odfTable}</office:spreadsheet>`);

export async function xlsxFixture(): Promise<Uint8Array> {
  const ws = XLSX.utils.aoa_to_sheet([[...HEAD, 'Amount'], ['Porcelain tiles 600x600', 120, 'sqm', 45.5], [ARABIC_LINE, 40, 'sqm', 38]]);
  ws['E2'] = { t: 'n', v: 5460, f: 'B2*D2' };
  ws['!ref'] = 'A1:E3';
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'BOQ');
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['Total', 5460]]), 'Summary');
  return new Uint8Array(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }));
}
