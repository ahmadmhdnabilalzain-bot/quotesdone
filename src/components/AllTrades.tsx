'use client';
// THE WHOLE OFFER, NOT A SAMPLE. Founder, 14 Sep 2026: never show a selected few categories as if
// they were the scope — a visitor who does not see their trade assumes we cannot do it. This lists
// every trade in src/content/categories.json (read from public.category_specs; QuotesDone covers
// every trade in the UAE except food & beverage for now), with a filter box. Each row pre-fills the
// job box through the same hand-off as the homepage "Get quotes for this".
import { useState } from 'react';
import { useTranslations, useLocale } from 'next-intl';
import cats from '@/content/categories.json';
import { GetQuotesFor } from '@/components/GetQuotesFor';

type Cat = { code: string; en: string; ar: string };
const ITEMS = (cats as { items: Cat[] }).items;

export function AllTrades() {
  const t = useTranslations('cats');
  const ar = useLocale() === 'ar';
  const [q, setQ] = useState('');
  const needle = q.trim().toLowerCase();
  const rows = ITEMS
    .map((c) => ({ code: c.code, label: ar ? c.ar : c.en, other: ar ? c.en : c.ar }))
    .sort((a, b) => a.label.localeCompare(b.label, ar ? 'ar' : 'en'))
    .filter((c) => !needle || c.label.toLowerCase().includes(needle) || c.other.toLowerCase().includes(needle));
  return (
    <section id="all-trades" className="container-x scroll-mt-20 py-beat-s">
      <div className="mb-6 flex flex-wrap items-baseline justify-between gap-4 border-b border-line pb-5">
        <h2 className="font-head text-[clamp(20px,2vw,24px)] font-semibold tracking-snug text-white">{t('allTrades')}</h2>
        <span className="tabular font-mono text-label text-faint">{t('tradesN', { n: ITEMS.length })}</span>
      </div>
      <label className="block max-w-md">
        <span className="sr-only">{t('search')}</span>
        <input
          type="search"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder={t('search')}
          className="w-full rounded-btn border border-line2 bg-surf/60 px-4 py-2.5 text-[15px] text-paper outline-none placeholder:text-faint focus-visible:border-teal"
        />
      </label>
      {rows.length ? (
        <ul className="mt-6 grid gap-x-8 sm:grid-cols-2 lg:grid-cols-3">
          {rows.map((c) => (
            <li key={c.code} className="flex items-center justify-between gap-3 border-b border-[var(--line)] py-3">
              <span className="min-w-0 text-[15px] text-paper">{c.label}</span>
              <GetQuotesFor category={c.code} label={t('getQuotes')} draft={t('draft', { trade: c.label })} />
            </li>
          ))}
        </ul>
      ) : null}
      <p className="mt-6 text-copy text-muted">{t('noMatch')}</p>
    </section>
  );
}
