// compliance_archive v4 — signed T&C acceptance certificates + customer register + Dropbox mirror.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import * as XLSX from 'https://esm.sh/xlsx@0.18.5';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const URL_ = Deno.env.get('SUPABASE_URL')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const BUCKET = 'signed-terms';
const DBX_BASE = '/QuotesDone Backup';
const TENYRS = 10 * 365 * 24 * 3600;

async function sec(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function authed(req: Request, body: any) { if ((await requireInternal(admin, body?.__secret, 'compliance_archive')).ok) return true; const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''); const { data: { user } } = await admin.auth.getUser(jwt); const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean); return !!(user?.email && allow.includes(user.email.toLowerCase())); }
function esc(s: any) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
function safeName(s: string) { return String(s || '').replace(/[^\w.\- ]+/g, '').replace(/\s+/g, ' ').trim().slice(0, 80) || 'record'; }
async function sha256hex(s: string) { const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)); return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join(''); }
function gst(iso: string) { try { return new Date(iso).toLocaleString('en-GB', { timeZone: 'Asia/Dubai', day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) + ' (GST)'; } catch { return iso; } }

async function dbxToken(): Promise<string | null> {
  const key = await sec('dropbox_app_key'), secret = await sec('dropbox_app_secret'), refresh = await sec('dropbox_refresh_token');
  if (!key || !secret || !refresh) return null;
  try {
    const r = await fetch('https://api.dropboxapi.com/oauth2/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: refresh, client_id: key, client_secret: secret }) });
    const jd = await r.json(); return jd?.access_token || null;
  } catch { return null; }
}
function apiArg(obj: any) { return JSON.stringify(obj).replace(/[-￿]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0')); }
// The parameter stays a bare Uint8Array on purpose: narrowing it to Uint8Array<ArrayBuffer> compiles
// here but pushes the same TS2345 onto all three call sites, which is one error turned into three.
// The cast is at the fetch body instead, where BodyInit is what is actually being satisfied.
async function dbxUpload(token: string, path: string, bytes: Uint8Array): Promise<boolean> {
  try {
    const r = await fetch('https://content.dropboxapi.com/2/files/upload', { method: 'POST', headers: { 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/octet-stream', 'Dropbox-API-Arg': apiArg({ path, mode: 'overwrite', autorename: false, mute: true, strict_conflict: false }) }, body: bytes as unknown as BodyInit });
    return r.ok;
  } catch { return false; }
}

async function renderCert(fields: Record<string, string>, kind: string, hash: string, name: string, termsUrl: string): Promise<{ path: string; url: string } | null> {
  const rows: [string, string][] = [];
  rows.push(['Full name', fields.full_name]);
  if (kind === 'supplier') rows.push(['Company', fields.company], ['Authorised signatory', fields.full_name]);
  if (fields.dob) rows.push(['Date of birth', fields.dob]);
  rows.push(['Mobile', fields.phone], ['Email', fields.email], ['Account type', kind === 'supplier' ? 'Supplier' : 'Customer'], ['Terms accepted', fields.terms_label], ['Accepted at (UTC)', fields.accepted_utc], ['Accepted at (local)', gst(fields.accepted_iso)], ['IP address', fields.ip || 'Not recorded'], ['Method', 'Click-to-accept checkbox at registration'], ['Document integrity (SHA-256)', hash]);
  const trs = rows.map(([k, v]) => `<tr><td>${esc(k)}</td><td>${esc(v)}</td></tr>`).join('');
  const clauses = kind === 'supplier' ? '<ul><li>No-circumvention: no off-platform dealing with a customer introduced through the Platform for 24 months.</li><li>Confidentiality: no copying, reuse or disclosure of platform leads, customer data, pricing or anonymised scopes.</li><li>No replication or competing use of the Platform&#39;s software, matching logic or outputs.</li></ul>' : '<ul><li>No use of the Platform to build, benchmark or assist a competing product or service.</li><li>No scraping, copying or reuse of supplier data, pricing or platform content.</li><li>No reverse-engineering or replication of the Platform&#39;s software, matching logic or outputs.</li></ul>';
  const penalties = kind === 'supplier' ? 'Breach of the no-circumvention obligation entitles QuotesDone to liquidated compensation of AED 15,000 per incident, or three (3) times the avoided fee, whichever is higher, in addition to the unpaid fee. Breach of the confidentiality or data-reuse obligation entitles QuotesDone to AED 20,000 per incident. In every case QuotesDone is also entitled to injunctive relief to stop the ongoing breach and to recover any further proven losses.' : 'Any breach of the above obligations entitles QuotesDone to liquidated compensation of AED 10,000 per incident, immediate suspension or termination of the account, recovery of any further proven losses, and injunctive relief to stop the ongoing breach. The parties agree these amounts are a genuine pre-estimate of loss under the laws of the United Arab Emirates.';
  const body_html = `<p>This certificate records the electronic acceptance of the QuotesDone ${kind === 'supplier' ? 'Supplier Agreement &amp; Platform Terms' : 'Customer Terms &amp; Conditions'} by the party identified below. Acceptance was given by ticking the &quot;I accept&quot; box during registration on the QuotesDone platform, which under the laws of the United Arab Emirates (including the Electronic Transactions and Trust Services Law) constitutes a valid and binding electronic acceptance.</p><table><thead><tr><th>Field</th><th>Detail</th></tr></thead><tbody>${trs}</tbody></table><h3>Terms accepted</h3><p>By registering, the party accepted the QuotesDone ${kind === 'supplier' ? 'Supplier Agreement &amp; Platform Terms' : 'Customer Terms &amp; Conditions'} (${fields.terms_label}), published in full at ${termsUrl}. The key binding obligations accepted include:</p>${clauses}<h3>Penalties for breach</h3><p>${penalties}</p><p>The SHA-256 value above is a cryptographic fingerprint of the exact Terms text that was accepted. Any later change to that text produces a different fingerprint, allowing the accepted version to be independently verified.</p><p>This is a system-generated record issued by QuotesDone Technologies and is valid without a handwritten signature.</p>`;
  try {
    const secret = await sec('cred_fn_to_pdf_native');
    const pr = await fetch(`${URL_}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, title: 'Certificate of Acceptance — Terms & Conditions', body_html, name, bucket: BUCKET, folder: (kind === 'supplier' ? 'suppliers' : 'customers'), options: { letterhead: true, sign: true, stamp: true } }) });
    const pj = await pr.json(); if (pj?.ok && pj.path) return { path: pj.path, url: pj.url }; return null;
  } catch { return null; }
}

async function buildRegister(): Promise<{ count: number; url: string | null; bytes: Uint8Array | null }> {
  const { data } = await admin.from('customers').select('full_name,date_of_birth,phone,email,signed_terms_path,created_at,email_verified').order('created_at', { ascending: true });
  const rows = (data || []);
  const paths = rows.map((c: any) => c.signed_terms_path).filter(Boolean) as string[];
  const urlByPath: Record<string, string> = {};
  if (paths.length) { try { const { data: su } = await admin.storage.from(BUCKET).createSignedUrls(paths, TENYRS); for (const it of (su || [])) { if (it.path && it.signedUrl) urlByPath[it.path] = it.signedUrl; } } catch (_e) { } }
  const header = ['Name', 'Date of birth', 'Mobile', 'Email', 'Signed T&C copy', 'Registered (UTC)', 'Email verified'];
  const aoa: any[][] = [header];
  const urls: (string | null)[] = [null];
  for (const c of rows) { const u = c.signed_terms_path ? (urlByPath[c.signed_terms_path] || null) : null; aoa.push([c.full_name || '', c.date_of_birth || '', c.phone || '', c.email || '', u ? 'Open signed PDF' : '', (c.created_at || '').slice(0, 19).replace('T', ' '), c.email_verified ? 'Yes' : 'No']); urls.push(u); }
  const ws = XLSX.utils.aoa_to_sheet(aoa); ws['!cols'] = [{ wch: 26 }, { wch: 14 }, { wch: 18 }, { wch: 30 }, { wch: 24 }, { wch: 20 }, { wch: 14 }];
  for (let r = 1; r < aoa.length; r++) { const u = urls[r]; if (!u) continue; const ref = XLSX.utils.encode_cell({ c: 4, r }); ws[ref] = { t: 's', v: 'Open signed PDF', l: { Target: u, Tooltip: 'Open signed acceptance certificate (PDF)' } }; }
  const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, 'Customers');
  const out = XLSX.write(wb, { type: 'array', bookType: 'xlsx' }); const bytes = new Uint8Array(out);
  await admin.storage.from(BUCKET).upload('registers/customers-register.xlsx', bytes, { contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', upsert: true });
  const { data: signed } = await admin.storage.from(BUCKET).createSignedUrl('registers/customers-register.xlsx', TENYRS);
  return { count: rows.length, url: signed?.signedUrl || null, bytes };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!(await authed(req, body))) return J({ error: 'forbidden' }, 403);
    const action = String(body.action || '');
    try { await admin.storage.createBucket(BUCKET, { public: false }); } catch (_e) { }

    if (action === 'ping') { const t = await dbxToken(); return J({ ok: true, dropbox_ready: !!t }); }

    if (action === 'sign') {
      const kind = body.kind === 'supplier' ? 'supplier' : 'customer';
      const keyEmail = String(body.email || '').trim().toLowerCase();
      let rec: any = null;
      if (kind === 'customer') { const q = keyEmail ? admin.from('customers').select('*').eq('email', keyEmail) : admin.from('customers').select('*').eq('id', body.id); const { data } = await q.maybeSingle(); rec = data; }
      else { const q = keyEmail ? admin.from('leads').select('*').eq('claimed_by', keyEmail) : admin.from('leads').select('*').eq('id', body.id); const { data } = await q.maybeSingle(); rec = data; }
      if (!rec) return J({ error: 'record_not_found' }, 404);

      let termsText = '', termsLabel = '';
      // ONE SOURCE OF TRUTH FOR THE VERSION (2 Aug 2026, external code review). This label was
      // hard-coded to "Version 4" while supplier_api recorded the accepted version as whatever
      // app_secrets('terms_version') said — a key that did not exist, so it silently recorded 'v2'
      // — and kyc hard-coded 'v4' on a third path. A certificate that names a different version of
      // the agreement than the acceptance row it certifies is not evidence of anything; it is the
      // first thing a counterparty's lawyer would attack. Both now read the same secrets, so the
      // label, the stored version and the document move together and can only be changed in one
      // place. The fallbacks match today's live documents so nothing breaks if a key is deleted.
      if (kind === 'supplier') { termsText = (await sec('supplier_terms_html')) || ''; termsLabel = (await sec('supplier_terms_label')) || 'Supplier Agreement — Version 5'; }
      else { const { data: p } = await admin.from('pages').select('html').eq('slug', 'legal_terms_body').maybeSingle(); termsText = (p?.html as string) || ''; termsLabel = (await sec('customer_terms_label')) || 'Customer Terms & Conditions — Version 3'; }
      const hash = await sha256hex(termsText);
      // A CERTIFICATE OF ACCEPTANCE REQUIRES AN ACCEPTANCE (12 Aug 2026). This read
      // `... || new Date().toISOString()`, so when the party had NOT accepted the Terms it stamped
      // the certificate with the moment of rendering and carried on. The document it produces then
      // states, in its own words, that "Acceptance was given by ticking the 'I accept' box during
      // registration" and that this "constitutes a valid and binding electronic acceptance" under
      // the UAE Electronic Transactions and Trust Services Law — against a timestamp nobody clicked
      // anything at, with "Method: Click-to-accept checkbox at registration" beside it.
      //
      // This is reachable without anyone doing anything wrong: trg_sign_customer fires on
      // email_verified going true, NOT on tos_accepted_at being set, so any customer who verifies
      // their email before accepting the Terms gets one. Found because repairing the email_verified
      // flag for the one real production customer fired it, and produced a certificate asserting an
      // acceptance that has not happened — tos_accepted_at is still null on that row.
      //
      // Refusing is the only honest option. A missing acceptance is not a formatting problem to be
      // defaulted around; it is the absence of the fact the whole document exists to attest. The
      // caller is a best-effort background archiver in every path (customer_api explicitly does not
      // block on signed_terms_path), so refusing costs nothing and the certificate is produced the
      // moment a real acceptance is recorded.
      const acceptedIso = (kind === 'supplier' ? rec.accepted_terms_at : rec.tos_accepted_at) || '';
      if (!acceptedIso) {
        await admin.from('agent_runs').insert({
          agent: 'compliance_archive', status: 'error',
          started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
          counts: { stage: 'sign', kind, no_acceptance: 1 },
          note: ('compliance_archive refused to issue a Terms-acceptance certificate for ' + (keyEmail || rec.id)
            + ' because ' + (kind === 'supplier' ? 'leads.accepted_terms_at' : 'customers.tos_accepted_at')
            + ' is null: this party has not accepted the Terms, and the certificate asserts under UAE law '
            + 'that they did. It will be issued automatically the moment a real acceptance is recorded. '
            + 'Do NOT restore the previous behaviour of stamping the render time as the acceptance time.').slice(0, 500),
        });
        return J({ error: 'no_acceptance_on_record', kind, email: keyEmail || null }, 409);
      }
      const ip = (kind === 'supplier' ? rec.accepted_terms_ip : rec.tos_ip) || '';
      const fields: Record<string, string> = { full_name: rec.full_name || rec.contact_name || rec.signatory_name || '', company: rec.company_name || '', dob: (kind === 'supplier' ? rec.owner_dob : rec.date_of_birth) || '', phone: rec.phone || '', email: rec.email || rec.claimed_by || keyEmail, terms_label: termsLabel, accepted_utc: acceptedIso.slice(0, 19).replace('T', ' ') + ' UTC', accepted_iso: acceptedIso, ip };
      const nm = safeName((kind === 'supplier' ? fields.company : fields.full_name) || fields.email).replace(/\s+/g, '_') + '_TnC-Acceptance';
      const termsUrl = kind === 'supplier' ? 'https://quotesdone.com/supplier-agreement' : 'https://quotesdone.com/terms';
      const cert = await renderCert(fields, kind, hash, nm, termsUrl);
      if (!cert) return J({ error: 'cert_render_failed' }, 502);
      const nowIso = new Date().toISOString();
      let certUrl = cert.url; try { const { data: lu } = await admin.storage.from(BUCKET).createSignedUrl(cert.path, TENYRS); if (lu?.signedUrl) certUrl = lu.signedUrl; } catch (_e) { }
      if (kind === 'customer') await admin.from('customers').update({ signed_terms_url: certUrl, signed_terms_path: cert.path, signed_terms_at: nowIso }).eq('id', rec.id);
      else await admin.from('leads').update({ signed_terms_url: certUrl, signed_terms_path: cert.path, signed_terms_at: nowIso }).eq('id', rec.id);

      let dbx = false; const token = await dbxToken();
      let pdfBytes: Uint8Array | null = null;
      try { const dl = await admin.storage.from(BUCKET).download(cert.path); if (dl.data) pdfBytes = new Uint8Array(await dl.data.arrayBuffer()); } catch (_e) { }
      if (token && pdfBytes) {
        const folder = kind === 'supplier' ? `${DBX_BASE}/Suppliers/${safeName(fields.company || fields.email)}` : `${DBX_BASE}/Customers/${safeName(fields.full_name || fields.email)}`;
        dbx = await dbxUpload(token, `${folder}/Signed-Terms-Acceptance.pdf`, pdfBytes);
      }

      let reg: any = null;
      if (kind === 'customer') { try { const r = await buildRegister(); reg = { count: r.count, url: r.url }; if (token && r.bytes) await dbxUpload(token, `${DBX_BASE}/Customers/customers-register.xlsx`, r.bytes); } catch (_e) { } }

      return J({ ok: true, kind, signed_url: certUrl, dropbox_mirrored: dbx, register: reg });
    }

    if (action === 'register') {
      const r = await buildRegister(); let dbx = false; const token = await dbxToken();
      if (token && r.bytes) dbx = await dbxUpload(token, `${DBX_BASE}/Customers/customers-register.xlsx`, r.bytes);
      return J({ ok: true, count: r.count, url: r.url, dropbox_mirrored: dbx });
    }

    return J({ error: 'unknown_action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
