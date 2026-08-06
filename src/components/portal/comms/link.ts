// SPEC §16 — "Everything attached to: project, RFQ, supplier".
//
// This module decides WHICH DOCUMENTS BELONG TO WHICH CONVERSATION, and it is a separate file from
// the component for one reason: the rule is the only place in the Communication Center where a
// wrong answer would be invisible. Attaching a supplier's trade licence to the wrong conversation
// looks exactly like attaching it to the right one. So the rule is pure, imports nothing, and is
// exercised directly by link.test.mjs without a bundler or a test framework.
//
// WHAT THE TWO PAYLOADS ACTUALLY CARRY
//   messages_api action:'threads' -> { inquiry_id, supplier_id, counterpart, subject, ... }
//   customer_documents action:'list' -> { ref_table, ref_id, source, ... }
// and public.documents holds exactly three ref_table values in production: inquiries, quotes, leads.
//
// THE THREE CASES, AND WHY THE THIRD IS NOT GUESSED
//   ref_table 'inquiries' -> ref_id IS the inquiry id. Matches a thread on inquiry_id. Certain.
//   ref_table 'leads'     -> ref_id IS the supplier id. Matches a thread on supplier_id. Certain.
//   ref_table 'quotes'    -> ref_id is the QUOTE id, and neither payload maps a quote back to the
//                            RFQ it answers. A quotation file therefore CANNOT be attached to a
//                            conversation from what the endpoints return.
//
// The obvious temptation is to match a quote document to a thread by comparing `doc.supplier` to
// `thread.counterpart` — both are the supplier's company name once the reveal is paid. It is
// rejected on purpose: one supplier can quote several of a customer's RFQs, so that comparison
// would file supplier X's quotation for the villa under the conversation about the warehouse, with
// nothing on screen to show it was a guess. Unlinkable rows are RETURNED as unlinkable and the
// surface says so. Closing this properly is a backend change (a quote -> inquiry link in the
// document payload), not a heuristic here.

/** The fields of a messages_api thread this module uses. */
export interface LinkableThread {
  inquiry_id: string;
  supplier_id: number | string;
}

/** The fields of a customer_documents row this module uses. */
export interface LinkableDoc {
  id: number;
  ref_table: string | null;
  ref_id: string | null;
}

/** Documents attached to one conversation, kept apart by WHAT they are attached to. */
export interface ThreadDocuments<D> {
  /** Filed against the RFQ this conversation is about. */
  rfq: D[];
  /** Belonging to the supplier on the other side of it. */
  supplier: D[];
}

export interface LinkResult<D> {
  byThread: Record<string, ThreadDocuments<D>>;
  /** Vault rows no conversation can claim — see the header for why quote files land here. */
  unlinkable: D[];
}

/** The key both surfaces use for a conversation. Same shape CustomerPortal already keys rows by. */
export const threadKey = (t: LinkableThread): string => `${t.inquiry_id}:${t.supplier_id}`;

/**
 * Attach each document to every conversation that PROVABLY owns it.
 *
 * A document can legitimately reach more than one conversation — a supplier's trade licence belongs
 * to every conversation with that supplier — so this is not a partition and rows are not consumed.
 * `unlinkable` holds the rows no thread could claim, and it is a fact to display, not a leftover to
 * drop: silently discarding them is how a "unified" inbox quietly stops being unified.
 */
export function linkDocuments<T extends LinkableThread, D extends LinkableDoc>(
  threads: T[], docs: D[],
): LinkResult<D> {
  const byThread: Record<string, ThreadDocuments<D>> = {};
  for (const t of threads || []) byThread[threadKey(t)] = { rfq: [], supplier: [] };

  const claimed = new Set<number>();
  for (const d of docs || []) {
    for (const t of threads || []) {
      const bucket = byThread[threadKey(t)];
      if (!bucket) continue;
      if (d.ref_table === 'inquiries' && d.ref_id != null && String(d.ref_id) === String(t.inquiry_id)) {
        bucket.rfq.push(d); claimed.add(d.id);
      } else if (d.ref_table === 'leads' && d.ref_id != null && String(d.ref_id) === String(t.supplier_id)) {
        bucket.supplier.push(d); claimed.add(d.id);
      }
    }
  }

  return { byThread, unlinkable: (docs || []).filter((d) => !claimed.has(d.id)) };
}

/** How many documents one conversation carries, for the count on its row. */
export function documentCount<D>(td: ThreadDocuments<D> | undefined): number {
  return td ? td.rfq.length + td.supplier.length : 0;
}
