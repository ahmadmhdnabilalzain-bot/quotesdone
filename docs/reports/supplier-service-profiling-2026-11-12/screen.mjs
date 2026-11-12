// What the supplier would see on the Services tab today for each reading, DERIVED from the stored proposal shape and the tab's own rules
// (servicesState / preparedTrades / profileStateOf / ServicesTab.tsx), not walked in a browser.
import { readFileSync } from 'node:fs';
const dump = readFileSync(new URL('../taxonomy_dump.txt', import.meta.url), 'utf8').split('\n');
const nServices = Object.fromEntries(dump.map((l) => { const m = /\| ([a-z0-9_]+)(?: \^[a-z0-9_]+)? = .*? :: (.*)$/.exec(l); return m ? [m[1], m[2].split('; ').length] : null; }).filter(Boolean));
const keys = Object.fromEntries(JSON.parse(readFileSync(new URL('../profiles/answer_keys.json', import.meta.url), 'utf8')).profiles.map((p) => [p.id, p]));
const rows = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const english = (s) => !/[؀-ۿﭐ-﷿ﹰ-﻿]/.test(s);
console.log('| profile | run | banner he reads | "Services we understood" rows (with his sentence shown) | trades on the checklist | checkboxes in all | asked anything |', '\n|---|---|---|---|---|---|---|');
for (const r of rows) r.runs.forEach((u, i) => {
  const signup = keys[r.id].signup_trade;
  const trades = [...new Set([...u.trades.map((t) => t.code), signup])];
  const state = u.ok && u.trades.length ? 'summary + keywords' : u.why === 'held' ? '"We are still reading your documents..." (no end)' : u.ok ? '"found no service we could match"' : '"We are still reading..."';
  console.log(`| ${r.id} | ${i + 1} | ${state} | ${u.services.length} (${u.services.filter((s) => english(s.quote)).length}) | ${trades.join(', ')}${u.trades.some((t) => t.code === signup) ? '' : ' (sign-up trade only)'} | ${trades.reduce((n, t) => n + (nServices[t] || 0), 0)} | no |`);
});
