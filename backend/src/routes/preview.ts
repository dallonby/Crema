import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { db, schema } from "../db/client.js";

/**
 * Public HTML preview for `/p/<id>`.
 *
 * If Crema is installed, Universal Links bounce this request straight
 * into the app (via the apple-app-site-association `/p/*` rule served
 * from /.well-known/). If not installed, the user gets this HTML page
 * with the profile metadata + a "Get the app" CTA.
 *
 * Single-file, no dependencies (no templating engine). String-built
 * with deliberately small surface — the page is metadata + 3 buttons,
 * no interactivity.
 */
const preview = new Hono();

preview.get("/:id", async (c) => {
  const id = c.req.param("id");
  const row = await db
    .select({ p: schema.profiles, u: schema.users })
    .from(schema.profiles)
    .innerJoin(schema.users, eq(schema.users.id, schema.profiles.authorId))
    .where(eq(schema.profiles.id, id))
    .limit(1);
  if (!row.length) {
    c.status(404);
    return c.html(notFoundHTML);
  }
  const { p, u } = row[0];
  return c.html(profileHTML(p, u));
});

// ---------------------------------------------------------------
// HTML rendering
// ---------------------------------------------------------------

function esc(s: string | null | undefined): string {
  if (s == null) return "";
  return s.replace(/[&<>"']/g, (m) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;",
    '"': "&quot;", "'": "&#39;",
  }[m]!));
}

function profileHTML(p: schema.Profile, u: schema.User): string {
  const json = p.profileJson as Record<string, unknown>;
  const stages = Array.isArray(json.stages) ? (json.stages as Array<Record<string, unknown>>) : [];
  const totalDuration = stages.reduce((acc, s) => {
    return acc + (Number(s.duration) || 0) + (Number(s.waitAfter) || 0);
  }, 0);

  const stageRows = stages.map((s, i) => {
    const accent = s.priority === "pressure" ? "#E8843C" : "#D9B872";
    const detail = s.priority === "pressure"
      ? `${Number(s.pressureBar).toFixed(1)} bar`
      : `${Number(s.flowMlPerSec).toFixed(1)} mL/s`;
    return `
      <li class="stage">
        <span class="stage-bar" style="background:${accent}"></span>
        <div class="stage-text">
          <div class="stage-label">${esc(String(s.label ?? `Stage ${i+1}`))}</div>
          <div class="stage-detail">${detail} · ${Number(s.duration)} s${
            Number(s.waitAfter) ? ` + ${Number(s.waitAfter)} s wait` : ""
          }</div>
        </div>
      </li>`;
  }).join("");

  const deepLink = `crema://profile/${p.id}`;
  const pageTitle = `${p.name} · Crema`;

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${esc(pageTitle)}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#0A0908">
<meta property="og:title" content="${esc(p.name)}">
<meta property="og:description" content="${esc(p.description ?? `Brew profile by ${u.displayName}`)}">
<meta property="og:type" content="website">
<style>
:root { color-scheme: dark; }
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
  background: radial-gradient(ellipse at 75% 15%, #38221060 0%, #1E120988 35%, #0A0908 100%);
  background-attachment: fixed;
  color: #F5EFEA;
  min-height: 100dvh;
  -webkit-font-smoothing: antialiased;
}
.wrap { max-width: 560px; margin: 0 auto; padding: 40px 24px 80px; }
header { display: flex; align-items: center; gap: 12px; margin-bottom: 32px; }
.dot {
  width: 14px; height: 14px; border-radius: 50%;
  background: radial-gradient(circle at 30% 30%, #FF9F50, #E8843C);
  box-shadow: 0 0 12px #E8843C80;
}
.brand { font-size: 16px; font-weight: 600; letter-spacing: -0.01em; }
h1 {
  font-size: clamp(28px, 6vw, 38px); font-weight: 700; line-height: 1.1;
  letter-spacing: -0.02em; margin-bottom: 8px;
}
.by {
  color: #8A827C; font-size: 14px; margin-bottom: 24px;
}
.by strong { color: #E8843C; font-weight: 600; }
.desc {
  font-size: 15px; line-height: 1.55; color: #F5EFEAcc;
  margin-bottom: 28px;
}
.meta-grid {
  display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px;
  margin-bottom: 28px;
}
.tile {
  background: rgba(26, 22, 20, 0.6); border: 0.5px solid #8A827C30;
  border-radius: 12px; padding: 14px;
}
.tile-value {
  font-size: 22px; font-weight: 600; letter-spacing: -0.02em;
  font-variant-numeric: tabular-nums;
}
.tile-label {
  font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;
  color: #8A827C; font-weight: 600; margin-top: 4px;
}
.section-title {
  font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em;
  font-weight: 600; color: #8A827C; margin: 28px 0 12px;
}
.stages { list-style: none; }
.stage {
  display: flex; align-items: center; gap: 14px;
  padding: 14px; margin-bottom: 8px;
  background: rgba(26, 22, 20, 0.5); border-radius: 12px;
  border: 0.5px solid #8A827C30;
}
.stage-bar { display: block; width: 4px; height: 32px; border-radius: 2px; }
.stage-label { font-size: 14px; font-weight: 600; }
.stage-detail {
  font-size: 12px; color: #8A827C; margin-top: 2px;
  font-variant-numeric: tabular-nums;
}
.cta {
  display: flex; flex-direction: column; gap: 10px;
  margin-top: 36px;
}
.btn {
  display: flex; align-items: center; justify-content: center;
  gap: 8px;
  padding: 16px 20px; border-radius: 14px; font-weight: 600; font-size: 15px;
  text-decoration: none; transition: transform 0.1s ease;
}
.btn:active { transform: scale(0.98); }
.btn-primary {
  background: linear-gradient(135deg, #FF9F50, #E8843C);
  color: #0A0908;
  box-shadow: 0 4px 18px #E8843C66;
}
.btn-secondary {
  background: rgba(26, 22, 20, 0.6);
  color: #F5EFEA;
  border: 0.5px solid #8A827C50;
}
footer {
  margin-top: 56px; padding-top: 24px; border-top: 0.5px solid #8A827C30;
  text-align: center; color: #8A827C70; font-size: 11px;
}
footer a { color: #8A827C; text-decoration: none; }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <span class="dot"></span>
    <span class="brand">Crema</span>
  </header>

  <h1>${esc(p.name)}</h1>
  <div class="by">by <strong>${esc(u.displayName)}</strong>${
    p.beanName ? ` · ${esc(p.beanName)}` : ""
  }</div>

  ${p.description ? `<p class="desc">${esc(p.description)}</p>` : ""}

  <div class="meta-grid">
    <div class="tile">
      <div class="tile-value">${stages.length}</div>
      <div class="tile-label">Stages</div>
    </div>
    <div class="tile">
      <div class="tile-value">${Math.round(totalDuration)}<span style="font-size:14px;color:#8A827C">s</span></div>
      <div class="tile-label">Duration</div>
    </div>
    <div class="tile">
      <div class="tile-value">${p.likesCount}</div>
      <div class="tile-label">Likes</div>
    </div>
  </div>

  <div class="section-title">Stages</div>
  <ul class="stages">${stageRows}</ul>

  ${p.equipment ? `
    <div class="section-title">Equipment</div>
    <div class="tile">${esc(p.equipment)}</div>
  ` : ""}

  <div class="cta">
    <a class="btn btn-primary" href="${deepLink}">Open in Crema</a>
    <a class="btn btn-secondary" href="https://apps.apple.com/app/crema">Get the app</a>
  </div>

  <footer>
    Shared from <a href="https://github.com/dallonby/Crema">Crema</a> ·
    Espresso profiling for coffee nerds
  </footer>
</div>
</body>
</html>`;
}

const notFoundHTML = `<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"><title>Profile not found · Crema</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body {
  font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
  background: #0A0908; color: #F5EFEA; min-height: 100dvh;
  display: flex; align-items: center; justify-content: center;
  text-align: center; padding: 40px;
}
h1 { font-size: 32px; margin-bottom: 12px; letter-spacing: -0.02em; }
p  { color: #8A827C; font-size: 15px; }
</style>
</head><body><div>
<h1>Profile not found</h1>
<p>This share link is no longer valid — the author may have deleted it.</p>
</div></body></html>`;

export default preview;
