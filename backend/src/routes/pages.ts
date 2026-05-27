import { Hono } from "hono";

/**
 * Marketing / compliance pages served at well-known paths. App Store
 * Connect refuses to submit an app without a working privacy-policy URL
 * AND a support URL — both have to resolve to real HTML, not 404s.
 *
 * For now the policy text + support copy live as inline templates here.
 * If they grow, move to markdown files + a renderer.
 */
const pages = new Hono();

pages.get("/privacy", (c) => c.html(privacyHTML));
pages.get("/support", (c) => c.html(supportHTML));
// Apex / marketing landing — minimal "Coming soon" until the real site lands.
pages.get("/", (c) => c.html(homeHTML));

// ---------------------------------------------------------------
// Shared layout
// ---------------------------------------------------------------

function shell(title: string, body: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${title}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#0A0908">
<style>
:root { color-scheme: dark; }
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
  background: radial-gradient(ellipse at 75% 15%, #38221060 0%, #1E120988 35%, #0A0908 100%);
  background-attachment: fixed; color: #F5EFEA; min-height: 100dvh;
  -webkit-font-smoothing: antialiased; line-height: 1.6;
}
.wrap { max-width: 680px; margin: 0 auto; padding: 48px 24px 96px; }
header { display: flex; align-items: center; gap: 12px; margin-bottom: 40px; }
.dot { width: 14px; height: 14px; border-radius: 50%;
  background: radial-gradient(circle at 30% 30%, #FF9F50, #E8843C);
  box-shadow: 0 0 12px #E8843C80; }
.brand { font-size: 16px; font-weight: 600; letter-spacing: -0.01em; }
h1 { font-size: clamp(28px, 6vw, 40px); font-weight: 700;
  letter-spacing: -0.02em; margin-bottom: 8px; line-height: 1.15; }
h2 { font-size: 18px; font-weight: 600; letter-spacing: -0.01em;
  margin: 32px 0 10px; color: #E8843C; }
p, ul { margin-bottom: 14px; color: #F5EFEAdd; }
ul { padding-left: 22px; }
li { margin-bottom: 6px; }
strong { color: #F5EFEA; font-weight: 600; }
a { color: #FF9F50; text-decoration: none; }
a:hover { text-decoration: underline; }
.eyebrow { font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em;
  color: #8A827C; font-weight: 600; margin-bottom: 8px; }
footer { margin-top: 64px; padding-top: 24px; border-top: 0.5px solid #8A827C30;
  text-align: center; color: #8A827C70; font-size: 11px; }
footer a { color: #8A827C; }
</style>
</head>
<body>
<div class="wrap">
<header><span class="dot"></span><span class="brand">CaffeCrema Labs</span></header>
${body}
<footer>
  © 2026 CaffeCrema Labs · <a href="/privacy">Privacy</a> · <a href="/support">Support</a>
</footer>
</div>
</body>
</html>`;
}

// ---------------------------------------------------------------
// Privacy policy
// ---------------------------------------------------------------

const privacyHTML = shell("Privacy · CaffeCrema Labs", `
<div class="eyebrow">Last updated · 27 May 2026</div>
<h1>Privacy Policy</h1>
<p>CaffeCrema Labs connects your iPhone, iPad, or Mac to a Wendougee LITA espresso machine over Bluetooth LE, lets you design and run brew profiles, and offers an optional community feature for sharing recipes. This document explains what data we collect, why, and how we handle it.</p>

<h2>What stays on your device</h2>
<ul>
<li>Your brew profile library</li>
<li>Shot history with tasting notes and yield</li>
<li>Paired machine identifiers and connection state</li>
<li>Any profile you author but don't explicitly share</li>
</ul>
<p>These are <strong>not</strong> transmitted to our servers.</p>

<h2>What we collect when you sign in</h2>
<p>Sign-in is optional and only required for community sharing. When you sign in with Apple or Google:</p>
<ul>
<li>We receive a pseudonymous <strong>user identifier</strong> from the provider — a stable opaque string. We never receive your Apple ID. Google additionally provides display name + avatar if you grant the <code>profile</code> scope.</li>
<li>We store this identifier alongside a <strong>display name</strong> you choose.</li>
<li>We do not receive or store your email address from the sign-in provider.</li>
</ul>

<h2>What we collect when you share a profile</h2>
<ul>
<li>The full <strong>brew profile</strong> (recipe shape, equipment notes, bean name if provided)</li>
<li>Your display name as the author</li>
</ul>
<p>Shared profiles are <strong>public</strong> — anyone with the link or browsing the community feed can view and import them.</p>

<h2>Likes and follows</h2>
<p>Both are public signals stored on our backend.</p>

<h2>What we do NOT collect</h2>
<ul>
<li>Location, health, contacts, photos, files</li>
<li>Browsing or search history</li>
<li>Financial information</li>
<li>Advertising identifiers (IDFA / GAID)</li>
<li>Crash analytics — no third-party SDK runs in the app</li>
</ul>

<h2>Tracking</h2>
<p>We do not track you across apps or websites. No data is shared with advertising networks.</p>

<h2>Bluetooth</h2>
<p>Bluetooth LE talks to your espresso machine. Telemetry (pressure, flow, volume readings) and control commands stay on your device — they are not transmitted to our servers.</p>

<h2>Children</h2>
<p>The app is not directed at children under 13 and is rated 4+. We do not knowingly collect data from children.</p>

<h2>Your rights</h2>
<ul>
<li><strong>Delete an uploaded profile</strong> at any time from within the app — it is removed from the server immediately.</li>
<li><strong>Sign out</strong> from Settings → Sign Out.</li>
<li><strong>Delete your account</strong> by emailing <a href="mailto:da@byeq.com">da@byeq.com</a> with your display name. We will purge your user record and all uploaded profiles within 14 days.</li>
</ul>

<h2>Data location</h2>
<p>Our backend runs in the United Kingdom and stores data in PostgreSQL.</p>

<h2>Changes</h2>
<p>If we change this policy materially, the date above will update and the app will surface a notice on next launch.</p>

<h2>Contact</h2>
<p><a href="mailto:da@byeq.com">da@byeq.com</a></p>
`);

// ---------------------------------------------------------------
// Support
// ---------------------------------------------------------------

const supportHTML = shell("Support · CaffeCrema Labs", `
<h1>Support</h1>
<p>Reach us at <a href="mailto:da@byeq.com">da@byeq.com</a> with bug reports, feature requests, or hardware questions. We try to reply within 48 hours.</p>

<h2>Frequently asked</h2>

<p><strong>Which machines does it work with?</strong><br>
Wendougee LITA-BA, LITA-BR, and DATA-S — anything with the LITA Bluetooth protocol.</p>

<p><strong>Will it work with [other espresso machine]?</strong><br>
Not yet. The protocol is reverse-engineered from the Wendougee family. We may add others later if there's demand and the protocols are accessible.</p>

<p><strong>I don't have the machine — can I still try the app?</strong><br>
Yes. Tap the <strong>Demo</strong> chip in the header to switch to replay mode. A real captured shot plays back through every screen.</p>

<p><strong>The auto-tune wizard suggests a different grind size every shot.</strong><br>
That's working as intended — it's converging on a dialed-in recipe across 3 guided shots, narrowing the adjustment each iteration. Saved profile uses your highest-scoring shot, trimmed to your target brew time.</p>

<p><strong>My shared profile didn't sync to my other device.</strong><br>
You need to be signed in with the same Apple ID on both devices and have explicitly imported the profile from the community on each. Cross-device library sync is on the v0.3 roadmap.</p>

<p><strong>How do I delete my account / data?</strong><br>
Email <a href="mailto:da@byeq.com">da@byeq.com</a>. We purge within 14 days. An in-app delete button is coming in v0.3.</p>
`);

// ---------------------------------------------------------------
// Apex landing
// ---------------------------------------------------------------

const homeHTML = shell("CaffeCrema Labs · Espresso, dialed in.", `
<h1>Espresso, dialed in.</h1>
<p style="font-size: 17px; color: #F5EFEA;">A native iPhone / iPad / Mac client for the Wendougee LITA espresso machine. Author multi-stage pressure and flow profiles, watch every shot in real time, dial in new beans with the auto-tune wizard, and share your best recipes with the community.</p>

<h2>Coming soon</h2>
<p>TestFlight beta opening shortly. <a href="mailto:da@byeq.com?subject=Crema TestFlight">Email us</a> to be on the list.</p>

<h2>For the curious</h2>
<p>Source + protocol notes at <a href="https://github.com/dallonby/Crema">github.com/dallonby/Crema</a>.</p>
`);

export default pages;
