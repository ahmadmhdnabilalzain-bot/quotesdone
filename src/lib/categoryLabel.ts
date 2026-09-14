// A trade/category as the customer should read it. Categories arrive from the database as slugs or
// loose English ("hvac", "Fit-Out", "painting"); an Arabic page printed them raw (portal audit
// 14 Sep 2026). The Arabic words are the ones already held in src/content/categories.json.
import cats from '@/content/categories.json';

const ACRONYMS = new Set(['HVAC', 'MEP', 'AV', 'IT', 'CCTV', 'BOQ', 'DB', 'MDB']);
const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, '');

const INDEX = new Map<string, { en: string; ar: string }>();
for (const c of cats.items) {
  INDEX.set(norm(c.code), c);
  INDEX.set(norm(c.en), c);
  // "HVAC / Air Conditioning", "Plumbing & Sanitary": the first part alone is how a request names it.
  INDEX.set(norm(c.en.split(/\s*[/&(]\s*/)[0]), c);
}

/** "hvac" -> "HVAC", "fit-out" -> "Fit-Out", "painting" -> "Painting". */
function cased(s: string): string {
  return s.replace(/[A-Za-z]+/g, (w) => (ACRONYMS.has(w.toUpperCase()) ? w.toUpperCase() : w[0].toUpperCase() + w.slice(1).toLowerCase()));
}

export function categoryLabel(name: string, lang: string): string {
  const raw = String(name ?? '').trim();
  if (!raw) return raw;
  const hit = INDEX.get(norm(raw));
  if (lang === 'ar' && hit) return hit.ar;
  return cased(raw.replace(/[_]+/g, ' '));
}
