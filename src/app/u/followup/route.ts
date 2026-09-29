// /u/followup — the one-tap "did you hire, and how was the supplier?" link in the day-3 and day-14 e-mails
// (customer_support, founder_instruction 1013). GET shows the question, POST records the answer; both go to the
// customer_followup edge function through ../forwardToFunction.ts.
import { forwardToFunction } from '../forwardToFunction';

export const dynamic = 'force-dynamic';
const forward = forwardToFunction('customer_followup');
export const GET = forward;
export const POST = forward;
