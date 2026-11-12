
// Typography and chrome carry the platform's voice: display weights are optically
// tightened, body copy keeps a readable measure, and the tab bar is an inset well
// with a RAISED active pill rather than a tinted one — so the current tab reads as
// nearer to the viewer, which is how the rest of the product signals state.
// TO A FINGER, NOTHING SMALLER THAN SAFARI READS WITHOUT ZOOMING (12 Nov 2026, customer_support; browser perfection walk H3, M19).
// Measured at 390x844: the explanations 13 px, the hints 12 px, the errors 13 px, the lists and text areas 14 px. Under
// `pointer: coarse` the explanations and errors are 15 px, the hints 14 px, and every list and text area 16 px (Safari zooms the
// page into a box under 16 px); a mouse keeps the desktop's sizes.
const S = {
  center: 'grid place-items-center min-h-[70vh] p-5',
  h1: 'text-[22px] font-extrabold tracking-[-.03em] text-foreground',
  h2: 'text-[15.5px] font-bold tracking-[-.018em] text-foreground',
  sub: 'text-[13px] pointer-coarse:text-[15px] leading-[1.65] text-muted-foreground max-w-[68ch]',
  anon: 'ms-1.5 text-[11px] font-semibold text-muted-foreground/80',
  hint: 'text-xs pointer-coarse:text-[14px] text-muted-foreground my-2 leading-relaxed max-w-[68ch]',
  err: 'text-[13px] pointer-coarse:text-[15px] text-danger-fg mt-2',
  wrap: 'max-w-[1040px] mx-auto px-[22px] py-7',
  frow: 'flex gap-2.5 flex-wrap mt-2.5',
  tabsWrap: 'qd-tabs inline-flex flex-wrap gap-1 p-1.5',
  // 44px is the floor for anything a thumb presses. Measured on a phone 22 Sep 2026 (SP-M-01): the
  // sign-in / create-account tabs were 134x37 and the registration <select> 42 tall. `min-h-11` is
  // on the shared tab class so no caller can forget it; the main nav strip already added its own.
  tab: 'qd-tab min-h-11 px-3.5 py-2 text-[13px] font-semibold text-muted-foreground cursor-pointer border-0 bg-transparent',
  tabOn: 'qd-tab-on',
  list: 'flex flex-col gap-3',
  section: 'qd-section',
  figure: 'qd-figure',
  field: 'mt-3 flex min-h-11 w-full rounded-md border border-input bg-transparent px-3 text-sm pointer-coarse:text-[16px] text-foreground placeholder:text-muted-foreground focus-visible:outline-hidden focus-visible:ring-1 focus-visible:ring-ring',
  area: 'mt-3 flex w-full rounded-md border border-input bg-transparent px-3 py-2.5 text-sm pointer-coarse:text-[16px] text-foreground placeholder:text-muted-foreground focus-visible:outline-hidden focus-visible:ring-1 focus-visible:ring-ring resize-y',
  chip: 'rounded-full border border-border bg-secondary/40 px-3 py-1.5 text-[12.5px] font-semibold text-muted-foreground cursor-pointer',
  chipOn: 'bg-primary/15 border-primary/60 text-primary',
  fileInput: 'text-sm text-muted-foreground file:me-3 file:rounded-md file:border-0 file:bg-secondary file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-secondary-foreground hover:file:bg-secondary/80',
};
export { S };
