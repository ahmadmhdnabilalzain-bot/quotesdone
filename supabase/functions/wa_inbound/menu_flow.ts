// One WhatsApp turn through the welcome and menu (customer_support, 22 Sep 2026, instruction 759).
//
// Everything with a side effect arrives as a dependency, so menu_flow.test.ts drives the real routing
// with fakes and index.ts supplies the database and Twilio. menuTurn decides; it never guesses:
//   - an interactive list reply (ListId / ButtonPayload), a typed option title, or — only right after
//     we offered the menu — a bare number, selects an option;
//   - a message REASONED to be only a hello or a request for the menu (d.meaning, _shared/reasoned_menus.ts)
//     gets the welcome and the menu, whatever came before it;
//   - the message after "Report a problem" becomes a support case with a reference number when it is reasoned
//     to describe the problem, or while that reasoning is held (the words are kept for a person, never lost);
//   - anything else returns handled:false and the existing handlers answer it FIRST (document intake,
//     the founder's command channel, the supplier price change, fn_wa_route's intents). Only if none of
//     them did, and the message is a first contact — nothing from them AND nothing from us to them in
//     24 hours (review of #841: a supplier answering "12500" to a price request sent through the
//     outbox is in-flow, not a hello) — does welcomeFirstContact open the welcome; after that,
//     reofferMenu is the last word, never a dead end.
//
// THE CAPS DO NOT APPLY HERE, AND THAT IS DELIBERATE. app_secrets.wa_daily_cap and
// wa_per_recipient_24h are enforced in send_whatsapp over the notifications outbox — business-initiated
// notices to people who may never have written to us. A menu reply answers a message the person just
// sent, inside the 24-hour window their own message opened, and goes out through wa_inbound's sendWa,
// which never touches the outbox. per_recipient_24h=1 applied here would answer "hi" and then refuse
// the option they picked from our own list. wa_autoreply_enabled still governs every send.
import {
  type Audience, caseClosedNotice, caseConfirm, type CaseResult, contentKey, founderCommand, greetLine, type Lang, langOf, MENU_HINT, MENU_IDS, menuAsText, menuChoice, type MenuId, type MenuContext, optionReply, sorryLead, welcomeText, WELCOME_TAIL,
} from './menu.ts';
import { coverageReply, mightBeCoverage, type Trade } from './coverage.ts';
import { capabilityAnswer, figuresText, type Figures, isFiguresCommand, isSizeQuestion } from './founder_queries.ts';

export type Turn = { route: string | null; await: string | null; lang: Lang | null };
export type SendResult = { ok: boolean; err?: string };
export type Content = { sid: string; variables: Record<string, string> };
export type MenuMeaning = 'greeting' | 'salam' | 'problem' | 'other';
export type MenuDeps = {
  /** What this message means to the menu, REASONED (_shared/reasoned_menus.ts menuMeaning); null while held. */
  /** `offerMenu`: the options may be picked by typing (only right after we showed the menu, never for the founder). */
  meaning(text: string, awaitingProblem: boolean, offerMenu: boolean): Promise<MenuMeaning | MenuId | null>;
  autoreplyEnabled(): Promise<boolean>;
  /** This number's wa_messages rows in the last 24 hours, newest first, excluding the current message. */
  recentTurns(from: string): Promise<Turn[]>;
  /** True if WE sent this number anything in the last 24 hours (the notifications outbox). */
  weWroteRecently(from: string): Promise<boolean>;
  /** fn_wa_menu_context: audience by CONFIRMED number, name, approval, own open requests. */
  context(from: string): Promise<MenuContext>;
  /** fn_faq_answer with the gte-small embedding: a corroborated answer from the approved FAQ, or null. */
  faq(text: string): Promise<string | null>;
  /** public.taxonomy_trade, active rows in table order: the list fn_match_capability matches on. */
  trades(): Promise<Trade[]>;
  /** fn_support_knowledge_gap: the unanswered question is filed for the team. False if it could not be. */
  recordGap(text: string, reason: string): Promise<boolean>;
  /** fn_founder_whatsapp_figures: the founder's readings, on the FIGURES command only; {ok:false} for any other number. */
  founderFigures(from: string): Promise<Figures>;
  /** fn_wa_problem_report: opens a support case, or adds to the one this number/account already has open. */
  openCase(from: string, text: string, lang: Lang): Promise<CaseResult>;
  /** fn_wa_human_request: hands the conversation to a person (handoff + hold) and alerts the founder. */
  notifyHuman(from: string, ctx: MenuContext, text: string): Promise<boolean>;
  /** fn_wa_human_hold: true while this number waits for a person, so the seat stays quiet. */
  humanHold(from: string): Promise<boolean>;
  /** Founder commands. fn_support_case_close answers the reporter's number and language (or nulls). */
  closeCase(ref: string, reason: string): Promise<{ ok: boolean; phone?: string | null; lang?: Lang; reason?: string }>;
  /** fn_wa_human_request_close: how many open requests from that number were closed. */
  closeHuman(phone: string): Promise<number>;
  contentSid(key: string): Promise<string | null>;
  send(to: string, body: string, content?: Content): Promise<SendResult>;
  record(row: { inbound: string; reply: string; lang: Lang; sent: boolean; route: string; await: string | null;
                send_error: string | null; extra: Record<string, unknown> }): Promise<void>;
};
export type MenuInput = { from: string; body: string; listId?: string; buttonPayload?: string; audience: Audience; hasMedia?: boolean };

/** Send `text` (or the interactive `content`, falling back to `fallback`), then record the turn. */
async function reply(d: MenuDeps, inp: MenuInput, lang: Lang, route: string, text: string, awaitNext: string | null,
                     extra: Record<string, unknown>, content?: Content, fallback?: string) {
  const enabled = await d.autoreplyEnabled();
  let sent = false; let err: string | null = null; let via = 'text';
  if (enabled && content) {
    const r = await d.send(inp.from, text, content);
    sent = r.ok; err = r.err || null; via = 'content';
    // The interactive list can be refused (no approval needed in-session, but a client or a Twilio error
    // can still refuse it). The numbered menu says the same thing, so nobody is left unanswered.
    if (!sent && fallback) {
      const f = await d.send(inp.from, fallback);
      sent = f.ok; err = f.ok ? null : (f.err || err); via = 'text_fallback'; text = fallback;
    }
  } else if (enabled) {
    if (!content && fallback) text = fallback;
    const r = await d.send(inp.from, text);
    sent = r.ok; err = r.err || null;
  }
  await d.record({ inbound: String(inp.body || '').trim(), reply: text, lang, sent, route, await: awaitNext,
                   send_error: err, extra: { ...extra, via, autoreply_enabled: enabled } });
}

/** A question's answer: coverage from the live trade list first (it has an exact answer), then the
 *  approved FAQ. Null when neither has a confident one. */
async function answerOf(d: MenuDeps, text: string): Promise<string | null> {
  if (mightBeCoverage(text)) {
    const cov = coverageReply(text, await d.trades(), langOf(text));
    if (cov) return cov;
  }
  return d.faq(text);
}

async function sendMenu(d: MenuDeps, inp: MenuInput, lang: Lang, ctx: MenuContext, route: string, lead: string | null,
                        more: Record<string, unknown> = {}, salam = false) {
  const key = contentKey(lang, ctx.audience);
  const sid = await d.contentSid(key);
  // Content body = {{1}} + WELCOME_TAIL, so the text we record is exactly what the list shows.
  const line = lead ?? greetLine(lang, ctx.audience, ctx.name, salam);
  const shown = lead === null ? welcomeText(lang, ctx.audience, ctx.name, salam) : line + '\n\n' + WELCOME_TAIL[lang];
  await reply(d, inp, lang, route, shown, null, { ...more, audience: ctx.audience, content_key: key, content_sid: sid },
    sid ? { sid, variables: { '1': line } } : undefined, menuAsText(lang, ctx.audience, lead === null ? shown : line));
}

export async function menuTurn(d: MenuDeps, inp: MenuInput): Promise<{ handled: boolean; route?: string }> {
  const body = String(inp.body || '').trim();

  // 0a. The founder closes what the menu opened (instruction 763: nothing is one-way). His number only.
  if (inp.audience === 'founder') {
    const cmd = founderCommand(body);
    if (cmd?.kind === 'close_case') {
      const r = await d.closeCase(cmd.ref, cmd.reason || 'resolved');
      let notice: { sent: boolean; err?: string } | null = null;
      if (r.ok && r.phone) {
        const s = await d.send('whatsapp:+' + r.phone.replace(/[^0-9]/g, ''), caseClosedNotice(r.lang || 'en', cmd.ref, r.reason || cmd.reason));
        notice = { sent: s.ok, err: s.err };
      }
      const txt = !r.ok ? 'No open case ' + cmd.ref + ' was found; nothing was closed.'
        : 'Case ' + cmd.ref + ' is closed. ' + (!r.phone ? 'The reporter had no WhatsApp number on the case.'
          : notice?.sent ? 'The reporter was told on WhatsApp.' : 'The WhatsApp notice to the reporter failed (' + (notice?.err || 'unknown') + '); the email on their account, if any, carries it.');
      await reply(d, inp, 'en', 'founder_close_case', txt, null, { case_ref: cmd.ref, closed: r.ok, reporter_notice: notice });
      return { handled: true, route: 'founder_close_case' };
    }
    if (cmd?.kind === 'close_human') {
      const n = await d.closeHuman(cmd.phone);
      await reply(d, inp, 'en', 'founder_close_human', n
        ? 'Closed. Automatic replies to +' + cmd.phone + ' are back on.'
        : 'No open request for a person from +' + cmd.phone + ' was found.', null, { phone: cmd.phone, closed: n });
      return { handled: true, route: 'founder_close_human' };
    }
  }

  // 0a'. FIGURES / «أرقام» as the whole message: his internal reading (instruction 777). His number only;
  //      Exact-token command on HIS number only (decision point wa_inbound.figures_command: a structured command,
  //      not a reading of meaning). From anyone else the word is ordinary text: nothing is matched on it, and the
  //      figures routine refuses every other number anyway.
  if (inp.audience === 'founder' && isFiguresCommand(body)) {
    const lang = langOf(body);
    const f = await d.founderFigures(inp.from);
    await reply(d, inp, lang, 'founder_figures', figuresText(f, lang), null, { audience: 'founder', read: f?.ok === true });
    return { handled: true, route: 'founder_figures' };
  }

  // 0b. Handed to a person: the seat does not talk over the human (instruction 763). The message is
  //     recorded for the team and nothing is sent, until the founder closes it or the 23-hour follow-up
  //     (fn_wa_human_request_tick) hands the conversation back. Never the founder's own number: his
  //     command channel must keep working while he tests the menu.
  if (inp.audience !== 'founder' && await d.humanHold(inp.from)) {
    await d.record({ inbound: body, reply: '', lang: langOf(body), sent: false, route: 'held_for_human', await: null,
                     send_error: null, extra: { held_for_human: true, has_media: !!inp.hasMedia, autoreply_enabled: await d.autoreplyEnabled() } });
    return { handled: true, route: 'held_for_human' };
  }

  // A document belongs to document intake, whatever it says in the caption.
  if (inp.hasMedia) return { handled: false };
  const recent = await d.recentTurns(inp.from);
  const last = recent[0] || null;
  const lastWasMenu = !!last?.route && /^menu_(welcome|reoffer)$/.test(last.route);
  const awaiting = last?.route?.startsWith('menu_') ? last.await : null;
  const choice = menuChoice({ body, listId: inp.listId, buttonPayload: inp.buttonPayload, numbers: lastWasMenu });
  // A bare number carries no language; the menu it answers does.
  const lang: Lang = langOf(body, last?.lang || 'en');

  // 0c. A question about our size or volumes, from ANY number, the founder's included (instruction 777):
  //     what we do, never a number. Taken before every other handler so no FAQ row, fn_wa_route intent
  //     or model can answer it with a count.
  if (isSizeQuestion(body)) {
    await reply(d, inp, lang, 'capability_answer', capabilityAnswer(lang), null, { audience: inp.audience, size_question: true });
    return { handled: true, route: 'capability_answer' };
  }

  // What the message MEANS to the menu is reasoned, once (menuMeaning); null while held — never a word list.
  // The menu's options are offered to the reasoning ONLY right after we showed the menu (a typed title answers it),
  // never mid-conversation or for the founder: a reading must not page a person or skip a case on its own.
  const offerMenu = lastWasMenu && inp.audience !== 'founder';
  const meaning = !choice && body ? await d.meaning(body, awaiting === 'problem', offerMenu) : null;
  // A typed option (its title, or plainly asking for it) is REASONED to that option (decision point wa_inbound.menu_choice).
  const picked: MenuId | null = choice ?? (offerMenu && (MENU_IDS as readonly string[]).includes(String(meaning)) ? meaning as MenuId : null);

  // 1. The message after "Report a problem": reasoned to describe the problem, it is the case. Held, the words are
  //    kept as the case all the same — a person reads them, nothing is lost and they get a reference; only a
  //    message REASONED to be a hello or something else is not filed.
  if (!picked && awaiting === 'problem' && body && (meaning === 'problem' || meaning === null)) {
    const c = await d.openCase(inp.from, body, lang);
    await reply(d, inp, lang, 'menu_case', caseConfirm(lang, c), null, { case_ref: c.ref, case_appended: !!c.appended, meaning: meaning ?? 'held' });
    return { handled: true, route: 'menu_case' };
  }

  // 2. An option.
  if (picked) {
    const choice = picked;
    const ctx = await d.context(inp.from);
    const extra: Record<string, unknown> = { choice, audience: ctx.audience };
    if (choice === 'qd_person') extra.founder_notified = await d.notifyHuman(inp.from, ctx, body);
    if (choice === 'qd_follow') extra.requests_listed = (ctx.requests || []).length;
    const next = choice === 'qd_problem' ? 'problem' : choice === 'qd_general' ? 'question' : null;
    await reply(d, inp, lang, 'menu_' + choice, optionReply(choice, lang, ctx), next, extra);
    return { handled: true, route: 'menu_' + choice };
  }

  // 3. Reasoned to be only a greeting or a request for the menu: the welcome, even mid-conversation — they asked for it.
  //    Anything substantive is NOT taken here; it goes to its own handler first (welcomeFirstContact).
  if (meaning === 'greeting' || meaning === 'salam') {
    await sendMenu(d, inp, lang, await d.context(inp.from), 'menu_welcome', null, { meaning }, meaning === 'salam');
    return { handled: true, route: 'menu_welcome' };
  }

  // 4. After "General question": a confident FAQ answer; otherwise the normal route answers it.
  if (awaiting === 'question' && body) {
    const ans = await answerOf(d, body);
    if (ans) {
      await reply(d, inp, lang, 'menu_answer', ans + MENU_HINT[lang], null, { faq: true });
      return { handled: true, route: 'menu_answer' };
    }
  }
  return { handled: false };
}

/** A substantive first contact that no handler claimed: the FAQ answer if confident, then the welcome
 *  and the menu. Called by index.ts AFTER document intake, the founder channel, the supplier price
 *  change and fn_wa_route. Not a first contact — they wrote to us, or WE wrote to them (a notice, a
 *  price request), in the last 24 hours — returns false: the reply is in-flow, not a hello. */
export async function welcomeFirstContact(d: MenuDeps, inp: MenuInput): Promise<boolean> {
  if (inp.hasMedia || inp.audience === 'founder') return false;
  const body = String(inp.body || '').trim();
  if ((await d.recentTurns(inp.from)).length > 0 || await d.weWroteRecently(inp.from)) return false;
  const lang = langOf(body);
  const ctx = await d.context(inp.from);
  const ans = body ? await answerOf(d, body) : null;
  if (ans) await reply(d, inp, lang, 'menu_first_answer', ans, null, { audience: ctx.audience, faq: true });
  await sendMenu(d, inp, lang, ctx, 'menu_welcome', null);
  return true;
}

/** Free text that is not a menu choice: a confident answer from the approved FAQ (the same corpus and
 *  routine the site assistant uses), sent with the MENU hint. False when the FAQ has no confident answer. */
export async function answerFromFaq(d: MenuDeps, inp: MenuInput): Promise<boolean> {
  const body = String(inp.body || '').trim();
  if (!body) return false;
  const ans = await answerOf(d, body);
  if (!ans) return false;
  const lang = langOf(body);
  await reply(d, inp, lang, 'faq_answer', ans + MENU_HINT[lang], null, { faq: true, audience: inp.audience });
  return true;
}

/** The last word when nothing else could answer: the menu again, in their language. */
export async function reofferMenu(d: MenuDeps, inp: MenuInput, lead: string): Promise<void> {
  await sendMenu(d, inp, langOf(inp.body), { audience: inp.audience, name: null }, 'menu_reoffer', lead);
}

/** The founder's question that nothing could answer gets exactly what a customer gets (instruction 780,
 *  22 Sep 2026): the courteous line and the menu. He tests as a customer would, so no internal wording (figures,
 *  the model, the hold) ever appears in a normal reply; the figures are only ever the answer to FIGURES. */
export async function founderUnanswered(d: MenuDeps, inp: MenuInput, reason: string): Promise<void> {
  await unanswered(d, inp, reason);
}

/** Nothing could answer the question (22 Sep 2026). It is filed for the team (fn_support_knowledge_gap)
 *  and the person gets the courteous line and the menu, with "Talk to a person" on it. `reason` is kept
 *  in the record for the team; it is never shown. */
export async function unanswered(d: MenuDeps, inp: MenuInput, reason: string): Promise<void> {
  const body = String(inp.body || '').trim();
  const recorded = body ? await d.recordGap(body, reason) : false;
  const lang = langOf(body);
  await sendMenu(d, inp, lang, { audience: inp.audience, name: null }, 'menu_reoffer', sorryLead(lang, recorded),
    { unanswered_reason: reason, gap_recorded: recorded });
}
