import { useSyncExternalStore } from "react";
import { jasperCurrentGeneration, onJasperInvalidated } from "@/lib/jasperSession";

/** Scope private query keys and open Jasper panels to the current connection generation. */
export function useJasperGeneration(): number {
  return useSyncExternalStore(onJasperInvalidated, jasperCurrentGeneration, () => 0);
}
