// THE WIDGET'S RATE LIMITS IN ONE ROUND TRIP (it_engineer, 11 Nov 2026, load test round 2, founder ruling 1622).
//
// Measured on production, 11 Nov 2026 02:42-02:46 UTC (main 2bd2fa971, after #1923): at 50 concurrent website chats one
// site_assistant worker was killed at cpu_time_used 2,003 ms with 17 of the 18 turns it held (HTTP 546). The CPU budget is
// enforced on the WORKER's total (supabase.com/docs/guides/functions/limits says "per request"; the logs show one kill
// ending 18 requests whose mean was ~111 ms), and a worker that the router fills with turns in its first seconds runs out.
// Per-turn CPU barely fell in production (124-210 ms a turn against 145-215 before #1923). Locally, after #1923, switching
// off the person check, the recall and the trade retrieval together saved only ~30% of a young worker's turn; what is
// left is spread across the ~23 calls a turn makes (client code, JSON, runtime I/O) and the code they warm up. The edge
// log of that run counted 727 rl_check calls for ~133 turns: every widget turn spent four to six limiter buckets one
// call at a time, each its own HTTPS round trip and PostgREST transaction.
//
// prefetchLimits asks public.fn_rl_check_chain (scripts/sql/the_widget_spends_its_rate_limits_in_one_round_trip.sql)
// for the whole chain at once: groups in order, every bucket of a group spent, and no later group spent once a group
// refused, exactly the order and the short-circuits the code below it already follows. hitFrom then answers each
// rl() question index.ts asks from that one result, so index.ts and visitor_scope.pastVisitorCap are unchanged. A
// bucket the chain did not spend (or a chain that failed, or a database without the function yet) is spent the old way,
// one call, so the turn's counting never changes and this deploys safely before the SQL is applied.
// prevented by: site_assistant/limit_chain.test.ts

export type Step = { k: string; l: number; s: number };
// deno-lint-ignore no-explicit-any
type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: any; error: any }>;
export type Hit = (key: string, limit: number, seconds: number) => Promise<boolean>;

/** How long a database without fn_rl_check_chain is not asked again (it is applied at merge). */
export const CHAIN_RETRY_MS = 5 * 60_000;
let missingUntil = 0;
/** For tests. */
export function _resetChainForTest(): void { missingUntil = 0; }

const missing = (e: { code?: string; message?: string } | null | undefined) =>
  !!e && (e.code === 'PGRST202' || e.code === '42883' || /fn_rl_check_chain/.test(String(e.message ?? '')) && /not find|does not exist/i.test(String(e.message ?? '')));

/** The chain's answers by key ('true'/'false' spent, absent = not spent), or null when the chain could not be asked. */
export async function prefetchLimits(rpc: Rpc, groups: Step[][], now = Date.now()): Promise<Map<string, boolean> | null> {
  const gs = groups.filter((g) => g.length);
  if (!gs.length || now < missingUntil) return null;
  try {
    const { data, error } = await rpc('fn_rl_check_chain', { p_groups: gs });
    if (error) { if (missing(error)) missingUntil = now + CHAIN_RETRY_MS; return null; }
    if (!Array.isArray(data) || data.length !== gs.length) return null;
    const out = new Map<string, boolean>();
    gs.forEach((g, i) => g.forEach((s, j) => { const v = Array.isArray(data[i]) ? data[i][j] : null; if (v === true || v === false) out.set(s.k, v); }));
    return out;
  } catch (_e) { return null; }
}

/** rl() answered from the chain where it spent the bucket, the old one-call path for anything else. */
export function hitFrom(pre: Map<string, boolean> | null, rl: Hit): Hit {
  return (key, limit, seconds) => (pre && pre.has(key) ? Promise.resolve(pre.get(key)!) : rl(key, limit, seconds));
}

/** The chain a widget turn spends, in the order index.ts asks for it (the reference the test holds the SQL to). */
export function widgetChain(o: { who: boolean; hasConv: boolean; firstTurn: boolean; ip: string; conv: string; rlKey: string; rlLimit: number;
  ipLimit: number; ipHardLimit: number; globalKey: string; dayLimit: number; capConv: number; capIp: number }): Step[][] {
  const rate: Step[][] = o.hasConv
    ? [[{ k: 'site_assistant_ip_hard:' + o.ip, l: o.ipHardLimit, s: 3600 }],
       [...(o.firstTurn ? [{ k: 'site_assistant_ipconv:' + o.ip, l: o.ipLimit, s: 3600 }] : []), { k: o.rlKey, l: o.rlLimit, s: 3600 }]]
    : [[{ k: o.rlKey, l: o.rlLimit, s: 3600 }]];
  const global: Step[][] = [[{ k: o.globalKey, l: o.dayLimit, s: 86400 }]];
  // visitor_scope.pastVisitorCap: the conversation first, the IP only when the conversation is within its cap
  const cap: Step[][] = o.who ? [] : [...(o.conv ? [[{ k: 'site_assistant_visitor_conv_day:' + o.conv, l: o.capConv, s: 86400 }]] : []),
    [{ k: 'site_assistant_visitor_ip_day:' + o.ip, l: o.capIp, s: 86400 }]];
  return [...rate, ...global, ...cap];
}

// WHICH BUCKET REFUSED (it_engineer, 11 Nov 2026, load test round 3). The 03:46 UTC run had 4 widget turns refused (agent_runs
// scope 'ip', 2.2% of 181) from four load users with at most 6 requests each, and nothing recorded WHICH of the three buckets
// behind scope 'ip' refused; the rows were gone with the run's teardown. Every refusal now names its bucket in its agent_runs
// row and in the answer, so the next run (and any real visitor's refusal) says which limit it met.
// prevented by: site_assistant/limit_chain.test.ts
export type Bucket = 'ip_hard' | 'ip_new_conversation' | 'conversation_depth' | 'ip_messages' | 'account' | 'global_day';
export function refusedBucket(o: { who: boolean; hasConv: boolean; hardOk?: boolean; startOk?: boolean; convOk?: boolean; ipOk: boolean; globalOk: boolean }): Bucket | null {
  if (o.ipOk && o.globalOk) return null;
  if (!o.ipOk) {
    if (o.hasConv) return o.hardOk === false ? 'ip_hard' : o.startOk === false ? 'ip_new_conversation' : 'conversation_depth';
    return o.who ? 'account' : 'ip_messages';
  }
  return 'global_day';
}
