import { arAttr } from '../trade_glossary_ar.ts';
import { FIT_METHOD_AR, FIT_METHOD_EN, METHOD_NOTE_AR, METHOD_NOTE_EN } from '../../quote_compare/deterministic.ts';
// The model path's method (review item 4): the adviser weighs value for money; the fit rule is enforced on its ranking.
const FIT_METHOD_MODEL_EN = 'Our adviser weighs what each price buys against your request; a quote that fails a requirement you stated is never placed above one that meets them all.';
const FIT_METHOD_MODEL_AR = 'يوازن مستشارنا بين ما يشتريه كل سعر وما طلبته؛ ولا يتقدّم عرض لا يستوفي متطلبًا ذكرته على عرض يستوفيها جميعًا.';
import { aedRange } from '../money.ts';
import { NOT_RESPONSIBLE, priceStated } from '../stated_price.ts';
import { type InquiryRow, type TechTerm, arrOf, clipCell, jobNoOf } from './rows.ts';
import { DOC_VERSION, type Lang, PREPARED_BY, docName, maskDeep } from './base.ts';
import { type ArTexts, type Cell, flagged, kit, legendBlock } from './kit.ts';
import { commercialRows, heldLabels, techOf } from './compare_rows.ts';
import { arCategory, arEmirate, arUnit, enCategory } from './arabic.ts';

export function compareDocument(args: { analysis: any; inquiry: InquiryRow; lang: Lang; maskNames?: string[]; portalUrl?: string; linkFor?: (quoteId: string) => string; date?: string; date_ar?: string; arTexts?: ArTexts }) {
  const { analysis: a, inquiry: inq, lang } = args;
  const k = kit(lang, args.maskNames || [], args.arTexts); const { T, ar } = k;
  const ref = 'QD-' + jobNoOf(inq) + '-CMP';
  const date = (ar ? args.date_ar : args.date) || k.today();
  const roster = arrOf(a.all_quotes);
  const held = heldLabels(a);
  // deno-lint-ignore no-explicit-any
  const qs = arrOf(a.quotes).filter((q: any) => !held.has(String(q.label)));
  const received = roster.length || Number(a.total_quotes) || Number(a.considered) || qs.length;
  const tech = techOf(a);
  // top3 names quotes by label only; the roster carries each label's quote_id.
  // deno-lint-ignore no-explicit-any
  const idOf = new Map<string, string>(roster.filter((r: any) => r && r.label && r.quote_id).map((r: any) => [String(r.label), String(r.quote_id)]));
  const linked = (text: string, quoteId: unknown, extra: Record<string, unknown> = {}): Cell => (args.linkFor && quoteId ? { text, link: args.linkFor(String(quoteId)), ...extra } : (Object.keys(extra).length ? { text, ...extra } : text));
  const trade = ar ? (arCategory(inq?.category) ?? k.loc(inq?.category).text) : enCategory(inq?.category);
  const emirate = ar ? (arEmirate(inq?.emirate) ?? k.loc(inq?.emirate).text) : String(inq?.emirate || '');
  const summary = k.loc(inq?.summary, 600);
  // deno-lint-ignore no-explicit-any
  const prices = roster.filter((r: any) => r.status !== 'held' && Number(r.price) > 0).map((r: any) => Number(r.price));   // the roster's price is the fee base (comparedPrice)
  const top = arrOf(a.top3);
  // deno-lint-ignore no-explicit-any
  const blocks: any[] = [];
  let n = 0; const section = (en: string, arx: string) => blocks.push({ t: 'section', n: ++n, text: T(en, arx) });
  // The report states its method once, in its own section; the rules ranking's bottom line repeats it.
  const strip = (s: unknown) => String(s ?? '').replace(METHOD_NOTE_EN, '').replace(METHOD_NOTE_AR, '').replace(/\s+/g, ' ').trim();
  // WHAT HE ASKED FOR, QUOTE BY QUOTE (quote_compare request_fit, 15 Nov 2026): the requirements the intake recorded and each
  // quote's meets / differs / not stated, measured on its raw lines. Absent on a request with nothing recorded.
  const fit = a.request_fit && Array.isArray(a.request_fit.requirements) && a.request_fit.requirements.length ? a.request_fit : null;
  // deno-lint-ignore no-explicit-any
  const fitOf = (l: unknown): any => (fit ? arrOf(fit.quotes).find((x: any) => String(x.label) === String(l)) : null);
  const bi = (b: unknown): string => { const o = b as { en?: string; ar?: string } | null; return o ? String((ar ? o.ar : o.en) ?? '') : ''; };
  const FIT_FLAG: Record<string, 'match' | 'differs' | 'missing'> = { meets: 'match', differs: 'differs', not_stated: 'missing' };

  // 1 — Executive summary
  section('Executive summary', 'الملخص التنفيذي');
  // The callout below carries the recommendation's own words; the bottom line is printed only when it says more.
  const why1 = String(top[0]?.why ?? '').trim().toLowerCase().slice(0, 48);
  if (strip(a.bottom_line) && !(why1 && strip(a.bottom_line).toLowerCase().includes(why1))) blocks.push({ t: 'p', text: k.sentence(strip(a.bottom_line)), size: 11 });
  if (a.overview) blocks.push({ t: 'p', text: k.sentence(String(a.overview)) });
  if (top.length) {
    const t1 = top[0]; const id1 = idOf.get(String(t1.label));
    blocks.push({ t: 'callout', tone: 'teal', title: T('Recommended: ', 'التوصية: ') + k.label(t1.label), text: k.sentence(String(t1.why || '')) + (t1.tradeoff ? ' ' + T('Catch: ', 'الاعتبار: ') + k.sentence(String(t1.tradeoff)) : ''), ...(id1 && args.linkFor ? { link: args.linkFor(id1) } : {}) });
  }
  if (a.shortlist_reason) blocks.push({ t: 'note', text: k.sentence(String(a.shortlist_reason)) });
  if (top.length) {
    blocks.push({ t: 'h3', text: T('Recommended', 'التوصية') });
    blocks.push({ t: 'table', head: ['#', T('Supplier', 'المورّد'), T('Why', 'السبب'), T('Catch', 'الاعتبار')],
      // deno-lint-ignore no-explicit-any
      rows: top.map((r: any, i: number) => [String(r.rank ?? i + 1), linked(clipCell(k.label(r.label), 24), idOf.get(String(r.label)), { bold: true }), k.sentence(clipCell(r.why, 220)), k.sentence(clipCell(r.tradeoff, 160)) || '—']),
      widths: [0.06, 0.17, 0.47, 0.30], align: ['c', 's', 's', 's'], zebra: true });
    // deno-lint-ignore no-explicit-any
    // With his requirements the date is a yes / no and delivery carries no score (delivery_score null).
    const scored = top.map((t: any) => arrOf(a.quotes).find((q: any) => q.label === t.label)).filter((q: any) => q && [q.price_score, q.quality_score, ...(fit && q.delivery_score == null ? [] : [q.delivery_score])].every((x: unknown) => Number(x) > 0));
    // deno-lint-ignore no-explicit-any
    const fitRows = fit ? top.filter((t: any) => fitOf(t.label)) : [];
    if (fit && fitRows.length) {
      // PROPORTIONAL SCORES AND THE DATE AS A YES / NO (15 Nov 2026, journey A: 5/3/1 for AED 12,279 / 15,750 / 18,855, and a
      // delivery score although every quote met his date). ON BOTH PATHS the date answer and the "meets your request" score are
      // read from request_fit, never from the model's integer scores (review item 4: the model path printed "Done by your date:
      // Not stated" for three quotes that all met it, and "9 of 13 (5.0 / 5)"). The price score and the overall are the rules
      // ranking's on the rules path; on the model path the price score is the adviser's value-for-money judgement and there is
      // no computed overall, and the note under the table says which.
      const rulesPath = a.engine === 'deterministic';
      const dateReq = arrOf(fit.requirements).find((r: { code: string }) => r.code === 'date');
      const head = ['#', T('Supplier', 'المورّد'), T('Price score', 'درجة السعر'), T('Meets your request', 'استيفاء طلبك'), dateReq ? T('Done by your date', 'الإنجاز بحلول موعدك') : T('Delivery', 'التسليم'), ...(rulesPath ? [T('Overall', 'الإجمالي')] : [])];
      blocks.push({ t: 'table', head,
        // deno-lint-ignore no-explicit-any
        rows: fitRows.map((t: any, i: number) => {
          const f = fitOf(t.label);
          // deno-lint-ignore no-explicit-any
          const q: any = arrOf(a.quotes).find((x: any) => x.label === t.label) ?? {};
          const fitScore = f.score != null ? Number(f.score) : null;
          const price = Number(q.price_score) > 0 ? Number(q.price_score) : null;
          const del = Number(q.delivery_score) > 0 ? Number(q.delivery_score) : null;
          const date: Cell = dateReq
            ? (f.meets_date === true ? { text: T('Yes', 'نعم'), flag: 'match' } : f.meets_date === false ? { text: T('No', 'لا'), flag: 'differs' } : { text: T('Not stated', 'غير مذكور'), flag: 'missing' })
            : (del != null ? `${rulesPath ? del.toFixed(1) : del} / 5` : '—');
          const overall = rulesPath && price != null && fitScore != null ? Math.round((dateReq || del == null ? price * 0.5 + Math.max(1, fitScore) * 0.5 : price * 0.4 + Math.max(1, fitScore) * 0.4 + del * 0.2) * 10) / 10 : null;
          return [String(i + 1), linked(k.label(t.label), idOf.get(String(t.label)), { bold: true }), price != null ? `${rulesPath ? price.toFixed(1) : price} / 5` : '—',
            { text: T(`${f.met} of ${f.total}${fitScore != null ? ` (${fitScore.toFixed(1)} / 5)` : ''}`, `${f.met} من ${f.total}${fitScore != null ? ` (${fitScore.toFixed(1)} / 5)` : ''}`), ...(arrOf(f.hard_fails).length ? { flag: 'differs' as const } : {}) },
            date, ...(rulesPath ? [{ text: overall != null ? `${overall.toFixed(1)} / 5` : '—', bold: true }] : [])];
        }), widths: rulesPath ? [0.06, 0.2, 0.16, 0.24, 0.18, 0.16] : [0.06, 0.24, 0.2, 0.28, 0.22], align: rulesPath ? ['c', 's', 'e', 's', 's', 'e'] : ['c', 's', 'e', 's', 's'], zebra: true });
      blocks.push({ t: 'note', text: rulesPath
        ? T('Price scores 5 × the lowest price ÷ this price, so the scores keep the real gaps between prices. "Meets your request" scores 5 × the share of your requirements the quote meets; one it does not state counts half. Overall weighs price and your requirements equally. A quote that fails a requirement you stated is placed after every quote that meets them all, and one that leaves a requirement unstated after every quote that states it meets them.',
          'درجة السعر = 5 × أدنى سعر ÷ هذا السعر، فتبقى الفروق الحقيقية بين الأسعار. ودرجة "استيفاء طلبك" = 5 × نسبة متطلباتك التي يستوفيها العرض، ويُحتسب ما لا يذكره بنصف درجة. والإجمالي يوازن بين السعر ومتطلباتك بالتساوي. ولا يتقدّم عرض لا يستوفي متطلبًا ذكرته على عرض يستوفيها جميعًا، ولا عرض يغفل ذكر متطلب على عرض يذكر أنه يستوفيها.')
        : T('The price score is our adviser\'s judgement of value for money against the other shortlisted quotes, from 1 to 5 (5 is best): what the price buys, not only the lowest number. "Meets your request" counts the requirements you stated that each quote meets, and scores 5 × that share; one it does not state counts half. A quote that fails a requirement you stated is placed after every quote that meets them all, and one that leaves a requirement unstated after every quote that states it meets them.',
          'درجة السعر تقدير مستشارنا للقيمة مقابل السعر مقارنةً ببقية العروض المختصرة، من 1 إلى 5 (5 الأفضل): ما يشتريه السعر لا أدنى رقم فحسب. و"استيفاء طلبك" يعدّ متطلباتك التي يستوفيها كل عرض، ودرجته = 5 × تلك النسبة، ويُحتسب ما لا يذكره بنصف درجة. ولا يتقدّم عرض لا يستوفي متطلبًا ذكرته على عرض يستوفيها جميعًا، ولا عرض يغفل ذكر متطلب على عرض يذكر أنه يستوفيها.') });
    } else if (scored.length) {
      blocks.push({ t: 'scores', head: [T('Price', 'السعر'), T('Completeness', 'الاكتمال'), T('Delivery', 'التسليم'), T('Overall', 'الإجمالي')],
        // deno-lint-ignore no-explicit-any
        rows: scored.map((q: any, i: number) => ({ label: k.label(q.label), rank: i + 1, scores: [Number(q.price_score), Number(q.quality_score), Number(q.delivery_score)], overall: Math.round((q.price_score * 0.4 + q.quality_score * 0.4 + q.delivery_score * 0.2) * 10) / 10 })),
        note: T('Scores run from 1 to 5. Price scores 5 × the lowest price ÷ this price; completeness from what the supplier stated; delivery 5 × the fastest ÷ this lead time. Overall weights price 40%, completeness 40% and delivery 20%.', 'الدرجات من 1 إلى 5. درجة السعر = 5 × أدنى سعر ÷ هذا السعر؛ والاكتمال مما ذكره المورّد؛ والتسليم = 5 × أقصر مدة ÷ هذه المدة. الإجمالي: السعر 40%، والاكتمال 40%، والتسليم 20%.') });
    }
  }

  // 2 — Method and what is assessed
  section('Method and scope of assessment', 'المنهجية ونطاق التقييم');
  blocks.push({ t: 'p', text: fit
    ? T(`${PREPARED_BY.en} from the ${received} quotes submitted on your request. Each quote is measured against the ${fit.requirements.length} requirements you stated. ${a.engine === 'deterministic' ? FIT_METHOD_EN : FIT_METHOD_MODEL_EN}`, `${PREPARED_BY.ar} استنادًا إلى العروض الـ${received} المقدّمة على طلبك. قيس كل عرض بالمتطلبات الـ${fit.requirements.length} التي ذكرتها. ${a.engine === 'deterministic' ? FIT_METHOD_AR : FIT_METHOD_MODEL_AR}`)
    : T(`${PREPARED_BY.en} from the ${received} quotes submitted on your request. Quotes are ranked on the figures each supplier stated: price, completeness, lead time, warranty and payment terms.`,
    `${PREPARED_BY.ar} استنادًا إلى العروض الـ${received} المقدّمة على طلبك. رُتّبت العروض وفق الأرقام التي ذكرها كل مورّد: السعر، واكتمال العرض، ومدة التنفيذ، والضمان، وشروط الدفع.`) });
  blocks.push({ t: 'p', text: tech
    ? T('Material specifications are compared line by line with your request, exactly as each supplier stated them: each value is marked as matching your request, differing from it, or not stated.', 'تُقارن مواصفات المواد بندًا بندًا مع طلبك، كما ذكرها كل مورّد تمامًا: كل قيمة معلّمة بأنها مطابقة لطلبك أو مختلفة عنه أو غير مذكورة.')
    : T('Specifications are not assessed; check them before you pay.', 'لم تُقيَّم المواصفات؛ يُرجى التحقق منها قبل الدفع.') });
  blocks.push({ t: 'kv', pairs: [
    [T('Assessed', 'ما تم تقييمه'), T(`${fit ? 'Each requirement you stated, ' : ''}Price, completeness, lead time, installation, warranty, payment terms${tech ? ', line-by-line material specification' : ''}`.replace('stated, Price', 'stated, price'), `${fit ? 'كل متطلب ذكرته، و' : ''}السعر، والاكتمال، ومدة التنفيذ، والتركيب، والضمان، وشروط الدفع${tech ? '، ومواصفات المواد بندًا بندًا' : ''}`)],
    [T('Not assessed', 'ما لم يتم تقييمه'), T('Workmanship, supplier capacity, site conditions, and anything a supplier did not state in writing', 'جودة التنفيذ، وقدرة المورّد، وظروف الموقع، وأي أمر لم يذكره المورّد كتابيًا')],
  ] });

  // 3 — Technical comparison
  const cols = tech ? tech.suppliers.filter((l) => !held.has(String(l))) : [];
  section('Technical comparison', 'المقارنة الفنية');
  if (fit) {
    // deno-lint-ignore no-explicit-any
    const fcols: string[] = qs.map((q: any) => String(q.label)).filter((l: string) => fitOf(l));
    if (fcols.length) {
      blocks.push({ t: 'h3', text: T('What you asked for, quote by quote', 'ما طلبته، عرضًا بعرض') });
      blocks.push({ t: 'p', text: T('Each requirement you stated, from your request as our sales engineer recorded it, against what each supplier wrote. A brand is checked against the brands you named before the supplier\'s identity is hidden, so only whether it is one of yours is shown, with its tier and origin only where they cannot name it.',
        'كل متطلب ذكرته، من طلبك كما سجّله مهندس المبيعات لدينا، مقابل ما كتبه كل مورّد. وتُقارن العلامة التجارية بالعلامات التي سمّيتها قبل إخفاء هوية المورّد، فلا يظهر إلا ما إذا كانت من علاماتك، مع فئتها ومنشئها حيث لا يدلّان عليها.'), muted: true });
      const fw = 0.62 / fcols.length;
      blocks.push({ t: 'table', head: [T('Requirement', 'المتطلب'), T('You asked for', 'طلبك'), ...fcols.map((l) => k.label(l))], widths: [0.2, 0.18, ...fcols.map(() => fw)], zebra: true, fs: fcols.length >= 4 ? 7.8 : 8.5,
        // deno-lint-ignore no-explicit-any
        rows: arrOf(fit.requirements).map((r: any) => [{ text: bi(r.label), bold: true }, bi(r.asked) || '—', ...fcols.map((l): Cell => { const c = fitOf(l)?.cells?.[r.code]; return c ? { text: bi(c.shown) || '—', flag: FIT_FLAG[c.status] ?? 'missing' } : { text: T('N/A', 'لا ينطبق'), flag: 'na' }; })]) });
      for (const l of fcols) {
        const f = fitOf(l); if (!f || !arrOf(f.hard_fails).length) continue;
        // deno-lint-ignore no-explicit-any
        blocks.push({ t: 'note', text: k.sentence(T(`${l} fails what you asked for: ${arrOf(f.hard_fails).map((x: any) => `${bi(x.noun)}, ${bi(x.detail)}`).join('; ')}.`, `${l} لا يستوفي ما طلبته: ${arrOf(f.hard_fails).map((x: any) => `${bi(x.noun)}، ${bi(x.detail)}`).join('؛ ')}.`)) });
      }
    }
  }
  if (tech && cols.length) {
    blocks.push(legendBlock(k));
    blocks.push({ t: 'h3', text: T('Completeness: the four checks, side by side', 'الاكتمال: البنود الأربعة جنبًا إلى جنب') });
    // A value counts as matching only against something the request asked for (15 Nov 2026, journey A: "All 30 match" where
    // the request stated none of the 30). Values with nothing to check against are reported as stated, with no mark.
    const matFor = (l: string): Cell => {
      const cells = tech.lines.flatMap((ln) => ln.attributes.map((at) => ({ asked: !!at.requested, flag: at.values?.[l]?.flag ?? 'missing' }))).filter((c) => c.flag !== 'na');
      const miss = cells.filter((c) => c.flag === 'missing').length;
      const checked = cells.filter((c) => c.asked && (c.flag === 'match' || c.flag === 'differs'));
      const dif = checked.filter((c) => c.flag === 'differs').length;
      if (!cells.length) return { text: T('N/A', 'لا ينطبق'), flag: 'na' };
      if (miss) return { text: T(`${miss} not stated`, `${miss} غير مذكورة`), flag: 'missing' };
      if (dif) return { text: T(`${dif} of the ${checked.length} you specified differ`, `${dif} من ${checked.length} حددتها مختلفة`), flag: 'differs' };
      if (checked.length) return { text: T(`All ${checked.length} you specified match`, `جميع ما حددته مطابق (${checked.length})`), flag: 'match' };
      return { text: T(`Stated on every line (${cells.length} values; your request named none to check)`, `مذكورة في كل بند (${cells.length} قيمة؛ لم يحدد طلبك قيمة للمقارنة)`) };
    };
    const termRow = (en: string, arx: string, t: TechTerm | null | undefined): Cell[] => [{ text: T(en, arx), bold: true }, ...cols.map((l): Cell => t?.applicable === false ? { text: T('N/A', 'لا ينطبق'), flag: 'na' } : flagged(k, t?.values?.[l]))];
    const cw = 0.72 / cols.length;
    blocks.push({ t: 'table', head: [T('Check', 'البند'), ...cols.map((l) => k.label(l))], widths: [0.28, ...cols.map(() => cw)], zebra: true, rows: [
      [{ text: T('Material specification, per line', 'مواصفات المواد لكل بند'), bold: true }, ...cols.map(matFor)],
      termRow('Delivery / lead time', 'التسليم / مدة التنفيذ', tech.terms?.lead_time),
      termRow('Installation', 'التركيب', tech.terms?.installation),
      termRow('Warranty — period and coverage', 'الضمان — المدة والتغطية', tech.terms?.warranty),
    ] });
    blocks.push({ t: 'h3', text: T('Line by line: stated specification against your request', 'بندًا بندًا: المواصفات المذكورة مقابل طلبك') });
    const rows: Cell[][] = [];
    tech.lines.forEach((ln, i) => {
      const qty = [ln.qty, ln.unit ? (ar ? (arUnit(ln.unit) ?? k.loc(ln.unit).text) : ln.unit) : ''].filter((x) => x != null && String(x) !== '').join(' ');
      rows.push([{ text: `${ln.line_no ?? i + 1}. ${k.loc(ln.item, 120).text}${qty ? ' — ' + qty : ''}`, group: true }]);
      for (const at of ln.attributes) {
        const name = ar ? (arAttr(at.key) ?? arAttr(at.label) ?? k.loc(at.label || at.key).text) : String(at.label || at.key).replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase());
        rows.push([{ text: name, bold: true }, at.requested ? k.cell(at.requested, 120) : '—', ...cols.map((l) => flagged(k, at.values?.[l]))]);
      }
    });
    if (rows.length) blocks.push({ t: 'table', head: [T('Specification', 'المواصفة'), T('You asked for', 'طلبك'), ...cols.map((l) => k.label(l))], widths: [0.16, 0.18, ...cols.map(() => (0.66 / cols.length))], rows, zebra: true, fs: cols.length >= 4 ? 7.8 : 8.5 });
    // Service, removal, piping and testing lines carry no product specification (no brand, capacity or refrigerant applies to
    // them): they are not listed here, and the scope they cover is compared under "What you asked for" above.
    const dropped = Number((tech as unknown as { scope_lines_dropped?: number }).scope_lines_dropped) || 0;
    if (dropped) blocks.push({ t: 'note', text: T(`${dropped} service, removal, piping or testing line${dropped === 1 ? '' : 's'} carry no product specification and ${dropped === 1 ? 'is' : 'are'} not listed here${fit ? '; the scope they cover is compared under "What you asked for" above' : ''}.`, `${dropped} من بنود الصيانة أو الإزالة أو الأنابيب أو الاختبار لا تحمل مواصفات منتج، فلا تُدرج هنا${fit ? '؛ ويُقارن النطاق الذي تغطيه تحت "ما طلبته" أعلاه' : ''}.`), muted: true });
  } else {
    blocks.push({ t: 'p', text: T('The suppliers\' line specifications for this request are not in a comparable form yet, so no line-by-line specification table is shown. The commercial comparison below still applies, and each quotation shows its specification exactly as the supplier stated it.', 'لم تصل مواصفات البنود من المورّدين لهذا الطلب بصيغة قابلة للمقارنة بعد، لذا لا يظهر جدول المواصفات بندًا بندًا. المقارنة التجارية أدناه سارية، وكل عرض يعرض مواصفاته كما ذكرها المورّد تمامًا.'), muted: true });
  }
  if (tech) for (const l of held) blocks.push({ t: 'note', text: T(`${l} is on hold and is not compared here: its quote does not yet state everything a complete quote must.`, `${k.label(l)} معلّق ولا يُقارن هنا: عرضه لا يذكر بعد كل ما يجب أن يتضمنه العرض المكتمل.`) });
  if (arrOf(a.line_findings).length) {
    blocks.push({ t: 'h3', text: T('Line findings', 'ملاحظات البنود') });
    // deno-lint-ignore no-explicit-any
    blocks.push({ t: 'table', head: [T('Item', 'البند'), T('Finding', 'الملاحظة')], rows: arrOf(a.line_findings).map((f: any) => [k.cell(k.sentence(clipCell(f.item, 60))), k.cell(k.sentence(clipCell(f.finding, 300)))]), widths: [0.28, 0.72], zebra: true });
  }

  // 4 — Commercial comparison
  const side = commercialRows(a, lang, args.maskNames || [], args.arTexts, k.untranslated);
  if (side) {
    section('Commercial comparison', 'المقارنة التجارية');
    const colW = 0.76 / Math.max(1, side.labels.length);
    blocks.push({ t: 'table', head: side.head, rows: side.rows, widths: [0.24, ...side.labels.map(() => colW)], zebra: true });
    blocks.push({ t: 'note', text: T('Ranked on each supplier\'s final price after any discount it states, excluding VAT — the same figure our 3% fee is taken on; no card fee, no VAT on our fee.', 'رُتّبت العروض على السعر النهائي لكل مورّد بعد أي خصم يذكره وقبل الضريبة، وهو الرقم نفسه الذي تُحتسب عليه رسومنا البالغة 3%، بلا رسوم بطاقة ولا ضريبة قيمة مضافة على رسومنا.') });
    blocks.push({ t: 'callout', tone: 'gold', title: T('The suppliers\' quotations, as stated', 'عروض المورّدين كما ذكروها'), text: T(NOT_RESPONSIBLE.en, NOT_RESPONSIBLE.ar) });
  }

  // 5 — Every quote received
  if (roster.length) {
    section(`All quotes received (${roster.length})`, `جميع العروض المستلمة (${roster.length})`);
    blocks.push({ t: 'p', text: T(`All ${roster.length} quotes on your request are listed here, and each one stays open to you: you can view or reveal any of them from your portal.`, `جميع العروض الـ${roster.length} على طلبك مدرجة هنا، وكلها تبقى متاحة لك: يمكنك عرض أي منها أو كشفه من بوابتك.`), muted: true });
    // deno-lint-ignore no-explicit-any
    const chip = (r: any): Cell => r.status === 'shortlisted' ? { text: T(`Shortlisted #${r.rank}`, `ضمن القائمة المختصرة #${r.rank}`), chip: 'short' }
      : r.status === 'held' ? { text: T('On hold', 'معلّق'), chip: 'hold' } : { text: T('Open to reveal', 'متاح للكشف'), chip: 'open' };
    blocks.push({ t: 'table', head: [T('Supplier', 'المورّد'), T('Price', 'السعر'), T('Lead time', 'مدة التنفيذ'), T('Status', 'الحالة')],
      // A held quote is counted, never detailed: no price and no lead time on the page.
      // deno-lint-ignore no-explicit-any
      rows: roster.map((r: any) => r.status === 'held'
        ? [linked(k.label(r.label), r.quote_id, { bold: true }), '—', '—', chip(r)]
        : [linked(k.label(r.label) + (r.expired ? T(' (expired)', ' (منتهي الصلاحية)') : ''), r.quote_id, { bold: true }), priceStated({ ...r, quote_amount: r.price, price_ex_vat: r.price }, lang), k.dur(r.lead_time) || '—', chip(r)]),
      widths: [0.26, 0.22, 0.22, 0.30], align: ['s', 'e', 's', 's'], zebra: true });
    // deno-lint-ignore no-explicit-any
    for (const r of roster.filter((x: any) => x.status === 'held')) {
      const miss = typeof r.missing_mandatory === 'number' && r.missing_mandatory > 0 ? r.missing_mandatory : null;
      const why = r.price == null ? T('no price stated', 'لا يوجد سعر مذكور')
        : miss ? T(`${miss} mandatory detail(s) missing`, `${miss} من التفاصيل الإلزامية ناقصة`) : T('it does not pass our completeness check', 'لم يجتز فحص الاكتمال');
      blocks.push({ t: 'note', text: T(`${r.label} is on hold: ${why}. It is counted here but not ranked or detailed until the supplier completes it.`, `${k.label(r.label)} معلّق: ${why}. يُحتسب هنا لكنه لا يدخل الترتيب ولا تُعرض تفاصيله حتى يستكمله المورّد.`) });
    }
    blocks.push({ t: 'link', text: T('Every quote above stays open to you — the shortlist is advice, not a limit. You can choose any of them: open your QuotesDone portal to view or reveal it.',
      'كل العروض أعلاه تبقى متاحة لك، فالقائمة المختصرة نصيحة وليست قيدًا. يمكنك اختيار أي منها: افتح بوابتك في QuotesDone لعرضه أو كشفه.'), link: args.portalUrl });
  }

  // 6 — Risks and clarifications, per supplier
  const risk: Cell[][] = [];
  for (const q of qs) {
    const pts: string[] = [...arrOf(q.flags), ...arrOf(q.missing_from_request), ...arrOf(q.spec_deviation)].map(String);
    if (tech && cols.includes(String(q.label))) {
      tech.lines.forEach((ln, i) => ln.attributes.forEach((at) => {
        const c = at.values?.[String(q.label)]; if (!c || (c.flag !== 'differs' && c.flag !== 'missing')) return;
        const name = ar ? (arAttr(at.key) ?? k.loc(at.label || at.key).text) : String(at.label || at.key).replace(/_/g, ' ').toLowerCase();
        const item = k.loc(ln.item, 60).text; const no = ln.line_no ?? i + 1;
        // Only differs and missing reach this list; an optional detail not stated is shown in the table
        // as "Not stated (optional)" and is never chased. The missing branch is a SAFETY NET: the hold
        // gate keeps a quote with an unstated mandatory detail out of the comparison altogether.
        // Before the reveal the customer cannot reach a supplier; QuotesDone chases a missing detail
        // (founder, 14 Sep 2026). A mandatory detail left unstated holds the quote, and the hold desk
        // asks the supplier through customer_support (WhatsApp and email) until it is filled — so the
        // sentence says that, never "ask for it". A difference is stated as the supplier quoted it.
        pts.push(c.flag === 'missing'
          ? T(`Line ${no} (${item}): ${name} not stated — we have asked the supplier; this report updates when they answer.`, `البند ${no} (${item}): ${name} غير مذكورة — طلبناها من المورّد، وسيُحدَّث التقرير عند الرد.`)
          : T(`Line ${no} (${item}): ${name} is ${c.value ?? '—'}; you asked for ${at.requested ?? '—'}. This is what the supplier quoted in writing.`, `البند ${no} (${item}): ${name} ${k.loc(c.value ?? '—', 60).text} بينما طلبت ${k.loc(at.requested ?? '—', 60).text}. هذا ما قدّمه المورّد كتابيًا في عرضه.`));
      }));
    }
    const uniq = [...new Set(pts.map((p) => p.trim()).filter(Boolean))];
    uniq.forEach((p, i) => risk.push([i === 0 ? { text: k.label(q.label), bold: true } : '', k.cell(k.sentence(p), 240)]));
    if (!uniq.length) risk.push([{ text: k.label(q.label), bold: true }, T('Nothing flagged from what the supplier stated.', 'لا توجد ملاحظات مما ذكره المورّد.')]);
  }
  if (risk.length) {
    section('Risks and clarifications by supplier', 'المخاطر والاستيضاحات لكل مورّد');
    blocks.push({ t: 'table', head: [T('Supplier', 'المورّد'), T('What to know before you choose', 'ما يجب معرفته قبل الاختيار')], rows: risk, widths: [0.2, 0.8] });
  }

  // 7 — POINTS QUOTESDONE SETTLES WITH THE SUPPLIER FOR YOU (founder, 14 Sep 2026: before the reveal the customer never puts a
  // question to a supplier, and nothing tells him to; review item 6 of 15 Nov 2026). Each point is put to that supplier by our
  // sales engineer in the quotation conversation he already has with them (supplier_api quote_review_flow, quote_review_request),
  // with the customer's identity hidden; the answer joins this comparison. The customer is told what is open, never asked to act.
  if (fit) {
    const asks: Cell[][] = [];
    // deno-lint-ignore no-explicit-any
    for (const q of qs) { const f = fitOf(q.label); arrOf(f?.asks).forEach((x: any, i: number) => asks.push([i === 0 ? { text: k.label(q.label), bold: true } : '', bi(x)])); }
    if (asks.length) {
      section('Points QuotesDone settles with the supplier for you', 'نقاط تتولاها QuotesDone مع المورّد نيابةً عنك');
      blocks.push({ t: 'p', text: T('Each quotation leaves these points open. Our sales engineer puts each one to that supplier in writing, with your identity hidden, and the answer is added to this comparison. You do not need to contact anyone.',
        'يترك كل عرض هذه النقاط مفتوحة. يطرح مهندس المبيعات لدينا كل نقطة على المورّد المعني كتابةً، مع بقاء هويتك مخفية، وتُضاف الإجابة إلى هذه المقارنة. لا يلزمك التواصل مع أحد.'), muted: true });
      blocks.push({ t: 'table', head: [T('Supplier', 'المورّد'), T('Open point', 'النقطة المفتوحة')], rows: asks, widths: [0.2, 0.8] });
    }
  }

  // 8 — Advice and next steps
  if (a.best_value_reason || a.advice || arrOf(a.watch_outs).length) {
    section('Advice and next steps', 'النصيحة والخطوات التالية');
    // With his requirements the method is stated once, in section 2; the rules ranking's best_value_reason is that method.
    if (a.best_value_reason && !(fit && (a.best_value_reason === FIT_METHOD_EN || a.best_value_reason === FIT_METHOD_AR))) blocks.push({ t: 'p', text: k.sentence(String(a.best_value_reason)) });
    if (a.advice) blocks.push({ t: 'p', text: k.sentence(String(a.advice)) });
    for (const w of arrOf(a.watch_outs)) blocks.push({ t: 'li', text: k.sentence(String(w)) });
  }
  if (a.disclaimer) { blocks.push({ t: 'space', h: 4 }); blocks.push({ t: 'note', text: k.sentence(String(a.disclaimer)) }); }

  const lo = prices.length ? Math.min(...prices) : 0, hi = prices.length ? Math.max(...prices) : 0;
  const range = !prices.length ? '—' : lo === hi ? k.money(lo) : aedRange(lo, hi, lang);
  const cover0 = {
    kicker: T('Bid tabulation and technical comparison', 'جدول مقارنة العروض والمقارنة الفنية'), title: T('Quote comparison report', 'تقرير مقارنة العروض'),
    subtitle: clipCell(summary.text, 170),
    meta: [[T('Reference', 'الرقم المرجعي'), ref], [T('Date', 'التاريخ'), date], [T('Trade', 'التخصص'), trade || '—'], [T('Emirate', 'الإمارة'), emirate || '—']],
    figures: [[T('Quotes received', 'العروض المستلمة'), String(received)], [T('Compared in detail', 'قورنت بالتفصيل'), T(`${qs.length} of ${received}`, `${qs.length} من ${received}`)],
      [T('Price range', 'نطاق الأسعار'), range], [T('Recommended', 'الموصى به'), top.length ? k.label(top[0].label) : '—']],
  };
  const control = `${ref} · ${DOC_VERSION} · ${T('Generated', 'أُنشئ في')} ${date} · ${ar ? PREPARED_BY.ar : PREPARED_BY.en}`;
  const names = args.maskNames || [];
  const body: Record<string, unknown> = {
    title: T('Quote comparison report', 'تقرير مقارنة العروض'), ref, name: docName(ref, 'comparison', lang), lang,
    cover: maskDeep(cover0, names, lang), control, blocks: maskDeep(blocks, names, lang), options: { letterhead: true },
  };
  if (args.date) body.date = args.date; if (args.date_ar) body.date_ar = args.date_ar;
  return { body, ref, untranslated: [...k.untranslated] };
}
