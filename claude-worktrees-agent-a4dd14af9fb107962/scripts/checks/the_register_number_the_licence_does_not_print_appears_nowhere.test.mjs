// THE REGISTER NUMBER THE LICENCE DOES NOT PRINT APPEARS NOWHERE: not in the repository, not in the signed registry.
//
//   node --test scripts/checks/the_register_number_the_licence_does_not_print_appears_nowhere.test.mjs
//
// 15 Sep 2026, agent: ceo. The DET trade licence prints no Commercial Register number (founder, 14 Sep 2026; the
// number and why it is never printed are recorded in docs/legal/company_identity_sources.json, "not_printed").
// identity_numbers_come_from_the_licence.test.mjs guards the surfaces the SITE renders. It could not see the rest:
// measured 15 Sep 2026, six public.legal_documents rows (the text a customer signs, and the registry's copy of five
// policies) still printed the number a day after the site dropped it, and so did three agent_knowledge rows, three
// kb_chunks, a knowledge seed, a brand SQL file and three committed snapshots of the source. This check reads
// every tracked text file and, with a management token, the live stores.
//
// The number is matched by shape and never spelled here, so this file cannot find itself: the digits are written
// with a bracketed last digit, and the wording with \s between its words.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const NUMBER = /288350[3]/;
const WORDING = /Commercial\s+Register\s+No|السجل\s+التجاري\s+رقم/i;
const REISSUE = 'scripts/sql/the_legal_registry_is_reissued_without_the_register_number_the_licence_does_not_print.sql';

// Files that must name the number to do their job. Nothing else may.
const RECORDS = new Set([
  'docs/legal/company_identity_sources.json', // the ledger: which number is never printed, and why
  'scripts/checks/identity_numbers_come_from_the_licence.test.mjs', // asserts its absence from the site
  'scripts/checks/supplier_agreement_v12_notices_go_to_the_confirmed_whatsapp.test.mjs', // asserts its absence
  'supabase/functions/_shared/supplier_charge_documents.test.ts', // asserts its absence from a charge pack
]);
// legal.json keeps the archived Supplier Agreement v10 verbatim: it is the text suppliers accepted, a record.
const ARCHIVED_LEGAL_KEYS = new Set(['supplier-agreement-v10']);

// Applied history: a scripts/sql file ordered BEFORE the re-issue in MANIFEST.txt wrote a text that was true to the
// version it signed, and is superseded by the re-issue. A file ordered after it may not bring the number back.
function supersededSql() {
  const order = readFileSync(join(ROOT, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).map((l) => l.trim()).filter((l) => l.endsWith('.sql'));
  const at = order.indexOf(REISSUE);
  assert.ok(at >= 0, `${REISSUE} is not in scripts/sql/MANIFEST.txt`);
  return new Set(order.slice(0, at));
}

test('no tracked text file carries the register number or its wording, outside the named records', () => {
  const history = supersededSql();
  const files = execFileSync('git', ['ls-files', '-z'], { cwd: ROOT, maxBuffer: 1 << 26 }).toString('utf8').split('\0').filter(Boolean);
  const bad = [];
  for (const f of files) {
    if (RECORDS.has(f) || history.has(f)) continue;
    const p = join(ROOT, f);
    if (!existsSync(p)) continue; // deleted in the working tree
    const buf = readFileSync(p);
    if (buf.includes(0)) continue; // binary
    const s = buf.toString('utf8');
    if (f === 'src/content/legal.json') {
      for (const [k, d] of Object.entries(JSON.parse(s))) {
        if (ARCHIVED_LEGAL_KEYS.has(k)) continue;
        const t = JSON.stringify(d);
        if (NUMBER.test(t) || WORDING.test(t)) bad.push(`${f} ${k}`);
      }
      continue;
    }
    for (const re of [NUMBER, WORDING]) {
      const m = re.exec(s); // a bare test first: a context pattern over multi-megabyte snapshots is slow
      if (m) bad.push(`${f}: ${s.slice(Math.max(0, m.index - 50), m.index + m[0].length + 20)}`);
    }
  }
  assert.deepEqual(bad, []);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

test('no live legal document, signed body, knowledge row or routine carries the register number', { skip: hasToken ? false : 'no Supabase management token in this environment' }, async () => {
  // strpos on the number split across two literals: a regex over kb_chunks ran past a 30s statement timeout.
  const has = (col) => `(strpos(${col}, '2883' || '503') > 0 or ${col} ~* 'commercial[[:space:]]+register[[:space:]]+no')`;
  const stores = [
    ['legal_documents', `select string_agg(slug || ' ' || version, ', ') hits, count(*)::int n from public.legal_documents where ${has('body_html')}`],
    ['pages', `select string_agg(slug, ', ') hits, count(*)::int n from public.pages where ${has('html')}`],
    ['app_secrets', `select string_agg(key, ', ') hits, count(*)::int n from public.app_secrets where ${has('value')}`],
    ['agent_knowledge', `select string_agg(id::text, ', ') hits, count(*)::int n from public.agent_knowledge where strpos(content, '2883' || '503') > 0`],
    ['kb_chunks', `select string_agg(id::text, ', ') hits, count(*)::int n from public.kb_chunks where strpos(content, '2883' || '503') > 0`],
    ['routines', `select string_agg(p.oid::regprocedure::text, ', ') hits, count(*)::int n from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and ${has('p.prosrc')}`],
  ];
  const rows = [];
  for (const [store, q] of stores) rows.push({ store, ...(await sql(`set statement_timeout = '90s'; ${q}`))[0] });
  assert.equal(rows.length, 6, 'every store answered');
  assert.deepEqual(rows.filter((r) => r.n > 0), []);
});
