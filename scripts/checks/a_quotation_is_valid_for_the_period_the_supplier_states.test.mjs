// A QUOTATION IS VALID FOR THE PERIOD THE SUPPLIER STATES, AND FOR NO PERIOD WE CHOOSE (sales_engineer, 15 Nov 2026).
// Founder ruling, ledger 1697: "Quotation validity depends on what the supplier mentions in his quotation. No specific period".
//
// Guards scripts/sql/a_quotation_is_valid_for_the_period_the_supplier_states_and_for_no_period_we_choose.sql and the code
// beside it. The behaviour (every wording of its probe read, the trigger on insert and update, the reveal period) is proved by that
// file's _probe.sql on a local Postgres 16; this fails when the shape that makes it true is taken away. Reads only the
// repository.
//   node --test scripts/checks/a_quotation_is_valid_for_the_period_the_supplier_states.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyState } from '../lib/pending_sql.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const NAME = 'a_quotation_is_valid_for_the_period_the_supplier_states_and_for_no_period_we_choose';
const SQL = read(`scripts/sql/${NAME}.sql`);
// the code only: a comment may describe the old defect in its own words
const CODE = SQL.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const fn = (name) => {
  const at = CODE.search(new RegExp(`create or replace function public\\.${name}\\(`, 'i'));
  assert.ok(at >= 0, `${name} is defined`);
  const tag = CODE.slice(at).match(/as (\$\w*\$)/i)[1];
  const body = CODE.indexOf(tag, at) + tag.length;
  return CODE.slice(at, CODE.indexOf(tag, body));
};

test('the trigger fills an expiry only from what the supplier stated, on insert and whenever his validity changes', () => {
  const t = fn('trg_quote_expiry');
  assert.match(t, /NEW\.expires_at := public\.fn_quote_validity_until\(NEW\.validity, NEW\.quotation_date, coalesce\(NEW\.created_at, now\(\)\)\)/);
  assert.doesNotMatch(t, /\bdays\s+int\s*:=|make_interval\(days => days\)|interval '\d+ days?'/i, 'a period of its own');
  assert.match(CODE, /create or replace trigger trg_quote_expiry_b before insert or update of validity, quotation_date on public\.quotes/);
  assert.doesNotMatch(CODE, /drop trigger if exists trg_quote_expiry_b/, 'replaced in place, no gap');
});

test('the reading has no default, no cap and no fallback period: what it cannot read is NULL', () => {
  const u = fn('fn_quote_validity_until');
  assert.match(u, /if v = '' then return null; end if;/);
  assert.match(u, /else\s+return null;\s+end if;\s+return \(\(v_end \+ 1\)::timestamp at time zone 'Asia\/Dubai'\);/, 'nothing read: NULL');
  assert.match(u, /coalesce\(p_quotation_date, \(coalesce\(p_received, now\(\)\) at time zone 'Asia\/Dubai'\)::date\)/, 'counted from the quotation date, else the day received');
  assert.doesNotMatch(u, /v_end := v_from \+ (14|30|180)\b|least\(v_end|greatest\(v_end/, 'a period or a cap of its own');
});

test('the review of 15 Nov: no year moved far, no start we cannot know, no fraction read whole, the validity\'s own period', () => {
  const d = fn('fn_quote_validity_date'), u = fn('fn_quote_validity_until');
  // item 2: a last day without a year moves forward only when near; a start never moves forward
  assert.match(d, /if v_dt > p_from \+ 183 then return null; end if;/);
  assert.match(d, /elsif p_start and v_dt > p_from \+ 183 then\s+v_dt := \(v_dt - interval '1 year'\)::date;/);
  assert.doesNotMatch(d, /make_date\(v_year \+ 1, v_mon, v_day\)/, 'the unbounded roll forward');
  // item 3: the old fallback counted an unknown start from the quotation's date
  assert.doesNotMatch(u, /coalesce\(public\.fn_quote_validity_date\(v_since, v_from\), v_from\)/);
  assert.match(u, /v_head ~ '\\m\(lpo\|po\|p\\\.o\|purchase\|order/);
  assert.match(u, /then\s+return null;\s+end if;\s+v_dt := public\.fn_quote_validity_date\(substring\(v_anchor from '\^\[\^;\|\]\{0,40\}'\), v_from, true\);/);
  // item 4: N/M before a unit states no number of its own
  assert.ok(u.includes("v := regexp_replace(v, '(?<![\\d/.])\\d+ ?/ ?\\d+(?![\\d/.])"));
  // item 5: the clause after valid / validity / صلاحية is read
  assert.match(u, /m := regexp_match\(v, '\^\(\.\*\?\)\(' \|\| c_valid \|\| '\.\*\)\$'\);/);
});

test('the reveal period counts a quotation with no stated validity as live and fills no period for it', () => {
  for (const name of ['fn_sales_engineer_reveal_period_until', 'fn_sales_engineer_live_quotes_left', 'fn_sales_engineer_tells_unchosen_suppliers']) {
    const b = fn(name);
    assert.match(b, /\(q\.expires_at is null or q\.expires_at > now\(\)\)/, name);
    assert.doesNotMatch(b, /created_at \+ interval/, `${name} fills a missing expiry`);
  }
  assert.match(fn('fn_sales_engineer_reveal_period_until'), /least\(p_cap, coalesce\(max\(coalesce\(q\.expires_at, p_cap\)\), now\(\)\)\)/);
});

test('every routine the file creates is closed to PUBLIC, anon and authenticated, with search_path pinned', () => {
  for (const sig of ['fn_quote_validity_month(text)', 'fn_quote_validity_date(text, date, boolean)', 'fn_quote_validity_until(text, date, timestamptz)',
    'trg_quote_expiry()', 'fn_sales_engineer_reveal_period_until(uuid, timestamptz)', 'fn_sales_engineer_live_quotes_left(uuid)',
    'fn_sales_engineer_tells_unchosen_suppliers(uuid, text, timestamptz)']) {
    assert.ok(CODE.includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), sig);
  }
  const defs = CODE.match(/create or replace function[\s\S]*?\bas \$fn\$/gi);
  assert.equal(defs.length, 7);
  for (const d of defs) assert.match(d, /set search_path to 'public', 'pg_temp'/, d.slice(0, 80));
  assert.match(CODE, /set local lock_timeout = '1500ms';/);
});

test('the file waits for the release with its note and its probe, and writes no row', () => {
  // waiting with a reason, or applied (16 Nov 02:24-03:xx UTC, 0db1eacfc) with a MANIFEST line: never both, never neither
  const st = applyState(`scripts/sql/${NAME}.sql`);
  assert.ok(st.applied !== (st.note !== null), 'pending and in MANIFEST at once, or neither');
  if (st.note !== null) assert.ok(st.note.length > 40);
  const probeSt = applyState(`scripts/sql/${NAME}_probe.sql`);
  assert.match(probeSt.note || '', /^A PROBE/); assert.ok(!probeSt.applied, 'the probe is applied');
  assert.doesNotMatch(CODE, /\bupdate public\.quotes\b/i, 'a backfill belongs in its own statement');
  const probe = read(`scripts/sql/${NAME}_probe.sql`);
  assert.match(probe, /raise exception 'CHK<<%>>', case when fails = '' then 'PROBE OK' else 'PROBE FAILED:' \|\| fails end;/);
  assert.match(probe, /'subject to stock', null, null/);
});

test('submit_quote records the printed date only when it is read for certain, and no edge function writes an expiry on a quote', () => {
  const q = read('supabase/functions/supplier_api/actions/quotes.ts');
  // written only with a date, and a write refused because the column is not applied yet is tried once without it (deploy order)
  assert.match(q, /const qDate = quotationDateOf\(body\.quotation_date\);/);
  assert.match(q, /\.\.\.\(qDate \? \{ quotation_date: qDate \} : \{\}\)/);
  assert.doesNotMatch(q, /quotation_date: quotationDateOf\(/, 'the key is never written as null');
  assert.doesNotMatch(q, /admin\.from\('quotes'\)\.(?:update\(det\)|insert\(\{ \.\.\.det)/, 'a quotes write that bypasses writeQuoteRow');
  const lib = read('supabase/functions/supplier_api/lib/quote_acceptance.ts');
  assert.match(lib, /PENDING_QUOTE_COLUMNS = \['quotation_date'\]/);
  assert.match(lib, /COLUMN_NOT_APPLIED = new Set\(\['PGRST204', '42703'\]\)/);
  const walk = (d, out = []) => { for (const n of readdirSync(join(ROOT, d))) { const p = d + '/' + n; if (statSync(join(ROOT, p)).isDirectory()) walk(p, out); else if (/\.ts$/.test(p) && !/\.test\.ts$/.test(p)) out.push(p); } return out; };
  const bad = walk('supabase/functions').filter((p) => /from\('quotes'\)\.(?:insert|update|upsert)\([^)]*expires_at/.test(read(p)));
  assert.deepEqual(bad, []);
  assert.match(read('supabase/functions/supplier_api/quote_review_flow/submit.ts'), /quotation_date: w\.quotation_date \|\| undefined/);
  assert.match(read('supabase/functions/_shared/reasoned_suppliers.ts'), /key: 'quotation_date'/);
});

test('a customer reads "Validity: not stated by the supplier" when he stated none, never a date of ours', () => {
  const card = read('src/components/me/requests/QuoteCard.tsx');
  assert.match(card, /\{!exp && !q\.validity && <div className=\{cn\(S\.sub, 'mt-1'\)\}>\{t\(lang, 'q_validity_not_stated'\)\}<\/div>\}/);
  const txt = read('src/components/me/portalText.ts');
  assert.ok(txt.includes("q_validity_not_stated: 'Validity: not stated by the supplier'"));
  assert.ok(txt.includes("q_validity_not_stated: 'صلاحية العرض: لم يذكرها المورّد'"));
  assert.match(read('supabase/functions/_shared/quote_documents/quote_document.ts'), /validity \|\| T\('Not stated by the supplier', 'لم يذكرها المورّد'\)/);
});

test('no seat, brief or FAQ states a validity period of QuotesDone\'s own', () => {
  const FIXED = /Quotation validity is 30 days|Quotations are valid 30 days|valid 30 days on QuotesDone|valid for 30 days from submission|quotation validity 30 days;|Quotation validity 30 days|It is valid for 30 days|صلاحية العرض 30 يوم|صلاحية عرض السعر 30 يوم|صالحة 30 يوم|صالح 30 يوماً على/;
  const files = ['src/content/marketing.json', 'knowledge/brief/company.md', 'knowledge/brief/supplier_howto.md',
    ...readdirSync(join(ROOT, 'knowledge/seats')).filter((f) => f.endsWith('.json')).map((f) => 'knowledge/seats/' + f),
    ...readdirSync(join(ROOT, 'knowledge/brief/seats')).map((f) => 'knowledge/brief/seats/' + f)];
  const bad = files.filter((p) => FIXED.test(read(p)));
  assert.deepEqual(bad, []);
});
