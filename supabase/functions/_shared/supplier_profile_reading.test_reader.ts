// A FAKE MODEL FOR THE READER'S TESTS (12 Nov 2026, sales_engineer; ruling 1647). Test code only: imported by *.test.ts, never by a
// function. The tests of storage, outages, long documents and the licence were written against the one-call chooser, which is deleted;
// they now give the reader of @5 the same answers through this model. Its answers go through the REAL two steps (readInTwoSteps:
// checkReading's quote checks, the mapping's key checks) and proposalOf, so what the tests assert is what production does.
//   answer(text) -> { trades: [{ code, quote, services?: [{ key, quote }] }] }, or { ok: false, error } for an outage.
// A service becomes a stated claim (its words are its key) mapped to its key; a trade with no service a stated claim of that trade
// (its words are the trade code) with no key.
import { readInTwoSteps, type ProfileReader, type Taxonomy } from './supplier_profile_reading.ts';

export type FakeTrade = { code: string; quote: string; quotes?: string[]; reason?: string; services?: { key: string; quote: string; licence?: string }[] };
/** `licence`: the model's judgement of whether the licence's activities cover the profile (reader @5 judges the whole profile). */
/** `supply_only` and `licence_activities` (12 Nov 2026, LLM-first audit A4/A5): the reading's answer whether the company only supplies, and
 *  the activities it read off the licence; left out, the answer carries neither, as an answer recorded before that day. */
export type FakeAnswer = { ok?: true; trades: FakeTrade[]; rejected?: unknown[]; licence?: 'yes' | 'partly' | 'no' | 'no_licence'; supply_only?: boolean | null; licence_activities?: string[] } | { ok: false; error: string };

/** The catalogue the fake reads against: every trade and service key an answer names. */
// Since 12 Nov 2026 (review of branch 2) a trade is listed only through a stated claim mapped to a key in it: a trade the fake answers with
// no service maps to a stand-in service of that trade (`<code>.service`), so the tests of pages and text keep seeing the trade listed.
export function fakeTaxonomy(codes: string[], keys: string[] = []): Taxonomy {
  const all = [...new Set([...codes, ...keys.map((k) => k.split('.')[0])])];
  return { trades: all.map((code) => ({ code, label: code.replace(/_/g, ' '), services: [...keys.filter((k) => k.startsWith(code + '.')), `${code}.service`].map((k) => ({ key: k, label: k.split('.')[1].replace(/_/g, ' ') })) })), adjacent: [] };
}

/** A ProfileReader whose model answers `answer(the documents as given)`. `seen` collects every text step A was given. */
export function fakeReader(answer: (text: string) => FakeAnswer | Promise<FakeAnswer>, opts: { seen?: string[]; taxonomy?: Taxonomy } = {}): ProfileReader {
  return async (docs, company) => {
    const given = docs.map((d) => `=== ${d.kind}: ${d.name} ===\n${d.text}`).join('\n\n');
    opts.seen?.push(given);
    const a = await answer(given);
    if ('ok' in a && a.ok === false) return { ok: false, error: a.error };
    const trades = (a as { trades: FakeTrade[] }).trades;
    const tax = opts.taxonomy ?? fakeTaxonomy(trades.map((t) => t.code), trades.flatMap((t) => (t.services ?? []).map((s) => s.key)));
    const evidence = trades.flatMap((t) => (t.services?.length ? t.services.map((s) => ({ words: s.key, quote: s.quote, basis: 'stated', trade: t.code, ...(s.licence ? { licence: s.licence } : {}) }))
      : (t.quotes?.length ? t.quotes : [t.quote]).slice(0, 1).map((q) => ({ words: t.code, quote: q, basis: 'stated', trade: t.code }))));
    const r = await readInTwoSteps(docs, company, tax, (step, _sys, text) => {
      const x = a as { licence?: string; supply_only?: boolean | null; licence_activities?: string[] };
      if (step === 'read') return Promise.resolve({ ok: true as const, content: JSON.stringify({ summary: '', evidence, vague: [], also_ask: [], licence: { covers_profile: x.licence ?? 'partly', note: '',
        ...(x.licence_activities ? { activities: x.licence_activities } : {}) }, ...(x.supply_only !== undefined ? { supply_only: x.supply_only } : {}) }) });
      const known = new Set(tax.trades.flatMap((t) => t.services.map((x) => x.key)));
      const map = [...text.matchAll(/^(\d+)\. (\S+)/gm)].map((m) => ({ i: Number(m[1]), keys: m[2].includes('.') ? [m[2]] : known.has(`${m[2]}.service`) ? [`${m[2]}.service`] : [] }));
      return Promise.resolve({ ok: true as const, content: JSON.stringify({ map }) });
    });
    return r.ok ? { ...r, taxonomy: tax, implications: [] } : r;
  };
}
