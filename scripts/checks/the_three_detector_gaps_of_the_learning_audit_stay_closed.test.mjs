// The three detector gaps found closing the 29 parked IT handoffs (7 Oct 2026, PR #1281):
//   1. claim_lookup's hourly launch-path probe was refused as a stranger (watch:refusal_rate:claim_lookup, 100487);
//   2. a debounced GitHub backup kick left no heartbeat row (duty:workflow_heartbeat:dropbox_kick, 130872);
//   3. run_silent judged a subject against a rhythm it had left, a burst, or refused outside traffic
//      (wa_templates_watch x8, unsubscribe x2, ai_gateway: 11 false findings).
// Each test reads the canonical source (a pending file wins over MANIFEST) and fails if the gap comes back.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const newest = (re) => {
  const defines = (f) => existsSync(f) && re.test(readFileSync(f, 'utf8'));
  const pending = readdirSync('scripts/sql/pending').map((n) => `scripts/sql/${n.replace(/\.txt$/, '.sql')}`).filter(defines);
  const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim())
    .filter((l) => l.endsWith('.sql')).filter(defines);
  return pending.at(-1) ?? manifest.at(-1);
};
const routine = (name) => {
  const head = new RegExp(String.raw`create\s+or\s+replace\s+function\s+public\.${name}\s*\(`, 'i');
  const file = newest(head);
  assert.ok(file, `no canonical file defines ${name}`);
  const src = readFileSync(file, 'utf8');
  const at = src.search(head);
  const end = src.slice(at).search(/\n(end\s*)?\$(fn|function)\$;/i);
  return [file, src.slice(at, at + end)];
};

test('gap 1: claim_lookup\'s launch-path probe proves itself and its refusal is marked fixture', () => {
  const lp = readFileSync('supabase/functions/_shared/launch_path.ts', 'utf8');
  assert.match(lp, /id: 'api:claim_lookup'[^\n]*withProbe\(/, 'launch_path.ts: the claim_lookup probe must present the probe credential');
  const cl = readFileSync('supabase/functions/claim_lookup/index.ts', 'utf8');
  assert.match(cl, /annotate\([\s\S]{0,300}invalid_link[\s\S]{0,300}probeCaller\(admin, req, 'claim_lookup'\)/,
    'claim_lookup: the invalid-link refusal must be annotated by probeCaller');
  const scoped = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/)
    .concat(readdirSync('scripts/sql/pending').map((n) => `scripts/sql/${n.replace(/\.txt$/, '.sql')}`))
    .filter((f) => f.endsWith('.sql') && existsSync(f))
    .some((f) => /array_append\(scope, 'claim_lookup'\)\s*\n\s*where context = 'fn\.resilience_ping'/.test(readFileSync(f, 'utf8')));
  assert.ok(scoped, 'no applied or pending file scopes fn.resilience_ping to claim_lookup');
});

test('gap 2: a debounced scheduler kick is recorded before fn_backup_kick returns', () => {
  const [file, b] = routine('fn_backup_kick');
  const deb = b.slice(b.indexOf('pg_try_advisory_xact_lock'), b.indexOf("'debounced: a kick"));
  assert.match(deb, /insert into public\.agent_runs[\s\S]*'backup_kick'[\s\S]*'debounced', true/,
    `${file}: the debounce branch returns without a heartbeat row; dropbox_kick reads it as no run`);
});

test('gap 3: run_silent judges silence against the rhythm a subject still keeps', () => {
  const [file, b] = routine('fn_it_detect');
  const d2 = b.slice(b.indexOf('A SUBJECT THAT HAS STOPPED RUNNING'), b.indexOf("v_key := 'run_silent:'"));
  assert.match(d2, /from it_runs7\s*(--[^\n]*\n\s*)?where not refused0/, `${file}: D2 builds a rhythm from refused calls again`);
  assert.match(d2, /c\.p50 >= 1/, `${file}: D2 accepts a sub-minute burst as a schedule again`);
  assert.match(d2, /c\.prev_gap/, `${file}: D2 must look at the last two gaps before calling a rhythm changed`);
});

// D2's qualifying WHERE, lifted from the canonical fn_it_detect and evaluated in JS on gap histories, so a
// change to the SQL changes what this test sees.
const qualifies = (d2) => {
  const where = d2.slice(d2.indexOf('where c.samples >= 10'), d2.search(/\nloop/))
    .replace(/--[^\n]*/g, '').replace(/^where /, '');
  const js = where
    .replace(/coalesce\(s\.public_surface, false\)/g, 'false')
    .replace(/coalesce\(([\w.]+), 0\)/g, '($1 ?? 0)')
    .replace(/greatest\(/g, 'Math.max(')
    .replace(/\bnot\b/g, '!').replace(/\band\b/g, '&&');
  return new Function('c', `return (${js});`);
};
const subject = (gaps) => ({ samples: gaps.length, hours: 24, p50: 30, p90: 31, last_gap: gaps.at(-1), prev_gap: gaps.at(-2) });

test('gap 3: a subject that stops, runs once and stops again is still watched; one settled into a new rhythm is not', () => {
  const [file, b] = routine('fn_it_detect');
  const ok = qualifies(b.slice(b.indexOf('A SUBJECT THAT HAS STOPPED RUNNING'), b.indexOf("v_key := 'run_silent:'")));
  const steady = Array(40).fill(30);
  assert.equal(ok(subject(steady)), true, `${file}: a steady 30-minute subject must be watched`);
  assert.equal(ok(subject([...steady, 300])), true,
    `${file}: stopped 5 h, ran once, now silent again -- it must still be watched (review of #1283)`);
  assert.equal(ok(subject([...steady, 1185, 1200])), false,
    `${file}: two 20-hour gaps after a 30-minute rhythm is a new cadence (wa_templates_watch after #1049)`);
});
