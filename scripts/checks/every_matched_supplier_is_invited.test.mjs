// sales_engineer, 12 Oct 2026. Founder ruling of 24 Sep 2026: ANY number of suppliers may quote on a request;
// "top 3" is ONLY the comparison report's recommendation. Sandbox run 1c94fa6a (S07) measured a one-trade request
// with four capable suppliers inviting three: sales_engineer's match capped each trade at
// decision_policy.match_max_fanout_per_trade (3) and the request at match_max_fanout (5), and the short-of-quotes
// sweep widened by at most match_max_fanout.
//
// This check fails if an invitation count cap comes back on either path that writes inquiry_matches:
//   1. supabase/functions/sales_engineer/ (the match action, actions/operator.ts) — the match reads neither dial, stops on no count, and asks
//      fn_match_capability for every candidate (MATCH_ALL), not a top N;
//   2. fn_rfq_short_of_quotes_tick — its winning definition (MANIFEST order, then files noted as pending) reads no
//      fanout dial and puts no LIMIT on the candidates it invites.
// Comments are stripped before matching, so the prose that explains the rule cannot trip it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { definitions } from '../lib/canonical_sql.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => fs.readFileSync(path.join(REPO, p), 'utf8');
const tsCode = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`])\/\/.*$/gm, '$1');
const sqlCode = (s) => s.replace(/--.*$/gm, '');
const DIAL = new RegExp('match_max_' + 'fanout');

test('sales_engineer invites every matched supplier: no fanout dial, no count stop, no top-N limit', () => {
  const src = tsCode(functionSource('sales_engineer'));
  assert.ok(!DIAL.test(src), 'sales_engineer reads a fanout dial again');
  assert.ok(!/picked\.length\s*>=|usedByTrade/.test(src), 'a count stop is back in the pick loop');
  // 12 Nov 2026 (founder ruling 1647, analysis services/REPORT.md 3.7, slice 5): every supplier above the floor is
  // invited EXCEPT one matched through a partner while 3 or more own-team suppliers matched (and the request does not
  // span two trades he partly does himself). invitedUnderPartnerRule never drops a supplier with no partner hit, so no
  // own-team supplier is capped by a count: proved by supabase/functions/_shared/partner_match.test.ts.
  assert.match(src, /const picked = invitedUnderPartnerRule\(aboveFloor, serviceKeys\);/, 'the invited list is no longer every supplier above the floor (bar the partner rule)');
  const rule = tsCode(read('supabase/functions/_shared/partner_match.ts'));
  assert.match(rule, /if \(!throughPartner\(r\)\) return true;/, 'the partner rule can drop a supplier who does the work himself');
  assert.match(src, /const headroom = MATCH_ALL;/, 'fn_match_capability is asked for a top N again');
  const cap = tsCode(read('supabase/functions/_shared/supplier_capability.ts')).match(/export const MATCH_ALL = (\d+);/);
  assert.ok(cap && Number(cap[1]) >= 10000, 'MATCH_ALL is no longer far above any trade list');
});

test('the short-of-quotes sweep invites every new match: no fanout dial, no LIMIT', () => {
  const pending = fs.readdirSync(path.join(REPO, 'scripts/sql/pending')).filter((f) => f.endsWith('.txt'))
    .map((f) => `scripts/sql/${f.replace(/\.txt$/, '.sql')}`);
  const order = [...read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()), ...pending]
    .filter((p) => /^scripts\/sql\/[^/]+\.sql$/.test(p) && fs.existsSync(path.join(REPO, p)));
  let win = null;
  for (const p of order) for (const d of definitions(read(p))) if (d.name === 'fn_rfq_short_of_quotes_tick') win = { p, stmt: d.stmt };
  assert.ok(win, 'fn_rfq_short_of_quotes_tick has no definition');
  const body = sqlCode(win.stmt);
  assert.ok(!DIAL.test(body), `${win.p}: the sweep reads a fanout dial again`);
  const loop = body.slice(body.indexOf('fn_match_capability('), body.indexOf('insert into public.inquiry_matches'));
  assert.ok(!/\blimit\b/i.test(loop), `${win.p}: the sweep limits the suppliers it invites again`);
  assert.match(loop, /,\s*100000\)\s*m/, `${win.p}: fn_match_capability is asked for a top N again`);
});
