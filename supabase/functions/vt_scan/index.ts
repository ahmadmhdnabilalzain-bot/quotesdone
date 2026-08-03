// vt_scan - privacy-safe VirusTotal hash-lookup scanner. Computes each file's SHA-256 locally and
// checks it against VirusTotal's known-malware DB. FILE CONTENTS ARE NEVER UPLOADED to VirusTotal.
// The worklist of files is supplied by fn_run_vt() (which can read storage.objects); this fn downloads + hashes + checks.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
async function sha256hex(buf: ArrayBuffer){ const h = await crypto.subtle.digest('SHA-256', buf); return Array.from(new Uint8Array(h)).map((b) => b.toString(16).padStart(2, '0')).join(''); }
const MAXB = 25 * 1024 * 1024;

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    const __exp = await sec('inbound_secret');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'vt_scan');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const { data: run } = await admin.from('agent_runs').insert({ agent: 'vt_scan' }).select('id').maybeSingle();
    const counts: Record<string, number> = { checked: 0, malicious: 0, clean: 0, unknown: 0, errors: 0, skipped: 0 };
    const finish = async (status: string, note = '') => { if (run?.id) await admin.from('agent_runs').update({ finished_at: new Date().toISOString(), status, counts, note }).eq('id', run.id); };
    const vtKey = await sec('virustotal_api_key');
    if (!vtKey) { await finish('ok', 'no_vt_key'); return J({ ok: true, skipped: 'no VirusTotal API key configured' }); }
    const files: { bucket: string; path: string; size: number }[] = Array.isArray(body.files) ? body.files : [];
    const owner = String(await sec('admin_emails') || 'management@quotesdone.com').split(',')[0].trim();

    for (const c of files) {
      if (!c || !c.bucket || !c.path) continue;
      if (Number(c.size || 0) > MAXB) { await admin.from('vt_results').insert({ sha256: null, bucket: c.bucket, path: c.path, status: 'skipped_large', malicious_count: 0 }); counts.skipped++; continue; }
      try {
        const { data: blob, error } = await admin.storage.from(c.bucket).download(c.path);
        if (error || !blob) { counts.errors++; await admin.from('vt_results').insert({ sha256: null, bucket: c.bucket, path: c.path, status: 'error', malicious_count: 0 }); continue; }
        const hash = await sha256hex(await blob.arrayBuffer());
        const r = await fetch('https://www.virustotal.com/api/v3/files/' + hash, { headers: { 'x-apikey': vtKey } });
        let status = 'unknown', mal = 0;
        if (r.status === 200) { const j = await r.json(); const st = j?.data?.attributes?.last_analysis_stats || {}; mal = Number(st.malicious || 0) + Number(st.suspicious || 0); status = mal > 0 ? 'malicious' : 'clean'; }
        else if (r.status === 404) { status = 'unknown'; }
        else { status = 'error'; }
        await admin.from('vt_results').insert({ sha256: hash, bucket: c.bucket, path: c.path, status, malicious_count: mal });
        counts.checked++;
        if (status === 'malicious') { counts.malicious++; await admin.from('security_events').insert({ kind: 'malware_detected', severity: 'high', source: c.bucket, subject: c.path.slice(0, 200), detail: { sha256: hash, vt_malicious: mal, why: 'VirusTotal flagged this file as malicious' } }); await admin.from('agent_actions').insert({ agent: 'security', kind: 'security_alert', status: 'pending', risk: 'high', title: 'MALWARE detected: ' + c.path.slice(0, 70), recommendation: 'remove this file immediately; do NOT open it. ' + mal + ' VirusTotal engines flagged it.', target_table: 'security_events', detail: { bucket: c.bucket, path: c.path, sha256: hash, vt_malicious: mal } }); await admin.from('notifications').insert({ type: 'security_alert', to_email: owner, to_role: 'admin', channel: 'email', subject: 'MALWARE detected on QuotesDone', body: 'VirusTotal flagged an uploaded file as malicious (' + mal + ' engines): ' + c.path + ' in ' + c.bucket + '. Remove it immediately and do not open it. See the Security agent in admin.' }); }
        else if (status === 'clean') counts.clean++; else if (status === 'unknown') counts.unknown++; else counts.errors++;
      } catch (_e) { counts.errors++; }
    }
    await finish('ok');
    return J({ ok: true, counts });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
