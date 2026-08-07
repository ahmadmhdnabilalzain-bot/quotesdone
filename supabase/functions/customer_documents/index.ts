// customer_documents — SPEC §14, the Document Intelligence Vault as the CUSTOMER reaches it.
//
// MEASURED BEFORE THIS FUNCTION EXISTED (production, 6 Aug 2026): public.documents had RLS enabled
// with ZERO policies and no SELECT grant to `authenticated`, and no customer-authed edge function
// read the table. The vault had no access path at all.
//
// THE SCOPING IS THE DATABASE'S, NOT THIS FILE'S. Every read of a customer's own documents below
// goes through a client carrying the CUSTOMER'S OWN JWT, so PostgREST applies the
// documents_customer_select policy and fn_customer_document_refs() decides what exists. There is
// deliberately no `customer_id` filter written in TypeScript here: a second copy of an ownership
// rule is a second place for it to be wrong, and this one could only ever be the WIDER of the two.
// The service-role client is used for exactly two things that RLS cannot do — signing a storage URL
// for a row the user-scoped read already returned, and the unscoped fn_memory_search call whose
// results are then intersected against the caller's own refs before they are used.
//
// NOTHING IS INVENTED. expiry_date / covers are null unless a field that MEANS expiry or coverage
// carried them, and expiry_source / covers_source name where each came from. A supplier NAME is
// null until the customer has paid to reveal that quote — the same rule customer_api enforces on
// every other pre-reveal surface. Empty vault returns an empty list and says why; it never claims
// documents were found.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY') || '';
const admin = createClient(SUPABASE_URL, SERVICE);

const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

type Doc = {
  id: number; kind: string; file_name: string | null; bucket: string; path: string;
  mime: string | null; status: string; created_at: string; source: string;
  ref_table: string | null; ref_id: string | null;
  supplier: string | null; supplier_revealed: boolean;
  expiry_date: string | null; expiry_source: string | null;
  covers: string | null; covers_source: string | null;
  summary: string | null; specifications: string[]; certifications: string[]; brands: string[];
  extracted_at: string | null; match_reason: string; score: number;
};

// The row the surface renders. Everything a customer is allowed to know about one document, and
// nothing that would name an unrevealed supplier.
function shape(d: Doc) {
  return {
    id: d.id,
    kind: d.kind,
    file_name: d.file_name,
    mime: d.mime,
    created_at: d.created_at,
    // where it came from, in the customer's own vocabulary
    source: d.source,                       // 'inquiry' | 'quote' | 'supplier'
    ref_table: d.ref_table,
    ref_id: d.ref_id,
    supplier: d.supplier,                   // null until this quote's reveal fee is paid
    supplier_revealed: d.supplier_revealed,
    expiry_date: d.expiry_date,             // null when the document does not state one
    expiry_source: d.expiry_source,
    covers: d.covers,
    covers_source: d.covers_source,
    summary: d.summary,
    specifications: d.specifications || [],
    certifications: d.certifications || [],
    brands: d.brands || [],
    extracted: d.status === 'done' && !!d.extracted_at,
    extraction_status: d.status,
    match_reason: d.match_reason,
    score: d.score,
  };
}

// One line of plain English for the answer panel. It states only what the row actually carries —
// a missing expiry is reported as missing, never rounded to a year.
function answerLine(d: ReturnType<typeof shape>): string {
  const bits: string[] = [];
  bits.push(`${d.file_name || d.kind}`);
  bits.push(d.supplier ? `from ${d.supplier}` : (d.source === 'quote' ? 'from a supplier you have not revealed yet' : 'your own upload'));
  bits.push(d.expiry_date ? `expires ${d.expiry_date}` : 'no expiry stated on the document');
  bits.push(d.covers ? `covers ${d.covers}` : 'no coverage stated on the document');
  return bits.join(' · ');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    // FAIL CLOSED, AND FAIL FIRST. Without the anon key there is no way to reach PostgREST AS THE
    // CUSTOMER, and the only other client here holds the service role, which bypasses RLS entirely.
    // Falling back to it would turn a missing environment variable into a vault that shows every
    // customer everything. It is checked BEFORE the sign-in check so the answer is observable on a
    // project with zero customers: an unauthenticated request returning 401 rather than 503 is the
    // proof that this deployment has the key. Production has zero customers, so there is no other
    // way to measure it without inventing one.
    if (!ANON) return J({ error: 'documents_unavailable', detail: 'SUPABASE_ANON_KEY is not set on this deployment, so this function cannot read as the signed-in customer. Refusing to read with the service role.' }, 503);

    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const email = user.email.toLowerCase();
    // The customers row is what makes this a CUSTOMER surface. It is not created here: a person
    // with an auth identity but no customer record has an empty vault, and is told that plainly
    // rather than having a row written for them by a read endpoint.
    const { data: cust } = await admin.from('customers').select('id,email,banned').eq('email', email).maybeSingle();

    const asUser = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const action = String((body as Record<string, unknown>).action || 'list');
    const kind = String((body as Record<string, unknown>).kind || '').trim() || null;
    const limit = Math.min(200, Math.max(1, Number((body as Record<string, unknown>).limit) || 50));

    if (!cust) {
      return J({ ok: true, action, documents: [], count: 0, answer: null,
        empty_reason: 'no_customer_record',
        note: 'This sign-in has no customer account on QuotesDone yet, so there are no documents to show.' });
    }

    // ---- LIST: the whole vault, newest first --------------------------------------------------
    // 'documents' is the name the rest of the estate uses for this request and is what the portal
    // sends; 'list' is kept because it is what shipped first and a client in the wild may still
    // send it. Two spellings, one branch — never two branches that can drift apart.
    if (action === 'list' || action === 'documents' || action === 'my_documents' || action === 'vault') {
      const { data, error } = await asUser.rpc('fn_customer_documents', { p_q: null, p_kind: kind, p_lim: limit });
      if (error) return J({ error: 'documents_read_failed', detail: error.message }, 500);
      const rows = ((data || []) as Doc[]).map(shape);
      return J({ ok: true, action, documents: rows, count: rows.length,
        kinds: [...new Set(rows.map((r) => r.kind))].sort(),
        empty_reason: rows.length ? null : (kind ? 'no_documents_of_this_kind' : 'no_documents'),
        note: rows.length ? null : 'Nothing has been filed to your vault yet. Documents appear here when you attach a drawing to a request, when a supplier sends a quotation file, and — once you reveal a supplier — their trade licence and certificates.' });
    }

    // ---- ASK: "Find warranty documents for HVAC" ----------------------------------------------
    // Two recall paths, both ranked, both ownership-scoped:
    //   1. the extraction itself — doc_extract's text, specifications, certifications and brands,
    //      full-text ranked inside fn_customer_documents. A filename LIKE would miss every one of
    //      these, because the filenames in this table look like 1784642800192_catalogue-....pdf.
    //   2. fn_memory_search over the customer's own RFQs and quotes, so a document attached to
    //      their HVAC request surfaces even when the document's own text never says HVAC.
    // fn_memory_search is SECURITY DEFINER and unscoped — it ranks EVERY customer's rfqs. Its
    // output is therefore treated as a list of candidate refs and INTERSECTED with the refs this
    // caller owns before a single one of them is used.
    if (action === 'ask' || action === 'search') {
      const q = String((body as Record<string, unknown>).q || (body as Record<string, unknown>).query || '').trim().slice(0, 300);
      if (!q) return J({ error: 'Ask a question, for example: Find warranty documents for HVAC' }, 400);

      const { data: owned } = await asUser.rpc('fn_customer_document_refs');
      const ownedRefs = new Set(((owned || []) as { ref_table: string; ref_id: string }[]).map((r) => `${r.ref_table}:${r.ref_id}`));
      // fn_memory_search builds its tsquery with plainto_tsquery, which ANDs every content word.
      // Asked the spec's own question it therefore requires find & warranti & document & hvac and
      // returns nothing — measured on staging. It is not this agent's function to change, so the
      // phrase is also asked one significant word at a time and the answers are unioned. Each
      // result is still only a CANDIDATE ref until ownedRefs accepts it.
      const terms = [q, ...new Set(q.toLowerCase().split(/[^a-z0-9]+/i).filter((w) => w.length >= 3))].slice(0, 7);
      let related: string[] = [];
      try {
        const answers = await Promise.all(terms.map((term) =>
          admin.rpc('fn_memory_search', { p_q: term, p_kinds: ['rfq', 'quote'], p_lim: 20 })
            .then((r) => (r.data || []) as { kind: string; ref: string }[])
            .catch(() => [] as { kind: string; ref: string }[])));
        related = [...new Set(answers.flat()
          .map((m) => (m.kind === 'rfq' ? `inquiries:${m.ref}` : `quotes:${m.ref}`))
          .filter((r) => ownedRefs.has(r)))];
      } catch (_e) { /* NL widening is additive; the extraction search below stands on its own */ }

      const { data, error } = await asUser.rpc('fn_customer_documents',
        { p_q: q, p_kind: kind, p_lim: limit, p_related_refs: related });
      if (error) return J({ error: 'documents_search_failed', detail: error.message }, 500);
      const rows = ((data || []) as Doc[]).map(shape);
      return J({
        ok: true, action: 'ask', q,
        documents: rows,
        count: rows.length,
        answer: rows.length ? rows.slice(0, 3).map(answerLine) : null,
        matched_by: { extraction_text: rows.filter((r) => r.match_reason === 'text').length,
                      related_request: rows.filter((r) => r.match_reason === 'related_request').length },
        searched: { owned_refs: ownedRefs.size, related_requests_matched: related.length },
        empty_reason: rows.length ? null : 'no_match',
        note: rows.length ? null : `Nothing in your vault matches “${q}”. Only your own documents are searched — your uploads, the quotation files sent to your requests, and the licences and certificates of suppliers you have revealed.`,
      });
    }

    // ---- GET: one document, with a signed link --------------------------------------------------
    // The read goes through the customer's own JWT, so the RLS policy is the authorisation. The
    // service role only signs a URL for a row that read already returned.
    if (action === 'get' || action === 'download') {
      const id = Number((body as Record<string, unknown>).id || 0);
      if (!id) return J({ error: 'id is required' }, 400);
      const { data: row, error } = await asUser.from('documents')
        .select('id,bucket,path,file_name,kind,mime,status,extracted,indexed,created_at,processed_at,ref_table,ref_id')
        .eq('id', id).maybeSingle();
      if (error) return J({ error: 'document_read_failed', detail: error.message }, 500);
      if (!row) return J({ error: 'not_found', detail: 'No document with that id is in your vault.' }, 404);

      // the metadata view of the same row, so supplier / expiry / coverage come from one place
      const { data: meta } = await asUser.rpc('fn_customer_documents', { p_q: null, p_kind: null, p_lim: 200 });
      const m = ((meta || []) as Doc[]).find((d) => Number(d.id) === id) || null;

      let url: string | null = null;
      try {
        const { data: sig } = await admin.storage.from(row.bucket).createSignedUrl(row.path, 3600);
        url = sig?.signedUrl || null;
      } catch (_e) { url = null; }

      return J({ ok: true, action: 'get',
        document: m ? { ...shape(m), file_url: url, extracted: row.extracted ?? null, indexed: row.indexed ?? false }
                    : { id: row.id, kind: row.kind, file_name: row.file_name, mime: row.mime,
                        created_at: row.created_at, extraction_status: row.status,
                        supplier: null, supplier_revealed: false,
                        expiry_date: null, expiry_source: null, covers: null, covers_source: null,
                        file_url: url, extracted: row.extracted ?? null, indexed: row.indexed ?? false },
        file_url_expires_in: url ? 3600 : null,
        note: url ? null : 'The file could not be signed for download right now; its metadata is shown above.' });
    }

    return J({ error: 'unknown_action', detail: 'Supported actions: documents (alias: list, my_documents, vault), ask, search, get, download.' }, 400);
  } catch (e) {
    return J({ error: 'exception', detail: String((e as Error)?.message || e) }, 500);
  }
});
