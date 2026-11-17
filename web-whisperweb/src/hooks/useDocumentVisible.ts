import { useEffect, useState } from "react";

/** Media playback follows browser visibility, not just the selected route. */
export function useDocumentVisible(): boolean {
  const [visible, setVisible] = useState<boolean>(() => !document.hidden);
  useEffect(() => { const update = (): void => setVisible(!document.hidden); document.addEventListener("visibilitychange", update); return () => document.removeEventListener("visibilitychange", update); }, []);
  return visible;
}
