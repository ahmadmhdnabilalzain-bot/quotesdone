#!/usr/bin/env node
// px_to_scale — rewrite arbitrary Tailwind literals onto the named brand scale (the @theme block in src/app/globals.css).
//
// Why: the website audit (14 Sep 2026) measured 749 [Npx] font sizes, 30 [var(--line)] brackets and
// 9 unnamed corner radii across src/**/*.tsx. The tokens now exist; this moves call sites onto them.
//
//   node scripts/codemods/px_to_scale.mjs [paths...]          dry run: per-file counts, no writes
//   node scripts/codemods/px_to_scale.mjs --write [paths...]  apply
//   node scripts/codemods/px_to_scale.mjs --self-test         assert the mapping
// Default path is src. Only className-shaped tokens are touched (a literal inside a JS string that
// is not a class would be too, so review the dry-run list before --write, and run it only on files
// you own).
//
// Size mapping is deliberate, not nearest-neighbour: everything below 12px goes UP to `label` (12px),
// the accessibility floor, so a rewrite can enlarge tiny text but never shrink anything.
import { readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { join, extname } from 'node:path';

const SIZE = (px) =>
  px <= 12 ? 'label' : px <= 13 ? 'small' : px <= 14 ? 'body' : px <= 15.5 ? 'copy' : null;
const RADIUS = { 9: 'chip', 10: 'chip', 11: 'chip', 12: 'chip', 14: 'panel', 22: 'card' };
const CLAMP = { 'clamp(40px,7vw,84px)': 'display', 'clamp(30px,4.4vw,54px)': 'display-sm' };
const HEX = { '#7C97A3': 'faint', '#7c97a3': 'faint', '#123041': 'surf', '#14303E': 'redact', '#14303e': 'redact' };

// Variant prefixes (md:, hover:, ...) stay attached because we only rewrite the utility after them.
const B = '(?<=^|[\\s"\'`:])'; // token boundary: start, whitespace, quote or a variant colon
export function transform(src) {
  let n = 0;
  const rep = (re, fn) => { src = src.replace(re, (...m) => { const r = fn(...m); if (r !== m[0]) n++; return r; }); };
  rep(new RegExp(`${B}text-\\[(\\d+(?:\\.\\d+)?)px\\]`, 'g'), (m, px) => { const t = SIZE(+px); return t ? `text-${t}` : m; });
  rep(new RegExp(`${B}text-\\[(clamp\\([^\\]\\s]+\\))\\]`, 'g'), (m, c) => (CLAMP[c] ? `text-${CLAMP[c]}` : m));
  rep(new RegExp(`${B}rounded(-[a-z]{1,2})?-\\[(\\d+)px\\]`, 'g'), (m, side, px) => (RADIUS[px] ? `rounded${side || ''}-${RADIUS[px]}` : m));
  rep(new RegExp(`${B}([a-z]+(?:-[a-z]+)?)-\\[var\\(--(line2?)\\)\\]`, 'g'), (m, util, tok) => `${util}-${tok}`);
  rep(new RegExp(`${B}(text|bg|border)-\\[(#[0-9a-fA-F]{6})\\]`, 'g'), (m, util, hex) => (HEX[hex] ? `${util}-${HEX[hex]}` : m));
  return { src, n };
}

function selfTest() {
  const eq = (a, b) => { if (a !== b) { console.error(`FAIL\n  got:  ${a}\n  want: ${b}`); process.exit(1); } };
  eq(transform('className="text-[10.5px] md:text-[13px] text-[15px] text-[18px]"').src,
    'className="text-label md:text-small text-copy text-[18px]"');
  eq(transform("'rounded-[22px] rounded-t-[14px] rounded-[18px]'").src, "'rounded-card rounded-t-panel rounded-[18px]'");
  eq(transform('border-[var(--line2)] hover:border-[var(--line)] divide-[var(--line)]').src, 'border-line2 hover:border-line divide-line');
  eq(transform('text-[clamp(40px,7vw,84px)] text-[clamp(1px,2vw,3px)]').src, 'text-display text-[clamp(1px,2vw,3px)]');
  eq(transform('text-[#7C97A3] bg-[#0b1220]').src, 'text-faint bg-[#0b1220]');
  eq(transform('max-w-[52ch] mytext-[11px]').n, 0); // not a text- utility boundary
  console.log('px_to_scale self-test: ok');
}

function* files(p) {
  const s = statSync(p);
  if (s.isFile()) { if (extname(p) === '.tsx' || extname(p) === '.ts') yield p; return; }
  for (const e of readdirSync(p)) if (e !== 'node_modules' && !e.startsWith('.')) yield* files(join(p, e));
}

const args = process.argv.slice(2);
if (args.includes('--self-test')) selfTest();
else {
  const write = args.includes('--write');
  const paths = args.filter((a) => !a.startsWith('--'));
  let total = 0;
  for (const f of (paths.length ? paths : ['src']).flatMap((p) => [...files(p)])) {
    const before = readFileSync(f, 'utf8');
    const { src, n } = transform(before);
    if (!n) continue;
    total += n;
    console.log(`${String(n).padStart(4)}  ${f}`);
    if (write) writeFileSync(f, src);
  }
  console.log(`${total} replacement(s) ${write ? 'written' : '(dry run — pass --write to apply)'}`);
}
