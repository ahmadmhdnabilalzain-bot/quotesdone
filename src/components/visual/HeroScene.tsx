'use client';
// Hero backdrop: anonymous quote panels orbit in depth, level into one row, and one is chosen —
// its edge turns gold and its redaction bar slides off. Pure procedural geometry, no drei, no
// textures, no fonts: the chunk is three + r3f and nothing else.
import { useEffect, useRef, useState } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { BoxGeometry, Color, EdgesGeometry, PlaneGeometry } from 'three';
import type { Group, LineBasicMaterial, Mesh, MeshBasicMaterial } from 'three';
import { canRun3D, useSceneGate, type SceneProps } from './gate';
import { HeroPoster } from './posters';

const N = 5;
const CYCLE = 9; // seconds: orbit → level → choose + reveal → release
const W = 1.2;
const H = 1.6;
const TEAL = new Color('#6EE7D4');
const GOLD = new Color('#E3C065');
const cardGeo = new BoxGeometry(W, H, 0.035);
const edgeGeo = new EdgesGeometry(cardGeo);
const barGeo = new PlaneGeometry(0.62, 0.13);
const lineGeo = new PlaneGeometry(1, 0.028);
const LINES: [number, number][] = [[0.28, 0.9], [0.14, 0.72], [0, 0.84], [-0.14, 0.58], [-0.28, 0.78]];

const smooth = (x: number) => {
  const c = Math.min(1, Math.max(0, x));
  return c * c * (3 - 2 * c);
};
const lerp = (a: number, b: number, k: number) => a + (b - a) * k;

function Card({ i }: { i: number }) {
  const g = useRef<Group>(null!);
  const bar = useRef<Mesh>(null!);
  const barMat = useRef<MeshBasicMaterial>(null!);
  const nameMat = useRef<MeshBasicMaterial>(null!);
  const edge = useRef<LineBasicMaterial>(null!);

  useFrame(({ clock }) => {
    const t = clock.elapsedTime;
    const p = (t % CYCLE) / CYCLE;
    const level = smooth((p - 0.28) / 0.14) * (1 - smooth((p - 0.9) / 0.1));
    const reveal = Math.floor(t / CYCLE) % N === i ? smooth((p - 0.48) / 0.12) * (1 - smooth((p - 0.86) / 0.08)) : 0;
    const a = t * 0.22 + (i / N) * Math.PI * 2;
    const rowX = (i - (N - 1) / 2) * 1.36;

    g.current.position.set(
      lerp(Math.cos(a) * 2.7, rowX, level),
      lerp(Math.sin(a * 2 + i) * 0.22, 0, level) + reveal * 0.12,
      lerp(Math.sin(a) * 1.5 - 0.6, 0, level) + reveal,
    );
    g.current.rotation.y = lerp(-Math.cos(a) * 0.35, 0, level);
    g.current.scale.setScalar(1 + reveal * 0.06);
    bar.current.position.x = -0.19 + reveal * 1.1;
    barMat.current.opacity = 1 - reveal;
    nameMat.current.opacity = reveal;
    edge.current.color.copy(TEAL).lerp(GOLD, reveal);
    edge.current.opacity = 0.4 + reveal * 0.6;
  });

  return (
    <group ref={g}>
      <mesh geometry={cardGeo}>
        <meshStandardMaterial color="#0C2330" transparent opacity={0.66} roughness={0.35} metalness={0.25} />
      </mesh>
      <lineSegments geometry={edgeGeo}>
        <lineBasicMaterial ref={edge} transparent />
      </lineSegments>
      {/* the supplier's name, only ever seen once the bar has slid off */}
      <mesh geometry={barGeo} position={[-0.25, 0.58, 0.019]} scale={[0.8, 1, 1]}>
        <meshBasicMaterial ref={nameMat} color="#E3C065" transparent opacity={0} />
      </mesh>
      <mesh ref={bar} geometry={barGeo} position={[-0.19, 0.58, 0.022]}>
        <meshBasicMaterial ref={barMat} color="#14303E" transparent />
      </mesh>
      {LINES.map(([y, w]) => (
        <mesh key={y} geometry={lineGeo} position={[-W / 2 + 0.1 + w / 2, y, 0.02]} scale={[w, 1, 1]}>
          <meshBasicMaterial color="#6EE7D4" transparent opacity={0.22} />
        </mesh>
      ))}
      <mesh geometry={lineGeo} position={[-W / 2 + 0.1 + 0.22, -0.6, 0.02]} scale={[0.44, 2.4, 1]}>
        <meshBasicMaterial color="#6EE7D4" transparent opacity={0.5} />
      </mesh>
    </group>
  );
}

/** Pointer parallax, lerped; pulls the camera back on portrait screens so the row still fits. */
function Rig() {
  useFrame(({ camera, pointer, size }) => {
    const z = Math.max(6.8, 10.5 / (size.width / size.height));
    camera.position.x += (pointer.x * 0.7 - camera.position.x) * 0.04;
    camera.position.y += (0.35 + pointer.y * 0.35 - camera.position.y) * 0.04;
    camera.position.z += (z - camera.position.z) * 0.1;
    camera.lookAt(0, 0, 0);
  });
  return null;
}

const ALT = {
  en: 'Illustration: anonymous quote panels line up side by side; the one the customer chooses turns gold and its hidden supplier name is revealed.',
  ar: 'رسم توضيحي: عروض أسعار مجهولة الهوية تصطف جنبًا إلى جنب، ويتحوّل العرض الذي يختاره العميل إلى اللون الذهبي ويُكشف اسم المورّد.',
};

export default function HeroScene({ locale }: SceneProps) {
  const ref = useRef<HTMLDivElement>(null);
  const { mounted, active } = useSceneGate(ref);
  const [capable, setCapable] = useState(false);
  const [ready, setReady] = useState(false);
  useEffect(() => setCapable(canRun3D()), []);

  return (
    <div ref={ref} className="relative h-full w-full">
      <div aria-hidden className="absolute inset-0 bg-[radial-gradient(60%_50%_at_72%_88%,rgba(227,192,101,.14),transparent_70%),radial-gradient(70%_60%_at_28%_18%,rgba(20,184,166,.12),transparent_70%)]" />
      <div aria-hidden className={`absolute inset-0 transition-opacity duration-700 ${ready ? 'opacity-0' : 'opacity-100'}`}>
        <HeroPoster />
      </div>
      {mounted && capable && (
        <div aria-hidden className={`absolute inset-0 transition-opacity duration-700 ${ready ? 'opacity-100' : 'opacity-0'}`}>
          <Canvas
            dpr={[1, 1.75]}
            frameloop={active ? 'always' : 'never'}
            camera={{ position: [0, 0.35, 6.8], fov: 38 }}
            gl={{ antialias: true, alpha: true, powerPreference: 'low-power' }}
            onCreated={() => setReady(true)}
          >
            <ambientLight intensity={0.55} />
            <directionalLight position={[3, -1, 4]} color="#F6DD8C" intensity={1.1} />
            <pointLight position={[-3, 2, 3]} color="#14B8A6" intensity={9} />
            {/* RTL: mirror the row so the choice reads from the reader's start side */}
            <group scale={[locale === 'ar' ? -1 : 1, 1, 1]}>
              {Array.from({ length: N }, (_, i) => (
                <Card key={i} i={i} />
              ))}
            </group>
            <Rig />
          </Canvas>
        </div>
      )}
      <span className="sr-only">{ALT[locale]}</span>
    </div>
  );
}
