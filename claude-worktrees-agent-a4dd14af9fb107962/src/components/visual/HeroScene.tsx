'use client';
// Hero scene, Sealed: five sealed quote slabs float in depth under one teal key light, drifting
// and turning toward the pointer. They settle into one levelled row, two dim and fall back, and the
// chosen slab lifts forward, takes a gold rim light, and its redaction bar slides off in gold.
// Procedural geometry only (no drei, no textures, no fonts): the chunk is three + r3f. Mounted
// behind the headline by the page, so LCP stays the server-rendered <h1>, never the canvas.
import { useEffect, useRef, useState } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { AdditiveBlending, BoxGeometry, CircleGeometry, Color, EdgesGeometry, Fog, PlaneGeometry } from 'three';
import type { Group, LineBasicMaterial, Mesh, MeshBasicMaterial, MeshStandardMaterial, PointLight } from 'three';
import { canRun3D, useSceneGate, type SceneProps } from './gate';
import { HeroPoster } from './posters';

const N = 5;
const CYCLE = 10; // s: drift → level → choose + unseal → hold → release
const W = 1.25;
const H = 1.7;
const TEAL = new Color('#6EE7D4');
const GOLD = new Color('#F6DD8C');
const SLAB = new Color('#0F2231');
const SLAB_GOLD = new Color('#2A2A1C');
const slabGeo = new BoxGeometry(W, H, 0.05);
const edgeGeo = new EdgesGeometry(slabGeo);
const barGeo = new PlaneGeometry(0.66, 0.12);
const lineGeo = new PlaneGeometry(1, 0.026);
const glowGeo = new CircleGeometry(1, 48);
const LINES: [number, number][] = [[0.3, 0.92], [0.17, 0.7], [0.04, 0.84], [-0.09, 0.6], [-0.22, 0.78]];

const smooth = (x: number) => { const c = Math.min(1, Math.max(0, x)); return c * c * (3 - 2 * c); };
const lerp = (a: number, b: number, k: number) => a + (b - a) * k;

/** Shared per-frame timeline so every slab (and the gold light) agree on which one is chosen. */
function phase(t: number) {
  const p = (t % CYCLE) / CYCLE;
  const chosen = Math.floor(t / CYCLE) % N;
  const level = smooth((p - 0.22) / 0.14) * (1 - smooth((p - 0.9) / 0.1));
  const reveal = smooth((p - 0.46) / 0.1) * (1 - smooth((p - 0.86) / 0.08));
  return { level, reveal, chosen };
}

function Slab({ i }: { i: number }) {
  const g = useRef<Group>(null!);
  const bar = useRef<Mesh>(null!);
  const barMat = useRef<MeshBasicMaterial>(null!);
  const nameMat = useRef<MeshBasicMaterial>(null!);
  const body = useRef<MeshStandardMaterial>(null!);
  const edge = useRef<LineBasicMaterial>(null!);
  const priceMat = useRef<MeshBasicMaterial>(null!);

  useFrame(({ clock, pointer }) => {
    const t = clock.elapsedTime;
    const { level, reveal: r, chosen } = phase(t);
    const me = chosen === i;
    const reveal = me ? r : 0;
    const dim = me ? 0 : r; // the others fall back while one is opened
    const a = t * 0.18 + (i / N) * Math.PI * 2;
    const rowX = (i - (N - 1) / 2) * 1.42;
    const floatY = Math.sin(t * 0.9 + i * 1.3) * 0.06;

    g.current.position.set(
      lerp(Math.cos(a) * 2.9, rowX, level),
      lerp(Math.sin(a * 1.6 + i) * 0.5, 0, level) + floatY + reveal * 0.18,
      lerp(Math.sin(a) * 1.8 - 0.8, 0, level) + reveal * 1.2 - dim * 0.9,
    );
    // turn toward the pointer; the opened slab faces the viewer squarely
    g.current.rotation.y = lerp(lerp(-Math.cos(a) * 0.5, 0, level) + pointer.x * 0.18, 0, reveal);
    g.current.rotation.x = lerp(-pointer.y * 0.12 + Math.sin(t * 0.7 + i) * 0.04, 0, reveal);
    g.current.scale.setScalar(1 + reveal * 0.08 - dim * 0.06);

    bar.current.position.x = -0.2 + reveal * 1.2;
    barMat.current.opacity = 1 - reveal;
    nameMat.current.opacity = reveal;
    priceMat.current.color.copy(TEAL).lerp(GOLD, reveal);
    priceMat.current.opacity = 0.55 + reveal * 0.45 - dim * 0.3;
    body.current.color.copy(SLAB).lerp(SLAB_GOLD, reveal * 0.6);
    body.current.opacity = 0.78 - dim * 0.35;
    body.current.emissiveIntensity = 0.25 + reveal * 0.5;
    edge.current.color.copy(TEAL).lerp(GOLD, reveal);
    edge.current.opacity = (0.35 + reveal * 0.65) * (1 - dim * 0.6);
  });

  return (
    <group ref={g}>
      <mesh geometry={slabGeo}>
        <meshStandardMaterial ref={body} color="#0F2231" emissive="#0B8276" emissiveIntensity={0.25} transparent opacity={0.78} roughness={0.3} metalness={0.45} />
      </mesh>
      <lineSegments geometry={edgeGeo}>
        <lineBasicMaterial ref={edge} transparent />
      </lineSegments>
      {/* the supplier's name, only ever seen once the bar has slid off */}
      <mesh geometry={barGeo} position={[-0.25, 0.62, 0.028]} scale={[0.82, 1, 1]}>
        <meshBasicMaterial ref={nameMat} color="#F6DD8C" transparent opacity={0} />
      </mesh>
      <mesh ref={bar} geometry={barGeo} position={[-0.2, 0.62, 0.031]}>
        <meshBasicMaterial ref={barMat} color="#1B3445" transparent />
      </mesh>
      {LINES.map(([y, w]) => (
        <mesh key={y} geometry={lineGeo} position={[-W / 2 + 0.12 + w / 2, y, 0.028]} scale={[w, 1, 1]}>
          <meshBasicMaterial color="#6EE7D4" transparent opacity={0.2} />
        </mesh>
      ))}
      {/* the price line */}
      <mesh geometry={lineGeo} position={[-W / 2 + 0.12 + 0.24, -0.6, 0.028]} scale={[0.48, 2.8, 1]}>
        <meshBasicMaterial ref={priceMat} color="#6EE7D4" transparent opacity={0.55} />
      </mesh>
    </group>
  );
}

/** A gold rim light that travels to the chosen slab while it is unsealed. */
function RevealLight() {
  const l = useRef<PointLight>(null!);
  const halo = useRef<Mesh>(null!);
  const haloMat = useRef<MeshBasicMaterial>(null!);
  useFrame(({ clock }) => {
    const { level, reveal, chosen } = phase(clock.elapsedTime);
    const x = (chosen - (N - 1) / 2) * 1.42 * level;
    l.current.position.set(x, 0.9, 2.2);
    l.current.intensity = reveal * 14;
    halo.current.position.set(x, 0.1, 0.4);
    haloMat.current.opacity = reveal * 0.22;
  });
  return (
    <>
      <pointLight ref={l} color="#F6DD8C" distance={6} decay={1.6} intensity={0} />
      <mesh ref={halo} geometry={glowGeo} scale={[1.6, 1.9, 1]}>
        <meshBasicMaterial ref={haloMat} color="#E3C065" transparent opacity={0} blending={AdditiveBlending} depthWrite={false} />
      </mesh>
    </>
  );
}

/** Pointer parallax, lerped; pulls the camera back on portrait screens so the row still fits. */
function Rig() {
  useFrame(({ camera, pointer, size }) => {
    const z = Math.max(7.2, 11 / (size.width / size.height));
    camera.position.x += (pointer.x * 0.8 - camera.position.x) * 0.035;
    camera.position.y += (0.4 + pointer.y * 0.4 - camera.position.y) * 0.035;
    camera.position.z += (z - camera.position.z) * 0.1;
    camera.lookAt(0, 0, 0);
  });
  return null;
}

const ALT = {
  en: 'Illustration: sealed quote panels float and line up side by side; the one the customer chooses lights gold and its hidden supplier name is revealed.',
  ar: 'رسم توضيحي: عروض أسعار مختومة تطفو ثم تصطف جنبًا إلى جنب، ويضيء العرض الذي يختاره العميل بالذهبي ويُكشف اسم المورّد المخفي.',
};

export default function HeroScene({ locale }: SceneProps) {
  const ref = useRef<HTMLDivElement>(null);
  const { mounted, active } = useSceneGate(ref);
  const [capable, setCapable] = useState(false);
  const [ready, setReady] = useState(false);
  useEffect(() => setCapable(canRun3D()), []);

  return (
    <div ref={ref} className="relative h-full w-full">
      {/* the key light and the reveal glow, painted in CSS so they exist before (and without) WebGL */}
      <div aria-hidden className="absolute inset-0 bg-[radial-gradient(46%_42%_at_50%_8%,rgba(110,231,212,.16),transparent_70%),radial-gradient(40%_36%_at_60%_78%,rgba(227,192,101,.10),transparent_70%)]" />
      <div aria-hidden className={`absolute inset-0 transition-opacity duration-700 ${ready ? 'opacity-0' : 'opacity-100'}`}>
        <HeroPoster />
      </div>
      {mounted && capable && (
        <div aria-hidden className={`absolute inset-0 transition-opacity duration-1000 ${ready ? 'opacity-100' : 'opacity-0'}`}>
          <Canvas
            dpr={[1, 1.75]}
            frameloop={active ? 'always' : 'never'}
            camera={{ position: [0, 0.4, 7.2], fov: 36 }}
            gl={{ antialias: true, alpha: true, powerPreference: 'low-power' }}
            onCreated={({ scene }) => { scene.fog = new Fog('#050C12', 6.5, 13); setReady(true); }}
          >
            <ambientLight intensity={0.35} />
            {/* the one teal key light, from above */}
            <spotLight position={[0, 6, 4]} angle={0.5} penumbra={0.9} color="#6EE7D4" intensity={60} distance={16} />
            <pointLight position={[-4, 1.5, 3]} color="#14B8A6" intensity={8} />
            <directionalLight position={[3, -2, 4]} color="#A7B9BB" intensity={0.3} />
            {/* RTL: mirror the row so the choice reads from the reader's start side */}
            <group scale={[locale === 'ar' ? -1 : 1, 1, 1]}>
              {Array.from({ length: N }, (_, i) => <Slab key={i} i={i} />)}
              <RevealLight />
            </group>
            <Rig />
          </Canvas>
        </div>
      )}
      <span className="sr-only">{ALT[locale]}</span>
    </div>
  );
}
