'use client';
// SPEC §9 — SUPPLIER DISCOVERY AS ITS OWN ACT. "Customer does not search. They ask."
//
// WHAT WAS MEASURED (production, 7 Aug 2026): fn_match_capability and a keyword matcher (dropped
// 15 Sep 2026) both existed, both ranked, and both sat on the DISPATCH path only — discovery happened as a side
// effect of sending an RFQ. No customer action invoked it, so the spec's "Found: 47 suppliers /
// Filtered: UAE, capacity, certification / Top recommendations" screen had nothing behind it.
//
// TWO THINGS THIS DELIBERATELY DOES NOT DO:
//
//   NO COMPANY NAMES. fn_match_capability returns company_name and customer_api's `discover`
//   action drops it before the wire. The entire product sells the supplier's identity at reveal;
//   a free discovery call that listed names would give away the thing being sold. What the
//   customer needs in order to decide whether to send the brief is the COUNT, the FILTERS and the
//   RANKING — and those are all here.
//
//   NO INVENTED COUNT. Production's supplier estate is 20,464 scraped listings of which zero have
//   registered, and fn_is_matchable admits only registered, verified suppliers. So this screen
//   honestly answers "0 found" today and says why, rather than counting rows that could never
//   receive an RFQ.
import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import { SUPA_ANON, SUPA_FN } from '@/lib/supaEnv';

const L = (lang: string, en: string, ar: string) => (lang === 'ar' ? ar : en);
const S = {
  label: 'text-[11px] uppercase tracking-wide text-muted-foreground',
  sub: 'text-[12.5px] text-muted-foreground',
  err: 'text-[12.5px] text-destructive',
};

type Match = {
  label: string; match_pct: number | null; trades: string[] | null; roles: string[] | null;
  product_hits: number; brand_hit: boolean; project_type_hit: boolean;
  track_record: number | null; why: string | null;
};

const EMIRATES = ['', 'Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Umm Al Quwain', 'Fujairah'];

export function SupplierDiscovery({ token, lang = 'en' }: { token: string; lang?: string }) {
  const [trades, setTrades] = useState('');
  const [emirate, setEmirate] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const [res, setRes] = useState<{
    found: number; filters: Record<string, unknown>; matches: Match[]; note?: string;
    why_empty?: { suppliers_holding_trade: number; confirmed_total: number; reason: string } | null;
    unresolved?: string[];
  } | null>(null);
  // The controlled vocabulary, offered as a native datalist. The box stays free text — a customer
  // may still type "marble" and have it resolved to Flooring server-side — but they can now SEE
  // what the matcher knows instead of guessing at it. No library: <datalist> is the platform's own
  // type-ahead and costs nothing.
  const [known, setKnown] = useState<{ code: string; label: string }[]>([]);
  useEffect(() => {
    let live = true;
    fetch(`${SUPA_FN}/customer_api`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token || SUPA_ANON}` },
      body: JSON.stringify({ action: 'trades' }),
    }).then((r) => r.json()).then((j) => { if (live && j && Array.isArray(j.trades)) setKnown(j.trades); }).catch(() => {});
    return () => { live = false; };
  }, [token]);

  const ask = async () => {
    const list = trades.split(/[,\n]/).map((s) => s.trim().toLowerCase()).filter(Boolean).slice(0, 6);
    if (!list.length) { setErr(L(lang, 'Name at least one trade.', 'اذكر تخصصًا واحدًا على الأقل.')); return; }
    setBusy(true); setErr(''); setRes(null);
    try {
      const r = await fetch(`${SUPA_FN}/customer_api`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token || SUPA_ANON}` },
        body: JSON.stringify({ action: 'discover', trades: list, emirate: emirate || null }),
      });
      const j = await r.json().catch(() => null);
      // An error is RENDERED, never swallowed into an empty state — "no suppliers found" and "we
      // could not ask" are different answers and the customer must be able to tell them apart.
      if (!j) setErr(L(lang, 'No response from the matcher.', 'لا استجابة من المطابق.'));
      else if (j.error) setErr(String(j.message || j.error));
      else setRes({ found: Number(j.found) || 0, filters: j.filters || {}, matches: Array.isArray(j.matches) ? j.matches : [], note: j.note, why_empty: j.why_empty || null, unresolved: Array.isArray(j.unresolved) ? j.unresolved : [] });
    } catch (e) {
      setErr((e as Error)?.message || L(lang, 'Network error.', 'خطأ في الشبكة.'));
    } finally { setBusy(false); }
  };

  const f = res?.filters as Record<string, unknown> | undefined;
  const filterChips = f
    ? [
        [L(lang, 'Trades', 'التخصصات'), Array.isArray(f.trades) ? (f.trades as string[]).join(', ') : null],
        [L(lang, 'Location', 'الموقع'), (f.emirate as string) || L(lang, 'anywhere in the UAE', 'كل الإمارات')],
        [L(lang, 'Capability', 'القدرة'), (f.need as string) || null],
        [L(lang, 'Shortlist size', 'حجم القائمة'), f.limit != null ? String(f.limit) : null],
      ].filter((x) => !!x[1])
    : [];

  return (
    <Card className="p-3.5">
      <div className={S.label}>{L(lang, 'Find suppliers', 'ابحث عن موردين')}</div>
      {/* THE INSTRUCTION AND THE CONTROL HAVE TO AGREE. This read 'Ask for what you need — "marble,
          delivered in Dubai"', and the field beneath it splits on commas into a TRADES LIST with a
          separate emirate dropdown. Typing this screen's own worked example produced
          `Trades: marble, delivered in dubai` — a second trade that is not a trade — with the
          location left at "anywhere in the UAE". A example that cannot work is worse than none. */}
      <div className={cn(S.sub, 'mt-1')}>
        {L(lang, 'Name the trades you need, separated by commas, and pick the emirate. We run the same matcher a real request would.',
                 'اذكر التخصصات التي تحتاجها مفصولة بفواصل، واختر الإمارة. نشغّل المطابق نفسه الذي يعمل مع أي طلب حقيقي.')}
      </div>

      <div className="mt-2 flex flex-wrap gap-2">
        <Input value={trades} onChange={(e) => setTrades(e.target.value)}
               placeholder={L(lang, 'marble, tiling', 'رخام، تبليط')} list="qd-trade-codes"
               className="min-w-0 flex-1" aria-label={L(lang, 'Trades', 'التخصصات')} />
        <datalist id="qd-trade-codes">
          {known.map((t) => <option key={t.code} value={t.label} />)}
        </datalist>
        <select value={emirate} onChange={(e) => setEmirate(e.target.value)}
                aria-label={L(lang, 'Emirate', 'الإمارة')}
                className="h-9 rounded-md border border-border bg-background px-2 text-[13px] text-foreground">
          {EMIRATES.map((x) => <option key={x || 'any'} value={x}>{x || L(lang, 'Any emirate', 'أي إمارة')}</option>)}
        </select>
        <Button onClick={ask} disabled={busy}>{busy ? L(lang, 'Searching…', 'جارٍ البحث…') : L(lang, 'Ask', 'اسأل')}</Button>
      </div>

      {err ? <div className={cn(S.err, 'mt-2')}>{err}</div> : null}

      {res ? (
        <div className="mt-3">
          <div className="text-[15px] font-extrabold text-foreground">
            {res.found === 0
              ? L(lang, 'No supplier is shortlisted for this yet', 'لا يوجد مورّد مرشّح لهذا بعد')
              : `${L(lang, 'Found', 'وُجد')} ${res.found} ${L(lang, res.found === 1 ? 'supplier' : 'suppliers', 'مورّد')}`}
          </div>

          {/* §9: the applied filters, shown back. They come from the server's own echo of what it
              used, not from the form state — a filter the matcher silently ignored must not appear
              here as one it honoured. */}
          <div className="mt-1.5">
            <div className={S.label}>{L(lang, 'Applied filters', 'المرشّحات المطبّقة')}</div>
            <div className="mt-1 flex flex-wrap gap-1.5">
              {filterChips.map(([k, v]) => (
                <span key={String(k)} className="rounded-full border border-border bg-secondary/25 px-2 py-0.5 text-[12px] text-foreground">
                  {String(k)}: <span className="text-muted-foreground">{String(v)}</span>
                </span>
              ))}
            </div>
          </div>

          {res.matches.length ? (
            <ul className="mt-2.5 space-y-1.5" role="list">
              {res.matches.map((m, i) => (
                <li key={m.label + i} className="rounded-md border border-border/60 bg-secondary/10 px-2.5 py-2">
                  <div className="flex flex-wrap items-baseline gap-x-2">
                    <span className="font-semibold text-foreground">{i + 1}. {m.label}</span>
                    {m.match_pct != null ? <span className="text-[13px] font-bold text-foreground">{m.match_pct}%</span> : null}
                    {(m.trades || []).length ? <span className={S.sub}>{(m.trades || []).slice(0, 4).join(', ')}</span> : null}
                  </div>
                  {m.why ? <div className={cn(S.sub, 'mt-0.5')}>{m.why}</div> : null}
                </li>
              ))}
            </ul>
          ) : (
            /* A ZERO THAT NAMES ITS OWN REASON. This said "No registered supplier matches that yet",
               which reads as "there are no such suppliers" and points at the wrong fix — buy more
               of them. Measured on production: 15,306 supplier_capabilities rows, every one
               carrying trades, and exactly ONE with confirmed_at set. The matcher gates on that
               confirmation on purpose, so what is missing is confirmations, not suppliers, and the
               two lead to completely different actions. */
            <div className={cn(S.sub, 'mt-2')}>
              {res.why_empty && res.why_empty.reason === 'not_a_trade_we_know'
                ? L(lang,
                    `We do not have a trade called ${(res.unresolved || []).join(', ')}. Pick one from the list in the box — the matcher only knows those.`,
                    `لا يوجد لدينا تخصص باسم ${(res.unresolved || []).join('، ')}. اختر واحدًا من القائمة في الحقل — المطابق لا يعرف سواها.`)
                : res.why_empty && res.why_empty.reason === 'held_but_unconfirmed'
                ? L(lang,
                    `${res.why_empty.suppliers_holding_trade} suppliers on QuotesDone list this trade, but matching only shortlists suppliers who have confirmed their own scope — ${res.why_empty.confirmed_total === 1 ? 'one has' : `${res.why_empty.confirmed_total} have`} done so. Sending the request still puts it in front of them as they confirm.`,
                    `${res.why_empty.suppliers_holding_trade} مورّد لدينا يذكر هذا التخصص، لكن المطابقة تُرشّح فقط من أكّد نطاق عمله بنفسه، وعددهم حتى الآن ${res.why_empty.confirmed_total}. إرسال الطلب يضعه أمامهم فور التأكيد.`)
                : L(lang, 'No supplier on QuotesDone lists that trade yet. Sending the request anyway still puts it in front of suppliers as they register.',
                          'لا يوجد مورّد لدينا يذكر هذا التخصص بعد. إرسال الطلب يضعه أمام الموردين فور تسجيلهم.')}
            </div>
          )}

          {/* A word we could not place is SAID, not dropped. It was silently discarded before, so a
              search for "marble, delivered in Dubai" ran as two trades and reported on neither. */}
          {res.unresolved && res.unresolved.length && res.why_empty?.reason !== 'not_a_trade_we_know' ? (
            <div className={cn(S.sub, 'mt-2')}>
              {L(lang, `Ignored, because it is not a trade we match on: ${res.unresolved.join(', ')}.`,
                       `تم تجاهلها لأنها ليست تخصصًا نطابق عليه: ${res.unresolved.join('، ')}.`)}
            </div>
          ) : null}
          {res.note ? <div className={cn(S.sub, 'mt-2')}>{res.note}</div> : null}
        </div>
      ) : null}
    </Card>
  );
}
