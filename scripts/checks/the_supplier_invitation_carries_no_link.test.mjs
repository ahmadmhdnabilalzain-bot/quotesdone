// THE SUPPLIER INVITATION CARRIES NO LINK, AND THE ROUTINES THAT BUILD IT ACCEPT THAT (marketing, 27 Oct 2026).
//
// The founder approved a no-link invitation ("safer to not send links", founder_instruction 1301). Before this
// change fn_supplier_invite_candidates and fn_marketing_gap_recruitment_plans RAISED on an invite_body without
// {{link}}, so storing the approved text would have errored every daily batch. Fails if:
//   - the canonical fn_supplier_invite_candidates or fn_marketing_gap_recruitment_plans refuses a body for having no
//     {{link}} again (the exact failure the coordinator caught), or stops refusing an EMPTY or whitespace-only one.
//     Canonical is what production runs: every overload in the LAST file, in apply order, that defines it (28 Oct);
//   - the stored invite_body this file writes carries a link, Al Furjan, the TDRA permit, or is not the text the
//     Microsoft 365 lane sends (m365_lane.ts m365InvitationText, neutral variant, company placeholder aside);
//   - a reply to the invitation stops reaching the sales engineer: the invite.reply kind, its handler and the
//     AFTER INSERT trigger on inbound_messages must all be in the file, and the TS registry must name the kind.
//   node --test scripts/checks/the_supplier_invitation_carries_no_link.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { definitions } from '../lib/canonical_sql.mjs';
import { manifestWithPending } from '../lib/pending_sql.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const ROOT = new URL('../../', import.meta.url);
const read = (p) => readFileSync(new URL(p, ROOT), 'utf8');
const FILE = 'scripts/sql/the_supplier_invitation_carries_no_link_and_a_reply_with_trades_reaches_the_sales_engineer.sql';
const sql = read(FILE);
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
const manifest = read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim());

// the body of one `create or replace function public.<name>` in this file, up to its closing dollar tag
function routine(name) {
  const m = new RegExp(`create or replace function public\\.${name}\\([^)]*\\)[\\s\\S]*?as (\\$[a-z]*\\$)([\\s\\S]*?)\\1`, 'i').exec(code);
  assert.ok(m, `${name} is not defined in ${FILE}`);
  return m[2];
}

// THE BUILDERS ARE READ WHERE PRODUCTION RUNS THEM (it_engineer, 28 Oct 2026; ledger 1406-1409). These two tests
// used to read the builders from FILE and require FILE to stay the last MANIFEST file defining them. Then
// the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.sql, applied after FILE, legitimately moved
// fn_supplier_invite_candidates' body into a new (integer, text[]) overload and left (integer) as a wrapper over it:
// the pin went red on main, and the {{link}} assertions went on passing against FILE's superseded body while
// production ran the new one. Each builder is now taken from the LAST file in apply order that defines it
// (manifestWithPending: MANIFEST, then the pending files, which apply after it, so a pull request fails its own
// check), less a definition scripts/sql/SUPERSEDED.txt retires. Every overload in that file is canonical, the rule
// canonical_routine_manifest.mjs holds production to, so each is checked: one that reads invite_body must refuse an
// empty body and accept a link-less one; one that does not must hand over to another overload of the routine
// instead of building a body of its own.
const BUILDERS = ['fn_supplier_invite_candidates', 'fn_marketing_gap_recruitment_plans'];
const RETIRED = new Set(read('scripts/sql/SUPERSEDED.txt').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
  .map((l) => l.split('::').map((s) => s.trim())).map(([f, r]) => `${f}::${(r || '').toLowerCase()}`));
// review of #1722 (S1): any mention of the template makes an overload a reader, whatever the query looks like
const READS_BODY = /'invite_body'/;
const CANON = new Map();   // name -> { file, overloads }: the tree is parsed once per builder
function canonical(name) {
  if (CANON.has(name)) return CANON.get(name);
  const defined = (f) => { try { return RETIRED.has(`${f}::${name}`) ? [] : definitions(read(f)).filter((d) => d.name === name); } catch { return []; } };
  const file = manifestWithPending().filter((f) => defined(f).length).pop();
  assert.ok(file, `${name} is defined in no applied or pending file`);
  // the body between the dollar tags, comments dropped (a comment may quote the old refusal); block comments too,
  // or a guard wrapped in /* */ would read as present (review of #1722, N1)
  const c = { file, overloads: defined(file).map((d) => ({ key: d.key,
    body: ((/\bas\s+(\$[A-Za-z0-9_]*\$)([\s\S]*?)\1/i.exec(d.stmt) || [])[2] ?? '').replace(/\/\*[\s\S]*?\*\//g, '')
      .split('\n').map((l) => l.replace(/--.*$/, '')).join('\n') })) };
  CANON.set(name, c);
  return c;
}

test('each builder is read where production runs it: every overload in the last file, in apply order, that defines it', () => {
  for (const name of BUILDERS) {
    const { file, overloads } = canonical(name);
    assert.ok(overloads.some((o) => READS_BODY.test(o.body)), `no overload of ${name} in ${file} reads app_secrets.invite_body: the next test would assert nothing`);
    // a non-reader must be a PURE hand-over: one `return query select * from public.<name>(...)`, nothing else, so it
    // cannot return a body of its own that skips the refusal and the fill (review of #1722, S1)
    const handover = new RegExp(`^\\s*begin\\s+return\\s+query\\s+select\\s+\\*\\s+from\\s+public\\.${name}\\([^;]*\\);\\s*end\\s*;?\\s*$`, 'i');
    for (const o of overloads.filter((x) => !READS_BODY.test(x.body))) {
      assert.match(o.body, handover, `${o.key} in ${file} neither reads invite_body nor only hands over to another ${name}: it builds a body this check does not see`);
    }
  }
});

test('the builders accept a body with no {{link}} and still refuse an empty one', () => {
  for (const name of BUILDERS) {
    const { file, overloads } = canonical(name);
    for (const o of overloads) {
      assert.doesNotMatch(o.body, /not like '%\{\{link\}\}%'/, `${o.key} in ${file} refuses a body without {{link}} again: every batch would raise`);
      assert.doesNotMatch(o.body, /raise exception[^;]*\{\{link\}\}/, `${o.key} in ${file} raises over {{link}}`);
      // the same refusal in the other shape a placeholder test takes: a zero position or strpos, then a raise
      assert.doesNotMatch(o.body, /(position\(\s*'\{\{link\}\}'\s+in\b|strpos\([^;]*?'\{\{link\}\}'\s*\))[^;]*?(=\s*0|<\s*1)[^;]*?\bthen\s+raise\b/i,
        `${o.key} in ${file} raises when the body has no {{link}}`);
      if (READS_BODY.test(o.body)) {
        // 28 Oct 2026 (ledger 1407): the refusal read btrim(...) = '', and btrim() given no characters strips only the
        // space, so a template of newlines or tabs was built from (measured on production, rolled back). It reads the
        // whitespace class now: the_invitation_builders_refuse_a_blank_body_not_only_an_empty_one.sql.
        assert.match(o.body, /if coalesce\(v_body, ''\) ~ '\^\[\[:space:\]\]\*\$' then\s+raise exception/,
          `${o.key} in ${file} no longer refuses an empty or whitespace-only template`);
      }
    }
  }
  // THE ONLY {{link}} IN BUILDER CODE IS THE FILL (review of #1722, S2). A refusal of a link-less body has to name the
  // placeholder, in any case, operator or shape (not like, NOT ILIKE, !~, assert, position ...); the detectors above
  // know a few shapes, this knows them all. Measured 1 Nov 2026: one occurrence, the picker's fill.
  for (const name of BUILDERS) {
    const { file, overloads } = canonical(name);
    for (const o of overloads) {
      const all = (o.body.match(/\\?\{\\?\{\s*link\s*\\?\}\\?\}/gi) || []).length;   // escaped in a regex too: \{\{link\}\}
      const fills = (o.body.match(/'\{\{link\}\}', public\.fn_supplier_invite_link\(/g) || []).length;
      assert.equal(all, fills, `${o.key} in ${file} names {{link}} outside the fill: a body without the placeholder may be refused`);
    }
  }
  // a template that still has the placeholder is filled, never left raw in a supplier's mail
  for (const o of canonical('fn_supplier_invite_candidates').overloads.filter((x) => READS_BODY.test(x.body))) {
    assert.match(o.body, /'\{\{link\}\}', public\.fn_supplier_invite_link\(/, `${o.key} leaves a {{link}} placeholder unfilled`);
  }
});

// 27 Oct 2026 (it_engineer): the copy moved to variant A in its own file. The stored body is read from the LAST
// MANIFEST file that writes invite_body (falling back to the newest copy file while it awaits its MANIFEST line), so
// the next copy change is held to the same rule instead of silently comparing against a superseded file.
const COPY_FILES = [FILE, 'scripts/sql/the_supplier_invitation_asks_one_question_and_makes_no_offer.sql'];
function latestCopyFile() {
  const writes = (f) => { try { return /update public\.app_secrets set value = \$body\$[\s\S]*?\$body\$[^;]*where key = 'invite_body'/.test(read(f)); } catch { return false; } };
  const inManifest = manifest.filter((f) => f.endsWith('.sql') && writes(f));
  return inManifest.length ? inManifest[inManifest.length - 1] : COPY_FILES[COPY_FILES.length - 1];
}

test('the stored invitation is the approved text: no link, no Al Furjan, no permit, the stop line last', async () => {
  const copyFile = latestCopyFile();
  const stored = (/update public\.app_secrets set value = \$body\$([\s\S]*?)\$body\$/.exec(read(copyFile)) || [])[1];
  assert.ok(stored, `the invite_body update is gone from ${copyFile}`);
  assert.doesNotMatch(stored, /https?:\/\/|www\.|\{\{link\}\}/i);
  assert.doesNotMatch(stored, /al[\s-]*furjan|NOL-|TDRA/i);
  globalThis.Deno ??= { env: { get: () => '' } };
  const { m365InvitationText } = await import(new URL('supabase/functions/send_outbox/m365_lane.ts', ROOT).href);
  // the lane's text for a named company with no trade is the stored text with the placeholder filled
  assert.equal(stored.replace('{{company}}', 'Sigma Ceramics'), m365InvitationText({ company: 'Sigma Ceramics' }),
    'the stored invite_body and the text the Microsoft 365 lane sends have drifted apart');
});

test('a plan row may not carry a link (the CHECK is turned round, not dropped)', () => {
  assert.match(code, /drop constraint if exists marketing_gap_recruitment_plan_check;/);
  assert.match(code, /add constraint marketing_gap_recruitment_plan_check\s+check \(invite_body !~\* '\(https\?:\/\/\|www\\\.\|\\\{\\\{link\\\}\\\}\)'/);
});

test('a reply to the invitation reaches the sales engineer as an invite.reply handoff', () => {
  assert.match(code, /\('invite\.reply', 'marketing', 'sales_engineer', '[^']+', 'fn_sales_engineer_takes_invite_reply',/);
  assert.match(code, /create trigger z52_invite_reply_reaches_sales_engineer after insert on public\.inbound_messages/);
  const filer = routine('fn_marketing_files_invite_reply');
  assert.match(filer, /public\.fn_seat_handoff\('marketing', 'sales_engineer', 'invite\.reply', 'leads', l\.id::text,/);
  assert.match(filer, /'lead_id', l\.id/); assert.match(filer, /'reply_text', left\(v_reply, 4000\)/);
  assert.match(filer, /'stop', 'unsubscribe'/, 'a stop reply must never become a page request');
  for (const fn of ['fn_sales_engineer_takes_invite_reply(bigint)', 'fn_marketing_files_invite_reply(bigint)', 'trg_invite_reply_reaches_sales_engineer()']) {
    assert.ok(code.includes(`revoke execute on function public.${fn} from public, anon, authenticated;`), `${fn} is not revoked`);
  }
  assert.match(read('supabase/functions/_shared/payment_handoffs.ts'), /\{ type: 'invite\.reply', from: 'marketing', to: 'sales_engineer' \}/);
});

// 27 Oct 2026 (review of #1614): an automatic reply must not take the lead's one invite.reply handoff.
test('an automatic reply files no handoff: the latest filer asks fn_inbound_is_auto_reply, and resend_inbound stores the marks it reads', () => {
  const AUTO = 'scripts/sql/an_automatic_reply_never_takes_an_invited_suppliers_handoff.sql';
  const auto = read(AUTO).split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
  const filer = (/create or replace function public\.fn_marketing_files_invite_reply\([^)]*\)[\s\S]*?as \$fn\$([\s\S]*?)\$fn\$/i.exec(auto) || [])[1] || '';
  assert.match(filer, /if public\.fn_inbound_is_auto_reply\(m\.subject, m\.body, m\.raw\) then return/);
  assert.ok(filer.indexOf('fn_inbound_is_auto_reply') < filer.indexOf('fn_seat_handoff('), 'the auto-reply test must come before the handoff is filed');
  for (const k of ['auto_submitted', 'x_auto_response_suppress', 'precedence', 'x_autoreply']) {
    assert.match(auto, new RegExp(`p_raw->>'${k}'`), `fn_inbound_is_auto_reply no longer reads ${k}`);
    assert.match(functionSource('resend_inbound'), new RegExp(`${k}: hv\\(`), `resend_inbound no longer stores ${k}`);
  }
  assert.match(auto, /revoke execute on function public\.fn_inbound_is_auto_reply\(text, text, jsonb\) from public, anon, authenticated;/);
  // the verdict row keeps both sides: the two measured machine replies, and a person who thanks us first
  assert.match(auto, /help-desk acknowledgement \(15 Aug\)/); assert.match(auto, /a person''s reply was taken for a machine/);
});
