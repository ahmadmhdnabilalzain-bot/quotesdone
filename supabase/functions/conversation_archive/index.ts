// conversation_archive — every saved conversation message becomes a PDF in two backups.
//
// The founder, 14 Sep 2026: "keep in mind that all conversations need to be saved and the sales
// agent has access to them at any time", "if the provider has one month history then we print a
// pdf copy of that email and keep it in our back up", and "by back up i mean 2 points. supabase
// and dropbox". Owner: sales_engineer. Agent that built it: ceo.
//
//   action 'sweep'           (default) render up to `limit` messages that have no PDF yet into the
//                            private 'backups' bucket, then fn_conversation_archived records it and
//                            queues the SAME file for Dropbox through doc_backups (the existing
//                            conveyor and its daily dropbox_backup pass - no second uploader).
//   action 'resend_backfill' pull what Resend still holds (inbound mail ~1 month) back into the
//                            rows: the full text, the HTML and Resend's id for inbound mail that was
//                            cut or replaced by a summary, and the exact HTML that was sent for
//                            outbound mail. Then the sweep renders them.
//
// Called every 15 minutes by resilience_ping. Which rows, and where in Dropbox, is decided in SQL
// (fn_conversation_archive_pending, fn_enqueue_doc_backups); this file only draws and stores.
import { whereAddress } from '../_shared/address_filter.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { docIdentity } from '../_shared/doc_template.ts';
import { observe } from '../_shared/observe.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { conversationDocument, stripHtml, type ConversationRow } from './document.ts';
import { drawingMs, mayRenderNext } from './budget.ts';
import { archiveOne } from './archive_one.ts';
import { J } from '../_shared/json_response.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const ASSET = Deno.env.get('SUPABASE_URL')! + '/storage/v1/object/public/brand';
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
const assetCache = new Map<string, Uint8Array | null>();
async function fetchBytes(path: string) {
  if (assetCache.has(path)) return assetCache.get(path)!;
  let b: Uint8Array | null = null;
  try { const r = await fetch(`${ASSET}/${path}`); if (r.ok) b = new Uint8Array(await r.arrayBuffer()); } catch { b = null; }
  assetCache.set(path, b); return b;
}
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try { await admin.from('agent_runs').insert({ agent: 'conversation_archive', status, counts, note, started_at: new Date().toISOString(), finished_at: new Date().toISOString() }); } catch { /* attribution must not fail the work */ }
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const addr = (v: unknown): string => { const s = Array.isArray(v) ? String(v[0] ?? '') : String(v ?? ''); const m = s.match(/<([^>]+)>/); return (m ? m[1] : s).trim().toLowerCase(); };

// `offset` lets the heartbeat run several sweeps at once, each in its own worker, over disjoint
// slices of the same oldest-first list (offset 0 takes rows 1-4, offset 4 rows 5-8 ...). A row that
// is archived between two reads can shift a slice by one; the record is an upsert, so the worst case
// is one message drawn twice, never one skipped.
// tag: a TAGGED SANDBOX RUN renders the ZZ DEMO messages carrying that tag in their subject
// (fn_conversation_archive_pending_sandbox); the scheduled sweep never takes a demo message.
async function sweep(limit: number, offset = 0, tag?: string) {
  const { data, error } = tag
    ? await admin.rpc('fn_conversation_archive_pending_sandbox', { p_tag: tag, p_limit: offset + limit })
    : await admin.rpc('fn_conversation_archive_pending', { p_limit: offset + limit });
  if (error) return { ok: false, stage: 'pending', error: error.message };
  const rows = ((data || []) as ConversationRow[]).slice(offset);
  const identity = rows.length ? await docIdentity(admin) : undefined;
  let archived = 0, queued = 0, renderMs = 0, slowestMs = 0, deferred = 0, htmlCopies = 0; const failed: Array<{ ref: string; error: string }> = [];
  // The budget counts drawing, not waiting: time spent fetching a brand asset or font (cold on a fresh worker) is
  // taken out of each render's clock, so a cold start does not cut a sweep to one or two PDFs (review of #1797).
  let waitedMs = 0;
  const timedFetchBytes = async (p: string) => { const t = performance.now(); try { return await fetchBytes(p); } finally { waitedMs += performance.now() - t; } };
  for (const r of rows) {
    const ref = `${r.source_table}:${r.source_id}`;
    // A CPU budget, not a count (budget.ts): what is not drawn here stays pending for the next sweep.
    if (!mayRenderNext(renderMs, slowestMs)) { deferred = rows.length - archived - failed.length; break; }
    try {
      const res = await archiveOne(r, {
        attempt: async (m) => { const { data, error } = await admin.rpc('fn_conversation_archive_attempt', { p_source_table: m.source_table, p_source_id: m.source_id }); return error || typeof data !== 'number' ? null : data; },
        render: async (m) => {
          const t0 = performance.now(), w0 = waitedMs;
          try {
            const out = await renderPdf(conversationDocument(m), { fetchBytes: timedFetchBytes, identity });
            return out.ok ? { ok: true, bytes: out.bytes } : { ok: false, error: JSON.stringify(out.body).slice(0, 160) };
          } finally { const took = drawingMs(performance.now() - t0, waitedMs - w0); renderMs += took; slowestMs = Math.max(slowestMs, took); }
        },
        upload: async (path, bytes, contentType) => { const up = await admin.storage.from('backups').upload(path, bytes, { contentType, upsert: true }); return up.error ? up.error.message : null; },
        record: async (m, path, n) => {
          const { data: rec, error: recErr } = await admin.rpc('fn_conversation_archived', { p_source_table: m.source_table, p_source_id: m.source_id, p_path: path, p_bytes: n });
          return recErr || !(rec as { ok?: boolean })?.ok ? { ok: false, queued: 0, error: recErr?.message || JSON.stringify(rec) }
            : { ok: true, queued: Number((rec as { queued_for_dropbox?: number }).queued_for_dropbox) || 0 };
        },
        clear: async (m) => { await admin.from('conversation_archive_attempt').delete().eq('source_table', m.source_table).eq('source_id', m.source_id); },
        finding: async (m, n, path) => {
          await admin.rpc('fn_it_engineer_finding_upsert', {
            p_issue_key: `conversation_archive:html_copy:${m.source_table}:${m.source_id}`,
            p_title: `A conversation could not be drawn as a PDF inside the edge CPU cap after ${n - 1} attempts; it is kept as an HTML copy instead`,
            p_where: 'conversation_archive sweep -> renderPdf (pdf_native) -> archive_one.ts HTML copy', p_blast: 'One conversation is kept as an HTML copy instead of a PDF: every field and the whole text are kept, the page layout is plain.', p_affected: 1,
            p_evidence: { ref: `${m.source_table}:${m.source_id}`, path, attempts: n, chars: String(m.body || m.html || '').length, at: new Date().toISOString() },
          });
        },
      });
      if (!res.ok) { failed.push({ ref, error: res.error }); continue; }
      archived++; queued += res.queued; if (res.light) htmlCopies++;
    } catch (e) { failed.push({ ref, error: String((e as Error)?.message || e).slice(0, 200) }); }
  }
  const render_ms = Math.round(renderMs), slowest_render_ms = Math.round(slowestMs);
  if (rows.length) await logRun(failed.length ? 'error' : 'ok', { pending: rows.length, archived, queued_for_dropbox: queued, failed: failed.length, deferred, render_ms, slowest_render_ms, html_copies: htmlCopies },
    failed.length ? 'PDF not kept for ' + failed.length + ' message(s): ' + failed.slice(0, 3).map((f) => f.ref + ' ' + f.error).join('; ') : '');
  return { ok: failed.length === 0, pending: rows.length, archived, queued_for_dropbox: queued, deferred, render_ms, slowest_render_ms, html_copies: htmlCopies, failed };
}

async function resendGet(key: string, url: string) {
  for (let i = 0; i < 4; i++) {
    const r = await fetch(url, { headers: { Authorization: `Bearer ${key}` } });
    if (r.status === 429) { await sleep(1200 * (i + 1)); continue; }
    await sleep(550); // Resend allows ~2 requests a second
    return { status: r.status, json: r.ok ? await r.json().catch(() => null) : null, text: r.ok ? '' : (await r.text()).slice(0, 200) };
  }
  return { status: 429, json: null, text: 'rate limited' };
}

async function resendBackfill() {
  const key = await sec('resend_api_key');
  if (!key) return { ok: false, error: 'resend_api_key is not in app_secrets' };
  const report: Record<string, unknown> = {};
  // ── RECEIVED ──
  let base = ''; let listed: Array<Record<string, unknown>> = []; const tried: Record<string, number> = {};
  for (const b of ['https://api.resend.com/emails/receiving', 'https://api.resend.com/emails/inbound']) {
    const r = await resendGet(key, b + '?limit=100'); tried[b] = r.status;
    if (r.status === 200 && Array.isArray(r.json?.data)) {
      base = b; listed = r.json.data;
      let page = r.json; let pages = 1;
      while (page?.has_more && pages < 10 && listed.length) {
        const n = await resendGet(key, `${b}?limit=100&after=${encodeURIComponent(String(listed[listed.length - 1].id))}`);
        if (n.status !== 200 || !Array.isArray(n.json?.data)) break;
        listed = listed.concat(n.json.data); page = n.json; pages++;
      }
      break;
    }
  }
  report.received_list_endpoint = base || null; report.received_list_status = tried; report.received_listed = listed.length;
  let updated = 0, inserted = 0, already = 0; const errs: string[] = [];
  for (const it of listed) {
    const id = String(it.id || ''); if (!id) continue;
    const { data: have } = await admin.from('inbound_messages').select('id').eq('provider_email_id', id).limit(1);
    if (have && have.length) { already++; continue; }
    const full = await resendGet(key, `${base}/${id}`);
    const e = (full.json?.data || full.json || it) as Record<string, unknown>;
    const html = e.html ? String(e.html) : null;
    const text = String(e.text || '') || (html ? stripHtml(html) : '');
    const from = addr(e.from), to = addr(e.to), subject = String(e.subject || '').slice(0, 300);
    const at = String(e.created_at || it.created_at || new Date().toISOString());
    if (/example\.invalid/i.test(from)) continue;
    const t = new Date(at).getTime();
    const { data: near } = await whereAddress(admin.from('inbound_messages').select('id,body,created_at'), 'from_email', from)
      .is('provider_email_id', null).eq('subject', subject)
      .gte('created_at', new Date(t - 3600e3).toISOString()).lte('created_at', new Date(t + 3600e3).toISOString()).limit(3);
    const match = (near || []).sort((a, b) => Math.abs(new Date(a.created_at).getTime() - t) - Math.abs(new Date(b.created_at).getTime() - t))[0];
    if (match) {
      const old = String(match.body || '');
      // A receipt row held a one-line summary; keep that line and put the whole email under it.
      const body = old.length >= text.length ? old : (old.startsWith('[') ? old.split('\n\n')[0] + '\n\n' + text : text);
      const { error } = await admin.from('inbound_messages').update({ body, html, provider_email_id: id }).eq('id', match.id);
      if (error) errs.push(`update ${match.id}: ${error.message}`); else updated++;
    } else {
      const { error } = await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, body: text, html, provider_email_id: id,
        attachments_count: Array.isArray(e.attachments) ? e.attachments.length : 0, matched_existing: false, needs_review: false, created_at: at });
      if (error) errs.push(`insert ${id}: ${error.message}`); else inserted++;
    }
  }
  Object.assign(report, { received_already_linked: already, received_rows_completed: updated, received_rows_added: inserted });
  // ── SENT ── the exact HTML each sent email carried, taken back from the provider by its own id.
  const { data: sent } = await admin.from('notifications').select('id,provider_message_id')
    .eq('status', 'sent').not('provider_message_id', 'is', null).is('html', null).limit(200);
  let filled = 0, missing = 0;
  for (const n of sent || []) {
    const r = await resendGet(key, `https://api.resend.com/emails/${n.provider_message_id}`);
    const html = r.json?.html ? String(r.json.html) : null;
    if (!html) { missing++; continue; }
    const { error } = await admin.from('notifications').update({ html }).eq('id', n.id);
    if (error) errs.push(`notif ${n.id}: ${error.message}`); else filled++;
  }
  Object.assign(report, { sent_checked: (sent || []).length, sent_html_filled: filled, sent_not_retrievable: missing, errors: errs.slice(0, 10) });
  await logRun(errs.length ? 'error' : 'ok', report, 'resend backfill');
  return { ok: errs.length === 0, ...report };
}

Deno.serve(observe('conversation_archive', async (req) => {
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const auth = await requireInternal(admin, String(body?.__secret || ''), 'conversation_archive');
    if (!auth.ok) return J({ error: 'forbidden' }, 403);
    // 5 per call. Measured 14 Sep 2026: a call asked for 100 rendered 10 then died with
    // WORKER_RESOURCE_LIMIT, and 5 of 18 calls at 8 died the same way; the renderer's font
    // subsetting is the cost. The heartbeat asks for 4 every 15 minutes - 384 a day, well above the
    // ~100 messages a day this estate writes - and a call that dies archives nothing twice.
    const limit = Math.max(1, Math.min(Number(body.limit) || 4, 5));
    const offset = Math.max(0, Math.min(Math.trunc(Number(body.offset) || 0), 195));
    if (body.action === 'resend_backfill') {
      const bf = await resendBackfill();
      const sw = await sweep(limit);
      return J({ backfill: bf, sweep: sw });
    }
    if (body.action === 'sandbox') {
      const tag = String(body.tag || '');
      if (!/^[A-Za-z0-9-]{6,40}$/.test(tag)) return J({ error: 'bad_tag' }, 400);
      return J(await sweep(limit, 0, tag));
    }
    return J(await sweep(limit, offset));
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
