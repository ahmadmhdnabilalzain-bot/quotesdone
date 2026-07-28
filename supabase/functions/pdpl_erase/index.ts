// pdpl_erase — completes a PDPL erasure request end-to-end: deletes the user's
// uploaded files from storage (KYC docs, drawings, quote files), then runs the
// DB PII redaction (fn_pdpl_redact). Internal/admin only: __secret gated, and the
// pdpl_requests row must already be status='approved'.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
async function rm(bucket: string, paths: string[]) { const clean = [...new Set(paths.filter((p) => p && typeof p === 'string'))]; if (!clean.length) return 0; try { const { error } = await admin.storage.from(bucket).remove(clean); return error ? 0 : clean.length; } catch { return 0; } }
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    const __exp = await sec('inbound_secret');
    if (!secretOk(__exp) || body.__secret !== __exp) return J({ error: 'forbidden' }, 403);
    const reqId = String(body.request_id || '');
    if (!reqId) return J({ error: 'request_id required' }, 400);
    const { data: pr } = await admin.from('pdpl_requests').select('id,email,status').eq('id', reqId).maybeSingle();
    if (!pr) return J({ error: 'request not found' }, 404);
    if (String(pr.status) !== 'approved') return J({ error: 'request must be approved first (current: ' + pr.status + ')' }, 409);
    const email = String(pr.email || '').toLowerCase();
    if (!email) return J({ error: 'request has no email' }, 400);

    const supDocs: string[] = [], drawings: string[] = [], quoteFiles: string[] = [];
    // supplier (lead) KYC docs
    const { data: lead } = await admin.from('leads').select('id,license_doc_path,company_profile_doc_path,catalog_doc_paths,egr_doc_path,iban_doc_path').eq('email', email).maybeSingle();
    if (lead) {
      for (const p of [lead.license_doc_path, lead.company_profile_doc_path, lead.egr_doc_path, lead.iban_doc_path]) if (p) supDocs.push(String(p));
      if (Array.isArray(lead.catalog_doc_paths)) for (const p of lead.catalog_doc_paths) if (p) supDocs.push(String(p));
      // supplier's uploaded quotation files
      const { data: qs } = await admin.from('quotes').select('original_file_path').eq('supplier_id', lead.id);
      for (const q of qs || []) if (q.original_file_path) quoteFiles.push(String(q.original_file_path));
    }
    // customer drawings (originals + redacted copies)
    const { data: cust } = await admin.from('customers').select('id').eq('email', email).maybeSingle();
    if (cust) {
      const { data: inqs } = await admin.from('inquiries').select('drawing_file_path,drawing_redacted_paths').eq('customer_id', cust.id);
      for (const i of inqs || []) { if (i.drawing_file_path) drawings.push(String(i.drawing_file_path)); if (Array.isArray(i.drawing_redacted_paths)) for (const p of i.drawing_redacted_paths) if (p) drawings.push(String(p)); }
    }
    const removed = { 'supplier-docs': await rm('supplier-docs', supDocs), 'drawing-files': await rm('drawing-files', drawings), 'quote-files': await rm('quote-files', quoteFiles) };

    // DB PII redaction (also flips request to completed + logs security_event)
    const { data: red, error: rerr } = await admin.rpc('fn_pdpl_redact', { p_request_id: reqId });
    if (rerr) return J({ ok: false, error: rerr.message, files_removed: removed }, 500);
    return J({ ok: true, subject: email, files_removed: removed, db_redaction: red });
  } catch (e) { return J({ ok: false, error: String((e as Error)?.message || e) }, 500); }
});
