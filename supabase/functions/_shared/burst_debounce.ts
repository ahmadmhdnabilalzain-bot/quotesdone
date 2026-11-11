// _shared/burst_debounce.ts — several messages in a few seconds get ONE reply (it_engineer, 11 Nov 2026).
//
// The founder (11 Nov 2026, with ruling 1636): when a person sends several messages within a few seconds (WhatsApp
// especially), wait about 3-5 s after the last one and answer them together in one reply, never one reply each.
// MEASURED before this: every WhatsApp message was its own turn from the moment it arrived (wa_inbound/index.ts), so
// "hi" + "I need a quote" + "for 12 windows" sent in four seconds started three classifications and three model replies,
// each written without the other two messages, and the person got three answers to three fragments.
//
// THE RULE, decided by the database rows every message already has (wa_messages, STORED ON ARRIVAL with meta.stage
// 'received'), so it holds across edge workers with no memory between them:
//   - the FIRST waiting message of a burst leads. It waits until QUIET ms have passed since the newest message of the
//     burst (never longer than MAX ms from its own arrival), then claims itself (meta.burst 'lead') and claims each newer
//     waiting text message (meta.stage 'merged', merged_into = its id). Each claim is a conditional update on
//     stage 'received' and burst unset, so a row is answered by exactly one turn;
//   - a later message whose earlier message is still waiting is a FOLLOWER: it waits for the leader's moment plus GRACE,
//     and ends without a reply only on positive evidence (its own row reads stage 'merged'). Not merged by then (the
//     leader died, or it arrived after the leader had claimed): it answers itself, as every message did before;
//   - a document, a voice note, a menu tap or a button is never merged: it is answered on its own path.
// A read that fails, or a claim that is not confirmed, answers the message alone: the rule can delay a reply by a few
// seconds, it can never lose one (a row left 'received' is still swept to customer_support after 5 minutes).
// prevented by: _shared/burst_debounce.test.ts, wa_inbound/burst.test.ts

/** Wait this long after the newest message of a burst before answering (the setting wa_burst_quiet_ms; 0 turns it off). */
export const BURST_QUIET_MS = 4_000;
/** A burst is never waited on longer than this from its first message, however long the person keeps typing. */
export const BURST_MAX_MS = 12_000;
/** A follower waits this much longer than its leader, so the leader's claim comes first. */
export const FOLLOWER_GRACE_MS = 1_500;

/** The setting's value as milliseconds: a whole number 0-8000, anything else the default. */
export function quietFrom(v: unknown): number {
  const s = String(v ?? '').trim();
  if (!/^[0-9]{1,5}$/.test(s)) return BURST_QUIET_MS;
  return Math.min(8_000, Number(s));
}

export interface ArrivalRow {
  id: number;
  at: number;               // arrival, epoch ms (wa_messages.created_at)
  stage: string | null;     // meta.stage
  burst: string | null;     // meta.burst: 'lead' | 'merged' | 'alone' | null
  media: number;            // meta.media
  inbound: string;
  sid?: string | null;      // meta.message_sid
}

/** A message another turn may answer together with its own: still waiting, unclaimed, text only. */
export function mergeable(r: ArrivalRow): boolean {
  return r.stage === 'received' && !r.burst && !(Number(r.media) > 0) && String(r.inbound || '').trim() !== '';
}

export type Plan =
  | { kind: 'wait'; ms: number }                 // the burst may still be going: look again in ms
  | { kind: 'follow'; ms: number }               // an earlier message leads: look again in ms (merged, or answer myself)
  | { kind: 'lead'; merge: ArrivalRow[] };       // answer now, with these later messages

/** What this turn does now, from the rows of the same number (any order; rows not newer than `now` only). */
export function planBurst(me: { id: number; at: number }, rows: readonly ArrivalRow[], now: number, quietMs = BURST_QUIET_MS): Plan {
  const others = rows.filter((r) => r.id !== me.id && r.at <= now);
  const newer = others.filter((r) => r.id > me.id && mergeable(r)).sort((a, b) => a.id - b.id);
  const older = others.filter((r) => r.id < me.id && r.at >= me.at - BURST_MAX_MS && mergeable(r));
  const last = Math.max(me.at, ...newer.map((r) => r.at));
  if (older.length) {
    const first = Math.min(...older.map((r) => r.at));
    const due = Math.min(last + quietMs, first + BURST_MAX_MS) + FOLLOWER_GRACE_MS;
    if (now < due) return { kind: 'follow', ms: due - now };
    return { kind: 'lead', merge: newer };
  }
  const due = Math.min(last + quietMs, me.at + BURST_MAX_MS);
  return now < due ? { kind: 'wait', ms: due - now } : { kind: 'lead', merge: newer };
}

/** The messages as the turn reads them: its own first, then each later one on its own line, in the order they arrived. */
export function combinedBody(own: string, merged: readonly ArrivalRow[]): string {
  return [own, ...[...merged].sort((a, b) => a.id - b.id).map((r) => r.inbound)].map((s) => String(s || '').trim()).filter(Boolean).join('\n');
}
