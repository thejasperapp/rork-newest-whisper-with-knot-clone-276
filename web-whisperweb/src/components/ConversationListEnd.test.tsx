import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ConversationListEnd } from "./ConversationListEnd";
let notify: IntersectionObserverCallback | undefined;
const disconnect = vi.fn();
beforeEach(() => {
  Object.defineProperty(document, "hidden", { configurable: true, value: false });
  vi.stubGlobal("IntersectionObserver", class {
    constructor(callback: IntersectionObserverCallback) { notify = callback; }
    observe() {} disconnect = disconnect;
  });
});
afterEach(() => { cleanup(); notify = undefined; vi.unstubAllGlobals(); vi.clearAllMocks(); Object.defineProperty(document, "hidden", { configurable: true, value: false }); });
const intersect = () => notify?.([{ isIntersecting: true } as IntersectionObserverEntry], {} as IntersectionObserver);
const props = { active: true, hasMore: true, busy: false, loading: false, failed: false };

describe("automatic inbox continuation", () => {
  it("loads at the visible end even when no rows match a local filter, without an idle pagination control", async () => {
    const load = vi.fn().mockResolvedValue(undefined);
    render(<ConversationListEnd {...props} onLoad={load} />);
    expect(screen.queryByRole("button")).toBeNull();
    act(intersect);
    await waitFor(() => expect(load).toHaveBeenCalledTimes(1));
  });
  it("does not load while the inbox is hidden, a request is in progress, or paging failed", () => {
    const load = vi.fn().mockResolvedValue(undefined);
    const view = render(<ConversationListEnd {...props} active={false} onLoad={load} />);
    expect(notify).toBeUndefined();
    view.rerender(<ConversationListEnd {...props} busy onLoad={load} />);
    expect(notify).toBeUndefined();
    view.rerender(<ConversationListEnd {...props} failed onLoad={load} />);
    expect(notify).toBeUndefined();
    expect(load).not.toHaveBeenCalled();
  });
  it("pauses while backgrounded and resumes after returning", async () => {
    const load = vi.fn().mockResolvedValue(undefined);
    render(<ConversationListEnd {...props} onLoad={load} />);
    act(() => {
      Object.defineProperty(document, "hidden", { configurable: true, value: true });
      document.dispatchEvent(new Event("visibilitychange"));
    });
    act(intersect);
    expect(load).not.toHaveBeenCalled();
    expect(disconnect).toHaveBeenCalled();
    act(() => {
      Object.defineProperty(document, "hidden", { configurable: true, value: false });
      document.dispatchEvent(new Event("visibilitychange"));
    });
    act(intersect);
    await waitFor(() => expect(load).toHaveBeenCalledTimes(1));
  });
  it("shows accessible progress and disables retry during its request", () => {
    const load = vi.fn().mockResolvedValue(undefined);
    const view = render(<ConversationListEnd {...props} failed busy loading onLoad={load} />);
    expect(screen.getByRole("status", { name: "Loading conversations" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Try again" })).toBeDisabled();
    view.rerender(<ConversationListEnd {...props} failed onLoad={load} />);
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(load).toHaveBeenCalledTimes(1);
  });
});
