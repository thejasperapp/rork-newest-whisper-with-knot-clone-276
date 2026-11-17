import { useCallback, useSyncExternalStore } from "react";
const event = "whisper-conversation-nickname";
const subscribe = (change: () => void): (() => void) => { window.addEventListener(event, change); window.addEventListener("storage", change); return () => { window.removeEventListener(event, change); window.removeEventListener("storage", change); }; };
/** Personal account-and-thread-qualified display name; never changes the participant identity. */
export function useConversationNickname(accountID: string, thread: string): { nickname: string; saveNickname: (value: string) => void } {
  const key = `whisper.nickname.v1:${accountID}:${thread}`;
  const read = useCallback((): string => { try { return localStorage.getItem(key)?.slice(0, 48) ?? ""; } catch { return ""; } }, [key]);
  const nickname = useSyncExternalStore(subscribe, read, () => "");
  const saveNickname = useCallback((value: string): void => { const name = value.trim().slice(0, 48); if (name) localStorage.setItem(key, name); else localStorage.removeItem(key); window.dispatchEvent(new Event(event)); }, [key]);
  return { nickname, saveNickname };
}
