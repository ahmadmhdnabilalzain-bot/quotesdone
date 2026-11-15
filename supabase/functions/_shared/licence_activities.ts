// A LICENCE'S ACTIVITIES ARE READ ONE TO AN ELEMENT (15 Nov 2026, customer_support; supplier registration certification, founder
// ruling 1620: invite only once the registration "reads their trade licence"). Measured in the paid certification of 15 Nov 2026
// (2 runs, live): run 1 J3 (L3, JAFZA) read its activities as ONE item, "Building Materials Trading, Tiles and Ceramics Trading,
// Sanitary Ware Trading", and run 2 J9 (L9, Dubai DET) as "Interior Decoration Works, Building Maintenance". The same licences read
// as three and two items in the other run. Every licence of the corpus (L1-L10) prints its activities as a comma list in one cell;
// the reading asked for them "copied exactly as printed", and once in eight it copied the cell.
//
// THE FIX IS AT THE READING (rulings 1663, 1664: the model reads, code only checks). Both readers that return activities now ask for
// ONE array element per licensed activity, a comma list in one cell being several activities, and an activity whose own printed name
// holds a comma kept whole (licence_extract.SYS_LICENSE, supplier_profile_reading.profileReadSystem).
//
// THIS IS THE GROUNDED BACKSTOP, AND ONLY THAT. An element is split at its commas (or semicolons, Arabic commas) only when the
// document's own text shows every piece as an activity of its own: each piece is a whole line of the text (or a whole cell of a line:
// cells are split at a tab, a run of two or more spaces or a " | "; or the value after a "Label:"), after a list marker ("1.", "-",
// "•"), and the element is not printed whole as one run of the text (a list that only wraps across lines is one cell). A piece may
// keep a comma when the text prints it so. Nothing else splits. It never splits on what the words mean, so
// "Air-Conditioning, Ventilation & Air Filtration Systems Installation" printed on a line of its own stays one activity
// ("Air-Conditioning" is no line of its own). It does NOT fire on a licence that prints the list in one cell (L3, L9 and every licence of the corpus): there
// the document gives code no evidence, and the reading carries it. Where it fires: a scan or photo, whose text is the vision model's
// own list one to a line (supplier_doc_trades.modelReadText), read again by the profile reading that joined them; a licence that
// prints its activities as table rows. Prevented by _shared/a_licence_activity_is_one_element.test.ts.

const SEP = /[,،;؛]/;
/** A line or a cell, compared: lower case, one space, no list marker, no trailing separator or full stop. */
const key = (s: string) => String(s ?? '').normalize('NFKC').toLowerCase()
  .replace(/^\s*(?:\(?\d{1,2}[.)]|\(?[a-z][.)]|[-–•*·▪])\s+/u, '')
  .replace(/[\s,،;؛.]+$/u, '').replace(/\s+/g, ' ').trim();

/** Every line of the text and every cell of every line, compared by `key`. */
export function printedOnTheirOwn(text: string | null | undefined): Set<string> {
  const out = new Set<string>();
  for (const line of String(text ?? '').split(/\r?\n/)) {
    const k = key(line); if (k) out.add(k);
    for (const cell of line.split(/\t| {2,}|\s\|\s/)) { const c = key(cell); if (c) out.add(c); }
    // "Activities: A" / "Activity | A": the value after a label on its line is a cell of its own
    const m = line.match(/^[^:：]{2,40}[:：]\s*(.+)$/u); if (m) { const c = key(m[1]); if (c) out.add(c); }
  }
  return out;
}

/** An element cut at its separators into consecutive runs, each run printed on its own in the text; null when no such cut of two or
 *  more runs exists. A run may hold a comma ("Air-Conditioning, Ventilation & Air Filtration Systems Installation" printed on its own
 *  line is one run), so the comma inside an activity's own name is never cut. */
function cutAsPrinted(a: string, own: Set<string>): string[] | null {
  const cuts = [0]; for (let i = 0; i < a.length; i++) if (SEP.test(a[i])) cuts.push(i + 1);
  const ends = [...cuts.slice(1).map((c) => c - 1), a.length];   // a run from cuts[i] ends just before the separator at ends[j]
  // best[i]: the runs that cover a from cuts[i] to its end, or null
  const best: (string[] | null)[] = new Array(cuts.length + 1).fill(null);
  best[cuts.length] = [];
  for (let i = cuts.length - 1; i >= 0; i--) {
    for (let j = i; j < cuts.length; j++) {
      const run = a.slice(cuts[i], ends[j]).trim();
      const rest = best[j + 1];
      if (rest && run.length >= 3 && own.has(key(run))) { best[i] = [run, ...rest]; break; }
    }
  }
  return best[0] && best[0].length >= 2 ? best[0] : null;
}

/** The activities as the reader returned them, an element split at its separators only where the document's own text prints each
 *  part on its own (see the header). Order kept, duplicates dropped, nothing else changed. */
export function activitiesAsPrinted(activities: readonly unknown[] | null | undefined, text: string | null | undefined): string[] {
  const acts = (Array.isArray(activities) ? activities : []).map((a) => String(a ?? '').replace(/\s+/g, ' ').trim()).filter(Boolean);
  const own = String(text ?? '').trim() ? printedOnTheirOwn(text) : null;
  // the text read as one run (lines joined, every separator one ", "): an element found whole in it is printed as one list in one
  // place, its line breaks only wrapping (L2's "... Windows Manufacturing,\nWooden Furniture Fixing"), so it is never split
  const flat = (s: string) => String(s ?? '').normalize('NFKC').toLowerCase().replace(/\s*[,،;؛]\s*/g, ', ').replace(/\s+/g, ' ').trim();
  const run = own ? flat(String(text)) : '';
  const out: string[] = [];
  const push = (a: string) => { if (!out.some((x) => key(x) === key(a))) out.push(a); };
  for (const a of acts) {
    // an element printed whole on its own is that activity, whatever commas it holds
    const runs = own && SEP.test(a) && !own.has(key(a)) && !run.includes(flat(a)) ? cutAsPrinted(a, own) : null;
    if (runs) runs.forEach(push); else push(a);
  }
  return out;
}
