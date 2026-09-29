// SPEC §14 Document Intelligence Vault — the typed client for supabase/functions/customer_documents.
//
// EVERY FIELD BELOW IS TRANSCRIBED FROM THAT FUNCTION'S OWN `shape()`. Nothing is invented, and a
// field that is not here is a field the endpoint does not serve. The three the spec names —
// supplier, expiry, coverage — are `supplier`, `expiry_date` and `covers`, and all three are
// NULLABLE ON PURPOSE: the endpoint returns null when the document does not state one rather than
// guessing, and `expiry_source` / `covers_source` name where a non-null value came from. The
// surface must render the null as "not stated", never round it to a year.
//
// `supplier` is null until the customer has paid to reveal that quote — the same rule customer_api
// enforces everywhere else. `supplier_revealed` distinguishes "not revealed yet" from "the document
// names no supplier", which read identically if you only look at `supplier`.
//
// Three actions exist: 'list', 'search' (aliased 'ask' server-side) and 'get' (aliased 'download').
// Anything else is answered with HTTP 400 unknown_action.
import { SUPA_ANON, fnUrl } from '@/lib/supaEnv';

export type Lang = 'en' | 'ar';

/** Where a document entered the vault. customer_documents derives it from documents.ref_table. */
export type VaultSource = 'inquiry' | 'quote' | 'supplier';

/** Why a row came back from a search. 'text' = the extraction matched; 'related_request' = the
 *  document hangs off an RFQ or quote whose own text matched. 'listed' on a plain list. */
export type MatchReason = 'text' | 'related_request' | 'listed' | string;

/** One row of the vault — exactly what customer_documents' `shape()` returns. */
export interface VaultDocument {
  id: number;
  kind: string;
  file_name: string | null;
  mime: string | null;
  created_at: string;
  source: VaultSource;
  ref_table: string | null;
  ref_id: string | null;
  /** null until this quote's reveal fee is paid — see supplier_revealed before phrasing it. */
  supplier: string | null;
  supplier_revealed: boolean;
  /** null when the document itself states no expiry. NEVER substitute a default. */
  expiry_date: string | null;
  expiry_source: string | null;
  /** null when the document itself states no coverage. */
  covers: string | null;
  covers_source: string | null;
  summary: string | null;
  specifications: string[];
  certifications: string[];
  brands: string[];
  extracted: boolean;
  extraction_status: string;
  match_reason: MatchReason;
  score: number;
  /** Only on action:'get' — a storage URL signed for file_url_expires_in seconds. */
  file_url?: string | null;
  indexed?: boolean;
}

/** Why the list came back empty. The endpoint always says which; the surface must print it. */
export type EmptyReason =
  | 'no_customer_record'
  | 'no_documents'
  | 'no_documents_of_this_kind'
  | 'no_match'
  | null;

export interface VaultListResponse {
  ok: true;
  action: string;
  documents: VaultDocument[];
  count: number;
  /** Distinct kinds present in THIS response — the vault's real taxonomy, not a hard-coded six. */
  kinds?: string[];
  answer?: string[] | null;
  empty_reason: EmptyReason;
  note: string | null;
}

export interface VaultSearchResponse extends VaultListResponse {
  q: string;
  /** How many rows each recall path produced. Printed so a thin answer is legible, not mysterious. */
  matched_by?: { extraction_text: number; related_request: number };
  searched?: { owned_refs: number; related_requests_matched: number };
}

export interface VaultGetResponse {
  ok: true;
  action: 'get';
  document: VaultDocument;
  file_url_expires_in: number | null;
  note: string | null;
}

export type VaultResult<T> =
  | { ok: true; data: T }
  | { ok: false; error: string; detail?: string };

/**
 * One POST to customer_documents.
 *
 * Errors are RETURNED, never thrown, so every caller is forced to render them. A swallowed error is
 * how a vault ends up showing "nothing filed yet" over a 500 — which is the exact defect this
 * portal has already shipped once, in a different empty state. `error` is passed through verbatim
 * ('documents_unavailable', 'Not signed in', 'documents_read_failed'…) together with the endpoint's
 * own `detail`, because the endpoint's sentence is more accurate than any we could invent here.
 */
export async function documentsApi<T>(token: string, body: Record<string, unknown>): Promise<VaultResult<T>> {
  try {
    const r = await fetch(fnUrl('customer_documents'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token || SUPA_ANON}` },
      body: JSON.stringify(body),
    });
    const json = (await r.json().catch(() => null)) as Record<string, unknown> | null;
    if (!json) return { ok: false, error: 'no_response' };
    if (typeof json.error === 'string') {
      return { ok: false, error: json.error, detail: typeof json.detail === 'string' ? json.detail : undefined };
    }
    if (!r.ok) return { ok: false, error: `http_${r.status}` };
    return { ok: true, data: json as T };
  } catch (e) {
    return { ok: false, error: (e as Error)?.message || 'network_error' };
  }
}

/** The whole vault, newest first. `kind` filters server-side; omit it for everything. */
export const listDocuments = (token: string, kind?: string | null, limit = 100) =>
  documentsApi<VaultListResponse>(token, { action: 'documents', kind: kind || null, limit });

/**
 * The natural-language question — spec §14's own example is "Find warranty documents for HVAC".
 *
 * 'search' and 'ask' are the same handler. It ranks the EXTRACTION (doc_extract's text,
 * specifications, certifications and brands) rather than the filename, which matters because the
 * filenames in this table look like 1784642800192_catalogue-….pdf and a LIKE would match none of
 * them, and it widens the recall through the customer's OWN RFQs and quotes.
 */
export const askDocuments = (token: string, q: string, kind?: string | null, limit = 50, lang: Lang = 'en') =>
  documentsApi<VaultSearchResponse>(token, { action: 'search', q, kind: kind || null, limit, lang });

/** One document plus a signed download URL, valid for file_url_expires_in seconds. */
export const getDocument = (token: string, id: number) =>
  documentsApi<VaultGetResponse>(token, { action: 'get', id });
