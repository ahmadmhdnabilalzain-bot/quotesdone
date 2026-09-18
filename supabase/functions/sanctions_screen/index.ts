// sanctions_screen — THE HALF OF THE WEEKLY SANCTIONS SCREEN THAT WAS NEVER BUILT (18 Sep 2026, it_engineer).
//
// WHAT WAS ACTUALLY HAPPENING, MEASURED 18 Sep 2026 04:35 UTC.
//   * public.fn_sanctions_screen_tick() has posted to https://<ref>.supabase.co/functions/v1/sanctions_screen
//     since 6 Sep. There was no such directory in supabase/functions and no such deployed function.
//   * It posts with net.http_post, which is FIRE AND FORGET. The response lands in net._http_response and
//     NOTHING reads it, so a 404 raised no exception, opened no finding, and was retried by nobody. The tick
//     returns {"posted": true} whatever comes back — a claim, not a measurement.
//   * And it was not even being called: cron.job holds ONE row in the whole database (`wa_flush`, active =
//     false). pg_cron has been empty since 7 Sep; the estate runs off resilience_ping's STEPS list.
//   * public.screening_run = 0, screening_entry = 0, supplier_screening_hit = 0. The weekly sanctions
//     screening the estate believes is running has NEVER run, not once.
//
// IS IT REDUNDANT WITH fn_supplier_sanctions_screen (repaired last night in PR #739)? No — they are the two
// halves of one loop and neither works alone. fn_supplier_sanctions_screen matches registered suppliers
// against rows in public.screening_entry. Only this function can PRODUCE those rows: it has to HTTP-fetch a
// 2.1 MB XML file and a legacy Excel workbook and parse them, and Postgres can do neither (net.http_post is
// async and unreadable from the calling statement, and there is no XML or XLS parser in the database). So
// this was never built and never renamed. It is the missing producer, and it is built here rather than
// retired because the screen is a live compliance obligation the founder asked for on 6 Sep 2026 and
// fn_supplier_sanctions_screen was repaired on 17 Sep precisely so that it works when a hit arrives.
//
// THE CLOCK IS resilience_ping's `orphans` STEP, NOT pg_cron. The gate is in Postgres
// (fn_resilience_orphan_steps_due → .sanctions): due at most once every 6 days, and only while
// app_secrets.sanctions_screen_enabled = 'true'. A missing key reads as NOT enabled, so the gate is shut
// until this function is deployed — the SQL can be applied in either order without the tick hammering a 404.
//
// ── IT RAN FOR THE FIRST TIME ON 18 Sep 2026 07:15 UTC, AND THREE MORE THINGS WERE WRONG ─────────
// The flag was switched on and the screen still did not execute. Driven end to end by hand, it did —
// and each of the three was invisible until something actually ran:
//   1. verify_jwt. This function was deployed verify_jwt = true, so the PLATFORM refused every caller
//      before a line of its code ran: net._http_response 432562 is HTTP 401 UNAUTHORIZED_NO_AUTH_HEADER,
//      which is the tick's exact request, and posting resilience_ping's own shape got the same. It is
//      verify_jwt = false now, in supabase/config.toml, with requireInternal below as the only gate —
//      the posture send_outbox, role_guard and resilience_ping already use. PROVED, against the
//      deployed function, that the gate is real: past the platform with NO credential → 403 forbidden.
//   2. The wrong credential. Internal credentials are scoped, and exactly ONE in the whole table is
//      scoped to sanctions_screen: id 175, context cron.compliance. resilience_ping's own credential is
//      not, so the orphans step would have been refused 403 even with the budget and the gateway fixed.
//      It now presents cred_cron_compliance for this one call.
//   3. The UAE source was the wrong FILE. See uaeCandidateUrls in parse.ts: the page's first matching
//      href is a Federal Decree PDF, and that 575,454-byte PDF is what run 74 downloaded and recorded
//      as "parsed 0 names". The list is chosen by sniffing the bytes now, not by href order.
// What the run proved does work: the UN consolidated list loaded 3,778 names (2,899 individuals plus
// entity names and aliases), sha256 recorded, normalised and tokenised by trigger.
//
// NO MODEL. Fetch, sha256, parse, insert, and one SQL call. OpenRouter is on hold and nothing here needs it.
//
// EACH SOURCE FAILS ON ITS OWN. A screening_run row is written for every source on every attempt, with
// status ok | failed | unparseable and the reason in `note`. A UN outage must not stop the UAE list being
// screened, and a screen that silently covered one list would be worse than one that says so.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import * as XLSX from '../_shared/vendor/sheetjs-0.20.3/xlsx.mjs';
import {
  isWorkbook, parseUaeWorkbook, parseUnXml, uaeCandidateUrls,
  UAE_FALLBACK_URL, UAE_PAGE, type ParsedEntry,
} from './parse.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
const UN_URL = 'https://scsanctions.un.org/resources/xml/en/consolidated.xml';
// A source that cannot be downloaded inside this must not hold the whole screen open. 2.1 MB over a warm
// edge connection measured in seconds; 45 s is generous and still well inside the tick's own budget.
const FETCH_MS = 45_000;
// screening_entry is inserted in batches so one 4,000-row statement cannot time out the whole run.
const BATCH = 500;

// t0 IS PASSED IN, NOT READ OFF THE MODULE. A `const T0 = Date.now()` at module scope is evaluated once
// per Deno isolate, not once per request, so every invocation after the first on a warm isolate would
// stamp agent_runs.started_at with the time of the FIRST one — a duration that is not this run's.
async function logRun(t0: number, status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({
      agent: 'sanctions_screen', status, counts, note: String(note || '').slice(0, 500),
      started_at: new Date(t0).toISOString(), finished_at: new Date().toISOString(),
    });
  } catch (_e) { /* never let logging break the screen */ }
}

async function sha256(buf: ArrayBuffer): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', buf);
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Writes the run row whatever happened, then the entries. Returns the run id so the caller can hand the
// whole set to fn_supplier_sanctions_screen in ONE call — screening every supplier once per source would
// open duplicate tasks for the same person.
async function record(
  source: string, source_url: string, status: 'ok' | 'failed' | 'unparseable',
  note: string, sha: string | null, entries: ParsedEntry[],
): Promise<{ run_id: number | null; inserted: number; error?: string }> {
  const { data, error } = await admin.from('screening_run')
    .insert({ source, source_url, sha256: sha, entries: entries.length, status, note: note.slice(0, 1000) })
    .select('id').maybeSingle();
  if (error || !data) return { run_id: null, inserted: 0, error: error?.message ?? 'screening_run insert returned no row' };
  const run_id = Number((data as { id: number }).id);
  let inserted = 0;
  for (let i = 0; i < entries.length; i += BATCH) {
    const chunk = entries.slice(i, i + BATCH).map((e) => ({ run_id, source, ...e }));
    // name_norm and tokens are written by trigger a00_screening_entry_normalise, so the SQL stays the
    // single normaliser and this function never has an opinion about how a name is compared.
    const { error: ie } = await admin.from('screening_entry').insert(chunk);
    if (ie) {
      // THE ROW ON RECORD MUST NOT OUTLIVE ITS OWN TRUTH (found in independent review before this
      // shipped). The run row is written BEFORE the entries, because the entries need its id. If a later
      // batch fails, the response and agent_runs already said 'failed' — but screening_run would keep
      // saying status 'ok', entries = the full parsed count, over a screening_entry set that is short.
      // An auditor reading that table would see full coverage of a list we only partly loaded. So the
      // row is corrected to what actually landed, which is also what keeps the weekly gate's 6-hour
      // failure back-off pointing at a source that needs re-fetching.
      await admin.from('screening_run')
        .update({ status: 'failed', entries: inserted,
          note: (note + ' | PARTIAL: ' + inserted + ' of ' + entries.length + ' entries inserted, then: ' + ie.message).slice(0, 1000) })
        .eq('id', run_id);
      return { run_id, inserted, error: ie.message };
    }
    inserted += chunk.length;
  }
  return { run_id, inserted };
}

async function un(): Promise<{ run_id: number | null; entries: number; status: string; note: string }> {
  try {
    const r = await fetch(UN_URL, { signal: AbortSignal.timeout(FETCH_MS) });
    if (!r.ok) {
      await r.body?.cancel().catch(() => {});
      const res = await record('un_consolidated', UN_URL, 'failed', 'HTTP ' + r.status + ' from scsanctions.un.org', null, []);
      return { run_id: res.run_id, entries: 0, status: 'failed', note: 'HTTP ' + r.status };
    }
    const got = await boundedBody(r);
    if ('tooBig' in got) {
      const res = await record('un_consolidated', UN_URL, 'failed', 'refused the download: ' + got.tooBig, null, []);
      return { run_id: res.run_id, entries: 0, status: 'failed', note: got.tooBig };
    }
    const { buf } = got;
    const bytes = new Uint8Array(buf);
    const sha = await sha256(buf);
    const parsed = parseUnXml(new TextDecoder().decode(bytes));
    // A DOWNLOAD THAT PARSES TO NOTHING IS NOT AN EMPTY SANCTIONS LIST. The UN list has carried 700+
    // individuals every day it has been measured; zero means the schema moved or we fetched an error page.
    // Recording that as `ok` with 0 entries would make the next screen pass over everybody in silence.
    if (!parsed.length) {
      const res = await record('un_consolidated', UN_URL, 'unparseable', 'downloaded ' + bytes.length + ' bytes but parsed 0 names — the UN schema has moved', sha, []);
      return { run_id: res.run_id, entries: 0, status: 'unparseable', note: 'parsed 0 of ' + bytes.length + ' bytes' };
    }
    const res = await record('un_consolidated', UN_URL, 'ok', 'UN consolidated list, ' + bytes.length + ' bytes, primary names and aliases', sha, parsed);
    if (res.error) return { run_id: res.run_id, entries: res.inserted, status: 'failed', note: 'entries insert failed: ' + res.error };
    return { run_id: res.run_id, entries: res.inserted, status: 'ok', note: '' };
  } catch (e) {
    const why = String((e as Error)?.message || e).slice(0, 300);
    const res = await record('un_consolidated', UN_URL, 'failed', why, null, []);
    return { run_id: res.run_id, entries: 0, status: 'failed', note: why };
  }
}

// Tries the ranked candidates and keeps the first whose BYTES are a workbook. The first real run
// downloaded a 575 KB PDF because the page's first matching href is a Federal Decree, so the choice is
// made on what the file IS rather than where it sat in the HTML. Bounded at UAE_MAX_TRIES requests.
// A CANDIDATE PROBE IS NOT A DOWNLOAD, AND A BODY IS NOT READ BEFORE ITS SIZE IS KNOWN (independent
// security review). Three bounds, each with the measurement behind it:
//   * 4 candidates at FETCH_MS each would be 180 s serially, against a caller that waits 55 s and an
//     orphan step budget of 60 s — the function would keep running past everyone watching it, which is
//     the CPU-cap-a-deadline-does-not-bound shape this estate has already paid for once. A real host
//     answers in seconds (measured: the workbook in well under one), so a probe gets 12 s.
//   * The real files are 2,176,957 bytes (UN) and 183,808 (UAE). 24 MB is ten times the larger one and
//     still small enough that an isolate cannot be exhausted by one response.
//   * Content-Length is checked BEFORE the body is buffered, so an oversized response costs a header
//     read rather than the memory it declares.
const UAE_MAX_TRIES = 4;
const UAE_PROBE_MS = 12_000;
const MAX_DOWNLOAD_BYTES = 24 * 1024 * 1024;

// Reads a response body only if it declares, or turns out to be, a sane size. Returns null with a
// reason rather than throwing, so the caller records WHY on the screening_run row.
async function boundedBody(r: Response): Promise<{ buf: ArrayBuffer } | { tooBig: string }> {
  const declared = Number(r.headers.get('content-length') ?? '');
  if (Number.isFinite(declared) && declared > MAX_DOWNLOAD_BYTES) {
    await r.body?.cancel().catch(() => {});
    return { tooBig: 'declared ' + declared + ' bytes, over the ' + MAX_DOWNLOAD_BYTES + ' byte ceiling' };
  }
  const buf = await r.arrayBuffer();
  if (buf.byteLength > MAX_DOWNLOAD_BYTES) {
    return { tooBig: 'returned ' + buf.byteLength + ' bytes, over the ' + MAX_DOWNLOAD_BYTES + ' byte ceiling' };
  }
  return { buf };
}
async function uaeWorkbookBytes(): Promise<
  { url: string; bytes: Uint8Array; buf: ArrayBuffer } | { error: string; tried: string[] }
> {
  let candidates = [UAE_FALLBACK_URL];
  try {
    const page = await fetch(UAE_PAGE, { signal: AbortSignal.timeout(FETCH_MS) });
    if (page.ok) candidates = uaeCandidateUrls(await page.text());
  } catch (_e) { /* the page is a convenience; the known FileID is the floor */ }
  const tried: string[] = [];
  let last = 'no candidate link was found on the page';
  for (const url of candidates.slice(0, UAE_MAX_TRIES)) {
    tried.push(url);
    try {
      const r = await fetch(url, { signal: AbortSignal.timeout(UAE_PROBE_MS) });
      // Release the stream before moving on. This loop runs up to UAE_MAX_TRIES times, so a host that
      // answers non-2xx every time would otherwise leave four undrained bodies per invocation — the same
      // discipline boundedBody applies on the oversized path (independent review).
      if (!r.ok) { await r.body?.cancel().catch(() => {}); last = 'HTTP ' + r.status + ' from ' + url; continue; }
      const got = await boundedBody(r);
      if ('tooBig' in got) { last = got.tooBig; continue; }
      const { buf } = got;
      const bytes = new Uint8Array(buf);
      if (!isWorkbook(bytes)) {
        last = 'not a workbook: ' + (r.headers.get('content-type') ?? 'unknown type') + ', ' + bytes.length + ' bytes';
        continue;
      }
      return { url, bytes, buf };
    } catch (e) { last = String((e as Error)?.message || e).slice(0, 160); }
  }
  return { error: last, tried };
}

async function uae(): Promise<{ run_id: number | null; entries: number; status: string; note: string }> {
  let url = UAE_FALLBACK_URL;
  // The PDF edition of this list is NOT parsed. That limitation is written onto every run row rather than
  // left for someone to infer from the entry count.
  const limitation = 'UAE local terrorist list: the Excel edition is parsed; the PDF edition is not, and no XML/JSON endpoint exists.';
  try {
    const got = await uaeWorkbookBytes();
    if ('error' in got) {
      const why = 'no workbook among ' + got.tried.length + ' candidate download(s): ' + got.error;
      const res = await record('uae_local_terrorist_list', got.tried[0] ?? url, 'failed', why + '. ' + limitation, null, []);
      return { run_id: res.run_id, entries: 0, status: 'failed', note: why };
    }
    url = got.url;
    const { bytes, buf } = got;
    const sha = await sha256(buf);
    let parsed: ParsedEntry[] = [];
    try {
      parsed = parseUaeWorkbook(XLSX.read(bytes, { type: 'array' }));
    } catch (pe) {
      const why = 'workbook did not parse: ' + String((pe as Error)?.message || pe).slice(0, 200);
      const res = await record('uae_local_terrorist_list', url, 'unparseable', why + '. ' + limitation, sha, []);
      return { run_id: res.run_id, entries: 0, status: 'unparseable', note: why };
    }
    if (!parsed.length) {
      const res = await record('uae_local_terrorist_list', url, 'unparseable', 'downloaded ' + bytes.length + ' bytes but parsed 0 names — the sheet names or layout have moved. ' + limitation, sha, []);
      return { run_id: res.run_id, entries: 0, status: 'unparseable', note: 'parsed 0 of ' + bytes.length + ' bytes' };
    }
    const res = await record('uae_local_terrorist_list', url, 'ok', limitation, sha, parsed);
    if (res.error) return { run_id: res.run_id, entries: res.inserted, status: 'failed', note: 'entries insert failed: ' + res.error };
    return { run_id: res.run_id, entries: res.inserted, status: 'ok', note: '' };
  } catch (e) {
    const why = String((e as Error)?.message || e).slice(0, 300);
    const res = await record('uae_local_terrorist_list', url, 'failed', why + '. ' + limitation, null, []);
    return { run_id: res.run_id, entries: 0, status: 'failed', note: why };
  }
}

Deno.serve(observe('sanctions_screen', async (req) => {
  const t0 = Date.now();
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const __auth = await requireInternal(admin, (body as { __secret?: unknown })?.__secret, 'sanctions_screen');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);

    const [a, b] = await Promise.all([un(), uae()]);
    const sources: Array<[string, Awaited<ReturnType<typeof un>>]> = [['un_consolidated', a], ['uae_local_terrorist_list', b]];
    // SCREEN ON WHAT WE ACTUALLY GOT. A source that failed contributes no run id, so the suppliers are
    // screened against the list(s) that did download rather than not screened at all — and the failure is
    // on the record as its own screening_run row, so nobody can read the result as full coverage.
    const usable = sources
      .filter(([, s]) => s.status === 'ok' && typeof s.run_id === 'number')
      .map(([, s]) => s.run_id as number);
    let screen: unknown = { skipped: 'no source produced entries' };
    if (usable.length) {
      const { data, error } = await admin.rpc('fn_supplier_sanctions_screen', { p_run_ids: usable });
      screen = error ? { ok: false, error: error.message } : data;
    }
    // ONE `ok`, AND IT MEANS THE WHOLE JOB (three findings from independent review before this shipped).
    // It read `ok: failed.length < 2`, so ONE source failing answered ok:true — the very thing the header
    // of this file calls worse than saying so. And the screening RPC's own failure was computed into
    // `screen` and then dropped: both lists could download and fn_supplier_sanctions_screen — the routine
    // that IS the screen — could error, and this returned HTTP 200 {ok:true} with agent_runs saying
    // "screened registered suppliers against both sanctions lists". That is fn_sanctions_screen_tick's
    // {"posted":true} rebuilt inside its own replacement. `ok` is now every part of the job, and the
    // `error` string travels with it so resilience_ping's failureOf can read it (a bare ok:false is, by
    // steps.ts convention, a seat that already staged its own finding — this one has not).
    const failed = sources.filter(([, s]) => s.status !== 'ok');
    const screenErr = usable.length
      ? ((screen as { ok?: unknown; error?: unknown })?.ok === false
        ? 'fn_supplier_sanctions_screen: ' + String((screen as { error?: unknown }).error ?? 'unknown error')
        : null)
      : 'nothing to screen against: neither sanctions source produced entries';
    const why = [
      ...failed.map(([n, s]) => n + ' ' + s.status + ': ' + s.note),
      ...(screenErr ? [screenErr] : []),
    ];
    const status = why.length === 0 ? 'ok' : (failed.length === 2 || screenErr) ? 'error' : 'warn';
    await logRun(t0, status, { un: a.entries, uae: b.entries, sources_ok: usable.length, screened: screenErr ? 0 : 1 },
      why.length
        ? why.join(' | ') + '; registered suppliers were screened against ' + (screenErr ? 0 : usable.length)
          + ' of 2 sanctions sources this week'
        : 'screened registered suppliers against both sanctions lists (' + a.entries + ' UN + ' + b.entries + ' UAE names)');
    return why.length
      ? J({ ok: false, error: why.join(' | ').slice(0, 400), un: a, uae: b, screen })
      : J({ ok: true, un: a, uae: b, screen });
  } catch (e) {
    const why = String((e as Error)?.message || e);
    await logRun(t0, 'error', { stage: 'run' }, 'sanctions_screen crashed: ' + why + '; no registered supplier was screened against the UN or UAE sanctions lists this week');
    return J({ ok: false, error: why }, 500);
  }
}));
