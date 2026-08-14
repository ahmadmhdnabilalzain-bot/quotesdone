// video_produce — generate a video, look at it, and change it if it is wrong.
//
// The review half already exists: artifact_review reads the real bytes and judges supplied
// frames. What it could not do was act on the verdict. This closes that: the agent generates,
// reviews, and if the review fails it rewrites its own prompt from the named failures and
// generates again — up to a hard attempt ceiling, because every attempt costs money.
//
//   POST { __secret, subject_id, brief, platform?, kind?, model?, mode?, attempts?,
//          artifact_url?, frames?, reference_image_urls? }
//
// Two entry shapes:
//   brief          → generate on OpenArt, then review and adjust
//   artifact_url   → skip generation, review the video already produced and return the
//                    revised prompt it would regenerate with. This path needs no OpenArt key,
//                    and it is how the adjustment logic is tested.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const OPENART = 'https://openart.ai/api/v1';

const MAX_ATTEMPTS = 3;          // a ceiling on spend, not a preference
const POLL_TIMEOUT_MS = 240_000; // a video model is slow; four minutes then give up honestly

// Verified against openart_model_list on 14 Aug 2026. Video-capable ids and their modes:
//   grok-imagine-1-5        text2video, image2video          fast, native 1080p, synced audio
//   gemini-omni-flash       text2video, image2video, element2video
//   kling-3-omni            text2video, image2video, element2video   4K, cheap in batch
//   byte-plus-seedance-2    text2video, image2video, element2video   most realistic people
//   byte-plus-seedance-2-5  ...                                      up to 30s, caps at 720p
//   wan2-7, pixverseV6, smart-shot (generate-shot-video)
// element2video is the right mode whenever the brand asset should appear in a NEW scene
// rather than being the literal first frame — which is what a marketing sting usually wants.
const DEFAULT_MODEL = 'grok-imagine-1-5';
const DEFAULT_MODE = 'text2video';

const REVISE_SYS = `You are QuotesDone's video director. A video you commissioned has just been
reviewed and it FAILED. Rewrite the generation prompt so the next attempt does not fail the same way.

You are given the original brief, the deterministic measurements, and the reviewer's named
failures. Fix what the failures actually say — a wrong aspect ratio is a framing instruction, a
caption cut too early is a timing instruction, a logo missing from later frames is a continuity
instruction. Do not restyle the whole thing because one caption was late.

Return ONLY JSON: {"revised_prompt":string,"changed":[string],"unfixable_by_prompt":[string]}

"unfixable_by_prompt" is for failures no wording can fix — a file-size limit, a duration ceiling,
a platform minimum resolution. Say so rather than pretending a prompt tweak will solve it.`;

type Review = { verdict?: string; failures?: string[]; measured?: Record<string, unknown>; vision?: Record<string, unknown>; review_id?: number; error?: string };

async function review(secret: string, body: Record<string, unknown>): Promise<Review> {
  const r = await fetch(`${FN}/artifact_review`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, ...body }),
  });
  return await r.json().catch(() => ({ error: 'artifact_review returned no json' }));
}

async function callGw(secret: string, sys: string, text: string, max: number) {
  const r = await fetch(`${FN}/ai_gateway`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, fn: 'video_produce', max, temperature: 0.2, sys,
                           input: [{ role: 'user', content: [{ type: 'text', text }] }] }),
  });
  const d = await r.json().catch(() => ({}));
  const m = String(d?.content || '').match(/\{[\s\S]*\}/);
  return { json: m ? JSON.parse(m[0]) : {}, cost_aed: Number(d?.cost_usd || 0) * 3.6725 };
}

// OpenArt: submit, then poll. The shape is submit -> historyId -> status -> assets.
async function openartGenerate(key: string, model: string, mode: string, params: Record<string, unknown>) {
  const sub = await fetch(`${OPENART}/video/generate`, {
    method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, mode, params }),
  });
  const subJson = await sub.json().catch(() => ({}));
  if (!sub.ok) throw new Error(`openart submit ${sub.status}: ${JSON.stringify(subJson).slice(0, 200)}`);
  const historyId = subJson.historyId || subJson.history_id || subJson.id;
  if (!historyId) throw new Error(`openart returned no historyId: ${JSON.stringify(subJson).slice(0, 200)}`);

  const started = Date.now();
  while (Date.now() - started < POLL_TIMEOUT_MS) {
    await new Promise((r) => setTimeout(r, 6000));
    const st = await fetch(`${OPENART}/creations/${historyId}`, { headers: { Authorization: `Bearer ${key}` } });
    const j = await st.json().catch(() => ({}));
    const status = String(j.status || '').toUpperCase();
    if (status === 'COMPLETED') {
      const assets = (j.assets || j.outputs || []) as Array<Record<string, unknown>>;
      const video = assets.find((a) => /video/i.test(String(a.type || a.mime || '')) || /\.(mp4|mov|webm)/i.test(String(a.url || '')));
      // Whatever stills the model returned are the frames the reviewer will look at: a poster,
      // a thumbnail, a storyboard sheet. No stills means the review will block, correctly.
      const frames = assets.filter((a) => /image/i.test(String(a.type || a.mime || '')) || /\.(png|jpe?g|webp)/i.test(String(a.url || '')))
        .map((a) => String(a.url)).filter(Boolean);
      for (const k of ['thumbnail_url', 'thumbnailUrl', 'poster_url', 'preview_url']) {
        if (typeof j[k] === 'string' && j[k]) frames.unshift(String(j[k]));
      }
      if (!video?.url) throw new Error('openart completed with no video asset');
      return { historyId, video_url: String(video.url), frames: [...new Set(frames)].slice(0, 8) };
    }
    if (status === 'FAILED' || status === 'CANCELLED') {
      throw new Error(`openart ${status}: ${String(j.error || j.message || '').slice(0, 160)}`);
    }
  }
  throw new Error(`openart did not finish within ${POLL_TIMEOUT_MS / 1000}s (historyId ${historyId})`);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  const started = new Date().toISOString();
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const auth = await requireInternal(admin, body?.__secret as string, 'video_produce');
    if (!auth.ok) return J({ error: 'unauthorized' }, 401);

    const subjectId = String(body.subject_id || '');
    const platform = String(body.platform || 'generic');
    const kind = String(body.kind || 'video');
    const attempts = Math.min(Math.max(Number(body.attempts || 2), 1), MAX_ATTEMPTS);
    let prompt = String(body.brief || '');
    const givenUrl = body.artifact_url ? String(body.artifact_url) : '';
    if (!subjectId) return J({ error: 'subject_id is required' }, 400);
    if (!prompt && !givenUrl) return J({ error: 'give a brief to generate from, or an artifact_url to review' }, 400);

    const { data: cred } = await admin.from('app_secrets').select('value').eq('key', 'cred_action_invoker').maybeSingle();
    if (!cred?.value) return J({ error: 'no invoker credential configured' }, 503);
    const { data: ai } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_ai').maybeSingle();
    const { data: oa } = await admin.from('app_secrets').select('value').eq('key', 'openart_api_key').maybeSingle();

    if (!givenUrl && !oa?.value) {
      // Say exactly what is missing and what will be done with it. A 503 that does not name
      // its own fix is a dead end.
      return J({ error: 'openart_api_key_missing',
        detail: 'Generation needs an OpenArt API key. Add it as app_secrets.openart_api_key '
          + '(https://openart.ai account settings). Nothing else is required — the review, the '
          + 'revision and the publish gate are already live.',
        model_it_will_use: body.model || DEFAULT_MODEL,
        mode_it_will_use: body.mode || DEFAULT_MODE,
        meanwhile: 'POST artifact_url + frames to review a video produced elsewhere; the '
          + 'revised prompt comes back the same way.' }, 503);
    }

    const history: Array<Record<string, unknown>> = [];
    let costAed = 0;
    let videoUrl = givenUrl;
    let frames = Array.isArray(body.frames) ? (body.frames as string[]) : [];

    for (let attempt = 1; attempt <= attempts; attempt++) {
      if (!videoUrl) {
        const gen = await openartGenerate(oa!.value, String(body.model || DEFAULT_MODEL),
          String(body.mode || DEFAULT_MODE),
          { prompt, ...(Array.isArray(body.reference_image_urls) && (body.reference_image_urls as string[]).length
            ? { image_urls: body.reference_image_urls } : {}) });
        videoUrl = gen.video_url;
        frames = gen.frames;
        history.push({ attempt, generated: gen.historyId, video_url: videoUrl, frames: frames.length });
      }

      const rev = await review(cred.value, {
        subject_type: 'social_post', subject_id: subjectId, artifact_url: videoUrl,
        platform, kind, frames, expect: prompt || String(body.expect || ''),
        author_agent: 'marketing_content', reviewer_agent: 'marketing_design',
      });
      history.push({ attempt, review_id: rev.review_id, verdict: rev.verdict, failures: rev.failures ?? [] });

      if (rev.verdict === 'pass') {
        await admin.from('agent_runs').insert({ agent: 'video_produce', started_at: started,
          finished_at: new Date().toISOString(), status: 'ok',
          counts: { subject_id: subjectId, attempts: attempt, cost_aed: costAed },
          note: null });
        return J({ ok: true, verdict: 'pass', attempts: attempt, video_url: videoUrl,
                   frames_reviewed: frames.length, review_id: rev.review_id,
                   cost_aed: Number(costAed.toFixed(4)), history });
      }

      // FAILED. Rewrite the prompt from what the reviewer actually named.
      if (!ai?.value) { history.push({ attempt, revision: 'skipped — no ai credential' }); break; }
      const ask = `ORIGINAL BRIEF:\n${prompt || '(none — the video was produced elsewhere)'}\n\n`
        + `MEASURED FROM THE FILE:\n${JSON.stringify(rev.measured ?? {})}\n\n`
        + `THE REVIEWER'S FAILURES:\n${JSON.stringify(rev.failures ?? [])}\n\n`
        + `WHAT THE REVIEWER SAW:\n${JSON.stringify(rev.vision ?? {}).slice(0, 2500)}`;
      const { json: revised, cost_aed } = await callGw(ai.value, REVISE_SYS, ask, 900);
      costAed += cost_aed;
      history.push({ attempt, revised_prompt: revised.revised_prompt,
                     changed: revised.changed ?? [], unfixable_by_prompt: revised.unfixable_by_prompt ?? [] });

      // A failure no prompt can fix ends the loop honestly instead of burning the ceiling.
      if ((revised.unfixable_by_prompt as string[] | undefined)?.length && attempt === 1 && !revised.revised_prompt) break;
      if (typeof revised.revised_prompt === 'string' && revised.revised_prompt.trim()) prompt = revised.revised_prompt;
      videoUrl = ''; frames = [];          // the next attempt must generate new bytes
      if (!oa?.value) break;               // review-only entry: return the revision, do not loop
    }

    const last = [...history].reverse().find((h) => h.verdict);
    await admin.from('agent_runs').insert({ agent: 'video_produce', started_at: started,
      finished_at: new Date().toISOString(), status: 'error',
      counts: { subject_id: subjectId, attempts, cost_aed: costAed },
      note: `video_produce could not get a passing video for ${subjectId} in ${attempts} attempt(s); `
        + `the last review failed on: ${JSON.stringify((last?.failures as string[]) ?? []).slice(0, 200)}` });
    return J({ ok: false, verdict: 'fail', attempts, video_url: videoUrl || givenUrl,
               cost_aed: Number(costAed.toFixed(4)), history,
               note: 'no attempt passed review, so nothing was published' });
  } catch (e) {
    await admin.from('agent_runs').insert({ agent: 'video_produce', started_at: started,
      finished_at: new Date().toISOString(), status: 'error',
      note: String((e as Error).message).slice(0, 300) });
    return J({ error: String((e as Error).message).slice(0, 300) }, 500);
  }
});
