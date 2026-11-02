// A SUPPLIER WHO ANSWERED THE INVITATION IS NOT ASKED THE SAME QUESTION AGAIN (28 Oct 2026, sales_engineer; found by
// it_engineer in the supplier-journey audit, founder ledger 1401).
//
// The day-3/7/14 nudge list (fn_supplier_invite_nudges_due) excluded a lead that clicked, claimed, registered,
// bounced, unsubscribed or was suppressed, but not one that REPLIED. send_outbox sends every nudge as the same
// variant A email, so a supplier who had answered "yes" (or "we only do steel, not tiles") was asked the identical
// question again three days later. This fails if the definition that wins the apply order stops excluding a lead
// with a message of its own since the invitation, or stops letting an automatic reply through as "no answer".
// It reads the routine's BODY (between its dollar tags, comments removed), so a comment cannot satisfy it.
// The behaviour is proved against production by the probe file of the same name (rolled back): on the definition
// before this fix it answers PROBE FAILED for the "yes" lead and the "Name <address>" lead.
//   node --test scripts/checks/a_supplier_who_answered_the_invitation_is_not_asked_the_same_question_again.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const SQL = 'scripts/sql/';
const FIX = 'a_supplier_who_answered_the_invitation_is_not_asked_the_same_question_again.sql';
const DEF = /create\s+or\s+replace\s+function\s+public\.fn_supplier_invite_nudges_due\s*\(/i;
const manifest = readFileSync(SQL + 'MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
  .map((l) => l.replace(/^scripts\/sql\//, ''));
const pending = (f) => existsSync(SQL + 'pending/' + f.replace(/\.sql$/, '.txt'));
const defines = (f) => existsSync(SQL + f) && DEF.test(readFileSync(SQL + f, 'utf8'));

/** The file that defines the routine LAST: a pending file is applied after everything in MANIFEST, so it wins. */
export function winningFile() {
  if (pending(FIX) && defines(FIX)) return FIX;
  const listed = manifest.filter(defines);
  assert.ok(listed.length > 0, 'no applied file defines fn_supplier_invite_nudges_due');
  return listed[listed.length - 1];
}

/** The routine's body, between its dollar tags, with -- comments removed. */
export function bodyOf(src) {
  const open = src.search(DEF);
  assert.ok(open >= 0, 'the file does not define fn_supplier_invite_nudges_due');
  const m = /\bas\s+(\$[a-z_]*\$)/i.exec(src.slice(open));
  assert.ok(m, 'fn_supplier_invite_nudges_due has no dollar-quoted body');
  const start = open + m.index + m[0].length;
  const end = src.indexOf(m[1], start);
  assert.ok(end > start, 'the body of fn_supplier_invite_nudges_due is not closed');
  return src.slice(start, end).replace(/--[^\n]*/g, '');
}

/** From an opening parenthesis, the text up to its matching close; '…' strings are skipped, so a parenthesis inside a
 *  regular-expression literal (the From-address pattern) does not end it early. */
function balanced(s, open) {
  let depth = 0;
  for (let i = open; i < s.length; i++) {
    const ch = s[i];
    if (ch === "'") { i = s.indexOf("'", i + 1); if (i < 0) return null; continue; }
    if (ch === '(') depth++;
    else if (ch === ')' && --depth === 0) return s.slice(open + 1, i);
  }
  return null;
}

/** The problems with a body, [] when it excludes a supplier who answered. Exported for the known-bad control below. */
export function problems(body) {
  const out = [];
  const b = body.replace(/\s+/g, ' ');
  // the exclusion: a NOT EXISTS over the supplier's own inbound messages ...
  const at = b.search(/not exists \(select 1 from public\.inbound_messages \w+ where /i);
  const sub = at >= 0 ? balanced(b, b.indexOf('(', at)) : null;
  const m = sub && /^select 1 from public\.inbound_messages (\w+) where (.*)$/i.exec(sub.trim());
  if (!m) { out.push('no "not exists (select 1 from public.inbound_messages …)" in the nudge list: a supplier who replied is nudged'); return out; }
  const [, alias, cond] = m;
  // ... matched to the lead (its id or its From address) ...
  if (!new RegExp(`${alias}\\.lead_id\\s*=\\s*c\\.id`, 'i').test(cond)) out.push('the reply is not matched on the lead id');
  if (!new RegExp(`${alias}\\.from_email`, 'i').test(cond)) out.push('the reply is not matched on the From address (an unmatched reply would still be nudged)');
  // ... arriving after THIS invitation was sent ...
  if (!new RegExp(`${alias}\\.created_at\\s*>=\\s*c\\.sent_at`, 'i').test(cond)) out.push('the reply is not limited to messages since the invitation was sent');
  if (!/i\.sent_at/i.test(b)) out.push('the invitation\'s sent_at is not carried into the candidates');
  // ... and an automatic reply is NOT an answer
  if (!new RegExp(`not\\s+public\\.fn_inbound_is_auto_reply\\(\\s*${alias}\\.subject\\s*,\\s*${alias}\\.body\\s*,\\s*${alias}\\.raw\\s*\\)`, 'i').test(cond)) {
    out.push('an automatic reply (out of office) would stop the nudge: fn_inbound_is_auto_reply is not applied');
  }
  return out;
}

test('the nudge list that wins the apply order does not ask a supplier who answered the same question again', () => {
  const f = winningFile();
  const p = problems(bodyOf(readFileSync(SQL + f, 'utf8')));
  assert.deepEqual(p, [], `${f}: ${p.join('; ')}`);
});

test('known-bad control: the definition before this fix is caught', () => {
  // the body as it was live on 28 Oct 2026 (read back from production), reduced to the clauses the check reads
  const before = `with inv as (select n.lead_id, min(coalesce(n.sent_at, n.created_at)) as sent_at from public.notifications n group by n.lead_id),
    c as (select l.id, lower(btrim(l.email)) as to_email, l as lead from inv i join public.leads l on l.id = i.lead_id)
    select c.id from c where not exists (select 1 from public.email_suppressions s where lower(s.email) = c.to_email)
      and not exists (select 1 from public.agent_actions a where a.kind = 'handoff') order by c.id`;
  assert.ok(problems(before).length > 0, 'the check passes the definition that nudged a supplier who had replied');
  // and an exclusion that forgets the automatic-reply rule is caught too
  const noAuto = `with inv as (select 1), c as (select l.id, i.sent_at from inv i join public.leads l on true)
    select c.id from c where not exists (select 1 from public.inbound_messages m where (m.lead_id = c.id
      or lower(m.from_email) = c.to_email) and m.created_at >= c.sent_at) order by c.id`;
  assert.ok(problems(noAuto).some((p) => /automatic reply/.test(p)), 'an exclusion without the automatic-reply rule passes');
});
