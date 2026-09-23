// WHAT IS TOO BIG TO PARSE IS REFUSED BEFORE IT IS PARSED (22 Sep 2026, it_engineer, CONN-06).
//
// WHAT WAS MEASURED. drawing_boq and drawing_redact hit the edge runtime's CPU cap — HTTP 546, 546
// seconds of CPU across the sampled window — decoding and parsing whatever base64 arrived in the
// request. There was no ceiling anywhere: customer_api caps the number of PAGES it forwards (8 images
// a call, 4 PDF pages a batch) and nothing capped their SIZE. A CPU kill is the worst way to fail
// here, because it takes the isolate with it: no catch runs, no row is updated, no finding is raised.
// The estate has already recorded that property — "an edge function has a CPU cap a deadline does not
// bound" — from #686, where 546 kills left a job hung silently.
//
// 24 MB DECODED. The drawing buckets and the attachment policy already cap a stored object at 25 MB
// (_shared/safe_url.ts safeFetch's default, and send_outbox's 20 MB attachment ceiling), so a drawing
// larger than this could not have been stored in the first place; this refuses it at the parse instead
// of discovering it at the CPU cap. base64 inflates by 4/3, so the character ceiling is 32 MB.
//
// THE REFUSAL IS BILINGUAL because the customer sees it. Everything else this estate says to a
// customer is in their registered language, and a refusal is the message most likely to be read.
export const MAX_PARSE_BYTES = 24 * 1024 * 1024;
const MAX_B64_CHARS = Math.ceil(MAX_PARSE_BYTES * 4 / 3);

/** The decoded size of a base64 string (or data URL), without decoding it. */
export function b64Bytes(s: unknown): number {
  const t = typeof s === 'string' ? s.replace(/^data:[^;]+;base64,/, '') : '';
  if (!t) return 0;
  const pad = t.endsWith('==') ? 2 : t.endsWith('=') ? 1 : 0;
  return Math.max(0, Math.floor(t.length * 3 / 4) - pad);
}

export type ParseRefusal = { error: string; detail: string; detail_ar: string; bytes: number; cap: number };

/**
 * null when the inputs fit; otherwise the refusal to answer with, in both languages. `fields` may hold
 * strings, arrays of strings, or objects with a base64-bearing property — anything else counts as 0.
 */
export function tooLargeToParse(fields: unknown[]): ParseRefusal | null {
  let bytes = 0;
  const add = (v: unknown): void => {
    if (typeof v === 'string') { bytes += b64Bytes(v); return; }
    if (Array.isArray(v)) { for (const x of v) add(x); return; }
    if (v && typeof v === 'object') for (const x of Object.values(v as Record<string, unknown>)) if (typeof x === 'string') bytes += b64Bytes(x);
  };
  for (const f of fields) add(f);
  if (bytes <= MAX_PARSE_BYTES) return null;
  const mb = (n: number) => Math.round(n / (1024 * 1024));
  return {
    error: 'input_too_large_to_parse',
    bytes, cap: MAX_PARSE_BYTES,
    detail: `This drawing is ${mb(bytes)} MB, over the ${mb(MAX_PARSE_BYTES)} MB we can read in one request. `
      + 'Please send it as fewer pages, or export it at a lower resolution, and we will read it straight away.',
    detail_ar: `حجم هذا المخطط ${mb(bytes)} ميغابايت، وهو أكبر من ${mb(MAX_PARSE_BYTES)} ميغابايت التي يمكننا قراءتها في طلب واحد. `
      + 'يرجى إرساله على صفحات أقل، أو تصديره بدقة أقل، وسنقوم بقراءته فوراً.',
  };
}

/** The character ceiling, exported so a caller can refuse before it even builds the string. */
export { MAX_B64_CHARS };
