// email.fixtures — .eml files built in memory for the email reader's tests and the before/after audit.
//
// Every address is @example.invalid and every name is ZZ DEMO, so no fixture can reach a real person.
// The content is the smallest that proves the reader: a BOQ line in the body, an Arabic line sent
// quoted-printable (with soft line breaks), a base64 CSV attachment, a folded header and an RFC 2047
// subject; the nested fixture attaches that whole message inside another as message/rfc822.

export const BOQ_LINE = 'Porcelain tiles 600x600 120 sqm';
export const ARABIC_LINE = 'بلاط بورسلين 600x600 الكمية 120 متر مربع';
export const SUBJECT = 'طلب عرض سعر BOQ';
export const BOQ_CSV = new TextEncoder().encode('Description,Qty,Unit\nPorcelain tiles 600x600,120,sqm\nGypsum ceiling,85,sqm\n');

const binStr = (b: Uint8Array) => String.fromCharCode(...b);
const utf8 = (s: string) => new TextEncoder().encode(s);
const b64Lines = (b: Uint8Array) => btoa(binStr(b)).replace(/.{1,76}/g, '$&\r\n');

/** Quoted-printable with soft breaks before 76 columns, never splitting an =XX escape. */
function qp(s: string): string {
  const toks = Array.from(utf8(s), (c) => (c >= 33 && c <= 126 && c !== 61) || c === 32 ? String.fromCharCode(c) : '=' + c.toString(16).toUpperCase().padStart(2, '0'));
  let line = '', out = '';
  for (const t of toks) { if (line.length + t.length > 72) { out += line + '=\r\n'; line = ''; } line += t; }
  return out + line;
}

/** The message as text, so the nested fixture can embed it verbatim. */
export function emlText(): string {
  return [
    'From: ZZ DEMO Buyer <buyer@example.invalid>',
    'To: rfq@example.invalid',
    `Subject: =?UTF-8?B?${btoa(binStr(utf8(SUBJECT)))}?=`,
    'MIME-Version: 1.0',
    'Content-Type: multipart/mixed;',
    '\tboundary="==b1=="',
    '',
    'This is a multi-part message in MIME format.',
    '--==b1==',
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: 7bit',
    '',
    'Please quote the following.',
    BOQ_LINE,
    '--==b1==',
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: quoted-printable',
    '',
    qp(ARABIC_LINE),
    '--==b1==',
    'Content-Type: text/csv; name="boq.csv"',
    'Content-Disposition: attachment; filename="boq.csv"',
    'Content-Transfer-Encoding: base64',
    '',
    b64Lines(BOQ_CSV),
    '--==b1==--',
    '',
  ].join('\r\n');
}

export const emlFixture = (): Uint8Array => utf8(emlText());

export function emlNestedFixture(): Uint8Array {
  return utf8([
    'From: ZZ DEMO Forwarder <fwd@example.invalid>',
    'Subject: Fwd: BOQ',
    'MIME-Version: 1.0',
    'Content-Type: multipart/mixed; boundary="outer"',
    '',
    '--outer',
    'Content-Type: text/plain; charset=utf-8',
    '',
    'See the attached request.',
    '--outer',
    'Content-Type: message/rfc822',
    'Content-Disposition: attachment; filename="inner.eml"',
    '',
    emlText(),
    '--outer--',
    '',
  ].join('\r\n'));
}
