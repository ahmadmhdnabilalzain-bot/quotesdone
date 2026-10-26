// THE MONTHLY SOCIAL CALENDAR THE FOUNDER APPROVES (marketing, 23 Sep 2026).
//
// Founder, founder_instruction 871: "It has the video link that I can press and open it ... the caption used,
// the hashtag used, like each one in a column, and the name of the video. So it should be extremely organized
// calendar that I check every month." One function turns the LOADED ROWS (marketing_post + its variants) into
// the calendar's rows; the PDF table (pdf_native's renderer, the company template) and the spreadsheet are both
// drawn from those rows, so neither can say something the posts do not. The caption cell is the variant's
// stored `body` -- the EXACT text Postiz receives, hashtags included at its end -- and the hashtags cell lists
// them again on their own so he can scan them (content review of #870: he approves the composed text).
// Tested in marketing_calendar_doc.test.ts.

export interface CalPost {
  ingest_key: string; scheduled_at: string; scheduled_local: string | null; title: string | null; cta_url: string | null;
  video_path: string | null; video_sha256: string | null;
  variants: Array<{ platform: string; seq: number; language: string; post_type: string; body: string; hashtags: string[];
                    title: string | null; alt_text: string | null; first_comment: string | null }>;
}
export interface CalRow {
  n: number; date: string; time: string; platform: string; video: string; video_url: string | null;
  caption: string; hashtags: string; link: string; alt_text: string; extra: string;
}

const PLATFORM: Record<string, string> = { instagram: 'Instagram', facebook: 'Facebook', linkedin: 'LinkedIn', x: 'X', youtube: 'YouTube', tiktok: 'TikTok' };
const TYPE: Record<string, string> = { reel: 'Reel', short: 'Short', post: 'Post', video: 'Video' };
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** Dubai wall clock of a UTC instant (UTC+4 all year). */
export function dubai(utc: string): { date: string; time: string } {
  const d = new Date(Date.parse(utc) + 4 * 3600_000);
  return { date: `${DAYS[d.getUTCDay()]} ${String(d.getUTCDate()).padStart(2, '0')} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`,
           time: `${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}` };
}

/** One row per platform post in time order; a thread (X) shows its parts in the caption cell, numbered. */
export function calendarRows(posts: CalPost[], videoUrls: Record<string, string>): CalRow[] {
  const sorted = [...posts].sort((a, b) => a.scheduled_at.localeCompare(b.scheduled_at) || a.ingest_key.localeCompare(b.ingest_key));
  return sorted.map((p, i) => {
    const vs = [...p.variants].sort((a, b) => a.seq - b.seq);
    const first = vs[0];
    const { date, time } = dubai(p.scheduled_at);
    const caption = vs.length > 1
      ? vs.map((v, k) => `(${k + 1}/${vs.length}) ` + v.body).join('\n\n')
      : (first ? first.body : '');
    const extra = [first?.title ? 'YouTube title: ' + first.title : '', first?.first_comment ? 'First comment: ' + first.first_comment : '']
      .filter(Boolean).join(' · ');
    return {
      n: i + 1, date, time,
      platform: (PLATFORM[first?.platform || ''] || first?.platform || '?') + (first ? ' · ' + (TYPE[first.post_type] || first.post_type) : ''),
      video: p.title || (p.video_path || '').split('/').pop() || '',
      video_url: p.video_path ? videoUrls[p.video_path] || null : null,
      caption, hashtags: (first?.hashtags || []).map((h) => '#' + h).join(' '),
      link: p.cta_url || '', alt_text: first?.alt_text || '', extra,
    };
  });
}

/** pdf_native blocks: a cover summary, the calendar TABLE, and the approval instruction with the content hash. */
export function calendarBlocks(c: { campaign_key: string; theme: string; month: string; hash: string; expires: string },
                               rows: CalRow[], frames: Array<{ video: string; bytes: Uint8Array; kind: 'jpg' | 'png' }>) {
  const blocks: unknown[] = [
    { t: 'kv', pairs: [['Campaign', c.campaign_key], ['Theme', c.theme], ['Month', c.month], ['Posts', String(rows.length)],
                       ['Spend', 'Organic only: no ads, no boosting'], ['Content reference', c.hash]] },
    { t: 'section', text: 'The calendar' },
    { t: 'table', fs: 6.2, zebra: true,
      head: ['#', 'Date', 'Dubai time', 'Platform', 'Video', 'Caption used', 'Hashtags used', 'Link'],
      widths: [0.035, 0.09, 0.065, 0.1, 0.13, 0.35, 0.13, 0.1],
      rows: rows.map((r) => [String(r.n), r.date, r.time, r.platform,
        r.video_url ? { text: r.video, link: r.video_url, sub: 'Press to open the video' } : { text: r.video, sub: 'no video link' },
        { text: r.caption, sub: [r.alt_text ? 'Alt text: ' + r.alt_text : '', r.extra].filter(Boolean).join(' · ') || undefined },
        r.hashtags, r.link ? { text: r.link, link: r.link } : '']) },
  ];
  if (frames.length) {
    blocks.push({ t: 'section', text: 'The videos (key frame)' });
    for (const fr of frames) { blocks.push({ t: 'h3', text: fr.video }); blocks.push({ t: 'image', bytes: fr.bytes, kind: fr.kind, w: 150 }); }
  }
  blocks.push({ t: 'section', text: 'To approve' });
  blocks.push({ t: 'p', text: 'Reply to this email with the single word "approve" (or "موافق"). That approves every post above exactly as shown, and nothing else. To change anything, reply saying what; a corrected calendar will be sent and this one will no longer be approvable.' });
  blocks.push({ t: 'note', text: `Content reference ${c.hash}. Any change to a caption, hashtag, time, video or link after this document was made changes the reference and voids an approval. The video links open the private master files and stop working after ${c.expires}.` });
  return blocks;
}

/** The same rows as a spreadsheet (array of arrays; the caller writes it with the vendored SheetJS). */
export function calendarSheet(rows: CalRow[]): { aoa: string[][]; links: Array<{ r: number; c: number; url: string }> } {
  const aoa = [['#', 'Date', 'Dubai time', 'Platform', 'Video', 'Video link', 'Caption used', 'Hashtags used', 'Link', 'Alt text', 'Other']];
  const links: Array<{ r: number; c: number; url: string }> = [];
  rows.forEach((r, i) => {
    aoa.push([String(r.n), r.date, r.time, r.platform, r.video, r.video_url ? 'Open video' : '', r.caption, r.hashtags, r.link, r.alt_text, r.extra]);
    if (r.video_url) links.push({ r: i + 1, c: 5, url: r.video_url });
    if (r.link) links.push({ r: i + 1, c: 8, url: r.link });
  });
  return { aoa, links };
}
