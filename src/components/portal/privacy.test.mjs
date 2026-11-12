// The self-service privacy controls: what a person is told, and whether the screens still call the
// routines #1237 granted. Fails if either portal's account page loses the controls, if the supplier's
// stops being English, or if a routine the screen calls is no longer granted to signed-in users.
//
//   node --test src/components/portal/privacy.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { errorText, keptLines, pendingFrom, livePending, pendingFromStatus, isCode, pt, ptList } from './privacy.ts';
import { readSource } from '../../../scripts/lib/portal_sources.mjs';

const read = (p) => readFileSync(new URL(p, import.meta.url), 'utf8');
const SQL = read('../../../scripts/sql/a_person_can_get_a_copy_of_their_data_and_have_it_erased_where_no_law_requires_it_kept.sql');
const UI = read('./PrivacyControls.tsx');

test('every routine the screen calls is granted to authenticated, with the argument names it sends', () => {
  for (const [fn, args] of [['pdpl_request_me', ['p_kind']], ['pdpl_confirm_me', ['p_request', 'p_code']], ['pdpl_cancel_me', ['p_request']]]) {
    assert.ok(UI.includes(`'${fn}'`), `${fn} is called`);
    assert.match(SQL, new RegExp(`grant execute on function public\\.${fn}\\([^)]*\\) to authenticated`), `${fn} granted`);
    const sig = SQL.match(new RegExp(`function public\\.${fn}\\(([^)]*)\\)\\s*returns`))[1];
    for (const a of args) { assert.ok(sig.includes(a), `${fn} takes ${a}`); assert.ok(UI.includes(a + ':'), `UI sends ${a}`); }
  }
});

test('both account pages mount the controls; the supplier one is English only', () => {
  assert.ok(readSource('src/components/me/CustomerPortal.tsx').includes("<PrivacyControls token={token} lang={lang === 'ar' ? 'ar' : 'en'} />"));
  assert.ok(read('./supplier/SupplierSettings.tsx').includes('<PrivacyControls token={token} lang="en" />'));
  for (const id of ['privacy-export', 'privacy-erase', 'privacy-code', 'privacy-erase-cancel']) assert.ok(UI.includes(`data-testid="${id}"`), id);
});

test('refusals become plain sentences, never the server wording', () => {
  assert.equal(errorText('en', { ok: false, code: 'email_not_verified' }), 'Verify your email address in your account first.');
  assert.equal(errorText('en', { ok: false, error: 'wrong or expired code', attempts_left: 3 }), 'That code is wrong or has expired. 3 tries left.');
  assert.match(errorText('ar', { ok: false, error: 'this code is spent; ask for a new one' }), /رمز جديد/);
  assert.match(errorText('en', { ok: false, error: 'too many attempts for this address; try again in an hour' }), /hour/);
  assert.match(errorText('en', { ok: false, error: 'no erasure in its cooling-off window' }), /no longer be cancelled/);
  assert.equal(errorText('en', null), pt('en', 'e_generic'));
});

test('a confirmed erase is scheduled, a refusal is not', () => {
  const ok = { ok: true, request_id: 'r1', status: 'cooling_off', confirm_after: '2026-10-14T10:00:00Z',
    plan: { erase_now: [], deferred: [{ record: 'customer 9', legal_hold: true, kept_until: '2032-01-01', reason: 'x' }] } };
  assert.deepEqual(pendingFrom('r1', ok), { id: 'r1', confirm_after: '2026-10-14T10:00:00Z', deferred: ok.plan.deferred });
  assert.equal(pendingFrom('r1', { ok: false, error: 'wrong or expired code' }), null);
  assert.equal(pendingFrom('r1', { ok: true, request_id: 'r1', export: {} }), null);
});

test('a legal hold is stated plainly; a statutory keep names its date; Arabic is Arabic', () => {
  const [hold, law] = keptLines('en', [{ record: 'supplier 4', legal_hold: true }, { record: 'customer 9', legal_hold: false, kept_until: '2032-01-01' }]);
  assert.match(hold, /^On hold: your supplier record is linked to an open dispute/);
  assert.match(law, /^Kept until 1 January 2032/);
  for (const l of keptLines('ar', [{ record: 'customer 9', legal_hold: true }]).concat(ptList('ar', 'del_warn'))) assert.doesNotMatch(l, /[A-Za-z]/, l);
});

test('the warning names what is kept: tax records 5 years and open disputes', () => {
  const w = ptList('en', 'del_warn').join(' ');
  assert.match(w, /tax records are kept for 5 years/); assert.match(w, /open dispute/); assert.match(w, /7 days/);
  assert.doesNotMatch(UI + JSON.stringify(ptList('en', 'del_warn')), /\bAI\b/);
});

test('a remembered erase shows only while it can be cancelled', () => {
  const now = Date.parse('2026-10-08T00:00:00Z');
  assert.ok(livePending(JSON.stringify({ id: 'r', confirm_after: '2026-10-14T00:00:00Z', deferred: [] }), now));
  assert.equal(livePending(JSON.stringify({ id: 'r', confirm_after: '2026-10-01T00:00:00Z', deferred: [] }), now), null);
  assert.equal(livePending('not json', now), null);
  assert.equal(livePending(null, now), null);
});

test('only six digits are a code', () => {
  assert.ok(isCode('012345')); assert.ok(!isCode('12345')); assert.ok(!isCode('1234567')); assert.ok(!isCode('12a456'));
});

const STATUS_SQL = read('../../../scripts/sql/a_person_sees_their_own_open_privacy_requests_on_any_device.sql');
test('pdpl_status_me: own address only, pinned, anon revoked, authenticated granted, no secrets returned', () => {
  for (const s of ['function public.pdpl_status_me()', "security definer set search_path to 'public', 'pg_temp'", 'fn_pdpl_my_verified_email()',
    'revoke execute on function public.pdpl_status_me() from public, anon;', 'grant execute on function public.pdpl_status_me() to authenticated;'])
    assert.ok(STATUS_SQL.includes(s), s);
  assert.doesNotMatch(STATUS_SQL.replace(/^--.*$/gm, ''), /code_sha|fn_pdpl_export_data/);
  assert.ok(UI.includes("'pdpl_status_me'"), 'the account page reads it on load');
  assert.match(read('../../../scripts/checks/anon_cannot_execute_security_definer.test.mjs'), /pdpl_status_me:/);
});

test('the server status decides Cancel on any device; an unanswerable status keeps the local one', () => {
  const now = Date.parse('2026-10-08T00:00:00Z');
  const ok = { ok: true, requests: [
    { request_id: 'x', kind: 'export', status: 'received' },
    { request_id: 'r9', kind: 'delete', status: 'cooling_off', confirm_after: '2026-10-14T00:00:00Z', deferred: [{ record: 'customer 1', legal_hold: true }] }] };
  assert.deepEqual(pendingFromStatus(ok, now), { id: 'r9', confirm_after: '2026-10-14T00:00:00Z', deferred: [{ record: 'customer 1', legal_hold: true }] });
  assert.equal(pendingFromStatus({ ok: true, requests: [] }, now), null);
  assert.equal(pendingFromStatus({ ok: true, requests: [{ request_id: 'r', kind: 'delete', status: 'received' }] }, now), null);
  assert.equal(pendingFromStatus({ ok: false, code: 'email_not_verified' }, now), undefined);
  assert.equal(pendingFromStatus(null, now), undefined);
});

test('each portal calls the routines with its OWN session, never a shared storage key', () => {
  // the controls take the portal's token and use it for every call; no storage key is named here
  const has = (src, s) => assert.ok(src.includes(s), s), lacks = (src, s) => assert.ok(!src.includes(s), 'must not contain ' + s);
  has(UI, "supaRpcAs(token || '', fn, args)");
  for (const s of ['qd-portal-auth', 'qd-cust-auth', 'supaRpcMaybeOne', 'supaClient(']) lacks(UI, s);
  // and that token is the portal's own: the customer's comes from qd-cust-token, the supplier's from qd-sup-token
  const cust = readSource('src/components/me/CustomerPortal.tsx'), sup = readSource('src/components/portal/SupplierPortal.tsx'), set = read('./supplier/SupplierSettings.tsx');
  has(cust, "localStorage.setItem('qd-cust-token'"); lacks(cust, 'qd-sup-token');
  has(sup, "localStorage.setItem('qd-sup-token'"); lacks(sup, 'qd-cust-token');
  has(sup, '<SupplierSettings token={token}'); has(set, '<PrivacyControls token={token}');
  has(cust, '<AccountSettings token={token}'); has(cust, '<PrivacyControls token={token}');
});

// Walk of 12 Nov 2026 (sales_engineer, built by it_engineer), S1 and S2: once the code was sent the only button was "Confirm
// deletion" (w2_iphone_erase_code.jpg), and the "Before you continue" warning measured 2.6:1 at 12.5 px. This fails if the code
// step loses its way back, if going back does more than close the step, or if the warning goes back to muted text under 14 px.
test('the code step has a way back, and the warning is read at 14 px in the page\'s own text colour', () => {
  const form = UI.slice(UI.indexOf('<form'), UI.indexOf('</form>'));
  assert.match(form, /data-testid="privacy-erase-back"/, 'no Back on the code step');
  assert.match(form, /onClick=\{\(\) => \{ setReq\(null\); setCode\(''\); setAck\(false\);/);
  assert.equal(pt('en', 'cancel_btn'), 'Cancel deletion');
  const warn = UI.slice(UI.indexOf('data-testid="privacy-erase-warning"'), UI.indexOf("ptList(lang, 'del_warn')"));
  assert.ok(warn.length > 0, 'the warning block was not found');
  assert.doesNotMatch(warn, /text-muted-foreground|text-\[1[0-3](\.\d+)?px\]|bg-muted/, 'the warning is muted or under 14 px again');
});
