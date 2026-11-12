// license_extract - Document Controller vision: (1) 'license' mode reads a UAE trade licence and
// extracts the legal company name, licence no, authority, emirate/city, issue/expiry dates;
// (2) 'profile' mode reads a company profile / catalog and summarises what the company does;
// (3) 'cert' mode reads ANY certificate (insurance, ISO, manufacturer authorisation) and pulls the
//     expiry date out of it - so nobody is ever asked to type dd/mm/yyyy by hand. A supplier holding
//     the document already has the date; asking them to retype it is a chance to get it wrong.
// Routed through ai_gateway (v3 multimodal passthrough) - the model ladder now lives in the gateway.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal, secretOk } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
// The licence request and its reading live in one module so the accuracy suite measures exactly this (7 Oct 2026).
import { SYS_LICENSE, SYS_PROFILE, parseJson, normDate, normEmirate, documentContent, normaliseLicence, imagesTooSmallToRead, UNREADABLE_LICENCE, lowReadProven, licencePages, hasReadablePage, checkLicenceRead } from '../_shared/licence_extract.ts';
import { pagesBlank } from '../_shared/licence_page_ink.ts';
import { pdfText } from '../_shared/document_expiry.ts';
import { J } from '../_shared/json_response.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
// secretOk() is the shared one, in ../_shared/internal_auth.ts.
// STOP REPORTING A FAILED READ AS A SUCCESSFUL ONE (9 Sep 2026).
//
// parseJson returned {} on unparseable model output. Every field below then read '' and the
// function answered HTTP 200 {ok:true, doc:{legal_name:'', confidence:'low'}} — byte-identical to
// the answer for a genuinely unreadable scan. The comment eleven lines into the handler had said
// so, in those words, since 5 August; nothing acted on it. That matters here specifically because
// this function is the front of supplier verification, and supplier_api's licence gate reads
// `!!licPath` — the licence being ON FILE, not the licence being READ — so a lie about success
// here is a lie inside an approval path.
//
// null now means "no usable object", and the handler turns that into a 502 with a named error
// instead of a blank doc. Every caller already branches on `jd?.ok && jd.doc` (supplier_api:344 →
// out.license_error, supplier_portal:421 → the "we could not read the expiry" message,
// wa_inbound:276 → stores the file and says it was not read, resend_inbound:108 → null), so all
// four get their existing failure path rather than a fabricated empty record.
//
// The approval gate itself is NOT touched — another effort owns that. This only stops the input
// to it from claiming a read that did not happen.
const SYS_CERT = `You read a supplier's CERTIFICATE or LETTER - typically an insurance policy schedule, an ISO certificate, or a manufacturer/authorised-dealer letter - and pull out the dates and identifying details so the supplier never has to type them by hand.\n\nRULES\n1. expiry_date is the date the document STOPS being valid. On insurance schedules this is the 'period of insurance' TO date. On ISO certificates it is the 'expiry' or 'valid until' date, NOT the certification or surveillance-audit date. On dealer letters it is the stated validity end, if any.\n2. If several dates appear, choose the one that governs when this document lapses. Do not return an issue date as an expiry.\n3. If NO expiry is printed anywhere, return an empty string and set confidence 'low'. Never invent or estimate a date - a wrong expiry either suspends a valid supplier or lets a lapsed one keep trading.\n4. Dates may be printed as DD/MM/YYYY, DD-MMM-YYYY or written out. Output YYYY-MM-DD.\n\nReturn STRICT JSON only:\n{\"doc_type\":\"insurance\"|\"iso\"|\"manufacturer\"|\"other\",\"issuer\":string,\"reference\":string,\"issue_date\":\"YYYY-MM-DD\",\"expiry_date\":\"YYYY-MM-DD\",\"covers\":string,\"confidence\":\"low\"|\"medium\"|\"high\"}\nissuer = the insurer, certification body, or manufacturer. reference = policy/certificate number. covers = one short line on what it covers or authorises.`;

function buildContent(mode: string, images: any[], body: any, withFile = false): any[] {
  const intro = mode === 'license'
    ? 'Read the attached UAE trade licence (all pages) and return the extraction JSON.'
    : mode === 'cert'
      ? 'Read the attached certificate / letter (all pages) and return the extraction JSON. The expiry date is the important field.'
      : 'Read the attached company profile / catalog pages and return the summary JSON.';
  return documentContent(intro, images, body, { withFile });
}

Deno.serve(observe('license_extract', async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'license_extract');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const secret = await sec('cred_fn_ai'); if (!secret) return J({ error: 'no ai key' }, 500);
    const mode = body.mode === 'profile' ? 'profile' : body.mode === 'cert' ? 'cert' : 'license';
    const images: any[] = Array.isArray(body.images) ? body.images : [];
    if (!images.length && !body.file_b64) return J({ error: 'no file' }, 400);
    // Review of #1707 (28 Oct 2026): pages that carry no base64 (an empty page, an object, a URL) are refused here, by
    // name, instead of reaching the provider as an image URL it rejects with a 400 the caller reads as 'ai_error'.
    if (!hasReadablePage(images, body)) return J({ error: 'no_readable_page', message: 'The file arrived without a readable page. Please upload the licence again as a PDF or a clear photo.' }, 400);
    // The blank-image guard runs first, in code: no model is asked to read a page too small to hold print.
    if (mode === 'license' && imagesTooSmallToRead(images, body)) return J({ ok: true, mode, doc: UNREADABLE_LICENCE(), guard: 'image_too_small' });
    // ...and a page-sized image that carries no print (a white scan, a photo of a wall) is blank, measured by
    // code (licence_page_ink): the model is not asked. inkProven = every image page decoded and one is printed.
    let inkProven = false;
    if (mode === 'license') {
      const blank = await pagesBlank(licencePages(images, body));
      if (blank === true) return J({ ok: true, mode, doc: UNREADABLE_LICENCE(), guard: 'image_blank' });
      inkProven = blank === false;
    }
    // the original PDF beside its page pictures, for a licence, only when switched on (_shared/licence_extract.ts documentContent)
    const withFile = mode === 'license' && (await sec('licence_read_sends_the_pdf')) === 'on';
    const content = buildContent(mode, images, body, withFile);
    const sys = mode === 'license' ? SYS_LICENSE : mode === 'cert' ? SYS_CERT : SYS_PROFILE;
    // One read: the model's parsed answer, or the Response this function answers when the read failed.
    // deno-lint-ignore no-explicit-any
    const ask = async (): Promise<{ ai: any } | { fail: Response }> => {
      try {
        // NO caller-side `max`. ai_gateway computes min(body.max ?? route.max_tokens,
        // route.max_tokens), so a number here can only LOWER model_policy.document_extraction's 8000,
        // never raise it. Measured on deployed staging 5 Aug 2026 against synthetic DED licences: a
        // plain licence uses 811-860 output tokens (54-57% of the old 1500) and a realistic
        // 15-activity one uses 1,116 (74%). It had not truncated yet, but a two-page licence or one
        // with partner and manager blocks would, and the failure is invisible: parseJson returns {}
        // on a truncated response and every field below is then scrubbed to '', so the caller gets
        // HTTP 200 {ok:true, doc:{legal_name:'', license_number:'', confidence:'low'}} - identical to
        // a genuinely unreadable scan. doc_extract carried the same pattern at max:2000 and DID fail.
        const r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, fn: 'license_extract', subject: body.subject ?? null, temperature: 0.1, sys, input: [{ role: 'user', content }] }) });
        const jd = await r.json();
        if (!r.ok || jd?.ok === false) return { fail: J({ error: 'ai_error', detail: jd?.detail || jd?.error || JSON.stringify(jd).slice(0, 300) }, 502) };
        // A truncation and a malformed answer are different repairs (raise the ceiling / fix the
        // parser) and used to collapse into the same blank doc. ai_gateway has always returned both
        // flags; read them.
        if (jd?.truncated === true || jd?.finish_reason === 'length') {
          return { fail: J({ error: 'extract_truncated', mode, message: 'The document was not fully read, so nothing was extracted. Please try again or upload a clearer copy.' }, 502) };
        }
        const parsed = parseJson(String(jd?.content ?? ''));
        if (!parsed) {
          return { fail: J({ error: 'extract_unreadable', mode, message: 'We could not read this document. Please upload a clear copy of the full page (PDF or a sharp photo).' }, 502) };
        }
        return { ai: parsed };
      } catch (e) { return { fail: J({ error: 'ai_exception', detail: String((e as Error)?.message || e) }, 502) }; }
    };
    const first = await ask();
    if ('fail' in first) return first.fail;
    // deno-lint-ignore no-explicit-any
    const ai: any = first.ai;

    if (mode === 'license') {
      // A 'low' read is stored only when code proved a real page was read: printed ink measured above, or its
      // licence number found in the document's own text layer. Otherwise it is held for a person (unreadable).
      // The text layer is read for EVERY licence sent as a file (12 Nov 2026, rulings 1663/1664): checkLicenceRead notes, for our
      // reviewer only, a date or number the model returned that the text layer does not print. It never blanks or holds one.
      let text: string | null = null;
      const textOf = async () => {
        if (text !== null || !body.file_b64 || /^image\//.test(String(body.mime || ''))) return text;
        try { text = await pdfText(Uint8Array.from(atob(String(body.file_b64).replace(/^data:[^;]+;base64,/, '')), (c) => c.charCodeAt(0))); } catch { text = null; }
        return text;
      };
      // deno-lint-ignore no-explicit-any
      const settle = async (raw: any) => {
        const read = normaliseLicence(raw);
        if (read.unreadable) return { read, doc: read, check: null };
        if (!lowReadProven(read, inkProven, await textOf())) return { read, doc: UNREADABLE_LICENCE(), check: null, guard: 'low_read_unproven' };
        const { doc, check } = checkLicenceRead(read, text);
        return { read, doc, check };
      };
      let s = await settle(ai);
      // AN EXPIRY NOT AFTER ITS ISSUE DATE IS IMPOSSIBLE (ruling 1663, B.2): the model is asked once more. A second answer that
      // passes stands; otherwise the first answer stands with its two dates unread (held for a person, never "expired").
      let asked = 1;
      if (s.check?.failed.includes('expiry_not_after_issue')) {
        const again = await ask(); asked = 2;
        if (!('fail' in again)) { const s2 = await settle(again.ai); if (s2.check && !s2.check.failed.length && !s2.doc.unreadable) s = s2; }
      }
      if ('guard' in s && s.guard) return J({ ok: true, mode, doc: s.doc, guard: s.guard });
      const check = s.check && (s.check.failed.length || s.check.notes.length) ? { ...s.check, asked } : undefined;
      return J({ ok: true, mode, doc: s.doc, ...(check ? { check } : {}) });
    }

    if (mode === 'cert') {
      const expiry = normDate(ai.expiry_date);
      const cert = {
        doc_type: ['insurance','iso','manufacturer','other'].includes(ai.doc_type) ? ai.doc_type : 'other',
        issuer: String(ai.issuer || '').trim().slice(0, 160),
        reference: String(ai.reference || '').trim().slice(0, 80),
        issue_date: normDate(ai.issue_date),
        expiry_date: expiry,
        covers: String(ai.covers || '').trim().slice(0, 300),
        confidence: ['low', 'medium', 'high'].includes(ai.confidence) ? ai.confidence : 'low',
      };
      // The portal prefills the date field from this and leaves it editable. found_expiry=false means
      // the document genuinely had no printed expiry, so the supplier is asked rather than guessed at.
      return J({ ok: true, mode, cert, found_expiry: !!expiry });
    }

    const profile = {
      summary: String(ai.summary || '').trim().slice(0, 1200),
      services: Array.isArray(ai.services) ? ai.services.map((s: any) => String(s).slice(0, 80)).slice(0, 12) : [],
      products: Array.isArray(ai.products) ? ai.products.map((s: any) => String(s).slice(0, 80)).slice(0, 12) : [],
      sectors: Array.isArray(ai.sectors) ? ai.sectors.map((s: any) => String(s).slice(0, 60)).slice(0, 12) : [],
      emirates: Array.isArray(ai.emirates) ? ai.emirates.map((s: any) => normEmirate(s)).filter(Boolean) : [],
      confidence: ['low', 'medium', 'high'].includes(ai.confidence) ? ai.confidence : 'low',
      // The printed lines, verbatim: the ONLY text a picture's trades are chosen from (review of #1412, 18 Oct 2026).
      lines: Array.isArray(ai.lines) ? ai.lines.map((s: any) => String(s).trim().slice(0, 120)).filter(Boolean).slice(0, 30) : [],
    };
    return J({ ok: true, mode, profile });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
