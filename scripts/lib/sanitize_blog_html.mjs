// BLOG HTML IS SANITISED WHEN IT IS PUBLISHED (it_engineer, 19 Oct 2026; Aikido scan, BlogPost.tsx:132).
//
// A released article's body_html is model-written. `business_development.mjs bake` copies it from
// public.marketing_article into src/content/blog.json, and BlogPost.tsx renders it with
// dangerouslySetInnerHTML. The bake is where it gets published, so it is cleaned there, with an allow-list:
//   - Every allowed tag is REBUILT from its name, so the only attributes are the ones written back here:
//       <a href>: http(s), mailto:, site-relative (/...) or #fragment only;
//       <img src alt>: src must be https or site-relative, otherwise the image is dropped;
//       dir="rtl" or dir="ltr" on any allowed tag.
//   - "//", "/\" and "\" are refused, because a browser reads each of them as another site.
//   - A dangerous container (script, style, iframe, svg, ...) is dropped along with its contents.
//   - Any other tag is dropped and its text is kept.
//   - Comments are removed. A stray "<" becomes "&lt;".
// The hand-written June guides in blog.json are not baked, so they are untouched: they were reviewed in a PR,
// and their JSON-LD <script> blocks are intended.
// Tested by scripts/checks/blog_html_is_sanitised_when_published.test.mjs.

const ALLOWED = new Set(['p', 'h2', 'h3', 'h4', 'strong', 'b', 'em', 'i', 'u', 'a', 'ul', 'ol', 'li', 'br', 'blockquote',
  'table', 'thead', 'tbody', 'tr', 'th', 'td', 'code', 'div', 'span', 'img']);
const VOID = new Set(['br', 'img']);
const DROP_WITH_CONTENT = ['script', 'style', 'iframe', 'object', 'embed', 'noscript', 'template', 'svg', 'math', 'textarea', 'title', 'xmp', 'noembed', 'noframes'];

const decode = (s) => s
  .replace(/&#x([0-9a-f]+);?/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
  .replace(/&#(\d+);?/g, (_, d) => String.fromCodePoint(Number(d)))
  .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const escAttr = (s) => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** The value of one attribute in a tag's attribute text, or null. */
const attr = (attrs, name) => {
  const m = new RegExp(`(?:^|\\s)${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'>]+))`, 'i').exec(attrs);
  return m ? (m[1] ?? m[2] ?? m[3]) : null;
};

/** A safe href, or null. Decoded first, so an entity-encoded "javascript:" is caught; control characters and spaces are removed. */
export function safeHref(raw) {
  const v = decode(String(raw)).replace(/[\u0000- \u007f-\u009f]/g, '');
  if (/^(https?:|mailto:)/i.test(v) || /^\/(?![/\\])/.test(v) || v.startsWith('#')) return v;
  return null;
}

export function sanitizeBlogHtml(html) {
  let s = String(html ?? '');
  s = s.replace(/<!--[\s\S]*?(-->|$)/g, '');
  for (const t of DROP_WITH_CONTENT) s = s.replace(new RegExp(`<${t}\\b[\\s\\S]*?(<\\/${t}\\s*>|$)`, 'gi'), '');
  return s.replace(/<(\/?)([a-zA-Z][a-zA-Z0-9]*)\b([^>]*)>|</g, (m, close, name, attrs) => {
    if (name === undefined) return '&lt;';                       // a "<" that does not open a tag
    const tag = name.toLowerCase();
    if (!ALLOWED.has(tag)) return '';
    if (close) return VOID.has(tag) ? '' : `</${tag}>`;
    const dir = /^(rtl|ltr)$/i.exec(attr(attrs, 'dir') ?? '')?.[1]?.toLowerCase();
    const d = dir ? ` dir="${dir}"` : '';
    if (tag === 'img') {
      const src = safeHref(attr(attrs, 'src') ?? '');
      if (!src || !/^(https:|\/)/i.test(src)) return '';        // an image only from https or this site
      return `<img src="${escAttr(src)}" alt="${escAttr(decode(attr(attrs, 'alt') ?? ''))}"${d}>`;
    }
    if (tag === 'a') {
      const raw = attr(attrs, 'href');
      const href = raw == null ? null : safeHref(raw);
      return href ? `<a href="${escAttr(href)}"${/^https?:/i.test(href) ? ' rel="noopener noreferrer"' : ''}${d}>` : `<a${d}>`;
    }
    return `<${tag}${d}>`;
  });
}
