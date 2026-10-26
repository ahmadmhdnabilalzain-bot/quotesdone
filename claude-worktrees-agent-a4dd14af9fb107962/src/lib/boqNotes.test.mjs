// boqNotes.test.mjs — every sentence a BOQ reader can write has Arabic for the customer's screen.
// node --test src/lib/boqNotes.test.mjs
// Measured 22 Sep 2026 on /ar/me: the BOQ card's "Missing information" and the confidence "medium"
// were English. This reads the readers' SOURCE, so a sentence added to a reader tomorrow fails here
// until it has a rule in boqNotes.ts.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { boqNoteAr, boqNote, confidenceWord } from './boqNotes.ts';

const ROOT = join(import.meta.dirname, '..', '..');
const FN = join(ROOT, 'supabase', 'functions');
const READERS = [
  ...['boq_from_document', 'boq_from_sheet', 'boq_from_text', 'drawing_from_ocr', 'drawing_set', 'length_notes'].map((f) => join(FN, 'drawing_boq', f + '.ts')),
  join(FN, '_shared', 'pdf_measure.ts'),
  ...readdirSync(join(FN, '_shared', 'doc_read')).filter((f) => f.endsWith('.ts') && !/test|fixtures/.test(f)).map((f) => join(FN, '_shared', 'doc_read', f)),
];

// Reads the string literals that follow `missing.push(`, `notes.add(`, `assumptions: [`,
// `MISSING_ALWAYS = [` and the like. A template's ${…} (nested backticks included) becomes a sample
// value that looks like a file name, which every value-carrying rule accepts.
// 22 Sep 2026 (#821): also a note CONSTANT (RVT_NOTE = '...', DENSE_NOTE = (a, b) => template,
// DWG_SEND_DXF), missing.unshift(, and a reader's own empty('dwg', [ note list - the DWG/DGN/RVT asks
// and the length notes were written in those shapes and slipped past the first version of this anchor.
const ANCHOR = /\b(?:missing|notes|assumptions|MISSING_ALWAYS)\b(?:\s*:\s*string\[\])?\s*(?:\.(?:push|add|unshift)\(|=\s*\[|:\s*\[|=\s*new Set(?:<string>)?\(\[)|\b[A-Z][A-Z0-9_]*(?:_NOTE|_SEND_DXF|_ASK)\s*=\s*(?:\([^)]*\)\s*=>\s*)?|\bempty\('[a-z]+',\s*\[/g;
function literals(src, at) {
  const out = [];
  let i = at;
  for (;;) {
    while (/[\s,]/.test(src[i])) i++;
    const q = src[i];
    if (q !== "'" && q !== '"' && q !== '`') return out;
    let s = '', depth = 0;
    for (i++; i < src.length; i++) {
      const c = src[i];
      if (c === '\\') { s += src[i + 1]; i++; continue; }
      if (q === '`' && c === '$' && src[i + 1] === '{' && depth === 0) { depth = 1; i++; s += 'ZZDEMO_7.pdf'; continue; }
      if (depth) { if (c === '{') depth++; else if (c === '}') depth--; else if (c === '`') { const e = src.indexOf('`', i + 1); i = e; } continue; }
      if (c === q) break;
      s += c;
    }
    i++;
    out.push(s);
  }
}
const sentences = new Set();
for (const f of READERS) {
  const src = readFileSync(f, 'utf8');
  for (const m of src.matchAll(ANCHOR)) for (const s of literals(src, m.index + m[0].length)) sentences.add(s);
}

test('the readers were read', () => {
  assert.ok(sentences.size >= 50, `found ${sentences.size} sentences`);
  assert.ok(sentences.has('Read from the PDF text layer only: no drawing geometry was measured and no scale was applied.'));
});

// 22 Sep 2026: the binary-DXF, Revit and DGN sentences are found by the anchor (so a new one without
// Arabic fails the test below), and a queued-DWG customer never sees a sentence the screen cannot say.
test('the binary DXF, Revit and DGN sentences are among those read', () => {
  for (const s of ['The Revit version could not be read from this file.', 'This Revit file is a family (.rfa), not a project model.',
    'This is a MicroStation DGN V8 file.', 'A ZZDEMO_7.pdf x ZZDEMO_7.pdf pixel preview image was extracted from the file.',
    'Read from binary DXF: ZZDEMO_7.pdf group-code pairs.']) assert.ok(sentences.has(s), `not found by the anchor: ${s}`);
  assert.ok([...sentences].some((s) => s.startsWith('The building elements and quantities inside a Revit file')), 'RVT_IFC_ASK');
  assert.ok([...sentences].some((s) => s.startsWith('A MicroStation DGN drawing cannot be read here yet.')), 'DGN_NOTE');
});

test('every reader sentence has Arabic', () => {
  const none = [...sentences].filter((s) => !boqNoteAr(s));
  assert.deepEqual(none, [], `no Arabic for:\n  ${none.join('\n  ')}`);
  for (const s of sentences) assert.match(boqNoteAr(s), /[؀-ۿ]/, s);
});

test('the walk\'s exact card, in Arabic; English untouched', () => {
  const a = 'Read from the PDF text layer only: no drawing geometry was measured and no scale was applied.';
  assert.match(boqNote(a, 'ar'), /^قُرئ من طبقة النص/);
  assert.equal(boqNote(a, 'en'), a);
  assert.equal(boqNote('7 line(s) have no quantity written.', 'ar'), 'عدد البنود التي لا تُذكر لها كمية: 7.');
  assert.equal(confidenceWord('medium', 'ar'), 'متوسطة');
  assert.equal(confidenceWord('medium', 'en'), 'medium');
  assert.equal(confidenceWord(0.62, 'ar'), '62%');
  assert.equal(confidenceWord(null, 'ar'), '—');
});

test('a sentence that is not a reader\'s stays as written rather than being guessed', () => {
  assert.equal(boqNoteAr('Check the site: access is by road only.'), null);
});
