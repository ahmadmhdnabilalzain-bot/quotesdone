import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import { setRequestLocale } from 'next-intl/server';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { HeroScene } from '@/components/visual/slots';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Progress } from '@/components/ui/progress';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle, SheetTrigger } from '@/components/ui/sheet';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import {
  Seal, Kicker, SectionHead, Bento, BentoTile, ProductFrame, ComparisonShowcase, BoqShowcase, MatchShowcase,
  StatBlock, Stepper, FactBand, ProofBand,
} from '@/components/ui/sealed';
import { PAIRS, SWATCHES, contrast } from '@/lib/brandTokens';

// The living style guide for brand direction A "Sealed". It renders every token, both type scales,
// every primitive in its states and every recipe, straight from the production components, so it
// is the page the system is verified against. Not for search engines, not in the sitemap.
export function generateStaticParams() {
  return [{ locale: 'en' }, { locale: 'ar' }];
}
export const metadata: Metadata = {
  title: 'QuotesDone · Sealed brand system',
  robots: { index: false, follow: false, nocache: true },
};

const L = {
  en: { cover: 'Brand system · Direction A', idea: 'Every quote arrives sealed. Only the one you choose is ever opened.', sample: 'Sample data', note: 'Figures on this page are sample data for the design system, not measurements.' },
  ar: { cover: 'نظام الهوية · الاتجاه أ', idea: 'كل عرض يصل مختومًا. ولا يُفتح إلا العرض الذي تختاره.', sample: 'بيانات نموذجية', note: 'الأرقام في هذه الصفحة بيانات نموذجية لنظام التصميم، وليست قياسات.' },
};

function Section({ n, title, kicker, children, id }: { n: string; title: string; kicker: string; children: ReactNode; id: string }) {
  return (
    <section id={id} className="border-t border-line py-beat-s md:py-beat">
      <div className="container-x">
        <div className="grid gap-10 lg:grid-cols-[240px_1fr]">
          <div className="lg:sticky lg:top-28 lg:self-start">
            <div className="font-mono text-label text-teal-light">{n}</div>
            <h2 className="mt-3 font-head text-display-sm text-white">{title}</h2>
            <div className="mt-3 font-mono text-label uppercase tracking-caps text-faint">{kicker}</div>
          </div>
          <div className="min-w-0">{children}</div>
        </div>
      </div>
    </section>
  );
}
const Spec = ({ k, v }: { k: string; v: string }) => (
  <span className="font-mono text-label text-faint"><span className="text-muted">{k}</span> {v}</span>
);

const EN_SCALE: [string, string, string][] = [
  ['Display XL', 'text-display-xl', 'clamp(48–120) / .92 / 600 / −4.5%'],
  ['Display', 'text-display', 'clamp(44–92) / .95 / 600 / −4.5%'],
  ['Display S', 'text-display-sm', 'clamp(30–56) / 1.02 / 600 / −3%'],
  ['H2', 'text-h2', 'clamp(28–48) / 1.05 / 600 / −3%'],
  ['H3', 'text-h3', 'clamp(20–24) / 1.25 / 600 / −1.5%'],
  ['Lead', 'text-lead', 'clamp(17–20) / 1.55 / 400'],
  ['Copy', 'text-copy', '15 / 1.65 / 400'],
  ['Label', 'text-label', '12 / 1.4 / mono caps +14%'],
];
// Literal class names: Tailwind only generates classes it can read whole in the source.
const TRACK: [string, string][] = [['display', 'tracking-display'], ['tight', 'tracking-tight'], ['snug', 'tracking-snug'], ['normal', 'tracking-normal'], ['wide', 'tracking-wide'], ['caps', 'tracking-caps']];
const ELEV: [string, string][] = [['e1', 'shadow-e1'], ['e2', 'shadow-e2'], ['e3', 'shadow-e3']];
const RADII: [string, string, string][] = [['chip', '6', 'rounded-chip'], ['btn', '10', 'rounded-btn'], ['panel', '12', 'rounded-panel'], ['card', '16', 'rounded-card'], ['frame', '18', 'rounded-frame'], ['pill', '∞', 'rounded-pill']];
const AR_SCALE: [string, string, string][] = [
  ['عرض كبير', 'text-display-xl', 'clamp(40–96) / 1.22 / 700 / 0'],
  ['عرض', 'text-display', 'clamp(36–74) / 1.25 / 700 / 0'],
  ['عنوان 2', 'text-h2', 'clamp(26–42) / 1.35 / 700 / 0'],
  ['عنوان 3', 'text-h3', '21 / 1.5 / 600'],
  ['مقدمة', 'text-lead', '18 / 1.8 / 400'],
  ['نص', 'text-copy', '15 / 1.85 / 400'],
];

export default async function BrandPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const lang = locale === 'ar' ? 'ar' : 'en';
  const t = L[lang];

  return (
    <>
      <SiteHeader />
      <main id="main">
        {/* ── COVER ─────────────────────────────────────────────────────── */}
        <section className="qd-keylight relative overflow-hidden">
          <div className="grid-tech" aria-hidden />
          <div className="container-x relative grid min-h-[86vh] items-center gap-12 py-24 lg:grid-cols-[1.1fr_1fr]">
            <div>
              <Kicker>QuotesDone · {t.cover}</Kicker>
              <h1 className="mt-8 font-head text-display-xl text-white">
                {/* bdi: the Latin brand word keeps its own order inside the Arabic page (it read ".Sealed") */}
                <Seal loop><bdi>Sealed.</bdi></Seal>
              </h1>
              <p className="mt-8 max-w-[34ch] text-lead text-muted">{t.idea}</p>
              <div className="mt-10 flex flex-wrap gap-3">
                <Button size="lg" className="qd-magnet">Get quotes</Button>
                <Button size="lg" variant="reveal">Reveal · 3%</Button>
                <Button size="lg" variant="secondary">How it works</Button>
              </div>
            </div>
            <div className="relative aspect-5/4 w-full">
              <HeroScene locale={lang} />
            </div>
          </div>
        </section>

        {/* ── 01 COLOUR ─────────────────────────────────────────────────── */}
        <Section id="colour" n="01" title="Colour" kicker="Navy ground · one teal light · gold for the reveal">
          <div className="flex flex-col gap-10">
            {SWATCHES.map((g) => (
              <div key={g.group}>
                <div className="font-mono text-label uppercase tracking-caps text-faint">{g.group}</div>
                <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-5">
                  {g.items.map((s) => {
                    const onNavy = contrast(s.hex, '#0A1720');
                    return (
                      <div key={s.token} className="qd-panel overflow-hidden">
                        <div className="h-24 border-b border-line" style={{ background: s.hex }} />
                        <div className="flex flex-col gap-1 p-4">
                          <span className="text-small font-medium text-white">{s.name}</span>
                          <span className="font-mono text-label text-muted" dir="ltr">{s.hex} · {s.token}</span>
                          <span className="text-label text-faint">{s.role}</span>
                          <span className="font-mono text-label text-faint" dir="ltr">{onNavy.toFixed(2)}:1 on navy</span>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            ))}
            <div className="qd-panel p-6">
              <div className="font-mono text-label uppercase tracking-caps text-faint">Status (text on its 12% tint)</div>
              <div className="mt-4 flex flex-wrap gap-2">
                <Badge variant="ok" dot>Verified</Badge><Badge variant="warn" dot>Missing item</Badge><Badge variant="info" dot>In review</Badge>
                <Badge variant="danger" dot>Expired licence</Badge><Badge variant="sealed">Supplier ▮▮▮▮</Badge><Badge variant="revealed">Revealed</Badge><Badge>Default</Badge><Badge variant="outline">Outline</Badge>
              </div>
            </div>
          </div>
        </Section>

        {/* ── 02 TYPE ───────────────────────────────────────────────────── */}
        <Section id="type" n="02" title="Type" kicker="Geist · Readex Pro · Geist Mono — SIL OFL">
          <div className="grid gap-6">
            <div lang="en" dir="ltr" className="qd-panel p-6 md:p-8">
              <div className="flex items-center justify-between"><Kicker>Latin · Geist</Kicker><Spec k="weights" v="100–900 variable" /></div>
              <div className="mt-8 flex flex-col divide-y divide-(--line)">
                {EN_SCALE.map(([name, cls, spec]) => (
                  <div key={name} className="grid gap-2 py-5 md:grid-cols-[140px_1fr] md:items-baseline">
                    <div className="flex flex-col"><span className="text-small text-white">{name}</span><Spec k="" v={spec} /></div>
                    <div className={`${cls} ${cls === 'text-label' ? 'font-mono uppercase tracking-caps text-teal-light' : 'font-head text-white'} min-w-0 text-balance`}>
                      {cls === 'text-label' ? 'Quote Q-0412 · Levelled' : cls.startsWith('text-display') || cls === 'text-h2' ? 'Only the best one opened.' : 'Describe the job once. Licence-verified suppliers quote blind.'}
                    </div>
                  </div>
                ))}
              </div>
            </div>
            <div lang="ar" dir="rtl" className="qd-panel p-6 md:p-8">
              <div className="flex items-center justify-between"><Kicker>العربية · Readex Pro</Kicker><Spec k="" v="160–700" /></div>
              <div className="mt-8 flex flex-col divide-y divide-(--line)">
                {AR_SCALE.map(([name, cls, spec]) => (
                  <div key={name} className="grid gap-2 py-5 md:grid-cols-[140px_1fr] md:items-baseline">
                    <div className="flex flex-col"><span className="text-small text-white">{name}</span><span dir="ltr" className="text-end"><Spec k="" v={spec} /></span></div>
                    <div className={`${cls} min-w-0 text-balance font-head text-white`}>
                      {cls.startsWith('text-display') || cls === 'text-h2' ? 'كل عرض مختوم.' : 'صِف عملك مرة واحدة، ويقدّم الموردون المرخّصون عروضهم دون أن يعرفوا هويتك.'}
                    </div>
                  </div>
                ))}
              </div>
            </div>
            <div className="grid gap-4 md:grid-cols-3">
              <div className="qd-panel p-6">
                <Kicker>Figures · Geist Mono</Kicker>
                <div className="qd-figure mt-6 font-mono text-[44px]" dir="ltr">AED 38,750</div>
                <div className="mt-2 font-mono text-label text-faint" dir="ltr">tabular · 0123456789</div>
              </div>
              <div className="qd-panel p-6">
                <Kicker>Tracking scale</Kicker>
                <div className="mt-5 flex flex-col gap-2 text-copy text-white">
                  {TRACK.map(([k, cls]) => <span key={k} className={cls}>tracking-{k} · Sealed</span>)}
                </div>
              </div>
              <div className="qd-panel p-6">
                <Kicker>Floor</Kicker>
                <p className="mt-5 text-copy text-muted">No text below 12px. In Arabic every tracking token is 0 (letter-spacing breaks the joins) and uppercase does nothing, so labels carry weight and a teal lead bar instead.</p>
              </div>
            </div>
          </div>
        </Section>

        {/* ── 03 THE SEAL ───────────────────────────────────────────────── */}
        <Section id="seal" n="03" title="The Seal" kicker="Redaction is the motif, the loading state and the promise">
          <div className="grid gap-4 md:grid-cols-3">
            <Card><CardHeader><Kicker>Sealed</Kicker><CardTitle>Supplier <Seal>Sample Flooring Co.</Seal></CardTitle><CardDescription>The identity is withheld. The bar is drawn, never text-hidden.</CardDescription></CardHeader></Card>
            <Card className="qd-gold-edge"><CardHeader><Kicker>Unsealed</Kicker><CardTitle>Supplier <Seal open className="qd-revealed">Sample Flooring Co.</Seal></CardTitle><CardDescription>Gold appears only here: a hairline sweeps the bar and it slides off toward inline-end, 320 ms expo-out.</CardDescription></CardHeader></Card>
            <Card><CardHeader><Kicker>Loop</Kicker><CardTitle>Supplier <Seal loop>Sample Flooring Co.</Seal></CardTitle><CardDescription>The demonstration loop. Under reduced motion it rests open.</CardDescription></CardHeader></Card>
            <Card className="md:col-span-3"><CardHeader><Kicker>Skeleton = redaction</Kicker></CardHeader><CardContent className="flex flex-col gap-3"><Skeleton className="w-2/5" /><Skeleton className="w-4/5 h-2!" /><Skeleton className="w-3/5 h-2!" /><div className="flex gap-3"><Skeleton className="h-9! w-9!" /><Skeleton className="h-9! w-32" /></div></CardContent></Card>
          </div>
        </Section>

        {/* ── 04 MATERIALS ──────────────────────────────────────────────── */}
        <Section id="materials" n="04" title="Materials" kicker="Glass · grain · key light · ruled grid">
          <div className="grid gap-4 md:grid-cols-3">
            <div className="qd-panel qd-grain flex h-48 flex-col justify-end p-5"><Kicker>.qd-panel + .qd-grain</Kicker></div>
            <div className="qd-panel qd-lit qd-panel-hover flex h-48 flex-col justify-end p-5"><Kicker>.qd-lit (hover)</Kicker></div>
            <div className="qd-frame flex h-48 flex-col justify-end p-5"><Kicker>.qd-frame</Kicker></div>
            <div className="qd-panel qd-grid-fine flex h-48 flex-col justify-end p-5"><Kicker>.qd-grid-fine</Kicker></div>
            <div className="qd-panel qd-ticks flex h-48 flex-col justify-end p-5"><Kicker>.qd-ticks</Kicker></div>
            <div className="qd-panel qd-keylight qd-mesh flex h-48 flex-col justify-end overflow-hidden p-5"><Kicker>.qd-keylight + .qd-mesh</Kicker></div>
          </div>
          <div className="mt-4 grid grid-cols-3 gap-4">
            {ELEV.map(([e, cls]) => (
              <div key={e} className={`flex h-28 items-end rounded-card border border-line bg-surf p-4 ${cls}`}><Spec k="shadow-" v={e} /></div>
            ))}
          </div>
          <div className="mt-4 flex flex-wrap gap-4">
            {RADII.map(([k, v, cls]) => (
              <div key={k} className={`grid h-20 w-24 place-items-center border border-line2 bg-surf ${cls}`}><Spec k={k} v={v} /></div>
            ))}
          </div>
        </Section>

        {/* ── 05 CONTROLS ───────────────────────────────────────────────── */}
        <Section id="controls" n="05" title="Controls" kicker="Every primitive, every state">
          <TooltipProvider delayDuration={150}>
            <div className="flex flex-col gap-6">
              <div className="qd-panel p-6">
                <Kicker>Buttons</Kicker>
                <div className="mt-5 flex flex-wrap items-center gap-3">
                  <Button>Primary</Button><Button variant="reveal">Reveal · 3%</Button><Button variant="secondary">Secondary</Button>
                  <Button variant="outline">Outline</Button><Button variant="ghost">Ghost</Button><Button variant="link">Link</Button>
                  <Button variant="destructive">Withdraw</Button><Button disabled>Disabled</Button>
                </div>
                <div className="mt-4 flex flex-wrap items-center gap-3">
                  <Button size="sm">Small</Button><Button>Default</Button><Button size="lg">Large</Button><Button size="xl" className="qd-magnet">XL · magnetic</Button>
                  <Button size="icon" variant="secondary" aria-label="Add">+</Button>
                </div>
              </div>
              <div className="qd-panel grid gap-4 p-6 md:grid-cols-2">
                <div className="flex flex-col gap-2"><label className="text-small text-muted" htmlFor="b1">Project name</label><Input id="b1" placeholder="Villa fit-out, Al Barsha" /></div>
                <div className="flex flex-col gap-2"><label className="text-small text-muted" htmlFor="b2">Invalid</label><Input id="b2" aria-invalid defaultValue="not-an-email" /></div>
                <div className="flex flex-col gap-2"><label className="text-small text-muted" htmlFor="b3">Disabled</label><Input id="b3" disabled defaultValue="Locked after reveal" /></div>
                <div className="flex flex-col gap-2"><span className="text-small text-muted">Progress · 64%</span><Progress value={64} className="mt-3" /></div>
              </div>
              <div className="qd-panel p-6">
                <Tabs defaultValue="levelled">
                  <TabsList><TabsTrigger value="received">As received</TabsTrigger><TabsTrigger value="levelled">Levelled</TabsTrigger><TabsTrigger value="verdict">Verdict</TabsTrigger></TabsList>
                  <TabsContent value="received" className="text-copy text-muted">Three quotes in three suppliers’ own orders.</TabsContent>
                  <TabsContent value="levelled" className="text-copy text-muted">Rows aligned by item on one grid.</TabsContent>
                  <TabsContent value="verdict" className="text-copy text-muted">The best match, with the reason.</TabsContent>
                </Tabs>
                <div className="mt-6 flex flex-wrap gap-3">
                  <Tooltip><TooltipTrigger asChild><Button variant="outline">Tooltip</Button></TooltipTrigger><TooltipContent>Identity sealed until reveal</TooltipContent></Tooltip>
                  <Popover><PopoverTrigger asChild><Button variant="outline">Popover</Button></PopoverTrigger><PopoverContent><Kicker>Why sealed</Kicker><p className="mt-3 text-small text-muted">Suppliers compete on the job, not on who is asking.</p></PopoverContent></Popover>
                  <DropdownMenu><DropdownMenuTrigger asChild><Button variant="outline">Dropdown</Button></DropdownMenuTrigger><DropdownMenuContent><DropdownMenuLabel>Quote Q-0412</DropdownMenuLabel><DropdownMenuSeparator /><DropdownMenuItem>Compare</DropdownMenuItem><DropdownMenuItem>Ask a question</DropdownMenuItem><DropdownMenuItem>Reveal supplier</DropdownMenuItem></DropdownMenuContent></DropdownMenu>
                  <Dialog><DialogTrigger asChild><Button variant="secondary">Dialog</Button></DialogTrigger><DialogContent><DialogHeader><DialogTitle>Reveal this supplier?</DialogTitle><DialogDescription>You pay 3% of the quote to open one identity. The other quotes stay sealed.</DialogDescription></DialogHeader><DialogFooter><Button variant="ghost">Keep sealed</Button><Button variant="reveal">Reveal · 3%</Button></DialogFooter></DialogContent></Dialog>
                  <Sheet><SheetTrigger asChild><Button variant="secondary">Sheet</Button></SheetTrigger><SheetContent><SheetHeader><SheetTitle>Quote Q-0412</SheetTitle><SheetDescription>Levelled against two others.</SheetDescription></SheetHeader><Skeleton className="mt-4 w-3/5" /><Skeleton className="mt-3 w-4/5 h-2!" /></SheetContent></Sheet>
                </div>
              </div>
              <Card>
                <CardHeader><Kicker>Table</Kicker><CardTitle>Received quotes</CardTitle></CardHeader>
                <Table>
                  <TableHeader><TableRow><TableHead>Quote</TableHead><TableHead>Supplier</TableHead><TableHead>Status</TableHead><TableHead className="text-end">Total (AED)</TableHead></TableRow></TableHeader>
                  <TableBody>
                    {[['Q-0412', false, 'ok', 'Complete', '38,750'], ['Q-0415', false, 'warn', 'Missing item', '34,200'], ['Q-0419', true, 'revealed', 'Revealed', '41,900']].map(([q, open, v, s, a]) => (
                      <TableRow key={q as string}>
                        <TableCell className="font-mono text-teal-light">{q as string}</TableCell>
                        <TableCell><Seal open={open as boolean} className={open ? 'qd-revealed' : undefined}>Sample Flooring Co.</Seal></TableCell>
                        <TableCell><Badge variant={v as 'ok'} dot>{s as string}</Badge></TableCell>
                        <TableCell className="text-end font-mono" dir="ltr">{a as string}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                <CardFooter><span className="font-mono text-label text-faint">{t.sample}</span></CardFooter>
              </Card>
            </div>
          </TooltipProvider>
        </Section>

        {/* ── 06 RECIPES ────────────────────────────────────────────────── */}
        <Section id="recipes" n="06" title="Recipes" kicker="Composed pieces for wave 2 · components/ui/sealed">
          <div className="flex flex-col gap-16">
            <SectionHead kicker="Section head" title="Suppliers compete. You stay unseen." lead="Describe the job once. Licence-verified suppliers quote blind. You see the top three, levelled, and pay 3% only to reveal one." />

            <Bento>
              <BentoTile span={4} tall kicker="Levelling" title="Three quotes, one grid" visual={
                <ProductFrame title="compare / Q-0412" sampleLabel={t.sample} status="Live" className="absolute inset-4 rounded-panel!">
                  <ComparisonShowcase suppliers={['A', 'B', 'C']} best={1} totals={['38,750', '36,900', '34,200']}
                    labels={{ item: 'Item', total: 'Total AED', missing: 'Missing', best: 'Best' }}
                    rows={[{ item: 'Gypsum partitions', values: ['9,400', '9,100', '8,800'] }, { item: 'Ceiling works', values: ['7,250', '6,900', '7,000'] }, { item: 'Paint & finishes', values: ['5,600', '5,400', '5,900'] }, { item: 'MEP first fix', values: ['16,500', '15,500', null] }]} />
                </ProductFrame>
              }>Every supplier lists scope in their own order. We align it, flag what is missing, and say why one fits best.</BentoTile>
              <BentoTile span={2} kicker="Anonymity" title="Your name never enters the room" visual={<div className="grid h-full place-items-center p-6"><div className="flex flex-col gap-3"><Seal>Customer: Villa 14</Seal><Seal>Supplier: Sample Co.</Seal></div></div>}>Both sides stay sealed until one reveal.</BentoTile>
              <BentoTile span={2} kicker="Verification" title="Licence-checked, every time">We verify trade licences before a supplier can quote.</BentoTile>
              <BentoTile span={3} kicker="Price" title="3% only on reveal">Nothing to pay to post, compare or decline.</BentoTile>
              <BentoTile span={3} kicker="Coverage" title="All seven emirates">Suppliers matched by trade and area.</BentoTile>
            </Bento>

            <div className="grid gap-6 xl:grid-cols-2">
              <ProductFrame title="boq / drawing-A-102.pdf" sampleLabel={t.sample} status="Reading">
                <BoqShowcase labels={{ code: 'Code', desc: 'Description', unit: 'Unit', qty: 'Qty' }} lines={[
                  { code: '02.10', desc: 'Gypsum board partition, 12.5 mm double layer', unit: 'm²', qty: '184.0' },
                  { code: '03.04', desc: 'Suspended ceiling, mineral tile 600 × 600', unit: 'm²', qty: '96.5' },
                  { code: '05.21', desc: 'Timber door set, single leaf', unit: 'nr', qty: '7' },
                  { code: '06.02', desc: 'Porcelain floor tiling 600 × 600', unit: 'm²', qty: '112.0' },
                  { code: '07.11', desc: 'Emulsion paint, two coats', unit: 'm²', qty: '420.0' },
                ]} />
              </ProductFrame>
              <ProductFrame title="match / flooring · Dubai" sampleLabel={t.sample} status="3 of 12">
                <MatchShowcase labels={{ match: 'Match' }} matches={[
                  { name: 'Sample Flooring Co.', score: 94, facts: 'Licence verified · 11 years · Al Quoz', revealed: true },
                  { name: 'Sample Supplier B', score: 88, facts: 'Licence verified · 7 years · Jebel Ali' },
                  { name: 'Sample Supplier C', score: 81, facts: 'Licence verified · 4 years · Sharjah' },
                ]} />
              </ProductFrame>
            </div>

            <div className="grid gap-8 md:grid-cols-3">
              <StatBlock value="3%" label="Paid only to reveal one supplier" note="Price rule" />
              <StatBlock value="3" label="Quotes levelled side by side" note="Per request, top three" />
              <StatBlock value="7" label="Emirates covered" note="UAE-wide" />
            </div>

            <div className="grid gap-10 lg:grid-cols-2">
              <Stepper steps={[
                { meta: 'Day 0', title: 'Describe the job', body: 'Upload a drawing or write the scope.', state: 'done' },
                { meta: 'Day 1–3', title: 'Suppliers quote blind', body: 'Licence-verified suppliers price the same scope.', state: 'current' },
                { meta: 'Day 4', title: 'Compare the top three', body: 'Levelled, gaps flagged, one best match.', state: 'next' },
                { meta: 'When ready', title: 'Reveal one', body: 'Pay 3% and both sides see each other.', state: 'next' },
              ]} />
              <div className="flex flex-col gap-6">
                <FactBand facts={[{ k: 'Licence', v: 'DET verified' }, { k: 'Identity', v: 'Sealed' }, { k: 'Fee', v: '3% on reveal' }, { k: 'Coverage', v: '7 emirates' }]} />
                <ProofBand className="md:grid-cols-1" items={[
                  { claim: 'Suppliers cannot price you, only the job.', evidence: 'Your name, phone and address are withheld from every supplier until you reveal one.' },
                  { claim: 'You compare like with like.', evidence: 'Every quote is levelled onto one item grid; missing scope is flagged, not hidden.' },
                ]} />
              </div>
            </div>
          </div>
        </Section>

        {/* ── 07 CONTRAST ───────────────────────────────────────────────── */}
        <Section id="contrast" n="07" title="Contrast" kicker="WCAG AA over every token pair · scripts/brand_contrast.mjs">
          <Card>
            <Table>
              <TableHeader><TableRow><TableHead>Pair</TableHead><TableHead>Sample</TableHead><TableHead className="text-end">Ratio</TableHead><TableHead className="text-end">AA</TableHead></TableRow></TableHeader>
              <TableBody>
                {PAIRS.map((p) => {
                  const r = contrast(p.fg, p.bg);
                  return (
                    <TableRow key={p.use}>
                      <TableCell className="text-muted">{p.use}</TableCell>
                      <TableCell><span className="rounded-chip px-2.5 py-1 text-small font-medium" style={{ color: p.fg, background: p.bg }}>Aa 12,400</span></TableCell>
                      <TableCell className="text-end font-mono" dir="ltr">{r.toFixed(2)}:1</TableCell>
                      <TableCell className="text-end"><Badge variant={r >= p.min ? 'ok' : 'danger'}>{r >= p.min ? `≥ ${p.min}` : 'fail'}</Badge></TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </Card>
          <p className="mt-4 text-small text-faint">{t.note}</p>
        </Section>
      </main>
      <SiteFooter />
    </>
  );
}
