'use client';
// Spec §6 (3D Project Visualization) + the §19 Project Room.
//
// ── WHY three.js AND NOT THE SUPPLIED cad-viewer ────────────────────────────────────────────────
// vendor/reference/cad-viewer was read before this was written. Three findings, in the order they
// mattered:
//
//  1. LICENCE. The core packages (@mlightcad/cad-viewer, cad-simple-viewer, three-renderer) are
//     MIT, but the DWG path is libredwg-web, which is GPL-3.0. Serving that JS/WASM to a browser
//     is conveying under GPL-3.0 — the visitor receives a copy — so a closed-source hosted product
//     that shipped it would owe the Corresponding Source of the combined work. The project agrees
//     with that reading: PROPRIETARY-PARSER.md sells a closed DWG parser for USD 3,000 aimed at
//     exactly "a SaaS ... that cannot distribute GPL-3.0 code to your customers".
//  2. STACK. packages/cad-viewer is a Vue 3 + element-plus application (vue-tsc, @vitejs/plugin-vue,
//     @element-plus/icons-vue). Mounting it here means shipping Vue and a second component library
//     into a React 19 / Next 16 bundle.
//  3. FIT — the decisive one. cad-viewer renders CAD ENTITIES out of a DWG/DXF file. Spec §6 asks
//     for a model whose components carry PROCUREMENT STATUS and open their RFQs when clicked. A DXF
//     entity has no link to an inquiry, and QuotesDone holds no DWG/DXF project geometry at all, so
//     even a perfect CAD viewer would answer none of §6.
//
// So: three.js directly — MIT, and the same renderer cad-viewer's own MIT @mlightcad/three-renderer
// wraps. That keeps the door open: if customers ever upload real drawings, three-renderer +
// cad-simple-viewer drop onto this same scene, DXF-only, with the GPL-3.0 DWG converter excluded.
//
// three is DYNAMICALLY imported inside the effect below, so it lands in its own async chunk and
// never enters the main bundle. Nothing above the fold pays for it.
//
// ── AND WHY THE SCENE LOOKS LIKE THIS ───────────────────────────────────────────────────────────
// Every block is ONE REAL LINKED RFQ, coloured by a status derived from real fields (see
// ./model.ts). There is no per-floor component model in this database — measured, not assumed —
// so unless the project carries a storey model in projects.meta the bands are the project's own
// trade categories and the caption says so in the customer's own language. No block stands for a
// component nobody requested.
import { useEffect, useMemo, useRef, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import {
  buildModel, chainLegs, docsForRfq, elapsedPct, fmtDate, money,
  NO_INQUIRIES, STAGE_COLOR, STAGE_LABEL,
  type CustomerOrder, type Lang, type PackageStage, type PortalInquiry,
  type SpatialPackage, type SpatialProject, type SpatialRfq, type VaultDoc,
} from './model';
import { tx } from './strings';

export interface ProjectRoomProps {
  project: SpatialProject | null;
  rfqs: SpatialRfq[];
  orders: CustomerOrder[];
  documents: VaultDoc[];
  /** my_inquiries rows the portal already holds — used ONLY for quote counts and revealed names. */
  inquiries?: PortalInquiry[];
  lang?: Lang;
  /** Called with an inquiry id when the customer asks to open the request itself. */
  onOpenRfq?: (rfqId: string) => void;
}

const BLOCK = { w: 1.6, h: 0.9, d: 1.6, gap: 0.5, band: 2.0, perRow: 5 };

/** Where one block sits. Deterministic, so the same project draws the same building twice running. */
function layout(levelIndex: number, i: number, n: number) {
  const cols = Math.min(BLOCK.perRow, n);
  const row = Math.floor(i / cols);
  const col = i % cols;
  const inRow = Math.min(cols, n - row * cols);
  const spanX = inRow * BLOCK.w + (inRow - 1) * BLOCK.gap;
  return {
    x: -spanX / 2 + BLOCK.w / 2 + col * (BLOCK.w + BLOCK.gap),
    y: levelIndex * BLOCK.band + BLOCK.h / 2 + 0.12,
    z: row * (BLOCK.d + BLOCK.gap) - ((Math.ceil(n / cols) - 1) * (BLOCK.d + BLOCK.gap)) / 2,
  };
}

export function ProjectRoom({ project, rfqs, orders, documents, inquiries = NO_INQUIRIES, lang = 'en', onOpenRfq }: ProjectRoomProps) {
  const model = useMemo(() => buildModel(project, rfqs, orders, inquiries), [project, rfqs, orders, inquiries]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [glFailed, setGlFailed] = useState(false);
  const host = useRef<HTMLDivElement | null>(null);
  const selectRef = useRef(setSelectedId);
  selectRef.current = setSelectedId;

  const flat = useMemo(
    () => model.levels.flatMap((l, li) => l.packages.map((p, i) => ({ p, li, i, n: l.packages.length }))),
    [model],
  );
  const selected = flat.find((f) => f.p.rfqId === selectedId)?.p || null;

  // ── the scene ─────────────────────────────────────────────────────────────────────────────────
  // One effect owns the whole three lifecycle: import, build, animate, dispose. Rebuilt when the
  // model changes because the geometry IS the data — there is no incremental path worth the code.
  useEffect(() => {
    const el = host.current;
    if (!el || flat.length === 0) return;
    let disposed = false;
    let cleanup: (() => void) | null = null;

    (async () => {
      const THREE = await import('three');
      if (disposed || !host.current) return;

      let renderer: import('three').WebGLRenderer;
      try {
        renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
      } catch {
        setGlFailed(true);
        return;
      }
      const w = el.clientWidth || 640;
      const h = el.clientHeight || 360;
      renderer.setPixelRatio(Math.min(2, typeof window === 'undefined' ? 1 : window.devicePixelRatio || 1));
      renderer.setSize(w, h, false);
      renderer.domElement.style.width = '100%';
      renderer.domElement.style.height = '100%';
      renderer.domElement.style.display = 'block';
      renderer.domElement.style.touchAction = 'none';
      renderer.domElement.setAttribute('aria-hidden', 'true');
      el.appendChild(renderer.domElement);

      const scene = new THREE.Scene();
      scene.add(new THREE.HemisphereLight(0xdff2f0, 0x0a1a24, 1.5));
      const key = new THREE.DirectionalLight(0xffffff, 1.1);
      key.position.set(6, 12, 8);
      scene.add(key);

      const owned: Array<{ dispose(): void }> = [];
      const track = <T extends { dispose(): void }>(x: T): T => { owned.push(x); return x; };
      const blocks: Array<import('three').Mesh> = [];
      const levelCount = model.levels.length;

      // A thin plate under each band. It is a plate, not a floor slab pretending to be a storey —
      // the caption under the canvas names what the bands are.
      const plateGeom = track(new THREE.BoxGeometry(1, 0.08, 1));
      const plateMat = track(new THREE.MeshStandardMaterial({ color: 0x14313f, roughness: 0.95, transparent: true, opacity: 0.55 }));
      model.levels.forEach((l, li) => {
        const n = l.packages.length;
        if (!n) return;
        const cols = Math.min(BLOCK.perRow, n);
        const rows = Math.ceil(n / cols);
        const plate = new THREE.Mesh(plateGeom, plateMat);
        plate.scale.set(cols * (BLOCK.w + BLOCK.gap) + 0.6, 1, rows * (BLOCK.d + BLOCK.gap) + 0.6);
        plate.position.set(0, li * BLOCK.band, 0);
        scene.add(plate);
      });

      const boxGeom = track(new THREE.BoxGeometry(BLOCK.w, BLOCK.h, BLOCK.d));
      const matFor = new Map<PackageStage, import('three').MeshStandardMaterial>();
      for (const stage of Object.keys(STAGE_COLOR) as PackageStage[]) {
        matFor.set(stage, track(new THREE.MeshStandardMaterial({
          color: new THREE.Color(STAGE_COLOR[stage]), roughness: 0.45, metalness: 0.05,
        })));
      }
      for (const { p, li, i, n } of flat) {
        const mesh = new THREE.Mesh(boxGeom, matFor.get(p.stage));
        const at = layout(li, i, n);
        mesh.position.set(at.x, at.y, at.z);
        mesh.userData.rfqId = p.rfqId;
        scene.add(mesh);
        blocks.push(mesh);
      }

      // Frame the whole massing rather than guessing a camera distance.
      const bounds = new THREE.Box3().setFromObject(scene);
      const size = bounds.getSize(new THREE.Vector3());
      const centre = bounds.getCenter(new THREE.Vector3());
      const radius = Math.max(3, size.length() * 0.62);
      const camera = new THREE.PerspectiveCamera(42, w / h, 0.1, 500);

      // ponytail: hand-rolled orbit — spherical angles + wheel zoom, on pointer events so mouse,
      // pen and touch all work with one code path. OrbitControls would be one import but ~15 kB
      // and a resolution path three@0.180 does not type; this is 25 lines and does the two gestures
      // a massing needs. Swap it in if pan, damping or gizmos are ever asked for.
      const cam = { az: Math.PI * 0.28, el: 0.62, r: radius };
      const place = () => {
        camera.position.set(
          centre.x + cam.r * Math.cos(cam.el) * Math.sin(cam.az),
          centre.y + cam.r * Math.sin(cam.el),
          centre.z + cam.r * Math.cos(cam.el) * Math.cos(cam.az),
        );
        camera.lookAt(centre);
      };
      place();

      const cv = renderer.domElement;
      let dragging = false, moved = 0, lastX = 0, lastY = 0, pid = -1;
      const onDown = (e: PointerEvent) => {
        dragging = true; moved = 0; lastX = e.clientX; lastY = e.clientY; pid = e.pointerId;
        try { cv.setPointerCapture(pid); } catch { /* capture is best-effort */ }
      };
      const onMove = (e: PointerEvent) => {
        if (!dragging) return;
        const dx = e.clientX - lastX, dy = e.clientY - lastY;
        lastX = e.clientX; lastY = e.clientY; moved += Math.abs(dx) + Math.abs(dy);
        cam.az -= dx * 0.006;
        cam.el = Math.max(0.08, Math.min(1.45, cam.el + dy * 0.005));
        place();
      };
      const raycaster = new THREE.Raycaster();
      const ndc = new THREE.Vector2();
      const onUp = (e: PointerEvent) => {
        if (!dragging) return;
        dragging = false;
        try { cv.releasePointerCapture(pid); } catch { /* nothing captured */ }
        if (moved > 6) return; // a drag is an orbit, not a click
        const r = cv.getBoundingClientRect();
        ndc.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
        raycaster.setFromCamera(ndc, camera);
        const hit = raycaster.intersectObjects(blocks, false)[0];
        if (hit) selectRef.current(String((hit.object as import('three').Mesh).userData.rfqId));
      };
      const onWheel = (e: WheelEvent) => {
        e.preventDefault();
        cam.r = Math.max(radius * 0.45, Math.min(radius * 2.4, cam.r + e.deltaY * 0.01));
        place();
      };
      cv.addEventListener('pointerdown', onDown);
      cv.addEventListener('pointermove', onMove);
      cv.addEventListener('pointerup', onUp);
      cv.addEventListener('pointercancel', onUp);
      cv.addEventListener('wheel', onWheel, { passive: false });

      const ro = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(() => {
        const nw = el.clientWidth || w, nh = el.clientHeight || h;
        renderer.setSize(nw, nh, false);
        camera.aspect = nw / nh;
        camera.updateProjectionMatrix();
      });
      ro?.observe(el);

      let raf = 0;
      const tick = () => { raf = requestAnimationFrame(tick); renderer.render(scene, camera); };
      tick();

      cleanup = () => {
        cancelAnimationFrame(raf);
        ro?.disconnect();
        cv.removeEventListener('pointerdown', onDown);
        cv.removeEventListener('pointermove', onMove);
        cv.removeEventListener('pointerup', onUp);
        cv.removeEventListener('pointercancel', onUp);
        cv.removeEventListener('wheel', onWheel);
        for (const o of owned) o.dispose();
        renderer.dispose();
        cv.remove();
      };
    })().catch(() => setGlFailed(true));

    return () => { disposed = true; if (cleanup) cleanup(); };
  }, [model, flat]);

  const nBlocks = model.packageCount;
  const nLevels = model.levels.length;

  return (
    <Card className="p-4 md:p-5 bg-card/70 backdrop-blur border-border">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <div className="text-[15px] font-bold text-foreground">{tx(lang, 'model_title')}</div>
          <div className="text-[13px] text-muted-foreground">{project ? project.name : tx(lang, 'room_title')}</div>
        </div>
        <StageLegend lang={lang} />
      </div>

      {nBlocks === 0 ? (
        <div className="mt-3 rounded-lg border border-dashed border-border bg-secondary/20 p-5 text-center">
          <div className="text-[14px] font-semibold text-foreground">{tx(lang, 'model_empty_title')}</div>
          <div className="mt-1 text-[13px] leading-relaxed text-muted-foreground">{tx(lang, 'model_empty_body')}</div>
        </div>
      ) : (
        <>
          <div className="mt-3 grid gap-3 lg:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)]">
            <div>
              {glFailed ? (
                <div className="rounded-lg border border-border bg-secondary/20 p-4 text-[13px] leading-relaxed text-muted-foreground">
                  {tx(lang, 'webgl_missing')}
                </div>
              ) : (
                <div
                  ref={host}
                  className="h-[320px] md:h-[400px] w-full rounded-lg border border-border bg-gradient-to-b from-secondary/40 to-background overflow-hidden transition-colors"
                />
              )}
              <div className="mt-1.5 text-[11.5px] text-muted-foreground">{tx(lang, 'model_hint')}</div>
            </div>

            {/* The same blocks as real buttons. The canvas is aria-hidden — a mesh is not in the
                accessibility tree, so without this list a keyboard or screen-reader customer could
                not open a single one of their own packages. It is also the band label track, which
                is why no text is drawn into the scene. */}
            <div className="max-h-[400px] overflow-y-auto pr-1">
              {model.levels.map((l) => (
                <div key={l.key} className="mb-3">
                  <div className="text-[12px] font-semibold uppercase tracking-wide text-muted-foreground mb-1">{l.label}</div>
                  <div className="flex flex-col gap-1.5">
                    {l.packages.map((p) => (
                      <button
                        key={p.rfqId}
                        onClick={() => setSelectedId(p.rfqId)}
                        aria-pressed={selectedId === p.rfqId}
                        className={cn(
                          'flex items-center gap-2 rounded-md border px-2.5 py-2 text-left transition-colors duration-150',
                          selectedId === p.rfqId ? 'border-primary bg-primary/10' : 'border-border bg-secondary/20 hover:bg-secondary/40',
                        )}
                      >
                        <span className="inline-block h-2.5 w-2.5 rounded-sm shrink-0" style={{ backgroundColor: STAGE_COLOR[p.stage] }} />
                        <span className="min-w-0 flex-1">
                          <span className="block truncate text-[13px] font-semibold capitalize text-foreground">{p.category}</span>
                          <span className="block truncate text-[11.5px] text-muted-foreground">{STAGE_LABEL[lang][p.stage]}{p.value == null ? '' : ' · ' + money(p.value)}</span>
                        </span>
                      </button>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="mt-2 text-[12px] leading-relaxed text-muted-foreground">
            {model.source === 'project_meta_levels' ? tx(lang, 'model_from_meta') : tx(lang, 'model_from_trades')}
            {' '}
            <span className="text-foreground/80">
              {nBlocks} {nBlocks === 1 ? tx(lang, 'blocks_one') : tx(lang, 'blocks_many')} · {nLevels} {nLevels === 1 ? tx(lang, 'level_one') : tx(lang, 'level_many')}
            </span>
          </div>
        </>
      )}

      <PackageDetail
        pkg={selected}
        project={project}
        documents={documents}
        inquiries={inquiries}
        lang={lang}
        onOpenRfq={onOpenRfq}
      />
    </Card>
  );
}

function StageLegend({ lang }: { lang: Lang }) {
  const stages: PackageStage[] = ['requested', 'quotation', 'ordered', 'delivered'];
  return (
    <div className="flex flex-wrap items-center gap-2.5">
      <span className="text-[11.5px] font-semibold uppercase tracking-wide text-muted-foreground">{tx(lang, 'legend')}</span>
      {stages.map((s) => (
        <span key={s} className="flex items-center gap-1.5 text-[11.5px] text-muted-foreground">
          <span className="inline-block h-2.5 w-2.5 rounded-sm" style={{ backgroundColor: STAGE_COLOR[s] }} />
          {STAGE_LABEL[lang][s]}
        </span>
      ))}
    </div>
  );
}

/**
 * "Click any component: opens RFQs, suppliers, documents, costs, timeline." All five, each from a
 * named source, each with its own empty state — never one sentence covering all five absences.
 */
function PackageDetail({ pkg, project, documents, inquiries, lang, onOpenRfq }: {
  pkg: SpatialPackage | null;
  project: SpatialProject | null;
  documents: VaultDoc[];
  inquiries: PortalInquiry[];
  lang: Lang;
  onOpenRfq?: (rfqId: string) => void;
}) {
  if (!pkg) {
    return <div className="mt-3 rounded-lg border border-border bg-secondary/20 p-3 text-[13px] text-muted-foreground">{tx(lang, 'sel_none')}</div>;
  }
  const inq = inquiries.find((i) => i.id === pkg.rfqId) || null;
  const quotes = inq && Array.isArray(inq.quotes) ? inq.quotes : null;
  const revealed = (quotes || []).filter((q) => q && q.revealed && q.supplier);
  const docs = docsForRfq(documents, pkg.rfqId);
  const legs = chainLegs(pkg.orders);
  const ordered = pkg.orders.reduce((a, o) => a + (Number(o.subtotal) || 0), 0);
  const pct = project ? elapsedPct(project.created_at, project.target_open_date) : null;

  return (
    <div className="mt-3 rounded-lg border border-primary/30 bg-primary/5 p-3.5">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div className="flex items-center gap-2">
          <span className="inline-block h-3 w-3 rounded-sm" style={{ backgroundColor: STAGE_COLOR[pkg.stage] }} />
          <span className="text-[15px] font-bold capitalize text-foreground">{pkg.category}</span>
          <Badge variant="secondary">{STAGE_LABEL[lang][pkg.stage]}</Badge>
        </div>
        {onOpenRfq ? <Button size="sm" variant="secondary" onClick={() => onOpenRfq(pkg.rfqId)}>{tx(lang, 'sel_open_rfq')}</Button> : null}
      </div>

      <div className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <Facet title={tx(lang, 'sel_rfqs')}>
          <div className="text-[12.5px] text-foreground">{pkg.summary || '—'}</div>
          <div className="mt-0.5 text-[11.5px] text-muted-foreground">{pkg.emirate || '—'}</div>
        </Facet>

        <Facet title={tx(lang, 'sel_suppliers')}>
          {quotes == null ? <Muted>{tx(lang, 'quotes_unknown')}</Muted>
            : quotes.length === 0 ? <Muted>{tx(lang, 'quotes_none')}</Muted>
              : (<>
                <div className="text-[12.5px] text-foreground">{quotes.length} {tx(lang, 'quotes_n')}</div>
                {revealed.length
                  ? <div className="mt-0.5 text-[11.5px] text-foreground/85">{revealed.map((q) => q.supplier).join(', ')}</div>
                  : <Muted>{tx(lang, 'sup_hidden')}</Muted>}
              </>)}
        </Facet>

        <Facet title={tx(lang, 'sel_documents')}>
          {docs.length === 0 ? <Muted>{tx(lang, 'docs_none')}</Muted> : (
            <ul className="space-y-0.5">
              {docs.slice(0, 6).map((d) => (
                <li key={d.id} className="truncate text-[12px] text-foreground/90">
                  <span className="capitalize text-muted-foreground">{d.kind}</span> · {d.file_name || '—'}
                  {d.expiry_date ? <span className="text-muted-foreground"> · {fmtDate(d.expiry_date, lang)}</span> : null}
                </li>
              ))}
            </ul>
          )}
        </Facet>

        <Facet title={tx(lang, 'sel_costs')}>
          {pkg.value == null && ordered === 0 ? <Muted>{tx(lang, 'costs_none')}</Muted> : (
            <div className="space-y-0.5 text-[12.5px]">
              {pkg.value != null ? <div className="text-foreground">{tx(lang, 'costs_expected')}: {money(pkg.value)}</div> : null}
              {ordered > 0 ? <div className="text-foreground">{tx(lang, 'costs_ordered')}: {money(ordered, pkg.orders[0]?.currency || 'AED')}</div> : null}
            </div>
          )}
        </Facet>

        <Facet title={tx(lang, 'sel_timeline')}>
          <div className="space-y-0.5 text-[12px]">
            <div className="text-foreground/90">{tx(lang, 'tl_created')}: {fmtDate(pkg.createdAt, lang)}</div>
            {legs.map((g) => (
              <div key={g.orderId} className="text-foreground/90">
                {tx(lang, 'tl_ordered')}: {fmtDate(g.orderDate, lang)} · {tx(lang, 'tl_expected')}: {fmtDate(g.expectedDate, lang)}
              </div>
            ))}
            {project ? <div className="text-muted-foreground">{tx(lang, 'tl_target')}: {fmtDate(project.target_open_date, lang)}</div> : null}
            {pct == null ? <Muted>{tx(lang, 'tl_no_target')}</Muted> : <div className="text-muted-foreground">{pct}% {tx(lang, 'tl_elapsed')}</div>}
          </div>
        </Facet>
      </div>
    </div>
  );
}

const Facet = ({ title, children }: { title: string; children: React.ReactNode }) => (
  <div className="rounded-md border border-border bg-card/60 p-2.5">
    <div className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{title}</div>
    {children}
  </div>
);

const Muted = ({ children }: { children: React.ReactNode }) => (
  <div className="text-[11.5px] leading-relaxed text-muted-foreground">{children}</div>
);
