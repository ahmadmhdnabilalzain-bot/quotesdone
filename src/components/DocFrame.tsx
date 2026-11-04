/**
 * DOC FRAME — the Sealed frame around every page whose copy is CMS HTML (legal, about, how-we-verify,
 * services, FAQ, contact). The HTML stays the single source of the words; this file only lifts its
 * hero out (so the page opens on the brand's own hero instead of a styled div) and anchors its
 * headings (so long documents get a contents rail). Server-safe: no hooks, so the client FAQ and
 * contact pages import it too. Parsing is by tag scan on our own content files, never user input.
 */
import type { ReactNode } from 'react';
import { Kicker } from '@/components/ui/sealed';
import { cn } from '@/lib/utils';

/** End index (exclusive) of the element that opens at `start`, balancing tags of the same name. */
function elementEnd(html: string, start: number): number {
  const name = /^<([a-z0-9]+)/i.exec(html.slice(start))?.[1];
  if (!name) return -1;
  const re = new RegExp(`<(/?)${name}\\b[^>]*>`, 'gi');
  re.lastIndex = start;
  let depth = 0;
  for (let m = re.exec(html); m; m = re.exec(html)) {
    depth += m[1] ? -1 : 1;
    if (depth === 0) return m.index + m[0].length;
  }
  return -1;
}

/** The first element carrying `cls` in its class list: its outer html and the html around it. */
export function takeByClass(html: string, cls: string): { el: string; before: string; after: string } | null {
  const m = new RegExp(`<[a-z0-9]+\\b[^>]*class="(?:[^"]*\\s)?${cls}(?:\\s[^"]*)?"[^>]*>`, 'i').exec(html);
  if (!m) return null;
  const end = elementEnd(html, m.index);
  if (end < 0) return null;
  return { el: html.slice(m.index, end), before: html.slice(0, m.index), after: html.slice(end) };
}

const inner = (el: string) => el.replace(/^<[^>]+>/, '').replace(/<\/[a-z0-9]+>\s*$/i, '');
const firstTag = (html: string, tag: string) => {
  const m = new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)</${tag}>`, 'i').exec(html);
  return m ? m[1].trim() : null;
};
export const textOf = (html: string) => html.replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/\s+/g, ' ').trim();

export type HeroParts = {
  kicker: string | null; // crumb or eyebrow html
  title: string | null; // h1 inner html
  lead: string | null; // first paragraph inner html
  actions: { href: string; label: string; ghost: boolean }[];
  extra: string | null; // the FAQ search box
  rest: string; // everything after the hero
};

/** Lift the `.hero` block out of a marketing document. */
export function splitHero(html: string): HeroParts {
  const hit = takeByClass(html, 'hero');
  if (!hit) return { kicker: null, title: null, lead: null, actions: [], extra: null, rest: html };
  const h = hit.el;
  const crumb = takeByClass(h, 'crumb') ?? takeByClass(h, 'eyebrow');
  const search = takeByClass(h, 'search');
  const actions = [...h.matchAll(/<a\b[^>]*class="(btn[^"]*)"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>|<a\b[^>]*href="([^"]+)"[^>]*class="(btn[^"]*)"[^>]*>([\s\S]*?)<\/a>/gi)]
    .map((m) => ({ cls: m[1] ?? m[5], href: m[2] ?? m[4], label: textOf(m[3] ?? m[6]) }))
    .map((a) => ({ href: a.href, label: a.label.replace(/\s*[→←]\s*$/, ''), ghost: /\bo\b/.test(a.cls) }));
  return {
    kicker: crumb ? inner(crumb.el) : null,
    title: firstTag(h, 'h1'),
    lead: firstTag(h, 'p'),
    actions,
    extra: search ? search.el : null,
    // an empty wrapper left behind by the lift (FAQ's .fwrap) is harmless; the rest keeps its classes
    rest: hit.before + hit.after,
  };
}

export type Heading = { id: string; text: string };
/** Give every <tag> an id (after `skip` of them) and return the list for a contents rail. */
export function anchorHeadings(html: string, tag: string, prefix: string, skip = 0): { html: string; list: Heading[] } {
  const list: Heading[] = [];
  let n = 0;
  const out = html.replace(new RegExp(`<${tag}(\\s[^>]*)?>([\\s\\S]*?)</${tag}>`, 'gi'), (whole, attrs: string | undefined, body: string) => {
    n += 1;
    if (n <= skip || (attrs && /\sid=/.test(attrs))) return whole;
    const id = `${prefix}-${list.length + 1}`;
    list.push({ id, text: textOf(body) });
    return `<${tag} id="${id}"${attrs ?? ''}>${body}</${tag}>`;
  });
  return { html: out, list };
}

/** The sub-page hero: ruled grid, one teal key light, kicker, display title, lead, actions, aside. */
export function PageHero({ kicker, title, lead, actions, aside, children, center, className }: {
  kicker?: ReactNode; title: ReactNode; lead?: ReactNode; actions?: ReactNode; aside?: ReactNode; children?: ReactNode; center?: boolean; className?: string;
}) {
  return (
    <section className={cn('qd-keylight relative overflow-hidden border-b border-line', className)}>
      <span className="grid-tech" aria-hidden />
      <div className={cn('container-x relative grid items-center gap-12 pb-16 pt-16 md:pb-20 md:pt-24', aside && 'lg:grid-cols-[1.08fr_.92fr]')}>
        <div className={cn('min-w-0', center && 'mx-auto max-w-[860px] text-center')}>
          {kicker ? <Kicker>{kicker}</Kicker> : null}
          <h1 className={cn('mt-6 text-balance font-head text-display-sm text-white md:text-display', center ? 'mx-auto max-w-[20ch]' : 'max-w-[18ch]')}>{title}</h1>
          {lead ? <p className={cn('mt-6 max-w-[58ch] text-pretty text-lead text-muted', center && 'mx-auto')}>{lead}</p> : null}
          {actions ? <div className={cn('mt-9 flex flex-wrap gap-3', center && 'justify-center')}>{actions}</div> : null}
          {children}
        </div>
        {aside ? <div className="relative min-w-0">{aside}</div> : null}
      </div>
    </section>
  );
}

/** Sticky contents rail for long documents; a closed <details> on narrow screens. */
export function ContentsRail({ title, list, footer }: { title: string; list: Heading[]; footer?: ReactNode }) {
  if (!list.length && !footer) return null;
  const links = (
    <ol className="flex flex-col gap-0.5">
      {list.map((h, i) => (
        <li key={h.id}>
          <a href={`#${h.id}`} className="group flex gap-3 rounded-chip px-2 py-1.5 text-small leading-snug text-muted transition-colors duration-base hover:bg-teal-light/5 hover:text-white">
            <span className="tabular w-5 shrink-0 font-mono text-label text-faint group-hover:text-teal-light">{String(i + 1).padStart(2, '0')}</span>
            <span className="min-w-0">{h.text.replace(/^\d+(\.\d+)*[.)]?\s*/, '')}</span>
          </a>
        </li>
      ))}
    </ol>
  );
  return (
    <>
      <details className="qd-panel group/rail p-4 lg:hidden">
        <summary className="flex cursor-pointer list-none items-center justify-between font-mono text-label uppercase tracking-caps text-faint">
          {title}<span aria-hidden className="text-teal-light transition-transform duration-base group-open/rail:rotate-45">+</span>
        </summary>
        <div className="mt-3 border-t border-line pt-3">{links}{footer}</div>
      </details>
      <nav aria-label={title} className="sticky top-[92px] hidden max-h-[calc(100vh-120px)] overflow-y-auto pe-2 lg:block">
        <div className="mb-3 px-2 font-mono text-label uppercase tracking-caps text-faint">{title}</div>
        {links}
        {footer}
      </nav>
    </>
  );
}

/** Closing call to action shared by the doc pages. */
export function CtaPanel({ kicker, title, body, children }: { kicker?: ReactNode; title: ReactNode; body?: ReactNode; children?: ReactNode }) {
  return (
    <section className="container-x py-beat-s md:py-beat">
      <div className="qd-env qd-env-lg qd-grain relative overflow-hidden px-6 py-14 text-center md:px-12 md:py-20">
        <span className="grid-tech grid-tech-sm opacity-60" aria-hidden />
        <div className="relative mx-auto max-w-[680px]">
          {kicker ? <Kicker>{kicker}</Kicker> : null}
          <h2 className="mt-5 text-balance font-head text-h2 text-white">{title}</h2>
          {body ? <p className="mx-auto mt-4 max-w-[52ch] text-lead text-muted">{body}</p> : null}
          {children ? <div className="mt-9 flex flex-wrap justify-center gap-3">{children}</div> : null}
        </div>
      </div>
    </section>
  );
}
