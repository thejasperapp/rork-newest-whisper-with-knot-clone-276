import { useEffect, useState } from "react";
import { appearanceEvent, appearanceKey, readWallpaper } from "@/lib/chatWallpapers";
import { defaultGroupTheme, isGroupTheme, type GroupThemeDesign } from "@/lib/groupThemes";

/** Local preferences are keyed to both the account and exact conversation. */
export function usePersonalChatAppearance(accountID: string, thread: string) {
  const key = appearanceKey(accountID, thread);
  const [state, setState] = useState<{ key: string; design: GroupThemeDesign; wallpaper?: string }>({ key, design: defaultGroupTheme });
  useEffect(() => {
    let current = true;
    let request = 0;
    let url: string | undefined;
    const refresh = async (): Promise<void> => {
      const token = ++request;
      let design = defaultGroupTheme;
      try { const stored: unknown = JSON.parse(localStorage.getItem(key) ?? "null"); if (isGroupTheme(stored)) design = stored; } catch { /* Browsers can disable local storage. */ }
      const blob = await readWallpaper(key).catch(() => null);
      if (!current || token !== request) return;
      if (url) URL.revokeObjectURL(url);
      url = blob ? URL.createObjectURL(blob) : undefined;
      setState({ key, design, wallpaper: url });
    };
    const update = (): void => { void refresh(); };
    update(); window.addEventListener(appearanceEvent, update); window.addEventListener("storage", update);
    return () => { current = false; if (url) URL.revokeObjectURL(url); window.removeEventListener(appearanceEvent, update); window.removeEventListener("storage", update); };
  }, [key]);
  return state.key === key ? state : { key, design: defaultGroupTheme, wallpaper: undefined };
}
