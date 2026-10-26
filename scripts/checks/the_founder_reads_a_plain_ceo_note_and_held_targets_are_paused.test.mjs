// 19 Oct 2026, seat ceo. The founder's CEO daily note (notifications 101297) and weekly review (105207) read as code:
// "Directive #293 ... Bring invitations_delivered back to its path: it reads 0 against 644.5", "0 opened, 9 escalated".
// And the targets of the supplier campaign he switched off were graded misses and re-issued every week.
// These assert, on the canonical definitions (a pending file wins over MANIFEST):
//   1. a held target is paused, never a miss, and the hold comes from data (founder_hold), not a name in code;
//   2. the founder-facing text carries no metric code, directive id or raw count;
//   3. nothing in the founder's text is shortened with a bare left() (no mid-word cut).
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
const body = (name) => {
  const re = new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${name}\\s*\\(`, 'i');
  const file = newest(re);
  assert.ok(file, `no file defines ${name}`);
  const src = readFileSync(file, 'utf8');
  const start = src.search(re);
  const end = src.indexOf('$function$', src.indexOf('$function$', start) + 10);
  return { file, text: src.slice(start, end) };
};
// String literals a routine writes into the founder's text (SQL quoting: '' is a quote inside a literal).
const literals = (sqlText) => [...sqlText.matchAll(/'((?:[^']|'')*)'/g)].map((m) => ({ s: m[1], at: m.index }));
const CODE = /\b[a-z]+_[a-z0-9_]+\b|#\d|\bdirective\b|\bmetric\b/i;

test('a target the founder has held is paused, driven by the hold register', () => {
  const held = body('fn_held_targets');
  assert.match(held.text, /from public\.founder_hold/, `${held.file}: held targets must come from founder_hold`);
  assert.match(held.text, /flag_released_value/, `${held.file}: a hold must lift when its switch reads the released value`);
  assert.doesNotMatch(held.text, /released_at/, `${held.file}: the flag is the only way a hold lifts`);
  const guard = body('fn_founder_hold_is_lifted_only_by_its_flag');
  assert.match(guard.text, /tg_op = 'DELETE'[\s\S]*raise exception[\s\S]*new\.flag_key is distinct from old\.flag_key[\s\S]*raise exception/, `${guard.file}: deleting a hold or re-pointing its flag must be refused`);
  assert.match(readFileSync(held.file, 'utf8'), /before update or delete on public\.founder_hold/, 'the guard must be attached to founder_hold');
  const verdict = body('fn_ceo_target_daily_verdict');
  assert.match(verdict.text, /when p\.metric_key = any \(v_held\) then 'paused'[\s\S]*?else 'miss' end/, `${verdict.file}: a held target must grade paused before any miss branch`);
  assert.match(body('fn_ceo_year_plan_status').text, /fn_held_targets\(\)[\s\S]*then 'paused'/, 'the plan status must report a held target paused');
  const dir = body('fn_ceo_directive_run');
  assert.match(dir.text, /source_kind = 'target_miss'[\s\S]*?fn_held_targets\(\)[\s\S]*?set status = 'paused'/, `${dir.file}: an open target directive on a held target must close paused, not re-issue`);
  const wk = body('fn_ceo_weekly_review');
  assert.match(wk.text, /not \(x->>'met'\)::boolean and not coalesce\(\(x->>'paused'\)::boolean, false\)/, `${wk.file}: a paused target must open no weekly action`);
  for (const [n, t] of [['fn_ceo_target_daily_verdict', verdict], ['fn_ceo_directive_run', dir], ['fn_ceo_weekly_review', wk]]) {
    assert.doesNotMatch(t.text, /invitations_delivered|'registrations_submitted'/, `${n}: the paused set must come from data, not a name in code`);
  }
});

test('the founder text has no metric codes, ids or counts', () => {
  const daily = body('fn_ceo_daily_run').text;
  const start = daily.indexOf('v_lines := v_lines ||');
  const founder = daily.slice(start, daily.indexOf('insert into public.ceo_day', start))
    + daily.slice(daily.indexOf('v_body :='), daily.indexOf('update public.ceo_day set note_handoff_id'));
  const lines = body('fn_ceo_weekly_review_lines').text;
  const weekly = lines.slice(lines.indexOf('v_items := v_items || case'), lines.indexOf('end loop;', lines.indexOf('v_items := v_items || case')));
  const pdf = body('fn_ceo_weekly_review_pdf_blocks').text;
  const pdfTexts = [...pdf.matchAll(/'text', '((?:[^']|'')*)'/g)].map((m) => m[1]).join('\n');
  for (const [where, src] of [['daily note', founder], ['weekly lines', weekly], ['weekly pdf', pdfTexts]]) {
    for (const { s, at } of literals(src)) {
      if (/(when |->>|'t', |fn_[a-z_]+\()$/.test(src.slice(Math.max(0, at - 30), at))) continue;   // keys, not text
      if (/^(t|text|h2|h3|li|p|note|items|hold|runway|recipient_role|founder|level|info|kind|founder_brief|dedupe_key|event|detail|FMDay DD Mon|FMDay DD Mon YYYY|Dy DD Mon|FM999,999,990|, |, \(\[\^,\]\*\)\$| and \\1|ceo_day:|ceo|customer_support|delivery\.request|ceo_day)$/.test(s)) continue;
      assert.doesNotMatch(s, CODE, `${where}: founder text "${s}" reads like a code or an id`);
    }
  }
  const weeklyEmail = body('fn_ceo_weekly_review_deliver').text;
  assert.doesNotMatch(weeklyEmail, /opened, %s escalated|targets missed this week/, 'the weekly email must not report raw action counts');
  assert.doesNotMatch(daily, /Directive #%s[^\n]*\n[^\n]*'detail', left\(v_body/, 'the daily note must not carry the directive list');
});

test('nothing in the founder text is cut with a bare left()', () => {
  const daily = body('fn_ceo_daily_run').text;
  assert.doesNotMatch(daily, /'detail', left\(/, 'the daily note body must not be cut mid-word');
  for (const n of ['fn_ceo_weekly_review_lines', 'fn_ceo_weekly_review_pdf_blocks', 'fn_ceo_weekly_review_text']) {
    assert.doesNotMatch(body(n).text, /\bleft\(/, `${n}: founder text must not be cut mid-word`);
  }
});

test('every target has plain words, and none of them is a code', () => {
  const f = newest(/insert into public\.target_label/i);
  const src = readFileSync(f, 'utf8');
  const block = src.slice(src.search(/insert into public\.target_label/i), src.indexOf('on conflict (target_key)', src.search(/insert into public\.target_label/i)));
  const pairs = [...block.matchAll(/\('([a-z0-9_]+)', '((?:[^']|'')*)'\)/g)];
  assert.ok(pairs.length >= 20, `${f}: target_label must name every target`);
  for (const [, , words] of pairs) assert.doesNotMatch(words, CODE, `${f}: label "${words}" reads like a code`);
});
