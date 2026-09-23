// EVERY LINK WE PUBLISH NAMES THE POST (marketing, 23 Sep 2026; founder instruction 865).
//
// Tagged at calendar LOAD time (load_calendar.mjs), not at send time, so the text the founder approves, its
// hash, the calendar PDF and the platform length checks all already include the tags (#874 sends the
// approved body byte for byte). One implementation, imported by the loader (Node) and the tests (Deno).
//
// Every quotesdone.ae / quotesdone.com link gains
//   utm_source=<platform>&utm_medium=social&utm_campaign=<campaign>&utm_content=<post key>
// A hand-made campaign link (the month-1 calendar already carries source/medium/campaign) keeps its tags and
// gains only utm_content. A link that already names utm_content, and other sites' links, are left alone.
const OUR_LINK = /https?:\/\/(?:www\.)?quotesdone\.(?:ae|com)(?:\/[^\s)\]>"'«»]*)?/gi;

export function withUtm(text, platform, campaign, postKey) {
  if (typeof text !== 'string' || !text) return text;
  return text.replace(OUR_LINK, (url) => {
    const trail = url.match(/[.,;:!?،]+$/)?.[0] ?? '';
    const bare = trail ? url.slice(0, -trail.length) : url;
    if (/[?&]utm_content=/i.test(bare)) return url;
    const [base, hash] = bare.split('#');
    const q = /[?&]utm_/i.test(base) ? `utm_content=${encodeURIComponent(postKey)}`
      : `utm_source=${encodeURIComponent(platform)}&utm_medium=social&utm_campaign=${encodeURIComponent(campaign)}&utm_content=${encodeURIComponent(postKey)}`;
    return base + (base.includes('?') ? '&' : '?') + q + (hash !== undefined ? '#' + hash : '') + trail;
  });
}

/** A copy of the calendar with every link in every post's texts tagged for that post. */
export function tagCalendar(calendar) {
  const campaign = String(calendar?.campaign?.month || calendar?.campaign?.key || 'campaign');
  return {
    ...calendar,
    posts: (calendar?.posts || []).map((p) => {
      const key = String(p.key || '').toLowerCase();
      const t = (s) => withUtm(s, String(p.platform || ''), campaign, key);
      return { ...p, caption_en: t(p.caption_en), caption_ar: t(p.caption_ar), first_comment: t(p.first_comment), cta_url: t(p.cta_url) };
    }),
  };
}
