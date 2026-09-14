// PAYMENT METHODS AND WALLET DOMAINS, DECLARED IN CODE (14 Sep 2026, agent: accountant, for the ceo).
//
// Founder: "whatever available options in UAE with stripe then add it. except for services like
// tabby or so." Measured the same day through the Stripe API: the default payment method
// configuration (live pmc_1To5ETC45SqX5pVb5tZjqFQK, test pmc_1To5ETC45SqX5pVbkBkuuzmh) had card,
// apple_pay and link on, google_pay off. Samsung Pay is not offered to this account at all.
//
// The rule, so it can be re-run rather than re-remembered:
//   every payment method type Stripe reports on the default configuration is switched ON,
//   EXCEPT buy-now-pay-later, which stays exactly as it is (never switched on, never touched).
// The reveal's Payment Element (src/components/me/RevealPayment.tsx) passes no paymentMethodTypes,
// so it shows whatever this configuration allows and the device supports — Google Pay on Chrome and
// Android, Apple Pay on Safari and iOS once the domain below is registered.
//
// Idempotent: a method already 'on' is not written, a domain already registered is not re-added.

export type StripeResult = { ok: boolean; status: number; j: any };
/** GET when form is undefined, POST otherwise. */
export type StripeCall = (path: string, form?: URLSearchParams) => Promise<StripeResult>;

// Buy-now-pay-later. The founder excluded these by name ("tabby or so"). A type on this list is
// never written, whatever its current setting. Extend it when Stripe adds a new instalment method.
export const BNPL_DENY = new Set([
  'affirm', 'afterpay_clearpay', 'alma', 'atome', 'billie', 'clearpay', 'humm', 'klarna', 'kriya',
  'laybuy', 'mondu', 'openpay', 'paybright', 'riverty', 'scalapay', 'sequra', 'sunbit', 'tabby',
  'tamara', 'zip',
]);

// Apple Pay and Google Pay only render on a registered domain.
export const WALLET_DOMAINS = ['quotesdone.com', 'quotesdone.ae'];

export type MethodRow = {
  type: string; available: boolean | null; before: string | null; after: string | null;
  action: 'already_on' | 'enabled' | 'skipped_bnpl' | 'not_overridable' | 'dry_run' | 'failed';
  error?: string;
};

// A configuration object mixes metadata (id, name, is_default ...) with one object per method; a
// method is anything that carries a display_preference.
function methodsOf(cfg: any): [string, any][] {
  return Object.entries(cfg || {}).filter(([, v]) => v && typeof v === 'object' && (v as any).display_preference);
}

export async function syncPaymentMethods(stripe: StripeCall, dryRun = false) {
  const list = await stripe('payment_method_configurations?limit=100');
  if (!list.ok) return { ok: false, error: 'configuration_list_failed: ' + (list.j?.error?.message || 'http ' + list.status), methods: [] as MethodRow[] };
  // The account's own default, not one belonging to a Connect platform application.
  const cfg = (list.j?.data || []).find((c: any) => c.is_default && !c.application);
  if (!cfg) return { ok: false, error: 'no_default_configuration', methods: [] as MethodRow[] };

  const rows: MethodRow[] = [];
  for (const [type, m] of methodsOf(cfg)) {
    const pref = m.display_preference || {};
    const row: MethodRow = { type, available: m.available ?? null, before: pref.preference ?? null, after: pref.preference ?? null, action: 'already_on' };
    if (BNPL_DENY.has(type)) row.action = 'skipped_bnpl';
    else if (pref.preference === 'on') row.action = 'already_on';
    else if (pref.overridable === false) row.action = 'not_overridable';
    else if (dryRun) row.action = 'dry_run';
    else {
      // One write per method: a type Stripe refuses (not offered for AED, needs activation) must
      // not stop the others, and its refusal is reported rather than swallowed.
      const up = await stripe('payment_method_configurations/' + cfg.id, new URLSearchParams({ [`${type}[display_preference][preference]`]: 'on' }));
      if (up.ok) { row.action = 'enabled'; row.after = up.j?.[type]?.display_preference?.preference ?? 'on'; }
      else { row.action = 'failed'; row.error = up.j?.error?.message || 'http ' + up.status; }
    }
    rows.push(row);
  }
  return { ok: rows.every((r) => r.action !== 'failed'), configuration: cfg.id, livemode: cfg.livemode ?? null, methods: rows };
}

export type DomainRow = { domain: string; before: string; after: string; id?: string; apple_pay?: string | null; google_pay?: string | null; error?: string };

export async function syncDomains(stripe: StripeCall, dryRun = false) {
  const list = await stripe('payment_method_domains?limit=100');
  if (!list.ok) return { ok: false, error: 'domain_list_failed: ' + (list.j?.error?.message || 'http ' + list.status), domains: [] as DomainRow[] };
  const have = new Map<string, any>((list.j?.data || []).map((d: any) => [String(d.domain_name), d]));
  const rows: DomainRow[] = [];
  for (const domain of WALLET_DOMAINS) {
    const d = have.get(domain);
    if (d && d.enabled !== false) { rows.push({ domain, before: 'registered', after: 'registered', id: d.id, apple_pay: d.apple_pay?.status ?? null, google_pay: d.google_pay?.status ?? null }); continue; }
    if (dryRun) { rows.push({ domain, before: d ? 'disabled' : 'missing', after: 'dry_run' }); continue; }
    const r = d
      ? await stripe('payment_method_domains/' + d.id, new URLSearchParams({ enabled: 'true' }))
      : await stripe('payment_method_domains', new URLSearchParams({ domain_name: domain }));
    rows.push(r.ok
      ? { domain, before: d ? 'disabled' : 'missing', after: 'registered', id: r.j?.id, apple_pay: r.j?.apple_pay?.status ?? null, google_pay: r.j?.google_pay?.status ?? null }
      : { domain, before: d ? 'disabled' : 'missing', after: 'failed', error: r.j?.error?.message || 'http ' + r.status });
  }
  return { ok: rows.every((r) => r.after !== 'failed'), domains: rows };
}
