'use client';
// ROW #5 §19 §22 §23 — THE SUPPLIER NETWORK MAP.
//
// ── ONE LAYER HAS DATA AND THREE DO NOT, AND THE GLOBE SAYS WHICH ───────────────────────────────
// Measured on production: 20,464 leads carry an emirate (real, dense); 0 inquiries; 0 projects;
// no shipments relation exists at all. §19 asks for four layers. Three of them have nothing.
//
// So the empty layers render as DISABLED toggles carrying their own reason, not as plausible dots.
// A globe speckled with invented demand would be the most seductive lie in this spec: it looks like
// market intelligence, it photographs well, and nobody can tell by looking that it is nothing.
//
// ── AND THE COUNT ON A MARKER IS TWO DIFFERENT CLAIMS ───────────────────────────────────────────
// `count` is how many companies the platform KNOWS OF in an emirate. `matchable` is how many can
// actually receive an RFQ — on production that is 0 everywhere, because nothing is verified. Both
// are shown, because letting the first stand in for the second is exactly how a scraped prospect
// list gets mistaken for a supplier network.
import React, { Suspense, useEffect, useMemo, useState } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { Html, OrbitControls, Sphere } from '@react-three/drei';
import type { Group } from 'three';

type Marker = { name: string; lat: number; lng: number; count: number; matchable: number };
type Layer = { basis?: string; count?: number; unplaced?: number; markers?: Marker[]; note?: string };
type MapData = {
  suppliers?: Layer; demand?: Layer; projects?: Layer; shipments?: Layer;
  totals?: { leads?: number; placed?: number; matchable?: number };
};
type Lang = 'en' | 'ar';
type LayerKey = 'suppliers' | 'demand' | 'projects' | 'shipments';

const FN = (process.env.NEXT_PUBLIC_SUPABASE_URL || '') + '/functions/v1';
const ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

async function call(path: string, body: unknown, token?: string | null) {
  const r = await fetch(FN + '/' + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) },
    body: JSON.stringify(body),
  });
  return r.json();
}

const T = {
  en: {
    title: 'Supplier Network Map', suppliers: 'Suppliers', demand: 'Demand',
    projects: 'Projects', shipments: 'Shipments', known: 'known', matchable: 'matchable',
    loading: 'Plotting the network…', noData: 'no data to plot',
    placed: 'placed', unplaced: 'unplaced', hint: 'Drag to rotate. Click a marker.',
    matchableNote: 'Nothing is verified yet, so no company here can receive an RFQ.',
  },
  ar: {
    title: 'خريطة شبكة الموردين', suppliers: 'الموردون', demand: 'الطلب',
    projects: 'المشاريع', shipments: 'الشحنات', known: 'معروف', matchable: 'قابل للمطابقة',
    loading: 'جارٍ رسم الشبكة…', noData: 'لا توجد بيانات للرسم',
    placed: 'محدد', unplaced: 'غير محدد', hint: 'اسحب للتدوير. انقر على العلامة.',
    matchableNote: 'لا توجد شركة موثّقة بعد، لذا لا يمكن لأي منها تلقي طلب.',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

// Geographic position → a point on the sphere. Reference geography, not business data.
const toVec = (lat: number, lng: number, r = 2): [number, number, number] => {
  const phi = (90 - lat) * (Math.PI / 180);
  const theta = (lng + 180) * (Math.PI / 180);
  return [-r * Math.sin(phi) * Math.cos(theta), r * Math.cos(phi), r * Math.sin(phi) * Math.sin(theta)];
};

function Globe({ markers, lang, onPick, picked }: {
  markers: Marker[]; lang: Lang; onPick: (m: Marker | null) => void; picked: Marker | null;
}) {
  const g = React.useRef<Group>(null);
  useFrame((_, d) => { if (g.current && !picked) g.current.rotation.y += d * 0.09; });
  const max = Math.max(1, ...markers.map((m) => m.count));
  return (
    <group ref={g}>
      <Sphere args={[2, 48, 48]}>
        <meshStandardMaterial color="#0b2033" roughness={0.85} metalness={0.15} wireframe={false} />
      </Sphere>
      <Sphere args={[2.01, 24, 24]}>
        <meshBasicMaterial color="#1e6fa8" wireframe transparent opacity={0.22} />
      </Sphere>
      {markers.map((m) => {
        const p = toVec(m.lat, m.lng, 2.03);
        // Height encodes DENSITY, so an emirate with 8,000 companies reads differently from one
        // with 40. sqrt keeps the tallest from dwarfing everything else.
        const h = 0.12 + Math.sqrt(m.count / max) * 0.6;
        const tip = toVec(m.lat, m.lng, 2.03 + h);
        return (
          <group key={m.name}>
            <mesh
              position={tip}
              onClick={(e) => { e.stopPropagation(); onPick(m); }}
              onPointerOver={() => { document.body.style.cursor = 'pointer'; }}
              onPointerOut={() => { document.body.style.cursor = 'auto'; }}
            >
              <sphereGeometry args={[0.075, 16, 16]} />
              <meshStandardMaterial
                color={picked?.name === m.name ? '#fbbf24' : '#34d399'}
                emissive={picked?.name === m.name ? '#fbbf24' : '#34d399'}
                emissiveIntensity={0.75}
              />
            </mesh>
            <line>
              <bufferGeometry>
                <bufferAttribute attach="attributes-position" args={[new Float32Array([...p, ...tip]), 3]} />
              </bufferGeometry>
              <lineBasicMaterial color="#34d399" transparent opacity={0.55} />
            </line>
            {picked?.name === m.name && (
              <Html position={tip} distanceFactor={8}>
                <div className="w-52 rounded-xl border border-white/15 bg-[#0b1220]/95 backdrop-blur-xl p-3 shadow-xl">
                  <div className="text-[12.5px] font-medium mb-1.5">{m.name}</div>
                  <div className="flex justify-between text-[11px]">
                    <span className="opacity-60">{t(lang, 'known')}</span>
                    <span className="tabular-nums">{m.count.toLocaleString()}</span>
                  </div>
                  <div className="flex justify-between text-[11px]">
                    <span className="opacity-60">{t(lang, 'matchable')}</span>
                    <span className="tabular-nums">{m.matchable.toLocaleString()}</span>
                  </div>
                  {m.matchable === 0 && (
                    <p className="text-[10px] opacity-50 mt-1.5 leading-snug">{t(lang, 'matchableNote')}</p>
                  )}
                </div>
              </Html>
            )}
          </group>
        );
      })}
    </group>
  );
}

export default function SupplierNetworkMap({ token, lang = 'en' }: { token?: string | null; lang?: Lang }) {
  const [d, setD] = useState<MapData | null>(null);
  const [err, setErr] = useState('');
  const [picked, setPicked] = useState<Marker | null>(null);
  const [on, setOn] = useState<Record<LayerKey, boolean>>({
    suppliers: true, demand: false, projects: false, shipments: false,
  });

  useEffect(() => {
    let live = true;
    call('supplier_portal', { action: 'network_map' }, token).then((j) => {
      if (!live) return;
      if (j && j.ok) setD(j);
      else setErr((j && (j.error || j.hint)) || 'load_err');
    });
    return () => { live = false; };
  }, [token]);

  const markers = useMemo(
    () => (on.suppliers ? (d?.suppliers?.markers || []).filter((m) => m.count > 0) : []),
    [d, on.suppliers],
  );

  if (err) return <div className="text-xs opacity-60 p-4">{err}</div>;
  if (!d) return <div className="text-xs opacity-60 p-4">{t(lang, 'loading')}</div>;

  const LAYERS: { key: LayerKey; label: string; layer?: Layer }[] = [
    { key: 'suppliers', label: t(lang, 'suppliers'), layer: d.suppliers },
    { key: 'demand', label: t(lang, 'demand'), layer: d.demand },
    { key: 'projects', label: t(lang, 'projects'), layer: d.projects },
    { key: 'shipments', label: t(lang, 'shipments'), layer: d.shipments },
  ];

  return (
    <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
      <div className="flex justify-between items-baseline mb-2">
        <h3 className="text-xs uppercase tracking-wide opacity-60">{t(lang, 'title')}</h3>
        <span className="text-[10px] opacity-40">{t(lang, 'hint')}</span>
      </div>

      {/* Layer toggles. An empty layer is DISABLED and carries its reason — it is not silently
          absent, and it cannot be switched on to reveal dots that do not exist. */}
      <div className="flex flex-wrap gap-2 mb-3">
        {LAYERS.map(({ key, label, layer }) => {
          const empty = !layer || !(layer.count ?? 0);
          return (
            <button
              key={key}
              type="button"
              disabled={empty}
              title={empty ? (layer?.note || t(lang, 'noData')) : layer?.basis}
              onClick={() => setOn((s) => ({ ...s, [key]: !s[key] }))}
              className={`rounded-full border px-2.5 py-1 text-[11px] transition-colors ${
                empty
                  ? 'border-white/10 opacity-35 cursor-not-allowed'
                  : on[key]
                    ? 'border-emerald-400/50 bg-emerald-400/15 text-emerald-200'
                    : 'border-white/20 hover:bg-white/10'
              }`}
            >
              {label} · {(layer?.count ?? 0).toLocaleString()}
              {empty && <span className="opacity-60"> — {t(lang, 'noData')}</span>}
            </button>
          );
        })}
      </div>

      <div className="h-[400px] w-full rounded-xl overflow-hidden bg-[#050912]">
        <Canvas camera={{ position: [0, 1.6, 6.2], fov: 45 }} dpr={[1, 2]} onPointerMissed={() => setPicked(null)}>
          <Suspense fallback={null}>
            <ambientLight intensity={0.6} />
            <directionalLight position={[5, 4, 5]} intensity={1.05} />
            <pointLight position={[-5, -2, -3]} intensity={0.45} color="#38bdf8" />
            <Globe markers={markers} lang={lang} onPick={setPicked} picked={picked} />
            <OrbitControls enablePan={false} minDistance={3.6} maxDistance={11} />
          </Suspense>
        </Canvas>
      </div>

      <div className="flex justify-between text-[10px] opacity-50 mt-2">
        <span>
          {(d.totals?.placed ?? 0).toLocaleString()} {t(lang, 'placed')}
          {(d.suppliers?.unplaced ?? 0) > 0 &&
            ` · ${(d.suppliers?.unplaced ?? 0).toLocaleString()} ${t(lang, 'unplaced')}`}
        </span>
        <span>
          {(d.totals?.matchable ?? 0).toLocaleString()} {t(lang, 'matchable')}
        </span>
      </div>
    </section>
  );
}
