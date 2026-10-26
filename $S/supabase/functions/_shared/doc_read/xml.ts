// xml — a small, SAFE XML reader for the document formats doc_read opens (OOXML, ODF, GAEB DA XML).
//
// WHY NOT A LIBRARY. Deno has no DOMParser, and every full XML parser worth using implements DTDs —
// which is exactly the attack surface a customer-supplied document brings: XXE (an entity that reads
// a file or a URL) and "billion laughs" (entities that expand exponentially). This reader has no DTD
// support at all. A <!DOCTYPE ...> block, internal subset included, is skipped unread; the only
// references ever decoded are the five predefined entities and numeric character references. Any
// other &name; stays literal text, so a hostile entity is inert rather than refused or expanded.
//
// CEILINGS. 500,000 nodes and 256 levels of nesting, then it throws (the caller reports the file as
// too complex). Mismatched close tags are tolerated by popping to the nearest open tag of that name,
// because real-world OOXML from odd writers is not always tidy.
export type XmlNode = { name: string; attrs: Record<string, string>; children: (XmlNode | string)[] };

const MAX_NODES = 500_000;
const MAX_DEPTH = 256;

export function decodeEntities(s: string): string {
  if (!s.includes('&')) return s;
  return s.replace(/&(#x[0-9a-fA-F]+|#\d+|lt|gt|amp|quot|apos);/g, (_m, e: string) => {
    switch (e) {
      case 'lt': return '<';
      case 'gt': return '>';
      case 'amp': return '&';
      case 'quot': return '"';
      case 'apos': return "'";
    }
    const cp = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
    return Number.isFinite(cp) && cp > 0 && cp <= 0x10ffff ? String.fromCodePoint(cp) : '';
  });
}

/** The local name of a possibly namespaced tag: 'w:t' -> 't'. */
export const local = (n: string) => n.slice(n.indexOf(':') + 1);

function findTagEnd(s: string, from: number): number {
  let q = '';
  for (let j = from; j < s.length; j++) {
    const c = s[j];
    if (q) { if (c === q) q = ''; }
    else if (c === '"' || c === "'") q = c;
    else if (c === '>') return j;
  }
  return -1;
}

export function parseXml(xml: string): XmlNode {
  const root: XmlNode = { name: '#root', attrs: {}, children: [] };
  const stack: XmlNode[] = [root];
  const top = () => stack[stack.length - 1];
  const pushText = (t: string) => { if (t) top().children.push(decodeEntities(t)); };
  let nodes = 0, i = 0;
  const n = xml.length;
  while (i < n) {
    const lt = xml.indexOf('<', i);
    if (lt < 0) { pushText(xml.slice(i)); break; }
    if (lt > i) pushText(xml.slice(i, lt));
    if (xml.startsWith('<!--', lt)) { const e = xml.indexOf('-->', lt + 4); i = e < 0 ? n : e + 3; continue; }
    if (xml.startsWith('<![CDATA[', lt)) {
      const e = xml.indexOf(']]>', lt + 9);
      top().children.push(xml.slice(lt + 9, e < 0 ? n : e));
      i = e < 0 ? n : e + 3; continue;
    }
    if (xml.startsWith('<?', lt)) { const e = xml.indexOf('?>', lt + 2); i = e < 0 ? n : e + 2; continue; }
    if (xml.startsWith('<!', lt)) {
      // DOCTYPE, internal subset and all: skipped, never interpreted. This is the XXE defence.
      let depth = 0, j = lt + 2;
      for (; j < n; j++) { const c = xml[j]; if (c === '[') depth++; else if (c === ']') depth--; else if (c === '>' && depth <= 0) break; }
      i = j + 1; continue;
    }
    const gt = findTagEnd(xml, lt + 1);
    if (gt < 0) break;
    const raw = xml.slice(lt + 1, gt);
    i = gt + 1;
    if (raw.startsWith('/')) {
      const name = raw.slice(1).trim();
      for (let k = stack.length - 1; k > 0; k--) if (stack[k].name === name) { stack.length = k; break; }
      continue;
    }
    const selfClose = raw.endsWith('/');
    const body = selfClose ? raw.slice(0, -1) : raw;
    const m = body.match(/^([^\s/>]+)/);
    if (!m) continue;
    const node: XmlNode = { name: m[1], attrs: {}, children: [] };
    const re = /([^\s=]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
    const rest = body.slice(m[1].length);
    let a: RegExpExecArray | null;
    while ((a = re.exec(rest))) node.attrs[a[1]] = decodeEntities(a[2] ?? a[3] ?? '');
    if (++nodes > MAX_NODES) throw new Error('xml_too_large');
    top().children.push(node);
    if (!selfClose) {
      if (stack.length >= MAX_DEPTH) throw new Error('xml_too_deep');
      stack.push(node);
    }
  }
  return root;
}

/** Every descendant, depth-first in document order, whose LOCAL name is one of `names`. */
export function findAll(node: XmlNode, ...names: string[]): XmlNode[] {
  const want = new Set(names);
  const out: XmlNode[] = [];
  const walk = (x: XmlNode) => {
    for (const c of x.children) if (typeof c !== 'string') { if (want.has(local(c.name))) out.push(c); walk(c); }
  };
  walk(node);
  return out;
}

/** The first direct child with this local name. */
export function child(node: XmlNode, name: string): XmlNode | undefined {
  for (const c of node.children) if (typeof c !== 'string' && local(c.name) === name) return c;
  return undefined;
}

/** All text beneath a node, concatenated in document order. */
export function textOf(node: XmlNode): string {
  let s = '';
  const walk = (x: XmlNode) => { for (const c of x.children) { if (typeof c === 'string') s += c; else walk(c); } };
  walk(node);
  return s;
}
