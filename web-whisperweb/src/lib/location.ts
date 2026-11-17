/**
 * Resolves the user's current city for the "Location" thought style — the web
 * counterpart of the iOS `EmberLocationService`. Uses the browser Geolocation
 * API for coordinates, then BigDataCloud's free reverse-geocode endpoint (no
 * key required) to turn them into a "City, Region" label.
 */

interface ReverseGeocode {
  city?: string;
  locality?: string;
  principalSubdivision?: string;
  countryName?: string;
}

function getPosition(): Promise<GeolocationPosition> {
  return new Promise((resolve, reject) => {
    if (!("geolocation" in navigator)) {
      reject(new Error("Geolocation unavailable"));
      return;
    }
    navigator.geolocation.getCurrentPosition(resolve, reject, {
      enableHighAccuracy: false,
      timeout: 10000,
      maximumAge: 5 * 60 * 1000,
    });
  });
}

/** Returns a "City, Region" label or null if it can't be resolved. */
export async function resolveCurrentCity(): Promise<string | null> {
  try {
    const pos = await getPosition();
    const { latitude, longitude } = pos.coords;
    const res = await fetch(
      `https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${latitude}&longitude=${longitude}&localityLanguage=en`
    );
    if (!res.ok) return null;
    const data = (await res.json()) as ReverseGeocode;
    const city = data.city || data.locality || "";
    const region = data.principalSubdivision || "";
    if (city && region) return `${city}, ${region}`;
    if (city) return city;
    if (region) return region;
    return data.countryName || null;
  } catch {
    return null;
  }
}
