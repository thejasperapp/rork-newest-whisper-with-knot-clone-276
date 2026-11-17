import { useEffect, useState } from "react";
import { coachDashboard, type JasperClientDashboard } from "@/lib/jasperCoachConnect";
import { useJasperGeneration } from "@/hooks/useJasperGeneration";

export type CoachPreview = JasperClientDashboard | "error";

/** Display-only roster enrichment. The transport retains its authoritative
 * grants, session checks and matching-request sharing. Never fan out the roster. */
export function useCoachPreviews(owner: string, clientIds: string[], active: boolean) {
  const generation = useJasperGeneration();
  const rosterKey = [...new Set(clientIds)].sort().join(",");
  const scope = `${owner}/${generation}/${rosterKey}`;
  const [visible, setVisible] = useState(() => document.visibilityState === "visible");
  const [snapshot, setSnapshot] = useState<{ scope: string; rows: Record<string, CoachPreview> }>({ scope: "", rows: {} });
  useEffect(() => {
    const update = () => setVisible(document.visibilityState === "visible");
    document.addEventListener("visibilitychange", update);
    return () => document.removeEventListener("visibilitychange", update);
  }, []);
  useEffect(() => {
    if (!owner || !active || !visible || !rosterKey) return;
    let current = true;
    const ids = rosterKey.split(",");
    let next = 0;
    setSnapshot(previous => previous.scope === scope ? previous : { scope, rows: {} });
    const worker = async () => {
      while (current && next < ids.length) {
        const id = ids[next++];
        let value: CoachPreview;
        try { value = await coachDashboard(id); } catch { value = "error"; }
        if (!current) return;
        setSnapshot(previous => ({ scope, rows: { ...(previous.scope === scope ? previous.rows : {}), [id]: value } }));
      }
    };
    // Stop scheduling on navigation/background; an already shared dashboard
    // read is not aborted out from underneath the full client detail panel.
    void Promise.all(Array.from({ length: Math.min(4, ids.length) }, worker));
    return () => { current = false; };
  }, [owner, rosterKey, scope, active, visible]);
  return snapshot.scope === scope ? snapshot.rows : {};
}
