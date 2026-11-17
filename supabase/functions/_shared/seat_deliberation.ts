// seat_deliberation — the runner for a review between two seats on models of DIFFERENT families.
// Seat: it_engineer. 23 Sep 2026, founder_instruction 873 ("they shouldn't be on the same model").
//
// The rules live in the database (scripts/sql/a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql):
// fn_seat_deliberation_step decides the next model step, routes the reviewer to another family through
// fn_ai_route_review, builds the payload (blind first, proposal withheld) and records "held, not run" or
// "no independent reviewer" itself. This file only carries a call_model step to ai_gateway — with
// counterpart_model, so the gateway routes through fn_ai_route_review too — and hands the answer back to
// fn_seat_deliberation_record, whose trigger refuses a same-family turn or an approval with no steelman.
//
// INTERFACE FOR A SEAT'S BUILD (the marketing <-> ceo monthly plan debate, sales_engineer -> ceo, ...):
//   const { data: id } = await admin.rpc('fn_seat_deliberation_open', { p_kind, p_author_seat,
//     p_reviewer_seat, p_question, p_evidence, p_proposal, p_author_model });
//   await advanceDeliberation(admin, id);          // or leave it to the resilience_ping heartbeat
//   ... later, the AUTHOR seat: rpc('fn_seat_deliberation_close', { p_id: id, p_closed_by, p_outcome })
import { parseJson } from './model_json.ts';
// deno-lint-ignore no-explicit-any
type Admin = any;

export type ReviewOutput = Record<string, unknown> & { verdict?: string };

/** The model's reply as one JSON object, or null. Tolerates a ```json fence; nothing else. */
export function parseReviewOutput(text: string | null): ReviewOutput | null {
  return parseJson<ReviewOutput>(text, { exact: true });
}

/**
 * Advance one deliberation by at most `maxSteps` model steps (blind, then compare). Never throws:
 * a refusal by the database (malformed, same family) is recorded as a 'failed' turn with its reason.
 */
// THE REVIEWER SEES THE IMAGES, NOT THEIR PATHS. Evidence may carry storage paths of images under
// `key_frames` (paths in DEFAULT_IMAGE_BUCKET, the bucket name in front optional). The runner downloads them with the
// service role and sends them as image parts on the blind and the compare call alike (Sol and Opus both read
// images). Capped; a missing or oversized image is named in the text, never fatal.
// ponytail: 6 images of <= 1.5 MB each; raise when a real deliberation needs more.
export const DEFAULT_IMAGE_BUCKET = 'marketing-media';
export const MAX_IMAGES = 6;
export const MAX_IMAGE_BYTES = 1_500_000;
export const KEY_FRAME_PATH = /^features\/[0-9a-f]{64}\/[A-Za-z0-9_.-]+\.(jpg|jpeg|png|webp)$/;

export type ImagePart = { type: 'image_url'; image_url: { url: string } };

function b64(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

/** Download the evidence's key frames as image parts; returns the parts and what could not be attached. */
export async function evidenceImages(admin: Admin, evidence: unknown): Promise<{ parts: ImagePart[]; missing: string[] }> {
  const frames = (evidence as { key_frames?: unknown })?.key_frames;
  const paths = Array.isArray(frames) ? frames.filter((p): p is string => typeof p === 'string' && p.trim() !== '') : [];
  const parts: ImagePart[] = [];
  const missing: string[] = [];
  let tried = 0;
  for (const p of paths) {
    // ONLY A KEY FRAME THE SERVER PRODUCED: features/<sha256 of the asset>/<frame>.<image ext>, the bucket name in
    // front optional. Anything else ('..', '\\', '%', '//', a video, a foreign folder) is refused unread.
    // TODO(#876): also require the path to be in marketing_asset_feature's key-frame list once that table lands.
    const path = p.startsWith(DEFAULT_IMAGE_BUCKET + '/') ? p.slice(DEFAULT_IMAGE_BUCKET.length + 1) : p;
    if (!KEY_FRAME_PATH.test(path) || path.includes('..')) { missing.push(p + ' (not a server-produced key frame path; not read)'); continue; }
    if (++tried > MAX_IMAGES) { missing.push(p + ' (over the ' + MAX_IMAGES + '-image cap; not read)'); continue; }
    const slash = path.lastIndexOf('/');
    try {
      // Size and type from the object's metadata BEFORE anything is downloaded.
      const { data: ls, error: le } = await admin.storage.from(DEFAULT_IMAGE_BUCKET)
        .list(path.slice(0, slash), { search: path.slice(slash + 1), limit: 1 });
      const meta = (Array.isArray(ls) ? ls.find((o: { name?: string }) => o?.name === path.slice(slash + 1)) : null)?.metadata;
      if (le || !meta) { missing.push(p + ' (' + (le?.message ?? 'not found') + ')'); continue; }
      const size = Number(meta.size), type = String(meta.mimetype ?? '');
      if (!type.startsWith('image/')) { missing.push(p + ' (' + (type || 'unknown type') + ', not an image; not read)'); continue; }
      if (!(size > 0) || size > MAX_IMAGE_BYTES) { missing.push(p + ' (' + size + ' bytes, over the cap; not read)'); continue; }
      const { data, error } = await admin.storage.from(DEFAULT_IMAGE_BUCKET).download(path);
      if (error || !data) { missing.push(p + ' (' + (error?.message ?? 'not found') + ')'); continue; }
      const bytes = new Uint8Array(await data.arrayBuffer());
      if (bytes.length > MAX_IMAGE_BYTES) { missing.push(p + ' (' + bytes.length + ' bytes, over the cap)'); continue; }
      const mime = type;
      parts.push({ type: 'image_url', image_url: { url: `data:${mime};base64,${b64(bytes)}` } });
    } catch (e) { missing.push(p + ' (' + String((e as Error)?.message ?? e).slice(0, 80) + ')'); }
  }
  return { parts, missing };
}

// deno-lint-ignore no-explicit-any
type LlmFactory = (models: string[], def: any) => (sys: string, input: any, max?: number, stable?: string, opts?: any) => Promise<any>;

export async function advanceDeliberation(admin: Admin, id: number, maxSteps = 2, makeLlm?: LlmFactory): Promise<unknown[]> {
  const out: unknown[] = [];
  for (let i = 0; i < maxSteps; i++) {
    const { data: step, error } = await admin.rpc('fn_seat_deliberation_step', { p_id: id });
    if (error) { out.push({ ok: false, error: 'fn_seat_deliberation_step: ' + error.message }); break; }
    out.push({ action: step?.action, phase: step?.phase, why: step?.why });
    if (step?.action !== 'call_model') break;

    // Imported here, not at the top: llm.ts opens a client at load, and this file is tested without one.
    const factory: LlmFactory = makeLlm ?? (await import('./llm.ts')).makeLlmRich;
    const llm = factory([], {
      fn: 'resilience_ping', taskClass: step.task_class, agent: step.reviewer_seat, dept: step.dept,
      max: step.max_tokens, timeoutMs: 60_000, cacheTtlMin: 0,
    });
    const img = await evidenceImages(admin, step.payload?.evidence);
    const text = JSON.stringify(img.missing.length ? { ...step.payload, images_not_attached: img.missing } : step.payload);
    const r = await llm(step.system, text, step.max_tokens, '', {
      counterpartModel: step.counterpart_model,
      ...(img.parts.length ? { messages: [{ role: 'system', content: step.system },
                                           { role: 'user', content: [{ type: 'text', text }, ...img.parts] }] } : {}),
    });
    const record = (status: string, output: Record<string, unknown>, why: string | null) =>
      admin.rpc('fn_seat_deliberation_record', {
        p_id: id, p_phase: step.phase, p_model: r.model ?? step.model, p_output: output,
        p_status: status, p_why: why,
      });

    if (!r.used_llm || r.error || !r.content) {
      const held = /circuit_open|open-circuit|founder_hold/.test(String(r.error ?? ''));
      await record(held ? 'held_not_run' : 'failed', {}, (held ? 'held, not run: ' : 'no answer: ') + (r.error ?? 'empty'));
      break;
    }
    const parsed = parseReviewOutput(r.content);
    const { error: recErr } = parsed
      ? await record('recorded', { ...parsed, _payload_sha256: step.payload_sha256 }, null)
      : { error: { message: 'MALFORMED_REVIEW: the reply is not one JSON object' } };
    if (recErr) {
      await record('failed', { raw: String(r.content).slice(0, 4000) }, String(recErr.message).slice(0, 500));
      out.push({ ok: false, refused: String(recErr.message).slice(0, 200) });
      break;
    }
  }
  return out;
}

/** The heartbeat: open deliberations, least recently attempted first (fn_seat_deliberation_due), bounded. */
export async function advanceOpenDeliberations(admin: Admin, limit = 3): Promise<unknown> {
  const { data, error } = await admin.rpc('fn_seat_deliberation_due', { p_limit: limit });
  if (error) return { ok: false, error: 'fn_seat_deliberation_due: ' + error.message };
  const done: Record<string, unknown> = {};
  for (const id of (data ?? []) as number[]) done[id] = await advanceDeliberation(admin, id);
  return { advanced: Object.keys(done).length, steps: done };
}
