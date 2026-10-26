// THE MARKETING SEAT'S LINKEDIN OUTREACH, COMPOSED (marketing, 22 Sep 2026).
//
// Founder, instruction 722: "on LinkedIn every day he texts two or three connections ... no one should feel
// he is an agent -- replies extremely professional." LinkedIn's User Agreement (section 8.2) forbids bots
// and automated messaging, and its API gives an ordinary app no member messaging and no connection list, so
// the seat never touches LinkedIn: it composes two or three messages a day for people researched from
// PUBLIC sources (marketing_prospect, every row with its source URLs), the founder receives them each
// morning as a copy-ready list, and he sends each one himself from his own account. He marks sent / replied /
// converted with one tap (marketing_outreach, the link in the list); when he pastes a reply, the seat
// drafts the follow-up.
//
// What a message may say is fixed here and grounded in the website FAQ (src/content/marketing.json faq):
// a buyer describes a job once, verified UAE suppliers quote anonymously, the buyer compares like-for-like
// and reveals only the supplier chosen. It never claims a relationship, a meeting or a mutual contact that
// does not exist, never invents a personal detail: the only personal hook is opening_line, a sentence about
// the person's COMPANY that the researcher took from a public page and cited (opening_line_url).
//
// Deterministic: variants are chosen by a hash of the prospect id, so two people at one company do not get
// the same words, and the same person always gets the same draft. Every text passes lintDraft
// (marketing_style.ts). Tested by supabase/functions/_shared/marketing_outreach.test.ts.
import { lintDraft, type Finding } from './marketing_style.ts';

export type Segment = 'developer' | 'contractor_procurement' | 'consultant' | 'facility_manager';
export type Lang = 'en' | 'ar';
export type Prospect = {
  id: number; full_name: string; company: string; segment: Segment; language: Lang;
  opening_line?: string | null;
};
export type Composed = { message: string; note: string; lint: Finding[] };

// UAE readers are served on quotesdone.ae (28 Sep 2026: every blog and outreach link points there).
export const SITE = 'https://quotesdone.ae';
export const NOTE_MAX = 300;   // LinkedIn's limit on a connection-request note

// A title the researcher left on the name ("Eng. Ahmed") is not how a founder greets a peer.
const firstName = (full: string) =>
  String(full || '').trim().split(/\s+/).filter((w, i, a) => !(i < a.length - 1 && /^(mr|mrs|ms|dr|eng|engr)\.?$/i.test(w)))[0] || '';
const pick = <T>(xs: readonly T[], id: number, salt: number) => xs[Math.abs((id * 2654435761 + salt) >>> 0) % xs.length];

const T = {
  en: {
    hello: (n: string) => `Hello ${n},`,
    intro: 'I founded QuotesDone, a Dubai-licensed platform for construction and fit-out procurement.',
    value: {
      developer: 'It lets a project team post a package once and receive anonymised, like-for-like quotes from verified UAE suppliers.',
      contractor_procurement: 'It lets a procurement team send one request and compare structured quotes from verified UAE suppliers, with no supplier calls until you choose one.',
      consultant: 'It lets consultants and their clients collect comparable quotes from verified UAE suppliers against one clear brief.',
      facility_manager: 'It lets FM teams post a maintenance or replacement job once and compare quotes from verified UAE suppliers.',
    } as Record<Segment, string>,
    ask: [
      'If it would be useful for your team, I would be glad to show you how it works.',
      'Would a short walk-through be of interest at a time that suits you?',
      'I would value your view on it, if you have a few minutes.',
    ],
  },
  ar: {
    hello: (n: string) => `السلام عليكم ${n}،`,
    intro: 'أسّستُ QuotesDone، منصة مرخّصة في دبي لطلب عروض الأسعار في قطاع البناء والتشطيبات.',
    value: {
      developer: 'تتيح المنصة لفريق المشروع طرح الحزمة مرة واحدة، واستلام عروض أسعار قابلة للمقارنة من موردين موثّقين في الإمارات دون كشف الهوية.',
      contractor_procurement: 'تتيح المنصة لفريق المشتريات إرسال طلب واحد ومقارنة عروض منظّمة من موردين موثّقين في الإمارات، ولا يتصل بكم أي مورد قبل أن تختاروه.',
      consultant: 'تتيح المنصة للاستشاريين وعملائهم جمع عروض أسعار قابلة للمقارنة من موردين موثّقين في الإمارات على أساس نطاق عمل واضح.',
      facility_manager: 'تتيح المنصة لفرق إدارة المرافق طرح أعمال الصيانة أو الاستبدال مرة واحدة، ومقارنة عروض موردين موثّقين في الإمارات.',
    } as Record<Segment, string>,
    ask: [
      'إن كان ذلك مفيدًا لفريقكم، يسعدني أن أعرض عليكم طريقة العمل باختصار.',
      'هل تسمحون بعرض موجز لطريقة عمل المنصة في الوقت الذي يناسبكم؟',
      'يسعدني أن أسمع رأيكم فيها متى سمح وقتكم.',
    ],
  },
} as const;

/** The first message (to a connection) and the connection-request note (to someone not yet connected). */
export function composeFirst(p: Prospect): Composed {
  const t = T[p.language];
  const hello = t.hello(firstName(p.full_name));
  const hook = (p.opening_line || '').trim();
  const ask = pick(t.ask, p.id, 1);
  const message = [hello, '', [hook, t.intro].filter(Boolean).join(' '), t.value[p.segment], '', ask].join('\n');
  let note = [hello, t.intro, ask].join(' ');
  if (note.length > NOTE_MAX) note = [hello, t.intro].join(' ');
  return { message, note, lint: [...lintDraft(message, 'message'), ...lintDraft(note, 'note')] };
}

export type ReplyClass = 'decline' | 'later' | 'positive' | 'question';
// WHAT A REPLY MEANS is reasoned (_shared/reasoned_outreach.ts replyClass, through think()); the regex lists that
// read it (classifyReply) are gone (23 Sep 2026, founder_instruction 886-903). This file only writes the follow-up
// for a class already decided.

const F = {
  en: {
    positive: (n: string) => `Thank you, ${n}.\n\nThe quickest way to see it is to post a real or sample package at ${SITE}: it takes a few minutes, and nothing is charged unless you choose to reveal a supplier. I am also glad to take you through it on a short call; please tell me a time that suits you.`,
    later: (n: string) => `Thank you for letting me know, ${n}. I will leave it with you; whenever a package comes up, QuotesDone is at ${SITE}.`,
    decline: (n: string) => `Understood, and thank you for replying, ${n}. I will not follow up further.`,
    question: (n: string) => `Thank you, ${n}. The detail is set out at ${SITE}/faq, and I am glad to answer anything specific in a short call or here.`,
  },
  ar: {
    positive: (n: string) => `شكرًا لكم ${n}.\n\nأسرع طريقة للتعرّف على المنصة أن تطرحوا طلبًا حقيقيًا أو تجريبيًا عبر ${SITE}، ويستغرق ذلك دقائق قليلة، ولا تُحتسب أي رسوم إلا إذا اخترتم الكشف عن هوية مورد. ويسعدني كذلك أن أشرحها لكم في اتصال قصير، فأرجو أن تحددوا الوقت المناسب لكم.`,
    later: (n: string) => `شكرًا لإفادتكم ${n}. أترك الأمر لكم، ومتى احتجتم إلى عروض أسعار فالمنصة متاحة عبر ${SITE}.`,
    decline: (n: string) => `أتفهّم ذلك تمامًا، وشكرًا على ردّكم ${n}. لن أعاود التواصل بخصوص هذا الموضوع.`,
    question: (n: string) => `شكرًا لكم ${n}. التفاصيل متاحة عبر ${SITE}/ar/faq، ويسعدني الإجابة عن أي استفسار محدد هنا أو في اتصال قصير.`,
  },
} as const;

export function composeFollowUp(p: Pick<Prospect, 'full_name' | 'language'>, cls: ReplyClass): { cls: ReplyClass; message: string; lint: Finding[] } {
  const message = F[p.language][cls](firstName(p.full_name));
  return { cls, message, lint: lintDraft(message, 'message') };
}

export type ListItem = {
  full_name: string; role_title: string; company: string; language: Lang; linkedin_url: string | null;
  message: string; note: string; link: string;
};
/** The morning email to the founder: plain text, one block per person, each with its one-tap page. */
export function founderList(day: string, items: ListItem[]): { subject: string; body: string } {
  const blocks = items.map((it, i) => [
    `${i + 1}. ${it.full_name}, ${it.role_title}, ${it.company} (${it.language === 'ar' ? 'Arabic' : 'English'})`,
    `   Profile: ${it.linkedin_url || 'not published; search LinkedIn for the name and company'}`,
    `   Message (if you are connected):`, ...it.message.split('\n').map((l) => '     ' + l),
    `   Connection note (if not):`, '     ' + it.note,
    `   Mark sent, replied or converted, or paste the reply: ${it.link}`,
  ].join('\n'));
  return {
    subject: `LinkedIn: ${items.length} people for today (${day})`,
    body: [`Today's LinkedIn list. Each is from public sources; send from your own account, then tap its link.`, '', ...blocks].join('\n\n'),
  };
}
