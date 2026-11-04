// The CSV's columns and its price row are quote_compare's roster: every live quote, cheapest first, at quote_compare's
// price (journey run 41459344864 step 46: four live quotes, the model's detail capped at three). Pure: no network.
import { assertEquals } from 'jsr:@std/assert@1';
import { compareTable, toCsv } from './quote_documents.ts';

// The analysis as quote_compare returns it: `quotes` is the model's detail (three), `all_quotes` the roster (four).
const ANALYSIS = {
  quotes: [{ label: 'Supplier A – Option 1', price: 118500, lead_time: '21 days' }, { label: 'Supplier B', price: 124900, lead_time: '21 days' }, { label: 'Supplier C', price: 131000, lead_time: '21 days' }],
  all_quotes: [
    { label: 'Supplier A – Option 1', price: 118500, status: 'shortlisted', vat_treatment: 'exclusive' },
    { label: 'Supplier B', price: 124900, status: 'shortlisted', vat_treatment: 'exclusive' },
    { label: 'Supplier C', price: 131000, status: 'shortlisted', vat_treatment: 'exclusive' },
    { label: 'Supplier A – Option 2', price: 142000, status: 'received', vat_treatment: 'exclusive' },
  ],
  top3: [{ label: 'Supplier A – Option 1' }, { label: 'Supplier B' }, { label: 'Supplier C' }],
};
// The journey's own reading of the file (scripts/e2e/journeys.mjs step 46).
const parseRow = (line: string) => { const out: string[] = []; let cur = '', qd = false; for (let i = 0; i < line.length; i++) { const c = line[i]; if (qd) { if (c === '"' && line[i + 1] === '"') { cur += '"'; i++; } else if (c === '"') qd = false; else cur += c; } else if (c === '"') qd = true; else if (c === ',') { out.push(cur); cur = ''; } else cur += c; } out.push(cur); return out; };
const digits = (s: string) => Number(String(s).replace(/[^\d.]/g, '')) || 0;

Deno.test('compare_csv: every live quote is a column, cheapest first, priced as quote_compare prices it', () => {
  const side = compareTable(ANALYSIS, false)!;
  const lines = toCsv(side.head, side.rows).replace(/^﻿/, '').split(/\r\n/).filter(Boolean);
  const head = parseRow(lines[0]).slice(1);
  const price = lines.map(parseRow).find((r) => /^Price\b/.test(r[0] || ''))!.slice(1);
  const want = [...ANALYSIS.all_quotes].sort((x, y) => x.price - y.price);
  assertEquals(head, want.map((x) => x.label));
  assertEquals(price.map(digits), want.map((x) => x.price), 'the price row is quote_compare\'s roster prices, none empty');
});

Deno.test('KNOWN-BAD CONTROL: the step-46 reading before 2 Nov (a row named exactly "Price") finds no price row at all', () => {
  const side = compareTable(ANALYSIS, false)!;
  const rows = toCsv(side.head, side.rows).replace(/^﻿/, '').split(/\r\n/).filter(Boolean).map(parseRow);
  assertEquals(rows.find((r) => r[0] === 'Price'), undefined);
});
