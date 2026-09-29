// fn_supplier_invite_eligible_ids() is the set form of fn_supplier_invite_eligible(leads), written so the
// daily supplier list and the 10:00 send fit PostgREST's 8 s statement timeout (28 Sep 2026: the list
// timed out every evening and was never produced). Two statements of one rule can drift, so this reads the
// live mirror and fails when a table the row rule consults is missing from the set rule, or when the set
// callers go back to the per-row call. The apply probe proved lead-for-lead equality on 17,401 leads.
// It also reads the repository (below) so an Arabic or doubly-defined invitation fails before it is applied.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';

const MIRROR = new URL('../../supabase/schema/full_schema.sql', import.meta.url);
const body = (sql, name) => {
  const i = sql.search(new RegExp(`FUNCTION public\\.${name}\\(`));
  if (i < 0) return null;
  const s = sql.indexOf('$', sql.indexOf(' AS ', i));
  const tag = sql.slice(s, sql.indexOf('$', s + 1) + 1);
  const a = s + tag.length;
  return sql.slice(a, sql.indexOf(tag, a));
};

test('the set rule consults every table the row rule does', { skip: !existsSync(MIRROR) }, () => {
  const sql = readFileSync(MIRROR, 'utf8');
  const row = body(sql, 'fn_supplier_invite_eligible');
  const set = body(sql, 'fn_supplier_invite_eligible_ids');
  if (!set) return;   // not applied yet: the pending note covers it
  const sendable = body(sql, 'fn_email_sendable') ?? '';
  const tables = (t) => new Set([...t.matchAll(/\b(?:public\.)?(sanctions_ban|supplier_screening_hit|notifications|email_domain_mx|email_platform_domain|email_suppressions|email_block_pattern)\b/g)].map((m) => m[1]));
  const want = new Set([...tables(row), ...(row.includes('fn_email_sendable') ? tables(sendable) : [])]);
  const have = tables(set);
  for (const t of want) assert.ok(have.has(t), `the row rule reads ${t}; the set rule does not`);
});

test('the list and the candidates read the set, not the per-row call', { skip: !existsSync(MIRROR) }, () => {
  const sql = readFileSync(MIRROR, 'utf8');
  if (!body(sql, 'fn_supplier_invite_eligible_ids')) return;
  for (const f of ['fn_supplier_campaign_next_list', 'fn_supplier_invite_candidates']) {
    assert.doesNotMatch(body(sql, f), /fn_supplier_invite_eligible\(l\)/, f);
  }
});

// REVIEW OF #1051 AND #1012 (29 Sep 2026): both PRs copied an OLD body of fn_supplier_invite_candidates (MANIFEST
// 1757: Arabic copy, /ar/portal links) instead of the canonical always-English body (then MANIFEST 1824, #964; since
// #1070, MANIFEST 1835), so applying either would have brought Arabic invitations back, and each would have
// overwritten the other.
const ROOT = new URL('../../', import.meta.url);
const read = (p) => readFileSync(new URL(p, ROOT), 'utf8');
const code = (s) => s.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
const defines = (name) => new RegExp(`create or replace function public\\.${name}\\(`, 'i');
const fnText = (sql, name) => {
  const m = sql.match(defines(name));
  if (!m) return null;
  const ends = ['$function$;', '$fn$;'].map((t) => sql.indexOf(t, m.index)).filter((i) => i > 0);
  return sql.slice(m.index, Math.min(...ends));
};
const manifest = read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim()).filter((l) => l.startsWith('scripts/sql/'));
const inManifest = new Set(manifest);
const pendingSql = readdirSync(new URL('scripts/sql/', ROOT)).filter((f) => f.endsWith('.sql'))
  .map((f) => 'scripts/sql/' + f).filter((f) => !inManifest.has(f));
const ENGLISH_SINCE = 'scripts/sql/the_supplier_invitation_ends_with_one_question_and_is_always_english.sql';

test('every definition of fn_supplier_invite_candidates from #964 on, applied or pending, is English only', () => {
  const since = manifest.indexOf(ENGLISH_SINCE);
  assert.ok(since >= 0, `${ENGLISH_SINCE} is no longer in MANIFEST.txt`);
  const files = [...manifest.slice(since), ...pendingSql].filter((f) => defines('fn_supplier_invite_candidates').test(code(read(f))));
  assert.ok(files.length > 0);
  for (const f of files) {
    const fn = fnText(code(read(f)), 'fn_supplier_invite_candidates');
    assert.match(fn, /'en'::text as lang/, `${f}: the language is no longer fixed to English`);
    assert.doesNotMatch(fn, /invite_body_ar|invite_subject_ar|then 'ar'|\/ar\/|'\/' \|\| e\.lang/, `${f}: reads or chooses the Arabic invitation`);
    assert.match(fn, /'\{\{link\}\}', (public\.fn_supplier_invite_link\(v_site, e\.claim_token, e\.id\)|v_site \|\| '\/en\/portal\?t=')/,
      `${f}: {{link}} is not the English portal link`);
  }
});

// RE-REVIEW (29 Sep 2026): #1070 moved the canonical body (MANIFEST 1835) while this PR was open, so a copy of 1824
// was stale again. A pending redefinition must be the LATEST applied body with only the pending PR's own lines changed.
// #1051 (the set read and the ref'd link) is applied (MANIFEST 1844); the pending redefinition is now ledger 1018's
// stalled-request tier (sales_engineer, 29 Sep 2026): exactly one line of the applied body is replaced, and what is added
// is the rescue CTE and the -1 tier ahead of the unchanged 'recruit' tier. A copy of an older body fails here.
test('a pending fn_supplier_invite_candidates is the latest applied body with only the stalled-request tier added', () => {
  const lines = (f) => fnText(read(f), 'fn_supplier_invite_candidates').split('\n').map((l) => l.trimEnd());
  const canonFile = [...manifest].reverse().find((f) => defines('fn_supplier_invite_candidates').test(code(read(f))));
  const canon = lines(canonFile);
  for (const f of pendingSql.filter((p) => defines('fn_supplier_invite_candidates').test(code(read(p))))) {
    const mine = lines(f);
    const gone = canon.filter((l) => !mine.includes(l)).map((l) => l.trim());
    const added = mine.filter((l) => !canon.includes(l)).map((l) => l.trim()).filter((l) => !l.startsWith('--'));
    assert.deepEqual(gone, ["case when exists (select 1 from public.supply_gap g where g.status = 'recruit' and g.trade = any(coalesce(c.invite_trades, '{}'::text[]))"],
      `${f} is not ${canonFile} with only the recruit tier's first line re-worded`);
    assert.deepEqual(added, [
      'rescue as materialized (select x.trades, x.emirate from public.stalled_inquiry_rescue x where x.cleared_at is null and not x.fixture and cardinality(x.trades) > 0),',
      "case when exists (select 1 from rescue x where x.trades && coalesce(c.invite_trades, '{}'::text[])",
      "and (x.emirate is null or x.emirate = 'UAE' or x.emirate = c.emirate)) then -1",
      "when exists (select 1 from public.supply_gap g where g.status = 'recruit' and g.trade = any(coalesce(c.invite_trades, '{}'::text[]))",
    ], `${f} adds more to ${canonFile} than the stalled-request tier`);
  }
});

test('at most one pending file redefines fn_supplier_invite_candidates (two would overwrite each other)', () => {
  const p = pendingSql.filter((f) => defines('fn_supplier_invite_candidates').test(code(read(f))));
  assert.ok(p.length <= 1, `pending files each redefine fn_supplier_invite_candidates: ${p.join(', ')}`);
});

test('the invitation link takes no language, is the English portal, and carries its ref', () => {
  const files = [...manifest, ...pendingSql].filter((f) => defines('fn_supplier_invite_link').test(code(read(f))));
  assert.ok(files.length > 0, 'fn_supplier_invite_link is defined nowhere');
  for (const f of files) {
    const fn = fnText(code(read(f)), 'fn_supplier_invite_link');
    assert.match(fn, /fn_supplier_invite_link\(p_site text, p_token uuid, p_lead_id bigint\)/, `${f}: the link takes a language again`);
    assert.match(fn, /'\/en\/portal\?t=' \|\| p_token::text/, `${f}: the link is not the English portal`);
    assert.match(fn, /utm_source=invite&utm_medium=email&utm_campaign=supplier_invite&utm_content=lead-' \|\| p_lead_id::text/, `${f}: the link lost its ref`);
  }
});

test('the apply probe raises on failure; it does not only return a row', () => {
  const sql = read('scripts/sql/the_invitation_pool_is_read_once_as_a_set_so_the_daily_list_fits_its_timeout.sql');
  assert.ok(sql.includes('do $probe$'), 'the probe block is gone');
  const probe = code(sql.slice(sql.indexOf('do $probe$')));
  for (const what of ['the set rule and the row rule disagree', 'are not English', 'are not /en/portal with their ref', 'do not end with the question']) {
    assert.ok(new RegExp(`raise exception 'PROBE FAILED: [^']*${what}`).test(probe), `the probe no longer raises when it finds candidates that ${what}`);
  }
});
