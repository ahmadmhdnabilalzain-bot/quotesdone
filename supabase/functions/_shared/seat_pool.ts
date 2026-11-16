// seat_pool — the shared pool every seat's model path reads. Seat: ceo. 13 Nov 2026, founder ledger 1688:
//   "there is like a shared pool where they all know what's going on around ... everyone should know."
//
// ONE function builds the view, so every seat reads the same thing: public.fn_seat_pool_context(seat, subject, audience)
// (scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql). It returns, newest first, what EVERY seat did
// or decided about the same subject (events, hand-overs with their outcome, judgements: who, what, when, outcome), and for
// an internal audience the company today (cached per window in SQL, never one model call per event) and this seat's own
// hand-overs nobody answered ("no answer yet from <seat> since <time>"). A customer's or a supplier's reply reads the
// timeline's kinds and states only: no name, no payload text.
//
// Read by think() (every seat's reasoning: replies, decisions, the CEO's reviews and its it.finding and overdue triage, the IT
// postmortems), by aiReply (the conversation replies) and by the CEO's judgement. BUDGET (ruling 1619): the SQL orders the block
// by importance (your hand-overs, the subject, the company today) inside SQL_BUDGET characters, and the header is counted
// inside POOL_MAX_CHARS, so nothing is cut here: about 300 tokens (scripts/checks/every_seat_reads_one_pool.test.mjs).
// A customer's or supplier's reply passes that party's own id (customer_id / supplier_id): it then reads only its own events.
// NEVER IN THE WAY: an error, a missing routine (the SQL not applied yet) or a slow database gives an empty block within
// POOL_TIMEOUT_MS, and the reply goes on exactly as before.

type Rpc = { rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { message: string } | null }> };

export const POOL_MAX_CHARS = 1300;
export const POOL_TIMEOUT_MS = 1500;
/** The keys a seat's own code names its subject by; the SQL maps each to one kind (fn_pool_kind). */
export const POOL_SUBJECT_KEYS = ['supplier_id', 'lead_id', 'customer_id', 'inquiry_id', 'request_id', 'rfq_id', 'quote_id',
  'transaction_id', 'tx_id', 'refund_id', 'issue_key', 'case_ref'] as const;
export const POOL_HEADER = 'SHARED POOL (what every seat did; internal, never quoted to a customer or supplier):';
/** fn_seat_pool_context's p_budget: the header and a newline fit beside it inside POOL_MAX_CHARS. */
export const SQL_BUDGET = 1200;

export interface Pool { block: string; chars: number }

/** The subject keys found in the given objects (shallow), plus {table, id}. null when none names one. */
export function poolSubject(...sources: unknown[]): Record<string, string> | null {
  const out: Record<string, string> = {};
  for (const s of sources) {
    if (!s || typeof s !== 'object' || Array.isArray(s)) continue;
    const o = s as Record<string, unknown>;
    for (const k of POOL_SUBJECT_KEYS) {
      const v = o[k];
      if ((typeof v === 'string' && v.trim()) || typeof v === 'number') out[k] ??= String(v).trim();
    }
    const table = o.table ?? o.subject_table; const id = o.id ?? o.subject_id;
    if (typeof table === 'string' && table && (typeof id === 'string' || typeof id === 'number') && String(id).trim() && !out.table) {
      out.table = table; out.id = String(id).trim();
    }
    if (Object.keys(out).length >= 6) break;
  }
  return Object.keys(out).length ? out : null;
}

/** The pool block for this seat. '' when there is nothing to say or the database did not answer in time. */
export async function seatPool(deps: Rpc, seat: string, subject: Record<string, string> | null,
  audience: 'internal' | 'customer' | 'supplier' | 'visitor' | 'founder'): Promise<Pool> {
  // the founder reads as an insider; a customer, supplier or visitor reads only a subject's kinds and states
  const aud = audience === 'founder' ? 'internal' : audience;
  if (aud !== 'internal' && !subject) return { block: '', chars: 0 };
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const call = Promise.resolve(deps.rpc('fn_seat_pool_context', { p_seat: seat, p_subject: subject, p_audience: aud, p_budget: SQL_BUDGET }));
    const late = new Promise<null>((res) => { timer = setTimeout(() => res(null), POOL_TIMEOUT_MS); });
    const r = await Promise.race([call, late]);
    if (!r || r.error || !r.data || typeof r.data !== 'object') return { block: '', chars: 0 };
    const raw = String((r.data as Record<string, unknown>).block ?? '').trim();
    if (!raw) return { block: '', chars: 0 };
    // never cut here: the SQL already ordered and fitted it; a block over its budget is refused whole, not truncated
    if (raw.length > SQL_BUDGET) return { block: '', chars: 0 };
    const block = POOL_HEADER + '\n' + raw;
    return { block, chars: block.length };
  } catch (_e) {
    return { block: '', chars: 0 };
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}
