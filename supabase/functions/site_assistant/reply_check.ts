// THE WIDGET AND PORTAL REPLY CHECK (it_engineer, 3 Nov 2026, release qualification). answerFromBrief's check ran only
// guardSupportReply (the reply rules), so a figure the brief never states, or a phone, email or licence number that is
// not in the brief or the prompt, went out on the widget's main road. It now also runs replyProblems, the same gate
// aiReply applies, against the brief and this turn's prompt (the published contact and the person's own live data are there).
// answerFromBrief runs this check per streamed SENTENCE, so the deferral rule, a whole-answer judgement (fewer than 25
// substance words), is left out, as sales_engineer's portal does: "A member of the team will contact you shortly." is
// one ordinary sentence of a full answer (review of #1836).
import { replyProblems } from '../_shared/ai_reply.ts';
import { briefNumbers, figureSource } from '../_shared/company_brief.ts';
import { guardSupportReply } from '../_shared/support_reply_guard.ts';

export function siteReplyCheck(brief: string, sys: string, lang: 'en' | 'ar'): (s: string) => string[] {
  const allowed = figureSource(brief) + '\n' + sys;
  const known = briefNumbers(allowed);
  return (s) => [...guardSupportReply(s, lang).violations.map((v) => 'it breaks the reply rule "' + v + '"'),
    ...replyProblems(s, known, { allowed }).filter((p) => !/defers/.test(p))];
}
