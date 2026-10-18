// BLOG HTML IS SANITISED WHEN IT IS PUBLISHED (it_engineer, 19 Oct 2026; Aikido scan, BlogPost.tsx:132).
//
// A released article's body_html is model-written. `business_development.mjs bake` copies it from
// public.marketing_article into src/content/blog.json, and BlogPost.tsx renders it with
// dangerouslySetInnerHTML. The bake is where it gets published, so it is cleaned there, with an allow-list:
//   - Every allowed tag is REBUILT from its name. No attribute survives except <a href>, and only an
//     http(s), mailto:, site-relative (/...) or #fragment href.
//   - A dangerous container (script, style, iframe, ...) is dropped along with its contents.
//   - Any other tag is dropped and its text is kept.
//   - Comments are removed. A stray "<" becomes "&lt;".
// The hand-written June guides in blog.json are not baked, so they are untouched: they were reviewed in a PR,
// and their JSON-LD <script> blocks are intended.
// Tested by scripts/checks/blog_html_is_sanitised_when_published.test.mjs.

const ALLOWED = new Set(['p', 'h2', 'h3', 'h4', 'strong', 'b', 'em', 'i', 'u', 'a', 'ul', 'ol', 'li', 'br', 'blockquote',
  'table', 'thead', 'tbody', 'tr', 'th', 'td', 'code', 'div', 'span']);
const VOID = new Set(['br']);
const DROP_WITH_CONTENT = ['script', 'style', 'iframe', 'object', 'embed', 'noscript', 'template', 'svg', 'math', 'textarea', 'title', 'xmp', 'noembed', 'noframes'];

const decode = (s) => s
  .replace(/&#x([0-9a-f]+);?/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
  .replace(/&#(\d+);?/g, (_, d) => String.fromCodePoint(Number(d)))
  .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const escAttr = (s) => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** A safe href, or null. Decoded first, so an entity-encoded "javascript:" is caught; control characters and spaces are removed. */
export function safeHref(raw) {
  const v = decode(String(raw)).replace(/[\u0000- \u007f-\u009f]/g, '');
  if (/^(https?:|mailto:)/i.test(v) || /^\/(?!\/)/.test(v) || v.startsWith('#')) return v;
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
    if (tag === 'a') {
      const h = /\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/i.exec(attrs);
      const href = h ? safeHref(h[1] ?? h[2] ?? h[3]) : null;
      return href ? `<a href="${escAttr(href)}"${/^https?:/i.test(href) ? ' rel="noopener noreferrer"' : ''}>` : '<a>';
    }
    return `<${tag}>`;
  });
}
