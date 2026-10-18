// marketing_judgement — THE ONE PLACE a marketing-seat model step is run. (The CEO's review of the monthly plan is
// NOT here: it is a seat_deliberation on another model family, founder_instruction 873 — see the SQL file's adapter.)
// marketing, 23 Sep 2026; founder instructions 865, 866, 867.
// scripts/sql/the_marketing_seat_watches_its_videos_studies_the_market_and_argues_its_month_with_the_ceo.sql
//
// Every step is the same three parts, so a model answer can only ever land in a table:
//   1. fn_marketing_step_request(step, subject)  — the measured input, the output schema, the class, the cap
//   2. the founder's hold is asked FIRST (llm_hold.ts). Held -> fn_marketing_step_accept(..., 'held') records ONE
//      "held, not run" row per step, subject and day, and nothing else is written. No gateway round trip.
//   3. ONE gateway call through _shared/llm.ts with the step's own task_class and dept 'marketing' (the ceiling),
//      then fn_marketing_step_accept validates the JSON and writes the step's table, or records why not.
// The seat is checked twice: here and in the accept routine.
//
// WATCHING (867). gpt-5.6-sol cannot hear or watch video, so the 'watch' step sends the WHOLE master (with its
// soundtrack) to marketing_watch (google/gemini-3.8-flash) as a base64 data URL — OpenRouter's Gemini providers
// take no arbitrary video URL — and the judgement ('quality_review') gets the perception row plus key frames as
// images (signed URLs, which sol can read).

// deno-lint-ignore no-explicit-any
type Admin = any;
export type Seat = 'marketing';
export type Step = 'watch' | 'quality_review' | 'research' | 'evaluate' | 'plan' | 'plan_defend';

/** step -> who runs it, its model_policy class, and the table its answer lands in. The check
 *  scripts/checks/every_marketing_model_output_lands_in_a_table.test.mjs reads this map. */
export const STEPS: Record<Step, { seat: Seat; taskClass: string; table: string }> = {
  watch:          { seat: 'marketing', taskClass: 'marketing_watch',          table: 'marketing_asset_perception' },
  quality_review: { seat: 'marketing', taskClass: 'marketing_quality_review', table: 'marketing_asset_review' },
  research:       { seat: 'marketing', taskClass: 'marketing_research',       table: 'marketing_insight_note' },
  evaluate:       { seat: 'marketing', taskClass: 'marketing_evaluate',       table: 'marketing_month_plan' },
  plan:           { seat: 'marketing', taskClass: 'marketing_plan',           table: 'marketing_plan_review_turn' },
  plan_defend:    { seat: 'marketing', taskClass: 'marketing_plan_defend',    table: 'marketing_plan_review_turn' },
};

export const MAX_VIDEO_BYTES = 8 * 1024 * 1024; // the 12 masters are 3.0-4.1 MB; a bigger file is refused, not sent

export interface ModelAnswer { content: string | null; error: string | null; truncated: boolean; model?: string | null; cost_usd?: number | null }
// deno-lint-ignore no-explicit-any
export type CallModel = (taskClass: string, max: number, messages: any[], requireCaps: string[]) => Promise<ModelAnswer>;
export interface Deps {
  admin: Admin;
  held: () => Promise<boolean>;
  callModel: CallModel;
  /** bytes of a stored object (the video); injectable so a test never touches storage */
  download?: (bucket: string, path: string) => Promise<Uint8Array>;
  /** a short-lived URL for a stored image (a key frame) */
  signedUrl?: (bucket: string, path: string) => Promise<string | null>;
}

export function parseAnswer(text: string | null): Record<string, unknown> | null {
  if (!text) return null;
  try {
    const v = JSON.parse(text.trim().replace(/^```(?:json)?\s*|\s*```$/g, ''));
    return v && typeof v === 'object' && !Array.isArray(v) ? v : null;
  } catch { return null; }
}

function b64(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

// deno-lint-ignore no-explicit-any
async function messagesFor(deps: Deps, req: any): Promise<any[]> {
  // deno-lint-ignore no-explicit-any
  const parts: any[] = [{ type: 'text', text: JSON.stringify({ output_schema: req.output_schema, input: req.input }) }];
  if (req.video) {
    if (!deps.download) throw new Error('no downloader for the video');
    if (Number(req.video.bytes) > MAX_VIDEO_BYTES) throw new Error(`video ${req.video.path} is ${req.video.bytes} bytes, above ${MAX_VIDEO_BYTES}`);
    const bytes = await deps.download(req.video.bucket, req.video.path);
    parts.push({ type: 'video_url', video_url: { url: 'data:video/mp4;base64,' + b64(bytes) } });
  }
  for (const k of (req.images || []) as Array<{ bucket?: string; path?: string }>) {
    if (!k?.path || !deps.signedUrl) continue;
    const url = await deps.signedUrl(k.bucket || 'marketing-media', k.path);
    if (url) parts.push({ type: 'image_url', image_url: { url } });
  }
  return [{ role: 'system', content: String(req.system) }, { role: 'user', content: parts }];
}

export async function runStep(deps: Deps, seat: Seat, step: Step, subject: string): Promise<Record<string, unknown>> {
  const def = STEPS[step];
  if (!def) throw new Error('unknown marketing step ' + step);
  if (def.seat !== seat) throw new Error(`step ${step} belongs to ${def.seat}, not ${seat}`);
  const accept = async (output: unknown, outcome: string, reason: string | null, model: string | null = null) => {
    const { data, error } = await deps.admin.rpc('fn_marketing_step_accept', {
      p_step: step, p_subject: subject, p_seat: seat, p_output: output, p_outcome: outcome, p_reason: reason, p_model: model });
    if (error) throw new Error('fn_marketing_step_accept: ' + error.message);
    return data as Record<string, unknown>;
  };

  if (await deps.held()) return { step, subject, ...(await accept(null, 'held', 'the founder\'s model hold is on (llm_route_health)')) };

  const { data: req, error } = await deps.admin.rpc('fn_marketing_step_request', { p_step: step, p_subject: subject });
  if (error || !req) throw new Error('fn_marketing_step_request: ' + (error?.message || 'nothing'));
  // deno-lint-ignore no-explicit-any
  const r = req as any;
  if (r.task_class !== def.taskClass) throw new Error(`request class ${r.task_class} is not ${def.taskClass}`);
  // THE TRENDS FEED THE PLAN (24 Sep 2026, GAPS.md marketing gap 3): the relevant trends think() judged, each with
  // its "why it matters" line (fn_marketing_trends_for_plan), go into the plan and its defence as input.
  if ((step === 'plan' || step === 'plan_defend') && r.input && typeof r.input === 'object') {
    const { data: trends } = await deps.admin.rpc('fn_marketing_trends_for_plan', { p_month: r.input.month });
    r.input.trends = trends ?? [];
  }

  let msgs;
  try { msgs = await messagesFor(deps, r); }
  catch (e) { return { step, subject, ...(await accept(null, 'failed', 'input: ' + String((e as Error).message).slice(0, 300))) }; }

  const ans = await deps.callModel(def.taskClass, Number(r.max_tokens) || 2000, msgs, (r.require_caps || []) as string[]);
  // The gateway enforces the hold too; a race with a hold that closed after our check is still "held".
  if (ans.error && /circuit_open|held/i.test(ans.error)) return { step, subject, ...(await accept(null, 'held', ans.error)) };
  if (ans.error) return { step, subject, ...(await accept(null, 'failed', ans.error, ans.model ?? null)) };
  if (ans.truncated) return { step, subject, ...(await accept(null, 'rejected', 'the answer was truncated at the token cap', ans.model ?? null)) };
  const out = parseAnswer(ans.content);
  return { step, subject, ...(await accept(out, out ? 'answered' : 'rejected', out ? null : 'the answer was not a JSON object', ans.model ?? null)) };
}
