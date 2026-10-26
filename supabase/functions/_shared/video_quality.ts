// The marketing seat's pre-upload quality gate (founder, 24 Sep 2026: every social upload at the highest
// quality possible). Nothing in our path re-encodes a video: the bucket bytes go to Postiz as they are. So the
// only place quality is lost on OUR side is a source file below what the platform recommends, and that is what
// this refuses. The MP4 header is read here (no ffprobe in an edge function): resolution, frame rate, codec
// and the per-track bitrate from the sample-size table.
//
// Measured 24 Sep 2026 on 09_Your_Business_Belongs_Here_LoFiMix_60fps.mp4 (posts 84-88): 1080x1920,
// avc1.64002a (H.264 High 4.2), 60 fps, video 817 kbps, AAC-LC mono 44.1 kHz 151 kbps. YouTube recommends
// 12 Mbps for 1080p60, so that file would now be refused and flagged, not posted.

export interface TrackInfo { kind: 'video' | 'audio'; codec: string; width?: number; height?: number; fps?: number; kbps: number; channels?: number; sample_rate?: number }
export interface Mp4Info { duration_s: number; tracks: TrackInfo[] }

type Box = { type: string; start: number; end: number };
function boxes(d: DataView, start: number, end: number): Box[] {
  const out: Box[] = [];
  for (let p = start; p + 8 <= end;) {
    let size = d.getUint32(p); const type = String.fromCharCode(d.getUint8(p + 4), d.getUint8(p + 5), d.getUint8(p + 6), d.getUint8(p + 7));
    let hdr = 8;
    if (size === 1) { size = Number(d.getBigUint64(p + 8)); hdr = 16; } else if (size === 0) size = end - p;
    if (size < hdr || p + size > end) break;
    out.push({ type, start: p + hdr, end: p + size }); p += size;
  }
  return out;
}
const child = (d: DataView, b: Box | undefined, t: string) => b && boxes(d, b.start, b.end).find((x) => x.type === t);
const path = (d: DataView, b: Box | undefined, ...ts: string[]) => ts.reduce<Box | undefined>((acc, t) => child(d, acc, t), b);

/** Reads an MP4's header; null when it is not an MP4 this parser understands. */
export function readMp4(bytes: Uint8Array): Mp4Info | null {
  const d = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const moov = boxes(d, 0, bytes.byteLength).find((b) => b.type === 'moov');
  if (!moov) return null;
  const tracks: TrackInfo[] = []; let duration_s = 0;
  for (const trak of boxes(d, moov.start, moov.end).filter((b) => b.type === 'trak')) {
    const mdia = child(d, trak, 'mdia'); const hdlr = child(d, mdia, 'hdlr'); const mdhd = child(d, mdia, 'mdhd');
    const stbl = path(d, mdia, 'minf', 'stbl'); const stsd = child(d, stbl, 'stsd'); const stsz = child(d, stbl, 'stsz');
    if (!hdlr || !mdhd || !stsd || !stsz) continue;
    const handler = String.fromCharCode(...bytes.subarray(hdlr.start + 8, hdlr.start + 12));
    if (handler !== 'vide' && handler !== 'soun') continue;
    const v1 = d.getUint8(mdhd.start) === 1;
    const scale = d.getUint32(mdhd.start + (v1 ? 20 : 12));
    const dur = v1 ? Number(d.getBigUint64(mdhd.start + 24)) : d.getUint32(mdhd.start + 16);
    const secs = dur / scale; duration_s = Math.max(duration_s, secs);
    const fixed = d.getUint32(stsz.start + 4), count = d.getUint32(stsz.start + 8);
    let total = fixed * count;
    if (!fixed) for (let i = 0; i < count; i++) total += d.getUint32(stsz.start + 12 + 4 * i);
    const entry = boxes(d, stsd.start + 8, stsd.end)[0];
    if (!entry) continue;
    const kbps = Math.round(total * 8 / secs / 1000);
    if (handler === 'vide') {
      const avcC = boxes(d, entry.start + 78, entry.end).find((b) => b.type === 'avcC');
      const codec = entry.type + (avcC ? '.' + [1, 2, 3].map((o) => d.getUint8(avcC.start + o).toString(16).padStart(2, '0')).join('') : '');
      tracks.push({ kind: 'video', codec, width: d.getUint16(entry.start + 24), height: d.getUint16(entry.start + 26), fps: Math.round(count / secs * 100) / 100, kbps });
    } else {
      tracks.push({ kind: 'audio', codec: entry.type, channels: d.getUint16(entry.start + 16), sample_rate: d.getUint32(entry.start + 24) >>> 16, kbps });
    }
  }
  return { duration_s, tracks };
}

/**
 * Each platform's RECOMMENDED upload spec for a vertical short video, from its own page (read 24 Sep 2026).
 * A value a page does not state is not invented: only YouTube publishes a bitrate recommendation.
 */
export const UPLOAD_FLOOR: Record<string, { width: number; height: number; fps: number; video_kbps?: number; audio_kbps?: number; source: string }> = {
  // 1080p at 48-60 fps: 12 Mbps SDR; 24-30 fps: 8 Mbps. Audio: AAC-LC, 384 kbps stereo.
  youtube:   { width: 1080, height: 1920, fps: 24, video_kbps: 8000, audio_kbps: 384, source: 'https://support.google.com/youtube/answer/1722171' },
  instagram: { width: 1080, height: 1920, fps: 23, source: 'https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-user/media' },
  facebook:  { width: 1080, height: 1920, fps: 24, source: 'https://developers.facebook.com/docs/video-api/guides/reels-publishing' },
  tiktok:    { width: 1080, height: 1920, fps: 23, source: 'https://support.tiktok.com/en/using-tiktok/creating-videos/upload-videos' },
  linkedin:  { width: 1080, height: 1920, fps: 10, source: 'https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/videos-api' },
};

/** Every way this video falls below the platform's recommended upload spec; [] when it meets it. */
export function belowUploadSpec(platform: string, info: Mp4Info | null): string[] {
  const f = UPLOAD_FLOOR[platform];
  if (!f) return [];
  if (!info) return [`${platform}: the video header could not be read, so its quality is unproven`];
  const v = info.tracks.find((t) => t.kind === 'video'); const a = info.tracks.find((t) => t.kind === 'audio');
  const out: string[] = [];
  if (!v) return [`${platform}: no video track`];
  if (!/^avc1|^avc3/.test(v.codec)) out.push(`${platform}: codec ${v.codec}, H.264 recommended`);
  if ((v.width ?? 0) < f.width || (v.height ?? 0) < f.height) out.push(`${platform}: ${v.width}x${v.height} below ${f.width}x${f.height}`);
  if ((v.fps ?? 0) < f.fps) out.push(`${platform}: ${v.fps} fps below ${f.fps}`);
  // YouTube's table: 12 Mbps at 48-60 fps, 8 Mbps at 24-30 fps.
  const vk = f.video_kbps && (v.fps ?? 0) > 31 ? 12000 : f.video_kbps;
  if (vk && v.kbps < vk) out.push(`${platform}: video ${v.kbps} kbps below the recommended ${vk} kbps`);
  if (f.audio_kbps && a && a.kbps < f.audio_kbps) out.push(`${platform}: audio ${a.kbps} kbps${a.channels === 1 ? ' mono' : ''} below the recommended ${f.audio_kbps} kbps stereo`);
  return out.map((m) => m + ' (' + f.source + ')');
}
