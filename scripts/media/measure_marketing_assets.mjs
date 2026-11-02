// measure_marketing_assets — the marketing seat's DETERMINISTIC eyes and ears on its own videos (build item 6).
// marketing, 23 Sep 2026; founder instructions 865 and 867. Owner: the marketing seat.
//
// WHERE IT RUNS, AND WHY. An edge function cannot run ffmpeg (no subprocess, 2 s CPU). This runs on GitHub Actions
// (.github/workflows/marketing-asset-features.yml), where ubuntu's own apt packages give ffmpeg/ffprobe/tesseract,
// the same way scripts/cad_read_worker.ts reads what the edge cannot. It reaches the database through the
// management API (SUPABASE_ACCESS_TOKEN) and storage with the service key that API reveals.
//
// WHAT IT MEASURES, per MP4 under marketing-media/campaigns/*/videos/:
//   file sha256, bytes, duration, resolution/aspect, fps; scene cuts (ffmpeg scene score > 0.30), cuts per 10 s,
//   cuts and mean frame difference in the first 3 s (the hook proxy); audio present, EBU R128 loudness and true
//   peak; the speech-band energy share (300-3400 Hz) as a voice-over PROXY; on-screen text by tesseract over
//   1 frame/s; key frames (0.5 s, every cut up to 6, the midpoint) uploaded to marketing-media/features/<sha>/;
//   and the music on file (track, bpm, mood) from the campaign Manifest.csv inside the archived zip.
// SAME FILE => SAME FEATURES: every value comes from the file and pinned tool options; --check-determinism
// measures each file twice and fails if any field differs. The toolchain versions are recorded with the row.
//
// ponytail: speech_band_ratio is a coarse proxy — lo-fi music also carries mid-band energy. It is recorded with
// voiceover_suspected at a fixed threshold only to CROSS-CHECK the perception step (marketing_watch), which
// listens; a disagreement is flagged, never treated as truth. Upgrade path: a VAD model in this job.
//
//   node scripts/media/measure_marketing_assets.mjs --check-determinism [--limit=2]   # measure twice, no write
//   node scripts/media/measure_marketing_assets.mjs --write                           # record + upload key frames
//   node scripts/media/measure_marketing_assets.mjs --fixture=<file.mp4>             # measure a local file twice; no network, no secrets
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { pickApiKey } from '../lib/supabase_keys.mjs';   // new keys first; legacy only as a temporary fallback (27 Oct 2026)

export const EXTRACTOR_VERSION = 'mf-1';
const REF = 'htdblwldjkcgjvmqkbeh';
const BASE = `https://${REF}.supabase.co`;
const BUCKET = 'marketing-media';
const MANIFEST_ZIP = { bucket: 'backups', path: 'marketing/2026-month1-supplier-recruitment/QuotesDone_All_12_Unique_LoFi_Videos.zip' };
const SCENE = 0.30, VOICE_RATIO = 0.55, TEXT_MIN_CHARS = 8;

const args = process.argv.slice(2);
const WRITE = args.includes('--write');
const TWICE = args.includes('--check-determinism');
const FIXTURE = (args.find((a) => a.startsWith('--fixture=')) || '').slice(10);
const LIMIT = Number((args.find((a) => a.startsWith('--limit=')) || '').slice(8)) || Infinity;

const token = () => { const t = process.env.SUPABASE_ACCESS_TOKEN; if (!t) throw new Error('SUPABASE_ACCESS_TOKEN is not set'); return t.trim(); };
async function sql(query) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' }, body: JSON.stringify({ query }) });
  if (!r.ok) throw new Error('sql ' + r.status + ': ' + (await r.text()).slice(0, 300));
  return r.json();
}
let _key;
async function serviceKey() {
  if (_key) return _key;
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`, { headers: { Authorization: 'Bearer ' + token() } });
  const k = await r.json();
  _key = Array.isArray(k) ? pickApiKey(k, 'secret') : undefined;
  if (!_key) throw new Error('no service_role key from the management API');
  return _key;
}
const enc = (p) => p.split('/').map(encodeURIComponent).join('/');
async function download(bucket, path) {
  const r = await fetch(`${BASE}/storage/v1/object/${bucket}/${enc(path)}`, { headers: { apikey: await serviceKey(), Authorization: 'Bearer ' + await serviceKey() } });
  if (!r.ok) throw new Error(`download ${bucket}/${path}: ${r.status}`);
  return Buffer.from(await r.arrayBuffer());
}
async function upload(bucket, path, bytes, type) {
  const r = await fetch(`${BASE}/storage/v1/object/${bucket}/${enc(path)}`, {
    method: 'POST', headers: { apikey: await serviceKey(), Authorization: 'Bearer ' + await serviceKey(), 'Content-Type': type, 'x-upsert': 'true' }, body: bytes });
  if (!r.ok) throw new Error(`upload ${bucket}/${path}: ${r.status} ${(await r.text()).slice(0, 200)}`);
}

const run = (cmd, a) => execFileSync(cmd, a, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 << 20 });
// ffmpeg writes its filter reports to stderr: return both streams, fail on a non-zero exit.
function require_spawn(cmd, a) {
  const r = spawnSync(cmd, a, { encoding: 'utf8', maxBuffer: 64 << 20 });
  if (r.status !== 0) throw new Error(`${cmd} ${a.join(' ')} exited ${r.status}: ${String(r.stderr).slice(-400)}`);
  return String(r.stderr) + String(r.stdout);
}
const r3 = (n) => (n == null || !Number.isFinite(n) ? null : Math.round(n * 1000) / 1000);

export function parseRate(s) { const [a, b] = String(s || '0/1').split('/').map(Number); return b ? a / b : a; }
export function parseCutTimes(log) { return [...log.matchAll(/pts_time:([0-9.]+)/g)].map((m) => Number(m[1])); }
export function parseEbur128(log) {
  const sum = log.slice(log.lastIndexOf('Summary:'));
  const i = sum.match(/I:\s+(-?[0-9.]+|-inf)\s+LUFS/); const p = sum.match(/Peak:\s+(-?[0-9.]+|-inf)\s+dBFS/);
  const n = (m) => (m && m[1] !== '-inf' ? Number(m[1]) : null);
  return { lufs: n(i), peak: n(p) };
}
export function parseRmsDb(log) { const m = [...log.matchAll(/Overall[\s\S]*?RMS level dB:\s+(-?[0-9.]+|-inf)/g)].pop(); return m && m[1] !== '-inf' ? Number(m[1]) : null; }
export function parseYavg(log) { const v = [...log.matchAll(/lavfi\.signalstats\.YAVG=([0-9.]+)/g)].map((m) => Number(m[1])); return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null; }
export function aspectOf(w, h) { const g = (a, b) => (b ? g(b, a % b) : a); const d = g(w, h) || 1; return `${w / d}:${h / d}`; }

function parseCsv(text) {
  const rows = []; let row = [], cell = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; } else if (c === '"') q = false; else cell += c; }
    else if (c === '"') q = true; else if (c === ',') { row.push(cell); cell = ''; }
    else if (c === '\n' || c === '\r') { if (c === '\r' && text[i + 1] === '\n') i++; row.push(cell); rows.push(row); row = []; cell = ''; }
    else cell += c;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  const [head, ...body] = rows.filter((r) => r.some((x) => x.trim()));
  return body.map((r) => Object.fromEntries(head.map((h, i) => [h.trim(), (r[i] ?? '').trim()])));
}
/** The manifest row for a video: the row naming its file, else the row with the same leading number. */
export function musicFor(manifest, fileName) {
  const num = (fileName.match(/^(\d+)/) || [])[1];
  const row = manifest.find((r) => Object.values(r).some((v) => v && v.length >= 4 && !/^\d+$/.test(v) && fileName.includes(v.replace(/\.mp4$/i, ''))))
    || manifest.find((r) => Object.values(r).some((v) => num && new RegExp('^0*' + Number(num) + '(\\D|$)').test(v)));
  if (!row) return { on_file: false };
  const pick = (re) => { const k = Object.keys(row).find((h) => re.test(h)); return k ? row[k] : null; };
  const bpm = pick(/bpm|tempo/i);
  return { on_file: true, track: pick(/track|music|song|audio/i), bpm: bpm && /\d/.test(bpm) ? Number(bpm.match(/[\d.]+/)[0]) : null,
           mood: pick(/mood|vibe|feel/i), row };
}

export function measure(file, dir) {
  const probe = JSON.parse(run('ffprobe', ['-v', 'error', '-print_format', 'json', '-show_streams', '-show_format', file]));
  const v = probe.streams.find((s) => s.codec_type === 'video');
  const hasAudio = probe.streams.some((s) => s.codec_type === 'audio');
  const duration = Number(probe.format.duration);
  const cuts = parseCutTimes(require_spawn('ffmpeg', ['-hide_banner', '-nostats', '-i', file, '-vf', `select='gt(scene,${SCENE})',showinfo`, '-an', '-f', 'null', '-']));
  const motion = parseYavg(require_spawn('ffmpeg', ['-hide_banner', '-nostats', '-t', '3', '-i', file, '-vf',
    'scale=270:480,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG', '-an', '-f', 'null', '-']));
  let lufs = null, peak = null, ratio = null;
  if (hasAudio) {
    ({ lufs, peak } = parseEbur128(require_spawn('ffmpeg', ['-hide_banner', '-nostats', '-i', file, '-vn', '-af', 'ebur128=peak=true', '-f', 'null', '-'])));
    const full = parseRmsDb(require_spawn('ffmpeg', ['-hide_banner', '-nostats', '-i', file, '-vn', '-af', 'astats=metadata=0', '-f', 'null', '-']));
    const band = parseRmsDb(require_spawn('ffmpeg', ['-hide_banner', '-nostats', '-i', file, '-vn', '-af', 'highpass=f=300,lowpass=f=3400,astats=metadata=0', '-f', 'null', '-']));
    ratio = full != null && band != null ? Math.pow(10, (band - full) / 10) : null;
  }
  // on-screen text: 1 frame/s, tesseract, deterministic single-thread
  const fdir = join(dir, 'f1s'); mkdirSync(fdir, { recursive: true });
  require_spawn('ffmpeg', ['-hide_banner', '-nostats', '-i', file, '-vf', 'fps=1,scale=720:-2', '-an', join(fdir, '%03d.png')]);
  const frames = readdirSync(fdir).filter((f) => f.endsWith('.png')).sort();
  const chars = frames.map((f) => (spawnSync('tesseract', [join(fdir, f), '-', '--psm', '11'], { encoding: 'utf8', env: { ...process.env, OMP_THREAD_LIMIT: '1' } }).stdout || '')
    .replace(/[^A-Za-z0-9\u0600-\u06FF]/g, '').length);
  // key frames
  const times = [...new Set([0.5, ...cuts.slice(0, 6).map((t) => r3(t + 0.2)), r3(duration / 2)])].filter((t) => t < duration).sort((a, b) => a - b);
  const keyframes = times.map((t, i) => {
    const out = join(dir, `kf_${i}.jpg`);
    require_spawn('ffmpeg', ['-hide_banner', '-nostats', '-ss', String(t), '-i', file, '-frames:v', '1', '-vf', 'scale=540:-2', '-q:v', '3', '-y', out]);
    return { t, local: out };
  });
  return {
    duration_s: r3(duration), width: v.width, height: v.height, aspect: aspectOf(v.width, v.height), fps: r3(parseRate(v.avg_frame_rate || v.r_frame_rate)),
    scene_cuts: cuts.length, cuts_per_10s: r3(duration ? (cuts.length / duration) * 10 : 0), hook_cuts_first_3s: cuts.filter((t) => t < 3).length,
    hook_motion_first_3s: r3(motion), audio_present: hasAudio, loudness_lufs: r3(lufs), true_peak_db: r3(peak),
    speech_band_ratio: r3(ratio), voiceover_suspected: ratio == null ? null : ratio > VOICE_RATIO,
    frames_sampled: frames.length, frames_with_text: chars.filter((c) => c >= TEXT_MIN_CHARS).length,
    text_chars_per_frame: r3(frames.length ? chars.reduce((a, b) => a + b, 0) / frames.length : 0),
    keyframes_local: keyframes,
  };
}

/** The pull-request proof: a local file, measured twice, compared field by field and frame by frame. */
function fixtureDeterminism(file) {
  const dir = mkdtempSync(join(tmpdir(), 'mkt-fx-'));
  const strip = (x) => ({ ...x, keyframes_local: x.keyframes_local.map((k) => ({ t: k.t, sha: createHash('sha256').update(readFileSync(k.local)).digest('hex') })) });
  const a = strip(measure(file, mkdtempSync(join(dir, 'a-')))), b = strip(measure(file, mkdtempSync(join(dir, 'b-'))));
  rmSync(dir, { recursive: true, force: true });
  if (!isDeepStrictEqual(a, b)) throw new Error('NOT DETERMINISTIC on the fixture:\n' + JSON.stringify(a) + '\n' + JSON.stringify(b));
  console.log(JSON.stringify({ fixture: file, deterministic: true, features: a }));
}

async function main() {
  if (FIXTURE) return fixtureDeterminism(FIXTURE);
  const listed = await sql(`select name, (metadata->>'size')::bigint size from storage.objects where bucket_id = '${BUCKET}'
                             and name ~ '^campaigns/[^/]+/videos/[^/]+\\.mp4$' order by name`);
  const videos = listed.slice(0, LIMIT);
  if (!videos.length) throw new Error('no videos found under marketing-media/campaigns/*/videos/');
  const work = mkdtempSync(join(tmpdir(), 'mkt-'));
  let manifest = [];
  try {
    writeFileSync(join(work, 'm.zip'), await download(MANIFEST_ZIP.bucket, MANIFEST_ZIP.path));
    const names = run('unzip', ['-Z1', join(work, 'm.zip')]).split('\n').filter((n) => /manifest\.csv$/i.test(n));
    if (names[0]) manifest = parseCsv(execFileSync('unzip', ['-p', join(work, 'm.zip'), names[0]], { encoding: 'utf8' }));
  } catch (e) { console.error('manifest not read (music will be recorded as not on file):', e.message); }
  const toolchain = { ffmpeg: run('ffmpeg', ['-version']).split('\n')[0], tesseract: run('tesseract', ['--version']).split('\n')[0] };
  const report = [];
  for (const v of videos) {
    const dir = mkdtempSync(join(work, 'v-')); const file = join(dir, 'in.mp4');
    const bytes = await download(BUCKET, v.name); writeFileSync(file, bytes);
    const sha = createHash('sha256').update(bytes).digest('hex');
    const a = measure(file, join(dir));
    if (TWICE) {
      const b = measure(file, mkdtempSync(join(dir, 'again-')));
      const strip = (m) => ({ ...m, keyframes_local: m.keyframes_local.map((k) => ({ t: k.t, sha: createHash('sha256').update(readFileSync(k.local)).digest('hex') })) });
      if (!isDeepStrictEqual(strip(a), strip(b))) throw new Error(`NOT DETERMINISTIC for ${v.name}:\n${JSON.stringify(strip(a))}\n${JSON.stringify(strip(b))}`);
    }
    const fileName = v.name.split('/').pop();
    const keyframes = [];
    for (const [i, k] of a.keyframes_local.entries()) {
      const path = `features/${sha}/kf_${i}.jpg`;
      if (WRITE) await upload(BUCKET, path, readFileSync(k.local), 'image/jpeg');
      keyframes.push({ t: k.t, bucket: BUCKET, path });
    }
    const { keyframes_local, ...m } = a;
    const row = { file_sha256: sha, extractor_version: EXTRACTOR_VERSION, asset_bucket: BUCKET, asset_path: v.name, bytes: bytes.length,
                  ...m, keyframes, music: musicFor(manifest, fileName), toolchain };
    if (WRITE) await sql(`select public.fn_marketing_asset_feature_record('${JSON.stringify(row).replace(/'/g, "''")}'::jsonb)`);
    report.push({ asset: fileName, sha: sha.slice(0, 12), duration_s: row.duration_s, fps: row.fps, aspect: row.aspect, cuts: row.scene_cuts,
                  audio: row.audio_present, lufs: row.loudness_lufs, text_frames: `${row.frames_with_text}/${row.frames_sampled}`,
                  music: row.music.on_file ? `${row.music.bpm ?? '?'} bpm ${row.music.mood ?? ''}` : 'not on file', deterministic: TWICE ? 'identical on re-run' : 'not checked' });
    rmSync(dir, { recursive: true, force: true });
  }
  rmSync(work, { recursive: true, force: true });
  console.table(report);
  console.log(JSON.stringify({ measured: report.length, written: WRITE, determinism_checked: TWICE }));
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('measure_marketing_assets.mjs')) {
  main().catch((e) => { console.error(e.message); process.exit(1); });
}
