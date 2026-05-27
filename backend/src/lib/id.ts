import { customAlphabet } from "nanoid";

/**
 * 8-char URL-safe IDs for profiles (e.g. "k7Fp2nLm"). Alphabet avoids
 * easily-confused characters (0/O, 1/I/l) so a person can type a URL by hand
 * if they have to. 8 chars over a 56-symbol alphabet gives ~7e13 possibilities
 * — collision-resistant for any plausible scale.
 */
const ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz";

export const newProfileId = customAlphabet(ALPHABET, 8);
export const newUserId = customAlphabet(ALPHABET, 12);
