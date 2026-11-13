// compliance_archive v5 — signed T&C acceptance certificates + the customer register.
//
// RESTORED 9 Sep 2026 (agent: sales_engineer). Commit 182308b deleted 137 edge functions and took
// this one with them, while public.qd_sign_customer and public.qd_sign_supplier — both still live
// DB triggers — kept calling it by URL and discarding the result. Every T&C signature since 8 Sep
// has failed to archive silently. Measured on restore: customers.tos_accepted_at is null on the
// only customer row and leads.accepted_terms_at is null on every lead, so the number of signatures
// actually lost in that window is ZERO. The hole was real; the backlog behind it was not.
//
// WHAT CHANGED FROM v4 — THE CERTIFICATE NO LONGER PUTS ITSELF IN DROPBOX.
// v4 uploaded the rendered certificate to
//     /QuotesDone Backup/Customers/<safeName(full_name)>/Signed-Terms-Acceptance.pdf
// while fn_enqueue_doc_backups — the function that owns the organized tree — files the same
// document at
//     /QuotesDone Backup/Customers/<fn_dbx_safe(full_name)> (<id8>)/Signed Terms & Conditions - <file>.pdf
// Two different folders for one customer, by two different name-sanitizers, for the same PDF. The
// live doc_backups rows show the tree's form ('ahmad alzain (95e4345e)/Signed Terms & Conditions -
// ...'), so v4's upload was creating a duplicate id-less sibling folder beside it every time. That
// is the exact opposite of the founder's "organized folders" ask.
//
// The fix is subtraction: this function writes signed_terms_path, and fn_enqueue_doc_backups picks
// that column up for BOTH customers and suppliers on the next backup sweep. One function decides
// where a document lives in Dropbox. The certificate reaches Dropbox on the next tick instead of
// instantly, which is the correct trade for never filing it in two places again.
import { timedFetch } from '../_shared/timed_fetch.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { adminCaller, type TwoStepBody } from '../_shared/admin_session.ts';
// SheetJS 0.20.3, VENDORED in _shared/vendor (14 Sep 2026). NOT the remote esm.sh copy of xlsx 0.18.5: that npm package
// stopped at 0.18.5, which carries CVE-2023-30533 (prototype pollution on read), and a remote import makes
// a third-party CDN a deploy-time dependency of the compliance register. 22 Sep 2026, UNSOLVED-08.
// @deno-types="../_shared/vendor/sheetjs-0.20.3/types/index.d.ts"
import * as XLSX from '../_shared/vendor/sheetjs-0.20.3/xlsx.mjs';
import { observe } from '../_shared/observe.ts';
import { writeRecorded } from '../_shared/recorded_write.ts';
import { certFields, certLang, certificate, COMPANY_NOT_YET_READ, isRegisterRow, noAcceptanceRunStatus, supplierCompany, supplierEvidence, type Lang } from './certificate.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const URL_ = Deno.env.get('SUPABASE_URL')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const BUCKET = 'signed-terms';
const DBX_BASE = '/QuotesDone Backup';
const TENYRS = 10 * 365 * 24 * 3600;

async function sec(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// The JWT half goes through the one admin door (_shared/admin_session.ts): admin_emails AND an aal2 session. An admin
// whose session has one factor gets the body naming the step instead of `true` (security audit 10 Nov 2026, item 1).
async function authed(req: Request, body: any): Promise<true | false | TwoStepBody> { if ((await requireInternal(admin, body?.__secret, 'compliance_archive')).ok) return true; const a = await adminCaller(admin, sec, req.headers.get('Authorization')); return a.kind === 'admin' ? true : a.kind === 'two_step_required' ? a.body : false; }
// A CERTIFICATE THAT COULD NOT BE WRITTEN TELLS THE IT SEAT (13 Nov 2026). The person is not left with nothing: the
// supplier's portal says "Signing your Supplier Agreement…" while signed_terms_path is empty, and the minute sweeps
// (fn_sales_engineer_resigns_unsigned_agreements for suppliers, fn_customer_support_resigns_unsigned_terms for
// customers) post the sign again after 5 minutes, 3 times, then ask a person. This finding is the IT seat's step: a write
// that fails after its retries is a database that is not answering, which no re-sign repairs by itself.
async function certificateNotRecorded(kind: string, id: unknown, attempts: number, reason: string): Promise<void> {
  try {
    await admin.rpc('fn_it_engineer_finding_upsert', {
      p_issue_key: `certificate_not_recorded:${kind}`, p_title: `compliance_archive could not write a ${kind}'s signed-terms certificate onto the row`,
      p_where: 'edge function compliance_archive, action sign', p_blast: 'customer_facing', p_affected: 1,
      p_evidence: { kind, row_id: id, attempts, reason: reason.slice(0, 300), at: new Date().toISOString(),
        recovers_by: kind === 'supplier' ? 'fn_sales_engineer_resigns_unsigned_agreements (every minute, after 5 min, 3 tries)' : 'fn_customer_support_resigns_unsigned_terms (every minute, after 5 min, 3 tries)' },
      p_ruled_out: [], p_undetermined: ['what held the lock or the time: the postgres log at this time ("still waiting for", "statement timeout"); scripts/lib/replay_guard.mjs'],
      p_raised_by: 'it_engineer',
    });
  } catch (e) { console.error('compliance_archive: IT finding not raised:', String((e as Error)?.message || e)); }
}
function safeName(s: string) { return String(s || '').replace(/[^\w.\- ]+/g, '').replace(/\s+/g, ' ').trim().slice(0, 80) || 'record'; }
async function sha256hex(s: string) { const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)); return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join(''); }

async function dbxToken(): Promise<string | null> {
  const key = await sec('dropbox_app_key'), secret = await sec('dropbox_app_secret'), refresh = await sec('dropbox_refresh_token');
  if (!key || !secret || !refresh) return null;
  try {
    const r = await timedFetch('https://api.dropboxapi.com/oauth2/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: refresh, client_id: key, client_secret: secret }) });
    const jd = await r.json(); return jd?.access_token || null;
  } catch { return null; }
}
function apiArg(obj: any) { return JSON.stringify(obj).replace(/[-￿]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0')); }
// The parameter stays a bare Uint8Array on purpose: narrowing it to Uint8Array<ArrayBuffer> compiles
// here but pushes the same TS2345 onto the call site, which is one error turned into two.
// The cast is at the fetch body instead, where BodyInit is what is actually being satisfied.
async function dbxUpload(token: string, path: string, bytes: Uint8Array): Promise<boolean> {
  try {
    const r = await timedFetch('https://content.dropboxapi.com/2/files/upload', { method: 'POST', headers: { 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/octet-stream', 'Dropbox-API-Arg': apiArg({ path, mode: 'overwrite', autorename: false, mute: true, strict_conflict: false }) }, body: bytes as unknown as BodyInit });
    return r.ok;
  } catch { return false; }
}

async function renderCert(fields: Record<string, string>, kind: string, hash: string, name: string, termsUrl: string, lang: Lang = 'en'): Promise<{ path: string; url: string } | null> {
  const { title, body_html } = certificate(fields, kind, hash, termsUrl, lang);
  try {
    const secret = await sec('cred_fn_to_pdf_native');
    const pr = await timedFetch(`${URL_}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, title, lang, body_html, name, bucket: BUCKET, folder: (kind === 'supplier' ? 'suppliers' : 'customers'), options: { letterhead: true, sign: true, stamp: true } }) }, 45_000);
    const pj = await pr.json(); if (pj?.ok && pj.path) return { path: pj.path, url: pj.url }; return null;
  } catch { return null; }
}

async function buildRegister(): Promise<{ count: number; url: string | null; bytes: Uint8Array | null }> {
  // 12 Oct 2026 (founder audit against the 9 Sep spec): the register lists CUSTOMERS, and a sign-up is a customer only
  // once the terms are accepted (ruling 1181), with the IP, the accepted version and the time, beside the link.
  const { data } = await admin.from('customers').select('full_name,date_of_birth,phone,email,signed_terms_path,created_at,email_verified,tos_ip,tos_version,tos_accepted_at,is_demo')
    .not('tos_accepted_at', 'is', null).eq('is_demo', false).order('created_at', { ascending: true });
  const rows = (data || []).filter(isRegisterRow);
  const paths = rows.map((c: any) => c.signed_terms_path).filter(Boolean) as string[];
  const urlByPath: Record<string, string> = {};
  if (paths.length) { try { const { data: su } = await admin.storage.from(BUCKET).createSignedUrls(paths, TENYRS); for (const it of (su || [])) { if (it.path && it.signedUrl) urlByPath[it.path] = it.signedUrl; } } catch (_e) { } }
  const header = ['Name', 'Date of birth', 'Mobile', 'Email', 'Signed T&C copy', 'Registered (UTC)', 'Email verified', 'Terms version', 'Terms accepted (UTC)', 'IP address'];
  const aoa: any[][] = [header];
  const urls: (string | null)[] = [null];
  for (const c of rows) { const u = c.signed_terms_path ? (urlByPath[c.signed_terms_path] || null) : null; aoa.push([c.full_name || '', c.date_of_birth || '', c.phone || '', c.email || '', u ? 'Open signed PDF' : '', (c.created_at || '').slice(0, 19).replace('T', ' '), c.email_verified ? 'Yes' : 'No', c.tos_version || '', (c.tos_accepted_at || '').slice(0, 19).replace('T', ' '), c.tos_ip || '']); urls.push(u); }
  const ws = XLSX.utils.aoa_to_sheet(aoa); ws['!cols'] = [{ wch: 26 }, { wch: 14 }, { wch: 18 }, { wch: 30 }, { wch: 24 }, { wch: 20 }, { wch: 14 }, { wch: 12 }, { wch: 20 }, { wch: 18 }];
  for (let r = 1; r < aoa.length; r++) { const u = urls[r]; if (!u) continue; const ref = XLSX.utils.encode_cell({ c: 4, r }); ws[ref] = { t: 's', v: 'Open signed PDF', l: { Target: u, Tooltip: 'Open signed acceptance certificate (PDF)' } }; }
  const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, 'Customers');
  const out = XLSX.write(wb, { type: 'array', bookType: 'xlsx' }); const bytes = new Uint8Array(out);
  await admin.storage.from(BUCKET).upload('registers/customers-register.xlsx', bytes, { contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', upsert: true });
  const { data: signed } = await admin.storage.from(BUCKET).createSignedUrl('registers/customers-register.xlsx', TENYRS);
  return { count: rows.length, url: signed?.signedUrl || null, bytes };
}

Deno.serve(observe('compliance_archive', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    const ok = await authed(req, body);
    if (ok !== true) return J(ok || { error: 'forbidden' }, 403);
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
          agent: 'compliance_archive', status: noAcceptanceRunStatus(keyEmail),
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
      // ONE CERTIFICATE PER ACCEPTANCE (15 Sep 2026, sales_engineer). Several callers ask for the same
      // certificate at once: kyc accept_terms signs synchronously, and the acceptance it (or supplier_api)
      // wrote fires z21_sign_supplier_on_acceptance, which posts here too. Each render is a new object in
      // the bucket, and only the last one to write signed_terms_path is named by the row; the rest never
      // reach the Dropbox tree and no teardown removes them. So: a certificate already issued at or after
      // this acceptance is returned as it is, and a new one is written only if the row still names what
      // it named when this call read it (compare-and-set). The caller that loses the race deletes its own
      // render and returns the winner's. Every acceptance still gets exactly one certificate, whichever
      // caller arrives first. body.force re-issues deliberately. A certificate replaced by a genuinely NEW
      // acceptance (a later version) is kept in the bucket on purpose: it is the evidence of the earlier one.
      const table = kind === 'customer' ? 'customers' : 'leads';
      const priorPath: string | null = rec.signed_terms_path ?? null;
      const signedUrlOf = async (p: string | null) => { if (!p) return null; const { data } = await admin.storage.from(BUCKET).createSignedUrl(p, TENYRS); return data?.signedUrl || null; };
      if (body.force !== true && priorPath && rec.signed_terms_at && Date.parse(rec.signed_terms_at) >= Date.parse(acceptedIso)) {
        const existing = await signedUrlOf(priorPath);
        if (existing) return J({ ok: true, kind, signed_url: existing, filed_by: 'fn_enqueue_doc_backups', register: null, reused: true });
      }
      const ip = (kind === 'supplier' ? rec.accepted_terms_ip : rec.tos_ip) || '';
      // A supplier's certificate prints the version, SHA-256 and user agent the ACCEPTANCE ROW recorded
      // (supplierEvidence, certificate.ts); the live secrets only fill in for older rows without them.
      const ev = kind === 'supplier' ? supplierEvidence(rec, termsLabel, hash) : { terms_label: termsLabel, hash, ua: '' };
      const fields: Record<string, string> = { ...certFields(rec, kind), ...(kind === 'supplier' ? supplierCompany(rec) : { company: rec.company_name || '' }), dob: (kind === 'supplier' ? rec.owner_dob : rec.date_of_birth) || '', phone: rec.phone || '', email: rec.email || rec.claimed_by || keyEmail, terms_label: ev.terms_label, accepted_utc: acceptedIso.slice(0, 19).replace('T', ' ') + ' UTC', accepted_iso: acceptedIso, ip, ua: ev.ua };
      const nm = safeName((kind === 'supplier' ? (fields.company === COMPANY_NOT_YET_READ ? '' : fields.company) : fields.full_name) || fields.email).replace(/\s+/g, '_') + '_TnC-Acceptance';
      const termsUrl = kind === 'supplier' ? 'https://quotesdone.com/supplier-agreement' : 'https://quotesdone.com/terms';
      const cert = await renderCert(fields, kind, ev.hash, nm, termsUrl, certLang(rec));
      if (!cert) return J({ error: 'cert_render_failed' }, 502);
      const nowIso = new Date().toISOString();
      let certUrl = cert.url; try { const { data: lu } = await admin.storage.from(BUCKET).createSignedUrl(cert.path, TENYRS); if (lu?.signedUrl) certUrl = lu.signedUrl; } catch (_e) { }
      // signed_terms_path is what puts this certificate into the organized Dropbox tree:
      // fn_enqueue_doc_backups reads it for customers AND suppliers and files it under
      // '<entity folder>/Signed Terms & Conditions - <file>'. See the header note.
      // THE WRITE IS READ BACK AND A BLIP IS TRIED AGAIN (13 Nov 2026, _shared/recorded_write.ts). At 07:46:10 this write
      // waited behind a rehearsal's lock on quotes (the gate it fires sends a notice whose trigger reads quotes) and the 8 s
      // statement timeout cancelled it: cert_record_failed, and the supplier stayed unapproved until the minute sweep
      // (fn_sales_engineer_resigns_unsigned_agreements) signed it again at 07:51. A compare-and-set is safe to repeat: a
      // retry after a write that did land matches no row and is answered as the lost race below.
      const casWrite = () => {
        const cas = admin.from(table).update({ signed_terms_url: certUrl, signed_terms_path: cert.path, signed_terms_at: nowIso }).eq('id', rec.id);
        return (priorPath === null ? cas.is('signed_terms_path', null) : cas.eq('signed_terms_path', priorPath)).select('id');
      };
      const w = await writeRecorded(casWrite);
      const won = w.ok ? w.data : null;
      const casErr = !w.ok && w.reason !== 'the write matched no row' ? { message: w.reason } : null;
      if (casErr) await certificateNotRecorded(kind, rec.id, w.attempts, casErr.message);
      if (casErr || !won?.length) {
        // Lost the race (or the write failed): this render is named by no row, so it must not stay. The
        // winner already rebuilt the customer register after its own write, so nothing is left to refresh.
        const { error: rmErr } = await admin.storage.from(BUCKET).remove([cert.path]);
        if (rmErr) await admin.from('agent_runs').insert({ agent: 'compliance_archive', status: 'error', started_at: nowIso, finished_at: new Date().toISOString(),
          counts: { stage: 'sign', kind, orphan_left: 1 }, note: ('a duplicate certificate render could not be removed and is named by no row: ' + cert.path + ' (' + rmErr.message + ')').slice(0, 500) });
        if (casErr) return J({ error: 'cert_record_failed', detail: casErr.message }, 502);
        const { data: w } = await admin.from(table).select('signed_terms_path').eq('id', rec.id).maybeSingle();
        return J({ ok: true, kind, signed_url: await signedUrlOf((w?.signed_terms_path as string) || null), filed_by: 'fn_enqueue_doc_backups', register: null, reused: true });
      }

      // The register is a whole-of-register document, not an entity document, so it has no row in
      // doc_backups and no place in the per-entity tree. It sits at the head of Customers/ and is
      // the one thing this function still writes to Dropbox itself.
      let reg: any = null;
      if (kind === 'customer') { try { const token = await dbxToken(); const r = await buildRegister(); reg = { count: r.count, url: r.url }; if (token && r.bytes) await dbxUpload(token, `${DBX_BASE}/Customers/customers-register.xlsx`, r.bytes); } catch (_e) { } }

      return J({ ok: true, kind, signed_url: certUrl, filed_by: 'fn_enqueue_doc_backups', register: reg });
    }

    if (action === 'register') {
      const r = await buildRegister(); let dbx = false; const token = await dbxToken();
      if (token && r.bytes) dbx = await dbxUpload(token, `${DBX_BASE}/Customers/customers-register.xlsx`, r.bytes);
      return J({ ok: true, count: r.count, url: r.url, dropbox_mirrored: dbx });
    }

    return J({ error: 'unknown_action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
