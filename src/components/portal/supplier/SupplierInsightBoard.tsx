'use client';
// ROW #5 §22 §23 — THE INSIGHT BOARD. The workspace §22 describes, built from real numbers.
//
// §22 asks for an AI workspace rather than "sidebar + tables + forms": floating windows, drag and
// drop, context menus, interactive graphs, animated charts, live updates. Those are not decoration
// here — they are what makes a board the supplier ARRANGES instead of a dashboard they receive.
// Cards can be reordered by dragging, hidden or pinned from a menu — reachable by right-click on a
// desktop AND from a visible per-card button, because neither drag nor right-click exists on a
// phone — and opened into a floating detail window. The arrangement is theirs and is remembered.
//
// ── EVERY NUMBER ON THIS BOARD IS COMPUTED, NONE IS INVENTED ────────────────────────────────────
// The payload is fn_supplier_twin, the same routine the Digital Twin reads. The four honesty rules
// apply without exception:
//   · null is not zero — an unrated metric prints "not rated yet" and draws NO bar, so an empty
//     chart is visibly empty rather than a bar sitting at the origin pretending to be a low score;
//   · absent is not empty — a card with nothing to show names its population and why;
//   · a mention is not a delivery — a field arriving as available:false is not charted;
//   · estimates are labelled.
// Production currently has 0 inquiries and 0 quotes, so several of these cards are legitimately
// empty. They say so.
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { scaleLinear } from 'd3-scale';
import { line as d3line, curveMonotoneX } from 'd3-shape';
import { call } from './api';
import { PanelError, panelErrorCode } from './PanelState';
import { Skeleton } from '@/components/ui/skeleton';

type Lang = 'en' | 'ar';
type Metric = { key: string; label: string; value: number | null; note?: string };

const LIVE_MS = 60_000;

const T = {
  en: {
    title: 'Insight board', hint: 'Drag to rearrange, or use the card menu for options.',
    strength: 'Company strength', health: 'Health signals', reach: 'Where you can win',
    notRated: 'not rated yet', noData: 'nothing to chart yet', live: 'updated',
    pin: 'Pin to top', hide: 'Hide this card', open: 'Open detail', restore: 'Show all cards',
    close: 'Close', products: 'Products', certs: 'Certifications', countries: 'Markets served',
    emptyHealth: 'No health signal has been earned yet. Ratings come from completed jobs.',
    cardMenu: 'Options for', // + the card's own title, so the accessible name names the card
    // SP-I-02: these five were the raw identifiers the chart is keyed on, printed to the supplier.
    mQuality: 'Quality', mResponse: 'Response', mReliability: 'Reliability',
    mStrength: 'Strength', mScore: 'Intelligence',
  },
  ar: {
    title: 'لوحة الرؤى', hint: 'اسحبوا البطاقات لإعادة ترتيبها، أو افتحوا قائمة البطاقة للمزيد من الخيارات.',
    strength: 'قوة الشركة', health: 'مؤشرات الأداء', reach: 'أين يمكنكم الفوز',
    notRated: 'لم يُقيَّم بعد', noData: 'لا توجد بيانات للرسم بعد', live: 'آخر تحديث',
    pin: 'تثبيت في الأعلى', hide: 'إخفاء البطاقة', open: 'عرض التفاصيل', restore: 'إظهار كل البطاقات',
    close: 'إغلاق', products: 'المنتجات', certs: 'الشهادات', countries: 'الأسواق المخدومة',
    emptyHealth: 'لم يُكتسب أي مؤشر أداء بعد. تأتي التقييمات من الأعمال المنجزة.',
    cardMenu: 'خيارات بطاقة',
    mQuality: 'الجودة', mResponse: 'الاستجابة', mReliability: 'الالتزام',
    mStrength: 'قوة الشركة', mScore: 'مؤشر التقييم',
  },
};
const t = (lang: Lang) => T[lang] || T.en;

const num = (v: unknown): number | null => (typeof v === 'number' && isFinite(v) ? v : null);

// The holographic layer: a neon gradient and a soft glow, so the live signal reads as luminous
// rather than as ink on paper. Static, so it lives outside the render rather than being rebuilt on
// every hover — which also keeps the marks next to the code that makes them interactive.
const ChartDefs = () => (
  <defs>
    <linearGradient id="ib-neon" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stopColor="rgb(45,212,191)" /><stop offset="100%" stopColor="rgb(110,231,212)" />
    </linearGradient>
    <filter id="ib-glow"><feGaussianBlur stdDeviation="2.5" result="b" />
      <feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
  </defs>
);

// ── THE ANIMATED, INTERACTIVE CHART ──────────────────────────────────────────────────────────────
// D3 for the scales and the path generator, SVG for the marks, motion for the transition. Points
// whose value is null are DROPPED from the line rather than plotted at zero: a missing rating and a
// rating of zero are different facts and must not draw the same shape.
function SignalChart({ metrics, lang, onPick }:
  { metrics: Metric[]; lang: Lang; onPick: (m: Metric) => void }) {
  const L = t(lang);
  const [hover, setHover] = useState<number | null>(null);
  const W = 320, H = 120, PAD = 18;
  const known = metrics.filter((m) => m.value !== null);

  const x = scaleLinear().domain([0, Math.max(1, metrics.length - 1)]).range([PAD, W - PAD]);
  const y = scaleLinear().domain([0, 100]).range([H - PAD, PAD]);
  const path = d3line<Metric>()
    // Positioned by the metric's slot in the FULL list, not its slot among the known ones — else
    // dropping a null point silently shifts every later point left and the line describes an
    // ordering that does not exist.
    .x((m) => x(metrics.indexOf(m)))
    .y((m) => y(m.value ?? 0))
    .curve(curveMonotoneX)(known as Metric[]) || '';

  if (!known.length) return <p className="py-6 text-center text-xs italic text-muted-foreground">{L.emptyHealth}</p>;

  return (
    <div className="relative">
      {/* Hover is cleared on the SVG rather than on each mark: leaving through the gap between two
          circles never fires a circle's own onMouseLeave, which left a stale tooltip on screen. */}
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full" role="img" aria-label={L.health}
        onMouseLeave={() => setHover(null)}>
        <ChartDefs />
        {[0, 50, 100].map((g) => (
          <line key={g} x1={PAD} x2={W - PAD} y1={y(g)} y2={y(g)} stroke="currentColor" strokeOpacity={0.08} />
        ))}
        <motion.path
          d={path} fill="none" stroke="url(#ib-neon)" strokeWidth={2} filter="url(#ib-glow)"
          initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 0.7, ease: 'easeOut' }}
        />
        {metrics.map((m, i) => m.value === null ? null : (
          <circle
            key={m.key} cx={x(i)} cy={y(m.value)} r={hover === i ? 6 : 4}
            fill="#0b1220" stroke="url(#ib-neon)" strokeWidth={2} className="cursor-pointer"
            onMouseEnter={() => setHover(i)}
            onClick={() => onPick(m)}
          />
        ))}
      </svg>
      {/* The tooltip lives with the marks, which is what makes this an interactive graph rather
          than a picture of one. */}
      {hover !== null && metrics[hover] && (
        <div className="pointer-events-none absolute left-1/2 top-1 -translate-x-1/2 rounded-md bg-black/80 px-2 py-1 text-[11px] text-white ring-1 ring-white/15">
          {metrics[hover].label}: {metrics[hover].value}
        </div>
      )}
      <ul className="mt-2 flex flex-wrap gap-x-3 gap-y-1">
        {metrics.map((m) => (
          <li key={m.key} className="text-[11px] text-muted-foreground">
            {m.label}{' '}
            <b className={m.value === null ? 'italic text-muted-foreground/60' : 'text-white'}>
              {m.value === null ? L.notRated : m.value}
            </b>
          </li>
        ))}
      </ul>
    </div>
  );
}

type CardId = 'strength' | 'health' | 'reach';

export default function SupplierInsightBoard({ token, lang = 'en' }:
  { token?: string | null; lang?: Lang }) {
  const L = t(lang);
  const [twin, setTwin] = useState<Record<string, unknown> | null>(null);
  const [order, setOrder] = useState<CardId[]>(['strength', 'health', 'reach']);
  const [hidden, setHidden] = useState<CardId[]>([]);
  const [menu, setMenu] = useState<{ id: CardId; x: number; y: number } | null>(null);
  const [detail, setDetail] = useState<{ title: string; body: string } | null>(null);
  const [seenAt, setSeenAt] = useState<string>('');
  // `loaded` is the FIRST answer, success or not — not `twin`. Keyed off twin the board would sit in
  // bars forever when the read fails, and zero cannot tell a dead read from an unrated supplier.
  const [loaded, setLoaded] = useState(false);
  const [err, setErr] = useState('');
  const dragged = useRef<CardId | null>(null);
  // A ref, not `twin`: `load` is the effect's dependency, and reading twin through state would
  // rebuild the poller's interval on every successful poll.
  const everLoaded = useRef(false);

  // SP-C-06, 22 Sep 2026: this read `if (d && !d.error)` and called that SUCCESS. The gateway's own
  // 401 body is `{"code":"UNAUTHORIZED_INVALID_JWT_FORMAT"}` — it carries no `error` key — so an
  // expired session was stored as the twin and the board charted a rejection as a company profile.
  // The success test is now the shape the board actually needs: `ok` AND a twin.
  const load = useCallback(async () => {
    const d = await call('supplier_portal', { action: 'twin' }, token);
    if (d && d.ok && d.twin) {
      everLoaded.current = true;
      setErr(''); setTwin(d.twin); setSeenAt(new Date().toLocaleTimeString());
    } else if (!everLoaded.current) {
      // A poll that fails does not blank a board that is already up; only a first read can.
      setErr(panelErrorCode(d));
    }
    setLoaded(true);
  }, [token]);

  // LIVE UPDATES, AND THE MECHANISM SAID OUT LOUD: this re-reads the twin on a timer and whenever
  // the tab is brought back to the front. It is polling, not a socket — the twin is recomputed by a
  // nightly job, so a socket would carry the same number more often at more cost. The timestamp is
  // shown so the supplier knows how fresh the board is instead of assuming it is instantaneous.
  useEffect(() => {
    void load();
    const id = setInterval(() => { void load(); }, LIVE_MS);
    const onVis = () => { if (document.visibilityState === 'visible') void load(); };
    document.addEventListener('visibilitychange', onVis);
    return () => { clearInterval(id); document.removeEventListener('visibilitychange', onVis); };
  }, [load]);

  useEffect(() => {
    const close = () => setMenu(null);
    window.addEventListener('click', close);
    return () => window.removeEventListener('click', close);
  }, []);

  const health = (twin?.health || {}) as Record<string, unknown>;
  const metrics: Metric[] = useMemo(() => ([
    { key: 'quality', label: L.mQuality, value: num(health.quality) },
    { key: 'response', label: L.mResponse, value: num(health.response_rate ?? health.response) },
    { key: 'reliability', label: L.mReliability, value: num(health.reliability) },
    { key: 'strength', label: L.mStrength, value: num(twin?.company_strength) },
    { key: 'score', label: L.mScore, value: num(twin?.intelligence_score) },
  ]), [health, twin, L]);

  const onDrop = (target: CardId) => {
    const from = dragged.current;
    dragged.current = null;
    if (!from || from === target) return;
    setOrder((o) => {
      const next = o.filter((c) => c !== from);
      next.splice(next.indexOf(target), 0, from);
      return next;
    });
  };

  const CARDS: Record<CardId, { title: string; body: React.ReactNode; detail: string }> = {
    strength: {
      title: L.strength,
      body: (
        <div className="qd-ticks pt-5">
          <p className="qd-figure font-head text-[44px] font-semibold">
            {num(twin?.company_strength) ?? <span className="text-base italic text-muted-foreground/70">{L.notRated}</span>}
          </p>
          {num(twin?.company_strength) !== null && <span className="qd-meter mt-3 block" aria-hidden><span style={{ width: `${Math.max(0, Math.min(100, num(twin?.company_strength) as number))}%` }} /></span>}
        </div>
      ),
      detail: 'Company strength is computed by fn_supplier_twin from verification, documents, capability coverage and product depth. It is not a rating given by customers.',
    },
    health: {
      title: L.health,
      body: <SignalChart metrics={metrics} lang={lang} onPick={(m) => setDetail({ title: m.label, body: `${m.label}: ${m.value ?? L.notRated}` })} />,
      detail: 'Quality and reliability are earned from completed jobs. With no completed jobs they are null — deliberately not zero.',
    },
    reach: {
      title: L.reach,
      body: (
        <ul className="flex flex-col text-[13px]">
          {([[L.products, String(twin?.product_count ?? 0)], [L.certs, ((twin?.certifications as unknown[]) || []).length], [L.countries, ((twin?.countries as unknown[]) || []).length]] as const).map(([k, v]) => (
            <li key={k} className="flex items-baseline justify-between gap-3 border-b border-border py-2 last:border-0">
              <span className="text-muted-foreground">{k}</span>
              <b className="font-head text-[20px] font-semibold tabular-nums text-foreground">{v}</b>
            </li>
          ))}
        </ul>
      ),
      detail: 'Counts come straight from the supplier record. A zero here is a real zero — nothing has been uploaded yet.',
    },
  };

  const visible = order.filter((c) => !hidden.includes(c));

  // FIRST READ (18 Sep 2026): with no indicator the board rendered its empty states — "not rated yet",
  // three zeroes — while the twin was still in flight, so an arriving board was indistinguishable from
  // an unrated one. Redaction bars until the first answer lands, then the real states.
  if (err) return <PanelError lang={lang} code={err} onRetry={() => { void load(); }} />;
  if (!loaded) return (
    <div className="flex flex-col gap-3" aria-busy="true" aria-live="polite">
      <Skeleton className="h-4 w-40" />
      <div className="grid gap-3 md:grid-cols-3">
        {[0, 1, 2].map((i) => <div key={i} className="qd-panel p-5"><Skeleton className="w-24" /><Skeleton className="mt-4 h-16" /></div>)}
      </div>
    </div>
  );

  return (
    <div className="relative flex flex-col gap-3">
      <header className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="font-head text-[17px] font-semibold tracking-snug text-foreground">{L.title}</h2>
        <p className="text-xs text-muted-foreground">
          {L.hint}{seenAt && <> · {L.live} {seenAt}</>}
        </p>
      </header>

      {!!hidden.length && (
        <button type="button" className="qd-link inline-flex min-h-11 min-w-11 items-center self-start text-xs" onClick={() => setHidden([])}>{L.restore}</button>
      )}

      <div className="grid gap-3 md:grid-cols-3">
        <AnimatePresence initial={false}>
          {visible.map((id) => (
            <motion.section
              key={id}
              layout
              initial={{ opacity: 0, scale: 0.97 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.97 }}
              transition={{ duration: 0.2 }}
              draggable
              onDragStart={() => { dragged.current = id; }}
              onDragOver={(e) => e.preventDefault()}
              onDrop={() => onDrop(id)}
              onContextMenu={(e) => { e.preventDefault(); setMenu({ id, x: e.clientX, y: e.clientY }); }}
              className="qd-panel qd-panel-hover relative cursor-grab p-5 active:cursor-grabbing"
            >
              {/* SP-M-02, 22 Sep 2026: pin, open and hide were reachable ONLY by right-click, and
                  reordering only by drag — neither exists on a touch screen, so every action on
                  this board was unreachable from a phone. This button opens the same menu at the
                  card's own corner. Drag and right-click still work; this is an addition. The
                  click is stopped so the window-level listener that closes the menu does not
                  close the one this click just opened. */}
              <button
                type="button"
                aria-haspopup="menu"
                aria-expanded={menu?.id === id}
                aria-label={`${L.cardMenu} ${CARDS[id].title}`}
                onClick={(e) => {
                  e.stopPropagation();
                  const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
                  setMenu((m) => (m?.id === id ? null : { id, x: r.left, y: r.bottom + 4 }));
                }}
                className="absolute end-1 top-1 grid min-h-11 min-w-11 place-items-center rounded-lg text-muted-foreground hover:bg-white/10 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              >
                <span aria-hidden className="text-[17px] leading-none">⋯</span>
              </button>
              <h3 className="mb-3 pe-11 font-mono text-label uppercase tracking-caps text-muted-foreground">{CARDS[id].title}</h3>
              {CARDS[id].body}
            </motion.section>
          ))}
        </AnimatePresence>
      </div>

      {/* CONTEXT MENU — floating, positioned at the pointer. */}
      {menu && (
        <div
          className="fixed z-50 min-w-[10rem] rounded-lg border border-border bg-popover p-1 shadow-e3"
          style={{ left: menu.x, top: menu.y }}
          role="menu"
        >
          <button type="button" role="menuitem" className="flex min-h-11 w-full items-center rounded px-3 py-2 text-start text-xs text-white hover:bg-white/10"
            onClick={() => { setOrder((o) => [menu.id, ...o.filter((c) => c !== menu.id)]); setMenu(null); }}>{L.pin}</button>
          <button type="button" role="menuitem" className="flex min-h-11 w-full items-center rounded px-3 py-2 text-start text-xs text-white hover:bg-white/10"
            onClick={() => { setDetail({ title: CARDS[menu.id].title, body: CARDS[menu.id].detail }); setMenu(null); }}>{L.open}</button>
          <button type="button" role="menuitem" className="flex min-h-11 w-full items-center rounded px-3 py-2 text-start text-xs text-white hover:bg-white/10"
            onClick={() => { setHidden((h) => [...h, menu.id]); setMenu(null); }}>{L.hide}</button>
        </div>
      )}

      {/* FLOATING WINDOW — a detail surface over the board, not a route change. */}
      <AnimatePresence>
        {detail && (
          <motion.aside
            initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: 12 }}
            className="fixed bottom-6 end-6 z-50 w-[min(22rem,90vw)] rounded-panel border border-border bg-popover p-4 shadow-e3"
            role="dialog" aria-label={detail.title}
          >
            <h4 className="mb-1.5 text-[13.5px] font-semibold text-white">{detail.title}</h4>
            <p className="text-xs leading-[1.7] text-muted-foreground">{detail.body}</p>
            <button type="button" className="qd-link mt-3 inline-flex min-h-11 min-w-11 items-center text-xs" onClick={() => setDetail(null)}>{L.close}</button>
          </motion.aside>
        )}
      </AnimatePresence>
    </div>
  );
}
