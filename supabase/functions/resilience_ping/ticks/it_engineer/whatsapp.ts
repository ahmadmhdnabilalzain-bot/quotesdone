// resilience_ping ticks owned by the it_engineer seat: the WhatsApp queue drain and the sender-quality reading. Moved out of ticks/it_engineer.ts unchanged (9 Nov 2026);
// the order the steps run in is still set in resilience_ping/index.ts (STEP_RUN).
import { FN, GATEWAY, admin, sec } from '../../shared.ts';

// THE FOUNDER'S WHATSAPP QUEUE HAD NO CONSUMER AT ALL. Measured 9 Sep 2026: public.notifications
// held a channel='whatsapp' founder alert queued since 7 Sep 18:15 with attempts = 0, and
// public.agent_runs held ZERO rows for send_whatsapp — it has never run. Nothing in the repository
// calls it. It used to be drained by the pg_cron job wa_flush, and pg_cron was removed on 7 Sep by
// the founder's instruction, which is the same day the message stopped moving.
//
// WhatsApp is his command channel, so a queue with no consumer there is not a cosmetic gap: every
// alert routed to it since 7 Sep has been written and never delivered, and nothing reported that,
// because a queued row looks identical to one that is simply waiting its turn.
//
// Swallowed like the other ticks — the founder's WhatsApp must never take the watchdog down — and
// deliberately run on EVERY tick rather than only the unhealthy branch, because the messages this
// drains are mostly written while the system is healthy.
export async function whatsappTick(): Promise<unknown> {
  try {
    const { count } = await admin.from('notifications')
      // 'sending' is counted (22 Sep 2026, CONN-03): a claimed row is mail that has not gone, and only
      // a sender requeues an expired claim, so counting 'queued' alone would report an empty queue in
      // the one case that matters — the sender being down.
      .select('id', { count: 'exact', head: true }).eq('channel', 'whatsapp').in('status', ['queued', 'sending']);
    // A HEARTBEAT THAT BEATS ONLY UNDER LOAD IS NOT A HEARTBEAT (21 Sep 2026). This used to return
    // here when nothing was queued, so send_whatsapp ran only when there was mail: 26 runs in the
    // 3.4 days to 21 Sep against a tick every 15 minutes. fn_it_detect's run_silent arm reads that
    // subject's own rhythm (p50 13 min over 7 days, from the weeks it drained every two minutes) and
    // raised "send_whatsapp has not run for 60/99/150 minutes" — seen 290 times, emailed to the
    // founder on 18 Sep — about a function that had nothing to do. The call is ~0.8 s (resilience_step
    // ewma 1654 ms) and the function's own queue read is its first statement, so it is made on every
    // tick and the subject has a real pulse to be measured against.
    const secret = await sec('cred_fn_resilience_ping');
    const r = await fetch(FN + '/send_whatsapp', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, limit: 25 }), signal: AbortSignal.timeout(30000),
    });
    const sent = { queued: count ?? 0, status: r.status, result: await r.json().catch(() => null) };
    // THE STATUS BACKSTOP (22 Sep 2026). Twilio does not retry a lost status callback, so every tick
    // wa_status asks Twilio directly about any WhatsApp/SMS sent 30+ minutes ago with no final status
    // (bounded: 20 a call, each row once per 30 minutes). Its own try, so it can never stop the drain.
    let backstop: unknown;
    try {
      const b = await fetch(FN + '/wa_status', {
        method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
        body: JSON.stringify({ __secret: secret, poll: true }), signal: AbortSignal.timeout(30000),
      });
      backstop = { status: b.status, result: await b.json().catch(() => null) };
    } catch (e) { backstop = { ok: false, error: String((e as Error)?.message || e) }; }
    return { ...sent, status_backstop: backstop };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE WHATSAPP SENDER'S RATING, READ WITHOUT A MESSAGE (2 Nov 2026, ceo). The supplier invitation gate needs a reading
// under 26 hours old, and until now only a queued invitation caused one, so the channel could never open.
export async function waSenderQualityTick(): Promise<unknown> {
  try {
    const r = await fetch(FN + '/send_whatsapp', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: await sec('cred_fn_resilience_ping'), read_sender_quality: true }), signal: AbortSignal.timeout(8500),
    });
    return { ok: r.ok, status: r.status, result: await r.json().catch(() => null) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
