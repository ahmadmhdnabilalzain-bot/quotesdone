// inquiry_split — posting ONE customer request as a combined parent plus one child per trade,
// all or nothing. Assigned: sales_engineer.
//
// REVIEW OF #653 (14 Sep 2026), the blocker: create_inquiry saved the parent, then for each trade
// saved a child AND immediately matched it and emailed its suppliers. When a later child failed to
// save, the customer was told "sent", the failure was never shown, nothing retried, the parent kept
// listing trades that never went out — and the suppliers of the earlier trades had already been
// invited to a request that was only partly real.
//
// NOW, in this order:
//   1. save the parent, then EVERY child — nothing is matched or sent yet;
//   2. if any child failed: delete the children that were saved and the parent (compensation), and
//      answer split_failed naming the failed trades. The customer is told nothing went out, because
//      nothing did;
//   3. a compensating delete that itself fails is never swallowed: it is reported as a finding with
//      the ids left behind, and the answer says the cleanup failed;
//   4. only when every child exists are they matched and notified.
// The database operations are injected, so inquiry_split.test.ts drives the real orchestration
// through the partial-failure and all-fail paths without a database.

export type SplitOps = {
  insertParent: () => Promise<string | null>;
  insertChild: (trade: string) => Promise<string | null>;
  /** Delete the given inquiry ids; resolves false (or throws) when it did not. */
  deleteInquiries: (ids: string[]) => Promise<boolean>;
  /** Match and notify one saved child; returns the suppliers reached. */
  notifyChild: (childId: string, trade: string) => Promise<number>;
  /** Record a problem nobody may miss (it.finding). Never throws. */
  finding: (detail: Record<string, unknown>) => Promise<void>;
};

export type SplitResult =
  | { ok: true; parentId: string; children: { inquiry_id: string; trade: string; matches: number }[] }
  | { ok: false; error: 'split_failed'; failed_trades: string[]; cleanup_failed?: string[] };

/** `onParent` receives the saved parent's id before any child is inserted (children reference it). */
export async function splitInquiry(trades: string[], ops: SplitOps, onParent: (id: string) => void = () => {}): Promise<SplitResult> {
  const parentId = await ops.insertParent().catch(() => null);
  if (!parentId) return { ok: false, error: 'split_failed', failed_trades: [...trades] };
  onParent(parentId);

  const saved: { id: string; trade: string }[] = [];
  const failed: string[] = [];
  for (const trade of trades) {
    const id = await ops.insertChild(trade).catch(() => null);
    if (id) saved.push({ id, trade }); else failed.push(trade);
  }

  if (failed.length) {
    // Compensation: children first (they reference the parent), then the parent.
    const ids = [...saved.map((s) => s.id), parentId];
    let removed = false;
    try { removed = await ops.deleteInquiries(ids); } catch { removed = false; }
    if (!removed) {
      await ops.finding({ kind: 'split_compensation_failed', parent_id: parentId, left_behind: ids, failed_trades: failed });
      return { ok: false, error: 'split_failed', failed_trades: failed, cleanup_failed: ids };
    }
    return { ok: false, error: 'split_failed', failed_trades: failed };
  }

  const children: { inquiry_id: string; trade: string; matches: number }[] = [];
  for (const s of saved) {
    const matches = await ops.notifyChild(s.id, s.trade).catch(() => 0);
    children.push({ inquiry_id: s.id, trade: s.trade, matches });
  }
  return { ok: true, parentId, children };
}
