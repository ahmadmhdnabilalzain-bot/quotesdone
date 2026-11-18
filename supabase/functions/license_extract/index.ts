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
import { LICENCE_INTRO, SYS_LICENSE, SYS_PROFILE, parseJson, normDate, normEmirate, documentContent, normaliseLicence, imagesTooSmallToRead, UNREADABLE_LICENCE, lowReadProven, licencePages, hasReadablePage, checkLicenceRead, licenceSecondReadRequest } from '../_shared/licence_extract.ts';
// A file longer than any licence is read by its first pages only (ruling 1728, 18 Nov 2026; it was answered unread under ruling 1681); a
// file the reader is unsure of is read once more by the other model family before a person is asked (licence_second_read.ts).
import { b64Bytes, licencePageCount, tooManyPagesForALicence, firstPagesOfALongFile, longFileNote, withLongFileWindow, type LongFileWindow } from '../_shared/licence_pages.ts';
import { decideWithSecondRead, licenceFileSha } from '../_shared/licence_second_read.ts';
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

function buildContent(mode: string, images: any[], body: any, withFile = false, note = ''): any[] {
  const intro = mode === 'license'
    ? LICENCE_INTRO + (note ? ' ' + note : '')
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
    let images: any[] = Array.isArray(body.images) ? body.images : [];
    if (!images.length && !body.file_b64) return J({ error: 'no file' }, 400);
    // Review of #1707 (28 Oct 2026): pages that carry no base64 (an empty page, an object, a URL) are refused here, by
    // name, instead of reaching the provider as an image URL it rejects with a 400 the caller reads as 'ai_error'.
    if (!hasReadablePage(images, body)) return J({ error: 'no_readable_page', message: 'The file arrived without a readable page. Please upload the licence again as a PDF or a clear photo.' }, 400);
    // MORE PAGES THAN ANY TRADE LICENCE (ruling 1728; _shared/licence_pages.ts): the reader is given the file's first pages, told which
    // they are, and judges them as for any file; nothing else of it is sent. Only a long file whose first pages cannot be given (too large
    // to cut, or it cannot be opened, and no page pictures) is answered by its count, as under ruling 1681. A file whose pages cannot be
    // counted is read as before. The file's SHA is the whole file's, so the same file refused twice still opens one task.
    const original = { images, file_b64: body.file_b64 };
    let pagesWindow: LongFileWindow | null = null;
    // the original PDF beside its page pictures, for a licence, only when switched on (_shared/licence_extract.ts documentContent); read
    // before the page rule, because a long PDF is cut only when it will be sent (review of #2054)
    const withFile = mode === 'license' && (await sec('licence_read_sends_the_pdf')) === 'on';
    if (mode === 'license') {
      const pages = await licencePageCount({ images, file_b64: body.file_b64, mime: body.mime });
      const first = await firstPagesOfALongFile({ images, file_b64: body.file_b64, mime: body.mime, filename: body.filename }, pages, { sendsPdf: withFile });
      if (first) { pagesWindow = first.window; images = first.payload.images ?? []; body.file_b64 = first.payload.file_b64; body.mime = first.payload.mime ?? body.mime; }
      const long = first ? null : tooManyPagesForALicence(pages);
      if (long) return J({ ok: true, mode, doc: { ...UNREADABLE_LICENCE(), wrong_document: { ...long, file_sha: (await licenceFileSha(original)) ?? undefined } }, guard: 'too_many_pages', pages });
    }
    const note = pagesWindow ? longFileNote(pagesWindow) : '';
    const pagesRead = pagesWindow ? { pages_read: pagesWindow } : {};
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
    const content = buildContent(mode, images, body, withFile, note);
    const sys = mode === 'license' ? SYS_LICENSE : mode === 'cert' ? SYS_CERT : SYS_PROFILE;
    // One read: the model's parsed answer, or the Response this function answers when the read failed.
    // deno-lint-ignore no-explicit-any
    // over: the second read's question, prompt and counterpart (licence_extract.ts licenceSecondReadRequest); none = the first read
    // deno-lint-ignore no-explicit-any
    const ask = async (over?: { sys: string; input: any[]; counterpart_model: string }): Promise<{ ai: any; model: string | null } | { fail: Response }> => {
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
        const r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, fn: 'license_extract', subject: body.subject ?? null, temperature: 0.1, sys, input: [{ role: 'user', content }], ...(over ?? {}) }) });
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
        return { ai: parsed, model: typeof jd?.model === 'string' ? jd.model : null };
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
        // a plain-loop decode (licence_pages.ts b64Bytes), not Uint8Array.from with a callback: 1,281 ms for 12 MB (review of #2054)
        try { text = await pdfText(b64Bytes(String(body.file_b64)).slice()); } catch { text = null; }
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
      // A date the model gave that is no calendar day (normDate: a Hijri year, 30 Feb, a month-first form) is unread; noted, and asked again.
      // deno-lint-ignore no-explicit-any
      const badDates = (raw: any, read: { issue_date: string | null; expiry_date: string | null }) =>
        [...(raw?.issue_date && !read.issue_date ? ['issue_date_not_a_date'] : []), ...(raw?.expiry_date && !read.expiry_date ? ['expiry_date_not_a_date'] : [])];
      let s = await settle(ai);
      if (s.check) s.check.failed.push(...badDates(ai, s.read));
      // AN EXPIRY NOT AFTER ITS ISSUE DATE IS IMPOSSIBLE (ruling 1663, B.2), and a date that is no date is unread: the model is asked
      // once more. A second answer that passes stands; otherwise the first answer stands with those dates unread (held for a person or
      // asked again in plain words, never "expired"). A normal licence costs one call; this adds one, only on such an answer.
      let asked = 1;
      if (s.check?.failed.length) {
        const again = await ask(); asked = 2;
        if (!('fail' in again)) { const s2 = await settle(again.ai); if (s2.check && !s2.check.failed.length && !badDates(again.ai, s2.read).length && !s2.doc.unreadable) s = s2; }
      }
      if ('guard' in s && s.guard) return J({ ok: true, mode, doc: s.doc, guard: s.guard, ...pagesRead });
      // THE READER IS UNSURE (licence_extract.ts outcome iii): the other model family is asked once, the same file, one direct question;
      // its answer decides (licence_second_read.ts). A licence, or a file named at 'high', is never read twice.
      const decided = await decideWithSecondRead(s, first.model, async (firstModel) => {
        const req = licenceSecondReadRequest({ images, file_b64: body.file_b64, mime: body.mime, filename: body.filename }, body.subject ?? null, firstModel, note);
        const r = await ask({ sys: req.sys, input: req.input, counterpart_model: req.counterpart_model });
        return 'fail' in r ? null : r;
      }, settle);
      s = decided.s;
      if ('guard' in s && s.guard) return J({ ok: true, mode, doc: s.doc, guard: s.guard, second_read: decided.second, ...pagesRead });
      // the same file refused twice for one supplier opens one ceo task (licence_read_state.ts recordWrongDocument)
      // a long file's first pages that are not a licence: the sentence names the pages read and asks for just the licence pages
      if (s.doc.wrong_document) s = { ...s, doc: { ...s.doc, wrong_document: { ...(pagesWindow ? withLongFileWindow(s.doc.wrong_document, pagesWindow) : s.doc.wrong_document), file_sha: (await licenceFileSha(original)) ?? undefined } } };
      if (decided.second.asked) { const check = s.check && (s.check.failed.length || s.check.notes.length) ? { ...s.check, asked: asked + 1 } : undefined;
        return J({ ok: true, mode, doc: s.doc, second_read: decided.second, ...(check ? { check } : {}), ...pagesRead }); }
      const check = s.check && (s.check.failed.length || s.check.notes.length) ? { ...s.check, asked } : undefined;
      return J({ ok: true, mode, doc: s.doc, ...(check ? { check } : {}), ...pagesRead });
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
