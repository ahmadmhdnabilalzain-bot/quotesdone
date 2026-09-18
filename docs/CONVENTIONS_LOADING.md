# Loading states — the standing convention

**Founder instruction, 18 September 2026, verbatim:**

> "in general in our website, wherever you go, wherever you press, when things are loading, there's
> no sort of an animation that says it's loading… for general people it would be nice to show that
> there is sort of an animation that things are loading. So in general, this should be everywhere.
> Whenever someone presses something, if it's not instant, then during that second, for example, or
> two seconds, there should be a sort of an animation showing loading until that thing is done."

This file is the standing rule. It governs every surface — the two portals, sign-in and OTP, uploads
and downloads, quotation submit, the quotation review chat, search and filters, and the public
marketing pages. It applies to work in this repository from now on, not only to the change that
created it.

---

## 1. Where the system lives

| Thing | File |
|---|---|
| Hook + button + region + note | `src/components/ui/busy.tsx` |
| Top bar for route changes | `src/components/ui/route-progress.tsx` (mounted once in `src/app/[locale]/layout.tsx`) |
| The ring and the bar, in CSS | `src/app/globals.css` §2b — `.qd-spin`, `.qd-routebar` |
| Content skeleton | `src/components/ui/skeleton.tsx` — the brand redaction bar, `.redact` |

There is no loading library and there must not be one. The bundle is already 1.35 MB; a rotating
ring and a scaling bar are two CSS properties. `motion` is in the bundle for other reasons — do not
reach for it here.

## 2. The four rules

1. **Show nothing under ~150 ms.** A 40 ms round trip that flashes a spinner reads as a glitch, not
   as work. `SHOW_AFTER_MS = 150`.
2. **Once shown, hold for ~300 ms.** A 160 ms round trip must not strobe. `MIN_SHOW_MS = 300`.
3. **Block re-triggering from the FIRST millisecond**, not from the moment the indicator appears —
   the double-submit window is exactly the 150 ms before it shows. `useBusy().pending` is the value
   that goes into `disabled`; `useBusy().busy` is the one that draws the ring. `run()` guards on a
   ref, not on state, because two clicks in one React batch both see the old state.
4. **A failure resolves the indicator into a visible error.** A spinner that never ends cannot tell
   "broken" from "idle" — the same defect this codebase already has a lens for
   (`zero-cannot-tell-a-dead-guard-from-an-idle-system`). `run()` catches into `error` so a call site
   cannot leave one spinning by forgetting a `catch`.

**Anything already instant stays instant.** Local state, client-side filters, menu open/close, an
optimistic update — no indicator. Rule 1 does this for free: if the work finishes in 40 ms nothing
was ever drawn.

## 3. How to write a new action

```tsx
const b = useBusy<'save' | 'del'>();

<BusyButton busy={b} act="save" busyLabel={t(lang, 'saving')}
            onClick={() => b.run('save', () => call('customer_api', { action: 'save_x' }, token))}>
  {t(lang, 'save')}
</BusyButton>
{b.error ? <p className="text-danger-fg">{b.error}</p> : null}
```

An **existing** hand-rolled `busy` boolean does not need rewriting. Bridge it:

```tsx
const shown = useDelayedFlag(busy);      // rules 1 and 2, applied to somebody else's flag
<Button disabled={busy} aria-busy={shown || undefined}>{shown ? <Spinner /> : null}{label}</Button>
```

A **content area** that is fetching:

```tsx
<BusyRegion busy={!data} error={err} onRetry={load} fallback={<><Skeleton /><Skeleton className="w-2/3" /></>}>
  {…}
</BusyRegion>
```

A **navigation** that pulls a new bundle (`/me`, `/portal`, `/supplier`, a locale switch):

```tsx
const [pending, start] = useTransition();
const shown = useDelayedFlag(pending);
onClick={() => { startRouteProgress(); start(() => router.push('/me?draft=1')); }}
```

Plain `<Link>` navigations need nothing — `RouteProgress` listens for the click at the document and
covers every anchor on the site.

## 4. Accessibility — not optional

- `aria-busy` on the control or the region that is working.
- `aria-live="polite"` on the text that announces it. `BusyRegion` and `BusyNote` already carry it.
- `prefers-reduced-motion: reduce` gets a **static** ring and a **static** bar — an indicator that is
  present but still. Never nothing: removing the only signal from the people who asked for less
  motion is the opposite of the instruction.

## 5. Arabic and RTL

- Every new user-visible string is EN **and** AR. The portals read `t(lang, key)` from
  `src/components/me/portalText.ts`, a local `strings.ts` (`tr(lang, key)`), or inline
  `ar ? '…' : '…'` — follow the file you are in, and put real Arabic in both tables.
- The **ring** is deliberately not mirrored: a counter-clockwise spinner reads as "undoing" in every
  locale.
- The **bar** is the thing with a direction. It grows from `inset-inline-start`, so it fills
  right-to-left in Arabic with no `[dir]` rule. Its `transform-origin` is the one exception —
  `transform-origin` has no logical keyword, so `[dir="rtl"] .qd-routebar::before` flips it.
- Any new directional indicator must be checked in `/ar` before it merges.

## 6. The guard

`scripts/checks/an_action_that_waits_says_so.test.mjs` fails a **new** async handler that performs a
network call without any busy affordance in its body. It reads source, so it is coarse by design: it
proves an action was written with the convention in mind, not that the affordance is correct. Correct
is what review is for.

When an action genuinely needs no indicator (it is instant, or the indicator lives on a different
element), say so on the handler:

```js
// busy-exempt: local state only, nothing is awaited across the network
```

The exemption must name the reason. An unexplained exemption is a check edited until it went green,
which this repository does not do.
