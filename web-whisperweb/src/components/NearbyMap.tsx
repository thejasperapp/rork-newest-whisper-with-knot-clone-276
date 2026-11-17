import { memo, useEffect, useMemo, useRef } from "react";
import L from "leaflet";
import "leaflet/dist/leaflet.css";

import type { MapPlace } from "@/lib/dmEmber";

/**
 * Real interactive map for the Ember nearby-restaurants embed — the web
 * counterpart of the iOS native MapKit `Map`. Renders OpenStreetMap tiles with
 * a "you" dot and numbered pins for each place, auto-framing the camera tightly
 * around every marker (mirroring the iOS `region` fitting logic).
 */
function NearbyMapBase({
  lat,
  lon,
  places,
  height = 150,
  interactive = false,
}: {
  lat: number;
  lon: number;
  places: MapPlace[];
  height?: number;
  interactive?: boolean;
}) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<L.Map | null>(null);

  const points = useMemo(
    () => places.slice(0, 9).filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon)),
    [places]
  );

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;

    const map = L.map(containerRef.current, {
      zoomControl: interactive,
      attributionControl: false,
      dragging: interactive,
      scrollWheelZoom: interactive,
      doubleClickZoom: interactive,
      touchZoom: interactive,
      boxZoom: interactive,
      keyboard: interactive,
    });
    mapRef.current = map;

    L.tileLayer("https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png", {
      maxZoom: 19,
      crossOrigin: true,
    }).addTo(map);

    // "You" marker — white ring with blue dot, matching iOS.
    L.marker([lat, lon], {
      icon: L.divIcon({
        className: "",
        html: `<div style="width:18px;height:18px;border-radius:50%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,0.35);display:flex;align-items:center;justify-content:center;"><div style="width:11px;height:11px;border-radius:50%;background:#2563eb;"></div></div>`,
        iconSize: [18, 18],
        iconAnchor: [9, 9],
      }),
      interactive: false,
    }).addTo(map);

    // Numbered black pins for each place.
    points.forEach((p, idx) => {
      L.marker([p.lat, p.lon], {
        icon: L.divIcon({
          className: "",
          html: `<div style="width:22px;height:22px;border-radius:50%;background:#111;border:1.5px solid #fff;box-shadow:0 1px 3px rgba(0,0,0,0.35);color:#fff;font-size:11px;font-weight:800;display:flex;align-items:center;justify-content:center;">${idx + 1}</div>`,
          iconSize: [22, 22],
          iconAnchor: [11, 11],
        }),
        title: p.name,
        interactive,
      }).addTo(map);
    });

    // Fit camera tightly around the user + all pins.
    const all: [number, number][] = [[lat, lon], ...points.map((p): [number, number] => [p.lat, p.lon])];
    if (all.length > 1) {
      map.fitBounds(L.latLngBounds(all), { padding: [28, 28], maxZoom: 16 });
    } else {
      map.setView([lat, lon], 14);
    }

    // Tiles can render before the container has its final size (sheets/dialogs).
    const t = setTimeout(() => map.invalidateSize(), 120);

    return () => {
      clearTimeout(t);
      map.remove();
      mapRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lat, lon, points, interactive]);

  return <div ref={containerRef} style={{ height, width: "100%" }} aria-label="Map of nearby restaurants" />;
}

export const NearbyMap = memo(NearbyMapBase);
