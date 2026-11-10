// @ts-nocheck
'use client';
import { panelErrorText } from '../PanelState';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { S } from './styles';

// WHAT THIS COMPANY CAN QUOTE FOR is the Services tab now (15 Sep 2026, sales_engineer):
// ./supplier/ServicesTab.tsx, over supplier_api services_* (docs/api/supplier_portal_services.md). It
// supersedes CapabilityConfirmPanel, which lived here: same confirm, same ledger, services inside trades.

// WHY A CLAIM WAS REFUSED, IN THE SUPPLIER'S LANGUAGE (SP-C-10).
//
// supplier_api's `claim` answers `invalid_link` as a stable code and its two 409s as English
// sentences only (supplier_api/index.ts action 'claim'), so the code is read first and the sentence
// is the fallback — the same order loginErr uses. Anything this table does not know falls to
// PanelState's bilingual "could not load" line rather than to the server's English.
const CLAIM_REFUSAL = {
  invalid_link: { en: 'This invitation link is not valid, so your company listing was not attached. You can still register below, or write to info@quotesdone.com and we will attach it for you.',
    ar: 'رابط الدعوة غير صالح، فلم يُربط سجل شركتكم بحسابكم. يمكنكم إكمال التسجيل أدناه، أو مراسلتنا على info@quotesdone.com لنربطه نيابةً عنكم.' },
  not_found: { en: 'We could not find the listing this invitation points to, so nothing was attached. You can still register below.',
    ar: 'لم نعثر على السجل الذي تشير إليه هذه الدعوة، فلم يُربط شيء. يمكنكم إكمال التسجيل أدناه.' },
  already_claimed: { en: 'This company has already been claimed by another account — most likely a colleague registered it first. Ask them to add you, or register your own account below.',
    ar: 'سبق أن طالب حساب آخر بهذه الشركة، والأرجح أن أحد زملائكم سجّلها قبلكم. يمكنكم أن تطلبوا منه إضافتكم، أو إكمال تسجيل حسابكم أدناه.' },
  other_company: { en: 'Your account already manages another company, so this listing was not attached to it. Sign in with the account you want to use, or register below.',
    ar: 'حسابكم يدير شركة أخرى بالفعل، فلم يُربط هذا السجل به. يُرجى تسجيل الدخول بالحساب الذي ترغبون في استخدامه، أو إكمال التسجيل أدناه.' },
};
export function claimRefusalKey(j) {
  const c = String((j && j.code) || '');
  if (CLAIM_REFUSAL[c]) return c;
  // 24 Sep 2026: a listing whose name or licence another account already claimed is refused with the
  // same code create_company uses; panelErrorText renders it from serverCopy.ts (no second copy).
  if (c === 'company_already_registered') return c;
  const e = String((j && j.error) || '');
  if (/invalid_link/i.test(e)) return 'invalid_link';
  if (/not found/i.test(e)) return 'not_found';
  if (/already claimed/i.test(e)) return 'already_claimed';
  if (/already manages another company/i.test(e)) return 'other_company';
  return 'load_failed';
}
function ClaimRefusal({ code, lang, onClose }) {
  const ar = lang === 'ar';
  const c = CLAIM_REFUSAL[code];
  return (
    <div className={S.wrap} style={{ paddingBottom: 0 }}>
      <Card role="alert" className="qd-panel border-warn/50 p-5" dir={ar ? 'rtl' : 'ltr'}>
        <div className={S.h2}>{ar ? 'لم يُربط سجل شركتكم' : 'Your company listing was not attached'}</div>
        <div className={cn(S.sub, 'mt-1')}>{c ? (ar ? c.ar : c.en) : panelErrorText(ar ? 'ar' : 'en', code)}</div>
        <Button className="mt-3" variant="outline" onClick={onClose}>{ar ? 'متابعة التسجيل' : 'Continue registering'}</Button>
      </Card>
    </div>
  );
}
export { ClaimRefusal };
