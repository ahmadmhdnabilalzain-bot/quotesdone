// Founder ruling 1249 (18 Oct 2026). Seat: customer_support. The homepage widget recommended a supplier
// ("aluminium windows in Dubai") and told a visitor they were a supplier ("who told you i am a supplier?").
// A SOURCE PIN, not a behaviour check: it pins the prompt rules and the message limit that answer that; the scored replies are
// widget_no_supplier_named / widget_no_role_assumed in scripts/eval/support_reply_suite.mjs (EN + AR); the proof of
// behaviour is their live run after deploy.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const src = readFileSync(new URL('../../supabase/functions/site_assistant/index.ts', import.meta.url), 'utf8');
test('the widget never names a supplier and points to sign-up', () => {
  assert.match(src, /Never recommend, name or rank any supplier/);
  assert.match(src, /founder ruling 1249/);
  assert.match(src, /sign up free at quotesdone\.com\/me/);
  assert.match(src, /Never collect or ask for job details/);
});
test('the widget assumes no role', () => {
  assert.match(src, /Never assume, state or hint at their role/);
  assert.doesNotMatch(src, /Read from their words whether they buy/);
});
test('a visitor conversation has a limited number of messages', () => {
  const m = src.match(/site_assistant_conv_hour: (\d+),/);
  assert.ok(m && Number(m[1]) <= 15, 'conversation cap ' + (m && m[1]));
});
test('the widget reports the seat that answered, as the other reply paths do', () => {
  // The homepage widget is customer_support (fn_seat_for_surface: not signed in -> customer_support).
  assert.match(src, /routed: 'brief', routed_seat: seatForSurface \?\? 'customer_support'/);
  const suite = readFileSync(new URL('../eval/support_reply_suite.mjs', import.meta.url), 'utf8');
  assert.match(suite, /j\.routed === 'brief' \? \(j\.routed_seat/);
});
test('the role grader catches an assumed role and passes an offer to register', async () => {
  const m = await import(new URL('../eval/support_reply_suite.mjs', import.meta.url).href);
  const f = (id, reply) => m.GRADERS.forbidden(m.buildScenarios().find((x) => x.id === id), { reply });
  const en = 'widget_no_role_assumed.en.widget', ar = 'widget_no_role_assumed.ar.widget';
  for (const r of ['As a supplier you can register.', 'As a supplier, you pay no commission.', "you're a supplier, so register.", 'Since you are a supplier, the portal is yours.'])
    assert.notEqual(f(en, r), true, r);
  for (const r of ['بصفتك موردًا يمكنك التسجيل.', 'لأنك مورد، سجّل عبر البوابة.', 'أنت مورد، لذا سجّل.'])
    assert.notEqual(f(ar, r), true, r);
  for (const r of ['Nobody did. Do you want a job quoted, or to register as a supplier and receive requests?', 'You can sign up as a supplier at /portal.', 'Use the as a supplier portal link.'])
    assert.equal(f(en, r), true, r);
  assert.equal(f(ar, 'لم يقل أحد ذلك. هل تريد عروض أسعار أم التسجيل كمورد؟'), true);
});
