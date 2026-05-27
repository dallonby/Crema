/**
 * Upload-time content filter — covers App Store Guideline 1.2 ("filter
 * objectionable material from being posted").
 *
 * Three layers:
 *
 *  1. **Obscenity (English with leetspeak / spacing detection).**
 *     Catches `f4ck`, `f.u.c.k`, `f u c k`, etc. The maintained Node
 *     library `obscenity` does this properly — significantly harder to
 *     bypass than a flat substring match.
 *
 *  2. **LDNOOBW multi-language word lists.**
 *     Shutterstock-maintained list of objectionable words across ~28
 *     languages (we bundle 19). Plain-text files in `wordlists/`,
 *     loaded once at module init. Substring match — no leet handling
 *     outside English, which is fine for the coarse "obvious bad faith"
 *     bar we're aiming for.
 *     https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words
 *
 *  3. **Pattern checks** — phone numbers, URLs, email addresses. Common
 *     spam vectors in a "share your recipe" feature.
 *
 * Anything that slips through (subtle harassment, sexual descriptions
 * without slurs, threats) is caught by the user-driven report flow.
 *
 * Upgrade path when we see real abuse: layer in OpenAI Moderation API
 * as a fourth check before insert. Free, multilingual, semantic.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  RegExpMatcher,
  englishDataset,
  englishRecommendedTransformers,
} from "obscenity";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------
// English (obscenity)
// ---------------------------------------------------------------
const englishMatcher = new RegExpMatcher({
  ...englishDataset.build(),
  ...englishRecommendedTransformers,
});

// ---------------------------------------------------------------
// Other languages (LDNOOBW)
// ---------------------------------------------------------------
const OTHER_LANGUAGES = [
  "es", "fr", "de", "it", "pt", "nl",
  "ja", "ko", "zh",
  "ar", "hi", "ru",
  "sv", "da", "no", "fi",
  "pl", "tr",
];

interface MultiLangBank {
  /** lowercase word → first language code it appeared in (for error reporting) */
  byWord: Map<string, string>;
}

let bank: MultiLangBank | null = null;
function loadBank(): MultiLangBank {
  if (bank) return bank;
  const byWord = new Map<string, string>();
  const dir = path.join(__dirname, "wordlists");
  for (const lang of OTHER_LANGUAGES) {
    const file = path.join(dir, `${lang}.txt`);
    if (!fs.existsSync(file)) continue;
    const words = fs.readFileSync(file, "utf8")
      .split(/\r?\n/)
      .map(w => w.trim().toLowerCase())
      // Skip very short tokens — they cause false positives across
      // languages (e.g. "ass" matches "passport"). LDNOOBW's English
      // list is filtered out anyway since obscenity handles English.
      .filter(w => w.length >= 4);
    for (const w of words) {
      if (!byWord.has(w)) byWord.set(w, lang);
    }
  }
  bank = { byWord };
  return bank;
}

// ---------------------------------------------------------------
// Pattern checks
// ---------------------------------------------------------------
const PHONE_REGEX = /(?:\+?\d[\d\s\-().]{7,}\d)/;
const URL_REGEX   = /\b(?:https?:\/\/|www\.)\S+/i;
const EMAIL_REGEX = /[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}/;

// ---------------------------------------------------------------
// Public API
// ---------------------------------------------------------------
export interface ModerationOutcome {
  ok: boolean;
  reason?: string;
}

export function checkText(input: string): ModerationOutcome {
  if (!input) return { ok: true };

  // 1. English with leetspeak / spacing detection
  if (englishMatcher.hasMatch(input)) {
    return { ok: false, reason: "english-profanity" };
  }

  // 2. Multi-language word list (substring match against bundled LDNOOBW)
  const lower = input.toLowerCase();
  const { byWord } = loadBank();
  for (const [word, lang] of byWord) {
    if (lower.includes(word)) {
      return { ok: false, reason: `${lang}-profanity` };
    }
  }

  // 3. Spam patterns
  if (PHONE_REGEX.test(input)) return { ok: false, reason: "contains-phone-number" };
  if (URL_REGEX.test(input))   return { ok: false, reason: "contains-url" };
  if (EMAIL_REGEX.test(input)) return { ok: false, reason: "contains-email" };

  return { ok: true };
}

/** Run checks across every user-supplied string field on a profile upload. */
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
      if (!r.ok) return { ok: false, reason: `${field}: ${r.reason}` };
    }
  }
  return { ok: true };
}

/** Number of words loaded across all languages — for /api debug. */
export function dictionarySize(): number {
  return loadBank().byWord.size;
}
