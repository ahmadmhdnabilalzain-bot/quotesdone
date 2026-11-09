// accountant — the report since day one: spend_report.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (the 1,715-line index.ts split into modules, a pure move).
import { type ActionCtx, J, SUPA_URL, admin, run, sec } from '../context.ts';

export async function reportActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action, caller } = c;
    // ── SPEND_REPORT ───────────────────────────────────────────────────────────────────────────
    // "let him send me a report of all what we spent since day 1 by trailing the whole inbox"
    // (the founder, 9 Sep 2026).
    //
    // THE SEAT SENDS IT, NOT A SESSION. He asked for this as a TEST of the agent, so the document
    // is rendered by the seat's own credential and the mail is inserted by the seat's own database
    // routine into the lane registered to owner_role 'accountant'. Nothing here is carried by hand.
    //
    // WHAT THE NUMBERS ARE. fn_accountant_spend_report reads expense_entries — nothing else — and
    // states the coverage of the last sweep from agent_runs beside the total, so the total can be
    // seen either to be complete or to be short. A held receipt is a NAMED LINE on the report, not
    // an omission and not a zero. The AED column converts USD at gl_settings.usd_to_aed and refuses
    // any other currency rather than booking it at 1:1; both are printed on the document.
    //
    // DELIVERY IS OPT-IN (`deliver: true`). A report renders without arming a send, so the document
    // can be produced and read before anyone is mailed.
    if (action === 'spend_report') {
      const { data: repRaw, error: repErr } = await admin.rpc('fn_accountant_spend_report', {
        p_as_of: typeof body.as_of === 'string' ? body.as_of : null,
      });
      if (repErr) {
        await run('spend_report', 'error', {}, 'fn_accountant_spend_report failed: ' + repErr.message);
        return J({ ok: false, error: 'report_unavailable', detail: repErr.message }, 503);
      }
      const rep = (repRaw || {}) as Record<string, unknown>;

      // ── THE DOCUMENT LINKS ───────────────────────────────────────────────────────────────────
      // The founder, 9 Sep 2026: "can the pdf have clickable links for the actual invoices or
      // receipts or at least a pdf print of the email".
      //
      // fn_accountant_spend_report marks every cell it wants clickable as
      // {text, link_entry: <expense id>}. It cannot do more than MARK it: receipt-files is a private
      // bucket, a URL into it must be signed with the service role, and there is no pgjwt in this
      // project. So the resolution happens here, in the one place that holds the key — one read of
      // v_expense_documents and ONE batch signing call, not forty-five round trips.
      //
      // LIFETIME, DECIDED DELIBERATELY. The signed URL is the CONVENIENCE; the record number printed
      // in the first column of every row is the PERMANENT handle. A year is long enough that the
      // founder is not chasing dead links next quarter, and short enough that a leaked copy of this
      // report is not a standing grant over the whole receipt archive. The exact expiry date is
      // printed on the document under the table — a link whose death date is unstated is a link that
      // gets discovered dead — together with the two routines that turn a record number back into a
      // fresh one. The full reasoning, including the two options not taken, is in the header of
      // scripts/sql/the_spend_report_links_every_line_to_the_document_behind_it.sql.
      const LINK_TTL = 365 * 24 * 3600;
      const linkExpiry = new Date(Date.now() + LINK_TTL * 1000);
      let linksResolved = 0, linksUnavailable = 0, linkErr: string | null = null;
      const blocks = rep.blocks;
      const wanted = new Set<number>();
      const collect = (v: unknown): void => {
        if (Array.isArray(v)) { for (const x of v) collect(x); return; }
        if (v && typeof v === 'object') {
          const o = v as Record<string, unknown>;
          if (typeof o.link_entry === 'number') wanted.add(o.link_entry);
          for (const x of Object.values(o)) collect(x);
        }
      };
      collect(blocks);
      const urlFor = new Map<number, string>();
      if (wanted.size) {
        try {
          const { data: docRows, error: dErr } = await admin.from('v_expense_documents')
            .select('id,doc_bucket,doc_path').in('id', [...wanted]);
          if (dErr) throw new Error(dErr.message);
          const withDoc = (docRows || []).filter((r: Record<string, unknown>) => !!r.doc_path);
          if (withDoc.length) {
            const bucket = String(withDoc[0].doc_bucket || 'receipt-files');
            const { data: signed, error: sErr } = await admin.storage.from(bucket)
              .createSignedUrls(withDoc.map((r: Record<string, unknown>) => String(r.doc_path)), LINK_TTL);
            if (sErr) throw new Error(sErr.message);
            const byPath = new Map((signed || []).map((s: Record<string, unknown>) => [String(s.path), s.signedUrl as string | null]));
            for (const r of withDoc) { const u = byPath.get(String(r.doc_path)); if (u) urlFor.set(Number(r.id), u); }
          }
        } catch (e) { linkErr = String((e as Error)?.message || e); }
      }
      // A mark that could not be signed LOSES its link and says so in the cell. The founder's own
      // condition for this document: a row that cannot be opened must read as such, never as a link
      // that goes nowhere.
      const resolveLinks = (v: unknown): void => {
        if (Array.isArray(v)) { for (const x of v) resolveLinks(x); return; }
        if (v && typeof v === 'object') {
          const o = v as Record<string, unknown>;
          if (typeof o.link_entry === 'number') {
            const u = urlFor.get(o.link_entry);
            if (u) { o.link = u; linksResolved++; }
            else { o.text = String(o.text ?? '') + ' (link unavailable)'; linksUnavailable++; }
            delete o.link_entry;
          }
          for (const x of Object.values(o)) resolveLinks(x);
        }
      };
      resolveLinks(blocks);
      if (Array.isArray(blocks) && wanted.size) {
        blocks.push({ t: 'note', text: linksResolved + ' link(s) above were signed on '
          + new Date().toISOString().slice(0, 10) + ' and stop working after '
          + linkExpiry.toISOString().slice(0, 10) + '. After that date the Record number in the first '
          + 'column is still the way to the document: public.fn_expense_document(<record>) names the '
          + 'bucket and the object, and this seat returns a fresh link for it on request. '
          + (linksUnavailable ? linksUnavailable + ' line(s) could not be signed and say so in the row. ' : '')
          + (linkErr ? 'The signing call reported: ' + linkErr + '. ' : '')
          + 'Nothing in this report stops being useful when the links expire.' });
      }

      const secret = await sec('cred_fn_accountant');
      // glyphs_dropped is carried through because ok:true alone cannot tell a correct document from
      // one rendered on the WinAnsi fallback with characters missing from a money line. It should
      // always be 0 here — strict_glyphs below makes pdf_native refuse rather than degrade — and
      // reporting the measured number is cheaper than trusting that it did.
      let pdf: { bucket: string | null; path: string | null; url: string | null; bytes: number | null; glyphs_dropped: number | null; links: number | null } =
        { bucket: null, path: null, url: null, bytes: null, glyphs_dropped: null, links: null };
      let pdfErr: string | null = null;
      if (!secret) {
        pdfErr = 'app_secrets.cred_fn_accountant is unreadable, so this seat could not authenticate to pdf_native.';
      } else {
        try {
          const r = await fetch(SUPA_URL + '/functions/v1/pdf_native', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              __secret: secret, title: String(rep.subject || 'Spend since day one'), blocks: rep.blocks,
              bucket: 'finance-reports', folder: 'accountant/spend',
              name: String(rep.doc_name || 'QuotesDone_Spend_Since_Day_One'),
              // strict_glyphs, because this is a financial statement: a character the font cannot
              // draw would otherwise vanish from a money line and the document would still say ok.
              options: { letterhead: true, strict_glyphs: true },
            }), signal: AbortSignal.timeout(55000),
          });
          const j = await r.json().catch(() => null);
          // THE PATH pdf_native RETURNS IS THE ONLY PATH. It names its own object (bucket + a
          // timestamped folder key); supplying one here and hoping they agree is how an attachment
          // reference comes to point at nothing.
          // `links` is what pdf_native ACTUALLY wrote as /Annot /Link dictionaries. Carried through
          // because "the seat resolved 45 links" and "the document has 45 clickable links" are two
          // different facts, and only the second one is the founder's request.
          if (r.ok && j?.ok && j?.path) pdf = { bucket: String(j.bucket || 'finance-reports'), path: String(j.path), url: j.url ?? null, bytes: j.bytes ?? null, glyphs_dropped: j.glyphs_dropped ?? null, links: j.links ?? null };
          else pdfErr = 'pdf_native ' + r.status + ': ' + JSON.stringify(j ?? {}).slice(0, 400);
        } catch (e) { pdfErr = 'pdf_native unreachable: ' + String((e as Error)?.message || e); }
      }

      let delivery: Record<string, unknown> | null = null;
      if (body.deliver === true) {
        if (!pdf.path) {
          delivery = { ok: false, reason: 'not delivered: the PDF did not render, and the founder asked for the report AS a document. ' + (pdfErr || '') };
        } else {
          const { data: delRaw, error: delErr } = await admin.rpc('fn_accountant_spend_report_deliver', {
            p_bucket: pdf.bucket, p_path: pdf.path, p_url: pdf.url, p_bytes: pdf.bytes,
            p_as_of: String(rep.as_of || ''), p_subject: String(rep.subject || ''), p_body: String(rep.body || ''),
          });
          delivery = delErr ? { ok: false, reason: 'fn_accountant_spend_report_deliver raised: ' + delErr.message } : (delRaw as Record<string, unknown>);
        }
      }

      await run('spend_report', pdfErr ? 'error' : 'ok', {
        as_of: rep.as_of ?? null, entries: (rep.figures as Record<string, unknown> | undefined)?.entries ?? null,
        pdf_path: pdf.path, delivered: delivery?.ok === true,
        links_in_pdf: pdf.links, links_resolved: linksResolved, links_unavailable: linksUnavailable,
      }, pdfErr ?? undefined);

      return J({
        ok: true, seat: 'accountant', caller: caller.kind,
        report: rep, pdf, pdf_error: pdfErr, delivery,
        links: { resolved: linksResolved, unavailable: linksUnavailable, in_pdf: pdf.links,
                 expires_at: linkExpiry.toISOString(), ttl_seconds: LINK_TTL, error: linkErr,
                 basis: 'Each Evidence cell the report marked with an expense id was signed against '
                   + 'the private receipt-files bucket. A cell that could not be signed prints '
                   + '"(link unavailable)" instead of a dead link, and every row carries the expense '
                   + 'record number, which does not expire.' },
        delivery_armed: body.deliver === true,
        note: body.deliver === true ? null : 'The document was rendered and stored. No mail was inserted: pass deliver:true to send it from this seat.',
      });
    }
}
