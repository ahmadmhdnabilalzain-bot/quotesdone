// WHERE HE WORKS, AS PROFILE SHOWS IT (12 Nov 2026, sales_engineer, built by it_engineer; walk of 12 Nov 2026, blocker B1).
// The emirates he works in are one list, edited in one place: Services, "Where you work". Profile shows the same list, read from
// `me` (supplier_api answers service_emirates as the matcher's one list, supabase/functions/_shared/where_he_works.ts), with the
// way to Services. The words are Services' own (servicesCopy.ts), so the two screens name it the same. English only (ruling 1008).
// Guard: src/components/portal/supplier/whereYouWork.test.mjs
import { FLOW_COPY as F } from './servicesCopy.ts';

export const WHERE_YOU_WORK = {
  title: F.where,
  note: 'Requests from these emirates reach you. You set this in Services.',
  change: 'Change where you work',
} as const;

const SEVEN = ['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'];

/** The list as one line, exactly as Services prints it: the emirates by name, or Services' own words when none is set. */
export function whereYouWorkLine(list: unknown): string {
  const on = Array.isArray(list) ? SEVEN.filter((e) => list.includes(e)) : [];
  return on.length ? on.join(', ') : F.where_all;
}
