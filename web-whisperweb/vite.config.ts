import fs from "fs";
import path from "path";

import react from "@vitejs/plugin-react";
import { defineConfig, type Plugin } from "vite";

/**
 * SPA fallback plugin — after every build, copies dist/index.html to
 * dist/404.html so static hosts that serve 404.html on unknown paths
 * (GitHub Pages–style) still boot the app on hard refreshes of deep
 * routes like /billing/success. Hosts that honor public/_redirects
 * (Netlify/Cloudflare-style) use that file instead.
 */
function spaFallback(): Plugin {
  return {
    name: "spa-404-fallback",
    apply: "build",
    closeBundle() {
      const dist = path.resolve(__dirname, "dist");
      const index = path.join(dist, "index.html");
      if (fs.existsSync(index)) {
        fs.copyFileSync(index, path.join(dist, "404.html"));
      }
    },
  };
}

/** The iOS app's bundle identifier (ios/Whisper.xcodeproj). */
const IOS_BUNDLE_ID = "com.mydailywhisper.whisper";

/**
 * Universal links — writes the apple-app-site-association file after every
 * build so meeting links (mydailywhisper.com/meet/…, meet./wsp-…) open the
 * native Whisper app first, with the web page as the backup. Apple requires
 * the Team ID in the file, so it's read from the build environment
 * (EXPO_PUBLIC_TEAM_ID or APPLE_TEAM_ID); without it the file is skipped and
 * links simply stay on the web (the "Open in the Whisper app" button still
 * hands off via the whisper:// scheme).
 */
function appleAppSiteAssociation(): Plugin {
  return {
    name: "apple-app-site-association",
    apply: "build",
    closeBundle() {
      const teamId = (process.env.EXPO_PUBLIC_TEAM_ID ?? process.env.APPLE_TEAM_ID ?? "").trim();
      if (!teamId) {
        console.warn("[aasa] EXPO_PUBLIC_TEAM_ID not set — skipping apple-app-site-association");
        return;
      }
      const appID = `${teamId}.${IOS_BUNDLE_ID}`;
      const body = JSON.stringify(
        {
          applinks: {
            details: [
              {
                appIDs: [appID],
                components: [
                  { "/": "/meet/*", comment: "Whisper Meet rooms" },
                  { "/": "/wsp-*", comment: "Bare meeting codes (meet. subdomain)" },
                ],
              },
            ],
          },
          webcredentials: { apps: [appID] },
        },
        null,
        2,
      );
      const dist = path.resolve(__dirname, "dist");
      const wellKnown = path.join(dist, ".well-known");
      fs.mkdirSync(wellKnown, { recursive: true });
      fs.writeFileSync(path.join(wellKnown, "apple-app-site-association"), body);
      fs.writeFileSync(path.join(dist, "apple-app-site-association"), body);
    },
  };
}

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => ({
  server: {
    host: "::",
    port: 8080,
    hmr: {
      overlay: false,
    },
  },
  plugins: [react(), spaFallback(), appleAppSiteAssociation()],
  build: {
    rollupOptions: {
      input: {
        main: path.resolve(__dirname, "index.html"),
        knotVoice: path.resolve(__dirname, "knot-voice-transport.html"),
      },
    },
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  // Expose both VITE_* (Vite default) and EXPO_PUBLIC_* (Rork's cross-platform
  // public-env convention, written by tools like getOrCreateAuthConfig).
  envPrefix: ["VITE_", "EXPO_PUBLIC_"],
}));
