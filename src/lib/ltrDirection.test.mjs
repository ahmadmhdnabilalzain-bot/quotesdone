// ltrDirection.test.mjs — the one rule <Ltr> enforces, in both directions.
//   node --test src/lib/ltrDirection.test.mjs
//
// Two ways to get this wrong, and the fix for each caused the other historically:
//   forcing ltr onto Arabic  -> the licence chip read "سبتمبر 2027 18" (the defect, 17 Sep 2026)
//   letting auto take a number -> "+971 50 931 9355" inherits the page's RTL and its groups scramble
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isRtlText, dirFor } from './ltrDirection.ts';

test('a localised Arabic date is NOT forced left-to-right', () => {
  // Exactly what toLocaleDateString('ar-AE', {day:'numeric',month:'short',year:'numeric'}) returns.
  for (const d of ['18 سبتمبر 2026', '24 يونيو 2027', '١٨ سبتمبر ٢٠٢٦']) {
    assert.equal(dirFor(d), 'auto', d);
  }
});

test('a genuinely left-to-right string IS forced left-to-right', () => {
  for (const s of ['+971 50 931 9355', 'AED 12,500', '18 Sep 2026', 'ARQ-1042', 'a@b.example', '1633275', 'quote.pdf', '4/5']) {
    assert.equal(dirFor(s), 'ltr', s);
  }
});

test('Arabic-Indic digits are not direction: a number written in them still gets the LTR force', () => {
  // These live inside U+0600-06FF, so a naive block test calls them RTL and sends the exact string
  // shape the force exists for down the `auto` path. They are AN/EN class and carry no direction.
  for (const s of ['١٢٣', '+٩٧١ ٥٠ ٩٣١ ٩٣٥٥', '١٢٬٥٠٠', '٥٠٪', '۱۲۳']) {
    assert.equal(dirFor(s), 'ltr', s);
  }
  assert.equal(isRtlText('٢٠٢٦'), false);
  // ...but one real Arabic letter anywhere still counts.
  assert.equal(isRtlText('٢٠٢٦ سبتمبر'), true);
});

test('a stray byte-order mark does not flip the branch', () => {
  assert.equal(dirFor('﻿invoice-2026.pdf'), 'ltr');
});

test('Hebrew counts as right-to-left too', () => {
  assert.equal(dirFor('שלום'), 'auto');
});

test('an empty or neutral-only string is left-to-right, never inherited', () => {
  for (const s of ['', '—', '  ', '0']) assert.equal(dirFor(s), 'ltr', JSON.stringify(s));
});
