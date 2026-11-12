// @ts-nocheck
'use client';
import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Seal } from '@/components/ui/sealed';
import { cn } from '@/lib/utils';
import { durationLabel } from '@/lib/durationLabel';
import * as M from 'motion/react-m';
import { useReducedMotion } from 'motion/react';
import { t, tf, errText, qualityReason } from '../portalText';
import { openDocument } from '@/lib/openDocument';
import { COMPARE_PDF_TIMEOUT_MS, call } from '../api';
import { STILL_WORKING_MS } from '@/lib/stillWorking';
import { aed, supLabel } from '../format';
import { S } from '../styles';

// The comparison rows: one qd-row per quote over the same five columns, the best-value row lit teal,
// a term the supplier did not state flagged in warn. Real fields only — nothing here is sample data.
function LevelledRows({ quotes, vmap, bestId, lang }) {
  const cols = 'minmax(128px,1.3fr) minmax(96px,1fr) repeat(2,minmax(88px,1fr)) minmax(64px,.6fr)';
  const miss = <span className="text-warn-fg">⚠ {t(lang, 'lv_missing')}</span>;
  return (
    <div className="overflow-x-auto">
      <div className="min-w-[540px]" role="table" aria-label={tf(lang, 'rc_quotes_received', { n: quotes.length })}>
        <div className="qd-row bg-secondary/25 font-mono text-label uppercase tracking-caps text-muted-foreground" style={{ gridTemplateColumns: cols }} role="row">
          <span role="columnheader">{t(lang, 'lv_supplier')}</span><span role="columnheader" className="text-end">{t(lang, 'lv_price')}</span>
          <span role="columnheader">{t(lang, 'q_lead')}</span><span role="columnheader">{t(lang, 'q_warranty')}</span><span role="columnheader" className="text-end">{t(lang, 'q_value')}</span>
        </div>
        <div className="qd-stagger reveal-stagger">
          {quotes.map((q) => {
            const best = q.id === bestId;
            return (
              <div key={q.id} className={cn('qd-row', best && 'qd-row-best')} style={{ gridTemplateColumns: cols }} role="row">
                <span role="cell" className="flex min-w-0 flex-col gap-1">
                  <span className="truncate font-medium text-foreground">{supLabel(q.label, lang)}</span>
                  {q.revealed
                    ? (q.supplier_name ? <Seal open className="qd-revealed text-accent! max-w-full truncate text-label">{q.supplier_name}</Seal> : null)
                    : <span aria-hidden className="leading-none"><Seal className="text-label">{'••••••••••'}</Seal></span>}
                </span>
                <span role="cell" className={cn('tabular text-end font-mono', best ? 'font-semibold text-primary' : 'text-foreground')}>{Number(q.price) > 0 ? aed(q.price) : miss}</span>
                <span role="cell" className="min-w-0 truncate text-muted-foreground">{q.lead_time || miss}</span>
                <span role="cell" className="min-w-0 truncate text-muted-foreground">{q.warranty ? durationLabel(q.warranty, lang) : miss}</span>
                <span role="cell" className={cn('tabular text-end font-mono', best ? 'text-primary' : 'text-muted-foreground')}>{vmap[q.id] != null ? vmap[q.id] : '—'}</span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
// A CODE IS NOT A SENTENCE. `note` is written by quote_compare FOR the customer ("not enough quotes
// to compare yet") and is rendered as-is. `error` is written for us — and quote_compare's own catch
// is `J({ error: String(e.message) }, 500)`, so an unhandled Postgres or Deno message would be
// rendered as the whole card. MEASURED 13 Aug 2026 on a real request screen: a card containing the
// single word `not_found`, between "Trades: hvac" and "Your request reached 9 suppliers".
const compareErrText = (code, lang) => {
  const c = String(code || '');
  if (c === 'ai_unavailable') return lang === 'ar'
    ? 'خدمة المقارنة غير متاحة مؤقتًا. عروضك محفوظة — يمكنك مقارنتها بنفسك أدناه والمحاولة لاحقًا.'
    : 'The comparison service is briefly unavailable. Your quotes are safe — you can still compare them yourself below, and this will fill in when it returns.';
  if (c === 'unauthorized') return lang === 'ar' ? 'انتهت جلستك. يُرجى تسجيل الدخول من جديد.' : 'Your session has expired. Please sign in again.';
  if (c === 'not_your_inquiry') return lang === 'ar' ? 'هذا الطلب ليس ضمن طلباتك.' : 'That request is not on your account.';
  return lang === 'ar'
    ? 'تعذّر إعداد تقرير المقارنة. عروضك لم تتأثر — يُرجى المحاولة مرة أخرى.'
    : 'We could not prepare the comparison report. Your quotes are unaffected — please try again.';
};
function Comparison({ inqId, token, lang }) {
  const reduce = useReducedMotion();
  const [a, setA] = useState(null); const [busy, setBusy] = useState(true); const [note, setNote] = useState(''); const [code, setCode] = useState('');
  // quote_compare answers degraded:true, with analysis.disclaimer, when no model answered — the
  // only path under the hold. The card was titled "Expert comparison report" regardless (audit
  // 14 Sep 2026), so a rules-only ranking now says it is one, in both languages.
  const [degraded, setDegraded] = useState(false);
  // THE COMPARISON IS WAITED FOR, AND SAYS IT IS STILL WORKING (it_engineer, 12 Nov 2026; ledger 1642; final audit H2/E3).
  // quote_compare stays high effort (it prices and judges); a fresh one took 42-74 s on the 11-12 Nov journey runs (opus,
  // ai_cost_log quote_comparison p50 53.3 s, max 70.6 s) while this call waited the default 30 s, so the customer read "We
  // could not prepare the comparison report" 2 of 2 times. It waits COMPARE_PDF_TIMEOUT_MS (150 s, the edge wall) as the
  // PDF does, and after STILL_WORKING_MS the panel says it is still working. prevented by:
  // scripts/checks/a_long_reasoning_call_is_waited_for_with_progress.test.mjs
  const [slow, setSlow] = useState(false);
  useEffect(() => { let on = true; setBusy(true); setCode(''); setSlow(false); const late = setTimeout(() => { if (on) setSlow(true); }, STILL_WORKING_MS); call('quote_compare', { inquiry_id: inqId, lang }, token, COMPARE_PDF_TIMEOUT_MS).finally(() => clearTimeout(late)).then((j) => { if (!on) return; setBusy(false); if (j && j.ok && j.analysis) { setA(j.analysis); setDegraded(!!j.degraded || !!j.analysis.disclaimer); } else if (j && j.note) setNote(j.note); else if (j && j.error) { setCode(String(j.error)); setNote(compareErrText(j.error, lang)); } else setNote(''); }).catch(() => { if (on) { setBusy(false); } }); return () => { on = false; clearTimeout(late); }; }, [inqId, lang]);
  const arr = (x) => Array.isArray(x) ? x : [];
  if (busy) return (<div className="qd-panel p-3.5" aria-busy="true"><div className={cn(S.sub, 'text-primary')}>{t(lang, 'cmp_preparing')}</div>{slow ? <div className={cn(S.sub, 'mt-1')}>{t(lang, 'cmp_still')}</div> : null}<div className="mt-2 flex flex-col gap-1.5" aria-hidden><span className="redact redact-bar" style={{ width: '72%' }} /><span className="redact redact-bar" style={{ width: '48%' }} /><span className="redact redact-bar" style={{ width: '60%' }} /></div></div>);
  if (!a) return note ? (<div className="rounded-lg border border-border bg-secondary/20 p-3" title={code || undefined}><div className={S.sub}>{note}</div></div>) : null;
  return (<M.div initial={reduce ? false : { opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: reduce ? 0 : 0.3 }} className="qd-panel p-3.5">
    <div className="mb-1 flex flex-wrap items-center gap-2">
      <div className={cn(S.sub, 'font-bold text-primary')}>{t(lang, degraded ? 'cmp_title_rules' : 'cmp_title') + (a.trade ? ' · ' + a.trade : '')}</div>
      {degraded ? <span className="rounded-full border border-warn/40 bg-warn/10 px-2 py-0.5 text-[10.5px] font-semibold text-warn-fg">{t(lang, 'cmp_badge_rules')}</span> : null}
    </div>
    {degraded && a.disclaimer ? <div className={cn(S.sub, 'mb-1.5')}>{a.disclaimer}</div> : null}
    {a.bottom_line ? <div className={cn(S.sub, 'text-foreground font-semibold mb-1.5')}>{a.bottom_line}</div> : null}
    {a.overview ? <div className={cn(S.sub, 'mb-2')}>{a.overview}</div> : null}
    {arr(a.top3).length ? <div className="mb-2"><div className={cn(S.sub, 'font-semibold text-foreground')}>{t(lang, 'cmp_top')}</div>{arr(a.top3).map((r, i) => (<div key={i} className={cn(S.sub, 'mt-0.5')}><span className="text-primary font-semibold">#{r.rank} {supLabel(r.label, lang)}</span> — {r.why}{r.tradeoff ? (' (' + t(lang, 'cmp_catch') + ': ' + r.tradeoff + ')') : ''}</div>))}</div> : null}
    {arr(a.quotes).map((q, i) => (<div key={i} className="mt-2 border-t border-border/60 pt-2"><div className={cn(S.sub, 'font-semibold text-foreground')}>{supLabel(q.label, lang)}{q.price != null ? (' — ' + aed(q.price)) : ''}</div>
      {/* §10 per-dimension scores, relative to the other shortlisted quotes; unstated scores 1. */}
      {(q.price_score != null || q.delivery_score != null || q.quality_score != null) ? (
        <div className="mt-1 flex flex-wrap gap-x-3 gap-y-0.5" title={q.score_reason || ''}>
          {[[t(lang, 'cmp_price'), q.price_score], [t(lang, 'cmp_delivery'), q.delivery_score], [t(lang, 'cmp_quality'), q.quality_score]]
            .filter(([, v]) => v != null)
            .map(([label, v]) => (
              <span key={String(label)} className={S.sub}>
                <span className="text-muted-foreground">{label}: </span>
                <span className="text-foreground" aria-label={v + ' ' + t(lang, 'cmp_of5')}>{'★'.repeat(Math.max(0, Math.min(5, Number(v) || 0)))}{'☆'.repeat(Math.max(0, 5 - Math.max(0, Math.min(5, Number(v) || 0))))}</span>
              </span>
            ))}
        </div>
      ) : null}
      {q.score_reason ? <div className={cn(S.sub, 'text-muted-foreground')}>{q.score_reason}</div> : null}
      {q.getting ? <div className={S.sub}>{q.getting}</div> : null}{arr(q.missing_from_request).length ? <div className={cn(S.sub, 'text-warn-fg')}>{t(lang, 'cmp_missing') + arr(q.missing_from_request).join('; ')}</div> : null}{arr(q.spec_deviation).length ? <div className={cn(S.sub, 'text-warn-fg')}>{t(lang, 'cmp_dev') + arr(q.spec_deviation).join('; ')}</div> : null}{arr(q.flags).length ? <div className={cn(S.sub, 'text-danger')}>{arr(q.flags).join('; ')}</div> : null}</div>))}
    {arr(a.watch_outs).length ? <div className={cn(S.sub, 'text-danger mt-2')}>{t(lang, 'cmp_watch') + arr(a.watch_outs).join(' · ')}</div> : null}
    {/* THE QUALITY CHECK (ledger 1018, 29 Sep 2026): quotes held while the supplier corrects them, and the points a
        quote released after its wait did not correct, beside its label. Codes from quote_compare, words in portalText. */}
    {a.quality_check && (Number(a.quality_check.held) > 0 || arr(a.quality_check.notes).length) ? (<div className="mt-2 border-t border-border/60 pt-2">
      <div className={cn(S.sub, 'font-semibold text-foreground')}>{t(lang, 'qq_title')}</div>
      {Number(a.quality_check.held) > 0 ? <div className={S.sub}>{tf(lang, 'qq_held', { n: Number(a.quality_check.held), h: Number(a.quality_check.hours) || 24 })}</div> : null}
      {arr(a.quality_check.notes).map((n, i) => (<div key={i} className={cn(S.sub, 'text-warn-fg')}>{supLabel(n.label, lang)}: {arr(n.flags).map((f) => qualityReason(f, lang)).filter(Boolean).join('; ')} ({tf(lang, 'qq_uncorrected', { h: Number(a.quality_check.hours) || 24 })})</div>))}
    </div>) : null}
    {a.advice ? <div className={cn(S.sub, 'mt-2 text-foreground')}>{a.advice}</div> : null}
    {/* §10 EXPORT: customer_api compare_pdf, ownership-checked; the document goes to the meeting. */}
    <ExportComparison inqId={inqId} token={token} lang={lang} />
    <div className={cn(S.sub, 'mt-2 text-muted-foreground/70 text-[11px]')}>{t(lang, 'cmp_guidance')}</div>
  </M.div>);
}
// The download owns a failure the report must survive: a PDF that cannot be built must not blank
// the analysis the customer is reading.
function ExportComparison({ inqId, token, lang }) {
  const [busy, setBusy] = useState(false); const [err, setErr] = useState('');
  // The report opens in a tab opened inside the click (see openDocument), in the customer's
  // language, with the other language one click away.
  const mine = lang === 'ar' ? 'ar' : 'en'; const other = mine === 'ar' ? 'en' : 'ar';
  const go = (docLang) => async () => {
    setBusy(true); setErr(''); let j = null;
    try {
      const ok = await openDocument(lang, async () => { j = await call('customer_api', { action: 'compare_pdf', inquiry_id: inqId, lang: docLang }, token, COMPARE_PDF_TIMEOUT_MS); return j && (j.url || j.pdf_url || j.file_url) || null; });
      if (!ok) setErr(errText(j, lang, 'cmp_save_fail'));
    } catch (_e) {
      setErr(t(lang, 'cmp_save_fail'));
    } finally { setBusy(false); }
  };
  // W10: the same side-by-side rows as the PDF, as a spreadsheet. The server sends the text with a
  // UTF-8 BOM so Excel opens Arabic headers correctly; the browser only wraps it in a file.
  const csv = async () => {
    setBusy(true); setErr('');
    try {
      const j = await call('customer_api', { action: 'compare_csv', inquiry_id: inqId, lang }, token);
      if (j && j.ok && typeof j.csv === 'string') {
        const a = document.createElement('a');
        // window.URL: this module imports SUPA_URL under the name URL.
        a.href = window.URL.createObjectURL(new Blob([j.csv], { type: 'text/csv;charset=utf-8' }));
        a.download = j.filename || 'comparison.csv'; a.click();
        setTimeout(() => window.URL.revokeObjectURL(a.href), 4000);
      } else setErr(errText(j, lang, 'cmp_csv_fail'));
    } catch (_e) {
      setErr(t(lang, 'cmp_csv_fail'));
    } finally { setBusy(false); }
  };
  return (<div className="mt-2">
    <div className="flex flex-wrap gap-2">
      <Button size="sm" variant="secondary" disabled={busy} onClick={go(mine)}>{busy ? t(lang, 'cmp_saving') : t(lang, 'cmp_save')}</Button>
      <Button size="sm" variant="ghost" lang={other} disabled={busy} onClick={go(other)}>{other === 'ar' ? 'التقرير بالعربية (PDF)' : 'Report in English (PDF)'}</Button>
      <Button size="sm" variant="outline" disabled={busy} onClick={csv}>{t(lang, 'cmp_csv')}</Button>
    </div>
    {err ? <div className={cn(S.err, 'mt-1')} role="alert">{err}</div> : null}
  </div>);
}
export { LevelledRows, Comparison };
