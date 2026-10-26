// licence_extract — the licence half of license_extract (the vision read of a UAE trade licence), as a module.
// Seat: sales_engineer. 7 Oct 2026, accuracy suite (ledger 1162).
//
// WHY A MODULE. The founder's gate is "not a single mistake in any trade licence". The accuracy suite
// (scripts/e2e/document_intake_accuracy.mjs --model gateway) must measure the EXACT request and normalisation the
// function sends, before a prompt change is deployed; a copy in the harness would measure itself. license_extract
// builds its licence request and reads its answer only through these functions.
//
// WHAT CHANGED WITH THE MOVE: the prompt now also asks for the Arabic legal name, the trade name and the legal form,
// which a UAE licence prints and the suite measures; nothing else in the request changed.

export const SYS_LICENSE = `You are a meticulous UAE corporate-registry document controller. You read an official UAE TRADE LICENCE (DED / DET / free-zone / e-trader) and extract its registration data EXACTLY as printed. Read every line; do not guess. Return STRICT JSON only:\n{"legal_name":string,"legal_name_ar":string,"trade_name":string,"legal_form":string,"license_number":string,"license_authority":string,"emirate":string,"city":string,"issue_date":"YYYY-MM-DD","expiry_date":"YYYY-MM-DD","activities":[string],"trn":string,"confidence":"low"|"medium"|"high"}\nlegal_name = the exact licensed company / establishment name as printed in ENGLISH; if the licence prints no English name, an empty string (never a translation or transliteration). legal_name_ar = the name as printed in Arabic, else ''. trade_name = the trade name as printed, else ''. legal_form = the legal form / legal type / legal status as printed (e.g. 'Limited Liability Company', 'Free Zone Establishment'). license_number = the licence / register number exactly as printed. license_authority = issuing authority as printed (e.g. 'Dubai Department of Economy and Tourism', 'Sharjah Economic Development Department', 'Jebel Ali Free Zone Authority'). emirate = one of Dubai, Abu Dhabi, Sharjah, Ajman, Umm Al Quwain, Ras Al Khaimah, Fujairah. city = city/area if shown else the emirate. activities = the listed business activities, each exactly as printed. trn = VAT TRN if present else ''. Dates as printed, output YYYY-MM-DD (UAE dates are day-first). If a value is not visible use an empty string and lower the confidence. This is NOT a tax/AML check - it is commercial onboarding verification only.`;

/** null = no usable object (a 502 with a named error, never a blank doc: 9 Sep 2026). */
export function parseJson(t: string): Record<string, unknown> | null {
  const take = (s: string) => { try { const v = JSON.parse(s); return (v && typeof v === 'object' && !Array.isArray(v)) ? v as Record<string, unknown> : null; } catch { return null; } };
  return take(t) ?? (t.match(/\{[\s\S]*\}/) ? take(t.match(/\{[\s\S]*\}/)![0]) : null);
}
const dataUrl = (b64: string, mime: string) => `data:${mime};base64,${String(b64).replace(/^data:[^;]+;base64,/, '')}`;
export function normDate(s: unknown): string | null {
  const v = String(s || '').trim(); if (!v) return null;
  let m = v.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$/);
  if (m) { const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])); return isNaN(d.getTime()) ? null : `${m[1]}-${String(m[2]).padStart(2, '0')}-${String(m[3]).padStart(2, '0')}`; }
  m = v.match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$/);
  if (m) return `${m[3]}-${String(m[2]).padStart(2, '0')}-${String(m[1]).padStart(2, '0')}`;
  const d = new Date(v); return isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10);
}
const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'];
export function normEmirate(s: unknown): string {
  const t = String(s || '').toLowerCase();
  for (const e of EMIRATES) if (t.includes(e.toLowerCase())) return e;
  if (/rak/.test(t)) return 'Ras Al Khaimah'; if (/uaq|umm al/.test(t)) return 'Umm Al Quwain'; if (/auh|abu/.test(t)) return 'Abu Dhabi';
  return '';
}

// deno-lint-ignore no-explicit-any
export function documentContent(intro: string, images: any[], body: { file_b64?: string; mime?: string; filename?: string }): any[] {
  // deno-lint-ignore no-explicit-any
  const content: any[] = [{ type: 'text', text: intro }];
  if (Array.isArray(images) && images.length) {
    for (const im of images.slice(0, 10)) { const b = im?.b64 || im; const m = im?.mime || 'image/jpeg'; if (b) content.push({ type: 'image_url', image_url: { url: dataUrl(String(b), String(m)) } }); }
  } else if (body.file_b64) {
    const mime = String(body.mime || 'application/octet-stream');
    if (/^image\//.test(mime)) content.push({ type: 'image_url', image_url: { url: dataUrl(String(body.file_b64), mime) } });
    else content.push({ type: 'file', file: { filename: String(body.filename || 'document.pdf'), file_data: dataUrl(String(body.file_b64), mime || 'application/pdf') } });
  }
  return content;
}

/** The ai_gateway body for one licence (no caller-side `max`: model_policy.document_extraction decides it). */
// deno-lint-ignore no-explicit-any
export function licenceExtractRequest(payload: { images?: any[]; file_b64?: string; mime?: string; filename?: string }, subject: unknown) {
  return { fn: 'license_extract', subject: subject ?? null, temperature: 0.1, sys: SYS_LICENSE,
    input: [{ role: 'user', content: documentContent('Read the attached UAE trade licence (all pages) and return the extraction JSON.', payload.images || [], payload) }] };
}

/** A licence number a model makes up when it sees none: one digit repeated, or a straight run (123456, 654321). */
export function placeholderLicenceNo(v: unknown): boolean {
  const t = String(v ?? '').trim();
  if (!/^\d{4,}$/.test(t)) return false;
  if (/^(\d)\1+$/.test(t)) return true;
  return '01234567890123456789'.includes(t) || '98765432109876543210'.includes(t);
}

/** The model's object -> the licence doc every caller reads.
 *
 * NOTHING UNGROUNDED IS A READING (12 Oct 2026, stage-2 run 3 S02, sales_engineer). A 1x1 PNG went to the
 * vision model and came back with expiry 2023-03-14 and licence number 123456 (ai_cost_log 19449, lead 143063);
 * supplier_api wrote both and the review held the supplier as licence_expired off a date no document printed.
 * Every UAE licence prints the licensee's name, so a read with no name in either language, or one the model
 * itself calls 'low', saw no licence: it yields NO fields at all (unreadable: true) and callers write nothing.
 * A placeholder number (123456, 000000) is dropped even from an otherwise named read. */
export function normaliseLicence(ai: Record<string, unknown>) {
  const s = (v: unknown, n: number) => String(v ?? '').trim().slice(0, n);
  const named = /\p{L}{2}/u.test(s(ai.legal_name, 200)) || /\p{L}{2}/u.test(s(ai.legal_name_ar, 200));
  if (!named || String(ai.confidence) === 'low') {
    return { legal_name: '', legal_name_ar: '', trade_name: '', legal_form: '', license_number: '', license_authority: '', emirate: '',
             city: '', issue_date: null as string | null, expiry_date: null as string | null, activities: [] as string[], trn: '',
             confidence: 'low', unreadable: true };
  }
  const emirate = normEmirate(ai.emirate || ai.city);
  return {
    legal_name: s(ai.legal_name, 200), legal_name_ar: s(ai.legal_name_ar, 200), trade_name: s(ai.trade_name, 200), legal_form: s(ai.legal_form, 120),
    license_number: placeholderLicenceNo(ai.license_number) ? '' : s(ai.license_number, 60), license_authority: s(ai.license_authority, 160), emirate,
    city: s(ai.city || ai.emirate, 80) || emirate, issue_date: normDate(ai.issue_date), expiry_date: normDate(ai.expiry_date),
    activities: Array.isArray(ai.activities) ? ai.activities.map((x) => String(x).slice(0, 120)).slice(0, 20) : [],
    trn: String(ai.trn || '').replace(/\D/g, '').slice(0, 15),
    confidence: ['low', 'medium', 'high'].includes(String(ai.confidence)) ? String(ai.confidence) : 'low', unreadable: false,
  };
}

/** A gateway answer -> { ok, doc } or { ok:false, error } exactly as license_extract answers its callers. */
// deno-lint-ignore no-explicit-any
export function licenceFromGateway(httpOk: boolean, jd: any): { ok: true; doc: ReturnType<typeof normaliseLicence> } | { ok: false; error: string; detail?: string } {
  if (!httpOk || jd?.ok === false) return { ok: false, error: 'ai_error', detail: String(jd?.detail || jd?.error || JSON.stringify(jd)).slice(0, 300) };
  if (jd?.truncated === true || jd?.finish_reason === 'length') return { ok: false, error: 'extract_truncated' };
  const parsed = parseJson(String(jd?.content ?? ''));
  if (!parsed) return { ok: false, error: 'extract_unreadable' };
  return { ok: true, doc: normaliseLicence(parsed) };
}
