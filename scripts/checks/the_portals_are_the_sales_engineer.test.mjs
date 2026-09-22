// THE PORTALS ARE THE SALES ENGINEER.
//
// Founder, 14 Sep 2026, verbatim: "its always the sales agent. no other agent is involved in
// customer or supplier portal. make sure the wiring is made this way."
//
// WHAT IS PORTAL-REACHABLE is computed, not listed: every edge-function slug named in
// src/components/me and src/components/portal, plus every slug those functions call through
// /functions/v1/<slug>, one hop further. A new portal call site joins the set by existing.
//
// A reachable slug passes only if it is owned by sales_engineer, OR it is a PAYMENT function owned by
// the accountant, OR it is a documented PLATFORM SERVICE below. Payments are the accountant's (founder,
// 14 Sep 2026: "anything related to payment is under the accountant agent"): the portal calls them,
// they speak to nobody, and anything they need said goes to the sales engineer as a handoff. Sign-in
// codes and access rules are the it_engineer's since 22 Sep 2026, and Support's delivery pipe stays
// Support's; PLATFORM_SERVICES below names the one owner each must have, and why.
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

// Payment functions the portal may reach. Each must be owned by the accountant -- never the sales
// engineer, customer_support, the ceo or anyone else.
export const ACCOUNTANT_SERVICES = ['stripe_checkout', 'stripe_confirm', 'supplier_pay', 'reveal_invoice', 'quote_pdf', 'refunds_api', 'refund_flow'];

// 18 Sep 2026 (SUPERSEDED on 22 Sep, see below): sign-in, sessions and access rules are NO LONGER carved out here. On 15 Sep the
// estate moved auth_api, login_otp, mobile_otp, voice_otp, voice_otp_capture, role_guard and sup_dob
// off the ownerless 'website' owner and onto sales_engineer, with the reason recorded in the row's
// own note and in scripts/sql/the_ceo_decides_every_sales_engineer_report_and_every_sender_closes_
// their_handoff.sql section 9: "Either portal, its sign-in and its access rules: sales_engineer"
// (a 'website' owner is no seat, so every finding on those 18 slugs fell to the CEO). Carving them
// out here contradicted that decision and failed on the two the portal actually reaches -- login_otp
// and role_guard. They now sit in the sales-owned set, so the check ENFORCES the 15 Sep ownership
// instead of refusing it: "must not be sales_engineer" became "must be sales_engineer".
// send_sms stays below because the same file gave it to customer_support, the only sender.
//
// 22 Sep 2026: the ceo seat's scripts/sql/every_deployed_function_has_exactly_one_right_owner.sql (PR #811,
// applied) re-decided three groups, each on a founder ruling it cites, and this check still asserted the
// 18 Sep map, so it was red on production doing what was decided:
//   * sign-in codes and roles (login_otp, mobile_otp, voice_otp, voice_otp_capture, role_guard) -> it_engineer.
//     Founder, 14 Sep 2026: sign-in is a platform service, not agent work. The portal calls them; they speak
//     to nobody, so the sales engineer still owns every word the portal says.
//   * ai_gateway -> it_engineer: the model switchboard every seat calls is infrastructure.
//   * license_extract, doc_extract, extract_text -> sales_engineer: reading a supplier's licence and documents
//     is supplier verification, the sales engineer's (ruling of 9 Sep 2026). They are no longer Support's
//     pipe, so they leave this map and join the sales-owned set, where the check requires sales_engineer.
// Each platform service now names the ONE owner it must have, so the check is stricter than before: it used to
// assert only "not sales_engineer", which an ownerless or wrongly-seated row passed.
export const PLATFORM_SERVICES = {
  send_sms: { why: 'sign-in / OTP delivery (customer_support is the only sender)', owner: 'customer_support' },
  transcribe: { why: 'channel (Support pipe)', owner: 'customer_support' },
  send_outbox: { why: 'channel (Support pipe)', owner: 'customer_support' },
  send_whatsapp: { why: 'channel (Support pipe)', owner: 'customer_support' },
  ai_gateway: { why: 'model gateway (infrastructure)', owner: 'it_engineer' },
  login_otp: { why: 'sign-in code (platform service)', owner: 'it_engineer' },
  mobile_otp: { why: 'sign-in code (platform service)', owner: 'it_engineer' },
  voice_otp: { why: 'sign-in code (platform service)', owner: 'it_engineer' },
  voice_otp_capture: { why: 'sign-in code (platform service)', owner: 'it_engineer' },
  role_guard: { why: 'access rules (platform service)', owner: 'it_engineer' },
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
const salesOwned = reach.filter((s) => !PLATFORM_SERVICES[s] && !ACCOUNTANT_SERVICES.includes(s));

test('the portal reaches payments only through accountant-owned functions', () => {
  // A reachable function that calls Stripe and is not on the accountant's list is a payment path the
  // sales engineer would own -- the shape supplier_api.pay_registration had until 14 Sep 2026.
  const bad = salesOwned.filter((s) => /api\.stripe\.com/.test(fnSource(s)));
  assert.deepEqual(bad, []);
  assert.ok(reach.includes('supplier_pay'), 'supplier_pay (the accountant\'s) is no longer reachable from the supplier portal');
});

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
  for (const s of reach.filter((x) => PLATFORM_SERVICES[x])) {
    const { why, owner } = PLATFORM_SERVICES[s];
    if (owners.get(s) !== owner) bad.push(`${s}: a ${why} slug owned by ${owners.get(s) ?? '(none)'}, not ${owner}`);
  }
  for (const s of reach.filter((x) => ACCOUNTANT_SERVICES.includes(x))) {
    if (owners.get(s) !== 'accountant') bad.push(`${s}: a payment function owned by ${owners.get(s) ?? '(none)'}, not the accountant`);
    if (binds.has(s) && binds.get(s) !== 'accountant') bad.push(`${s}: llm_seat_binding=${binds.get(s)}`);
  }
  assert.deepEqual(bad, []);
});
