// sanctions_screen — the compliance officer's weekly list fetch (6 Sep 2026).
//
// Downloads the UN Security Council consolidated list (XML) and the UAE local terrorist list (the
// .xls workbook linked as "Download Excel File" on https://www.uaeiec.gov.ae/en-us/un-page; the PDF
// beside it is not parsed), records one public.screening_run per source (entries, fetched_at, sha256,
// status, note), stores the parsed names in public.screening_entry (normalised by a database trigger,
// so SQL is the only normaliser), then calls fn_supplier_sanctions_screen, which screens every
// registered supplier and opens the compliance / BD tasks on a hit. No model, no removal, no e-mail.
//
// Called by fn_sanctions_screen_tick (cron sanctions_screen_weekly) with a credential scoped to this
// function (context cron.compliance). Body: { __secret, run_tag? } — a run_tag makes the screen a
// rehearsal (fixtures only) and is otherwise null.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import * as XLSX from 'https://esm.sh/xlsx@0.18.5';
import { requireInternal } from '../_shared/internal_auth.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });

const UN_URL = 'https://scsanctions.un.org/resources/xml/en/consolidated.xml';
const UAE_PAGE = 'https://www.uaeiec.gov.ae/en-us/un-page';
// The FileID the page carried on 6 Sep 2026 for "Download Excel File" (LS 130923 2026.xls). The page is
// re-read on every run; this is the fallback when the anchor cannot be found.
const UAE_XLS_FALLBACK = 'https://www.uaeiec.gov.ae/API/Upload/DownloadFile?FileID=0433bfdb-8a3d-44db-9015-90cbbf48f6f6';
const UA = 'QuotesDone compliance screening (weekly; contact management@quotesdone.com)';

type Entry = { entry_type: 'individual' | 'entity'; reference: string; name: string };
type Fetched = { source: string; url: string; sha256: string; entries: Entry[]; note: string };

const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'sanctions_screen', status, counts, note: String(note || '').slice(0, 900),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* the run must not fail on its own log */ }
}
async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', bytes as BufferSource);
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, '0')).join('');
}
const clean = (s: string) => s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/\s+/g, ' ').trim();
const tag = (block: string, t: string): string => { const m = block.match(new RegExp('<' + t + '>([^<]*)</' + t + '>')); return m ? clean(m[1]) : ''; };
const tags = (block: string, t: string): string[] => Array.from(block.matchAll(new RegExp('<' + t + '>([^<]*)</' + t + '>', 'g'))).map((m) => clean(m[1])).filter(Boolean);

async function fetchBytes(url: string): Promise<Uint8Array> {
  const r = await fetch(url, { headers: { 'User-Agent': UA, 'Accept': '*/*' } });
  if (!r.ok) throw new Error('HTTP ' + r.status + ' from ' + url);
  return new Uint8Array(await r.arrayBuffer());
}

// UN consolidated list: INDIVIDUAL blocks (FIRST..FOURTH_NAME + INDIVIDUAL_ALIAS/ALIAS_NAME) and ENTITY
// blocks (FIRST_NAME + ENTITY_ALIAS/ALIAS_NAME). Regex over the text; the document is flat and 2 MB.
async function fetchUN(): Promise<Fetched> {
  const bytes = await fetchBytes(UN_URL);
  const xml = new TextDecoder().decode(bytes);
  const generated = xml.match(/dateGenerated="([^"]+)"/)?.[1] || '';
  const entries: Entry[] = [];
  const push = (type: Entry['entry_type'], ref: string, name: string) => { const n = clean(name); if (n.length >= 2) entries.push({ entry_type: type, reference: ref, name: n }); };
  for (const m of xml.matchAll(/<INDIVIDUAL>([\s\S]*?)<\/INDIVIDUAL>/g)) {
    const b = m[1]; const ref = tag(b, 'REFERENCE_NUMBER') || tag(b, 'DATAID');
    push('individual', ref, [tag(b, 'FIRST_NAME'), tag(b, 'SECOND_NAME'), tag(b, 'THIRD_NAME'), tag(b, 'FOURTH_NAME')].filter(Boolean).join(' '));
    for (const a of tags(b, 'ALIAS_NAME')) push('individual', ref, a);
    for (const a of tags(b, 'NAME_ORIGINAL_SCRIPT')) push('individual', ref, a);
  }
  for (const m of xml.matchAll(/<ENTITY>([\s\S]*?)<\/ENTITY>/g)) {
    const b = m[1]; const ref = tag(b, 'REFERENCE_NUMBER') || tag(b, 'DATAID');
    push('entity', ref, tag(b, 'FIRST_NAME'));
    for (const a of tags(b, 'ALIAS_NAME')) push('entity', ref, a);
    for (const a of tags(b, 'NAME_ORIGINAL_SCRIPT')) push('entity', ref, a);
  }
  if (entries.length < 100) throw new Error('UN list parsed to only ' + entries.length + ' names; the document shape has changed');
  return { source: 'un_consolidated', url: UN_URL, sha256: await sha256Hex(bytes), entries,
    note: 'UN Security Council consolidated list, XML, dateGenerated ' + generated + '; ' + bytes.length + ' bytes; names + aliases + original-script names.' };
}

// UAE local terrorist list: the page's "Download Excel File" anchor, then the workbook. Sheets in
// order: individuals, organisations, entities; the two de-listing sheets ("رفع الإدراج") are skipped.
async function fetchUAE(): Promise<Fetched> {
  let url = UAE_XLS_FALLBACK; let how = 'fallback FileID';
  try {
    const page = new TextDecoder().decode(await fetchBytes(UAE_PAGE + '?p=1'));
    // the page lays each file out as icon → label ("Download Excel File") → download anchor, so the
    // Excel FileID is the FIRST DownloadFile href AFTER the label (measured 6 Sep 2026)
    const at = page.search(/Download\s+Excel\s+File/i);
    const m = at > 0 ? page.slice(at, at + 800).match(/href="([^"]*DownloadFile\?FileID=[0-9a-f-]+)"/i) : null;
    if (m) { url = new URL(m[1], UAE_PAGE).toString(); how = 'page anchor "Download Excel File"'; }
  } catch (e) { how = 'fallback FileID (page unreadable: ' + String((e as Error).message || e).slice(0, 80) + ')'; }
  const bytes = await fetchBytes(url);
  const wb = XLSX.read(bytes, { type: 'array' });
  const entries: Entry[] = []; const sheetNotes: string[] = [];
  wb.SheetNames.forEach((sheet: string, si: number) => {
    if (/رفع الإدراج/.test(sheet)) return;                         // de-listed: not a sanction
    const rows = XLSX.utils.sheet_to_json(wb.Sheets[sheet], { header: 1, raw: false, defval: '' }) as string[][];
    const hi = rows.findIndex((r) => String(r[0] || '').trim() === '#');
    if (hi < 0) { sheetNotes.push(sheet + ': no header row'); return; }
    const header = rows[hi].map((h) => String(h || '').replace(/\s+/g, ' ').trim());
    const latinCols = header.map((h, i) => (/اللاتينية/.test(h) ? i : -1)).filter((i) => i >= 0);
    const arabicCols = header.map((h, i) => (/الاسم الكامل/.test(h) && !/اللاتينية/.test(h) ? i : -1)).filter((i) => i >= 0);
    const aliasCols = header.map((h, i) => (h === 'الاسم' ? i : -1)).filter((i) => i >= 0);
    const infoCol = header.findIndex((h) => /معلومات أخرى/.test(h));
    const type: Entry['entry_type'] = si === 0 ? 'individual' : 'entity';
    let n = 0;
    for (let r = hi + 1; r < rows.length; r++) {
      const row = rows[r]; const idx = String(row[0] || '').trim();
      if (!/^\d+$/.test(idx)) continue;
      const ref = 'UAE-' + (si === 0 ? 'I' : si === 1 ? 'O' : 'E') + idx + (infoCol >= 0 && row[infoCol] ? ' ' + String(row[infoCol]).replace(/\s+/g, ' ').trim().slice(0, 80) : '');
      for (const c of [...latinCols, ...arabicCols, ...aliasCols]) {
        const v = clean(String(row[c] || '')); if (v && v !== '-') { entries.push({ entry_type: type, reference: ref, name: v }); n++; }
      }
    }
    sheetNotes.push(sheet + ': ' + n + ' names');
  });
  if (entries.length < 50) throw new Error('UAE workbook parsed to only ' + entries.length + ' names; the workbook shape has changed');
  return { source: 'uae_local_terrorist_list', url, sha256: await sha256Hex(bytes), entries,
    note: 'UAE Local Terrorist List (EOCN), .xls workbook via ' + how + '; ' + bytes.length + ' bytes; ' + sheetNotes.join('; ')
        + '. Limitation: the list is published as PDF + legacy Excel only (no XML/JSON endpoint); the PDF is not parsed; Latin, Arabic and alias names are taken from the Excel; de-listing sheets excluded.' };
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return J({ error: 'POST only' }, 405);
  let body: any = {};
  try { body = await req.json(); } catch { body = {}; }
  const auth = await requireInternal(admin, body?.__secret, 'sanctions_screen', body?.caller);
  if (!auth.ok) return J({ error: auth.error, message: auth.message }, auth.status);
  const runTag: string | null = typeof body?.run_tag === 'string' && body.run_tag ? body.run_tag : null;

  // IDEMPOTENT PER TICK (measured 6 Sep 2026: pg_net delivered each weekly tick twice, ~20 s apart, and
  // two identical fetch-and-screen passes ran). A real run whose two sources both succeeded in the last
  // ten minutes is the run; a second delivery records 'skipped' and does nothing else.
  if (!runTag) {
    const { data: recent } = await admin.from('screening_run').select('id, source').is('run_tag', null).eq('status', 'ok')
      .gte('created_at', new Date(Date.now() - 10 * 60e3).toISOString());
    const sources = new Set((recent || []).map((r: any) => r.source));
    if (sources.has('un_consolidated') && sources.has('uae_local_terrorist_list')) {
      await logRun('skipped', { skipped: 'duplicate_delivery', recent_runs: (recent || []).map((r: any) => r.id) },
        'Both sources were fetched and screened within the last 10 minutes (runs ' + (recent || []).map((r: any) => r.id).join(', ') + '); this delivery is a duplicate and did nothing.');
      return J({ ok: true, skipped: 'duplicate_delivery', runs: (recent || []).map((r: any) => r.id) });
    }
  }

  const runIds: number[] = []; const report: Record<string, unknown> = {}; const failures: string[] = [];
  for (const fetcher of [fetchUN, fetchUAE]) {
    const source = fetcher === fetchUN ? 'un_consolidated' : 'uae_local_terrorist_list';
    try {
      const f = await fetcher();
      const { data: run, error } = await admin.from('screening_run').insert({ source: f.source, source_url: f.url, sha256: f.sha256, entries: f.entries.length, status: 'ok', note: f.note, run_tag: runTag }).select('id').single();
      if (error || !run) throw new Error('screening_run insert: ' + (error?.message || 'no row'));
      for (let i = 0; i < f.entries.length; i += 500) {
        const chunk = f.entries.slice(i, i + 500).map((e) => ({ run_id: run.id, source: f.source, entry_type: e.entry_type, reference: e.reference, name: e.name }));
        const ins = await admin.from('screening_entry').insert(chunk);
        if (ins.error) throw new Error('screening_entry insert: ' + ins.error.message);
      }
      runIds.push(run.id); report[source] = { run_id: run.id, entries: f.entries.length, sha256: f.sha256 };
    } catch (e) {
      const msg = String((e as Error).message || e).slice(0, 400);
      failures.push(source + ': ' + msg);
      await admin.from('screening_run').insert({ source, source_url: source === 'un_consolidated' ? UN_URL : UAE_PAGE, entries: 0, status: 'failed', note: msg, run_tag: runTag });
      report[source] = { failed: msg };
    }
  }

  let screen: unknown = null;
  if (runIds.length) {
    const { data, error } = await admin.rpc('fn_supplier_sanctions_screen', { p_run_ids: runIds, p_rehearsal_tag: runTag });
    screen = error ? { error: error.message } : data;
  }
  // A failed source is the compliance officer's to look at: one task, deduplicated while open.
  if (failures.length) {
    const title = 'Sanctions list fetch failed: ' + failures.map((f) => f.split(':')[0]).join(', ');
    const { data: open } = await admin.from('org_tasks').select('id').eq('title', title).not('status', 'in', '("done","cancelled")').limit(1);
    if (!open?.length) {
      await admin.from('org_tasks').insert({ dept_key: 'legal', title, status: 'assigned', tier: 'autonomous', needs_founder: false, action_class: 'compliance_check', assigned_agent: 'compliance_mgr',
        detail: 'The weekly sanctions screening could not fetch or parse a source: ' + failures.join(' | ') + '. The other source (if any) was screened. Check the publisher URL, then re-run: select public.fn_sanctions_screen_tick();' });
    }
  }
  const status = runIds.length ? 'ok' : 'error';
  await logRun(status, { runs: runIds, failures: failures.length, report, screen },
    'Sanctions lists fetched: ' + Object.entries(report).map(([k, v]) => k + '=' + JSON.stringify(v)).join('; ') + (screen ? ' → screen ' + JSON.stringify(screen) : ''));
  return J({ ok: runIds.length > 0, runs: runIds, report, screen, failures }, runIds.length ? 200 : 502);
});
