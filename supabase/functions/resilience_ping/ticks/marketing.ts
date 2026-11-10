// resilience_ping ticks owned by the marketing seat. Moved out of index.ts unchanged (9 Nov 2026);
// the order they run in is still set in index.ts (STEP_RUN).
import { DETACHED_MS, FN, GATEWAY, sec } from '../shared.ts';

// THE MARKETING SEAT'S CHANNELS (22 Sep 2026, marketing). Every beat: publish what is due (a dry run while
// app_secrets.marketing_golive is not 'true'), then the once-a-Dubai-day reads fn_marketing_duties_due names
// (access check, insights, ad spend -> the accountant). Under the seat's own credential, so the run is the
// marketing seat's. The result names only counts: this endpoint is public and secretless.
export async function marketingChannelsTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_marketing_channels');
    if (!secret) return { ok: false, error: 'cred_fn_marketing_channels is not in app_secrets' };
    const r = await fetch(FN + '/marketing_channels', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, action: 'duties' }), signal: AbortSignal.timeout(55000),
    });
    // deno-lint-ignore no-explicit-any
    const j = await r.json().catch(() => null) as any;
    return { status: r.status, ok: j?.ok ?? null, due: j?.publish?.due ?? null, published: j?.publish?.published ?? null,
             dry_run: j?.publish?.dry_run ?? null, daily: j?.daily ? Object.keys(j.daily) : [] };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE MARKETING SEAT'S DUTIES (founder instruction 721, 22 Sep 2026): its own duty list, then fn_marketing_tick
// (the daily report the CEO reads, and the ad-spend loops with the accountant). Presented as the seat, exactly
// as the accountant's duties are; resilience_step 'marketing' sets the cadence.
export async function marketingTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_marketing');
    if (!secret) return { ok: false, error: 'cred_fn_marketing is not in app_secrets' };
    const r = await fetch(FN + '/marketing', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, action: 'duties' }), signal: AbortSignal.timeout(DETACHED_MS),
    });
    // deno-lint-ignore no-explicit-any
    const j = await r.json().catch(() => null) as any;
    return { status: r.status, ok: r.ok && j?.ok !== false, duties: j?.result?.duties ?? null,
             failing: j?.result?.failing ?? null, report: j?.result?.tick?.report ?? null,
             ...(r.ok ? {} : { error: 'marketing ' + r.status }) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE MARKETING SEAT'S BUSINESS DEVELOPMENT (22 Sep 2026, marketing; founder instruction 722). Every beat:
// the morning LinkedIn list once a Dubai day (emailed to the founder only while marketing_golive is 'true'),
// the weekly article cadence and the live check. Under the seat's own credential; the result names only counts.
export async function marketingOutreachTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_marketing_outreach');
    if (!secret) return { ok: false, error: 'cred_fn_marketing_outreach is not in app_secrets' };
    const r = await fetch(FN + '/marketing_outreach', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, action: 'duties' }), signal: AbortSignal.timeout(55000),
    });
    // deno-lint-ignore no-explicit-any
    const j = await r.json().catch(() => null) as any;
    return { status: r.status, ok: j?.ok ?? null, listed: j?.outreach?.listed ?? null, delivery: j?.outreach?.delivery ?? null,
             released: j?.articles?.release?.released ?? null, live: j?.articles?.live?.length ?? null };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
