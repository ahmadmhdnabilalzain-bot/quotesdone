// THE REDACTED DRAWING PAGES A SUPPLIER IS SERVED (18 Sep 2026, agent: sales_engineer).
//
// THE DEFECT THIS FILE EXISTS FOR. supplier_api's `inbox` signed each path in
// inquiries.drawing_redacted_paths with a helper that returned null on any error and swallowed it, and
// the caller pushed the URL only `if (u)`. A page that failed to sign was therefore DROPPED: the
// supplier saw an inquiry with fewer drawings — or none at all — and nothing anywhere recorded that a
// page was meant to be there. Measured on production by driving scripts/e2e/supplier_quote_review.mjs
// four times: one whole run served ZERO pages for all four inquiries while the rows were correct and
// the objects had uploaded successfully (uploadObject throws on a failed upload and did not throw).
// The next run on an idle machine served them normally. A supplier inside that window would have priced
// a villa painting job from the BOQ alone, not knowing drawings existed.
//
// createSignedUrl does NOT throw on an API error — it answers `{ data: null, error }` — so the old
// try/catch was not even the path that fired. The error was simply never read.
//
// WHAT THIS DOES INSTEAD. Every page that signs is still served: one bad page never costs the others.
// Each inquiry carries expected / served / failed, so a zero is readable — the founder's rule that a
// guard which cannot tell a broken system from an idle one is worse than no guard. `expected: 0` means
// this inquiry had no drawings; `expected: 3, served: 3, failed: 0` means three were meant to be there
// and three arrived. The failures are logged (path and the storage client's message — never a signed
// URL, a token or a key) and raised ONCE per request as an IT engineer finding under a single
// deduplicated issue key, so a recurrence is visible after the fact and not only in a log line.
// deno-lint-ignore-file no-explicit-any

/**
 * THE CUSTOMER ATTACHED A FILE THE SUPPLIER CANNOT BE SHOWN (22 Sep 2026). A held drawing — or any CAD file,
 * which is never pictured for a supplier — carries an original and no redacted page. The supplier was told
 * nothing, and priced as if no drawing existed. True means "say so": the portal words it in EN and AR.
 */
export const drawingWithheld = (hasOriginal: boolean, redactedPages: number) => hasOriginal && redactedPages === 0;

/** The one dedupe identity for this fault. One key, not one per inquiry: the subject is the signing. */
export const DRAWING_SIGN_ISSUE = 'supplier_inbox:drawing_page_sign_failed';

/** Per inquiry, so the client can say "N drawing pages could not be opened" instead of showing nothing. */
export type InquiryPages = { urls: string[]; expected: number; served: number; failed: number };

const SIGNED_SECONDS = 3600;
const MAX_SAMPLES = 5;
// A HANG IS A FAILURE, NOT A WAIT (review, 18 Sep 2026). createSignedUrl does not throw on an API
// error and a stalled socket never resolves at all, so without a deadline one bad page would hold the
// whole inbox response open instead of degrading to "1 page could not be opened". A timeout is counted,
// logged and raised exactly like any other signing failure.
const SIGN_TIMEOUT_MS = 8000;

// The storage client's messages are static text today ("Object not found"), but this message is written
// into it_engineer_finding and that is emailed to the founder. Anything token-shaped is taken out before
// it is recorded, so the log can never become the leak (security review, 18 Sep 2026).
const safeMessage = (m: unknown) => String(m).replace(/(token|jwt|apikey|key|signature)=[^\s&]+/gi, '$1=[removed]').slice(0, 200);

async function signOne(admin: any, path: string): Promise<{ url: string | null; error: string | null }> {
  let timer: ReturnType<typeof setTimeout> | null = null;
  try {
    const signing = admin.storage.from('drawing-files').createSignedUrl(path, SIGNED_SECONDS);
    const deadline = new Promise<never>((_r, reject) => {
      timer = setTimeout(() => reject(new Error('signing timed out after ' + SIGN_TIMEOUT_MS + 'ms')), SIGN_TIMEOUT_MS);
    });
    const { data, error } = await Promise.race([signing, deadline]) as { data: any; error: any };
    if (error) return { url: null, error: String(error?.message || error) };
    return data?.signedUrl ? { url: String(data.signedUrl), error: null } : { url: null, error: 'storage returned no signed URL' };
  } catch (e) {
    return { url: null, error: String((e as Error)?.message || e) };
  } finally {
    if (timer !== null) clearTimeout(timer);
  }
}

/**
 * Sign every redacted page of every inquiry on one inbox page.
 * Returns a map keyed by String(inquiry id). Raises at most one finding for the whole request.
 */
export async function signRedactedDrawings(
  admin: any,
  rows: { id: unknown; paths: unknown }[],
): Promise<Record<string, InquiryPages>> {
  const out: Record<string, InquiryPages> = {};
  let expected = 0, served = 0, failed = 0;
  const samples: { path: string; message: string }[] = [];
  const perInquiry: { inquiry_id: string; expected: number; failed: number }[] = [];

  for (const row of rows) {
    const key = String(row.id);
    const paths = (Array.isArray(row.paths) ? row.paths : []).map((p) => String(p));
    const entry: InquiryPages = { urls: [], expected: paths.length, served: 0, failed: 0 };
    for (const p of paths) {
      const r = await signOne(admin, p);
      if (r.url) { entry.urls.push(r.url); entry.served++; continue; }
      entry.failed++;
      // The PATH and the message only. A signed URL carries a token and must never be logged.
      console.error('supplier inbox: a redacted drawing page could not be signed - path=' + p + ' error=' + safeMessage(r.error));
      if (samples.length < MAX_SAMPLES) samples.push({ path: p, message: safeMessage(r.error) });
    }
    out[key] = entry;
    expected += entry.expected; served += entry.served; failed += entry.failed;
    if (entry.failed > 0) perInquiry.push({ inquiry_id: key, expected: entry.expected, failed: entry.failed });
  }

  if (failed > 0) await raiseFinding(admin, { expected, served, failed, perInquiry, samples });
  return out;
}

async function raiseFinding(admin: any, m: {
  expected: number; served: number; failed: number;
  perInquiry: { inquiry_id: string; expected: number; failed: number }[];
  samples: { path: string; message: string }[];
}) {
  const title = m.failed + ' of ' + m.expected + ' redacted drawing page(s) could not be signed for a supplier inbox ('
    + m.served + ' served, ' + m.perInquiry.length + ' inquir(y/ies) affected)';
  try {
    const { error } = await admin.rpc('fn_it_engineer_finding_upsert', {
      p_issue_key: DRAWING_SIGN_ISSUE,
      p_title: title,
      p_where: "supabase/functions/supplier_api/index.ts action 'inbox', via _shared/drawing_pages.ts (storage bucket drawing-files)",
      // customer_facing: a supplier who cannot see the drawings prices the job from the BOQ alone, and
      // the quotation the customer compares is wrong. affected > 0 makes it critical, which is correct —
      // it fires only when a page that was meant to be served was not.
      p_blast: 'customer_facing',
      p_affected: m.failed,
      p_evidence: {
        subject: 'supplier_inbox_drawings', owner_seat: 'sales_engineer', demo: false,
        pages_expected: m.expected, pages_served: m.served, pages_failed: m.failed,
        inquiries_affected: m.perInquiry.length, per_inquiry: m.perInquiry, sample_errors: m.samples,
        why: 'storage createSignedUrl did not return a URL; the pages that did sign were still served',
      },
      p_raised_by: 'sales_engineer',
    });
    if (error) await findingUnavailable(admin, m, String(error.message || error));
  } catch (e) {
    await findingUnavailable(admin, m, String((e as Error)?.message || e));
  }
}

// THE FINDING PATH ITSELF CAN BE THE BROKEN THING (review, 18 Sep 2026). If fn_it_engineer_finding_upsert
// is unreachable, logging and moving on would put this fault back exactly where it started: visible only
// in a log line nobody reads. A second, queryable trail goes into agent_runs - the same shape supplier_api
// already writes when the inquiry owner cannot be read. It never blocks the response.
async function findingUnavailable(admin: any, m: { expected: number; served: number; failed: number }, reason: string) {
  console.error('drawing_pages: the IT engineer finding could not be opened -', reason);
  try {
    await admin.from('agent_runs').insert({
      agent: 'sales_engineer', status: 'error', started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
      counts: { signal: 'drawing_page_sign_failed', pages_expected: m.expected, pages_served: m.served, pages_failed: m.failed, finding_unavailable: 1 },
      note: ('supplier inbox: ' + m.failed + ' of ' + m.expected + ' redacted drawing page(s) could not be signed, and the IT '
        + 'engineer finding could not be opened either. Reason: ' + reason).slice(0, 500),
    });
  } catch (e) {
    console.error('drawing_pages: the agent_runs trail could not be written either -', String((e as Error)?.message || e));
  }
}
