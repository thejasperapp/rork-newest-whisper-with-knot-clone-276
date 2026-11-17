/**
 * Web port of the iOS `WhisperGroceryListEmbed` (`::whisper-grocery-v1::`).
 * A collaborative grocery list sent via `/grocery <theme>` or from a recipe.
 * Each user keeps their own check state locally (keyed by the embed id) so both
 * sides can tick items off without flooding the thread — exactly like the iOS
 * `WhisperGroceryStore`.
 */

const GROCERY_PREFIX = "::whisper-grocery-v1::";

export interface GroceryPayload {
  id: string;
  title: string;
  items: string[];
  authorUsername: string;
}

export function encodeGrocery(p: GroceryPayload): string {
  return GROCERY_PREFIX + JSON.stringify(p);
}

export function decodeGrocery(
  body: string | null | undefined
): GroceryPayload | null {
  if (!body || !body.startsWith(GROCERY_PREFIX)) return null;
  try {
    const o = JSON.parse(body.slice(GROCERY_PREFIX.length)) as Partial<GroceryPayload>;
    if (!Array.isArray(o.items)) return null;
    return {
      id: o.id ?? crypto.randomUUID(),
      title: o.title ?? "Shared grocery list",
      items: o.items.filter((i): i is string => typeof i === "string"),
      authorUsername: o.authorUsername ?? "",
    };
  } catch {
    return null;
  }
}

const STORE_KEY_PREFIX = "whisper_grocery_state_v1::";

/** Reads the locally-checked items for a list id. */
export function checkedGroceryItems(listId: string): Set<string> {
  try {
    const raw = localStorage.getItem(STORE_KEY_PREFIX + listId);
    if (!raw) return new Set();
    const arr = JSON.parse(raw) as unknown;
    return new Set(Array.isArray(arr) ? (arr as string[]) : []);
  } catch {
    return new Set();
  }
}

/** Toggles an item's checked state and persists it, returning the new set. */
export function toggleGroceryItem(listId: string, item: string): Set<string> {
  const set = checkedGroceryItems(listId);
  if (set.has(item)) set.delete(item);
  else set.add(item);
  try {
    localStorage.setItem(STORE_KEY_PREFIX + listId, JSON.stringify([...set]));
  } catch {
    /* storage full / unavailable — keep the in-memory toggle */
  }
  return set;
}
