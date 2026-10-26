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
  for (const name of ['fn_supplier_invite_candidates', 'fn_marketing_gap_recruitment_plans']) {
    const later = manifest.slice(at + 1).filter((f) => f.endsWith('.sql')).filter((f) => {
      try { return new RegExp(`function\\s+public\\.${name}\\b`, 'i').test(read(f)); } catch { return false; }
    });
    assert.deepEqual(later, [], `${name} is redefined after this file by ${later.join(', ')}`);
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

test('the stored invitation is the approved text: no link, no Al Furjan, no permit, the stop line last', async () => {
  const stored = (/update public\.app_secrets set value = \$body\$([\s\S]*?)\$body\$/.exec(sql) || [])[1];
  assert.ok(stored, 'the invite_body update is gone');
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
