/**
 * PRODUCT-FIRST VISUALS — what the platform actually does, drawn, never photographed or generated.
 *
 * Founder, 14 Sep 2026: no AI-generated people. Corporate visuals are (1) product-first, real
 * depictions of what the platform does, and (2) faceless licensed stock of real UAE work (the
 * shortlist is docs/visuals/photo_shortlist.md). These three are (1).
 *
 *   SealedQuote       one quote, sealed on arrival (supplier + total under redaction and a seal mark);
 *                     `open` shows it after the customer chose it: the seal broken, the name in gold.
 *   ComparisonReport  the report: top-3 technical comparison, then EVERY other quote listed below it,
 *                     each selectable. It must never read as "only three are shown".
 *   DrawingToBoq      a drawing whose title block is blacked out ("customer details removed") beside
 *                     the BOQ rows read from it.
 *
 * Server components, no client JS: copy comes from messages/{en,ar}.json → productVisuals, so the
 * Arabic is reviewed in the same place as every other string and mirrors through the page's dir.
 * Every figure is sample data and each frame says so. The drawn parts are aria-hidden; each visual
 * carries one text alternative (figure aria-label). Motion is only the existing .qd-seal sweep, which
 * the global prefers-reduced-motion block collapses to its end state.
 */
import { getTranslations } from 'next-intl/server';
import { cn } from '@/lib/utils';
import { ProductFrame, Seal } from '@/components/ui/sealed';
import type { Locale } from './gate';

/** The seal mark: a stamped ring with a keyhole. Teal while sealed; gold and split once opened. */
function SealMark({ open }: { open?: boolean }) {
  const c = open ? '#E3C065' : '#6EE7D4';
  const half = (side: 1 | -1) => (
    <g transform={open ? `translate(${side * 5} ${side * 3}) rotate(${side * 6} 40 40)` : undefined}>
      <path d={side === 1 ? 'M40 6 A34 34 0 0 1 40 74' : 'M40 74 A34 34 0 0 1 40 6'} fill="none" stroke={c} strokeWidth="2.2" />
      <path d={side === 1 ? 'M40 14 A26 26 0 0 1 40 66' : 'M40 66 A26 26 0 0 1 40 14'} fill="none" stroke={c} strokeWidth="1" strokeDasharray="2 3" />
    </g>
  );
  return (
    <svg viewBox="0 0 80 80" className="h-full w-full" aria-hidden>
      <circle cx="40" cy="40" r="34" fill={open ? 'rgba(227,192,101,.08)' : 'rgba(20,184,166,.10)'} />
      {half(1)}
      {half(-1)}
      {open ? (
        <path d="M40 4 L36 22 L44 34 L37 48 L43 60 L40 76" fill="none" stroke="#E3C065" strokeWidth="1.4" />
      ) : (
        <g fill={c}>
          <circle cx="40" cy="35" r="6" />
          <path d="M36.5 38 L43.5 38 L45 52 L35 52 Z" />
        </g>
      )}
    </svg>
  );
}

export async function SealedQuote({ locale, open, className }: { locale: Locale; open?: boolean; className?: string }) {
  const t = await getTranslations({ locale, namespace: 'productVisuals.sealed' });
  const scope = t.raw('scope') as string[];
  return (
    <figure aria-label={open ? t('altOpen') : t('altSealed')} className={cn('qd-panel qd-grain relative flex flex-col p-6', open && 'shadow-[var(--glow-gold)]', className)}>
      <div aria-hidden className="flex flex-col">
        <div className="flex items-center justify-between gap-3">
          <span className="font-mono text-label text-muted">{t('ref')}</span>
          <span className={cn('rounded-chip border px-2 py-0.5 font-mono text-label', open ? 'border-gold/40 text-gold-light' : 'border-line2 text-teal-light')}>
            {open ? t('stateOpen') : t('stateSealed')}
          </span>
        </div>
        <p className="mt-2 font-head text-[17px] font-semibold text-white">{t('trade')}</p>

        <div className="mt-5 flex items-center justify-between gap-3 border-t border-line pt-4">
          <span className="text-small text-muted">{t('supplier')}</span>
          {open ? <Seal open className="text-small font-medium"><span className="qd-revealed">{t('openName')}</span></Seal> : <span className="redact h-3 w-32" />}
        </div>

        <ul className="mt-4 flex flex-col gap-2">
          {scope.map((s) => (
            <li key={s} className="flex items-center gap-2.5 text-small text-paper/90">
              <svg viewBox="0 0 12 12" className="h-3 w-3 shrink-0"><path d="M2 6.5 L5 9 L10 3" fill="none" stroke="#6EE7D4" strokeWidth="1.6" /></svg>
              {s}
            </li>
          ))}
        </ul>

        <div className="mt-5 flex items-end justify-between gap-3 border-t border-line pt-4 pe-16">
          <span className="text-small text-muted">{t('total')}</span>
          {open ? <span className="tabular font-mono text-[20px] font-semibold text-white">{t('openTotal')}</span> : <span className="redact h-5 w-24" />}
        </div>
      </div>
      <div aria-hidden className={cn('absolute bottom-4 end-4 h-[72px] w-[72px]', open ? 'rotate-[8deg]' : '-rotate-[12deg]')}>
        <SealMark open={open} />
      </div>
      {/* pe-20 keeps the caption clear of the seal mark: at 1440 in Arabic it ran under the stamp */}
      <figcaption className="mt-4 max-w-[34ch] pe-20 text-small text-muted">{open ? t('openNote') : t('sealedNote')}</figcaption>
    </figure>
  );
}

type Row = { k: string; v: string[] };
type Rest = { s: string; v: string };

export async function ComparisonReport({ locale, className }: { locale: Locale; className?: string }) {
  const t = await getTranslations({ locale, namespace: 'productVisuals.report' });
  const suppliers = t.raw('suppliers') as string[];
  const rows = t.raw('rows') as Row[];
  const totals = t.raw('totals') as string[];
  const rest = t.raw('rest') as Rest[];
  const best = 1;
  const cols = 'minmax(118px,1.3fr) repeat(3,minmax(64px,1fr))';
  return (
    <div role="img" aria-label={t('alt')} className={className}>
      <ProductFrame title={t('frame')} sampleLabel={t('sample')} status={t('status')} className="shadow-e3">
        <div aria-hidden className="text-body">
          <p className="border-b border-line px-4 pb-2 pt-3.5 font-mono text-label text-teal-light">{t('topTitle')}</p>
          <div className="overflow-x-auto">
            <div className="min-w-[380px]">
              <div className="qd-row bg-navy-deep/40" style={{ gridTemplateColumns: cols }}>
                <span className="font-mono text-label text-faint">{t('criterion')}</span>
                {suppliers.map((s, i) => (
                  <span key={s} className="flex flex-col gap-1.5">
                    <span className="flex flex-wrap items-center gap-1.5 font-medium text-white">
                      {s}{i === best ? <span className="rounded-chip bg-teal/15 px-1.5 py-px font-mono text-label text-teal-light">{t('best')}</span> : null}
                    </span>
                    <span className="redact h-2 w-12" />
                  </span>
                ))}
              </div>
              {rows.map((r) => (
                <div key={r.k} className="qd-row" style={{ gridTemplateColumns: cols }}>
                  <span className="text-paper/90">{r.k}</span>
                  {r.v.map((v, i) => <span key={i} className={cn('tabular font-mono', i === best ? 'text-teal-light' : 'text-muted')}>{v}</span>)}
                </div>
              ))}
              <div className="qd-row border-t border-line2 bg-teal-light/[0.03]" style={{ gridTemplateColumns: cols }}>
                <span className="font-medium text-white">{t('total')}</span>
                {totals.map((v, i) => <span key={i} className={cn('tabular font-mono text-[15px] font-semibold', i === best ? 'text-white' : 'text-muted')}>{v}</span>)}
              </div>
            </div>
          </div>

          <p className="border-y border-line2 bg-navy-deep/40 px-4 py-2.5 font-mono text-label text-paper/90">{t('restTitle')}</p>
          <ul>
            {rest.map((r) => (
              <li key={r.s} className="qd-row" style={{ gridTemplateColumns: '28px minmax(0,1fr) auto auto' }}>
                <span className="font-medium text-white">{r.s}</span>
                <span className="redact h-2 w-16" />
                <span className="tabular font-mono text-muted">{r.v}</span>
                <span className="rounded-chip border border-line3 px-2.5 py-0.5 font-mono text-label text-teal-light">{t('choose')}</span>
              </li>
            ))}
          </ul>
          <p className="border-t border-line px-4 py-3 font-mono text-label text-warn-fg">{t('held')}</p>
        </div>
      </ProductFrame>
    </div>
  );
}

type Line = { code: string; desc: string; qty: string; unit: string };
const LINE = { stroke: '#6EE7D4', strokeOpacity: 0.7, fill: 'none' } as const;
const THIN = { stroke: '#6EE7D4', strokeOpacity: 0.35, fill: 'none', strokeWidth: 0.6 } as const;

/** Authored linework (no third-party art): a small fit-out plan with its title block blacked out. */
function Sheet() {
  return (
    <svg viewBox="0 0 320 250" className="h-auto w-full" aria-hidden>
      <rect x="4" y="4" width="312" height="242" rx="6" fill="#0F2231" stroke="rgba(110,231,212,.19)" />
      {[40, 102, 164, 226].map((x) => <line key={x} x1={x} y1="16" x2={x} y2="168" {...THIN} strokeDasharray="4 3" />)}
      {[40, 94, 148].map((y) => <line key={y} x1="22" y1={y} x2="236" y2={y} {...THIN} strokeDasharray="4 3" />)}
      <path d="M40 40H226V164H40Z" {...LINE} strokeWidth="3" />
      <path d="M102 40V100M40 100H90M114 100H164M164 100V164M164 130H226" {...LINE} strokeWidth="2" />
      <path d="M90 100A24 24 0 0 1 114 76M90 100H114" {...THIN} />
      <path d="M164 154A24 24 0 0 0 188 130" {...THIN} />
      <path d="M40 184H226M40 179V189M226 179V189" {...THIN} />
      {/* title block: every customer field under a bar */}
      <path d="M244 150H312V238H244Z" {...THIN} />
      {['CLIENT', 'PROJECT', 'TEL', 'EMAIL'].map((f, i) => (
        <g key={f}>
          <text x="248" y={161 + i * 20} fontSize="5.5" fill="#A7B9BB" letterSpacing="0.6">{f}</text>
          <rect x="247" y={164 + i * 20} width={58 - i * 5} height="8" fill="#050C12" stroke="rgba(110,231,212,.25)" strokeWidth="0.5" />
        </g>
      ))}
    </svg>
  );
}

export async function DrawingToBoq({ locale, className }: { locale: Locale; className?: string }) {
  const t = await getTranslations({ locale, namespace: 'productVisuals.drawing' });
  const lines = t.raw('lines') as Line[];
  return (
    <div role="img" aria-label={t('alt')} className={className}>
      <ProductFrame title={t('frame')} sampleLabel={t('sample')} status={t('status')} className="shadow-e3">
        <div aria-hidden className="grid gap-4 p-4 sm:grid-cols-[1fr_1.1fr]">
          <div className="flex flex-col gap-2">
            <span className="font-mono text-label text-faint">{t('sheet')}</span>
            <div className="relative" dir="ltr">
              <Sheet />
            </div>
            <span className="flex items-center gap-2 self-start rounded-chip border border-line2 bg-navy-deep px-2.5 py-1 font-mono text-label text-paper">
              <span className="inline-block h-2.5 w-5 rounded-[2px] bg-navy-deep ring-1 ring-[var(--line3)]" />
              {t('removed')}
            </span>
          </div>
          <div className="flex min-w-0 flex-col">
            <span className="pb-2 font-mono text-label text-faint">{t('boq')}</span>
            <ul className="qd-stagger reveal-stagger overflow-hidden rounded-panel border border-line">
              {lines.map((l) => (
                <li key={l.code} className="grid grid-cols-[42px_minmax(0,1fr)_auto] items-baseline gap-2 border-b border-line bg-surf/50 px-3 py-2.5 last:border-b-0">
                  <span className="font-mono text-label text-teal-light">{l.code}</span>
                  <span className="text-small leading-snug text-paper/90">{l.desc}</span>
                  <span className="tabular whitespace-nowrap font-mono text-small text-paper">{l.qty} <span className="text-muted">{l.unit}</span></span>
                </li>
              ))}
            </ul>
            <p className="mt-3 text-small text-muted">{t('note')}</p>
          </div>
        </div>
      </ProductFrame>
    </div>
  );
}
