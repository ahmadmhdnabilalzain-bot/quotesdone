// THE REVEAL RATE IS READ OR THE REVEAL IS REFUSED (13 Oct 2026, agent: accountant).
//
// getCfg() used to answer a guessed { standard_reveal_rate: 0.03 } whenever pricing_config could not be
// read, so the reveal confirm dialog quoted a price nobody had set. The rate is pricing_config.id=1 and
// nothing else (ruling 1208: 3% of the final ex-VAT price, no card surcharge). If that row cannot be
// read, or carries a rate that is not a positive number, the answer is "no rate": the caller refuses
// and the accountant gets a finding. Every reader of the rate (customer_api, supplier_api quotation PDF, stripe_checkout) calls this one function.

export type PricingCfg = { standard_reveal_rate: number; refund_window_working_days?: number; [k: string]: unknown };
export type RateRead = { ok: true; cfg: PricingCfg } | { ok: false; error: string };

/** Read pricing_config id=1. Never a default: an unreadable or non-positive rate is { ok:false }. */
export async function readRevealRate(admin: any): Promise<RateRead> {
  let res: { data: any; error: any };
  try { res = await admin.from('pricing_config').select('*').eq('id', 1).maybeSingle(); }
  catch (e) { return { ok: false, error: 'pricing_config_unreadable: ' + String((e as Error)?.message || e) }; }
  if (res.error) return { ok: false, error: 'pricing_config_unreadable: ' + String(res.error.message || res.error) };
  if (!res.data) return { ok: false, error: 'pricing_config_missing' };
  const rate = Number(res.data.standard_reveal_rate);
  if (!(rate > 0 && rate < 1)) return { ok: false, error: 'standard_reveal_rate_invalid: ' + String(res.data.standard_reveal_rate) };
  return { ok: true, cfg: { ...res.data, standard_reveal_rate: rate } };
}

/** The accountant's finding for a refused reveal; one per day, reopened rather than duplicated. */
export async function recordRateUnreadable(admin: any, where: string, error: string, evidence: Record<string, unknown> = {}): Promise<void> {
  try {
    await admin.rpc('fn_it_engineer_finding_upsert', {
      p_issue_key: 'accountant:reveal_rate_unreadable:' + new Date().toISOString().slice(0, 10),
      p_title: 'The reveal rate could not be read from pricing_config; reveals are refused until it can',
      p_where: where, p_blast: 'customer_facing', p_affected: 1,
      p_evidence: { ...evidence, error: error.slice(0, 600), at: new Date().toISOString() },
      p_raised_by: 'accountant',
    });
  } catch (_e) { /* the refusal below stands whether or not the finding lands */ }
}
