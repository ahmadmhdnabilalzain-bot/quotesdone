'use client';
// THE ACCOUNT AND MESSAGES TABS' FIRST READS, STARTED BEFORE THE TAB IS PRESSED (28 Sep 2026, it_engineer
// with sales_engineer). Measured on the 24 Sep walk: Messages 5.8 s, Billing 5.7 s, Settings 7.8 s — each
// tab fetched only on mount, and three of its four functions (messages_api, supplier_pay, supplier_api's
// settings path) were still cold at that moment. Once the dashboard has rendered, the portal issues these
// reads in the background; the tab's FIRST mount takes the in-flight answer (me/prefetch take: handed out
// once, to the same token), and every later load reads fresh. Only idempotent reads are listed here.
import { warm, take } from '@/components/me/prefetch';
import { call } from './api';

const READS = {
  'sup_tab:mailbox': (tk: string) => call('messages_api', { action: 'mailbox' }, tk),
  'sup_tab:projects': (tk: string) => call('supplier_api', { action: 'projects' }, tk),
  'sup_tab:billing': (tk: string) => call('supplier_pay', { action: 'list' }, tk),
  'sup_tab:settings': (tk: string) => call('supplier_api', { action: 'settings' }, tk),
} as const;
export type TabRead = keyof typeof READS;

export function warmTabs(token: string): void {
  for (const k of Object.keys(READS) as TabRead[]) warm(token, k, () => READS[k](token));
}

/** The first mount's read: the warmed answer when there is one for this token, a fresh read otherwise. */
export function firstRead(token: string | null | undefined, key: TabRead): Promise<any> {
  return take(token || '', key, () => READS[key](token || ''));
}
