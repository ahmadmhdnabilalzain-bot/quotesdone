// burst.ts - THE TURN GATE, between the arrival and the answer (it_engineer, 11 Nov 2026). One hook in index.ts: turnGate.
//   1. A BURST IS ONE TURN (_shared/burst_debounce.ts): messages sent within a few seconds are answered together, once,
//      by the turn of the first of them; the others end without a reply of their own. Durable across edge workers: the
//      claim is a conditional update of the wa_messages arrival rows, never memory.
//   2. TWO MACHINES NEVER ANSWER EACH OTHER FOR EVER (_shared/auto_reply_loop.ts): when our replies to this number reached
//      LOOP_CAP inside the hour with no human-sounding message of theirs between them, this turn is recorded unanswered and
//      raised to it_engineer, and no model is asked.
// A Response means the turn is over. Every read that fails answers the message as before.
// prevented by: wa_inbound/burst.test.ts
import { BURST_MAX_MS, combinedBody, mergeable, planBurst, quietFrom, type ArrivalRow } from '../_shared/burst_debounce.ts';
import { AUTO_REPEAT_MS, LOOP_CAP, LOOP_WINDOW_MS, loopVerdict, type LoopEvent } from '../_shared/auto_reply_loop.ts';
import { admin, itFinding, sec, TW } from './shared.ts';
import type { WaTurn } from './turn.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;
type Row = { id: number; created_at: string; inbound?: string | null; reply?: string | null; sent?: boolean | null; replied_at?: string | null; meta?: Record<string, unknown> | null };
export interface GateDeps { admin: Admin; setting: (k: string) => Promise<string>; finding: typeof itFinding; sleep: (ms: number) => Promise<void>; now: () => number;
  isFounder: (from: string) => Promise<boolean> }
/** The founder's number, read the way hear.ts reads it (fn_identify_contact). */
async function founderNumber(from: string): Promise<boolean> {
  try { const { data } = await admin.rpc('fn_identify_contact', { p_phone: from }); return (data as { audience?: string } | null)?.audience === 'founder'; } catch (_e) { return false; }
}
/** Below this own write lag a turn is running beside the database and the leader does not look again. */
export const LAG_FLOOR_MS = 600;
/** The longest extra look a leader takes for rows written late (the unpinned lag measured 11 Nov was 1.1-1.6 s). */
export const LAG_MAX_MS = 2_500;
const liveDeps: GateDeps = { admin, setting: sec, finding: itFinding, sleep: (ms) => new Promise((r) => setTimeout(r, ms)), now: () => Date.now(), isFounder: founderNumber };

const asArrival = (r: Row): ArrivalRow => ({
  id: Number(r.id), at: Date.parse(r.created_at) || 0, stage: (r.meta?.stage as string) ?? null, burst: (r.meta?.burst as string) ?? null,
  media: Number(r.meta?.media ?? 0) || 0, inbound: String(r.inbound ?? ''), sid: (r.meta?.message_sid as string) ?? null,
});

/** This number's rows since `sinceMs`, or null when the read failed. */
async function rowsSince(d: GateDeps, from: string, sinceMs: number): Promise<Row[] | null> {
  try {
    const { data, error } = await d.admin.from('wa_messages').select('id,created_at,inbound,reply,sent,replied_at,meta')
      .eq('wa_from', from).gte('created_at', new Date(sinceMs).toISOString()).order('id', { ascending: true }).limit(200);
    if (error || !Array.isArray(data)) return null;
    return (data as Row[]).filter((r) => r && Number.isFinite(Number(r.id)) && typeof r.created_at === 'string');
  } catch (_e) { return null; }
}

/** A conditional claim on one arrival row: true only when the database says this update won it. */
async function claim(d: GateDeps, r: Row, patch: Record<string, unknown>): Promise<boolean> {
  try {
    const { data, error } = await d.admin.from('wa_messages').update({ meta: { ...(r.meta ?? {}), ...patch } })
      .eq('id', r.id).eq('meta->>stage', 'received').is('meta->>burst', null).select('id');
    return !error && Array.isArray(data) && data.length === 1;
  } catch (_e) { return false; }
}

/** 'merged': another turn answers this message. 'answer': go on (with t.Body / t.burst set when messages were merged). */
export async function joinBurst(t: WaTurn, d: GateDeps = liveDeps): Promise<'merged' | 'answer'> {
  if (t.arrivalId == null || t.internalCaller) return 'answer';
  const quiet = quietFrom(await d.setting('wa_burst_quiet_ms'));
  const me = { id: t.arrivalId, at: Date.parse(t.receivedAt) || d.now() };
  const textOnly = !t.media.length && !t.ListId && !t.ButtonPayload && !t.voice;
  // A ROW WRITTEN LATE IS STILL PART OF THE BURST (final audit 12 Nov 2026, W5 / integration F7). An arrival row is stamped at
  // receipt but written after the request was authenticated; unpinned (us-east-1) that took 1.1-1.6 s, so a leader deciding at
  // exactly +quiet missed the next message's row and "Hi" was answered alone. This turn's own write lag is the lag the other
  // messages' rows have too: when it is more than LAG_FLOOR_MS, the leader looks once more after that long before it claims.
  // Pinned beside the database the lag is a few hundred ms and nothing is added.
  const lag = Math.min(LAG_MAX_MS, Number(t.arrivalLagMs ?? 0) || 0);
  let lookedAgain = lag <= LAG_FLOOR_MS;
  for (let round = 0; round < 12; round++) {
    const rows = await rowsSince(d, t.From, me.at - BURST_MAX_MS - 2_000);
    if (!rows) return 'answer';
    const own = rows.find((r) => Number(r.id) === me.id);
    if (!own) return 'answer';
    if (own.meta?.stage === 'merged') { t.arrivalId = null; return 'merged'; }
    // a document, a voice note, a menu tap or a button is answered on its own path and is never merged into another turn
    if (!textOnly || quiet === 0) { await claim(d, own, { burst: 'alone' }); return 'answer'; }
    const plan = planBurst(me, rows.map(asArrival), d.now(), quiet);
    if (plan.kind !== 'lead') { await d.sleep(Math.min(plan.ms, 4_000)); continue; }
    if (!lookedAgain) { lookedAgain = true; await d.sleep(lag + 250); continue; }
    if (!(await claim(d, own, { burst: 'lead' }))) {
      const again = (await rowsSince(d, t.From, me.at - 1_000))?.find((r) => Number(r.id) === me.id);
      if (again?.meta?.stage === 'merged') { t.arrivalId = null; return 'merged'; }
      return 'answer';   // claimed by nobody we can see (the sweep, a failed write): answered alone, as before
    }
    const taken: ArrivalRow[] = [];
    for (const m of plan.merge) {
      const row = rows.find((r) => Number(r.id) === m.id);
      if (row && mergeable(m) && await claim(d, row, { stage: 'merged', burst: 'merged', merged_into: me.id,
        no_autoreply_reason: 'answered together with wa_messages #' + me.id + ' (several messages in a few seconds, one reply: burst.ts)' })) taken.push(m);
    }
    if (taken.length) {
      t.Body = combinedBody(t.Body, taken);
      // THE LEADER'S ROW CARRIES EVERY MERGED MESSAGE AT ONCE (integration F7): the merged rows are 'merged' from here on, so a
      // leader whose worker died would leave fn_wa_arrival_sweep and the history (_shared/wa_history.ts skips merged rows) with
      // its own first message only. Written while its row is still 'received'; a failure leaves it as before, never worse.
      try { await d.admin.from('wa_messages').update({ inbound: t.Body }).eq('id', me.id).eq('meta->>stage', 'received'); } catch (_e) { /* as before */ }
      const last = taken[taken.length - 1];
      t.burst = { merged: taken.map((m) => m.id), lastAt: last.at, lastSid: String(last.sid || t.MessageSid || '') };
    }
    return 'answer';
  }
  return 'answer';
}

/** The loop cap: whether this turn must not be answered, from this number's last hour (the current message included). */
export async function loopHeld(t: WaTurn, d: GateDeps = liveDeps): Promise<{ held: boolean; ours: number }> {
  const now = d.now();
  const rows = await rowsSince(d, t.From, now - LOOP_WINDOW_MS);
  if (!rows) return { held: false, ours: 0 };
  const events: LoopEvent[] = [];
  for (const r of rows) {
    if (r.meta?.stage === 'merged' || (t.arrivalId != null && Number(r.id) === t.arrivalId)) continue;
    const at = Date.parse(r.created_at) || 0;
    if (String(r.inbound ?? '').trim()) events.push({ at, who: 'them', text: String(r.inbound) });
    if (r.sent === true && String(r.reply ?? '').trim()) events.push({ at: Date.parse(String(r.replied_at ?? '')) || at + 1, who: 'us', text: String(r.reply) });
  }
  // the message is stamped when it ARRIVED, not when the burst wait ended (review of 12 Nov 2026: 4-7 s later, which made a
  // repeat sent within AUTO_REPEAT_MS of our reply look slower than it was)
  events.push({ at: Math.min(now, Date.parse(t.receivedAt) || now), who: 'them', text: t.Body });
  const v = loopVerdict(events, now, LOOP_CAP, LOOP_WINDOW_MS, { repeatWithinMs: AUTO_REPEAT_MS });
  // the founder's own number is his command channel (founder.ts): no cap stops him, whatever he repeats. Read only when the
  // cap would stop the turn, so an ordinary turn pays nothing for it; a read that fails keeps the stop.
  if (v.stop && await d.isFounder(t.From)) return { held: false, ours: v.oursSinceHuman };
  return { held: v.stop, ours: v.oursSinceHuman };
}

/** THE HOOK (index.ts, after the arrival): a burst is answered once, and a loop with a machine is stopped. */
export async function turnGate(t: WaTurn, d: GateDeps = liveDeps): Promise<Response | undefined> {
  if ((await joinBurst(t, d)) === 'merged') {
    void t.logRun('ok', { burst_merged: 1 }, 'this message is answered together with an earlier one sent seconds before it (burst.ts); no reply of its own');
    return TW(200);
  }
  const loop = await loopHeld(t, d);
  if (!loop.held) return undefined;
  try {
    await t.waInsert(t.receivedAt, { wa_from: t.From, wa_to: 'whatsapp:' + (await d.setting('twilio_wa_from')), profile_name: t.Profile, inbound: t.Body,
      reply: '', lang: /[\u0600-\u06FF]/.test(t.Body) ? 'ar' : 'en', escalated: false, sent: false,
      meta: { message_sid: t.MessageSid || null, provenance_verified: true, no_autoreply_reason: 'auto_reply_loop', replies_since_a_person: loop.ours } });
  } catch (_e) { /* the finding below still records it */ }
  await d.finding('wa_inbound:auto_reply_loop', 'WhatsApp replies to one number reached ' + LOOP_CAP + ' within an hour with no human-sounding message between them; replying stopped',
    { phone_tail: t.From.replace(/[^0-9]/g, '').slice(-4), replies_since_a_person: loop.ours, cap: LOOP_CAP, window_min: LOOP_WINDOW_MS / 60_000, message_sid: t.MessageSid || null });
  return TW(200);
}
