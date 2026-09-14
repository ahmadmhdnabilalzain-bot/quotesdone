// The two passes every Arabic content document gets at render time (website audit, 14 Sep 2026).
//
// 1. arLinks — internal links keep the /ar prefix. Without it an Arabic legal page shared to a fresh
//    device (no NEXT_LOCALE cookie) opened every cross-link in English. Lifted out of ServiceDoc so the
//    legal, marketing, FAQ and contact pages apply the same rule.
// 2. isolateLatin — a Latin run inside right-to-left text is laid out right-to-left too: measured live,
//    "+971 50 931 9355" rendered as "9355 931 50 +971" on /ar/contact and /ar/privacy. Phones, emails,
//    URLs, licence/register numbers and AED figures are wrapped in <bdi dir="ltr">; a bare phone number
//    also becomes a tel: link. Same rule as ChatWidget.render(), applied to HTML instead of plain text.
//
// scripts/checks/arabic_docs_have_no_unprefixed_links.mjs runs both against every Arabic document.

// /blog is left unprefixed on purpose: blog posts are English-only, so /ar/blog/<slug> is the same
// English article under an Arabic notice.
export function arLinks(html: string): string {
  return html.replace(/href="\/(?!ar[\/"]|_next|blog)/g, 'href="/ar/');
}

const PHONE = String.raw`\+\d[\d\s-]{6,}\d`;
const RUN = new RegExp(
  [
    String.raw`https?:\/\/[^\s<]+`,
    String.raw`[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}`,
    PHONE,
    String.raw`\b800[\s-]?\d{4}\b`,
    String.raw`AED\s?\d[\d,.]*`,
    String.raw`\b\d[\d,.]*\s?AED\b`,
    String.raw`\b\d{5,}\b`,
  ].join('|'),
  'g',
);
const IS_PHONE = new RegExp('^' + PHONE + '$');
const OPAQUE = /^<(style|script|svg|textarea|bdi|code)\b/i;

// Walks the html as tags and text; only text outside an already-isolated or opaque element is touched,
// so running it twice changes nothing.
export function isolateLatin(html: string): string {
  const parts = html.split(/(<[^>]*>)/);
  const opaque: string[] = [];
  const anchors: number[] = [];
  let out = '';
  for (const p of parts) {
    if (p.startsWith('<')) {
      const close = /^<\/([a-z0-9]+)/i.exec(p);
      if (close) {
        const tag = close[1].toLowerCase();
        if (opaque.length && opaque[opaque.length - 1] === tag) opaque.pop();
        if (tag === 'a') anchors.pop();
      } else {
        const open = OPAQUE.exec(p);
        if (open && !p.endsWith('/>')) opaque.push(open[1].toLowerCase());
        if (/^<a\b/i.test(p)) anchors.push(1);
      }
      out += p;
      continue;
    }
    if (opaque.length || !p) { out += p; continue; }
    out += p.replace(RUN, (m) => {
      if (IS_PHONE.test(m) && !anchors.length) {
        return `<a href="tel:${m.replace(/[\s-]/g, '')}" dir="ltr"><bdi dir="ltr">${m}</bdi></a>`;
      }
      return `<bdi dir="ltr">${m}</bdi>`;
    });
  }
  return out;
}

export function arDoc(html: string, locale: string): string {
  return locale === 'ar' ? isolateLatin(arLinks(html)) : html;
}
