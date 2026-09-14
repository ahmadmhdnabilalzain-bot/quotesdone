// THE PORTALS ARE THE SALES ENGINEER.
//
// Founder, 14 Sep 2026, verbatim: "its always the sales agent. no other agent is involved in
// customer or supplier portal. make sure the wiring is made this way."
//
// WHAT IS PORTAL-REACHABLE is computed, not listed: every edge-function slug named in
// src/components/me and src/components/portal, plus every slug those functions call through
// /functions/v1/<slug>, one hop further. A new portal call site joins the set by existing.
//
// A reachable slug passes only if it is owned by sales_engineer, OR it is a documented PLATFORM
// SERVICE below. Those are held for other seats by the founder's 9 Sep rulings (payments to the
// accountant, OTP to a future seat) or are Support's pipe (the standing guard in
// scripts/sql/the_sales_engineer_owns_both_portals_end_to_end.sql refuses channel slugs on
// sales_engineer). The portal calls them; no agent speaks through them.
//
// Also refused, statically (runs in CI without a token):
//   * an agent_actions row, a `seat:` or a `p_actor:` literal in a reachable sales-owned function
//     naming anything but sales_engineer
//   * the intake speaking under a category specialist's own name
//   * the portal UI labelling its agent as a generic or category "assistant"
//   * the Support widget (site_assistant) rendering on /me or /portal
// And, against production (skipped without a management token): function_owner and
// llm_seat_binding for every reachable slug.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FNS = join(REPO, 'supabase', 'functions');
const SEAT = 'sales_engineer';

export const PLATFORM_SERVICES = {
  stripe_checkout: 'payment (accountant)', stripe_confirm: 'payment (accountant)', supplier_pay: 'payment (accountant)',
  reveal_invoice: 'payment (accountant)', quote_pdf: 'payment (accountant)', refunds_api: 'payment (accountant)', refund_flow: 'payment (accountant)',
  login_otp: 'sign-in / OTP', send_sms: 'sign-in / OTP', mobile_otp: 'sign-in / OTP', voice_otp: 'sign-in / OTP',
  voice_otp_capture: 'sign-in / OTP', sup_dob: 'sign-in / OTP', auth_api: 'sign-in / OTP', role_guard: 'auth',
  transcribe: 'channel (Support pipe)', wa_optin_set: 'channel consent (Support pipe)', ai_gateway: 'model gateway (Support pipe)',
  extract_text: 'channel (Support pipe)', license_extract: 'channel (Support pipe)', doc_extract: 'channel (Support pipe)',
  send_outbox: 'channel (Support pipe)', send_whatsapp: 'channel (Support pipe)',
};

const slugs = readdirSync(FNS).filter((s) => !s.startsWith('_') && statSync(join(FNS, s)).isDirectory());
const walk = (d) => readdirSync(d).flatMap((f) => {
  const p = join(d, f);
  return statSync(p).isDirectory() ? walk(p) : /\.(tsx?|mjs)$/.test(f) && !/\.test\./.test(f) ? [p] : [];
});
const read = (f) => readFileSync(f, 'utf8');
const fnSource = (s) => walk(join(FNS, s)).map(read).join('\n');

export function portalReachable() {
  const ui = [join(REPO, 'src/components/me'), join(REPO, 'src/components/portal')].flatMap(walk).map(read).join('\n');
  const direct = slugs.filter((s) => new RegExp(`['"\`/]${s}['"\`?/]`).test(ui));
  const reach = new Set(direct);
  for (const s of direct) for (const m of fnSource(s).matchAll(/functions\/v1\/([a-z_]+)/g)) if (slugs.includes(m[1])) reach.add(m[1]);
  return [...reach].sort();
}

const reach = portalReachable();
const salesOwned = reach.filter((s) => !PLATFORM_SERVICES[s]);

test('the portal reach set is found at all', () => {
  // A walk that finds nothing would pass every assertion below. The assistant and both portals' write paths must be in it.
  for (const s of ['sales_engineer', 'customer_api', 'supplier_api', 'messages_api']) assert.ok(reach.includes(s), `${s} not found reachable`);
});

test('no reachable sales-owned function writes an actor other than the sales engineer', () => {
  const bad = [];
  for (const s of salesOwned) {
    const src = fnSource(s);
    for (const m of src.matchAll(/from\('agent_actions'\)\.insert\(\{[\s\S]{0,400}?agent:\s*'([a-z_]+)'/g)) if (m[1] !== SEAT) bad.push(`${s}: agent_actions.agent='${m[1]}'`);
    for (const m of src.matchAll(/\b(?:seat|p_actor):\s*'([a-z_]+)'/g)) if (m[1] !== SEAT) bad.push(`${s}: '${m[1]}'`);
  }
  assert.deepEqual(bad, []);
});

test('the intake speaks as the sales engineer, not under a specialist name', () => {
  const src = fnSource('inquiry_intake');
  assert.ok(!/You are \$\{specialist\.name\}/.test(src), 'inquiry_intake introduces a category specialist by its own name');
  assert.ok(/You are QuotesDone's sales engineer/.test(src), 'inquiry_intake identity no longer names the sales engineer');
});

test('the portal UI never labels its agent as a generic or category assistant', () => {
  const FORBIDDEN = /Procurement assistant|intake assistant|category assistant|'AI Assistant'|مساعد المشتريات|مساعد الطلبات|مساعد الفئة|المساعد الذكي/;
  const files = [join(REPO, 'src/components/me'), join(REPO, 'src/components/portal')].flatMap(walk);
  const bad = files.filter((f) => FORBIDDEN.test(read(f))).map((f) => f.slice(REPO.length));
  assert.deepEqual(bad, []);
  assert.ok(read(join(REPO, 'src/components/me/portalText.ts')).includes("asst_title:'QuotesDone sales engineer'"));
});

test('the Support widget does not render inside either portal', () => {
  const w = read(join(REPO, 'src/components/ChatWidget.tsx'));
  assert.ok(/\(os\|me\|portal[^)]*\)[\s\S]{0,40}return null/.test(w), 'ChatWidget (site_assistant, customer_support) no longer hides on /me and /portal');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('production: every reachable slug is owned by the sales engineer or is a platform service', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const owners = new Map((await sql('select function_slug, owner from public.function_owner')).map((r) => [r.function_slug, r.owner]));
  const binds = new Map((await sql('select fn, seat from public.llm_seat_binding')).map((r) => [r.fn, r.seat]));
  const bad = [];
  for (const s of salesOwned) {
    if (owners.get(s) !== SEAT) bad.push(`${s}: owner=${owners.get(s) ?? '(none)'}`);
    if (binds.has(s) && binds.get(s) !== SEAT) bad.push(`${s}: llm_seat_binding=${binds.get(s)}`);
  }
  for (const s of reach.filter((x) => PLATFORM_SERVICES[x])) if (owners.get(s) === SEAT) bad.push(`${s}: a ${PLATFORM_SERVICES[s]} slug landed on sales_engineer — the guard refuses it`);
  assert.deepEqual(bad, []);
});
