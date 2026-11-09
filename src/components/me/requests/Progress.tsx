// @ts-nocheck
'use client';
import { cn } from '@/lib/utils';
import { Lock, Check } from 'lucide-react';
import { trackerOf } from '../requestTracker';
import { t, tf } from '../portalText';
import { countPhrase } from '@/lib/countedNoun';
import { aed, RFQ_STAGES, rfqStageIdx } from '../format';
import { S } from '../styles';

function Timeline({ inq, quotes, anyRevealed: _anyRevealed, lang }) {
  const steps = lang === 'ar' ? RFQ_STAGES.ar : RFQ_STAGES.en;
  const idx = rfqStageIdx(inq, quotes);
  const fmt = (d) => { try { return new Date(d).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }); } catch (_e) { return ''; } };
  return (<div className="rounded-lg border border-border bg-secondary/20 p-3">
    {inq.created_at ? <div className={cn(S.sub, 'mb-2')}>{(lang === 'ar' ? 'أُنشئ في ' : 'Created ') + fmt(inq.created_at)}</div> : null}
    <div className="flex items-center gap-1.5 flex-wrap text-[11px]">{steps.map((sname, si) => (<span key={sname} className={cn('flex items-center gap-1', si <= idx ? 'text-primary font-semibold' : 'text-muted-foreground/60')}>{si > 0 ? <span className="text-muted-foreground/40">›</span> : null}<span className={cn('inline-block w-2 h-2 rounded-full', si <= idx ? 'bg-primary' : 'bg-muted-foreground/30')} />{sname}</span>))}</div>
  </div>);
}

// THE LIVE REQUEST TRACKER (T2, sales_engineer, 5 Oct 2026). Replaced the six-node Journey rail,
// which was aria-hidden, had no timestamps, no held-for-specs stage and no next step. The stages are
// computed in requestTracker.ts (executed by scripts/checks/the_request_tracker_reads_the_stage_from_the_servers_fields.test.mjs)
// from my_inquiries fields only; the card refreshes with the portal's existing 60-second poll.
// An ordered list, the current stage marked aria-current="step"; logical start/end so RTL mirrors.
function RequestTracker({ inq, quotes, lang }) {
  const tr = trackerOf(inq, quotes, lang);
  const fmt = (d) => { try { return new Date(d).toLocaleString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }); } catch (_e) { return ''; } };
  return (
    <div className="mt-3">
      <ol className="flex flex-col gap-1.5 sm:flex-row sm:gap-0" aria-label={lang === 'ar' ? 'مراحل تقدّم الطلب' : 'Request progress'}>
        {tr.stages.map((st, i) => (
          <li key={st.key} aria-current={st.current ? 'step' : undefined} className="flex min-w-0 items-start gap-2 sm:flex-1 sm:flex-col sm:gap-1">
            <div className="flex items-center sm:w-full">
              <span aria-hidden className={cn('h-2.5 w-2.5 shrink-0 rounded-full border transition-colors duration-500',
                st.done ? 'border-primary bg-primary' : st.current ? (tr.held && st.key === 'specs' ? 'border-warn bg-warn/30' : 'border-primary bg-primary/25 shadow-glow-teal motion-safe:animate-pulse') : 'border-border bg-card')} />
              {i < tr.stages.length - 1 ? <span aria-hidden className={cn('hidden h-px flex-1 sm:block', st.done ? 'bg-primary' : 'bg-border')} /> : null}
            </div>
            <div className="min-w-0 pe-1">
              <div className={cn('text-[11px] leading-tight', st.done ? 'text-muted-foreground' : st.current ? 'font-semibold text-primary' : 'text-muted-foreground/60')}>{st.label}</div>
              {st.at ? <time dateTime={st.at} className="block text-[10.5px] text-muted-foreground/80">{fmt(st.at)}</time> : null}
            </div>
          </li>
        ))}
      </ol>
      <div className={cn(S.sub, 'mt-2', tr.held ? 'text-warn-fg' : '')} aria-live="polite">{tr.next}</div>
    </div>
  );
}

// THE QUOTE SPREAD, IN BOTH STATES — and this is the one rule no amount of design may break.
//
// PRE-REVEAL: a count and a band rounded to the nearest 1,000. NOT five bars. A chart that plots
// each quote as its own bar before the customer has paid to reveal is exactly the picture that
// destroys what the marketplace sells, even when every bar is labelled "Supplier A" — the shape of
// the market is the thing being bought.
// POST-REVEAL: everything, because they have bought it. Lowest highlighted.
//
// The rounding is done HERE and also in SQL (fn_wa_context) for the conversational channel. This
// component is given the same prices the rest of the card already holds and chooses not to draw
// them; the SQL path is given a band and could not draw them if it wanted to.
function QuoteSpread({ quotes, lang }) {
  const priced = (quotes || []).filter((q) => Number(q.price) > 0);
  if (!priced.length) return null;
  const anyRevealed = priced.some((q) => q.revealed);
  const vals = priced.map((q) => Number(q.price));
  const lo = Math.min(...vals), hi = Math.max(...vals);
  const roundK = (n) => Math.round(n / 1000) * 1000;
  return (
    <div className="rounded-lg border border-border bg-secondary/20 p-3.5">
      <div className="flex items-center justify-between gap-2">
        <b className="text-[13px] text-foreground">{t(lang, 'spread_title')}</b>
        {!anyRevealed ? (
          <span className="inline-flex items-center gap-1.5 rounded-full border border-border bg-card px-2 py-1 text-[11px] font-medium text-muted-foreground">
            <Lock className="h-3 w-3" aria-hidden />{t(lang, 'spread_locked')}
          </span>
        ) : null}
      </div>
      {!anyRevealed ? (
        <>
          <div className="mt-2.5 text-[15px] font-bold text-foreground">
            {tf(lang, 'spread_line', { c: countPhrase(lang, priced.length, 'quote'), avg: aed(roundK(vals.reduce((a, b) => a + b, 0) / vals.length)) })}
          </div>
          {/* One band. Not one bar per quote. */}
          <div className="mt-2 h-2.5 overflow-hidden rounded-full bg-secondary/70">
            <div className="h-full w-1/2 rounded-full bg-linear-to-r from-primary/35 via-primary/70 to-primary/35 motion-safe:transition-[width] motion-safe:duration-700" style={{ marginInlineStart: '25%' }} />
          </div>
        </>
      ) : (
        <div className="mt-2.5 flex flex-col gap-1.5">
          {priced.slice().sort((a, b) => Number(a.price) - Number(b.price)).map((q, i) => {
            const pct = hi === lo ? 100 : Math.max(12, Math.round(((Number(q.price) - lo) / (hi - lo)) * 70) + 30);
            return (
              <div key={q.id} className="flex items-center gap-2">
                <span className="w-[104px] shrink-0 truncate text-[11.5px] text-muted-foreground">{q.supplier_name || q.label}</span>
                <span className="h-2.5 flex-1 overflow-hidden rounded-full bg-secondary/70">
                  <span className={cn('block h-full rounded-full motion-safe:transition-[width] motion-safe:duration-700', i === 0 ? 'bg-primary' : 'bg-primary/45')} style={{ width: pct + '%' }} />
                </span>
                <span className={cn('w-[92px] shrink-0 text-end text-[11.5px] tabular-nums', i === 0 ? 'font-bold text-primary' : 'text-foreground')}>{aed(q.price)}</span>
                {i === 0 ? <Check className="h-3.5 w-3.5 shrink-0 text-primary" aria-hidden /> : <span className="w-3.5 shrink-0" />}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
export { Timeline, RequestTracker, QuoteSpread };
