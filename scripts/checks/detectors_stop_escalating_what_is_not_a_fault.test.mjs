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

// 27 Oct 2026 (customer_support): there is ONE machine-sender rule, public.fn_is_machine_sender(text), and every
// routine that asks "is this sender a machine?" calls it. Before, the reply watch and the customer-contact test
// carried two diverging regexes (one read the whole From header, so "Bounce Fitness <info@...>" was a machine).
// The shared rule is replayed in JS from its canonical body: strip quoted strings with the regexp_replace pattern,
// then the chain of substring(s.v from '...') inside its coalesce (the first that matches wins, as coalesce does),
// lower-case, and the ~ token pattern. POSIX and these JS RegExps share the syntax used here.
const machineRule = () => {
  const t = canonical('fn_is_machine_sender');
  assert.ok(t, 'fn_is_machine_sender has a canonical definition: the one machine-sender rule');
  const strip = t.code.match(/regexp_replace\(coalesce\(p_from, ''\), '([^']+)', '', 'g'\)/);
  assert.ok(strip, `${t.file}: fn_is_machine_sender does not strip quoted strings before reading the address`);
  const extract = [...t.code.matchAll(/substring\(s\.v from '([^']+)'\)/g)].map((m) => new RegExp(m[1]));
  assert.ok(extract.length >= 2, `${t.file}: fn_is_machine_sender does not read the <...> address, then a bare one`);
  assert.match(t.code, /lower\(coalesce\(substring\(s\.v/, `${t.file}: the local part is not lower-cased`);
  // the lower-cased local part l.v is tested against each `l.v ~ '...'` pattern, OR-ed (the noreply family as a
  // token; postmaster and bounce(s) only as a whole mailbox or VERP-shaped, review of #1691)
  const pats = [...t.code.matchAll(/\bl\.v ~ '([^']+)'/g)].map((m) => new RegExp(m[1]));
  assert.ok(pats.length, `${t.file}: fn_is_machine_sender has no machine-word pattern`);
  const stripRe = new RegExp(strip[1], 'g');
  const local = (a) => { const v = String(a ?? '').replace(stripRe, ''); for (const r of extract) { const m = v.match(r); if (m) return m[1]; } return null; };
  return { file: t.file, code: t.code, machine: (a) => { const l = local(a); return l !== null && pats.some((r) => r.test(l.toLowerCase())); } };
};
// A caller's sender test IS the shared rule: it must call it, and carry no machine-word regex of its own.
const senderRule = (caller = 'fn_support_reply_watch_tick', call = 'fn_is_machine_sender(m.from_email)') => {
  const t = canonical(caller);
  assert.ok(t, `${caller} has a canonical definition`);
  assert.ok(t.code.includes(`not public.${call}`), `${t.file}: ${caller} does not test its sender with public.${call}`);
  assert.doesNotMatch(t.code, /~\*?\s*'[^']*(reply|daemon|postmaster|bounce)[^']*'/i,
    `${t.file}: ${caller} carries a machine-sender pattern of its own beside fn_is_machine_sender`);
  const { machine } = machineRule();
  return { file: t.file, dropped: machine };
};

test('6c. a machine sender is exempt anywhere in the local part, and a person is still counted', () => {
  const { file, dropped } = senderRule();
  for (const machine of ['LinkedIn <security-noreply@linkedin.com>', 'MAILER-DAEMON@mx.google.com', 'noreply@github.com',
    'Billing <Do-Not-Reply@bank.ae>', 'alerts_no_reply+bounce@vendor.com', 'notifications-donotreply@x.com', 'account-do-not-reply@x.com']) {
    assert.equal(dropped(machine), true, `${file}: ${machine} is a machine sender and is counted as a customer waiting`);
  }
  for (const person of ['Alice <alice.noreply.fan@gmail.com>', 'info@noreply-studio.ae', 'alice+noreply@gmail.com',
    'noreen@gmail.com', 'bruno.reply@outlook.com']) {
    assert.equal(dropped(person), false, `${file}: ${person} is a person and is exempted as a machine sender`);
  }
});

// 6f (27 Oct 2026, review of #1684). The local part was the first `x@` in the header, so a quoted display name
// that looks like a machine address hid the customer in <...>; and the start of the local part had no right-hand
// boundary, so noreplying@ was a machine.
test('6f. the address inside <...> decides, and the machine word must end where the word ends', () => {
  const { file, dropped } = senderRule();
  for (const person of ['"noreply@spoof.com" <bob@client.ae>', '"Mailer-Daemon@x.com" <carol.ops@client.ae>',
    'noreplying@gmail.com', 'donotreplyteam@client.ae']) {
    assert.equal(dropped(person), false, `${file}: ${person} is a customer and is exempted as a machine sender`);
  }
  for (const machine of ['"Bob" <noreply@client.ae>', 'noreply.alerts@vendor.com', 'no-reply2@vendor.com']) {
    assert.equal(dropped(machine), true, `${file}: ${machine} is a machine sender and is counted as a customer waiting`);
  }
});

// 6g-6h (27 Oct 2026, customer_support). The case table is the probe's own, so the offline replay and the live probe
// can never test different things: the_reply_watch_and_the_customer_contact_test_share_one_machine_sender_rule_probe.sql.
// It covers the review of #1686: quoted display names holding @ or < ("Support <noreply@spoof>" <bob@...>), the
// display-name words fn_support_email_is_a_customer_contact used to catch ("Bounce Fitness <info@...>",
// "Postmaster General <pm@...>"), postmaster@ and bounce(s)@ the reply watch used to miss, multiple <>, an unclosed <.
const PROBE = 'scripts/sql/the_reply_watch_and_the_customer_contact_test_share_one_machine_sender_rule_probe.sql';
const probeCases = () => [...readFileSync(join(REPO, PROBE), 'utf8')
  .matchAll(/^\s*jsonb_build_array\('((?:[^']|'')*)', (true|false)\)/gm)].map((m) => [m[1].replace(/''/g, "'"), m[2] === 'true']);

test('6g. the reply watch and the customer-contact test answer every case of the probe table with the one shared rule', () => {
  const cases = probeCases();
  assert.ok(cases.length >= 30, `${PROBE}: the case table has ${cases.length} cases, fewer than 30`);
  assert.ok(cases.some(([, m]) => m) && cases.some(([, m]) => !m), `${PROBE}: the case table needs machines and people`);
  // review of #1691: customers whose own mailbox name is bounce/postmaster must stay in the table, as people
  for (const lp of ['bounce.fitness', 'bounce-house', 'bounce_kids', 'bounce2024', 'postmaster.general', 'postmaster-ali', 'john_bounce']) {
    assert.ok(cases.some(([from, m]) => !m && from.startsWith(lp + '@')), `${PROBE}: the customer ${lp}@ is missing from the case table`);
  }
  for (const [caller, call] of [['fn_support_reply_watch_tick', 'fn_is_machine_sender(m.from_email)'],
    ['fn_support_email_is_a_customer_contact', 'fn_is_machine_sender(p_from)']]) {
    const { file, dropped } = senderRule(caller, call);
    for (const [from, machine] of cases) {
      assert.equal(dropped(from), machine, `${file}: ${caller} reads ${JSON.stringify(from)} as ${dropped(from) ? 'a machine' : 'a person'}`);
    }
  }
  assert.equal(machineRule().machine(null), false, 'a NULL sender must be false, never null, so NOT in a caller keeps the message');
});

test('6h. fn_is_machine_sender is immutable, pins search_path, and is closed to public, anon and authenticated', () => {
  const t = canonical('fn_is_machine_sender');
  assert.ok(t, 'fn_is_machine_sender has a canonical definition');
  assert.match(t.code, /\bimmutable\b/i, `${t.file}: fn_is_machine_sender is not immutable`);
  assert.match(t.code, /set search_path to 'public', 'pg_temp'/i, `${t.file}: fn_is_machine_sender does not pin search_path`);
  assert.doesNotMatch(t.code, /security definer/i, `${t.file}: fn_is_machine_sender reads no table and needs no definer rights`);
  const text = readFileSync(join(REPO, t.file), 'utf8');
  assert.match(text, /^revoke execute on function public\.fn_is_machine_sender\(text\) from public, anon, authenticated;/m,
    `${t.file}: CREATE granted EXECUTE to PUBLIC and the file does not revoke it`);
  const overloads = new Set();
  for (const f of manifestWithPending()) {
    let s; try { s = readFileSync(join(REPO, f), 'utf8'); } catch { continue; }
    for (const d of definitions(s)) if (d.name === 'fn_is_machine_sender') overloads.add(d.key);
  }
  assert.deepEqual([...overloads], ['fn_is_machine_sender(text)'], 'fn_is_machine_sender has exactly one signature, the one revoked');
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
