// classification.ts - THE WELCOME AND THE MENU, and the classifications that start with it: what the message asks, whether it needs
// a person, what it means to the menu (one model call, memoised), the database wiring menuTurn reads, and the menu answer itself.
// Moved out of index.ts's handleInbound (9 Nov 2026, customer_support); history and sayOutage are read from the turn.
import { needsAPerson } from '../_shared/reasoned_decisions.ts';
import { queueWhatsAppMeaning, whatsappReadings, type WaMeaningInput } from '../_shared/reasoned_channels.ts';
import { menuMeaning } from '../_shared/reasoned_menus.ts';
import { defaultDeps, type Phase } from '../_shared/think.ts';
import { type Content, type MenuDeps, menuTurn, type Turn } from './menu_flow.ts';
import type { Figures } from './founder_queries.ts';
import { type Audience, humanAlert, type Lang, MENU_IDS, menuItems } from './menu.ts';
import type { Trade } from './coverage.ts';
import { embedQuestion, FAQ_MIN_SIMILARITY } from './faq.ts';
import { admin, itFinding, sec, TW } from './shared.ts';
import { bidiSafe, sendWa, toContact } from './replies.ts';
import type { WaTurn } from './turn.ts';

/** The wall clock one classification call may take before it counts as unreasoned (see classifyDeps). */
const CLASSIFY_MS = 20_000;

export async function startClassification(t: WaTurn): Promise<void> {
  const { From, Body, Profile, MessageSid, ListId, ButtonPayload, media, audience, known, receivedAt, waInsert, sayFor, heldTurn } = t;
  // ---- THE WELCOME AND THE MENU (22 Sep 2026, founder_instruction 759) ---------------------------
  // "said hi, got no response. Even without the LLM there should be automatic replies: a professional
  // welcome message and options." menu_flow.ts decides; this block only wires it to the database and
  // Twilio. It runs after the no-exact-spec answer (a "2" there is an answer to that offer) and before
  // the founder's command channel, and it never takes a document (the media branch below owns those).
  // read beside the classification, not before it (one database trip off the reply's path, 10 Nov 2026): only record() needs it
  const waFromP = sec('twilio_wa_from').then((v) => 'whatsapp:' + v);
  waFromP.catch(() => null);   // a failed read surfaces where it is awaited (record's own try), never as an unhandled rejection
  // WHAT THE MESSAGE ASKS, reasoned ONCE (23 Sep 2026, founder_instruction 886-903): which intent row, our
  // size, the trade list or one trade (_shared/reasoned_channels.ts). It replaces fn_wa_answer's
  // match_patterns, coverage.ts's regexes and isSizeQuestion's. Held (the model hold) it is null: nothing is
  // guessed, and only if nothing else answers the message is it filed for replay (menu_flow.ts unanswered).
  // The reason it was not answered (the hold, a failed reasoning, or a throw) rides with it, so the queue files
  // the question WITHOUT reasoning again: one think() per message, never a second model call.
  // A CLASSIFICATION HAS 20 S (CLASSIFY_MS), NOT THE REPLY'S 45 (customer_support, 19 Oct 2026). Measured on production
  // (run 53bbd42e): a Luna Pro classification is 9-16 s, and one call in ten ran 41-47 s, which left the reply no time
  // and sent the held notice. A classification that runs out is unreasoned (null), exactly like the hold: nothing is
  // guessed, the reply is still written from the facts, and needs-a-person goes to the CEO seat for visibility.
  const classifyDeps = () => { const d = defaultDeps(admin, 'wa_inbound');
    return { ...d, llm: (p: Phase, s: string, i: string, o: Parameters<typeof d.llm>[3]) => d.llm(p, s, i, { ...o, timeoutMs: Math.min(o.timeoutMs ?? CLASSIFY_MS, CLASSIFY_MS) }) }; };
  let meaningP: Promise<string | null> | null = null; let meaningWhy = 'not_asked';
  // The intent table, the trade list and the history are read TOGETHER (10 Nov 2026): they were three database trips in series
  // before the classification call could start, ~0.25 s each from a worker outside ap-southeast-1 (_shared/db_region.ts).
  const meaningIn = async (): Promise<WaMeaningInput> => {
    const [{ data: rows }, trades, conversation] = await Promise.all([
      admin.from('wa_reply_intent').select('intent_key,label').eq('active', true).order('sort').order('intent_key'),
      menuDeps.trades(), t.history ?? Promise.resolve([])]);
    return { message: Body, intents: (rows || []) as WaMeaningInput['intents'], trades, phone: From,
             messageSid: MessageSid || null, audience: (['customer', 'supplier', 'founder'].includes(audience) ? audience : 'unknown') as WaMeaningInput['audience'],
             conversation };
  };
  // Both languages' titles, so a typed Arabic title is recognised as surely as an English one.
  // Paired by option id, never by position, so the two languages cannot drift onto each other's option.
  const menuOffer = () => menuItems('en', audience === 'supplier' ? 'supplier' : 'unknown').map((i) => {
    const ar = menuItems('ar', audience === 'supplier' ? 'supplier' : 'unknown').find((x) => x.id === i.id);
    return { id: i.id, title: i.item + (ar ? ' / ' + ar.item : ''), description: i.description + (ar ? ' / ' + ar.description : '') };
  });
  // THE THREE READINGS OF A TYPED MESSAGE ARE ONE MODEL CALL (whatsappReadings, customer_support 19 Oct 2026): what it
  // asks, whether it needs a person, what it means to the menu. Memoised; each consumer below reads its own part.
  type Readings = { intent: string | null; needsPerson: boolean | null; menu: string | null; why: string };
  let readingsP: Promise<Readings> | null = null;
  const readings = () => (readingsP ??= (async (): Promise<Readings> => {
    const r = await whatsappReadings(classifyDeps(), { ...(await meaningIn()), menu: menuOffer() });
    return { intent: r.intent, needsPerson: r.needsPerson, menu: r.menu, why: r.result.reason ?? r.result.status };
  })().catch((e) => ({ intent: null, needsPerson: null, menu: null, why: 'threw: ' + String((e as Error)?.message || e).slice(0, 200) })));
  const menuDeps: MenuDeps = {
    intent: (_text: string) => (meaningP ??= Body.trim() ? readings().then((r) => { meaningWhy = r.why; return r.intent; }) : Promise.resolve(null)),
    queueIntent: async (_text: string) => {
      try { await queueWhatsAppMeaning(defaultDeps(admin, 'wa_inbound'), await meaningIn(), meaningWhy); }
      catch (e) { await itFinding('wa_inbound:meaning_not_queued', 'A held WhatsApp question could not be filed for replay', { error: String((e as Error)?.message || e) }); }
    },
    meaning: async (text: string, awaitingProblem: boolean, offerMenu: boolean) => {
      // This message: its menu reading came with the others. The menu items and the problem option count only when
      // the turn offers them; otherwise the message is 'other', exactly as if they had not been offered.
      if (text.trim() && text.trim() === Body.trim()) {
        const m = (await readings()).menu;
        if (m === 'problem' && !awaitingProblem) return 'other';
        if (m && (MENU_IDS as readonly string[]).includes(m) && !offerMenu) return 'other';
        return m as Awaited<ReturnType<MenuDeps['meaning']>>;
      }
      return (await menuMeaning(classifyDeps(), { text, awaitingProblem, messageSid: MessageSid || undefined,
        // Both languages' titles, so a typed Arabic title is recognised as surely as an English one.
        // Paired by option id, never by position, so the two languages cannot drift onto each other's option.
        menu: offerMenu ? menuItems('en', audience === 'supplier' ? 'supplier' : 'unknown').map((i) => {
          const ar = menuItems('ar', audience === 'supplier' ? 'supplier' : 'unknown').find((x) => x.id === i.id);
          return { id: i.id, title: i.item + (ar ? ' / ' + ar.item : ''), description: i.description + (ar ? ' / ' + ar.description : '') };
        }) : undefined })).value;
    },
    autoreplyEnabled: async () => (await sec('wa_autoreply_enabled')) === 'true',
    recentTurns: async (from: string): Promise<Turn[]> => {
      const { data } = await admin.from('wa_messages').select('meta,lang,created_at').eq('wa_from', from)
        .gte('created_at', new Date(Date.now() - 86400e3).toISOString()).order('created_at', { ascending: false }).limit(5);
      // A message we refused at the door (bad signature, unverified) was never a conversation we were in.
      return ((data || []) as Array<{ meta: Record<string, unknown> | null; lang: string | null }>)
        // ...nor is an arrival row ('received': this very message or a crashed turn; 'handled': a branch that kept no row,
        // which before 19 Oct 2026 left no row at all): neither carries a route.
        .filter((r) => !r.meta?.no_autoreply_reason && r.meta?.stage !== 'received' && r.meta?.stage !== 'handled')
        .map((r) => ({ route: (r.meta?.route as string) || null, await: (r.meta?.menu_await as string) || null,
                       lang: r.lang === 'ar' ? 'ar' : r.lang === 'en' ? 'en' : null }));
    },
    context: async (from: string) => {
      const { data, error } = await admin.rpc('fn_wa_menu_context', { p_phone: from });
      if (error || !data) return { audience: audience as Audience, name: (known?.name as string) || null };
      return data as { audience: Audience; name: string | null };
    },
    faq: async (text: string) => {
      const q = text.slice(0, 1000);
      const { data, error } = await admin.rpc('fn_faq_answer', {
        p_text: q, p_min_rank: 0.15, p_embedding: await embedQuestion(q), p_min_similarity: FAQ_MIN_SIMILARITY,
      });
      if (error) await itFinding('wa_inbound:faq_answer_failed', 'WhatsApp could not read the approved FAQ', { error: error.message });
      return (data as { answered?: boolean; answer?: string } | null)?.answered ? String((data as { answer: string }).answer) : null;
    },
    trades: async (): Promise<Trade[]> => {
      // Each trade with its live group (taxonomy_trade_group, twelve groups since #881).
      const grouped = await admin.from('taxonomy_trade').select('code,label,label_ar,aliases,group:taxonomy_trade_group(code,label_en,label_ar,sort)')
        .eq('active', true).order('sort').order('code');
      if (!grouped.error) return (grouped.data || []) as unknown as Trade[];
      // Before the groups exist (#881 unapplied) the list still answers, ungrouped, rather than vanishing.
      const { data, error } = await admin.from('taxonomy_trade').select('code,label,label_ar,aliases').eq('active', true).order('sort').order('code');
      if (error) await itFinding('wa_inbound:trade_list_failed', 'WhatsApp could not read the live trade list', { error: error.message });
      return (data || []) as Trade[];
    },
    founderFigures: async (from: string): Promise<Figures> => {
      const { data, error } = await admin.rpc('fn_founder_whatsapp_figures', { p_phone: from });
      if (error) await itFinding('wa_inbound:founder_figures_failed', "WhatsApp could not read the founder's figures", { error: error.message });
      return (error || !data ? { ok: false } : data) as Figures;
    },
    recordGap: async (text: string, reason: string) => {
      const { data, error } = await admin.rpc('fn_support_knowledge_gap', { p_question: text.slice(0, 2000), p_refusal: reason, p_surface: 'whatsapp' });
      if (error) await itFinding('wa_inbound:knowledge_gap_failed', 'WhatsApp could not file an unanswered question', { error: error.message });
      return !error && (data as { ok?: boolean } | null)?.ok === true;
    },
    openCase: async (from: string, text: string, lang: Lang) => {
      const { data, error } = await admin.rpc('fn_wa_problem_report', { p_phone: from, p_text: text.slice(0, 4000), p_lang: lang });
      const r = (error ? null : data) as { case_ref?: string; appended?: boolean; sla_hours?: number } | null;
      return { ref: r?.case_ref || null, appended: r?.appended === true, slaHours: r?.sla_hours ?? null };
    },
    // The alert is actionable (instruction 763): who, which side, their last messages, a one-tap
    // wa.me reply and the DONE command. fn_wa_human_request records the handoff and the hold.
    notifyHuman: async (from: string, ctx, _text: string) => {
      const { data: last } = await admin.from('wa_messages').select('inbound').eq('wa_from', from)
        .not('inbound', 'is', null).order('created_at', { ascending: false }).limit(6);
      const said = ((last || []) as Array<{ inbound: string | null }>).map((r) => String(r.inbound || ''))
        .filter((m) => m && !/^qd_[a-z]+$/.test(m)).slice(0, 3);
      const a = humanAlert({ phone: from, name: ctx.name, profile: Profile || null, audience: ctx.audience, lastMessages: said });
      const { data, error } = await admin.rpc('fn_wa_human_request', {
        p_phone: from, p_hold: ctx.audience !== 'founder', p_event: a.event, p_detail: a.detail,
      });
      return !error && (data as { notified?: boolean } | null)?.notified === true;
    },
    humanHold: async (from: string) => {
      const { data, error } = await admin.rpc('fn_wa_human_hold', { p_phone: from });
      return !error && data === true;
    },
    closeCase: async (ref: string, reason: string) => {
      const { data, error } = await admin.rpc('fn_support_case_close', { p_ref: ref, p_reason: reason, p_by: 'founder (WhatsApp)' });
      const r = (error ? null : data) as { ok?: boolean; phone_digits?: string | null; lang?: string; close_reason?: string } | null;
      return { ok: r?.ok === true, phone: r?.phone_digits || null, lang: r?.lang === 'ar' ? 'ar' : 'en', reason: r?.close_reason || reason };
    },
    closeHuman: async (phone: string) => {
      const { data, error } = await admin.rpc('fn_wa_human_request_close', { p_phone: phone, p_by: 'founder (WhatsApp)', p_note: 'closed by the DONE command' });
      return error ? 0 : Number((data as { closed?: number } | null)?.closed || 0);
    },
    // Anything the company sent this number on WhatsApp in 24 hours (price requests, notices): a reply
    // to it is in-flow, not a first contact. Matched on the last nine digits, as fn_whatsapp_owner does.
    weWroteRecently: async (from: string) => {
      const tail = from.replace(/[^0-9]/g, '').slice(-9);
      if (tail.length < 9) return false;
      const { count } = await admin.from('notifications').select('id', { count: 'exact', head: true })
        .eq('channel', 'whatsapp').like('to_phone', '%' + tail)
        .gte('created_at', new Date(Date.now() - 86400e3).toISOString());
      return (count || 0) > 0;
    },
    contentSid: async (key: string) => {
      try { const m = JSON.parse((await sec('wa_menu_content_sids')) || '{}'); return typeof m[key] === 'string' && /^HX[0-9a-f]{32}$/i.test(m[key]) ? m[key] : null; }
      catch (_e) { return null; }
    },
    // A customer or supplier reply passes support_reply_guard.ts (FAQ rows can carry the licence number);
    // the founder's own command channel is not a customer surface and is left as it is.
    write: (r) => sayFor(r.audience === 'unknown' ? 'visitor' : r.audience)(r.situation, r.lang, r.must),
    outage: () => t.sayOutage,
    held: (r) => heldTurn(r.audience === 'unknown' ? 'visitor' : r.audience, r.lang, r.situation, r.route),
    send: (to: string, text: string, content?: Content) => {
      const guarded = content ? text : (audience === 'founder' ? bidiSafe(text.slice(0, 1500)) : toContact(text.slice(0, 1500)));
      // the guard refused it ('' — never a substitute text): nothing goes out
      return guarded ? sendWa(to, guarded, null, content) : Promise.resolve({ ok: false, err: 'guard_refused' });
    },
    record: async (row) => {
      try {
        await waInsert(receivedAt, {
          wa_from: From, wa_to: await waFromP, profile_name: Profile, inbound: row.inbound, reply: row.reply, lang: row.lang,
          escalated: row.route === 'menu_qd_person', sent: row.sent,
          meta: { ...row.extra, route: row.route, menu_await: row.await, enabled: row.extra.autoreply_enabled,
                  send_error: row.send_error, provenance_verified: true, message_sid: MessageSid || null,
                  list_id: ListId || null, button_payload: ButtonPayload || null },
        });
      } catch (_e) { /* the reply already went out */ }
      try {
        await admin.rpc('fn_wa_record_turn', { p_phone: From, p_direction: 'in', p_body: row.inbound.slice(0, 4000), p_intent: row.route });
        await admin.rpc('fn_wa_record_turn', { p_phone: From, p_direction: 'out', p_body: row.reply.slice(0, 4000), p_intent: row.route, p_answered_by: row.extra.model_written ? 'model' : 'template' });
      } catch (_e) { /* memory is worth less than the reply */ }
    },
  };
  const menuIn = { from: From, body: Body, listId: ListId, buttonPayload: ButtonPayload,
                   audience: (['customer', 'supplier', 'founder'].includes(audience) ? audience : 'unknown') as Audience,
                   hasMedia: media.length > 0 };
  // Only a menu choice, the problem text after "Report a problem", or an explicit hello/MENU is taken
  // here. A substantive message goes to its own handler first; welcomeFirstContact runs after them.
  // THE CLASSIFICATIONS START TOGETHER, NOT ONE AFTER ANOTHER (customer_support, 19 Oct 2026). Measured on production
  // (ai_cost_log, 18 Oct, four ZZ DEMO turns): what-it-asks, menu meaning and needs-a-person ran in series, 54-108 s
  // before the reply call. They read only the message, so a typed question starts both here; each is memoised and
  // awaited where it was before. A menu tap, a button and a document never reach them, so nothing starts for those.
  const typedQuestion = !!Body.trim() && media.length === 0 && !ListId && !ButtonPayload;
  let needsP: Promise<boolean | null> | null = null;
  const needsPersonP = () => (needsP ??= readings().then((r) => r.needsPerson !== null ? r.needsPerson : needsAPerson(classifyDeps(), {
    seat: 'customer_support', surface: 'wa_inbound.needs_a_person', message: Body.slice(0, 4000),
    audience: audience === 'supplier' ? 'supplier' : 'customer',
    dedupeKey: 'wa:' + (MessageSid || From + ':' + Body.slice(0, 40)), subject: { phone: From, message_sid: MessageSid || null },
  }).then((x) => x.value, () => null /* unreasoned is not "no": the route records it as held */)));
  // Held or failed, the person check falls back to its own think(): under the hold that files it for replay (no model).
  if (typedQuestion) readings();
  Object.assign(t, { menuDeps, menuIn, typedQuestion, needsPersonP });
}

// A MENU ANSWER ENDS THE TURN (and stops the speculative draft, which would otherwise keep paying for a reply nobody sends).
export async function answerFromTheMenu(t: WaTurn): Promise<Response | undefined> {
  const { audience, menuDeps, menuIn, specAbort, logRun } = t;
  const m = await menuTurn(menuDeps, menuIn);
  if (m.handled) {
    specAbort.abort();
    await logRun('ok', { audience, route: m.route, cost_aed: 0 }, 'answered from the WhatsApp menu: ' + m.route);
    return TW(200);
  }
}
