// The three customer-authed endpoints this module reads. Errors are RETURNED, never thrown and
// never swallowed — a swallowed error is how a surface ends up showing an encouraging empty state
// over a failure, which is the defect this whole portal is being repaired for.
//
// All three already exist and are already customer-authed; nothing here is a new server contract.
//   project_api        detail  -> the project and its linked RFQs
//   procurement_api    orders  -> this customer's po_orders, via fn_customer_orders
//   customer_documents list    -> this customer's vault, RLS-scoped at PostgREST
import { SUPA_ANON, fnUrl } from '@/lib/supaEnv';
import type { CustomerOrder, SpatialProject, SpatialRfq, VaultDoc } from './model';

export type ApiResult<T> = { ok: true; data: T } | { ok: false; error: string };

/**
 * The endpoints this module reaches, written out in full rather than assembled from a variable.
 * "What can a customer actually reach from this page?" is a question this repo has had to answer
 * by hand more than once, and a URL built as `${BASE}/${name}` cannot be grepped for. Three names,
 * three lines, and an audit can read them.
 */
const ENDPOINT = {
  project_api: fnUrl('project_api'),
  procurement_api: fnUrl('procurement_api'),
  customer_documents: fnUrl('customer_documents'),
} as const;

async function post<T>(url: string, token: string, body: Record<string, unknown>): Promise<ApiResult<T>> {
  try {
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token || SUPA_ANON}` },
      body: JSON.stringify(body),
    });
    const json = (await r.json().catch(() => null)) as Record<string, unknown> | null;
    if (!json) return { ok: false, error: 'no_response' };
    if (typeof json.error === 'string') return { ok: false, error: json.error };
    if (!r.ok) return { ok: false, error: `http_${r.status}` };
    return { ok: true, data: json as T };
  } catch (e) {
    return { ok: false, error: (e as Error)?.message || 'network_error' };
  }
}

export const fetchProjectList = (token: string) =>
  post<{ projects: Array<{ project_id: string; name: string; status: string; rfq_count: number }> }>(
    ENDPOINT.project_api, token, { action: 'list' });

export const fetchProjectDetail = (token: string, project_id: string) =>
  // project_api detail reads body.id (index.ts, `const id = String(body.id || '')`). This sent
  // `project_id`, so every Project room load was answered 400 "id required" and never rendered.
  post<{ project: SpatialProject; rfqs: SpatialRfq[] }>(ENDPOINT.project_api, token, { action: 'detail', id: project_id });

/**
 * The customer's orders. Every order, not just this project's: the chain map shows the whole
 * account, and ProjectRoom filters by inquiry_id itself. `orders` is [] for a customer with none —
 * an honest empty state the endpoint already returns, so nothing here has to invent one.
 */
export const fetchOrders = (token: string) =>
  post<{ orders: CustomerOrder[] }>(ENDPOINT.procurement_api, token, { action: 'orders' });

/**
 * The vault. This module uses it for ONE thing — the documents filed against a package's own RFQ,
 * matched on (ref_table, ref_id) in ./model.ts#docsForRfq. `empty_reason` and `note` are typed
 * because the response carries them, but the vault-level empty state belongs to the Documents
 * module; here an RFQ with no documents says exactly that and nothing wider.
 */
export const fetchDocuments = (token: string) =>
  post<{ documents: VaultDoc[]; count: number; empty_reason: string | null; note: string | null }>(
    ENDPOINT.customer_documents, token, { action: 'list', limit: 200 });
