// marketing_channels -- THE MARKETING SEAT'S HANDS ON POSTIZ AND META (marketing, 22 Sep 2026).
//
// Founder, 22 Sep 2026: he and Claude create posts together and ingest them to the marketing seat; the seat
// schedules them, monitors analytics, reports the overall picture to the CEO and shares the ad spend with
// the accountant. Every HTTP call is in _shared/marketing_channels.ts (tested with mock HTTP); this file
// reads the database, calls those, and writes what they return.
//
// Actions (internal credential fn.marketing_channels -> app_secrets.cred_fn_marketing_channels):
//   ingest        {post:{ingest_key, ingested_by, title?, text_en, text_ar, channels[], scheduled_at?, is_demo?},
//                  media?:[{name, type, base64}]} -> media into the PRIVATE marketing-media bucket, then
//                  fn_marketing_post_ingest. Used by scripts/marketing/ingest_post.mjs.
//   duties        every resilience beat: reconcile posts in flight (watchdog), publish what is due, email any
//                 monthly calendar that is owed (fn_marketing_calendar_due), then the daily reads
//   publish_due / access_check / pull_insights / pull_ad_spend   one duty on demand
//   calendar_send {campaign_key}   render and email that month's calendar now
//   cancel {ingest_key} / reschedule {ingest_key, at_utc} / requeue {ingest_key}
//   The month's posts are loaded by scripts/marketing/load_calendar.mjs (fn_marketing_calendar_load).
//
// THE SWITCH AND THE APPROVAL. A due post goes to Postiz only when app_secrets.marketing_golive is 'true'
// (measured 'false' on 22 Sep 2026), the post is not a ZZ DEMO post (flag or text), and the database lets the
// claim through: the founder approved the month, by replying to its calendar email, for exactly this content. Otherwise the scheduler records on marketing_post.dry_run
// what it WOULD have sent and leaves the post scheduled. Nothing in this function writes to Meta or spends.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import {
  assetMismatch, deletePostizPost, dubaiDate, findInPostiz, integrationFor, isDemoText, measureAccess, postizIds, postizIntegrations, postizReleases,
  publishPost, pullInsights, readAdSpend, stripTokens, type MetaEnv, type PublishInput, type Variant,
} from '../_shared/marketing_channels.ts';
import { calendarBlocks, calendarRows, calendarSheet, type CalPost } from '../_shared/marketing_calendar_doc.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { docIdentity } from '../_shared/doc_template.ts';
import * as XLSX from '../_shared/vendor/sheetjs-0.20.3/xlsx.mjs';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
const BUCKET = 'marketing-media';
const POSTIZ_DEFAULT = 'https://api.postiz.com/public/v1';

async function secrets(keys: string[]): Promise<Record<string, string>> {
  const { data } = await admin.from('app_secrets').select('key,value').in('key', keys);
  return Object.fromEntries((data || []).map((r: { key: string; value: string }) => [r.key, r.value]));
}
async function policy(key: string): Promise<string | null> {
  const { data } = await admin.from('decision_policy').select('value').eq('key', key).maybeSingle();
  return data?.value == null ? null : String(data.value);
}
async function logRun(status: 'ok' | 'error' | 'skipped', counts: Record<string, unknown>, note: string, started: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'marketing_channels', status, counts, note: note.slice(0, 500), started_at: started, finished_at: new Date().toISOString() });
  } catch (_e) { /* the log never breaks the duty */ }
}

async function env() {
  const s = await secrets(['postiz_api_key', 'postiz_api_url', 'meta_access_token', 'meta_ad_account_id', 'marketing_golive']);
  const [graphVer, business] = await Promise.all([policy('marketing_meta_graph_version'), policy('marketing_meta_business_id')]);
  const meta: MetaEnv | null = s.meta_access_token
    ? { graph: 'https://graph.facebook.com/' + (graphVer || 'v21.0'), token: s.meta_access_token, adAccountId: s.meta_ad_account_id || null, businessId: business || '' }
    : null;
  return { postizBase: s.postiz_api_url || POSTIZ_DEFAULT, postizKey: s.postiz_api_key || null, meta, golive: String(s.marketing_golive || 'false').toLowerCase() === 'true' };
}
type Env = Awaited<ReturnType<typeof env>>;

// ── ingest ────────────────────────────────────────────────────────────────────────────────────────
const MEDIA_TYPES = new Set(['image/png', 'image/jpeg', 'image/webp', 'video/mp4']);
async function ingest(body: any) {
  const post = body?.post || {};
  const key = String(post.ingest_key || '').toLowerCase().trim();
  if (!/^[a-z0-9][a-z0-9_-]{2,80}$/.test(key)) return { ok: false, error: 'ingest_key must be 3-81 lowercase letters, digits, - or _' };
  const media: string[] = [];
  for (const m of Array.isArray(body?.media) ? body.media : []) {
    const name = String(m?.name || '').replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 100);
    const type = String(m?.type || '');
    if (!name || !MEDIA_TYPES.has(type)) return { ok: false, error: 'media must be png, jpeg, webp or mp4 with a name' };
    const bytes = Uint8Array.from(atob(String(m.base64 || '')), (c) => c.charCodeAt(0));
    if (!bytes.length || bytes.length > 50 * 1024 * 1024) return { ok: false, error: 'media ' + name + ' is empty or over 50 MB' };
    const path = `posts/${key}/${name}`;
    const { error } = await admin.storage.from(BUCKET).upload(path, bytes, { contentType: type, upsert: true });
    if (error) return { ok: false, error: 'media upload failed: ' + error.message };
    media.push(path);
  }
  const { data, error } = await admin.rpc('fn_marketing_post_ingest', { p: { ...post, ingest_key: key, media_paths: media.length ? media : (post.media_paths || []) } });
  if (error) return { ok: false, error: error.message };
  return data;
}

// ── publish ───────────────────────────────────────────────────────────────────────────────────────
// WHOSE CLOCK (23 Sep 2026). We keep our own 15-minute clock and send each post to Postiz as 'now' when it is
// due, rather than handing Postiz the month as scheduled posts. Reason: the founder's approval, the ZZ DEMO rule
// and marketing_golive are enforced by the DATABASE at the moment of the claim (fn_marketing_post_guard_publish);
// a post parked in Postiz's own queue would go out even after the month was edited (approval void), the switch
// was turned off, or a post was cancelled here and the delete to Postiz failed. The cost is up to one beat
// (15 min) of lateness, stated to him in the calendar as the Dubai time the post is due.
const VARIANT_COLS = 'platform,seq,post_type,body,hashtags,title,alt_text,first_comment';
const MIN = 60_000;

async function variantsOf(postId: number): Promise<Variant[]> {
  const { data } = await admin.from('marketing_post_variant').select(VARIANT_COLS).eq('post_id', postId).order('platform').order('seq');
  return (data || []) as Variant[];
}
async function download(path: string | null): Promise<PublishInput['media'][number] | null> {
  if (!path) return null;
  const { data: blob, error } = await admin.storage.from(BUCKET).download(path);
  if (error || !blob) return null;
  const name = path.split('/').pop()!;
  const type = blob.type && blob.type !== 'application/octet-stream' ? blob.type
    : /\.mp4$/i.test(name) ? 'video/mp4' : /\.png$/i.test(name) ? 'image/png' : /\.jpe?g$/i.test(name) ? 'image/jpeg' : 'application/octet-stream';
  return { name, type, bytes: new Uint8Array(await blob.arrayBuffer()) };
}
async function patch(id: number, fields: Record<string, unknown>) {
  const { error } = await admin.from('marketing_post').update({ ...fields, updated_at: new Date().toISOString() }).eq('id', id);
  return error;
}

/** Postiz's copy of a post, by the first value of each platform's variant thread. */
async function lookInPostiz(e: Env, p: { id: number; publish_started_at: string | null; scheduled_at: string }) {
  const ints = await postizIntegrations(fetch, e.postizBase, e.postizKey!);
  if (ints.error) return { ok: false, ids: [] as string[], error: 'integrations: ' + ints.error, expected: 0 };
  const vs = (await variantsOf(p.id)).filter((v) => v.seq === 1);
  const targets = vs.map((v) => ({ integrationId: integrationFor(ints.list, v.platform)?.id || '', content: v.body })).filter((t) => t.integrationId);
  const at = new Date(p.publish_started_at || p.scheduled_at).getTime();
  const r = await findInPostiz(fetch, e.postizBase, e.postizKey!, new Date(at - 60 * MIN), new Date(Date.now() + 60 * MIN), targets);
  return { ...r, expected: targets.length };
}

// THE WATCHDOG. A post in 'publishing' (a beat that died mid-send) or 'unconfirmed' (Postiz's answer was lost)
// for 10 minutes is looked up in Postiz: there -> published, with the ids found; not there after 30 minutes ->
// failed with the lookup recorded, never resent blind. Postiz unreadable -> left as it is and retried next beat.
async function reconcile(e: Env) {
  if (!e.postizKey) return { checked: 0 };
  const { data } = await admin.from('marketing_post').select('id,ingest_key,status,publish_started_at,scheduled_at')
    .in('status', ['publishing', 'unconfirmed']).lt('publish_started_at', new Date(Date.now() - 10 * MIN).toISOString()).limit(10);
  let published = 0, failed = 0, waiting = 0;
  for (const p of data || []) {
    const r = await lookInPostiz(e, p);
    const now = new Date().toISOString();
    if (r.ok && r.ids.length) {
      await patch(p.id, { status: 'published', published_at: now, error: null, postiz_result: { reconciled_at: now, from_status: p.status, postiz: r.ids.map((postId) => ({ postId })) } });
      published++;
    } else if (r.ok && Date.now() - new Date(p.publish_started_at).getTime() > 30 * MIN) {
      await patch(p.id, { status: 'failed', error: `was '${p.status}' and Postiz has no record of it at ${now} (looked ${r.expected} channel(s) up); safe to requeue` });
      failed++;
    } else waiting++;
  }
  return { checked: (data || []).length, published, failed, waiting };
}

async function publishDue(e: Env) {
  const recon = await reconcile(e);
  const { data: due, error } = await admin.from('marketing_post')
    .select('id,ingest_key,title,text_en,text_ar,cta_url,is_demo,media_paths,cover_path,video_path,video_sha256,cover_sha256,dry_run,attempts,scheduled_at,publish_started_at')
    .eq('status', 'scheduled').lte('scheduled_at', new Date().toISOString()).order('scheduled_at').limit(5);
  if (error) return { ok: false, error: error.message, reconcile: recon };
  if (!due?.length) return { ok: true, due: 0, reconcile: recon };
  if (!e.postizKey) return { ok: false, error: 'postiz_api_key is not in app_secrets', due: due.length, reconcile: recon };
  let live = 0, dry = 0, failed = 0, unconfirmed = 0, refused = 0;
  for (const p of due) {
    let variants = await variantsOf(p.id);
    const { data: refusal } = await admin.rpc('fn_marketing_post_refusal', { p_post_id: p.id });
    const demo = p.is_demo || isDemoText(p.title, p.text_en, p.text_ar, p.cta_url, ...variants.flatMap((v) => [v.body, v.title, v.alt_text, v.first_comment]));
    const why = demo ? 'a ZZ DEMO post is never published' : !e.golive ? 'app_secrets.marketing_golive is not true' : (refusal as string | null);
    const isLive = e.golive && !demo && !why;
    const input = (media: PublishInput['media'], cover: PublishInput['cover']): PublishInput =>
      ({ id: p.id, ingest_key: p.ingest_key, is_demo: p.is_demo, variants, media, cover });
    if (!isLive) {
      // A dry run is recorded once per post (and again when the reason changes); re-reading Postiz every beat is noise.
      if (p.dry_run && p.dry_run.reason === (why || refusal)) continue;
      const res = await publishPost(fetch, e.postizBase, e.postizKey, input((p.media_paths || []).map((x: string) => ({ name: x.split('/').pop()!, type: '', bytes: new Uint8Array() })), null), false, why || String(refusal));
      await patch(p.id, { dry_run: { at: new Date().toISOString(), ...res, database_says: refusal } });
      dry++; continue;
    }
    // A retry of an attempt that may have reached Postiz is looked up first: never published twice.
    if ((p.attempts || 0) > 0) {
      const seen = await lookInPostiz(e, p);
      if (!seen.ok) continue;                              // Postiz unreadable: try next beat
      if (seen.ids.length) {
        const now = new Date().toISOString();
        const err = await admin.from('marketing_post').update({ status: 'published', published_at: now, updated_at: now, postiz_result: { found_before_resend: now, postiz: seen.ids.map((postId) => ({ postId })) } }).eq('id', p.id).eq('status', 'scheduled');
        if (!err.error) live++; else refused++;
        continue;
      }
    }
    // THE CLAIM: scheduled -> publishing, once. The database refuses it unless the month is approved for exactly
    // this content, the switch is on, the specs pass and nothing says ZZ DEMO.
    const { data: claimed, error: cErr } = await admin.from('marketing_post')
      .update({ status: 'publishing', attempts: (p.attempts || 0) + 1, publish_started_at: new Date().toISOString(), updated_at: new Date().toISOString() })
      .eq('id', p.id).eq('status', 'scheduled').select('id');
    if (cErr) { await patch(p.id, { dry_run: { at: new Date().toISOString(), mode: 'refused_by_database', reason: cErr.message } }); refused++; continue; }
    if (!claimed?.length) continue;
    // Read the variants again AFTER the claim: what is sent is what the database let through, not an earlier read.
    variants = await variantsOf(p.id);
    const media: PublishInput['media'] = [];
    let missing = '';
    for (const path of p.media_paths || []) { const m = await download(path); if (!m) { missing = path; break; } media.push(m); }
    const cover = await download(p.cover_path);
    if (missing) { await patch(p.id, { status: 'failed', error: 'media not readable from ' + BUCKET + ': ' + missing }); failed++; continue; }
    // The bytes must be the ones the founder approved (the calendar's sha256, part of the approved hash). A file
    // replaced in the bucket after approval is never uploaded.
    const differs = await assetMismatch(media.map((m, i) => ({ path: (p.media_paths || [])[i], bytes: m.bytes })).concat(cover ? [{ path: p.cover_path, bytes: cover.bytes }] : []),
      { [p.video_path || '']: p.video_sha256, [p.cover_path || '']: p.cover_sha256 });
    if (differs) { await patch(p.id, { status: 'failed', error: 'bytes differ from what was approved: ' + differs }); failed++; continue; }
    const res = await publishPost(fetch, e.postizBase, e.postizKey, input(media, cover), true, '');
    const now = new Date().toISOString();
    if (res.mode === 'live' && res.ok) {
      await patch(p.id, { status: 'published', published_at: now, postiz_result: { channels: res.channels, skipped: res.skipped, postiz: res.postiz }, error: null });
      live++;
    } else if (res.mode === 'live' && res.unclear) {
      await patch(p.id, { status: 'unconfirmed', error: res.error.slice(0, 500), postiz_result: { skipped: res.skipped, status: res.status ?? null } });
      unconfirmed++;
    } else if (res.mode === 'live') {
      await patch(p.id, { status: 'failed', error: res.error.slice(0, 500), postiz_result: { skipped: res.skipped, status: res.status ?? null } });
      failed++;
    }
  }
  return { ok: failed === 0 && refused === 0, due: due.length, published: live, dry_run: dry, failed, unconfirmed, refused_by_database: refused, reconcile: recon };
}

// ── cancel / reschedule / requeue ─────────────────────────────────────────────────────────────────
async function postByKey(key: unknown) {
  const { data } = await admin.from('marketing_post').select('id,ingest_key,status,postiz_result,publish_started_at,scheduled_at').eq('ingest_key', String(key || '')).maybeSingle();
  return data;
}

// Cancel: a post already in Postiz is deleted THERE first; only then is it cancelled here. A cancelled post
// leaves the month's content hash, so cancelling one post VOIDS the month's approval by design: the founder
// is emailed the corrected calendar and approves the month as it now stands.
async function cancel(e: Env, body: any) {
  const p = await postByKey(body?.ingest_key);
  if (!p) return { ok: false, error: 'no_such_post' };
  if (p.status === 'cancelled') return { ok: true, unchanged: true };
  const ids = postizIds(p.postiz_result?.postiz);
  if (['publishing', 'unconfirmed'].includes(p.status) && e.postizKey) {
    const seen = await lookInPostiz(e, p);
    if (!seen.ok) return { ok: false, error: 'Postiz could not be read to see whether the post is there; nothing was cancelled' };
    ids.push(...seen.ids);
  }
  for (const id of new Set(ids)) {
    if (!e.postizKey) return { ok: false, error: 'postiz_api_key is not in app_secrets; the post is in Postiz and was not cancelled' };
    const d = await deletePostizPost(fetch, e.postizBase, e.postizKey, id);
    if (!d.ok) return { ok: false, error: 'Postiz refused to delete ' + id + ': ' + d.error };
  }
  const err = await patch(p.id, { status: 'cancelled', error: null });
  return err ? { ok: false, error: err.message } : { ok: true, deleted_in_postiz: [...new Set(ids)] };
}

// Reschedule: nothing waits in Postiz (our clock sends at the due time), so the new time is set here. The
// content hash includes the time, so the month's approval is void and a new calendar is emailed to him.
async function reschedule(body: any) {
  const p = await postByKey(body?.ingest_key);
  if (!p) return { ok: false, error: 'no_such_post' };
  if (!['draft', 'scheduled', 'failed'].includes(p.status)) return { ok: false, error: 'a post that reached Postiz is not rescheduled; cancel it and load a new one' };
  const at = new Date(String(body?.at_utc || ''));
  if (isNaN(at.getTime()) || at.getTime() < Date.now()) return { ok: false, error: 'at_utc must be a future ISO time' };
  const local = new Date(at.getTime() + 4 * 3600_000).toISOString().slice(0, 19);
  const err = await patch(p.id, { scheduled_at: at.toISOString(), scheduled_local: local, status: 'scheduled', dry_run: null, error: null });
  return err ? { ok: false, error: err.message } : { ok: true, scheduled_at: at.toISOString(), scheduled_local_dubai: local,
    note: 'the month\'s approval is void until the founder approves the new calendar, which is emailed automatically' };
}

// Requeue: a failed or unconfirmed post goes back to scheduled only after Postiz says it does not have it.
async function requeue(e: Env, body: any) {
  const p = await postByKey(body?.ingest_key);
  if (!p) return { ok: false, error: 'no_such_post' };
  if (!['failed', 'unconfirmed'].includes(p.status)) return { ok: false, error: 'only a failed or unconfirmed post is requeued' };
  if (!e.postizKey) return { ok: false, error: 'postiz_api_key is not in app_secrets' };
  const seen = await lookInPostiz(e, p);
  if (!seen.ok) return { ok: false, error: 'Postiz could not be read; not requeued' };
  if (seen.ids.length) {
    const now = new Date().toISOString();
    await patch(p.id, { status: 'published', published_at: now, error: null, postiz_result: { found_on_requeue: now, postiz: seen.ids.map((postId) => ({ postId })) } });
    return { ok: true, status: 'published', found_in_postiz: seen.ids };
  }
  const err = await patch(p.id, { status: 'scheduled', error: null, dry_run: null });
  return err ? { ok: false, error: err.message } : { ok: true, status: 'scheduled' };
}

// ── the monthly calendar email (founder_instructions 866, 871, 872) ─────────────────────────────────
// Rendered from the loaded rows on the company PDF template (pdf_native's renderer, in-process) and as a
// spreadsheet (the vendored SheetJS), stored in agent-docs (the outbox's attachable bucket), and mailed to him
// by fn_marketing_calendar_sent with the Reply-To token his "approve" must carry back.
//
// THE VIDEO LINKS are signed URLs of the PRIVATE marketing-media objects, valid until 14 days after the month
// ends, so the links work through his review and the whole month. The bucket never becomes public and no
// public copy is made; a signed URL stops working at its expiry, and what it serves is only that one object.
// (An authenticated company link would need him to sign in with his mobile OTP on each tap, and he asked for
// "a video link that I can press and open it".) Anyone he forwards the email to can open the videos until
// the expiry -- the same exposure as forwarding the attachment itself.
const LINK_MARGIN_DAYS = 14;

async function brandBytes(path: string) {
  try { const r = await timedFetch(`${Deno.env.get('SUPABASE_URL')}/storage/v1/object/public/brand/${path}`, {}, 10_000); return r.ok ? new Uint8Array(await r.arrayBuffer()) : null; }
  catch { return null; }
}

async function calendarSend(key: string) {
  const { data: c } = await admin.from('marketing_campaign').select('id,campaign_key,theme,title,month,is_demo').eq('campaign_key', key).maybeSingle();
  if (!c) return { ok: false, error: 'no_such_campaign' };
  if (c.is_demo) return { ok: false, error: 'a ZZ DEMO campaign is never mailed' };
  const { data: hash } = await admin.rpc('fn_marketing_campaign_hash', { p_campaign_id: c.id });
  const { data: posts } = await admin.from('marketing_post')
    .select('id,ingest_key,scheduled_at,scheduled_local,title,cta_url,video_path,video_sha256,cover_path')
    .eq('campaign_id', c.id).neq('status', 'cancelled').order('scheduled_at');
  if (!posts?.length) return { ok: false, error: 'the campaign has no posts' };
  const { data: vars } = await admin.from('marketing_post_variant').select('post_id,platform,seq,language,post_type,body,hashtags,title,alt_text,first_comment')
    .in('post_id', posts.map((p) => p.id));
  const monthStart = new Date(c.month + 'T00:00:00+04:00');
  const monthEnd = new Date(Date.UTC(monthStart.getUTCFullYear(), monthStart.getUTCMonth() + 1, 1) - 4 * 3600_000);
  const expiresAt = new Date(monthEnd.getTime() + LINK_MARGIN_DAYS * 86400_000);
  const secs = Math.max(3600, Math.floor((expiresAt.getTime() - Date.now()) / 1000));
  const urls: Record<string, string> = {};
  const frames: Array<{ video: string; bytes: Uint8Array; kind: 'jpg' | 'png' }> = [];
  for (const p of posts) {
    if (!p.video_path || urls[p.video_path]) continue;
    const { data: s, error } = await admin.storage.from(BUCKET).createSignedUrl(p.video_path, secs);
    if (error || !s?.signedUrl) return { ok: false, error: 'could not sign ' + p.video_path + ': ' + (error?.message || 'no url') };
    urls[p.video_path] = s.signedUrl;
    const fr = p.cover_path ? await admin.storage.from(BUCKET).download(p.cover_path) : null;
    if (fr?.data) frames.push({ video: p.title || p.video_path.split('/').pop()!, bytes: new Uint8Array(await fr.data.arrayBuffer()), kind: /\.png$/i.test(p.cover_path) ? 'png' : 'jpg' });
  }
  const calPosts: CalPost[] = posts.map((p) => ({ ...p, variants: (vars || []).filter((v) => v.post_id === p.id) }));
  const rows = calendarRows(calPosts, urls);
  const monthName = monthStart.toLocaleString('en-GB', { month: 'long', year: 'numeric', timeZone: 'Asia/Dubai' });
  const blocks = calendarBlocks({ campaign_key: c.campaign_key, theme: c.theme, month: monthName, hash: String(hash),
    expires: expiresAt.toISOString().slice(0, 10) }, rows, frames);
  const pdf = await renderPdf({ title: 'Social calendar — ' + monthName, blocks }, { fetchBytes: brandBytes, identity: await docIdentity(admin) });
  if (!pdf.ok) return { ok: false, error: 'the PDF did not render: ' + JSON.stringify(pdf.body).slice(0, 200) };
  const sheet = calendarSheet(rows);
  const ws = XLSX.utils.aoa_to_sheet(sheet.aoa);
  ws['!cols'] = [{ wch: 4 }, { wch: 16 }, { wch: 9 }, { wch: 18 }, { wch: 28 }, { wch: 12 }, { wch: 70 }, { wch: 30 }, { wch: 34 }, { wch: 30 }, { wch: 30 }];
  for (const l of sheet.links) { const ref = XLSX.utils.encode_cell({ r: l.r, c: l.c }); ws[ref] = { ...(ws[ref] || { t: 's', v: l.url }), l: { Target: l.url } }; }
  const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, 'Calendar');
  const xlsx = new Uint8Array(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }));
  const stem = `marketing/calendar/${c.campaign_key}/${String(hash).slice(0, 16)}`;
  for (const [ext, bytes, type] of [['pdf', pdf.bytes, 'application/pdf'], ['xlsx', xlsx, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']] as const) {
    const { error } = await admin.storage.from('agent-docs').upload(`${stem}.${ext}`, bytes, { contentType: type, upsert: true });
    if (error) return { ok: false, error: `could not store the calendar ${ext}: ${error.message}` };
  }
  const first = rows[0], last = rows[rows.length - 1];
  const body = [
    `Attached is the ${monthName} social calendar: ${rows.length} posts, ${first.date} to ${last.date} (Dubai time), organic only — no ads, no boosting.`,
    'The PDF lists every post with its date, Dubai time, platform, video, the exact caption and hashtags that will be published, and its link. Press a video name to open that video. The spreadsheet has the same rows.',
    `To approve all ${rows.length} posts exactly as shown, reply to this email with the single word "approve" (or "موافق"). To change anything, reply saying what, and a corrected calendar will follow.`,
    `Content reference: ${String(hash).slice(0, 12)}.`,
  ].join('\n\n');
  const { data: sent, error } = await admin.rpc('fn_marketing_calendar_sent', { p_campaign_key: c.campaign_key, p_hash: hash,
    p_pdf_path: `${stem}.pdf`, p_xlsx_path: `${stem}.xlsx`, p_subject: `Social calendar ${monthName}: ${rows.length} posts for your approval`, p_body: body });
  if (error) return { ok: false, error: error.message };
  return { ...(sent as Record<string, unknown>), pdf: `${stem}.pdf`, xlsx: `${stem}.xlsx`, posts: rows.length, links: pdf.meta.links, pages: pdf.meta.pages };
}

async function calendarsDue() {
  const { data, error } = await admin.rpc('fn_marketing_calendar_due');
  if (error) return { ok: false, error: error.message };
  const out: Record<string, unknown> = {};
  for (const r of (data || []) as Array<{ campaign_key: string }>) out[r.campaign_key] = await calendarSend(r.campaign_key);
  return { ok: Object.values(out).every((x: any) => x?.ok !== false), sent: out };
}

// ── daily duties ──────────────────────────────────────────────────────────────────────────────────
async function accessCheck(e: Awaited<ReturnType<typeof env>>) {
  const { data: li } = await admin.from('app_secrets').select('key').ilike('key', '%linkedin%');
  const checks = await measureAccess(fetch, { postizBase: e.postizBase, postizKey: e.postizKey, meta: e.meta, linkedinKeys: (li || []).map((r: { key: string }) => r.key) });
  const now = new Date().toISOString();
  const { error } = await admin.from('marketing_connection_check').upsert(checks.map((c) => ({ ...c, detail: stripTokens(c.detail), measured_at: now })), { onConflict: 'check_key' });
  if (error) return { ok: false, error: error.message };
  // the check completed; a platform that refuses is a measured fact in the table, not a failed duty
  return { ok: true, checks: checks.length, failing: checks.filter((c) => !c.ok).map((c) => c.check_key) };
}

async function insights(e: Awaited<ReturnType<typeof env>>) {
  if (!e.meta) return { ok: false, error: 'meta_access_token is not in app_secrets' };
  const day = dubaiDate(new Date(), -1);
  const { rows, errors } = await pullInsights(fetch, e.meta, e.postizKey ? { base: e.postizBase, key: e.postizKey } : null, day);
  if (rows.length) {
    const { error } = await admin.from('marketing_insight_day').upsert(rows.map((r) => ({ ...r, pulled_at: new Date().toISOString() })), { onConflict: 'platform,object_id,metric,day' });
    if (error) return { ok: false, error: error.message };
  }
  // permalinks for what the seat published: Postiz's releaseURL per channel
  let linked = 0;
  if (e.postizKey) {
    const { data: pub } = await admin.from('marketing_post').select('id,postiz_result,permalinks').eq('status', 'published').gte('published_at', new Date(Date.now() - 30 * 86400_000).toISOString());
    if (pub?.length) {
      const rel = await postizReleases(fetch, e.postizBase, e.postizKey, new Date(Date.now() - 31 * 86400_000), new Date(Date.now() + 86400_000));
      for (const p of pub) {
        const ids: string[] = (Array.isArray(p.postiz_result?.postiz) ? p.postiz_result.postiz : []).map((x: any) => String(x?.postId || x?.id || '')).filter(Boolean);
        const links: Record<string, string> = { ...(p.permalinks || {}) };
        for (const id of ids) { const r = rel.get(id); if (r?.url) links[r.identifier.split('-')[0]] = r.url; }
        if (JSON.stringify(links) !== JSON.stringify(p.permalinks || {})) { await admin.from('marketing_post').update({ permalinks: links }).eq('id', p.id); linked++; }
      }
    }
  }
  return { ok: errors.length === 0, day, rows: rows.length, linked, errors };
}

async function adSpend(e: Awaited<ReturnType<typeof env>>) {
  if (!e.meta?.adAccountId) return { ok: false, error: 'meta_access_token or meta_ad_account_id is not in app_secrets' };
  const back = Number(await policy('marketing_ad_spend_lookback_days')) || 7;
  const now = new Date();
  const read = await readAdSpend(fetch, e.meta, dubaiDate(now, -back), dubaiDate(now, 0));
  if (!read.ok) return { ok: false, error: read.error };
  const { data, error } = await admin.rpc('fn_marketing_ad_spend_record', { p_account: read.account, p_business_id: read.business_id, p_rows: read.rows, p_is_demo: false });
  if (error) return { ok: false, error: error.message };
  return { ok: (data as any)?.ok === true, currency: read.currency, rows: read.rows.length, recorded: data };
}

const DAILY: Record<string, (e: Awaited<ReturnType<typeof env>>) => Promise<any>> = { access: accessCheck, insights, ad_spend: adSpend };

async function runDaily(e: Awaited<ReturnType<typeof env>>, duty: string) {
  await admin.rpc('fn_marketing_duty_mark', { p_duty: duty, p_phase: 'start', p_result: null });
  let r: any;
  try { r = await DAILY[duty](e); } catch (err) { r = { ok: false, error: String((err as Error)?.message || err) }; }
  await admin.rpc('fn_marketing_duty_mark', { p_duty: duty, p_phase: r?.ok ? 'ok' : 'error', p_result: stripTokens(r) });
  return r;
}

Deno.serve(async (req) => {
  if (req.method === 'GET' && req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });
  const started = new Date().toISOString();
  const body = await req.json().catch(() => ({} as any));
  const auth = await requireInternal(admin, body?.__secret, 'marketing_channels');
  if (!auth.ok) return J({ error: auth.error, message: auth.message }, auth.status);
  const action = String(body.action || 'duties');
  try {
    if (action === 'ingest') return J(await ingest(body));
    const e = await env();
    if (action === 'publish_due') return J(await publishDue(e));
    if (action === 'cancel') return J(await cancel(e, body));
    if (action === 'reschedule') return J(await reschedule(body));
    if (action === 'requeue') return J(await requeue(e, body));
    if (action === 'calendar_send') return J(await calendarSend(String(body.campaign_key || '')));
    if (action === 'access_check') return J(await runDaily(e, 'access'));
    if (action === 'pull_insights') return J(await runDaily(e, 'insights'));
    if (action === 'pull_ad_spend') return J(await runDaily(e, 'ad_spend'));
    if (action !== 'duties') return J({ error: 'unknown_action' }, 400);

    const publish = await publishDue(e);
    const calendars = await calendarsDue();
    const { data: due } = await admin.rpc('fn_marketing_duties_due');
    const daily: Record<string, unknown> = {};
    for (const [duty, isDue] of Object.entries((due || {}) as Record<string, boolean>)) if (isDue) daily[duty] = await runDaily(e, duty);
    const bad = [publish, calendars, ...Object.values(daily)].filter((x: any) => x && x.ok === false);
    const ran = (publish as any).due > 0 || (publish as any).reconcile?.checked > 0 || Object.keys(calendars.sent || {}).length > 0 || Object.keys(daily).length > 0;
    if (ran || bad.length) {
      await logRun(bad.length ? 'error' : 'ok', { publish, calendars: Object.keys(calendars.sent || {}), daily: Object.keys(daily), failed: bad.length, golive: e.golive },
        bad.length ? 'marketing duty failed: ' + JSON.stringify(stripTokens(bad)).slice(0, 400) : 'marketing duties ran', started);
    }
    return J({ ok: bad.length === 0, publish, calendars, daily: stripTokens(daily) });
  } catch (err) {
    await logRun('error', { action }, 'marketing_channels crashed: ' + String((err as Error)?.message || err), started);
    return J({ ok: false, error: String((err as Error)?.message || err) }, 500);
  }
});
