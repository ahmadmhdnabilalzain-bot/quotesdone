// email — reads an RFC 822 / 5322 message with MIME (.eml): headers, body text, and attachments.
//
// WHY (14 Sep 2026). Customers forward RFQs as saved emails: the BOQ is a line in the body, a CSV or a
// PDF attached, or a whole earlier email attached inside this one. Before this reader an .eml upload
// was stored unread. Every model route is on hold, so this is plain parsing.
//
// WHAT IT READS. Headers unfolded; RFC 2047 encoded words (=?charset?B|Q?...?=) decoded in Subject,
// From and filenames; RFC 2231 filename*=charset''... decoded. multipart/* is walked by boundary, at
// most 8 levels of nesting and 200 parts. Transfer encodings base64, quoted-printable, 7bit and 8bit;
// charsets through TextDecoder (utf-8, iso-8859-1, windows-1252, windows-1256 and every other WHATWG
// label). text/plain is preferred; text/html is used, tags stripped and script/style dropped, only
// when no plain part exists. An attachment (Content-Disposition: attachment, or any part other than
// the text body that carries a filename) goes to ctx.readChild; message/rfc822 is read here as an eml.
//
// WHAT IT NEVER DOES. It does not scrub the sender (the caller does), follow a link, load a remote
// image, or execute anything. Attachments past 50, parts past 200 and nesting past LIMITS.maxDepth are
// dropped with a note — never silently. Content-Transfer-Encoding: binary is read as if it were 8bit
// after CRLF normalisation, which can corrupt a truly binary part (rare in mail; noted here, not fixed).
import { decodeEntities } from './xml.ts';
import { capText, empty, LIMITS, ok, refuse, type Extracted, type ReadContext, type ReadResult } from './types.ts';

export const MAX_ATTACHMENTS = 50;
export const MAX_PARTS = 200;
const MAX_NEST = 8;

type Reader = (bytes: Uint8Array, filename: string, depth: number) => Promise<ReadResult>;

/** Bytes <-> a binary string of the same length (one char per byte), so byte offsets never shift. */
const bin = (b: Uint8Array) => { let s = ''; for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode(...b.subarray(i, i + 0x8000)); return s; };
const unbin = (s: string) => Uint8Array.from(s, (c) => c.charCodeAt(0) & 0xff);
const b64 = (s: string) => { try { return atob(s.replace(/[^A-Za-z0-9+/]/g, '')); } catch { return ''; } };
const hexBytes = (s: string) => s.replace(/=([0-9A-Fa-f]{2})/g, (_m, h: string) => String.fromCharCode(parseInt(h, 16)));

/** Decode with a declared charset; an unknown label falls back to UTF-8 rather than failing the read. */
export function decodeText(b: Uint8Array, charset = 'utf-8'): string {
  try { return new TextDecoder(charset.trim().toLowerCase() || 'utf-8').decode(b); } catch { return new TextDecoder().decode(b); }
}

/** RFC 2047 encoded words; whitespace between two adjacent encoded words is dropped, as the RFC says. */
export function decodeWords(s: string): string {
  return s.replace(/(=\?[^?\s]+\?[bBqQ]\?[^?\s]*\?=)\s+(?==\?)/g, '$1')
    .replace(/=\?([^?\s]+)\?([bBqQ])\?([^?\s]*)\?=/g, (_m, cs: string, enc: string, data: string) =>
      decodeText(unbin(enc.toUpperCase() === 'B' ? b64(data) : hexBytes(data.replace(/_/g, ' '))), cs.split('*')[0]));
}

/** HTML to text: script/style/head dropped, block ends become newlines, cells become tabs. */
export function stripHtml(h: string): string {
  return decodeEntities(h
    .replace(/<(script|style|head)\b[\s\S]*?<\/\1\s*>/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<br\b[^>]*>|<\/(?:p|div|tr|li|h[1-6]|table)\s*>/gi, '\n')
    .replace(/<\/t[dh]\s*>/gi, '\t')
    .replace(/<[^>]*>/g, '')
    .replace(/&nbsp;/gi, ' '))
    .replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}

/**
 * The one way a container (eml, msg) hands an attachment on: capped at MAX_ATTACHMENTS, refused past
 * LIMITS.maxDepth, a reader error becomes a note instead of failing the whole message.
 */
export function attacher(ctx: ReadContext, out: Extracted) {
  let n = 0;
  const once = (s: string) => { if (!out.notes.includes(s)) out.notes.push(s); };
  return async (bytes: Uint8Array, name: string, reader: Reader | undefined = ctx.readChild): Promise<void> => {
    if (++n > MAX_ATTACHMENTS) return once(`only the first ${MAX_ATTACHMENTS} attachments were read`);
    if (ctx.depth >= LIMITS.maxDepth) return once(`attachments nested more than ${LIMITS.maxDepth} levels deep were not read`);
    if (!reader) return once('attachments were not read (no reader was given for them)');
    let r: ReadResult;
    try { r = await reader(bytes, name, ctx.depth + 1); } catch (e) { out.notes.push(`attachment ${name} could not be read: ${(e as Error).message}`); return; }
    if (!r.ok) { out.notes.push(`attachment ${name} was not read: ${r.error}`); return; }
    const { ok: _ok, ...doc } = r;
    out.children.push({ name, doc });
  };
}

type Entity = { headers: Map<string, string>; body: string };

function splitEntity(raw: string): Entity {
  const i = raw.startsWith('\n') ? 0 : raw.indexOf('\n\n');
  const head = i < 0 ? raw : raw.slice(0, i);
  const body = i < 0 ? '' : raw.slice(i + (raw.startsWith('\n') ? 1 : 2));
  const headers = new Map<string, string>();
  for (const line of head.replace(/\n[ \t]+/g, ' ').split('\n')) {
    const c = line.indexOf(':');
    if (c <= 0 || /\s/.test(line.slice(0, c))) continue;
    const k = line.slice(0, c).toLowerCase();
    if (!headers.has(k)) headers.set(k, line.slice(c + 1).trim());
  }
  return { headers, body };
}

/** 'text/plain; charset="utf-8"' -> { value: 'text/plain', p: { charset: 'utf-8' } }. */
function params(v: string): { value: string; p: Record<string, string> } {
  const p: Record<string, string> = {};
  const re = /;\s*([^=;\s]+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^;]*))/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(v))) {
    let k = m[1].toLowerCase(), val = (m[2] ?? m[3] ?? '').trim();
    if (k.endsWith('*')) { // RFC 2231: charset'lang'percent-encoded
      k = k.slice(0, -1);
      const x = /^([^']*)'[^']*'(.*)$/.exec(val);
      if (x) val = decodeText(unbin(x[2].replace(/%([0-9A-Fa-f]{2})/g, (_s, h: string) => String.fromCharCode(parseInt(h, 16)))), x[1] || 'utf-8');
    }
    if (!(k in p)) p[k] = val;
  }
  return { value: v.split(';')[0].trim().toLowerCase(), p };
}

function decodeCte(body: string, cte: string): Uint8Array {
  if (cte === 'base64') return unbin(b64(body));
  if (cte === 'quoted-printable') return unbin(hexBytes(body.replace(/=[ \t]*\n/g, '')));
  return unbin(body);
}

type Walk = { parts: number; capped: boolean; deep: boolean; plain: string[]; html: string[]; skipped: number };

async function walk(raw: string, nest: number, st: Walk, add: ReturnType<typeof attacher>, emlReader: Reader): Promise<void> {
  if (++st.parts > MAX_PARTS) { st.capped = true; return; }
  const { headers, body } = splitEntity(raw);
  const ct = params(headers.get('content-type') ?? 'text/plain');
  const type = ct.value || 'text/plain';
  if (type.startsWith('multipart/')) {
    const b = ct.p.boundary;
    if (!b) { st.plain.push(body); return; }
    if (nest >= MAX_NEST) { st.deep = true; return; }
    const chunks = ('\n' + body).split('\n--' + b);
    for (let i = 1; i < chunks.length && !st.capped; i++) {
      const c = chunks[i];
      if (c.startsWith('--')) break;
      const nl = c.indexOf('\n');
      if (nl >= 0) await walk(c.slice(nl + 1), nest + 1, st, add, emlReader);
    }
    return;
  }
  const disp = params(headers.get('content-disposition') ?? '');
  const name = decodeWords(disp.p.filename ?? ct.p.name ?? '');
  const bytes = decodeCte(body, (headers.get('content-transfer-encoding') ?? '').trim().toLowerCase());
  if (type === 'message/rfc822') return add(bytes, name || 'message.eml', emlReader);
  if ((type === 'text/plain' || type === 'text/html') && disp.value !== 'attachment') {
    (type === 'text/plain' ? st.plain : st.html).push(decodeText(bytes, ct.p.charset).trim());
    return;
  }
  if (disp.value === 'attachment' || name) return add(bytes, name || 'attachment', undefined);
  st.skipped++;
}

export async function readEml(bytes: Uint8Array, ctx: ReadContext): Promise<ReadResult> {
  const raw = bin(bytes).replace(/\r\n?/g, '\n');
  const top = splitEntity(raw);
  if (!top.headers.size) return refuse('unreadable_file', 'no RFC 822 headers found');
  const out = empty('eml');
  const add = attacher(ctx, out);
  const emlReader: Reader = (b, filename, depth) => readEml(b, { ...ctx, filename, depth });
  const st: Walk = { parts: 0, capped: false, deep: false, plain: [], html: [], skipped: 0 };
  await walk(raw, 0, st, add, emlReader);

  const subject = decodeWords(top.headers.get('subject') ?? '');
  const from = decodeWords(top.headers.get('from') ?? '');
  const body = st.plain.length ? st.plain.join('\n\n') : st.html.map(stripHtml).join('\n\n');
  const head = [subject && `Subject: ${subject}`, from && `From: ${from}`].filter(Boolean).join('\n');
  const parts: string[] = [];
  if (!capText(parts, (head ? head + '\n\n' : '') + body, { n: 0 })) out.notes.push(`text truncated at ${LIMITS.maxTextChars} characters`);
  out.text = parts.join('');
  if (st.capped) out.notes.push(`only the first ${MAX_PARTS} MIME parts were read`);
  if (st.deep) out.notes.push(`multipart nesting deeper than ${MAX_NEST} levels was not read`);
  if (st.skipped) out.notes.push(`${st.skipped} inline part(s) without a filename (such as embedded images) were not read`);
  return ok(out);
}
