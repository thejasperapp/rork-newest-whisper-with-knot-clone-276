import { useEffect, useRef, type RefObject } from "react";
import { useMutation, useQueryClient, type InfiniteData } from "@tanstack/react-query";
import { invalidateHistorySnapshot } from "@/lib/conversationHistory";
import type { MessageCursor, MessagePage } from "@/lib/messageHistory";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { groupThemeSession } from "@/lib/groupThemeSession";
import { supabaseUrl, supabaseAnonKey } from "@/lib/supabase";
import { parseGroupWire } from "@/lib/groupChats";
import type { WhisperMessage } from "@/lib/types";

/** Marks only visible, inbound rows in this exact group. No roster-wide inferred receipts. */
export function useGroupReadReceipts(accountID: string, groupID: string, rows: WhisperMessage[], root: RefObject<HTMLDivElement>, active = true) {
  const activeRef = useRef(active); activeRef.current = active;
  useEffect(() => { if (!active) work.current?.abort(); }, [active]);
  const cache = useQueryClient();
  const capture = useChatOperationGuard(accountID, groupID);
  const acknowledged = useRef<Set<string>>(new Set());
  const pending = useRef<Set<string>>(new Set());
  const work = useRef<AbortController | null>(null);
  const write = useMutation({ mutationFn: async (ids: string[]) => {
    const check = capture();
    const session = await groupThemeSession(accountID);
    const controller = new AbortController(); work.current = controller;
    const abort = (): void => controller.abort();
    session.signal.addEventListener("abort", abort);
    const timeout = window.setTimeout(abort, 20_000);
    try {
      check(); session.check();
      if (controller.signal.aborted || !activeRef.current || document.visibilityState !== "visible") throw new Error("Read update paused.");
      const url = new URL(`${supabaseUrl}/rest/v1/whisper_messages`);
      url.searchParams.set("id", `in.(${ids.join(",")})`);
      url.searchParams.set("to_user_id", `eq.${accountID}`);
      url.searchParams.set("body", `ilike.::wg-v1::${groupID.toLowerCase()}::*`);
      url.searchParams.set("read_at", "is.null");
      url.searchParams.set("select", "id,read_at");
      const result = await fetch(url, { method: "PATCH", signal: controller.signal, headers: { apikey: supabaseAnonKey, Authorization: `Bearer ${session.token}`, "Content-Type": "application/json", Prefer: "return=representation" }, body: JSON.stringify({ read_at: new Date().toISOString() }) });
      check(); session.check();
      if (!result.ok) throw new Error("Couldn't update read status.");
      const returned: unknown = await result.json();
      if (!Array.isArray(returned)) throw new Error("Couldn't confirm read status.");
      const receipts = new Map<string, string>();
      for (const row of returned) {
        if (row && typeof row.id === "string" && ids.includes(row.id) && typeof row.read_at === "string" && Number.isFinite(Date.parse(row.read_at))) receipts.set(row.id, row.read_at);
      }
      check();
      if (controller.signal.aborted) return;
      if (receipts.size !== ids.length) {
        // A second device may have marked these rows first. Reconcile, never invent receipts.
        url.searchParams.set("read_at", "not.is.null");
        const fresh = await fetch(url, { signal: controller.signal, cache: "no-store", headers: { apikey: supabaseAnonKey, Authorization: `Bearer ${session.token}` } });
        check(); session.check();
        if (!fresh.ok) throw new Error("Couldn't confirm read status.");
        const known: unknown = await fresh.json();
        if (Array.isArray(known)) for (const row of known) {
          if (row && typeof row.id === "string" && ids.includes(row.id) && typeof row.read_at === "string" && Number.isFinite(Date.parse(row.read_at))) receipts.set(row.id, row.read_at);
        }
        check();
        if (controller.signal.aborted) return;
        if (receipts.size !== ids.length) { void cache.invalidateQueries({ queryKey: ["group-wire", accountID] }); throw new Error("Some messages are no longer available. Refresh to continue."); }
      }
      invalidateHistorySnapshot();
      receipts.forEach((_value, id) => acknowledged.current.add(id));
      void cache.invalidateQueries({ queryKey: ["group-wire", accountID, "summaries"], exact: true });
      cache.setQueryData<InfiniteData<MessagePage, MessageCursor | null>>(["group-wire", accountID, "history", groupID.toLowerCase()], old => old ? {
        ...old, pages: old.pages.map(page => ({ ...page, messages: page.messages.map(row => receipts.has(row.id) ? { ...row, read_at: receipts.get(row.id)! } : row) })),
      } : old);
      cache.setQueryData<WhisperMessage[]>(["group-wire", accountID], old => old?.map(row => receipts.has(row.id) ? { ...row, read_at: receipts.get(row.id)! } : row));
    } finally { clearTimeout(timeout); session.dispose(); session.signal.removeEventListener("abort", abort); if (work.current === controller) work.current = null; ids.forEach(id => pending.current.delete(id)); }
  }, retry: false, onSettled: (_data, _error, ids) => { ids.forEach(id => pending.current.delete(id)); } });
  const mutate = write.mutate;
  useEffect(() => {
    const host = root.current;
    if (!active || !host || write.isPending || write.isError) return;
    const allowed = new Set(rows.filter(row => row.to_user_id.toLowerCase() === accountID.toLowerCase() && !row.read_at && parseGroupWire(row.body)?.groupId === groupID.toLowerCase() && /^[0-9a-f-]{36}$/i.test(row.id)).map(row => row.id));
    const batch = new Map<Element, string[]>();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const observer = new IntersectionObserver(entries => {
      if (!activeRef.current || document.visibilityState !== "visible") return;
      for (const entry of entries) {
        if (!entry.isIntersecting || entry.intersectionRatio < 0.5) { batch.delete(entry.target); continue; }
        const ids = (entry.target.getAttribute("data-read-ids") ?? "").split(",").filter(id => allowed.has(id) && !acknowledged.current.has(id) && !pending.current.has(id));
        if (ids.length) batch.set(entry.target, ids);
      }
      if (batch.size && !timer) timer = setTimeout(() => {
        timer = undefined;
        if (!activeRef.current || document.visibilityState !== "visible") return;
        const dialogs = document.querySelectorAll('[role="dialog"][data-state="open"]');
        const topDialog = dialogs.item(dialogs.length - 1);
        if (topDialog && !topDialog.contains(host)) { batch.clear(); return; }
        const viewport = host.getBoundingClientRect();
        const ids = [...batch].filter(([node]) => {
          const rect = node.getBoundingClientRect();
          const height = Math.max(0, Math.min(rect.bottom, viewport.bottom, window.innerHeight) - Math.max(rect.top, viewport.top, 0));
          const width = Math.max(0, Math.min(rect.right, viewport.right, window.innerWidth) - Math.max(rect.left, viewport.left, 0));
          return node.isConnected && rect.width * rect.height > 0 && height * width / (rect.width * rect.height) >= 0.5;
        }).flatMap(([, values]) => values).slice(0, 100); batch.clear();
        ids.forEach(id => pending.current.add(id));
        if (ids.length) mutate(ids);
      }, 500);
    }, { root: host, threshold: 0.5 });
    const observe = (): void => {
      observer.disconnect();
      if (document.visibilityState === "visible") host.querySelectorAll("[data-read-ids]").forEach(node => observer.observe(node));
      else { work.current?.abort(); batch.clear(); }
    };
    observe(); document.addEventListener("visibilitychange", observe);
    return () => { observer.disconnect(); clearTimeout(timer); document.removeEventListener("visibilitychange", observe); };
  }, [accountID, groupID, rows, root, mutate, write.isPending, write.isError, active]);
  useEffect(() => {
    const confirmedIDs = acknowledged.current;
    const pendingIDs = pending.current;
    const visibility = (): void => { if (document.visibilityState !== "visible") work.current?.abort(); };
    document.addEventListener("visibilitychange", visibility);
    return () => { work.current?.abort(); confirmedIDs.clear(); pendingIDs.clear(); document.removeEventListener("visibilitychange", visibility); };
  }, [accountID, groupID]);
  return { error: write.isError, retry: write.reset };
}
