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
//   duties        every resilience beat: publish what is due, then the daily reads that fn_marketing_duties_due names
//   publish_due / access_check / pull_insights / pull_ad_spend   one duty on demand
//
// THE SWITCH. A due post goes to Postiz only when app_secrets.marketing_golive is 'true' (measured 'false' on
// 22 Sep 2026) and the post is not a ZZ DEMO post. Otherwise the scheduler records on marketing_post.dry_run
// what it WOULD have sent and leaves the post scheduled. Nothing in this function writes to Meta or spends.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import {
  dubaiDate, measureAccess, postizReleases, publishPost, pullInsights, readAdSpend, stripTokens,
  type MetaEnv, type PublishInput,
} from '../_shared/marketing_channels.ts';

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
async function publishDue(e: Awaited<ReturnType<typeof env>>) {
  const { data: due, error } = await admin.from('marketing_post')
    .select('id,text_en,text_ar,channels,scheduled_at,is_demo,media_paths,dry_run')
    .eq('status', 'scheduled').lte('scheduled_at', new Date().toISOString()).order('scheduled_at').limit(5);
  if (error) return { ok: false, error: error.message };
  if (!due?.length) return { ok: true, due: 0 };
  if (!e.postizKey) return { ok: false, error: 'postiz_api_key is not in app_secrets', due: due.length };
  let live = 0, dry = 0, failed = 0;
  for (const p of due) {
    const isLive = e.golive && !p.is_demo;
    // A dry run is recorded once per post; re-reading Postiz every beat for the same answer is noise.
    if (!isLive && p.dry_run) continue;
    if (isLive) {
      // Claim: only one beat may publish a post (scheduled -> publishing), so a slow beat cannot post twice.
      const { data: claimed } = await admin.from('marketing_post').update({ status: 'publishing', attempts: 1, updated_at: new Date().toISOString() })
        .eq('id', p.id).eq('status', 'scheduled').select('id');
      if (!claimed?.length) continue;
    }
    const media: PublishInput['media'] = [];
    if (isLive) {
      let missing = '';
      for (const path of p.media_paths || []) {
        const { data: blob, error: dErr } = await admin.storage.from(BUCKET).download(path);
        if (dErr || !blob) { missing = path; break; }
        media.push({ name: path.split('/').pop()!, type: blob.type || 'application/octet-stream', bytes: new Uint8Array(await blob.arrayBuffer()) });
      }
      if (missing) {
        await admin.from('marketing_post').update({ status: 'failed', error: 'media not readable from ' + BUCKET + ': ' + missing, updated_at: new Date().toISOString() }).eq('id', p.id);
        failed++; continue;
      }
    } else {
      for (const path of p.media_paths || []) media.push({ name: path.split('/').pop()!, type: '', bytes: new Uint8Array() });
    }
    const why = p.is_demo ? 'a ZZ DEMO post is never published' : 'app_secrets.marketing_golive is not true';
    const res = await publishPost(fetch, e.postizBase, e.postizKey, { ...p, media } as PublishInput, isLive, why);
    const now = new Date().toISOString();
    if (res.mode === 'dry_run') {
      await admin.from('marketing_post').update({ dry_run: { at: now, ...res }, updated_at: now }).eq('id', p.id);
      dry++;
    } else if (res.ok) {
      await admin.from('marketing_post').update({ status: 'published', published_at: now, postiz_result: { channels: res.channels, skipped: res.skipped, postiz: res.postiz }, error: null, updated_at: now }).eq('id', p.id);
      live++;
    } else {
      await admin.from('marketing_post').update({ status: 'failed', error: res.error.slice(0, 500), postiz_result: { skipped: res.skipped, status: res.status ?? null }, updated_at: now }).eq('id', p.id);
      failed++;
    }
  }
  return { ok: failed === 0, due: due.length, published: live, dry_run: dry, failed };
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
    if (action === 'access_check') return J(await runDaily(e, 'access'));
    if (action === 'pull_insights') return J(await runDaily(e, 'insights'));
    if (action === 'pull_ad_spend') return J(await runDaily(e, 'ad_spend'));
    if (action !== 'duties') return J({ error: 'unknown_action' }, 400);

    const publish = await publishDue(e);
    const { data: due } = await admin.rpc('fn_marketing_duties_due');
    const daily: Record<string, unknown> = {};
    for (const [duty, isDue] of Object.entries((due || {}) as Record<string, boolean>)) if (isDue) daily[duty] = await runDaily(e, duty);
    const bad = [publish, ...Object.values(daily)].filter((x: any) => x && x.ok === false);
    const ran = (publish as any).due > 0 || Object.keys(daily).length > 0;
    if (ran || bad.length) {
      await logRun(bad.length ? 'error' : 'ok', { publish, daily: Object.keys(daily), failed: bad.length, golive: e.golive },
        bad.length ? 'marketing duty failed: ' + JSON.stringify(stripTokens(bad)).slice(0, 400) : 'marketing duties ran', started);
    }
    return J({ ok: bad.length === 0, publish, daily: stripTokens(daily) });
  } catch (err) {
    await logRun('error', { action }, 'marketing_channels crashed: ' + String((err as Error)?.message || err), started);
    return J({ ok: false, error: String((err as Error)?.message || err) }, 500);
  }
});
