// supplier_portal — what every module of this function shares: the service-role client, the CORS headers, the JSON
// responder and the failure helpers, the signed-URL and base64 helpers, and the request context index.ts hands each
// action group. ONE copy of each; nothing here is declared anywhere else.
// Moved here from index.ts on 9 Nov 2026 (sales_engineer: the 791-line index.ts split into modules, a pure move).
// supplier_portal v5 — advanced supplier dashboard API. Supplier-authed (own leads row via claimed_by).
import { createClient } from 'jsr:@supabase/supabase-js@2';

// The model path (license_extract → ai_gateway) is OFF unless app_secrets.document_expiry_ai is
// 'on'. OpenRouter is on hold; a closed door must not be knocked on for every upload.
export async function flagOn(key: string): Promise<boolean> { const { data } = await admin.from('app_secrets').select('value').eq('key', key).maybeSingle(); return /^(on|true|1)$/i.test(String(data?.value || '').trim()); }
// SUPPLIER-FACING TEXT CARRIES A CODE (14 Sep 2026). Every sentence below that reaches a supplier
// (document hints, alerts, eligibility titles/details) now travels with a stable `code` and `params`;
// the portal renders the EN/AR wording from src/components/portal/supplier/serverCopy.ts and falls
// back to the English here, which is kept verbatim for emails and older clients.
export const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
export const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
// A POSTGRES ERROR IS NOT A SENTENCE FOR A SUPPLIER (audit 22 Sep 2026, SP-I-01; agent:
// customer_support). Thirteen reads answered `{ error: error.message }`, which put raw Postgres text
// ("function fn_supplier_twin(p_lead_id => bigint) does not exist", column names, constraint names)
// straight into the browser — a schema leak, and untranslatable, so the Arabic portal printed English
// database prose. The real message now goes to the function log, the supplier gets a stable `code`
// src/components/portal/supplier/serverCopy.ts renders in their language, and `error` keeps a plain
// English sentence as the fallback for an older client.
export const failed = (where: string, code: string, english: string, error: { message?: string } | null, status = 500) => {
  console.error('supplier_portal: ' + where + ' failed —', String(error?.message || 'unknown'));
  return J({ error: english, code }, status);
};
export const loadFailed = (where: string, error: { message?: string } | null) =>
  failed(where, 'load_failed', 'Could not load this section. Please try again.', error);
export const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
export const SUPA_URL = Deno.env.get('SUPABASE_URL')!;
export function b64ToBytes(b64:string){ const bin=atob(String(b64).replace(/^data:[^;]+;base64,/,'')); const a=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i); return a; }
export async function sign(bucket:string, path:string|null){ if(!path) return null; try{ const { data } = await admin.storage.from(bucket).createSignedUrl(path, 3600); return data?.signedUrl || null; }catch{ return null; } }

/** One request, as the actions read it: built once by index.ts after the caller is signed in and their company found and not sanctioned. */
export type ActionCtx = {
  email: string;
  // deno-lint-ignore no-explicit-any
  sup: any;
  // deno-lint-ignore no-explicit-any
  supId: any;
  // deno-lint-ignore no-explicit-any
  b: any;
  action: string;
};
