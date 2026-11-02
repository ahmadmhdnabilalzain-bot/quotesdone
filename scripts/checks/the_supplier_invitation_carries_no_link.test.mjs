// THE SUPPLIER INVITATION CARRIES NO LINK, AND THE ROUTINES THAT BUILD IT ACCEPT THAT (marketing, 27 Oct 2026).
//
// The founder approved a no-link invitation ("safer to not send links", founder_instruction 1301). Before this
// change fn_supplier_invite_candidates and fn_marketing_gap_recruitment_plans RAISED on an invite_body without
// {{link}}, so storing the approved text would have errored every daily batch. Fails if:
//   - the canonical fn_supplier_invite_candidates or fn_marketing_gap_recruitment_plans refuses a body for having no
//     {{link}} again (the exact failure the coordinator caught), or stops refusing an EMPTY one;
//   - the stored invite_body this file writes carries a link, Al Furjan, the TDRA permit, or is not the text the
//     Microsoft 365 lane sends (m365_lane.ts m365InvitationText, neutral variant, company placeholder aside);
//   - a reply to the invitation stops reaching the sales engineer: the invite.reply kind, its handler and the
//     AFTER INSERT trigger on inbound_messages must all be in the file, and the TS registry must name the kind.
//   node --test scripts/checks/the_supplier_invitation_carries_no_link.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

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

test('this file is the canonical definition: it is the last MANIFEST line defining both builders (or awaits apply at merge)', () => {
  const at = manifest.lastIndexOf(FILE);
  if (at < 0) {
    // applied at merge: until then it carries its pending note, and nothing in the MANIFEST may redefine them after it lands
    assert.ok(read(FILE.replace('scripts/sql/', 'scripts/sql/pending/').replace(/\.sql$/, '.txt')).trim(), `${FILE} has neither a MANIFEST line nor a pending note`);
    return;
  }
  // 2 Nov 2026: a later file may redefine a builder (the mailbox gate, #1744), so "nothing may redefine it" became
  // "whatever defines it LAST in the MANIFEST keeps this file's two promises": a template with {{link}} is not
  // refused, and an empty one still is. Each builder's latest definition is read, so a later change cannot slip the
  // link refusal back in unseen.
  for (const name of ['fn_supplier_invite_candidates', 'fn_marketing_gap_recruitment_plans']) {
    const defs = manifest.slice(at).filter((f) => f.endsWith('.sql')).filter((f) => {
      try { return new RegExp(`function\\s+public\\.${name}\\b`, 'i').test(read(f)); } catch { return false; }
    });
    const last = defs[defs.length - 1];
    const text = read(last).split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
    const bodies = [...text.matchAll(new RegExp(`create or replace function public\\.${name}\\s*\\([^)]*\\)[\\s\\S]*?as (\\$[a-z]*\\$)([\\s\\S]*?)\\1`, 'gi'))].map((m) => m[2]);
    assert.ok(bodies.length, `${name} is not defined in ${last}`);
    for (const body of bodies) {
      assert.doesNotMatch(body, /not like '%\{\{link\}\}%'/, `${last}: ${name} refuses a body without {{link}} again`);
      assert.doesNotMatch(body, /raise exception[^;]*\{\{link\}\}/, `${last}: ${name} raises over {{link}}`);
      if (/v_body/.test(body)) assert.match(body, /if btrim\(coalesce\(v_body, ''\)\) = '' then\s+raise exception/, `${last}: ${name} no longer refuses an empty template`);
    }
  }
});

test('the builders accept a body with no {{link}} and still refuse an empty one', () => {
  for (const name of ['fn_supplier_invite_candidates', 'fn_marketing_gap_recruitment_plans']) {
    const body = routine(name);
    assert.doesNotMatch(body, /not like '%\{\{link\}\}%'/, `${name} refuses a body without {{link}} again: every batch would raise`);
    assert.doesNotMatch(body, /raise exception[^;]*\{\{link\}\}/, `${name} raises over {{link}}`);
    assert.match(body, /if btrim\(coalesce\(v_body, ''\)\) = '' then\s+raise exception/, `${name} no longer refuses an empty template`);
  }
  // a template that still has the placeholder is filled, never left raw in a supplier's mail
  assert.match(routine('fn_supplier_invite_candidates'), /'\{\{link\}\}', public\.fn_supplier_invite_link\(/);
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
    assert.match(read('supabase/functions/resend_inbound/index.ts'), new RegExp(`${k}: hv\\(`), `resend_inbound no longer stores ${k}`);
  }
  assert.match(auto, /revoke execute on function public\.fn_inbound_is_auto_reply\(text, text, jsonb\) from public, anon, authenticated;/);
  // the verdict row keeps both sides: the two measured machine replies, and a person who thanks us first
  assert.match(auto, /help-desk acknowledgement \(15 Aug\)/); assert.match(auto, /a person''s reply was taken for a machine/);
});
