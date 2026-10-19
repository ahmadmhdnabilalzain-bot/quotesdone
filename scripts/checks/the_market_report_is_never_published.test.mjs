// THE MARKET REPORT IS INTERNAL AND NEVER PUBLISHED (ceo, 5 Oct 2026, backlog T5 ledger 1019).
//
// WHAT FAILS IF THE CAUSE RETURNS:
//   * any publishing surface reads ceo_market_report: the site (src/), the edge functions that publish
//     (public_site, marketing*), a blog/article/social/sitemap routine in scripts/sql;
//   * the table loses its internal-only shape (audience CHECK, RLS with a deny policy, the anon/authenticated revoke);
//   * the body stops going through the #1164 supplier-name guard before it is stored or mailed;
//   * the binding finding stops acting (no improvement for the sales engineer), or the founder is asked to approve;
//   * production, in ONE aborted transaction: the _probe.sql answers PROBE OK (see the pending note).
//
//   node --test scripts/checks/the_market_report_is_never_published.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const OWN = 'the_ceo_writes_an_internal_uae_market_report_every_month';
const src = readFileSync(join(REPO, 'scripts/sql', `${OWN}.sql`), 'utf8');

const walk = (dir, out = []) => {
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) { if (n !== 'node_modules') walk(p, out); } else out.push(p);
  }
  return out;
};

test('no publishing surface names the report table', () => {
  const surfaces = [
    ...walk(join(REPO, 'src')),
    ...readdirSync(join(REPO, 'supabase/functions')).filter((d) => d === 'public_site' || d.startsWith('marketing'))
      .flatMap((d) => walk(join(REPO, 'supabase/functions', d))),
    ...readdirSync(join(REPO, 'scripts/sql')).filter((f) => f.endsWith('.sql') && !f.startsWith(OWN)
      && /blog|article|social|sitemap|publish|public_site|geo/.test(f)).map((f) => join(REPO, 'scripts/sql', f)),
  ];
  const hits = surfaces.filter((p) => /ceo_market_report\b/.test(readFileSync(p, 'utf8')));
  assert.deepEqual(hits, [], 'a publishing surface reads the internal market report');
});

test('the table is internal-only by construction', () => {
  assert.match(src, /audience\s+text not null default 'internal' check \(audience = 'internal'\)/);
  assert.match(src, /alter table public\.ceo_market_report enable row level security;/);
  assert.match(src, /as permissive for all to public using \(false\) with check \(false\);/);
  assert.match(src, /revoke all on public\.ceo_market_report from anon, authenticated;/);
  assert.match(src, /revoke execute on function public\.fn_ceo_market_report\(date, boolean\) from public, anon, authenticated;/);
  assert.match(src, /revoke execute on function public\.fn_ceo_market_report_now\(date\) from public, anon, authenticated;/);
});

test('the #1164 guard runs on the body before it is stored or mailed, and a hit withholds the detail', () => {
  const i = src.indexOf('v_named := public.fn_supplier_named_in(v_body)');
  assert.ok(i > 0, 'the body is not checked for supplier names');
  assert.ok(i < src.indexOf('insert into public.ceo_market_report ('), 'checked after it is stored');
  assert.match(src, /p_detail => case when v_named is null then v_body/);
});

test('a demo run never takes the real month or touches a real improvement (review of #1192)', () => {
  assert.match(src, /primary key \(month, include_demo\)/);
  assert.match(src, /where month = v_m and include_demo = p_include_demo\) then/);
  assert.match(src, /where not p_include_demo and i\.source_kind = 'market_report'/);
  assert.match(src, /if v_bind is not null and not p_include_demo then/);
});

test('it acts and the founder is only notified', () => {
  assert.match(src, /fn_ceo_improvement_open\('market_report', to_char\(v_m, 'YYYY-MM'\), 'sales_engineer'/);
  assert.match(src, /perform public\.fn_ceo_improvement_close\(r\.id/);
  assert.match(src, /p_kind => 'ceo_market_report'/);
  assert.match(src, /p_level => 'info', p_kind => 'ceo_market_report'/, 'the founder notice is no longer info-level');
  assert.match(src, /'ceo\.market_report', 'ceo', '1 day', 'fn_ceo_market_report_now'/);
});
