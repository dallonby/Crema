import { Hono } from "hono";

/**
 * Apple Universal Links + Android App Links discovery.
 *
 * Apple expects an `apple-app-site-association` JSON file at
 * `/.well-known/apple-app-site-association` (no extension, signed with
 * `application/json` Content-Type — Apple does NOT accept `.json`).
 *
 * The `appID` is `<team-id>.<bundle-id>`. With it served, tapping a
 * configured URL (e.g. `https://api.crema.coffee/p/abc12345`) in Mail,
 * Messages, Safari etc. opens the installed Crema app directly — no
 * scheme prompt, no `crema://` intermediate.
 *
 * Configure via env:
 *  APPLE_APP_ID="YDGQZ6G5L9.coffee.crema.app"
 *  ANDROID_PACKAGE_NAME="coffee.crema.app"
 *  ANDROID_SHA256_FINGERPRINTS="aa:bb:cc:…,ee:ff:00:…"  (comma-separated)
 *
 * The Android equivalent (`assetlinks.json`) is also served here so a
 * single backend deployment supports both platforms without web-server
 * config changes.
 */
const wellKnown = new Hono();

const APPLE_APP_ID = process.env.APPLE_APP_ID;
const ANDROID_PACKAGE = process.env.ANDROID_PACKAGE_NAME;
const ANDROID_FINGERPRINTS = (process.env.ANDROID_SHA256_FINGERPRINTS ?? "")
  .split(",").map(s => s.trim()).filter(Boolean);

wellKnown.get("/apple-app-site-association", (c) => {
  if (!APPLE_APP_ID) return c.json({ error: "APPLE_APP_ID not configured" }, 501);
  const payload = {
    applinks: {
      details: [
        {
          appIDs: [APPLE_APP_ID],
          components: [
            // Open in app for any /p/<id> URL.
            { "/": "/p/*", comment: "Shared brew profile permalinks" },
          ],
        },
      ],
    },
    // Useful when an external site links to the app for a specific
    // file type; harmless to include.
    appclips: { apps: [APPLE_APP_ID] },
  };
  // Important: explicit application/json, no .json extension on the path.
  c.header("Content-Type", "application/json");
  return c.body(JSON.stringify(payload));
});

wellKnown.get("/assetlinks.json", (c) => {
  if (!ANDROID_PACKAGE || ANDROID_FINGERPRINTS.length === 0) {
    return c.json({ error: "ANDROID_PACKAGE_NAME + ANDROID_SHA256_FINGERPRINTS not configured" }, 501);
  }
  const payload = [
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: {
        namespace: "android_app",
        package_name: ANDROID_PACKAGE,
        sha256_cert_fingerprints: ANDROID_FINGERPRINTS,
      },
    },
  ];
  return c.json(payload);
});

export default wellKnown;
