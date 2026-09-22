// One WhatsApp turn through the welcome and menu (customer_support, 22 Sep 2026, instruction 759).
//
// Everything with a side effect arrives as a dependency, so menu_flow.test.ts drives the real routing
// with fakes and index.ts supplies the database and Twilio. menuTurn decides; it never guesses:
//   - an interactive list reply (ListId / ButtonPayload), a typed option title, or — only right after
//     we offered the menu — a bare number, selects an option;
//   - a greeting, MENU / قائمة, or the first message of a conversation (nothing from this number in
//     24 hours) gets the welcome and the menu;
//   - the message after "Report a problem" becomes a support case with a reference number;
//   - anything else returns handled:false and the existing route answers it; if that route has
//     nothing either, reofferMenu is the last word, never a dead end.
//
// THE CAPS DO NOT APPLY HERE, AND THAT IS DELIBERATE. app_secrets.wa_daily_cap and
// wa_per_recipient_24h are enforced in send_whatsapp over the notifications outbox — business-initiated
// notices to people who may never have written to us. A menu reply answers a message the person just
// sent, inside the 24-hour window their own message opened, and goes out through wa_inbound's sendWa,
// which never touches the outbox. per_recipient_24h=1 applied here would answer "hi" and then refuse
// the option they picked from our own list. wa_autoreply_enabled still governs every send.
import {
  type Audience, caseConfirm, contentKey, greetLine, isGreeting, isMenuWord, isSalam, type Lang, langOf,
  MENU_HINT, menuAsText, menuChoice, type MenuContext, optionReply, welcomeText, WELCOME_TAIL,
} from './menu.ts';

export type Turn = { route: string | null; await: string | null; lang: Lang | null };
export type SendResult = { ok: boolean; err?: string };
export type Content = { sid: string; variables: Record<string, string> };
export type MenuDeps = {
  autoreplyEnabled(): Promise<boolean>;
  /** This number's wa_messages rows in the last 24 hours, newest first, excluding the current message. */
  recentTurns(from: string): Promise<Turn[]>;
  /** fn_wa_menu_context: audience by CONFIRMED number, name, approval, own open requests. */
  context(from: string): Promise<MenuContext>;
  /** fn_faq_answer: a confident answer from the approved FAQ, or null. */
  faq(text: string): Promise<string | null>;
  /** fn_wa_problem_report: opens a support case, returns its reference. */
  openCase(from: string, text: string, lang: Lang): Promise<string | null>;
  /** fn_notify_founder, kind whatsapp_human_request. */
  notifyHuman(from: string, ctx: MenuContext, text: string): Promise<boolean>;
  contentSid(key: string): Promise<string | null>;
  send(to: string, body: string, content?: Content): Promise<SendResult>;
  record(row: { inbound: string; reply: string; lang: Lang; sent: boolean; route: string; await: string | null;
                send_error: string | null; extra: Record<string, unknown> }): Promise<void>;
};
export type MenuInput = { from: string; body: string; listId?: string; buttonPayload?: string; audience: Audience };

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

async function sendMenu(d: MenuDeps, inp: MenuInput, lang: Lang, ctx: MenuContext, route: string, lead: string | null) {
  const key = contentKey(lang, ctx.audience);
  const sid = await d.contentSid(key);
  // Content body = {{1}} + WELCOME_TAIL, so the text we record is exactly what the list shows.
  const line = lead ?? greetLine(lang, ctx.audience, ctx.name, isSalam(inp.body));
  const shown = lead === null ? welcomeText(lang, ctx.audience, ctx.name, isSalam(inp.body)) : line + '\n\n' + WELCOME_TAIL[lang];
  await reply(d, inp, lang, route, shown, null, { audience: ctx.audience, content_key: key, content_sid: sid },
    sid ? { sid, variables: { '1': line } } : undefined, menuAsText(lang, ctx.audience, lead === null ? shown : line));
}

export async function menuTurn(d: MenuDeps, inp: MenuInput): Promise<{ handled: boolean; route?: string }> {
  const body = String(inp.body || '').trim();
  const recent = await d.recentTurns(inp.from);
  const last = recent[0] || null;
  const lastWasMenu = !!last?.route && /^menu_(welcome|reoffer)$/.test(last.route);
  const awaiting = last?.route?.startsWith('menu_') ? last.await : null;
  const choice = menuChoice({ body, listId: inp.listId, buttonPayload: inp.buttonPayload, numbers: lastWasMenu });
  // A bare number carries no language; the menu it answers does.
  const lang: Lang = langOf(body, last?.lang || 'en');

  // 1. The message after "Report a problem" is the problem.
  if (!choice && awaiting === 'problem' && body && !isGreeting(body) && !isMenuWord(body)) {
    const ref = await d.openCase(inp.from, body, lang);
    await reply(d, inp, lang, 'menu_case', caseConfirm(lang, ref), null, { case_ref: ref });
    return { handled: true, route: 'menu_case' };
  }

  // 2. An option.
  if (choice) {
    const ctx = await d.context(inp.from);
    const extra: Record<string, unknown> = { choice, audience: ctx.audience };
    if (choice === 'qd_person') extra.founder_notified = await d.notifyHuman(inp.from, ctx, body);
    if (choice === 'qd_follow') extra.requests_listed = (ctx.requests || []).length;
    const next = choice === 'qd_problem' ? 'problem' : choice === 'qd_general' ? 'question' : null;
    await reply(d, inp, lang, 'menu_' + choice, optionReply(choice, lang, ctx), next, extra);
    return { handled: true, route: 'menu_' + choice };
  }

  // 3. A greeting, the word MENU, or the first message of a conversation. The founder's number is his
  //    command channel, so for him only a greeting or MENU opens the menu, never "first message".
  const first = recent.length === 0;
  if (isGreeting(body) || isMenuWord(body) || (first && inp.audience !== 'founder')) {
    const ctx = await d.context(inp.from);
    // A first message with a real question in it gets the answer before the menu, if the FAQ has one.
    if (first && body && !isGreeting(body) && !isMenuWord(body)) {
      const ans = await d.faq(body);
      if (ans) await reply(d, inp, lang, 'menu_first_answer', ans, null, { audience: ctx.audience, faq: true });
    }
    await sendMenu(d, inp, lang, ctx, 'menu_welcome', null);
    return { handled: true, route: 'menu_welcome' };
  }

  // 4. After "General question": a confident FAQ answer; otherwise the normal route answers it.
  if (awaiting === 'question' && body) {
    const ans = await d.faq(body);
    if (ans) {
      await reply(d, inp, lang, 'menu_answer', ans + MENU_HINT[lang], null, { faq: true });
      return { handled: true, route: 'menu_answer' };
    }
  }
  return { handled: false };
}

/** Free text that is not a menu choice: a confident answer from the approved FAQ (the same corpus and
 *  routine the site assistant uses), sent with the MENU hint. False when the FAQ has no confident answer. */
export async function answerFromFaq(d: MenuDeps, inp: MenuInput): Promise<boolean> {
  const body = String(inp.body || '').trim();
  if (!body) return false;
  const ans = await d.faq(body);
  if (!ans) return false;
  const lang = langOf(body);
  await reply(d, inp, lang, 'faq_answer', ans + MENU_HINT[lang], null, { faq: true, audience: inp.audience });
  return true;
}

/** The last word when nothing else could answer: the menu again, in their language. */
export async function reofferMenu(d: MenuDeps, inp: MenuInput, lead: string): Promise<void> {
  await sendMenu(d, inp, langOf(inp.body), { audience: inp.audience, name: null }, 'menu_reoffer', lead);
}
