// reasoned_menus — what a WhatsApp message means to the welcome menu, reasoned, never matched.
// Seat: customer_support. 23 Sep 2026, founder_instruction 886-903 (ledger 890: no word matching anywhere).
//
// Decision points 16 wa_inbound.greeting_state and 17 wa_inbound.problem_state. wa_inbound/menu.ts decided a
// message was "just a hello" or "the word MENU" from GREETINGS / MENU_WORDS lists (isGreeting, isMenuWord), and a
// Wa-alaikum-salam reply from a regex (isSalam); after "Report a problem" any other text became a case by flow
// state alone. Now the meaning is reasoned:
//   greeting — a hello, or a request for the menu/options, and nothing else
//   salam    — the same, greeted with as-salamu alaikum (answered wa alaikum as-salam)
//   problem  — (only after "Report a problem") the message describes what went wrong
//   other    — anything else: it goes to its own handler
// Held (the model hold): null. menu_flow.ts then never guesses: after "Report a problem" the words are kept as the
// case (a person reads them — nothing is lost and they get a reference); anywhere else the message goes on to the
// other handlers, whose last word is the menu (reofferMenu). Nothing is queued: by the time the hold lifts the
// conversation has moved on, so a late reading of this turn has no effect to apply.
import { think, type ThinkDeps } from './think.ts';
import type { Reasoned } from './reasoned_decisions.ts';

export type MenuMeaning = 'greeting' | 'salam' | 'problem' | 'other';

export async function menuMeaning(deps: ThinkDeps, o: { text: string; awaitingProblem: boolean; messageSid?: string }): Promise<Reasoned<MenuMeaning>> {
  const options: { id: MenuMeaning; meaning: string }[] = [
    { id: 'greeting', meaning: 'only a greeting, or only a request to see the menu / the options, and nothing else' },
    { id: 'salam', meaning: 'only a greeting that uses as-salamu alaikum (in any spelling), and nothing else' },
    ...(o.awaitingProblem ? [{ id: 'problem' as const, meaning: 'the person describes a problem or something that went wrong (they were just asked to)' }] : []),
    { id: 'other', meaning: 'anything else: a question, a request, an answer, a document, a number' },
  ];
  const result = await think(deps, {
    seat: 'customer_support', surface: o.awaitingProblem ? 'wa_inbound.problem_state' : 'wa_inbound.greeting_state',
    question: o.text.slice(0, 2000), queueWhenHeld: false,
    dedupeKey: o.messageSid ? 'wa_menu:' + o.messageSid : undefined,
    context: { audience: 'customer' },
    decision: { name: 'menu_meaning', options },
  });
  const choice = result.status === 'answered' ? result.decision?.choice ?? null : null;
  return { value: options.some((x) => x.id === choice) ? choice as MenuMeaning : null, result };
}
