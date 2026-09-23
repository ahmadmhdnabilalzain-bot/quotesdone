// reasoned_documents — decision points of the documents we show and issue, reasoned instead of word-matched.
// Seat: sales_engineer. 23 Sep 2026, founder_instruction 886-903 (ledger 890: no word matching anywhere).
//
// documents.boq_arabic: which Arabic heading a BOQ section means. It was a regex list over the section's
// words (boq_arabic.ts SECTION_AR) plus a service-alias fallback. Now think() chooses among the glossary
// headings (boq_arabic.ts SECTIONS) or 'none'; the reading is remembered per section text in
// boq_section_reading, so each heading is reasoned once. Under the hold the question is filed once per
// section text (dedupeKey) and the heading shows in its original words until the replay writes the reading
// (fn_reason_apply_documents__boq_arabic).
import { think, type ThinkDeps } from './think.ts';
import type { Reasoned } from './reasoned_decisions.ts';
import { SECTIONS, sectionKey, sectionsToRead } from './boq_arabic.ts';

export const BOQ_ARABIC_SURFACE = 'documents.boq_arabic';

/** One section heading: which glossary heading does it mean? */
export async function sectionReading(deps: ThinkDeps, o: { section: string }): Promise<Reasoned<string>> {
  const key = sectionKey(o.section);
  const result = await think(deps, {
    seat: 'sales_engineer', surface: BOQ_ARABIC_SURFACE,
    question: `A bill of quantities has a section headed "${o.section.slice(0, 200)}". Which heading does it mean?`,
    dedupeKey: 'boq_section:' + key, subject: { section_key: key, section: o.section.slice(0, 200) },
    context: { audience: 'internal' },
    decision: {
      name: 'boq_section',
      options: [
        ...SECTIONS.map((s) => ({ id: s.id, meaning: `the section is ${s.meaning}` })),
        { id: 'none', meaning: 'none of these headings says what the section is (a project area, a bill number, a mixed or unclear heading)' },
      ],
    },
  });
  return { value: result.status === 'answered' ? result.decision?.choice ?? null : null, result };
}

// deno-lint-ignore no-explicit-any
type Admin = any;
export interface ReadingStore {
  remembered(keys: string[]): Promise<Record<string, string>>;
  remember(key: string, section: string, reading: string): Promise<void>;
}
export function liveReadingStore(admin: Admin): ReadingStore {
  return {
    remembered: async (keys) => {
      if (!keys.length) return {};
      const { data } = await admin.from('boq_section_reading').select('section_key,reading').in('section_key', keys);
      return Object.fromEntries((data || []).map((r: { section_key: string; reading: string }) => [r.section_key, r.reading]));
    },
    remember: async (key, section, reading) => {
      await admin.from('boq_section_reading').upsert({ section_key: key, section, reading, reasoned_by: 'reasoning' }, { onConflict: 'section_key' });
    },
  };
}

/** At most this many unread headings are reasoned per read; the rest wait for the next read (their originals show). */
export const READS_PER_CALL = 8;

/** The readings for every section of the given BOQs: remembered ones, plus up to READS_PER_CALL newly reasoned. */
export async function boqReadings(deps: ThinkDeps, store: ReadingStore, boqs: unknown[]): Promise<Record<string, string>> {
  const sections = new Map<string, string>();
  for (const b of boqs) for (const s of sectionsToRead(b)) if (!sections.has(sectionKey(s))) sections.set(sectionKey(s), s);
  if (!sections.size) return {};
  const readings = await store.remembered([...sections.keys()]);
  const unread = [...sections.entries()].filter(([k]) => !(k in readings)).slice(0, READS_PER_CALL);
  await Promise.all(unread.map(async ([k, s]) => {
    const r = await sectionReading(deps, { section: s });
    if (r.value) { readings[k] = r.value; await store.remember(k, s, r.value); }
  }));
  return readings;
}
