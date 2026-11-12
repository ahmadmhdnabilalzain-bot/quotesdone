// WHAT A SUPPLIER'S DOCUMENTS ARE READ WITH: THE MODEL, NOTHING ELSE. Seat: customer_support. 11 Nov 2026, founder ruling 1627.
//
// Founder, 11 Nov 2026: "We can't rely on the trade license for the services that the supplier will do. That's why the agent who
// is reading, he's having an LLM, is reading the documents, because he needs to be smart and understand from that document what
// services is done. It's not word matching only ... when a human reads that, he will understand what services they will do. It's
// not like he will do control find and search for a word and then assume it's just the service that he will do."
//
// WHAT WAS HERE, AND WHY IT IS GONE. Until today this module proposed a supplier's trades by code: a line that IS a trade code
// (fn_norm_trades), an Arabic clause holding a trade's Arabic name, a licence activity's subject, and gte-small MEANING over the
// stored service vectors confirmed by one head word (service_meaning.proposeByMeaning). The paid registration certification of
// 11 Nov 2026 showed what that does: "...with our own team and equipment" proposed Recording studio equipment to an MEP
// contractor, a joiner, an HVAC firm and a bus company; "doors, frames" proposed spectacle frames. #1934 then limited services to
// trades found that same way or named on the licence, which ruling 1627 rejects. Every code proposal path is deleted, not kept as
// a second path: supplier_doc_trades.readTogether gives ALL the supplier's documents to the model, which names the trades and the
// services the company does with the line it understood each from; code only checks the keys and the quotes. Since 12 Nov 2026
// (ruling 1647) that reading is two steps, read first and mapped second (supplier_profile_reading.ts); the one-call chooser is deleted.
// Prevented by: supabase/functions/_shared/the_model_reads_the_suppliers_documents_together.test.ts
import { liveProfileReader, type ProfileReader } from './supplier_profile_reading.ts';

/** A trade the documents were understood to name: the model's choice, proven by a line of the documents. */
export type TradeHit = {
  code: string;
  via: 'model_choice';
  /** the model's reason */
  phrases: string[];
  /** the line of the documents it was understood from */
  snippet: string;
};

/** What reading a supplier's documents needs: the model. Absent, nothing is proposed and the documents say why. */
/** `readProfile`: the two-step reading (supplier_profile_reading.ts, reader @5). */
export type TradeResolveDeps = { readProfile?: ProfileReader };

/** The deps an edge function builds: the model, through ai_gateway (supplier_profile_reading.liveProfileReader). The model's route is
 *  model_policy 'supplier_trade_choice'; `_caller` is kept for the callers that name themselves. */
// deno-lint-ignore no-explicit-any
export async function liveTradeDeps(admin: any, _caller = 'supplier_doc_trades', choice: { subject?: unknown; headers?: Record<string, string> } = {}): Promise<TradeResolveDeps> {
  return { readProfile: liveProfileReader(admin, choice) };
}
