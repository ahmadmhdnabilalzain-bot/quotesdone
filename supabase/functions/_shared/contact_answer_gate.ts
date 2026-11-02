// WHEN THE CONTACT FORM MAY BE ANSWERED BY MAIL (2 Nov 2026, customer_support, review of #1746). The form's address is typed
// by a stranger, so an automatic answer is a mail we send where they point us. contact_submit asks this BEFORE it stores
// the message; a reason comes back as source 'held:<reason>' and trigger z55 (scripts/sql/nothing_a_person_sends_us_waits_
// without_a_seat_that_acts.sql) then holds the message for customer_support instead of letting triage answer it. The
// message is stored either way. The database adds what it alone can see: suppressions, the founder, a known supplier,
// a second message in a day and the day's ceiling.
import { judgeDns, judgeWithoutDns } from '../sales_engineer/lead_email_check.ts';
import { mxRecord, type MxRecord } from './mail_domain.ts';

export const DAY_S = 86400;
export const IP_ANSWERS_PER_DAY = 3;
export const ADDRESS_ANSWERS_PER_DAY = 2;

/** `allow(key, limit, seconds)` is the rate limiter and MUST fail closed (false) when it cannot count. */
export async function answerHold(email: string, ip: string, allow: (key: string, limit: number, seconds: number) => Promise<boolean>,
  lookup: (domain: string) => Promise<MxRecord> = (d) => mxRecord(d)): Promise<string | null> {
  const e = email.trim().toLowerCase();
  if (judgeWithoutDns(e, null)) return 'address_check';
  const dns = judgeDns(e, (await lookup(e.split('@')[1])).kind);
  if (dns.verdict === 'rejected') return 'no_mx';
  if (dns.verdict === 'retry') return 'mx_unreadable';
  if (!(await allow('contact_answer_ip:' + ip, IP_ANSWERS_PER_DAY, DAY_S))) return 'ip_daily_limit';
  if (!(await allow('contact_answer_email:' + e, ADDRESS_ANSWERS_PER_DAY, DAY_S))) return 'address_daily_limit';
  return null;
}
