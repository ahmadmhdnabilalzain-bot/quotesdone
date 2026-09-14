// EVERY STATEMENT IN scripts/sql CLOSES EVERY PARENTHESIS IT OPENS, AND NO MORE.
//
// 14 SEP 2026. Twice in one day a PR shipped an extra `)` closing a nested jsonb_build_object:
// PR #645 (the_accountant_chases_what_a_silent_supplier_owes.sql, two lines) and PR #641
// (the_it_engineer_takes_on_seven_more_duties.sql). The dry run (`node scripts/apply_sql.mjs <file>`)
// never makes Postgres parse a file whose dependencies are not live yet, so both surfaced only at
// the real production apply and left production half-applied. A paren count needs no database, so
// it runs here, in the job that carries no Supabase token.
//
// What it does: walks the text, ignores everything inside 'strings' (with '' and, for E'...', \'
// escapes), "quoted identifiers", -- comments and nested /* */ comments, and counts ( and ) per
// statement. A $tag$ marker is TRANSPARENT — function and DO bodies are code and are scanned too,
// which is where both defects lived — except that the text between the markers of a dollar quote
// that is NOT a routine body (a $q$...$q$ literal handed to format() or execute) is a string.
// `;` ends a statement; depth must be 0 there, and must never go negative.
//
// What it does not do: parse SQL. Balanced parentheses is a necessary property, not a sufficient
// one. There is no allow-list: a finding is either a scanner defect (fix the scanner) or a file
// that would not parse if re-applied (fix the file, by its owner).
//
// MEASURED 14 SEP 2026 on its first run: 1,055 files, 7 findings, and none was a scanner defect.
// "Production accepted every applied file" is true of the file AS APPLIED, not as committed:
//   * ce2272e (#526, 8 Sep) replaced six cron.schedule calls with a removal comment and left each
//     call's closing `$job$);` / `$cron$);` behind: kb_embed_backfill_boost,
//     ops_knowledge_semantic_retrieval, the_canonical_answers_queued_behind_26000_rows,
//     the_priority_filter_was_built_for_three_kinds_and_nothing_ever_passed_it,
//     wiring_for_the_boq_fixture_runner, wiring_for_the_employee_side_of_the_engine.
//   * dfbd98f (6 Sep) deduped pricing_has_no_date_no_discount_and_no_cap.sql 534 -> 470 lines and
//     "was not re-applied"; the dedup left two `and ... cap >= 99999999);` lines after a closed check.
// The same PR (#660) deleted those orphaned tails, and only those, with nothing re-applied: the live objects were never
// affected. The pricing file still has `comment on constraint pricing_config_no_discount_no_cap_ck`
// but no longer the `add constraint` it describes (dfbd98f removed it). The constraint is live, but
// this file alone would fail on a fresh database. That is a missing definition, not a paren count.
//
//   node --test scripts/checks/sql_parentheses_balance.test.mjs        (part of npm test)
//   node scripts/checks/sql_parentheses_balance.test.mjs a.sql b.sql   (also scans the named files)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');
const SQL_DIR = path.join(REPO, 'scripts', 'sql');

const IDENT = /[A-Za-z0-9_$]/;
// A dollar-quote tag: $$ or $name$ where name does not start with a digit. `$1` is a parameter.
const DOLLAR = /^\$(?:[A-Za-z_\u0080-\uFFFF][A-Za-z0-9_\u0080-\uFFFF]*)?\$/;

/** Findings for one SQL text: [{ line, kind, from }]. Empty means balanced. */
export function scan(src) {
  const out = [];
  let depth = 0, line = 1, i = 0, opened = [];
  const n = src.length;
  const skipTo = (end) => { for (; i < end; i++) if (src[i] === '\n') line++; };
  while (i < n) {
    const c = src[i], d = src[i + 1];
    if (c === '\n') { line++; i++; continue; }
    if (c === '-' && d === '-') { while (i < n && src[i] !== '\n') i++; continue; }
    if (c === '/' && d === '*') {
      let nest = 1; i += 2;
      while (i < n && nest) {
        if (src[i] === '/' && src[i + 1] === '*') { nest++; i += 2; continue; }
        if (src[i] === '*' && src[i + 1] === '/') { nest--; i += 2; continue; }
        if (src[i] === '\n') line++;
        i++;
      }
      continue;
    }
    if (c === "'") {
      const esc = /[Ee]/.test(src[i - 1] ?? '') && !IDENT.test(src[i - 2] ?? '');
      i++;
      while (i < n) {
        if (src[i] === '\n') line++;
        if (esc && src[i] === '\\') { i += 2; continue; }
        if (src[i] === "'" && src[i + 1] === "'") { i += 2; continue; }
        if (src[i] === "'") break;
        i++;
      }
      i++; continue;
    }
    if (c === '"') { i++; while (i < n) { if (src[i] === '\n') line++; if (src[i] === '"' && src[i + 1] === '"') { i += 2; continue; } if (src[i] === '"') break; i++; } i++; continue; }
    if (c === '$' && !IDENT.test(src[i - 1] ?? '')) {
      const m = DOLLAR.exec(src.slice(i, i + 64));
      if (m) {
        const tag = m[0];
        const close = src.indexOf(tag, i + tag.length);
        const before = src.slice(Math.max(0, i - 40), i).toLowerCase();
        const isBody = /\b(as|do)\s*$/.test(before);
        if (!isBody && close > 0) { skipTo(close + tag.length); continue; }   // a literal
        i += tag.length; continue;                                              // a body: transparent
      }
    }
    if (c === '(') { depth++; opened.push(line); }
    else if (c === ')') { depth--; opened.pop(); if (depth < 0) { out.push({ line, kind: 'extra )', from: line }); depth = 0; } }
    else if (c === ';') { if (depth !== 0) out.push({ line, kind: `${depth} unclosed (`, from: opened[0] }); depth = 0; opened = []; }
    i++;
  }
  if (depth !== 0) out.push({ line, kind: `${depth} unclosed ( at end of file`, from: opened[0] });
  return out;
}

/** Every file the check covers: every MANIFEST entry (comments skipped) plus every scripts/sql/*.sql. */
export function filesToScan() {
  const manifest = fs.readFileSync(path.join(SQL_DIR, 'MANIFEST.txt'), 'utf8')
    .split(/\r?\n/).map((s) => s.trim()).filter((s) => s && !s.startsWith('#'));
  const onDisk = fs.readdirSync(SQL_DIR).filter((f) => f.endsWith('.sql')).map((f) => `scripts/sql/${f}`);
  return { manifest, all: [...new Set([...manifest, ...onDisk])].sort() };
}

const kinds = (s) => scan(s).map((x) => x.kind).join('|');

test('the shapes that broke #645 and #641 are caught, and a correct one passes', () => {
  assert.equal(kinds("x := a || f('k', g('v', 1)));"), 'extra )');
  assert.equal(kinds("x := f('a)', g(1));"), '');
  assert.notEqual(kinds('x := f(1 ;'), '');
});

test('quoting and comments that must not count', () => {
  assert.equal(kinds("create function f() returns int language plpgsql as $fn$ begin perform g(1); return 1; end $fn$;"), '');
  assert.equal(kinds("do $probe$ begin perform f(1)); end $probe$;"), 'extra )', 'a DO body is scanned');
  assert.equal(kinds("create function f() returns void as $fn$ begin execute format($q$select (%s$q$, 1); end $fn$;"), '', 'nested literal dollar quote');
  assert.equal(kinds("select E'it\\'s (', 1;"), '', "E'' backslash escape");
  assert.equal(kinds("select 'a\\', (1);"), '', 'plain string: backslash is not an escape');
  assert.equal(kinds("prepare p as select f($1, $2);"), '', 'positional parameters');
  assert.equal(kinds("select 1 -- it's (\n;"), '', 'line comment');
  assert.equal(kinds("select /* ( /* ) */ ' */ 1;"), '', 'nested block comment with a quote');
  assert.equal(kinds('select "a(""b" from t;'), '', 'quoted identifier');
  assert.equal(kinds("select $$ ( $$;"), '', 'bare $$ literal');
});

test('every scripts/sql file and MANIFEST entry has balanced parentheses', () => {
  const { manifest, all } = filesToScan();
  assert.ok(manifest.length > 900, `MANIFEST parsed to ${manifest.length} entries — expected ~1000`);
  const findings = [];
  for (const f of all) {
    const p = path.join(REPO, f);
    if (!fs.existsSync(p)) continue;   // canonical_routine_manifest owns missing-file findings
    for (const x of scan(fs.readFileSync(p, 'utf8'))) findings.push(`${f}:${x.line}: ${x.kind} (opened line ${x.from})`);
  }
  console.log(`scanned ${all.length} file(s), ${findings.length} finding(s)`);
  assert.deepEqual(findings, []);
});

// Direct invocation with paths: scan those too (used to check another branch's files).
const direct = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (direct) {
  const named = process.argv.slice(2).filter((a) => a.endsWith('.sql'));
  if (named.length) test('the named files have balanced parentheses', () => {
    const findings = named.flatMap((f) => scan(fs.readFileSync(f, 'utf8')).map((x) => `${f}:${x.line}: ${x.kind} (opened line ${x.from})`));
    assert.deepEqual(findings, []);
  });
}
