// fn_supplier_source_docs_store, for a test's in-memory supplier_capabilities row (12 Nov 2026, customer_support; final audit R1).
// The same compare-and-set the routine does (scripts/sql/two_reads_of_one_suppliers_documents_never_overwrite_each_other.sql):
// the write lands only when the row still has the fingerprint the writer read, and then moves `v`. That the routine computes the
// same fingerprint as sourceDocsFingerprint is held by its probe and two_reads_of_one_supplier_never_overwrite_each_other.test.ts, one literal in both.
import { sourceDocsFingerprint } from './supplier_doc_trades.ts';

type Row = Record<string, unknown> | null | undefined;
export function sourceDocsStoreRpc(row: () => Row, write: (next: Record<string, unknown>) => void) {
  return async (fn: string, a: Record<string, unknown>) => {
    if (fn !== 'fn_supplier_source_docs_store') return { data: null, error: null };
    const cur = (row()?.source_docs ?? {}) as Record<string, unknown>;
    if (JSON.stringify(sourceDocsFingerprint(cur)) !== JSON.stringify(a.p_expect)) return { data: false, error: null };
    write({ source_docs: { ...structuredClone(a.p_source_docs as Record<string, unknown>), v: Number(cur.v ?? 0) + 1 },
      ...(a.p_proposed_trades ? { proposed_trades: a.p_proposed_trades } : {}) });
    return { data: true, error: null };
  };
}
