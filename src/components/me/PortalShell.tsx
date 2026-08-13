// @ts-nocheck
'use client';
// THE PORTAL SHELL — an application frame, not a page with a menu.
//
// WHAT THIS REPLACES AND WHY. The founder registered as a customer on 13 Aug 2026, opened /en/me,
// and said: "so many tabs that are irrelevant to customers ... the visuals, extremely basic, felt
// so static and super outdated." Rendered at 1280 and 375 (which the previous session did not do),
// the screen was a stack of identical full-width cards under TEN identical grey pill buttons —
// Projects, Approvals, Messages, Documents, Orders, What you may need next, Project room, Account,
// Company profile, Home — in server-ranked order, with no icons, no grouping, no active state, and
// "Home" last. Every module behind those pills is real and most of them are good. The pills were
// the product's navigation and they read as a debug toolbar.
//
// The two structural lessons from the reference designs he supplied, which matter more than the
// palette: a customer belongs INSIDE an application with a persistent sidebar, and the assistant is
// a PRIMARY SURFACE — the widest element on the page — not a bubble in the corner.
//
// THREE THINGS THIS FILE MUST NOT BREAK, all of them earned:
//   1. RTL. Every inline direction here is LOGICAL (ms/me/ps/pe/start/end/border-e). No ml-, no
//      left-, no fixed left/right. Arabic is half the market.
//   2. Bidi isolation. Assistant replies carry +971 numbers, emails and paths; they render through
//      ChatWidget's `render`, which wraps each in <bdi>. Imported, never re-implemented.
//   3. Keyboard and screen-reader access. Every destination is a real <button>; the open one
//      carries aria-current; the mobile overflow carries aria-expanded. The 5 Aug a11y fix in
//      CustomerPortal exists because this exact class of control was once a bare <div onClick>.
import { useEffect, useRef, useState } from 'react';
import {
  LayoutDashboard, FileText, Files, MessagesSquare, FolderKanban, CheckSquare,
  Sparkles, Building2, UserCircle, Boxes, Compass, Search, Bell, Menu, X,
  Sun, Moon, LogOut, ChevronRight, Send, PanelLeftClose, PanelLeftOpen,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { render } from '@/components/ChatWidget';
import { SUPA_ANON as ANON, SUPA_FN as FN } from '@/lib/supaEnv';

// THE INFORMATION ARCHITECTURE, WRITTEN DOWN.
//
// The old bar was a flat list of nine modules plus Home, ordered by the server. Flat lists stop
// being navigable at about seven items; this one had ten and no captions, so a customer looking for
// their quotes had to read every label. Grouping is the fix, and the groups are the customer's
// own mental model of a procurement job, not our module boundaries:
//
//   WORK          what they came for — the request, the quotes, the paperwork
//   COLLABORATE   the people and the decisions around it
//   INTELLIGENCE  what the system worked out for them
//   ACCOUNT       who we think they are
//
// `id` values are the SAME ids the existing ModuleWindow already switches on, so this is a
// navigation change and not a rewrite of nine working modules. 'home' is the dashboard itself.
export const NAV_GROUPS = [
  { caption: 'nav_work', items: [
    { id: 'home',      icon: LayoutDashboard, label: 'nav_overview' },
    { id: 'requests',  icon: FileText,        label: 'nav_requests' },
    { id: 'documents', icon: Files,           label: 'mod_documents' },
    { id: 'orders',    icon: Boxes,           label: 'mod_orders' },
  ] },
  { caption: 'nav_collaborate', items: [
    { id: 'messages',  icon: MessagesSquare,  label: 'messages', badge: 'unread' },
    { id: 'projects',  icon: FolderKanban,    label: 'projects' },
    { id: 'approvals', icon: CheckSquare,     label: 'mod_approvals' },
    { id: 'spatial',   icon: Compass,         label: 'mod_spatial' },
  ] },
  { caption: 'nav_intelligence', items: [
    { id: 'predict',   icon: Sparkles,        label: 'mod_predict' },
    { id: 'profile',   icon: Building2,       label: 'mod_profile' },
  ] },
  { caption: 'nav_account', items: [
    { id: 'account',   icon: UserCircle,      label: 'mod_account' },
  ] },
];
// The phone gets the four a thumb reaches for; everything else lives behind More. Chosen by what a
// customer opens, not by group order: the dashboard, their requests, the inbox, the paperwork.
const MOBILE_PRIMARY = ['home', 'requests', 'messages', 'documents'];

// ── THE ASSISTANT, AS A SURFACE ────────────────────────────────────────────────────────────────
// site_assistant now takes the customer's session token and answers from fn_wa_context — their own
// requests, their own quotes, and a ROUNDED BAND before a reveal, scoped in SQL. Passing the token
// is what turns "I can't see your account" into an answer; it is not optional decoration.
async function askAssistant(message, history, token, lang, path) {
  const r = await fetch(FN + '/site_assistant', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) },
    body: JSON.stringify({ message, history, path: path || '/me', lang }),
  });
  return r.json();
}

// `suggestions` ARE THE OFFER, and they used to be three constants — the same three questions on a
// day-one account with nothing in it and on an account with three quotes waiting to be compared.
// "What is the status of my requests?" offered to someone who has never posted one is a menu, not
// an offer. CustomerPortal derives them from the rows it already holds and passes them down; an
// empty list falls back to the three constants, so a caller that does not compute them is unchanged.
export function AssistantPanel({ token, lang, open, onClose, seed, t, suggestions }) {
  const rtl = lang === 'ar';
  const [msgs, setMsgs] = useState([]);
  const [val, setVal] = useState('');
  const [busy, setBusy] = useState(false);
  const boxRef = useRef(null);
  const inpRef = useRef(null);
  const sentSeed = useRef('');

  useEffect(() => { if (boxRef.current) boxRef.current.scrollTop = boxRef.current.scrollHeight; }, [msgs, busy, open]);
  useEffect(() => { if (open) setTimeout(() => inpRef.current && inpRef.current.focus(), 80); }, [open]);

  const send = async (text) => {
    const q = String(text == null ? val : text).trim();
    if (!q || busy) return;
    setVal(''); setBusy(true);
    const history = msgs.map((m) => ({ role: m.role, content: m.content }));
    setMsgs((m) => [...m, { role: 'user', content: q }]);
    try {
      const j = await askAssistant(q, history, token, lang, '/me');
      setMsgs((m) => [...m, { role: 'assistant', content: String((j && j.reply) || t('asst_err')), scope: j && j.scope }]);
    } catch (_e) {
      setMsgs((m) => [...m, { role: 'assistant', content: t('asst_err') }]);
    }
    setBusy(false);
  };

  // A question typed into the top bar opens this panel already carrying it, so the widest element
  // on the page is a real entry point and not a decorative box that makes you type twice.
  useEffect(() => {
    if (open && seed && sentSeed.current !== seed) { sentSeed.current = seed; send(seed); }
  }, [open, seed]);

  if (!open) return null;
  return (
    <aside
      role="complementary"
      aria-label={t('asst_title')}
      className={cn(
        'fixed inset-y-0 z-40 flex w-full flex-col border-border bg-card/95 backdrop-blur-xl',
        // max-w, not w: a fixed 420px panel is 45px wider than a 375px viewport and cannot shrink.
        'end-0 sm:w-full sm:max-w-[420px] sm:border-s',
        'motion-safe:animate-in motion-safe:slide-in-from-bottom-4 sm:motion-safe:slide-in-from-right-4 motion-safe:duration-300',
      )}
    >
      <header className="flex items-center gap-2 border-b border-border px-4 py-3">
        <span className="grid h-8 w-8 place-items-center rounded-lg bg-primary/15 text-primary"><Sparkles className="h-4 w-4" aria-hidden /></span>
        <div className="min-w-0 flex-1">
          <div className="truncate text-[13.5px] font-bold text-foreground">{t('asst_title')}</div>
          <div className="truncate text-[11.5px] text-muted-foreground">{t('asst_sub')}</div>
        </div>
        <Button variant="ghost" size="sm" onClick={onClose} aria-label={t('close')}><X className="h-4 w-4" aria-hidden /></Button>
      </header>

      <div ref={boxRef} className="flex-1 space-y-3 overflow-y-auto px-4 py-4">
        {!msgs.length && (
          <div className="space-y-3">
            <p className="text-[13.5px] leading-relaxed text-muted-foreground">{t('asst_greet')}</p>
            <div className="flex flex-col gap-1.5">
              {((suggestions && suggestions.length) ? suggestions : ['asst_s1', 'asst_s2', 'asst_s3'].map(t)).map((q) => (
                <button key={q} type="button" onClick={() => send(q)}
                  className="flex items-center gap-2 rounded-lg border border-border bg-secondary/25 px-3 py-2 text-start text-[13px] text-foreground transition-colors hover:border-primary/40 hover:bg-primary/10">
                  <Search className="h-3.5 w-3.5 shrink-0 text-primary" aria-hidden />
                  <span className="min-w-0 flex-1">{q}</span>
                  <ChevronRight className={cn('h-3.5 w-3.5 shrink-0 text-muted-foreground', rtl && 'rotate-180')} aria-hidden />
                </button>
              ))}
            </div>
          </div>
        )}
        {msgs.map((m, i) => (
          <div key={i} className={cn('flex', m.role === 'user' ? 'justify-end' : 'justify-start')}>
            <div className={cn(
              'max-w-[86%] rounded-2xl px-3.5 py-2.5 text-[13.5px] leading-relaxed',
              m.role === 'user' ? 'bg-primary text-primary-foreground' : 'border border-border bg-secondary/30 text-foreground',
            )}>
              {/* Assistant replies carry phone numbers, emails and portal paths. ChatWidget's
                  renderer escapes then wraps each in <bdi>; without it they scramble in Arabic. */}
              {m.role === 'assistant'
                ? <span dangerouslySetInnerHTML={{ __html: render(m.content) }} />
                : m.content}
            </div>
          </div>
        ))}
        {busy && (
          <div className="flex justify-start">
            <div className="flex items-center gap-1 rounded-2xl border border-border bg-secondary/30 px-3.5 py-3">
              {[0, 1, 2].map((d) => (
                <span key={d} className="h-1.5 w-1.5 rounded-full bg-muted-foreground/70 motion-safe:animate-pulse"
                  style={{ animationDelay: d * 180 + 'ms' }} />
              ))}
              <span className="sr-only">{t('asst_thinking')}</span>
            </div>
          </div>
        )}
      </div>

      <form className="flex items-end gap-2 border-t border-border p-3"
        onSubmit={(e) => { e.preventDefault(); send(); }}>
        <input ref={inpRef} value={val} onChange={(e) => setVal(e.target.value)} disabled={busy}
          aria-label={t('asst_ph')} placeholder={t('asst_ph')}
          className="h-11 min-w-0 flex-1 rounded-xl border border-input bg-background px-3.5 text-[13.5px] text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" />
        <Button type="submit" size="sm" className="h-11 px-3.5" disabled={busy || !val.trim()} aria-label={t('asst_send')}>
          <Send className={cn('h-4 w-4', rtl && 'rotate-180')} aria-hidden />
        </Button>
      </form>
    </aside>
  );
}

// ── STAT TILE ──────────────────────────────────────────────────────────────────────────────────
// The old Kpi was a bare number over a caption in a flat box, six across. This gives each number a
// tinted glyph and an optional one-line meaning, and — the part that matters — an emphatic variant
// so "awaiting your decision" does not look the same as "requests". A zero that is GOOD and a zero
// that means nothing has happened yet are different facts and must not render identically.
export function StatTile({ icon: Icon, label, value, hint, tone = 'default' }) {
  return (
    <Card className={cn(
      'group relative overflow-hidden p-4 transition-[transform,border-color] duration-300 motion-safe:hover:-translate-y-0.5',
      tone === 'accent' && 'border-primary/35',
    )}>
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className={cn('font-head text-[26px] font-extrabold leading-none tracking-tight tabular-nums',
            tone === 'accent' ? 'text-primary' : 'text-foreground')}>{value}</div>
          <div className="mt-1.5 text-[12px] font-medium text-muted-foreground">{label}</div>
        </div>
        <span className={cn('grid h-9 w-9 shrink-0 place-items-center rounded-xl',
          tone === 'accent' ? 'bg-primary/15 text-primary' : 'bg-secondary/60 text-muted-foreground')}>
          <Icon className="h-4 w-4" aria-hidden />
        </span>
      </div>
      {hint ? <div className="mt-2 text-[11.5px] leading-snug text-muted-foreground/85">{hint}</div> : null}
    </Card>
  );
}

// ── STATUS PILL ────────────────────────────────────────────────────────────────────────────────
// The five stages of OUR lifecycle. A marketplace has no "Shipped" and no "Processing"; it has a
// request that is being matched, then quoted, then decided, then revealed, then closed. Colour
// carries meaning and is never the ONLY carrier — the word is always present.
export const RFQ_STATE = {
  matching:  { key: 'st_matching',  cls: 'bg-sky-500/12 text-sky-300 border-sky-500/25' },
  quoting:   { key: 'st_quoting',   cls: 'bg-amber-500/12 text-amber-300 border-amber-500/25' },
  quotes_in: { key: 'st_quotes_in', cls: 'bg-primary/12 text-primary border-primary/30' },
  revealed:  { key: 'st_revealed',  cls: 'bg-emerald-500/12 text-emerald-300 border-emerald-500/25' },
  closed:    { key: 'st_closed',    cls: 'bg-secondary/60 text-muted-foreground border-border' },
};
// Derived from facts the row already carries, never from the clock.
export function rfqState(inq, quotes) {
  const n = (quotes || []).length;
  if (['completed', 'closed', 'cancelled'].includes(String(inq && inq.status))) return 'closed';
  if ((quotes || []).some((q) => q.revealed) || (inq && inq.hired_supplier_id)) return 'revealed';
  if (n >= 2) return 'quotes_in';
  if (n >= 1) return 'quoting';
  return 'matching';
}
export function StatusPill({ state, t }) {
  const s = RFQ_STATE[state] || RFQ_STATE.matching;
  return (
    <span className={cn('inline-flex shrink-0 items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11.5px] font-semibold', s.cls)}>
      <span className="h-1.5 w-1.5 rounded-full bg-current opacity-80" aria-hidden />
      {t(s.key)}
    </span>
  );
}

// ── THE SHELL ──────────────────────────────────────────────────────────────────────────────────
// §21's per-customer panel ranking, kept and moved. customer_portal returns layout.order ranked by
// what this customer actually has outstanding, and it used to reorder a flat bar of ten pills. It
// now reorders items WITHIN their group, so the ranking still surfaces what is waiting on them
// without shuffling "Account" into the middle of their work.
//
// CSS `order`, not array order — the same reason the original bar used it: `order` moves the
// painted position and leaves the DOM alone, so a server-side ranking can never reorder a keyboard
// user's tab sequence. Unranked items sort last because indexOf returns -1.
// THE SPINE IS NOT A PANEL. Overview and My requests are the two destinations the portal is FOR;
// the server's ranking is over the §22 module panels and does not mention them, so they scored 99
// and the first render put "Documents, Orders, Overview, My requests" in the Work group — the
// dashboard third in its own menu. They are pinned ahead of the ranking rather than inside it.
const PINNED = { home: -2, requests: -1 };
const rankOf = (id, order) => {
  if (id in PINNED) return PINNED[id];
  const ids = Array.isArray(order) ? order.map(String) : [];
  const i = ids.indexOf(id);
  return i < 0 ? 99 : i;
};

export function PortalShell({
  lang, t, theme, onSwapTheme, onSetLang, onSignOut,
  view, onView, customerName, unread = 0, alerts = 0, alertList = [], token, order, suggestions, children,
}) {
  const rtl = lang === 'ar';
  const [collapsed, setCollapsed] = useState(false);
  const [moreOpen, setMoreOpen] = useState(false);
  const [bellOpen, setBellOpen] = useState(false);
  const [asstOpen, setAsstOpen] = useState(false);
  const [seed, setSeed] = useState('');
  const [q, setQ] = useState('');
  const searchRef = useRef(null);

  // A placeholder that says what the field can do is the point of the field — and at 375px
  // "Ask about your requests, quotes or documents…" renders as "Ask about your", which says
  // nothing and looks broken. A placeholder cannot be set per breakpoint in CSS, so it is set here.
  const [narrow, setNarrow] = useState(false);
  useEffect(() => {
    try { const c = localStorage.getItem('qd-nav-collapsed'); if (c === '1') setCollapsed(true); } catch (_e) {}
    const mq = window.matchMedia('(max-width: 639px)');
    const sync = () => setNarrow(mq.matches);
    sync(); mq.addEventListener('change', sync);
    return () => mq.removeEventListener('change', sync);
  }, []);
  const swapCollapsed = () => {
    setCollapsed((v) => { const n = !v; try { localStorage.setItem('qd-nav-collapsed', n ? '1' : '0'); } catch (_e) {} return n; });
  };
  // Cmd/Ctrl+K puts the cursor in the assistant field. The shortcut exists because the field is the
  // primary way to use the portal, not a search box bolted onto one.
  useEffect(() => {
    const onKey = (e) => {
      if ((e.metaKey || e.ctrlKey) && String(e.key).toLowerCase() === 'k') { e.preventDefault(); searchRef.current && searchRef.current.focus(); }
      if (e.key === 'Escape') { setMoreOpen(false); setBellOpen(false); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const go = (id) => { setMoreOpen(false); onView(id); };
  const submitAsk = (e) => {
    e.preventDefault();
    const text = q.trim(); if (!text) { setAsstOpen(true); return; }
    setSeed(text); setQ(''); setAsstOpen(true);
  };

  const NavButton = ({ item, compact }) => {
    const Icon = item.icon;
    const active = view === item.id || (item.id === 'home' && (view === '' || view === 'home'));
    return (
      <button
        type="button"
        onClick={() => go(item.id)}
        aria-current={active ? 'page' : undefined}
        title={compact ? t(item.label) : undefined}
        style={{ order: rankOf(item.id, order) }}
        className={cn(
          'group relative flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-[13.5px] font-medium transition-colors duration-200',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
          active ? 'bg-primary/14 text-primary' : 'text-muted-foreground hover:bg-secondary/50 hover:text-foreground',
          compact && 'justify-center px-0',
        )}
      >
        {/* The active marker is on the INLINE START edge so it lands on the correct side in Arabic. */}
        {active ? <span className="absolute inset-y-1.5 start-0 w-[3px] rounded-full bg-primary" aria-hidden /> : null}
        <Icon className="h-[18px] w-[18px] shrink-0" aria-hidden />
        {!compact && <span className="min-w-0 flex-1 truncate text-start">{t(item.label)}</span>}
        {!compact && item.badge === 'unread' && unread > 0
          ? <span className="rounded-full bg-primary px-1.5 py-0.5 text-[10px] font-bold text-primary-foreground tabular-nums">{unread}</span>
          : null}
        {compact && item.badge === 'unread' && unread > 0
          ? <span className="absolute end-2 top-1.5 h-2 w-2 rounded-full bg-primary" aria-hidden /> : null}
      </button>
    );
  };

  const mobileItems = NAV_GROUPS.flatMap((g) => g.items).filter((i) => MOBILE_PRIMARY.includes(i.id));
  const overflowGroups = NAV_GROUPS
    .map((g) => ({ ...g, items: g.items.filter((i) => !MOBILE_PRIMARY.includes(i.id)) }))
    .filter((g) => g.items.length);

  return (
    <div className="flex min-h-screen w-full">
      {/* ── SIDEBAR (desktop) ─────────────────────────────────────────────────────────────── */}
      <nav
        aria-label={t('nav_main')}
        className={cn(
          'sticky top-0 hidden h-screen shrink-0 flex-col border-e border-border bg-card/55 backdrop-blur-xl md:flex',
          'transition-[width] duration-300 ease-out',
          collapsed ? 'w-[76px]' : 'w-[264px]',
        )}
      >
        <div className={cn('flex items-center gap-2 px-4 py-4', collapsed && 'justify-center px-2')}>
          <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-primary/15 text-primary font-head text-[15px] font-extrabold">Q</span>
          {!collapsed && (
            <div className="min-w-0">
              <div className="truncate font-head text-[15px] font-extrabold leading-tight text-foreground">QuotesDone</div>
              <div className="truncate text-[11px] text-muted-foreground">{t('brand_sub')}</div>
            </div>
          )}
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto px-3 pb-2">
          {NAV_GROUPS.map((g) => (
            <div key={g.caption} className="mb-4">
              {!collapsed && (
                <div className="px-3 pb-1.5 text-[10.5px] font-bold uppercase tracking-[0.09em] text-muted-foreground/65">{t(g.caption)}</div>
              )}
              <div className="flex flex-col gap-0.5">
                {g.items.map((item) => <NavButton key={item.id} item={item} compact={collapsed} />)}
              </div>
            </div>
          ))}
        </div>

        <div className="border-t border-border p-3">
          <button type="button" onClick={swapCollapsed}
            aria-expanded={!collapsed}
            className="flex w-full items-center gap-3 rounded-xl px-3 py-2 text-[12.5px] font-medium text-muted-foreground transition-colors hover:bg-secondary/50 hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
            {collapsed
              ? <PanelLeftOpen className={cn('h-4 w-4 shrink-0', rtl && 'rotate-180')} aria-hidden />
              : <PanelLeftClose className={cn('h-4 w-4 shrink-0', rtl && 'rotate-180')} aria-hidden />}
            {!collapsed && <span className="truncate">{t('nav_collapse')}</span>}
          </button>
        </div>
      </nav>

      {/* ── MAIN COLUMN ───────────────────────────────────────────────────────────────────── */}
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-30 border-b border-border bg-background/85 backdrop-blur-xl">
          <div className="flex items-center gap-2 px-3 py-2.5 sm:gap-3 sm:px-5">
            <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-primary/15 font-head text-[15px] font-extrabold text-primary md:hidden">Q</span>

            {/* THE ASSISTANT FIELD — the widest element on the page, by design. In the reference
                the founder supplied, AI search is the primary surface; ours was a bubble in a
                corner, which is half of why he called it a chat bot. */}
            <form onSubmit={submitAsk} className="min-w-0 flex-1" role="search">
              <label className="sr-only" htmlFor="qd-ask">{t('ask_ph')}</label>
              <div className="group relative flex items-center">
                <Sparkles className="pointer-events-none absolute start-3.5 h-4 w-4 text-primary" aria-hidden />
                <input
                  id="qd-ask" ref={searchRef} value={q} onChange={(e) => setQ(e.target.value)}
                  placeholder={narrow ? t('ask_ph_short') : t('ask_ph')} autoComplete="off"
                  className={cn(
                    'h-11 w-full rounded-2xl border border-input bg-card/70 ps-11 pe-16 text-[13.5px] text-foreground',
                    'placeholder:text-muted-foreground focus-visible:outline-none',
                    'focus-visible:border-primary/50 focus-visible:ring-2 focus-visible:ring-primary/25',
                    'transition-[border-color,box-shadow] duration-200',
                  )}
                />
                <kbd className="pointer-events-none absolute end-3 hidden rounded border border-border bg-secondary/60 px-1.5 py-0.5 font-mono text-[10px] text-muted-foreground sm:block">⌘K</kbd>
              </div>
            </form>

            {/* A BELL MUST SHOW WHAT IT COUNTS. customer_portal returns the alerts themselves, not
                only alerts_count, so the dot has a list behind it. A notification control that
                opens something other than the notifications is the same defect this codebase keeps
                finding: an instrument reporting on a different subject to the one it names. */}
            <div className="relative shrink-0">
              <button type="button" onClick={() => setBellOpen((v) => !v)}
                aria-label={t('alerts_label')} aria-expanded={bellOpen}
                className="relative grid h-10 w-10 place-items-center rounded-xl text-muted-foreground transition-colors hover:bg-secondary/50 hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
                <Bell className="h-[18px] w-[18px]" aria-hidden />
                {alerts > 0 ? <span className="absolute end-2 top-2 h-2 w-2 rounded-full bg-primary ring-2 ring-background" aria-hidden /> : null}
              </button>
              {bellOpen && (
                <>
                  <button type="button" aria-label={t('close')} onClick={() => setBellOpen(false)} className="fixed inset-0 z-40 cursor-default" />
                  <div className="absolute end-0 z-50 mt-2 w-[min(360px,calc(100vw-24px))] overflow-hidden rounded-xl border border-border bg-card shadow-lg motion-safe:animate-in motion-safe:fade-in motion-safe:slide-in-from-top-1 motion-safe:duration-200">
                    <div className="border-b border-border px-4 py-2.5 text-[12px] font-bold uppercase tracking-[0.08em] text-muted-foreground/70">{t('alerts_label')}</div>
                    {!alertList.length ? (
                      <p className="px-4 py-4 text-[13px] text-muted-foreground">{t('attention_none')}</p>
                    ) : (
                      <ul className="max-h-[60vh] divide-y divide-border overflow-y-auto">
                        {alertList.map((a, i) => (
                          <li key={i} className="flex items-start gap-3 px-4 py-3">
                            <span className={cn('mt-0.5 h-2 w-2 shrink-0 rounded-full',
                              a.severity === 'high' ? 'bg-red-400' : a.severity === 'medium' ? 'bg-amber-300' : 'bg-primary')} aria-hidden />
                            <div className="min-w-0">
                              <div className="text-[13px] font-semibold text-foreground">{a.title}</div>
                              {a.detail ? <div className="mt-0.5 text-[12px] leading-relaxed text-muted-foreground">{a.detail}</div> : null}
                            </div>
                          </li>
                        ))}
                      </ul>
                    )}
                  </div>
                </>
              )}
            </div>

            <button type="button" onClick={() => go('account')}
              className="flex shrink-0 items-center gap-2 rounded-xl py-1 ps-1 pe-2 transition-colors hover:bg-secondary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
              <span className="grid h-8 w-8 place-items-center rounded-full bg-primary/15 text-[12px] font-bold text-primary">
                {String(customerName || '?').trim().charAt(0).toUpperCase()}
              </span>
              <span className="hidden max-w-[140px] truncate text-[13px] font-semibold text-foreground lg:block">{customerName || ''}</span>
            </button>

            <div className="hidden shrink-0 items-center gap-1 sm:flex">
              <Button variant="ghost" size="sm" onClick={() => onSetLang(rtl ? 'en' : 'ar')} aria-label={rtl ? 'English' : 'العربية'}>{rtl ? 'EN' : 'ع'}</Button>
              <Button variant="ghost" size="sm" onClick={onSwapTheme}
                aria-label={theme === 'dark' ? t('theme_light') : t('theme_dark')}>
                {theme === 'dark' ? <Sun className="h-4 w-4" aria-hidden /> : <Moon className="h-4 w-4" aria-hidden />}
              </Button>
              <Button variant="ghost" size="sm" onClick={onSignOut} aria-label={t('signout')}><LogOut className={cn('h-4 w-4', rtl && 'rotate-180')} aria-hidden /></Button>
            </div>
          </div>
        </header>

        <main className="min-w-0 flex-1 pb-24 md:pb-8">{children}</main>
      </div>

      {/* ── MOBILE TAB BAR ────────────────────────────────────────────────────────────────── */}
      <nav aria-label={t('nav_main')}
        className="fixed inset-x-0 bottom-0 z-30 flex items-stretch border-t border-border bg-card/95 backdrop-blur-xl md:hidden">
        {mobileItems.map((item) => {
          const Icon = item.icon;
          const active = view === item.id || (item.id === 'home' && (view === '' || view === 'home'));
          return (
            <button key={item.id} type="button" onClick={() => go(item.id)} aria-current={active ? 'page' : undefined}
              className={cn('relative flex flex-1 flex-col items-center gap-1 py-2.5 text-[10.5px] font-semibold transition-colors',
                active ? 'text-primary' : 'text-muted-foreground')}>
              <Icon className="h-[19px] w-[19px]" aria-hidden />
              <span className="max-w-full truncate px-1">{t(item.label)}</span>
              {item.badge === 'unread' && unread > 0
                ? <span className="absolute end-[22%] top-1.5 h-2 w-2 rounded-full bg-primary" aria-hidden /> : null}
              {active ? <span className="absolute inset-x-5 top-0 h-[2px] rounded-full bg-primary" aria-hidden /> : null}
            </button>
          );
        })}
        <button type="button" onClick={() => setMoreOpen((v) => !v)} aria-expanded={moreOpen}
          className={cn('flex flex-1 flex-col items-center gap-1 py-2.5 text-[10.5px] font-semibold transition-colors',
            moreOpen ? 'text-primary' : 'text-muted-foreground')}>
          {moreOpen ? <X className="h-[19px] w-[19px]" aria-hidden /> : <Menu className="h-[19px] w-[19px]" aria-hidden />}
          <span>{t('nav_more')}</span>
        </button>
      </nav>

      {moreOpen && (
        <>
          <button type="button" aria-label={t('close')} onClick={() => setMoreOpen(false)}
            className="fixed inset-0 z-30 bg-background/70 backdrop-blur-sm md:hidden" />
          <div className="fixed inset-x-0 bottom-[60px] z-40 max-h-[62vh] overflow-y-auto rounded-t-2xl border-t border-border bg-card p-4 motion-safe:animate-in motion-safe:slide-in-from-bottom-6 motion-safe:duration-300 md:hidden">
            {overflowGroups.map((g) => (
              <div key={g.caption} className="mb-3">
                <div className="px-1 pb-1.5 text-[10.5px] font-bold uppercase tracking-[0.09em] text-muted-foreground/65">{t(g.caption)}</div>
                <div className="grid grid-cols-2 gap-1.5">
                  {g.items.map((item) => {
                    const Icon = item.icon;
                    return (
                      <button key={item.id} type="button" onClick={() => go(item.id)}
                        className="flex items-center gap-2.5 rounded-xl border border-border bg-secondary/25 px-3 py-2.5 text-start text-[12.5px] font-medium text-foreground">
                        <Icon className="h-4 w-4 shrink-0 text-primary" aria-hidden />
                        <span className="min-w-0 flex-1 truncate">{t(item.label)}</span>
                      </button>
                    );
                  })}
                </div>
              </div>
            ))}
            <div className="mt-1 flex items-center gap-2 border-t border-border pt-3">
              <Button variant="outline" size="sm" className="flex-1" onClick={() => onSetLang(rtl ? 'en' : 'ar')}>{rtl ? 'English' : 'العربية'}</Button>
              <Button variant="outline" size="sm" className="flex-1" onClick={onSwapTheme}>{theme === 'dark' ? t('theme_light') : t('theme_dark')}</Button>
              <Button variant="outline" size="sm" className="flex-1" onClick={onSignOut}>{t('signout')}</Button>
            </div>
          </div>
        </>
      )}

      <AssistantPanel token={token} lang={lang} open={asstOpen} seed={seed} t={t} suggestions={suggestions}
        onClose={() => { setAsstOpen(false); setSeed(''); }} />
    </div>
  );
}
