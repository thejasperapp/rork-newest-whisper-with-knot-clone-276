import { act, renderHook } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ReactNode } from "react";
import type { WhisperMessage } from "@/lib/types";

vi.mock("@/lib/supabase", () => ({ supabaseUrl: "https://example.invalid", supabaseAnonKey: "public-test" }));
vi.mock("@/hooks/useChatOperationGuard", () => ({ useChatOperationGuard: () => () => () => {} }));
vi.mock("@/lib/groupThemeSession", () => ({ groupThemeSession: async () => ({ token: "test-only", signal: new AbortController().signal, check: () => {}, dispose: () => {} }) }));
vi.mock("@/lib/groupChats", () => ({ parseGroupWire: () => ({ groupId: "20000000-0000-4000-8000-000000000001" }) }));
import { useGroupReadReceipts } from "./useGroupReadReceipts";

const id = "30000000-0000-4000-8000-000000000001";
const account = "10000000-0000-4000-8000-000000000001";
const group = "20000000-0000-4000-8000-000000000001";
const rows: WhisperMessage[] = [{ id, from_user_id: "sender", to_user_id: account, from_username: "Sender", to_username: "Reader", created_at: "2026-09-26T12:00:00Z", read_at: null, body: "group fixture" }];
let callback: IntersectionObserverCallback;
let host: HTMLDivElement;
let node: HTMLDivElement;
let client: QueryClient;
const entry = (ratio: number): IntersectionObserverEntry => ({ target: node, intersectionRatio: ratio, isIntersecting: ratio > 0, boundingClientRect: node.getBoundingClientRect(), intersectionRect: node.getBoundingClientRect(), rootBounds: host.getBoundingClientRect(), time: 0 });
const notify = (ratio: number): void => callback([entry(ratio)], {} as IntersectionObserver);

beforeEach(() => {
  vi.useFakeTimers();
  Object.defineProperty(document, "visibilityState", { configurable: true, value: "visible" });
  host = document.createElement("div"); node = document.createElement("div");
  node.setAttribute("data-read-ids", id); host.append(node); document.body.append(host);
  host.getBoundingClientRect = () => ({ top: 0, left: 0, bottom: 400, right: 300, height: 400, width: 300 } as DOMRect);
  node.getBoundingClientRect = () => ({ top: 20, left: 0, bottom: 120, right: 280, height: 100, width: 280 } as DOMRect);
  vi.stubGlobal("IntersectionObserver", class {
    constructor(cb: IntersectionObserverCallback) { callback = cb; }
    observe(): void {} disconnect(): void {}
  });
  vi.stubGlobal("fetch", vi.fn());
  client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  client.setQueryData(["group-wire", account], rows);
});
afterEach(() => { client.clear(); host.remove(); vi.useRealTimers(); vi.unstubAllGlobals(); });
const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;

describe("group read visibility and reconciliation", () => {
  it("does not mark clipped rows or rows that leave before the dwell", async () => {
    const { unmount } = renderHook(() => useGroupReadReceipts(account, group, rows, { current: host }), { wrapper });
    act(() => notify(0.2));
    await act(async () => { await vi.advanceTimersByTimeAsync(600); });
    expect(fetch).not.toHaveBeenCalled();
    act(() => notify(1)); act(() => notify(0));
    await act(async () => { await vi.advanceTimersByTimeAsync(600); });
    expect(fetch).not.toHaveBeenCalled(); unmount();
  });
  it("accepts a real receipt already written by another device without replaying PATCH", async () => {
    vi.mocked(fetch).mockResolvedValueOnce(new Response("[]", { status: 200 })).mockResolvedValueOnce(new Response(JSON.stringify([{ id, read_at: "2026-09-26T12:02:00Z" }]), { status: 200 }));
    const { result, unmount } = renderHook(() => useGroupReadReceipts(account, group, rows, { current: host }), { wrapper });
    act(() => notify(1));
    await act(async () => { await vi.advanceTimersByTimeAsync(700); });
    expect(fetch).toHaveBeenCalledTimes(2);
    expect(vi.mocked(fetch).mock.calls[0][1]?.method).toBe("PATCH");
    expect(vi.mocked(fetch).mock.calls[1][1]?.method).toBeUndefined();
    expect(result.current.error).toBe(false);
    expect(client.getQueryData<WhisperMessage[]>(["group-wire", account])?.[0].read_at).toBe("2026-09-26T12:02:00Z"); unmount();
  });
});
