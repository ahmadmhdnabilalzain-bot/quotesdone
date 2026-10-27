// DETECTORS STOP ESCALATING WHAT IS NOT A FAULT.
//
// scripts/sql/detectors_stop_escalating_what_is_not_a_fault.sql. On 19 Oct 2026 six detectors sent the CEO
// "still broken" reports for things that are not faults: a Stripe test-mode charge, the OpenRouter accrual
// (no receipt ever exists), 1910 Dropbox copies verified and then pruned by retention, a fresh backup report
// every day for one condition, info findings, an SLA item repeating the open-finding queue, and no-reply /
// calendar+ mail counted as unanswered customers. This reads each routine's body in that file and fails if
// any of the six comes back. Offline: no token needed.
//
//   node --test scripts/checks/detectors_stop_escalating_what_is_not_a_fault.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { manifestWithPending } from '../lib/pending_sql.mjs';
import { definitions } from '../lib/canonical_sql.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const src = readFileSync(join(REPO, 'scripts/sql/detectors_stop_escalating_what_is_not_a_fault.sql'), 'utf8');
const body = (name) => {
  const s = src.indexOf('CREATE OR REPLACE FUNCTION public.' + name + '(');
  assert.ok(s >= 0, name + ' is defined in the file');
  const e = src.indexOf('$function$;', s);
  // comments are dropped so a comment describing the fix can never stand in for the fix
  return src.slice(s, e).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
};

test('1. a Stripe test-mode charge difference is recorded, not raised', () => {
  assert.match(body('fn_accountant_charge_audit_record'), /a\.resolved_at is null and a\.livemode loop/);
});

test('2. the OpenRouter daily accrual is never a missing receipt', () => {
  assert.match(body('fn_accountant_expense_duty'), /coalesce\(source, ''\) <> 'accountant:openrouter_daily'/);
});

test('3a. a copy that went through retention is not a backup gap', () => {
  assert.match(body('fn_backup_coverage'), /d\.status not in \('prune_pending', 'pruning', 'pruned'\)/);
});

test('3b. one backup condition is one CEO report, not one a day', () => {
  const b = body('fn_backup_watch');
  const guard = b.indexOf("idempotency_key like 'dropbox_backup_escalation:%' and status = 'accepted'");
  const call = b.indexOf("'dropbox_backup_escalation:' || v_date");
  assert.ok(guard > 0 && guard < call, 'the escalation is skipped while an earlier one is still accepted');
});

test('4. an info finding is never escalated to the CEO', () => {
  assert.match(body('fn_it_loop_reverify'), /and not \(coalesce\(f\.affected, 1\) = 0 and coalesce\(f\.title, ''\) ilike 'info:%'\) then/);
});

test("5. the handoff SLA does not repeat the open-finding queue (only 'unanswered' and 'unclosed')", () => {
  const b = body('fn_it_handoff_sla_items');
  assert.doesNotMatch(b, /open_over/);
  assert.match(b, /then 'unclosed'/);
});

test('6. no-reply senders and the calendar+ inbox are not unanswered email', () => {
  const b = body('fn_support_reply_watch_tick');
  assert.match(b, /to_email, ''\) !~\* '\^calendar\\\+'/);
  assert.ok(b.includes(`coalesce(substring(m.from_email from '([^<>\\s"]+)@'), '') !~* '^(no-?reply|do-?not-?reply)'`),
    'the no-reply rule reads the local part only, anchored at its start');
});

test('6b. a customer whose address merely contains noreply is still counted', () => {
  // the routine's two patterns replayed in JS (POSIX ~* is case-insensitive)
  const local = (a) => (a.match(/([^<>\s"]+)@/) || [, ''])[1];
  const dropped = (a) => /^(no-?reply|do-?not-?reply)/i.test(local(a));
  assert.equal(dropped('alice.noreply.fan@gmail.com'), false);
  assert.equal(dropped('info@noreply-studio.ae'), false);
  assert.equal(dropped('noreply@github.com'), true);
  assert.equal(dropped('Billing <Do-Not-Reply@bank.ae>'), true);
});

test('4b. an answered info finding is closed, not left open unwatched', () => {
  const b = body('fn_it_loop_reverify');
  const at = b.indexOf("ilike 'info:%' and h.detail ? 'replied_at' then");
  assert.ok(at > 0, 'the answered-info branch exists');
  const branch = b.slice(at, b.indexOf('elsif', at));
  assert.match(branch, /fn_it_engineer_finding_close\(f\.issue_key/);
  assert.match(branch, /fn_seat_handoff_complete\(h\.id/);
});

// 6c-6e (27 Oct 2026, customer_support). Tests 6 and 6b read the 19 Oct file; these read the routine as it is
// CANONICAL now: the last definition in MANIFEST order, pending files included (manifestWithPending), so a later
// file cannot quietly bring the anchored rule or the false close note back. Measured on production: security-noreply@
// (LinkedIn) waited 30 days as a customer because the rule only matched the START of the local part, and the
// finding then closed saying every message had a first reply when both had only aged out of the window.
const canonical = (name) => {
  let last = null;
  for (const f of manifestWithPending()) {
    const p = join(REPO, f);
    let text;
    try { text = readFileSync(p, 'utf8'); } catch { continue; }
    for (const d of definitions(text)) if (d.name === name) last = { file: f, stmt: d.stmt };
  }
  return last && { file: last.file, code: last.stmt.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n') };
};

test('6c. a machine sender is exempt anywhere in the local part, and a person is still counted', () => {
  const t = canonical('fn_support_reply_watch_tick');
  assert.ok(t, 'fn_support_reply_watch_tick has a canonical definition');
  const m = t.code.match(/substring\(m\.from_email from '\(\[\^<>\\s"\]\+\)@'\), ''\) !~\* '([^']+)'/);
  assert.ok(m, `${t.file}: the machine-sender rule on the sender's local part is missing`);
  const rule = new RegExp(m[1], 'i');                       // POSIX ~* replayed in JS: same syntax, case-insensitive
  const local = (a) => (a.match(/([^<>\s"]+)@/) || [, ''])[1];
  const dropped = (a) => rule.test(local(a));
  for (const machine of ['LinkedIn <security-noreply@linkedin.com>', 'MAILER-DAEMON@mx.google.com', 'noreply@github.com',
    'Billing <Do-Not-Reply@bank.ae>', 'alerts_no_reply+bounce@vendor.com', 'notifications-donotreply@x.com', 'account-do-not-reply@x.com']) {
    assert.equal(dropped(machine), true, `${t.file}: ${machine} is a machine sender and is counted as a customer waiting`);
  }
  for (const person of ['Alice <alice.noreply.fan@gmail.com>', 'info@noreply-studio.ae', 'alice+noreply@gmail.com',
    'noreen@gmail.com', 'bruno.reply@outlook.com']) {
    assert.equal(dropped(person), false, `${t.file}: ${person} is a person and is exempted as a machine sender`);
  }
});

test('6d. the reply finding never closes with a claim of replies it did not count', () => {
  const t = canonical('fn_support_reply_watch_tick');
  const at = t.code.indexOf("fn_it_engineer_finding_close('support_reply_sla:' || c,");
  assert.ok(at > 0, `${t.file}: the close branch is missing`);
  const call = t.code.slice(at, t.code.indexOf(';', at));
  assert.doesNotMatch(call, /has a first reply/, `${t.file}: the close note is a fixed claim that every message was answered`);
  assert.match(call, /fn_support_reply_watch_close_note\(c,/, `${t.file}: the close note is not built from what cleared each message`);
});

test('6e. the close note says aged out, and claims every reply only when every waiting message was listed and answered', () => {
  const n = canonical('fn_support_reply_watch_close_note');
  assert.ok(n, 'fn_support_reply_watch_close_note has a canonical definition');
  assert.match(n.code, /aged out of the 30-day window/, `${n.file}: an aged-out message is not named as such`);
  const every = n.code.indexOf("'cleared by replies: every one of the '");
  assert.ok(every > 0, `${n.file}: the all-answered wording is missing`);
  const guard = n.code.lastIndexOf('if', every);
  assert.match(n.code.slice(guard, every), /v_replied = v_listed and v_waiting = v_listed/,
    `${n.file}: "every one got a first reply" is not guarded by every listed message answered AND every waiting message listed`);
});
