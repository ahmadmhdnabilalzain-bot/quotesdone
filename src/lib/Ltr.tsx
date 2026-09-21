// THE ONE `Ltr`. Five files each carried their own `const Ltr = ({children}) => <bdi dir="ltr">…`
// and the copies were identical, so the same defect existed five times over.
//
// THE DEFECT (production journey, 17 Sep 2026): `dir="ltr"` was being forced onto strings that are
// not LTR. `fmtDate(d, 'ar')` returns "18 سبتمبر 2026" — Arabic. Laid out as an LTR paragraph the
// bidi algorithm reorders it and the licence chip read "سبتمبر 2027 18", while the same date
// unwrapped, a few pixels below, read correctly. Measured at 7 sites, all in SupplierPortal.tsx.
//
// THE RULE lives in ./ltrDirection.ts, with its reasoning and its tests: force LTR only for a
// string that is GENUINELY left-to-right, never for a localised date or any text carrying RTL
// script. This file is the JSX half — it works out what text the children actually are and hands
// that to the rule. The <bdi> isolates either way, which is the part that stops an Arabic label and
// a Latin value interleaving.
import * as React from 'react';
// The rule itself, in plain TypeScript so it can be unit-tested without JSX: ltrDirection.test.mjs.
// In particular it knows that Arabic-Indic digits are digits, not direction.
import { dirFor } from './ltrDirection';

// Children are strings, numbers and fragments of both at every call site; anything else (an
// element) is walked so a wrapped <span>{arabic}</span> is not mistaken for LTR content.
const textOf = (node: React.ReactNode): string => {
  if (node == null || typeof node === 'boolean') return '';
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (Array.isArray(node)) return node.map(textOf).join('');
  if (React.isValidElement(node)) return textOf((node.props as { children?: React.ReactNode }).children);
  return '';
};

export const Ltr = ({ children, className = '' }: { children: React.ReactNode; className?: string }) =>
  <bdi dir={dirFor(textOf(children))} className={className}>{children}</bdi>;

export default Ltr;
