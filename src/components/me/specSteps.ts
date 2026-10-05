// The held request's missing specs, asked ONE AT A TIME in plain words (sales_engineer, 5 Oct 2026; T2 spec helper).
// Pure step logic, no React, so its rules are checked: src/components/me/specSteps.test.mjs.
//
// Each missing spec (customer_api missing_specs -> fn_inquiry_missing_specs) becomes one step. A spec with options
// is multiple choice; "Other" (or a spec without options) takes typed words. "Not sure" is always offered: it records
// nothing (the server's _rfq_answered refuses "not sure" too), so the request stays held for that spec and the
// sales engineer follows it up, rather than a guess reaching suppliers. Only real answers are sent.
export type MissingSpec = { key: string; ask: string; type?: string; options?: string[] };
export const NOT_SURE = '__not_sure__';
export const OTHER = '__other__';

const isOther = (o: string) => /^other\b/i.test(String(o).trim());

/** The choices one step offers: the spec's options (an "Other" option becomes typed words), then "not sure". */
export function choicesFor(m: MissingSpec): string[] {
  const opts = (Array.isArray(m.options) ? m.options : []).map(String).filter((o) => o.trim());
  const listed = opts.filter((o) => !isOther(o));
  return [...listed, ...(listed.length ? [OTHER] : []), NOT_SURE];
}

/** Whether a step needs typed words: no options at all, or the customer chose "Other". */
export const needsText = (m: MissingSpec, pick: string | undefined) => !choicesFor(m).some((c) => c !== NOT_SURE && c !== OTHER) || pick === OTHER;

/** The answer one step contributes, or null when it contributes nothing (not sure, or nothing chosen/typed). */
export function answerOf(m: MissingSpec, pick: string | undefined, text: string | undefined): string | null {
  if (pick === NOT_SURE) return null;
  if (needsText(m, pick)) { const v = String(text || '').trim().slice(0, 300); return v || null; }
  return pick && choicesFor(m).includes(pick) ? pick : null;
}

/** A step may move on once something is chosen (not sure counts) or typed. */
export const stepDone = (m: MissingSpec, pick: string | undefined, text: string | undefined) =>
  pick === NOT_SURE || answerOf(m, pick, text) !== null;

/** The keyed answers to send: real answers only, never "not sure". */
export function collectAnswers(missing: MissingSpec[], picks: Record<string, string>, texts: Record<string, string>) {
  const out: Record<string, string> = {};
  for (const m of missing) { const a = answerOf(m, picks[m.key], texts[m.key]); if (a !== null) out[m.key] = a; }
  return out;
}

/** The keys the customer answered "not sure": each opens a handoff to the sales engineer (customer_api add_missing_specs). */
export const notSureKeys = (missing: MissingSpec[], picks: Record<string, string>) =>
  missing.filter((m) => picks[m.key] === NOT_SURE).map((m) => m.key);

/** What an option's button SHOWS: Arabic for an Arabic customer when a label exists. Display only, never the saved value. */
export const optionLabel = (o: string, lang: string, ar: Record<string, string>) => (lang === 'ar' && ar[o]) || o;
