// Run: deno test --no-lock --node-modules-dir=auto supabase/functions/stripe_setup/payment_methods.test.ts
// A fake Stripe holds one configuration and a domain list in memory, so the tests prove what is
// written, what is never written (buy-now-pay-later), and that a second run writes nothing.
import { assertEquals } from 'jsr:@std/assert@1';
import { BNPL_DENY, syncDomains, syncPaymentMethods, type StripeCall } from './payment_methods.ts';

const pm = (preference: string, available = true, overridable = true) =>
  ({ available, display_preference: { overridable, preference, value: preference } });

function fakeStripe() {
  const cfg: Record<string, any> = {
    id: 'pmc_zzdemo', object: 'payment_method_configuration', is_default: true, application: null, livemode: false, name: 'Default',
    card: pm('on'), apple_pay: pm('on'), link: pm('on'), google_pay: pm('off', false),
    klarna: pm('off'), tabby: pm('off'), afterpay_clearpay: pm('off'), locked: pm('off', true, false),
  };
  const other = { id: 'pmc_platform', is_default: true, application: 'ca_other', card: pm('off') };
  const domains: any[] = [{ id: 'pmd_com', domain_name: 'quotesdone.com', enabled: true, apple_pay: { status: 'active' } }];
  const writes: { path: string; form: Record<string, string> }[] = [];
  const stripe: StripeCall = async (path, form) => {
    if (form) writes.push({ path, form: Object.fromEntries(form) });
    if (path.startsWith('payment_method_configurations?')) return { ok: true, status: 200, j: { data: [other, cfg] } };
    if (path === 'payment_method_configurations/pmc_zzdemo' && form) {
      for (const [k, v] of form) { const t = k.split('[')[0]; cfg[t].display_preference.preference = v; }
      return { ok: true, status: 200, j: cfg };
    }
    if (path.startsWith('payment_method_domains?')) return { ok: true, status: 200, j: { data: domains } };
    if (path === 'payment_method_domains' && form) {
      const d = { id: 'pmd_' + domains.length, domain_name: form.get('domain_name'), enabled: true, apple_pay: { status: 'active' } };
      domains.push(d); return { ok: true, status: 200, j: d };
    }
    return { ok: false, status: 404, j: {} };
  };
  return { stripe, cfg, writes };
}

Deno.test('the deny-list names the instalment services the founder excluded', () => {
  for (const t of ['tabby', 'tamara', 'klarna', 'affirm', 'afterpay_clearpay', 'zip']) assertEquals(BNPL_DENY.has(t), true, t);
  for (const t of ['card', 'apple_pay', 'google_pay', 'link']) assertEquals(BNPL_DENY.has(t), false, t);
});

Deno.test('google_pay goes on; BNPL is never written; the platform config is not ours', async () => {
  const f = fakeStripe();
  const r = await syncPaymentMethods(f.stripe);
  const by = Object.fromEntries(r.methods.map((m) => [m.type, m]));
  assertEquals([by.google_pay.before, by.google_pay.after, by.google_pay.action], ['off', 'on', 'enabled']);
  assertEquals([by.card.action, by.klarna.action, by.tabby.action, by.afterpay_clearpay.action], ['already_on', 'skipped_bnpl', 'skipped_bnpl', 'skipped_bnpl']);
  assertEquals(by.locked.action, 'not_overridable');
  assertEquals(f.writes.map((w) => Object.keys(w.form)[0]), ['google_pay[display_preference][preference]']);
  assertEquals(f.writes.every((w) => w.path === 'payment_method_configurations/pmc_zzdemo'), true);
  assertEquals([f.cfg.klarna.display_preference.preference, f.cfg.tabby.display_preference.preference], ['off', 'off']);
});

Deno.test('idempotent: the second run writes nothing and reports everything already on', async () => {
  const f = fakeStripe();
  await syncPaymentMethods(f.stripe);
  await syncDomains(f.stripe);
  const n = f.writes.length;
  const m = await syncPaymentMethods(f.stripe);
  const d = await syncDomains(f.stripe);
  assertEquals(f.writes.length, n);
  assertEquals(m.methods.filter((x) => x.action === 'enabled'), []);
  assertEquals(d.domains.map((x) => [x.domain, x.before]), [['quotesdone.com', 'registered'], ['quotesdone.ae', 'registered']]);
});

Deno.test('the missing wallet domain is added, the registered one is left alone', async () => {
  const f = fakeStripe();
  const d = await syncDomains(f.stripe);
  assertEquals(d.domains.map((x) => [x.domain, x.before, x.after]), [['quotesdone.com', 'registered', 'registered'], ['quotesdone.ae', 'missing', 'registered']]);
  assertEquals(f.writes, [{ path: 'payment_method_domains', form: { domain_name: 'quotesdone.ae' } }]);
});

Deno.test('dry_run writes nothing', async () => {
  const f = fakeStripe();
  const m = await syncPaymentMethods(f.stripe, true);
  await syncDomains(f.stripe, true);
  assertEquals(f.writes, []);
  assertEquals(m.methods.find((x) => x.type === 'google_pay')!.action, 'dry_run');
});
