// artifact_review — the reviewing agent looks at the ACTUAL rendered artifact.
//
// A design agent that approves its own work from the brief approves the brief, not the
// design. So this fetches the bytes, measures what can be measured without a model
// (dimensions, aspect ratio, format, file size, platform crop, safe zone), and only then
// shows the image to a vision model for the judgements that need eyes. The review is
// anchored to the sha256 of those bytes: regenerate the image and the publish gate says
// unreviewed, because it is.
//
//   POST { __secret, subject_type, subject_id, artifact_url, platform?, kind?,
//          author_agent?, reviewer_agent?, expect? }
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';

// Dimensions straight from the container header. No decoder, no dependency: PNG carries
// width and height in the IHDR chunk, JPEG in the first SOFn marker, GIF and WEBP in their
// own fixed offsets. If the bytes are not one of these the reviewer says so rather than
// guessing, because a wrong dimension would fail a real design for an imagined reason.
function measure(buf: Uint8Array): { mime: string; width: number; height: number } | null {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  if (buf.length > 24 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) {
    return { mime: 'image/png', width: dv.getUint32(16), height: dv.getUint32(20) };
  }
  if (buf.length > 10 && buf[0] === 0xff && buf[1] === 0xd8) {
    let i = 2;
    while (i + 9 < buf.length) {
      if (buf[i] !== 0xff) { i++; continue; }
      const m = buf[i + 1];
      if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) {
        return { mime: 'image/jpeg', height: dv.getUint16(i + 5), width: dv.getUint16(i + 7) };
      }
      i += 2 + dv.getUint16(i + 2);
    }
    return null;
  }
  if (buf.length > 10 && buf[0] === 0x47 && buf[1] === 0x49 && buf[2] === 0x46) {
    return { mime: 'image/gif', width: buf[6] | (buf[7] << 8), height: buf[8] | (buf[9] << 8) };
  }
  if (buf.length > 30 && String.fromCharCode(...buf.slice(0, 4)) === 'RIFF'
      && String.fromCharCode(...buf.slice(8, 12)) === 'WEBP'
      && String.fromCharCode(...buf.slice(12, 16)) === 'VP8X') {
    return {
      mime: 'image/webp',
      width: 1 + (buf[24] | (buf[25] << 8) | (buf[26] << 16)),
      height: 1 + (buf[27] | (buf[28] << 8) | (buf[29] << 16)),
    };
  }
  return null;
}

// ── video ───────────────────────────────────────────────────────────────────────────────────
// MP4 and MOV are box structures: [4-byte size][4-byte type][payload]. Duration lives in
// moov/mvhd and the display size in the video track's tkhd matrix, both as plain integers, so
// the real dimensions and the real runtime can be read without decoding a single frame. WebM
// is EBML and is reported honestly as unmeasured rather than guessed at.
export type VideoFacts = { mime: string; width: number; height: number; duration_s: number | null; container: string };

function readBoxes(buf: Uint8Array, start: number, end: number, want: string): { off: number; end: number } | null {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  let i = start;
  while (i + 8 <= end) {
    let size = dv.getUint32(i);
    const type = String.fromCharCode(buf[i + 4], buf[i + 5], buf[i + 6], buf[i + 7]);
    let head = 8;
    if (size === 1) { size = Number(dv.getBigUint64(i + 8)); head = 16; }   // 64-bit extended size
    else if (size === 0) size = end - i;                                     // runs to the end
    if (size < head) return null;
    if (type === want) return { off: i + head, end: i + size };
    i += size;
  }
  return null;
}

function measureVideo(buf: Uint8Array): VideoFacts | null {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const ascii = (a: number, b: number) => String.fromCharCode(...buf.slice(a, b));
  if (buf.length > 32 && String.fromCharCode(0x1a, 0x45, 0xdf, 0xa3) === ascii(0, 4).slice(0, 4)) {
    // EBML — WebM/Matroska. Do not invent numbers we cannot read.
    return { mime: 'video/webm', width: 0, height: 0, duration_s: null, container: 'webm (dimensions not read)' };
  }
  if (!(buf.length > 32 && ascii(4, 8) === 'ftyp')) return null;
  const brand = ascii(8, 12);
  const mime = /qt/i.test(brand) ? 'video/quicktime' : 'video/mp4';

  const moov = readBoxes(buf, 0, buf.length, 'moov');
  if (!moov) return { mime, width: 0, height: 0, duration_s: null, container: brand + ' (no moov: not seekable, likely truncated)' };

  let duration: number | null = null;
  const mvhd = readBoxes(buf, moov.off, moov.end, 'mvhd');
  if (mvhd) {
    const v = buf[mvhd.off];
    const ts = v === 1 ? dv.getUint32(mvhd.off + 20) : dv.getUint32(mvhd.off + 12);
    const du = v === 1 ? Number(dv.getBigUint64(mvhd.off + 24)) : dv.getUint32(mvhd.off + 16);
    if (ts > 0) duration = du / ts;
  }

  // The largest tkhd display size is the video track; audio tracks carry 0x0.
  let width = 0, height = 0;
  let scan = moov.off;
  while (scan < moov.end) {
    const trak = readBoxes(buf, scan, moov.end, 'trak');
    if (!trak) break;
    const tkhd = readBoxes(buf, trak.off, trak.end, 'tkhd');
    if (tkhd) {
      const v = buf[tkhd.off];
      const base = tkhd.off + (v === 1 ? 32 : 20) + 4 + 8 + 2 + 2 + 2 + 2 + 36;  // to the matrix end
      const w = dv.getUint32(base) / 65536, h = dv.getUint32(base + 4) / 65536;
      if (w * h > width * height) { width = Math.round(w); height = Math.round(h); }
    }
    scan = trak.end;
  }
  return { mime, width, height, duration_s: duration, container: brand };
}

async function sha256Hex(buf: Uint8Array): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', buf.slice().buffer as ArrayBuffer);
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function b64(buf: Uint8Array): string {
  let s = ''; const chunk = 0x8000;
  for (let i = 0; i < buf.length; i += chunk) s += String.fromCharCode(...buf.subarray(i, i + chunk));
  return btoa(s);
}

const VISION_SYS = `You are QuotesDone's design reviewer. You are shown the ACTUAL rendered artifact that
is about to be published. Judge only what you can SEE in the image. If something is not visible, say
so — do not infer it from the description.

Return ONLY JSON:
{"composition":"...","hierarchy":"...","professionalism":"...","brand_consistency":"...",
 "message_clarity":"...","visible_defects":["..."],"text_legible":true|false,
 "spelling_errors":["..."],"logo_present":true|false,"logo_correct":true|false|null,
 "text_inside_safe_zone":true|false|null,"contrast_sufficient":true|false,
 "clipped_or_cropped_content":true|false,"audience_alignment":"...",
 "verdict":"pass"|"fail","reasons":["..."]}

Fail the artifact for: unreadable or clipped text, a wrong or missing logo where one is expected,
text running outside the safe zone, low contrast that hurts legibility, visible rendering defects,
or a spelling error. Do not fail it for taste.`;

const VIDEO_SYS = `You are QuotesDone's design reviewer, looking at frames taken from a video that is
about to be published, IN PLAYBACK ORDER. Judge each frame, and judge what happens BETWEEN them.

A video fails in ways a single image cannot: a caption that appears and is cut before it can be
read, a logo that shows in one frame and never again, a colour or style that jumps mid-sequence, a
message that only makes sense if the viewer sees a frame that is not there.

Judge only what you can SEE. You are looking at frames, not the whole video — say so where it
matters rather than assuming what happened in between.

Return ONLY JSON:
{"per_frame":[{"frame":number,"observation":"..."}],
 "broken_transitions":["frame 2 -> 3: the caption disappears after under a second"],
 "message_survives_the_cuts":true|false,"composition":"...","brand_consistency":"...",
 "logo_present":true|false,"logo_correct":true|false|null,"text_legible":true|false,
 "text_inside_safe_zone":true|false|null,"contrast_sufficient":true|false,
 "spelling_errors":["..."],"visible_defects":["..."],
 "verdict":"pass"|"fail","reasons":["..."]}`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    if (!(await requireInternal(admin, body?.__secret as string, 'artifact_review')).ok) {
      return J({ error: 'unauthorized' }, 401);
    }
    const subjectType = String(body.subject_type || '');
    const subjectId = String(body.subject_id || '');
    const url = String(body.artifact_url || '');
    const platform = String(body.platform || 'generic');
    const kind = String(body.kind || 'image');
    // THE DEFAULT REVIEWER WAS THE AUTHOR (15 Aug 2026). This defaulted to 'marketing_design',
    // which is the runtime agent_key of the Visual Design Director — the agent that produces these
    // artifacts. So unless a caller named someone else, the designer reviewed its own work, and
    // the guard below could not see it because `visual_design` !== `marketing_design` as strings
    // even though fn_org_agent_resolve maps both to the same employee. The default is now the
    // artifact-QA path: AI Quality Assurance Reviewer (ai_qa_specialist).
    const authorAgent = body.author_agent ? String(body.author_agent) : null;
    const reviewerAgent = String(body.reviewer_agent || 'ai_quality_reviewer');
    if (!subjectType || !subjectId || !url) return J({ error: 'subject_type, subject_id and artifact_url are required' }, 400);
    // RESOLVE BEFORE COMPARING. Same fix review_chain got on 14 Aug and this path did not: an alias
    // is a different string for the same employee, so a raw comparison answers "independent" for
    // exactly the case this guard exists to refuse. Refusing here — before the artifact is fetched
    // and before any vision call — also means a self-review costs nothing rather than a model call.
    const canon = async (id: string | null) => {
      if (!id) return null;
      const { data } = await admin.rpc('fn_org_agent_resolve', { p_addressee: id });
      return (typeof data === 'string' && data) ? data : id;
    };
    const [authorCanon, reviewerCanon] = await Promise.all([canon(authorAgent), canon(reviewerAgent)]);
    if (authorCanon && authorCanon === reviewerCanon) {
      return J({
        error: 'the agent that produced this artifact cannot be its only reviewer',
        author_agent: authorAgent, reviewer_agent: reviewerAgent, resolves_to: authorCanon,
      }, 409);
    }

    // 1. the actual bytes
    const res = await fetch(url);
    if (!res.ok) return J({ error: 'artifact could not be fetched', status: res.status, artifact_url: url }, 502);
    const buf = new Uint8Array(await res.arrayBuffer());
    const digest = await sha256Hex(buf);
    const dim = measure(buf);
    const vid = dim ? null : measureVideo(buf);
    const headerMime = res.headers.get('content-type') || '';

    // 2. what the platform requires
    const { data: spec } = await admin.from('artifact_platform_spec')
      .select('*').eq('platform', platform).eq('kind', kind).maybeSingle();
    const { data: fallback } = spec ? { data: spec } : await admin.from('artifact_platform_spec')
      .select('*').eq('platform', 'generic').eq('kind', 'image').maybeSingle();
    const s = (spec || fallback) as Record<string, number | string[] | number[]> | null;

    // 3. deterministic checks — measured, not judged
    const failures: string[] = [];
    const det: Record<string, unknown> = { sha256: digest, bytes: buf.length, header_mime: headerMime };
    if (vid) {
      // VIDEO. Duration, display size and container come from the real bytes; nothing here
      // needs a decoder. What no header can tell us is whether the thing looks right, and that
      // is what the frames are for below.
      const ar = vid.height ? vid.width / vid.height : 0;
      Object.assign(det, { mime: vid.mime, width: vid.width, height: vid.height,
        aspect_ratio: Number(ar.toFixed(4)), duration_s: vid.duration_s, container: vid.container,
        media: 'video' });
      if (!vid.width || !vid.height) failures.push('video_dimensions_not_readable:' + vid.container);
      if (vid.duration_s === null) failures.push('video_duration_not_readable:' + vid.container);
      if (s) {
        const allowed = (s.allowed_mime as string[]) || [];
        if (allowed.length && !allowed.includes(vid.mime)) failures.push(`format_not_allowed:${vid.mime}`);
        if (s.min_width && vid.width && vid.width < Number(s.min_width)) failures.push(`width_below_minimum:${vid.width}<${s.min_width}`);
        if (s.min_height && vid.height && vid.height < Number(s.min_height)) failures.push(`height_below_minimum:${vid.height}<${s.min_height}`);
        if (s.aspect_min && ar && ar < Number(s.aspect_min)) failures.push(`aspect_ratio_too_narrow:${ar.toFixed(2)}<${s.aspect_min}`);
        if (s.aspect_max && ar && ar > Number(s.aspect_max)) failures.push(`aspect_ratio_too_wide:${ar.toFixed(2)}>${s.aspect_max}`);
        if (s.max_bytes && buf.length > Number(s.max_bytes)) failures.push(`file_too_large:${buf.length}>${s.max_bytes}`);
        const minD = Number((s as Record<string, unknown>).min_duration_s || 0);
        const maxD = Number((s as Record<string, unknown>).max_duration_s || 0);
        if (minD && vid.duration_s !== null && vid.duration_s < minD) failures.push(`too_short:${vid.duration_s.toFixed(1)}s<${minD}s`);
        if (maxD && vid.duration_s !== null && vid.duration_s > maxD) failures.push(`too_long:${vid.duration_s.toFixed(1)}s>${maxD}s`);
        det.safe_zone_pct = s.safe_zone_pct;
        det.platform = platform; det.platform_kind = kind;
      }
    } else if (!dim) {
      failures.push('unrecognised_image_format');
      det.format = 'unrecognised — width, height and aspect could not be measured';
    } else {
      const ar = dim.height ? dim.width / dim.height : 0;
      Object.assign(det, { mime: dim.mime, width: dim.width, height: dim.height, aspect_ratio: Number(ar.toFixed(4)) });
      if (s) {
        const allowed = (s.allowed_mime as string[]) || [];
        if (allowed.length && !allowed.includes(dim.mime)) failures.push(`format_not_allowed:${dim.mime}`);
        if (s.min_width && dim.width < Number(s.min_width)) failures.push(`width_below_minimum:${dim.width}<${s.min_width}`);
        if (s.min_height && dim.height < Number(s.min_height)) failures.push(`height_below_minimum:${dim.height}<${s.min_height}`);
        if (s.aspect_min && ar < Number(s.aspect_min)) failures.push(`aspect_ratio_too_narrow:${ar.toFixed(2)}<${s.aspect_min}`);
        if (s.aspect_max && ar > Number(s.aspect_max)) failures.push(`aspect_ratio_too_wide:${ar.toFixed(2)}>${s.aspect_max}`);
        if (s.max_bytes && buf.length > Number(s.max_bytes)) failures.push(`file_too_large:${buf.length}>${s.max_bytes}`);
        det.safe_zone_pct = s.safe_zone_pct;
        det.platform = platform; det.platform_kind = kind;
      }
    }

    // 4. vision review of the same bytes — only if the format is one a model can read
    let vision: Record<string, unknown> = {};
    if (dim && buf.length < 6_000_000) {
      try {
        const { data: cred } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_ai').maybeSingle();
        if (cred?.value) {
          const content: unknown[] = [
            { type: 'text', text: `PLATFORM: ${platform}/${kind}. Measured: ${dim.width}x${dim.height}, ${dim.mime}, ${buf.length} bytes. Safe zone: ${det.safe_zone_pct ?? 0.05} of each edge.` },
            { type: 'text', text: `WHAT THIS ARTIFACT IS MEANT TO SAY: ${String(body.expect || 'not stated')}` },
            { type: 'image_url', image_url: { url: `data:${dim.mime};base64,${b64(buf)}` } },
          ];
          const r = await fetch(GW, {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ __secret: cred.value, fn: 'artifact_review', max: 900, temperature: 0.1, sys: VISION_SYS, input: [{ role: 'user', content }] }),
          });
          const d = await r.json();
          const txt = String(d?.content || '{}');
          const m = txt.match(/\{[\s\S]*\}/);
          vision = m ? JSON.parse(m[0]) : { error: 'model returned no json', raw: txt.slice(0, 300) };
          if (vision.verdict === 'fail') for (const why of (vision.reasons as string[] | undefined) || ['vision_review_failed']) failures.push('vision:' + why);
          if (vision.text_legible === false) failures.push('vision:text_not_legible');
          if (vision.contrast_sufficient === false) failures.push('vision:contrast_insufficient');
          if (vision.clipped_or_cropped_content === true) failures.push('vision:content_clipped');
          if (vision.text_inside_safe_zone === false) failures.push('vision:text_outside_safe_zone');
          if (vision.logo_correct === false) failures.push('vision:wrong_logo');
          for (const sp of (vision.spelling_errors as string[] | undefined) || []) failures.push('vision:spelling:' + sp);
        } else { vision = { skipped: 'no ai credential configured' }; }
      } catch (e) { vision = { error: String((e as Error).message).slice(0, 200) }; }
    } else if (dim) { vision = { skipped: 'artifact too large to send to a vision model' }; }

    // 4b. VIDEO REVIEW — representative frames and the transitions between them.
    //
    // The gateway takes text and images, not video, and no decoder runs in an edge function.
    // So the caller supplies frames — the poster plus representative stills, in order — and the
    // reviewer looks at those. A video with no frames is NOT passed on its header alone: it is
    // blocked, because approving a video nobody looked at is the exact failure this function
    // exists to prevent.
    if (vid) {
      const frames = Array.isArray(body.frames) ? (body.frames as string[]).slice(0, 8) : [];
      if (!frames.length) {
        failures.push('video_frames_required');
        vision = { blocked: 'no frames supplied, so nothing about this video was actually seen',
                   how_to_fix: 'send frames: [url, ...] — the poster plus 3 to 8 stills in playback order' };
      } else {
        try {
          const { data: cred } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_ai').maybeSingle();
          if (!cred?.value) { vision = { skipped: 'no ai credential configured' }; }
          else {
            const content: unknown[] = [{ type: 'text', text:
              `PLATFORM: ${platform}/${kind}. Measured from the file: ${vid.width}x${vid.height}, `
              + `${vid.duration_s === null ? 'duration unknown' : vid.duration_s.toFixed(1) + 's'}, `
              + `${vid.mime}, ${buf.length} bytes. Safe zone: ${det.safe_zone_pct ?? 0.05} of each edge.` },
              { type: 'text', text: `WHAT THIS VIDEO IS MEANT TO SAY: ${String(body.expect || 'not stated')}` },
              { type: 'text', text: `${frames.length} frame(s) follow IN PLAYBACK ORDER. Judge each frame, and judge the TRANSITIONS between consecutive frames: a cut that loses the message, a caption that disappears before it can be read, a logo that only appears in one frame, a jump in style or colour.` }];
            const frameDigests: string[] = [];
            for (let i = 0; i < frames.length; i++) {
              const fr = await fetch(String(frames[i]));
              if (!fr.ok) { failures.push(`frame_unfetchable:${i}`); continue; }
              const fb = new Uint8Array(await fr.arrayBuffer());
              const fdim = measure(fb);
              if (!fdim) { failures.push(`frame_not_an_image:${i}`); continue; }
              frameDigests.push(await sha256Hex(fb));
              content.push({ type: 'text', text: `FRAME ${i + 1} of ${frames.length}` });
              content.push({ type: 'image_url', image_url: { url: `data:${fdim.mime};base64,${b64(fb)}` } });
            }
            det.frames_reviewed = frameDigests.length;
            det.frame_sha256 = frameDigests;
            if (!frameDigests.length) {
              failures.push('no_frame_could_be_read');
              vision = { blocked: 'every supplied frame failed to fetch or was not an image' };
            } else {
              const r = await fetch(GW, {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ __secret: cred.value, fn: 'artifact_review', max: 900,
                                       temperature: 0.1, sys: VIDEO_SYS, input: [{ role: 'user', content }] }),
              });
              const d = await r.json();
              const txt = String(d?.content || '{}');
              const m = txt.match(/\{[\s\S]*\}/);
              vision = m ? JSON.parse(m[0]) : { error: 'model returned no json', raw: txt.slice(0, 300) };
              if (vision.verdict === 'fail') for (const why of (vision.reasons as string[] | undefined) || ['vision_review_failed']) failures.push('vision:' + why);
              if (vision.text_legible === false) failures.push('vision:text_not_legible');
              if (vision.contrast_sufficient === false) failures.push('vision:contrast_insufficient');
              if (vision.text_inside_safe_zone === false) failures.push('vision:text_outside_safe_zone');
              if (vision.logo_present === false) failures.push('vision:logo_missing_from_every_frame');
              if (vision.logo_correct === false) failures.push('vision:wrong_logo');
              if (vision.message_survives_the_cuts === false) failures.push('vision:message_lost_between_frames');
              for (const t of (vision.broken_transitions as string[] | undefined) || []) failures.push('vision:transition:' + t);
              for (const sp of (vision.spelling_errors as string[] | undefined) || []) failures.push('vision:spelling:' + sp);
            }
          }
        } catch (e) { vision = { error: String((e as Error).message).slice(0, 200) }; }
      }
    }

    // 5. revision: a new set of bytes for the same subject is a new revision, always
    const { data: prev } = await admin.from('artifact_review')
      .select('revision, artifact_sha256').eq('subject_type', subjectType).eq('subject_id', subjectId)
      .order('revision', { ascending: false }).limit(1).maybeSingle();
    const revision = prev ? (prev.artifact_sha256 === digest ? prev.revision : prev.revision + 1) : 1;

    const verdict = failures.length ? 'fail' : 'pass';
    const { data: row, error } = await admin.from('artifact_review').upsert({
      subject_type: subjectType, subject_id: subjectId, artifact_url: url,
      artifact_sha256: digest, revision, bytes: buf.length,
      mime: dim?.mime || headerMime || null, width: dim?.width || null, height: dim?.height || null,
      aspect_ratio: dim && dim.height ? Number((dim.width / dim.height).toFixed(4)) : null,
      // The CANONICAL identities, not what the caller happened to type. Storing the raw strings
      // would leave this table carrying two names for one employee, and force every later reader
      // to re-resolve before it could compare them. The trigger canonicalises too; doing it here as
      // well means the row the caller is shown matches the row that was stored.
      author_agent: authorCanon, reviewer_agent: reviewerCanon,
      deterministic: det, vision, verdict, failures,
    }, { onConflict: 'subject_type,subject_id,artifact_sha256,revision' }).select().single();
    if (error) return J({ error: error.message }, 500);

    return J({ ok: true, review_id: row.id, verdict, revision, failures, artifact_sha256: digest,
               measured: det, vision });
  } catch (e) {
    return J({ error: String((e as Error).message).slice(0, 300) }, 500);
  }
});
