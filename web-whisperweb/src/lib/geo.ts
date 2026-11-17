/**
 * Resolve the user's current location to a short place name using the browser
 * Geolocation API + OpenStreetMap's free Nominatim reverse geocoder (no key).
 * Returns a compact label like "Brooklyn, New York" or falls back to the
 * coordinates. Throws when permission is denied or geolocation is unsupported.
 */
export async function currentPlaceName(): Promise<string> {
  if (!("geolocation" in navigator)) {
    throw new Error("Location isn't supported on this device.");
  }

  const position = await new Promise<GeolocationPosition>((resolve, reject) => {
    navigator.geolocation.getCurrentPosition(resolve, reject, {
      enableHighAccuracy: false,
      timeout: 10_000,
      maximumAge: 60_000,
    });
  });

  const { latitude, longitude } = position.coords;

  try {
    const res = await fetch(
      `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${latitude}&lon=${longitude}&zoom=12`,
      { headers: { Accept: "application/json" } }
    );
    if (res.ok) {
      const json = (await res.json()) as {
        address?: Record<string, string>;
        name?: string;
      };
      const a = json.address ?? {};
      const city =
        a.city ?? a.town ?? a.village ?? a.suburb ?? a.county ?? json.name;
      const region = a.state ?? a.region ?? a.country;
      const parts = [city, region].filter(Boolean);
      if (parts.length > 0) return parts.join(", ");
    }
  } catch {
    // fall through to coordinates
  }

  return `${latitude.toFixed(3)}, ${longitude.toFixed(3)}`;
}
