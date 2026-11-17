import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

const auth = vi.hoisted(() => ({ callback: null as ((event: string, session: { user: { id: string } } | null) => void) | null, unsubscribe: vi.fn() }));
vi.mock("@/lib/supabase", () => ({ supabase: { auth: { onAuthStateChange: (callback: typeof auth.callback) => {
  auth.callback = callback;
  return { data: { subscription: { unsubscribe: auth.unsubscribe } } };
} } } }));
import { useChatOperationGuard } from "./useChatOperationGuard";

describe("chat operation identity", () => {
  it("invalidates switch-away-and-back even before a render", () => {
    const { result } = renderHook(() => useChatOperationGuard("alice", "thread"));
    const check = result.current();
    act(() => {
      auth.callback?.("SIGNED_IN", { user: { id: "bob" } });
      auth.callback?.("SIGNED_IN", { user: { id: "alice" } });
    });
    expect(check).toThrow("conversation changed");
  });
  it("keeps token refresh for the same user valid", () => {
    const { result } = renderHook(() => useChatOperationGuard("alice", "thread"));
    const check = result.current();
    act(() => auth.callback?.("TOKEN_REFRESHED", { user: { id: "alice" } }));
    expect(check).not.toThrow();
  });
  it("invalidates when the thread changes or unmounts", () => {
    const { result, rerender, unmount } = renderHook(({ thread }) => useChatOperationGuard("alice", thread), { initialProps: { thread: "one" } });
    const old = result.current();
    rerender({ thread: "two" });
    expect(old).toThrow("conversation changed");
    const current = result.current();
    unmount();
    expect(current).toThrow("conversation changed");
    expect(auth.unsubscribe).toHaveBeenCalled();
  });
});
