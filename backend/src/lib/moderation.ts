/**
 * Lightweight upload-time content filter — covers App Store Guideline 1.2
 * "method for filtering objectionable material from being posted."
 *
 * Two passes:
 *   1. Slur list — substring match against a small bundled set of obvious
 *      English-language slurs (incl. common leetspeak variants).
 *   2. Pattern checks — phone numbers, URLs in fields that shouldn't have
 *      them, email-looking strings.
 *
 * Intentionally conservative — too aggressive a filter blocks legitimate
 * recipes (e.g. "ass-kicking espresso"). The goal is to catch the obvious
 * bad-faith uploads, not to fully sanitise. Anything that slips through
 * gets caught by the user-driven report flow.
 *
 * Word list lives in `slurs.json` so it's grep-able / updateable without
 * touching code. NOT committed to git (gitignored) — the dev seed file
 * `slurs.example.json` is what ships with the repo.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let SLURS: string[] = [];
function loadSlurs(): string[] {
  if (SLURS.length) return SLURS;
  const here = path.resolve(__dirname, "..");
  for (const name of ["slurs.json", "slurs.example.json"]) {
    const p = path.join(here, name);
    if (fs.existsSync(p)) {
      try {
        SLURS = JSON.parse(fs.readFileSync(p, "utf8"));
        return SLURS;
      } catch { /* fall through */ }
    }
  }
  SLURS = [];   // empty list = nothing matches = filter is a no-op
  return SLURS;
}

/** Patterns we always reject regardless of word list. */
const PHONE_REGEX  = /(?:\+?\d[\d\s\-().]{7,}\d)/;
const URL_REGEX    = /\b(?:https?:\/\/|www\.)\S+/i;
const EMAIL_REGEX  = /[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}/;

export interface ModerationOutcome {
  ok: boolean;
  reason?: string;
}

/** Run all checks against a string. Returns the first failure reason. */
export function checkText(input: string): ModerationOutcome {
  if (!input) return { ok: true };
  const lower = input.toLowerCase();
  const slurs = loadSlurs();
  for (const s of slurs) {
    if (lower.includes(s.toLowerCase())) {
      return { ok: false, reason: "contains-blocked-word" };
    }
  }
  if (PHONE_REGEX.test(input))  return { ok: false, reason: "contains-phone-number" };
  if (URL_REGEX.test(input))    return { ok: false, reason: "contains-url" };
  if (EMAIL_REGEX.test(input))  return { ok: false, reason: "contains-email" };
  return { ok: true };
}

/** Check every user-supplied string field on a profile upload. */
export function checkProfileFields(args: {
  name?: string | null;
  description?: string | null;
  beanName?: string | null;
  equipment?: string | null;
}): ModerationOutcome {
  for (const field of ["name", "description", "beanName", "equipment"] as const) {
    const v = args[field];
    if (typeof v === "string") {
      const r = checkText(v);
      if (!r.ok) return { ok: false, reason: `${field}-${r.reason}` };
    }
  }
  return { ok: true };
}
