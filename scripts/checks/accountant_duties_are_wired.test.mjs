// THE ACCOUNTANT'S JOB-DESCRIPTION GAPS STAY CLOSED (24 Sep 2026, accountant; ledger 983, seats_v3 GAPS.md).
//
// What fails if a cause comes back:
//   * a duty row (ad spend, runway, UBO) or the routine it names disappears from its owning file
//   * a routine the files create is not revoked or does not pin its search_path
//   * the runtime stops handing the Resend inbound list to fn_accountant_mailbox_check_record
//   * a subscription-register lookup goes back to a LIKE on the vendor (founder_instruction 890)
//   * a seat duty or the registration note tells a seat to raise corporate tax (founder_instruction 344)
//   * sanctions_screen is owned by a seat other than the accountant
//
//   node --test scripts/checks/accountant_duties_are_wired.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
// accountant/index.ts names the whole function: index.ts plus the modules it was split into on 9 Nov 2026.
// A split function's index.ts names the whole function: index.ts plus its modules (accountant, resend_inbound: 9 Nov 2026).
const SRC = (p) => (/^supabase\/functions\/(accountant|resend_inbound)\/index\.ts$/.test(p) ? functionSource(p.split('/')[2]) : R(p));
const FILES = {
  ad: 'scripts/sql/the_accountant_reconciles_meta_invoices_daily_even_at_zero_spend.sql',
  runway: 'scripts/sql/the_accountant_sends_the_ceo_the_runway_against_the_budget_every_month.sql',
  mailbox: 'scripts/sql/the_accountant_says_whether_the_expenses_mailbox_is_quiet_or_the_intake_is_silent.sql',
  ubo: 'scripts/sql/sanctions_and_ubo_checks_have_one_owner_the_accountant.sql',
  ct: 'scripts/sql/corporate_tax_is_ignored_and_the_books_raise_only_vat.sql',
};

test('each duty row names a routine that exists in the repository, and its own file as owner', () => {
  const allSql = readdirSync(join(ROOT, 'scripts/sql')).filter((f) => f.endsWith('.sql')).map((f) => R('scripts/sql/' + f)).join('\n');
  for (const [duty, routine, file] of [
    ['accountant.ad_spend_reconcile', 'fn_accountant_ad_spend_reconcile', FILES.ad],
    ['accountant.runway_report', 'fn_accountant_runway_report_tick', FILES.runway],
    ['accountant.ubo_watch', 'fn_accountant_ubo_watch_tick', FILES.ubo],
  ]) {
    const src = R(file);
    assert.match(src, new RegExp(`\\('${duty.replace('.', '\\.')}', 'accountant', interval '[^']+', '${routine}'`), `${duty} is not scheduled with ${routine}`);
    assert.ok(src.includes(`'${file}')`), `${duty} does not name ${file} as its owner file`);
    assert.match(allSql, new RegExp(`create or replace function public\\.${routine}\\(`, 'i'), `${routine} is defined nowhere`);
  }
});

test('every routine these files create is revoked and pins its search_path', () => {
  for (const file of Object.values(FILES)) {
    const src = R(file);
    for (const m of src.matchAll(/create or replace function public\.(\w+)\(([^)]*)\)/g)) {
      const fn = m[1];
      assert.match(src, new RegExp(`revoke execute on function public\\.${fn}\\([^)]*\\) from public, anon, authenticated`), `${fn} is not revoked`);
      const body = src.slice(m.index).split('$fn$')[0];
      assert.match(body, /set search_path to 'public', 'pg_temp'/, `${fn} has no pinned search_path`);
    }
    for (const m of src.matchAll(/create table if not exists public\.(\w+)/g)) {
      assert.match(src, new RegExp(`create policy \\w+ on public\\.${m[1]}`), `${m[1]} has RLS and no policy`);
    }
  }
});

test('the hourly duties hand the expenses mailbox to the verdict routine', () => {
  const acc = SRC('supabase/functions/accountant/index.ts');
  assert.match(acc, /rpc\('fn_accountant_mailbox_check_record'/, 'the duties action no longer records the mailbox check');
  assert.match(acc, /mailboxMessages\(/, 'the mailbox is no longer filtered by its address');
  for (const v of ['unreadable', 'intake_silent', 'held_waiting', 'mailbox_quiet', 'current']) {
    assert.ok(R(FILES.mailbox).includes(`'${v}'`), `verdict ${v} is gone`);
  }
});

test('no subscription-register lookup is a LIKE on the vendor (instruction 890)', () => {
  for (const f of ['supabase/functions/accountant/index.ts', 'supabase/functions/resend_inbound/index.ts']) {
    assert.doesNotMatch(SRC(f), /\.ilike\(\s*'vendor'/, `${f} matches the vendor with a pattern`);
    assert.match(SRC(f), /registerRowsFor\(admin, vendor\)/, `${f} does not use the identity lookup`);
  }
});

test('nothing tells a seat to raise corporate tax (instruction 344); sanctions have one owner', () => {
  const ct = R(FILES.ct);
  assert.match(ct, /set corporate_tax_note = 'Corporate Tax is ignored/, 'the registration note is not the ruling');
  for (const f of readdirSync(join(ROOT, 'scripts/sql')).filter((x) => x.endsWith('.sql'))) {
    for (const m of R('scripts/sql/' + f).matchAll(/insert into public\.seat_duty[\s\S]*?on conflict/gi)) {
      assert.doesNotMatch(m[0], /corporate[\s_-]*tax/i, `${f} schedules a duty about corporate tax`);
    }
  }
  assert.match(R(FILES.ubo), /set owner = 'accountant'[\s\S]{0,400}where function_slug = 'sanctions_screen'/, 'sanctions_screen is not the accountant\'s');
});
