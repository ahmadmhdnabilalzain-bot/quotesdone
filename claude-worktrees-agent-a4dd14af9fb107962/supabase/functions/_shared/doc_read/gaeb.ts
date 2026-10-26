// gaeb — bill-of-quantities items read off a GAEB DA XML 3.x file (X81-X86), with no model (14 Sep 2026).
//
// WHY. GAEB DA XML is the German/European standard for exchanging a priced or unpriced BoQ, and
// European consultants and contractors working in the UAE send tenders in it. Every item already
// states its ordinal, quantity, unit and outline text; before this reader the file was stored unread.
//
// WHAT IT READS. GAEB > Award > BoQ > BoQBody, recursively: BoQCtgy (RNoPart, LblTx) nesting
// BoQBody, down to Itemlist > Item (RNoPart) with Qty, QU and Description > CompleteText >
// OutlineText > OutlTxt > TextOutlTxt (DetailTxt, then any Description text, as fallbacks). Each item
// becomes one Qty: section = the category labels, basis = "GAEB item 01.02.0010". The exchange phase
// (DP: 81 specification ... 86 contract award) goes to notes. Namespace prefixes are ignored.
//
// WHAT IT NEVER DOES. It never reads UP (unit price), IT (item total), Totals or any other price
// element — not into quantities, text or notes; it only says prices were present and not read,
// because this output is shown to competing suppliers. Old GAEB 90/2000 text formats are refused.
// Identity is NOT scrubbed here; the caller does that.
import { child, findAll, local, parseXml, type XmlNode } from './xml.ts';
import { capText, empty, LIMITS, ok, refuse, type Qty, type ReadContext, type ReadResult } from './types.ts';

const PHASE: Record<string, string> = {
  '81': 'X81 specification', '82': 'X82 cost estimate', '83': 'X83 bid request', '84': 'X84 bid',
  '85': 'X85 alternative bid', '86': 'X86 contract award',
};
// Price-bearing element names in DA XML 3.x. Presence is detected; content is never read.
const PRICE = ['UP', 'IT', 'Total', 'Totals', 'TotalNet', 'TotalGross', 'UPComp1', 'UPComp2', 'UPComp3', 'UPComp4', 'UPComp5', 'UPComp6', 'DiscountPcnt', 'VAT'];

/** Text beneath a node with paragraph breaks kept as spaces; whitespace collapsed. */
function plain(node: XmlNode | undefined): string {
  if (!node) return '';
  let s = '';
  const walk = (x: XmlNode) => {
    for (const c of x.children) {
      if (typeof c === 'string') s += c;
      else { if (PRICE.includes(local(c.name))) continue; walk(c); if (/^(p|br|div)$/.test(local(c.name))) s += ' '; }
    }
  };
  walk(node);
  return s.replace(/\s+/g, ' ').trim();
}

const path = (n: XmlNode | undefined, ...names: string[]) => { let x = n; for (const k of names) x = x && child(x, k); return x; };

export async function readGaeb(bytes: Uint8Array, _ctx: ReadContext): Promise<ReadResult> {
  const prolog = new TextDecoder('latin1').decode(bytes.subarray(0, 200));
  const enc = /encoding\s*=\s*["']([^"']+)/i.exec(prolog)?.[1]?.toLowerCase() ?? 'utf-8';
  let src: string;
  try { src = new TextDecoder(enc === 'utf-8' || enc === 'utf8' ? 'utf-8' : enc).decode(bytes); }
  catch { src = new TextDecoder('utf-8').decode(bytes); }
  let root: XmlNode;
  try { root = parseXml(src); } catch (e) { return refuse('gaeb_unreadable', `XML too large or too deep (${(e as Error).message}).`); }
  const gaeb = findAll(root, 'GAEB')[0];
  if (!gaeb) return refuse('gaeb_unreadable', 'Not a GAEB DA XML file (no GAEB root element). GAEB 90/2000 text formats are not read.');

  const notes: string[] = [];
  const dp = plain(findAll(gaeb, 'DP')[0]);
  const phase = PHASE[dp] ?? (dp ? `DP ${dp}` : 'phase not stated');
  const pricesPresent = findAll(gaeb, ...PRICE).length > 0;
  notes.push(pricesPresent ? `${phase}: prices present in the file were not read.` : `${phase}.`);

  const text: string[] = [], used = { n: 0 };
  const addText = (s: string) => { if (s) capText(text, s + '\n', used); };
  const info = findAll(gaeb, 'BoQInfo')[0];
  addText(plain(info && child(info, 'Name'))); addText(plain(info && child(info, 'LblTx')));

  const quantities: Qty[] = [];
  let items = 0, dropped = 0;
  const walkBody = (body: XmlNode, labels: string[], rno: string[]) => {
    for (const c of body.children) {
      if (typeof c === 'string') continue;
      const nm = local(c.name);
      if (nm === 'BoQCtgy') {
        const lbl = plain(child(c, 'LblTx'));
        addText(lbl);
        const sub = child(c, 'BoQBody');
        if (sub) walkBody(sub, [...labels, lbl || c.attrs.RNoPart || '?'], [...rno, c.attrs.RNoPart ?? '']);
      } else if (nm === 'Itemlist') {
        for (const it of c.children) {
          if (typeof it === 'string' || local(it.name) !== 'Item') continue;
          items++;
          const ord = [...rno, it.attrs.RNoPart ?? ''].filter(Boolean).join('.');
          const desc = child(it, 'Description');
          const outline = plain(path(desc, 'CompleteText', 'OutlineText')) || plain(path(desc, 'CompleteText', 'DetailTxt')) || plain(desc);
          addText(outline);
          const qtyTxt = plain(child(it, 'Qty')).replace(',', '.');
          const qty = qtyTxt && Number.isFinite(+qtyTxt) ? +qtyTxt : null;
          if (quantities.length >= LIMITS.maxQuantities) { dropped++; continue; }
          quantities.push({
            section: labels.join(' > ') || 'BoQ',
            description: `${outline || '(no text)'} (${ord})`,
            qty, unit: plain(child(it, 'QU')), basis: `GAEB item ${ord}`, confidence: 'medium',
          });
        }
      }
    }
  };
  for (const boq of findAll(gaeb, 'BoQ')) { const b = child(boq, 'BoQBody'); if (b) walkBody(b, [], []); }

  if (!items) notes.push('No BoQ items were found in the file.');
  if (dropped) notes.push(`${items} items found; the first ${LIMITS.maxQuantities} are kept.`);
  return ok({ ...empty('gaeb', notes), text: text.join('').trimEnd(), quantities });
}
