// Scores a run of the reader on the hard-profile set against the answer keys (sales_engineer, 12 Nov 2026; ruling 1647;
// docs/reports/2026-11-12-supplier-service-profiling.md 2.2, whose tables it printed).
//   node scripts/e2e/services_hard_profiles/score.mjs <run.json>    -> <run>.scores.json beside it + a markdown table on stdout
// A run row is { id, runs: [{ ms, ok, why, trades: [{code}], services: [{key, delivery?}], questions?: [...] }] }.
import { readFileSync, writeFileSync } from 'node:fs';
const [file] = process.argv.slice(2);
const keys = Object.fromEntries(JSON.parse(readFileSync(new URL('./answer_keys.json', import.meta.url), 'utf8')).profiles.map((p) => [p.id, p]));
const rows = JSON.parse(readFileSync(file, 'utf8'));
const pct = (a, b) => (b ? Math.round((100 * a) / b) + '%' : 'n/a');
const out = [];
for (const r of rows) {
  const k = keys[r.id].key;
  const mustT = new Set(k.must_trades), okT = new Set([...k.must_trades, ...k.ok_trades, ...[...k.must_services, ...k.ok_services, ...k.partner].map((s) => s.split('.')[0])]);
  const mustS = new Set(k.must_services), okS = new Set([...k.must_services, ...k.ok_services]), partner = new Set(k.partner), never = new Set(k.must_not || []);
  const runs = r.runs.map((u) => {
    const T = u.trades.map((t) => t.code), S = u.services.map((s) => s.key);
    // ASKED counts only the questions about what his documents say (vague, a trade with no service, partner, shown); an umbrella card
    // ("companies like yours often also do these") lists a trade's other services and is counted apart, never as found (12 Nov 2026)
    const asked = [...new Set((u.vague || []).flatMap((v) => (v.options || []).flatMap((o) => o.keys || (o.key ? [o.key] : []))))];
    const umb = [...new Set((u.also_ask || []).flatMap((v) => (v.options || []).flatMap((o) => o.keys || (o.key ? [o.key] : []))))];
    const own = u.services.filter((s) => (s.delivery ?? 'own') !== 'partner').map((s) => s.key), viaPartner = u.services.filter((s) => s.delivery === 'partner').map((s) => s.key);
    return { ms: u.ms, outcome: u.ok ? 'proposed' : u.why, trades: T, n_services: S.length,
      trades_found: [...mustT].filter((t) => T.includes(t)), trades_missed: [...mustT].filter((t) => !T.includes(t)), trades_wrong: T.filter((t) => !okT.has(t) || never.has(t)),
      services_found: [...mustS].filter((s) => S.includes(s)), services_asked: [...mustS].filter((s) => !S.includes(s) && asked.includes(s)), services_missed: [...mustS].filter((s) => !S.includes(s) && !asked.includes(s)), own_words: (u.own_words || []).length, vague_n: (u.vague || []).length, option_n: [...(u.vague || []), ...(u.also_ask || [])].reduce((n, v) => n + (v.options || []).length, 0),
      services_fair: S.filter((s) => okS.has(s) && !mustS.has(s)), services_wrong: own.filter((s) => !okS.has(s) && !partner.has(s)).concat(viaPartner.filter((s) => !partner.has(s) && !okS.has(s))),
      partner_as_own: own.filter((s) => partner.has(s)), partner_marked: viaPartner.filter((s) => partner.has(s)), partner_dropped: [...partner].filter((s) => !S.includes(s)),
      trade_only: T.filter((t) => !S.some((s) => s.startsWith(t + '.'))), questions: (u.questions || []).length,
      services_umbrella: [...mustS].filter((s) => !S.includes(s) && !asked.includes(s) && umb.includes(s)),
      // a trade with no service listed AND no question about it (the bar: 0)
      trade_unasked: T.filter((t) => !S.some((s) => s.startsWith(t + '.')) && !asked.some((s) => s.startsWith(t + '.')) && !(u.vague || []).some((v) => v.kind === 'trade_services' || v.kind === 'vague')),
      held: !u.ok };
  });
  out.push({ id: r.id, company: r.company, must_services: mustS.size, must_trades: mustT.size, partner: partner.size, vague: !!k.vague, must_be_empty: !!k.must_be_empty, runs });
}
writeFileSync(file.replace(/\.json$/, '') + '.scores.json', JSON.stringify(out, null, 1));
const L = [];
L.push('| profile | run | time | outcome | trades found/expected | wrong trades | services found/expected (recall) | fair extras | wrong services | partner: as own / marked / dropped | trades with no service | vague questions / options offered | kept in own words |', '|---|---|---|---|---|---|---|---|---|---|---|---|---|');
let F = 0, E = 0, W = 0, TF = 0, TE = 0, TW = 0, PO = 0, PM = 0, PD = 0, n = 0, ms = [];
for (const p of out) p.runs.forEach((u, i) => {
  L.push(`| ${p.id} | ${i + 1} | ${(u.ms / 1000).toFixed(0)} s | ${u.outcome} | ${u.trades_found.length}/${p.must_trades}${u.trades_missed.length ? ' (missed ' + u.trades_missed.join(', ') + ')' : ''} | ${u.trades_wrong.join(', ') || '-'} | ${u.services_found.length}${u.services_asked.length ? ' + ' + u.services_asked.length + ' asked' : ''}/${p.must_services} (${pct(u.services_found.length + u.services_asked.length, p.must_services)}) | ${u.services_fair.length} | ${u.services_wrong.join(', ') || '-'} | ${u.partner_as_own.length} / ${u.partner_marked.length} / ${u.partner_dropped.length} of ${p.partner} | ${u.trade_only.join(', ') || '-'} | ${u.vague_n} / ${u.option_n} | ${u.own_words} |`);
  F += u.services_found.length + u.services_asked.length; E += p.must_services; W += u.services_wrong.length; TF += u.trades_found.length; TE += p.must_trades; TW += u.trades_wrong.length; PO += u.partner_as_own.length; PM += u.partner_marked.length; PD += u.partner_dropped.length; n++; ms.push(u.ms);
});
ms.sort((a, b) => a - b);
// THE BAR of report 3.11, per profile and overall (what code can judge; the vague options and the licence row are read by hand)
const bar = out.map((p) => p.runs.map((u, i) => {
  const rec = p.must_services ? (u.services_found.length + u.services_asked.length) / p.must_services : 1;
  return { id: p.id, run: i + 1, recall: Math.round(rec * 100), recall_ok: rec >= 0.75, wrong: u.services_wrong.length, partner_as_own: u.partner_as_own.length,
    partner_unmarked: u.partner_dropped.length, held: u.held, vague_asked: !p.vague || u.vague_n > 0, trade_unasked: u.trade_unasked, within_110s: u.ms <= 110_000, ms: u.ms };
})).flat();
writeFileSync(file.replace(/\.json$/, '') + '.bar.json', JSON.stringify({ overall_recall: Math.round(100 * F / Math.max(1, E)), bar }, null, 1));
L.push('', `TOTAL over ${n} readings: services ${F}/${E} (${pct(F, E)}), wrong services ${W}; trades ${TF}/${TE} (${pct(TF, TE)}), wrong trades ${TW}; partner services proposed as own ${PO}, marked as partner ${PM}, dropped ${PD}; time p50 ${(ms[Math.floor(ms.length / 2)] / 1000).toFixed(0)} s, max ${(ms[ms.length - 1] / 1000).toFixed(0)} s.`);
console.log(L.join('\n'));
