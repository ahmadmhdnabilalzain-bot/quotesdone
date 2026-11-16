// THE SERVICE VOCABULARY (22 Sep 2026, agent: sales_engineer).
//
//   serviceVocab(admin)        — the active taxonomy_trade_service rows, with their stored vectors.
//
// One owner for the select: supplier_services.ts (the Services tab), inquiry_intake and the matchers import it from here
// rather than keeping their own copy.
//
// WHAT AN INQUIRY NAMES IS NOT READ HERE ANY MORE (11 Nov 2026, customer_support; founder rulings 1627 and 1628). serviceKeysOf
// read an inquiry's prose for service keys (exact names, then gte-small meaning with one head word) and keysInTrades bounded
// what it read by the request's trades (#1934). Both are DELETED. An inquiry's keys are the ones the intake model named from our
// catalogue when it read the request, or the option the customer chose (inquiry_intake/handle.ts; inquiries.service_keys via
// customer_api lib/state_service_keys.ts); dispatch matches them, in code, against the keys each supplier confirmed
// (fn_match_capability p_services). No keys named is trade level: nobody is dropped for a key nobody named.
import { parseVec, type MeaningService } from './service_meaning.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;

/** EVERY active taxonomy_trade_service row, paged. PostgREST caps one read at max-rows, measured 1,000 on
 *  29 Sep 2026 (an unpaged select answered `0-999/1047`): an unpaged read silently lost 47 services to exact
 *  and meaning matching. The order (trade_code, sort, code) is total, so pages neither skip nor repeat a row;
 *  the loop advances by what each page returned and stops on an empty page, so it holds whatever the cap is.
 *  Any failed page is an error for the whole read — a partial vocabulary is never answered as the vocabulary. */
export async function activeServiceRows<T = Record<string, unknown>>(admin: Admin, columns: string): Promise<{ data: T[]; error: unknown }> {
  const PAGE = 1000, MAX_PAGES = 50; // 50 pages is 50x today's 1,047 rows even at a 1,000-row cap
  const out: T[] = [];
  for (let from = 0, pages = 0; pages < MAX_PAGES; pages++) {
    const { data, error } = await admin.from('taxonomy_trade_service').select(columns).eq('active', true)
      .order('trade_code').order('sort').order('code').range(from, from + PAGE - 1);
    if (error) return { data: [], error };
    if (!data?.length) return { data: out, error: null };
    out.push(...data);
    from += data.length;
  }
  // A server that ignored .range() would answer the same page for ever; that is a failed read, not a loop.
  return { data: [], error: { message: `taxonomy_trade_service did not end within ${MAX_PAGES} pages` } };
}

/** The service vocabulary: every active service, its names, its aliases and its stored vectors (parseVec).
 *  The multilingual vector (embedding_ml) is read separately so that a database without that column yet (its SQL
 *  is applied at release) still answers everything else. */
export async function serviceVocab(admin: Admin): Promise<MeaningService[]> {
  // The two spaces are two independent reads, asked together (27 Oct 2026: ~1,047 rows each, the slowest part of an
  // intake turn that reached ready, inquiry_intake/turn_clock.ts).
  const [{ data, error }, ml] = await Promise.all([
    activeServiceRows(admin, 'trade_code,code,label_en,label_ar,aliases,embedding_gte'),
    activeServiceRows(admin, 'trade_code,code,embedding_ml'),
  ]);
  if (error) return [];
  const mlOf = new Map<string, number[] | null>((ml.error ? [] : ml.data || [])
    .map((r: Record<string, unknown>) => [`${r.trade_code}.${r.code}`, parseVec(r.embedding_ml)] as [string, number[] | null]));
  return (data || []).map(({ embedding_gte, ...s }: Record<string, unknown>) =>
    ({ ...s, vec: parseVec(embedding_gte), vec_ml: mlOf.get(`${s.trade_code}.${s.code}`) ?? null }) as MeaningService);
}

// tradeLabelVocab, tradeAliasVocab and tradeArNameVocab, the trade-name readers proposeByMeaning and trade_resolve's exact-name
// path took, had no caller left and were removed on 16 Nov 2026 (it_engineer, simplification wave A; ruling 1627).
