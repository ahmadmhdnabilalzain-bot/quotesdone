'use client';
// THE MONTHLY SCORECARD (29 Sep 2026, sales_engineer, founder_instruction 1013 item 2).
//
// Last month's response speed, win rate and customer rating, each beside the supplier's trade average. The
// average is shown only when at least 3 suppliers of the trade have that measure (fn_supplier_scorecard returns
// null otherwise, and this says why rather than printing a number over one or two companies). One tip, chosen by
// rule on the server. With no data at all it says "not enough data yet".
//
// ENGLISH ONLY, on /ar as well: the founder's rule (28 Sep 2026) is that a supplier is always written to in
// English, and this card is the same text the monthly e-mail carries. The block is lang="en" dir="ltr" so an
// Arabic page lays it out correctly.
import { useCallback, useEffect, useState } from 'react';
import { call } from './api';
import { PanelError, PanelLoading, panelErrorCode } from './PanelState';

type Metric = { you: number | null; trade_average: number | null; trade_suppliers: number; better: 'lower' | 'higher' };
export type Card = {
  month_label: string; trade: string | null; trade_label: string | null; enough_data: boolean; message: string | null;
  metrics: { response_hours: Metric; win_rate: Metric; rating: Metric };
  activity: { requests_sent: number; quoted: number; won: number; ratings: number };
  min_suppliers_for_average: number; tip: { code: string; text: string };
};

const ROWS: { key: keyof Card['metrics']; label: string; fmt: (n: number) => string }[] = [
  { key: 'response_hours', label: 'Response speed (median hours to your first quote)', fmt: (n) => `${n} h` },
  { key: 'win_rate', label: 'Win rate (quotes the customer chose you on)', fmt: (n) => `${Math.round(n * 100)}%` },
  { key: 'rating', label: 'Customer rating', fmt: (n) => `${n} / 5` },
];

export function verdict(m: Metric): string | null {
  if (m.you == null || m.trade_average == null) return null;
  if (m.you === m.trade_average) return 'on your trade average';
  const ahead = m.better === 'lower' ? m.you < m.trade_average : m.you > m.trade_average;
  return ahead ? 'better than your trade' : 'behind your trade';
}

export default function SupplierScorecard({ token }: { token?: string | null }) {
  const [card, setCard] = useState<Card | null>(null);
  const [err, setErr] = useState('');
  const load = useCallback(async () => {
    setErr('');
    const j = await call('supplier_portal', { action: 'scorecard' }, token);
    if (!j || !j.ok || !j.card) { setErr(panelErrorCode(j)); return; }
    setCard(j.card as Card);
  }, [token]);
  useEffect(() => { load(); }, [load]);

  if (err) return <PanelError lang="en" code={err} onRetry={load} />;
  if (!card) return <PanelLoading lang="en" />;
  const min = card.min_suppliers_for_average || 3;
  return (
    <section lang="en" dir="ltr" aria-labelledby="qd-scorecard-h" className="qd-panel p-5">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="qd-scorecard-h" className="text-[15.5px] font-bold text-foreground">Your scorecard, {card.month_label}</h2>
        {card.trade && <span className="font-mono text-[11.5px] text-muted-foreground">Compared with {card.trade_label || card.trade} suppliers</span>}
      </div>
      {!card.enough_data ? (
        <p className="mt-2 text-[13.5px] text-muted-foreground">Not enough data yet: no request, quote or rating of yours in {card.month_label}.</p>
      ) : (
        <dl className="mt-3 grid gap-3 sm:grid-cols-3">
          {ROWS.map(({ key, label, fmt }) => {
            const m = card.metrics[key];
            const v = verdict(m);
            return (
              <div key={key} className="rounded-lg border border-(--line) p-3">
                <dt className="text-[12px] text-muted-foreground">{label}</dt>
                <dd className="mt-1 text-[20px] font-semibold text-foreground">{m.you == null ? <span className="text-[13px] font-normal text-muted-foreground">not enough data yet</span> : fmt(m.you)}</dd>
                <dd className="mt-1 text-[12px] text-muted-foreground">
                  {m.trade_average == null ? `Trade average shown once ${min} suppliers of your trade have this measure.` : `Trade average ${fmt(m.trade_average)}${v ? `: ${v}` : ''}.`}
                </dd>
              </div>
            );
          })}
        </dl>
      )}
      <p className="mt-4 text-[13.5px] leading-[1.6] text-foreground"><strong>One thing to improve:</strong> {card.tip.text}</p>
    </section>
  );
}
