// inquiry_intake/knowledge.ts — the trade knowledge block, with its 3 s budget. Moved verbatim from index.ts (9 Nov 2026).
import { kbChunkIsCustomerFacing } from '../_shared/customer_facing_knowledge.ts';
import { admin } from './shared.ts';

// A BUDGET, AND A MISS THAT IS SAID OUT LOUD (22 Sep 2026, it_engineer, CONN-01). kb_query
// seq-scanned 148k rows and cancelled on the statement timeout 379 times in 48 hours; this read
// runs up to twice a turn and its `catch (_e) {}` swallowed every one, so a customer waited up to
// 16 s per turn for knowledge that never arrived and nothing anywhere recorded it. The routine is
// fixed (scripts/sql/kb_query_reads_the_index_instead_of_scanning_every_chunk.sql); this is the
// caller's half — retrieval is an enrichment and a customer never waits more than 3 s for it, and
// when it does not arrive the reason is logged instead of vanishing. Returns the trade's passage block, or null.
export async function kbFor(s: string, text: string): Promise<string | null> {
  const t0 = Date.now();
  // The timer is CLEARED whichever side wins (22 Sep 2026, independent review). Left running, a
  // 3 s timer per call kept the isolate alive after the handler had answered, and a rejected
  // promise nobody is awaiting any more is an unhandled rejection in waiting.
  let budget: ReturnType<typeof setTimeout> | undefined;
  try {
    const chunks = await Promise.race([
      admin.rpc('kb_query', { p_query: text.slice(0, 500), p_category: s, p_limit: 8 })
        .then((r: { data: unknown; error: { message: string } | null }) => { if (r.error) throw new Error(r.error.message); return r.data; }),
      new Promise((_ok, no) => { budget = setTimeout(() => no(new Error('kb_query did not answer within 3s')), 3000); }),
    ]).finally(() => clearTimeout(budget));
    // WITHHELD FROM THE CUSTOMER (founder ruling 1338, 27 Oct 2026, "Withhold from customers."; #1640): a passage the
    // model or an agent wrote (kb_chunks source_kind 'generated' / 'memory') was never read on a source page, and this
    // specialist talks to the customer. kb_query returns source_kind; one shared rule decides, and a row without one is
    // withheld. Eight are asked for so five read sources can still fill the block.
    const items = ((chunks as any[]) || []).filter((c: any) => kbChunkIsCustomerFacing(c?.source_kind)).slice(0, 5).map((c: any) => (c.title ? c.title + ': ' : '') + String(c.snippet || c.content || '').trim()).filter(Boolean);
    if (items.length) return s + ':\n' + items.join('\n\n');
    console.warn('kb_query returned nothing for category', s, 'in', Date.now() - t0, 'ms');
  } catch (e) {
    // Best-effort still, but NAMED: the flat trade brief is used instead, and the reason
    // this turn went without cited field knowledge is in the logs.
    console.error('kb_query miss for category', s, 'after', Date.now() - t0, 'ms:', String((e as Error)?.message || e));
  }
  return null;
}
