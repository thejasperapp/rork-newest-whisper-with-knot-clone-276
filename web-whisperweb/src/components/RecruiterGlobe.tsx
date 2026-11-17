import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { Html, Billboard } from "@react-three/drei";
import * as THREE from "three";
import { X, MessageCircle, UserPlus, UserCheck } from "lucide-react";
import { toast } from "sonner";

import { Avatar } from "@/components/Avatar";
import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";
import { useNavigate } from "react-router-dom";
import { supabase } from "@/lib/supabase";
import type { Territory, TerritoryRegion, Prospect } from "@/lib/recruiter";
import { TERRITORY_REGION_COLORS } from "@/lib/recruiter";
import type { WhisperProfile } from "@/lib/types";

const REGION_COORDS: Record<TerritoryRegion, { lat: number; lon: number }> = {
  northeast: { lat: 42.36, lon: -71.06 },
  southeast: { lat: 33.75, lon: -84.39 },
  midwest: { lat: 41.88, lon: -87.63 },
  southwest: { lat: 32.78, lon: -96.8 },
  west: { lat: 34.05, lon: -118.24 },
  northwest: { lat: 47.61, lon: -122.33 },
  international: { lat: 51.51, lon: -0.13 },
  other: { lat: 39.83, lon: -98.58 },
};

function latLonToVector3(lat: number, lon: number, radius: number) {
  const phi = (90 - lat) * (Math.PI / 180);
  const theta = (lon + 180) * (Math.PI / 180);
  const x = -(radius * Math.sin(phi) * Math.cos(theta));
  const z = radius * Math.sin(phi) * Math.sin(theta);
  const y = radius * Math.cos(phi);
  return new THREE.Vector3(x, y, z);
}

const EARTH_TEXTURE_URL =
  "https://unpkg.com/three-globe@2.24.13/example/img/earth-blue-marble.jpg";
const EARTH_BUMP_URL =
  "https://unpkg.com/three-globe@2.24.13/example/img/earth-topology.png";

function GlobeSphere({
  onDragState,
}: {
  onDragState: (dragging: boolean) => void;
}) {
  const meshRef = useRef<THREE.Mesh>(null);
  const groupRef = useRef<THREE.Group>(null);
  const { gl } = useThree();
  const isDragging = useRef(false);
  const lastX = useRef(0);
  const velocity = useRef(0);
  const autoSpin = useRef(true);

  const [textureLoaded, setTextureLoaded] = useState(false);

  const { texture, bumpMap } = useMemo(() => {
    const loader = new THREE.TextureLoader();
    const tex = loader.load(
      EARTH_TEXTURE_URL,
      () => setTextureLoaded(true),
      undefined,
      () => setTextureLoaded(false)
    );
    const bump = loader.load(EARTH_BUMP_URL, undefined, undefined, () => {});
    return { texture: tex, bumpMap: bump };
  }, []);

  useFrame((_, delta) => {
    if (!groupRef.current) return;

    if (!isDragging.current) {
      if (autoSpin.current && Math.abs(velocity.current) < 0.001) {
        groupRef.current.rotation.y += 0.0008;
      } else {
        // Inertial damping
        velocity.current *= 0.95;
        groupRef.current.rotation.y += velocity.current * delta * 60;
        if (Math.abs(velocity.current) < 0.0005) {
          velocity.current = 0;
          autoSpin.current = true;
        }
      }
    }
  });

  const onPointerDown = useCallback((e: THREE.Event) => {
    (e as unknown as PointerEvent).stopPropagation?.();
    isDragging.current = true;
    autoSpin.current = false;
    velocity.current = 0;
    lastX.current = (e as unknown as PointerEvent).clientX;
    onDragState(true);
    gl.domElement.setPointerCapture?.(
      (e as unknown as PointerEvent).pointerId
    );
  }, [gl.domElement, onDragState]);

  const onPointerMove = useCallback(
    (e: THREE.Event) => {
      if (!isDragging.current || !groupRef.current) return;
      const x = (e as unknown as PointerEvent).clientX;
      const dx = x - lastX.current;
      lastX.current = x;
      groupRef.current.rotation.y += dx * 0.005;
      velocity.current = dx * 0.005;
    },
    []
  );

  const onPointerUp = useCallback(
    (e: THREE.Event) => {
      isDragging.current = false;
      onDragState(false);
      gl.domElement.releasePointerCapture?.(
        (e as unknown as PointerEvent).pointerId
      );
    },
    [gl.domElement, onDragState]
  );

  return (
    <group ref={groupRef}>
      <mesh
        ref={meshRef}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerLeave={onPointerUp}
      >
        <sphereGeometry args={[2, 96, 96]} />
        <meshStandardMaterial
          map={texture}
          bumpMap={bumpMap}
          bumpScale={0.015}
          color={textureLoaded ? 0xffffff : 0x0a1628}
          emissive={textureLoaded ? 0x000000 : 0x050a14}
          roughness={0.55}
          metalness={0.05}
        />
      </mesh>
    </group>
  );
}

function Atmosphere() {
  return (
    <mesh scale={[1.12, 1.12, 1.12]}>
      <sphereGeometry args={[2, 64, 64]} />
      <meshBasicMaterial
        color={0x4aa3ff}
        transparent
        opacity={0.1}
        side={THREE.BackSide}
      />
    </mesh>
  );
}

function TerritoryPin({
  region,
  name,
  color,
  photoUrl,
  count,
  onClick,
  highlighted,
}: {
  region: TerritoryRegion;
  name: string;
  color: string;
  photoUrl?: string | null;
  count: number;
  onClick: () => void;
  highlighted: boolean;
}) {
  const { lat, lon } = REGION_COORDS[region] ?? REGION_COORDS.other;
  const position = useMemo(() => latLonToVector3(lat, lon, 2.05), [lat, lon]);
  const ringRef = useRef<THREE.Mesh>(null);

  useFrame(({ clock }) => {
    if (ringRef.current) {
      const scale = 1 + Math.sin(clock.getElapsedTime() * 2.5) * 0.08;
      ringRef.current.scale.setScalar(scale);
    }
  });

  return (
    <group position={position}>
      {/* Pulsing ring on the globe surface */}
      <mesh ref={ringRef}>
        <ringGeometry args={[0.18, 0.22, 32]} />
        <meshBasicMaterial
          color={color}
          transparent
          opacity={0.7}
          side={THREE.DoubleSide}
        />
      </mesh>

      <Billboard>
        <Html center distanceFactor={4}>
          <button
            onClick={onClick}
            className="group relative flex flex-col items-center transition-transform active:scale-95"
            style={{ cursor: "pointer" }}
          >
            <span
              className="h-10 w-10 overflow-hidden rounded-full border-[3px] bg-cover bg-center shadow-lg"
              style={{
                borderColor: color,
                backgroundImage: photoUrl ? `url(${photoUrl})` : undefined,
              }}
            >
              {!photoUrl && (
                <span className="flex h-full w-full items-center justify-center bg-muted text-[10px] font-bold">
                  {name.slice(0, 2).toUpperCase()}
                </span>
              )}
            </span>
            {count > 0 && (
              <span className="absolute -bottom-2 rounded-full bg-background px-1.5 py-0.5 text-[9px] font-bold shadow">
                {count}
              </span>
            )}
            {highlighted && (
              <span className="absolute -inset-1 animate-ping rounded-full border border-white/30" />
            )}
          </button>
        </Html>
      </Billboard>
    </group>
  );
}

interface RegionGroup {
  region: TerritoryRegion;
  territories: Territory[];
  color: string;
  name: string;
  recruiterId: string;
}

interface RecruiterGlobeProps {
  territories: Territory[];
  prospects?: Prospect[];
  recruiterPhotoUrl?: string | null;
  onSelectTerritory?: (t: Territory) => void;
  highlightedRegion?: TerritoryRegion | null;
}

function RecruiterGlobeBase({
  territories,
  prospects = [],
  recruiterPhotoUrl,
  highlightedRegion,
}: RecruiterGlobeProps) {
  const { user, profile } = useAuth();
  const navigate = useNavigate();
  const [isDragging, setIsDragging] = useState(false);
  const [selectedRegion, setSelectedRegion] = useState<TerritoryRegion | null>(
    null
  );
  const [selectedProfile, setSelectedProfile] = useState<WhisperProfile | null>(
    null
  );
  const [isLoadingProfile, setIsLoadingProfile] = useState(false);

  const groups = useMemo(() => {
    const map = new Map<TerritoryRegion, Territory[]>();
    for (const t of territories) {
      const list = map.get(t.region) ?? [];
      list.push(t);
      map.set(t.region, list);
    }
    return Array.from(map.entries()).map<RegionGroup>(([region, list]) => ({
      region,
      territories: list,
      color: list[0]?.color ?? TERRITORY_REGION_COLORS[region],
      name: list[0]?.name ?? region,
      recruiterId: list[0]?.recruiter_id ?? "",
    }));
  }, [territories]);

  const prospectCountForRegion = (region: TerritoryRegion) => {
    const ids = new Set(
      (groups.find((g) => g.region === region)?.territories ?? []).map(
        (t) => t.id
      )
    );
    return prospects.filter((p) => {
      const territoryId = (p as unknown as { territory_id?: string | null })
        .territory_id;
      return territoryId && ids.has(territoryId);
    }).length;
  };

  const handlePinClick = async (group: RegionGroup) => {
    setSelectedRegion(group.region);
    setIsLoadingProfile(true);
    if (group.recruiterId) {
      const { data } = await supabase
        .from("whisper_profiles")
        .select("*")
        .eq("user_id", group.recruiterId)
        .maybeSingle();
      setSelectedProfile((data as WhisperProfile | null) ?? null);
    }
    setIsLoadingProfile(false);
  };

  const selectedGroup = groups.find((g) => g.region === selectedRegion);
  const isMe = selectedProfile?.user_id === user?.id;

  const closeModal = () => {
    setSelectedRegion(null);
    setSelectedProfile(null);
  };

  return (
    <div className="relative aspect-square w-full overflow-hidden rounded-2xl border border-border/50 bg-black">
      <Canvas camera={{ position: [0, 0, 6.2], fov: 45 }}>
        <ambientLight intensity={0.4} />
        <directionalLight position={[5, 3, 5]} intensity={1.4} />
        <pointLight position={[-5, -2, -5]} intensity={0.3} color="#3b82f6" />
        <GlobeSphere onDragState={setIsDragging} />
        <Atmosphere />
        {groups.map((group) => (
          <TerritoryPin
            key={group.region}
            region={group.region}
            name={group.name}
            color={group.color}
            photoUrl={recruiterPhotoUrl}
            count={prospectCountForRegion(group.region)}
            highlighted={highlightedRegion === group.region}
            onClick={() => handlePinClick(group)}
          />
        ))}
      </Canvas>

      {/* Drag hint */}
      {!isDragging && (
        <div className="pointer-events-none absolute bottom-3 left-1/2 -translate-x-1/2 rounded-full bg-black/50 px-3 py-1 text-[11px] font-medium text-white backdrop-blur-sm">
          Drag to rotate
        </div>
      )}

      {/* Pin detail modal */}
      {selectedGroup && (
        <div className="absolute inset-0 z-10 flex items-center justify-center bg-black/50 p-4 backdrop-blur-sm">
          <div className="w-full max-w-xs rounded-2xl border border-border/50 bg-background p-5 shadow-2xl">
            <div className="mb-4 flex items-center justify-between">
              <h3 className="font-display text-lg font-bold">
                {selectedGroup.name}
              </h3>
              <button
                onClick={closeModal}
                className="flex h-8 w-8 items-center justify-center rounded-full bg-secondary transition-colors hover:bg-secondary/80"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            {isLoadingProfile ? (
              <div className="flex items-center justify-center py-6">
                <div className="h-6 w-6 animate-spin rounded-full border-2 border-foreground border-t-transparent" />
              </div>
            ) : (
              <div className="flex flex-col items-center gap-3 text-center">
                <div
                  className="rounded-full p-1"
                  style={{ backgroundColor: selectedGroup.color }}
                >
                  <Avatar
                    url={recruiterPhotoUrl}
                    name={selectedGroup.name}
                    size={72}
                    className="rounded-full bg-background"
                  />
                </div>
                <div>
                  <p className="text-[15px] font-bold">
                    {selectedProfile?.display_name || selectedGroup.name}
                  </p>
                  <p className="text-[13px] text-muted-foreground">
                    {selectedProfile?.username
                      ? `@${selectedProfile.username}`
                      : "Recruiting group"}
                  </p>
                </div>

                <div className="grid w-full grid-cols-2 gap-3">
                  <div className="rounded-xl bg-secondary p-2">
                    <p className="text-lg font-bold">
                      {selectedGroup.territories.length}
                    </p>
                    <p className="text-[11px] text-muted-foreground">
                      Territories
                    </p>
                  </div>
                  <div className="rounded-xl bg-secondary p-2">
                    <p className="text-lg font-bold">
                      {prospectCountForRegion(selectedGroup.region)}
                    </p>
                    <p className="text-[11px] text-muted-foreground">
                      Prospects
                    </p>
                  </div>
                </div>

                <div className="flex w-full gap-2">
                  {isMe ? (
                    <button
                      onClick={() => {
                        closeModal();
                        navigate("/profile");
                      }}
                      className="flex flex-1 items-center justify-center gap-1.5 rounded-full bg-secondary py-2.5 text-[13px] font-bold transition-colors hover:bg-secondary/80"
                    >
                      <UserCheck className="h-4 w-4" />
                      Your profile
                    </button>
                  ) : (
                    <button
                      onClick={() => {
                        closeModal();
                        if (selectedProfile?.username) {
                          navigate(`/u/${selectedProfile.username}`);
                        } else {
                          toast("No profile link available");
                        }
                      }}
                      className="flex flex-1 items-center justify-center gap-1.5 rounded-full bg-secondary py-2.5 text-[13px] font-bold transition-colors hover:bg-secondary/80"
                    >
                      <UserPlus className="h-4 w-4" />
                      Follow
                    </button>
                  )}
                  <button
                    onClick={() => {
                      closeModal();
                      if (selectedProfile?.username) {
                        navigate(
                          `/messages?to=${selectedProfile.user_id}&u=${encodeURIComponent(
                            selectedProfile.username
                          )}`
                        );
                      } else {
                        toast("No profile link available");
                      }
                    }}
                    className="flex flex-1 items-center justify-center gap-1.5 rounded-full bg-foreground py-2.5 text-[13px] font-bold text-background transition-colors hover:bg-foreground/90"
                  >
                    <MessageCircle className="h-4 w-4" />
                    Message
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

export const RecruiterGlobe = memo(RecruiterGlobeBase);
export { REGION_COORDS };
